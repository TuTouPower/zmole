import Combine
import Foundation

@MainActor
final class DiskMeasurementSession: ObservableObject {
    struct Config: Sendable {
        var maxResidentEntries: Int
        var maxStorageBytes: Int64
        var batchLimit: Int

        init(maxResidentEntries: Int = 4000, maxStorageBytes: Int64 = 100 * 1024 * 1024, batchLimit: Int = 100) {
            self.maxResidentEntries = max(1, maxResidentEntries)
            self.maxStorageBytes = maxStorageBytes
            self.batchLimit = max(1, min(batchLimit, self.maxResidentEntries))
        }
    }

    struct LevelRecord: Equatable, Sendable {
        let path: String
        var entries: [DiskEntry]
        var totalSize: Int64
        var selfDeduplicatedSize: Int64
        let filesTotal: Int64
        let generation: Int
        let isReadable: Bool
    }
    typealias LevelSummary = DiskLevelSummary

    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?
    let scanner: DiskScanning
    let rootPath: String
    let config: Config
    let store: DiskSessionStore
    private(set) var sessionGeneration = 0
    let scheduler: HeavyScanScheduler
    private var childCache: [String: [DiskEntry]] = [:]
    private var residentPaths: [String] = []
    private var listingCount = 0
    private var isClosed = false
    private var userVisible = false
    private var invalidatedPaths: Set<String> = []
    private var freshPaths: Set<String> = []

    private struct Request {
        let id: UUID
        let path: String
        let generation: Int
        var consumers: Set<UUID>
        var retainedByBrowser: Bool
    }
    private struct Running {
        var request: Request
        let task: Task<Void, Never>
    }
    private var retiring: Set<UUID> = []
    private var pending: [Request] = []
    private var running: [String: Running] = [:]

    var residentEntriesCount: Int { childCache.values.reduce(0) { $0 + $1.count } }

    init(scanner: DiskScanning, root: String = "/", config: Config = Config(), store: DiskSessionStore? = nil, scheduler: HeavyScanScheduler? = nil) {
        self.scanner = scanner
        rootPath = root
        self.config = config
        var initializationError: String?
        if let store { self.store = store }
        else {
            do { self.store = try DiskSessionStore(maxStorageBytes: config.maxStorageBytes) }
            catch {
                self.store = DiskSessionStore.unavailable(error)
                initializationError = error.localizedDescription
            }
        }
        self.scheduler = scheduler ?? HeavyScanScheduler()
        errorMessage = initializationError
    }

    func close() {
        isClosed = true
        cancel()
        store.close()
    }

    func levelRecord(for path: String) -> LevelRecord? {
        guard let summary = store.loadSummary(for: path) else { return nil }
        let entries = cachedEntries(for: path) ?? []
        return LevelRecord(path: path, entries: entries, totalSize: summary.totalSize, selfDeduplicatedSize: summary.selfDeduplicatedSize, filesTotal: 0, generation: sessionGeneration, isReadable: summary.isReadable)
    }

    func levelSummary(for path: String) -> LevelSummary? { store.loadSummary(for: path) }

    func cachedEntries(for path: String) -> [DiskEntry]? {
        if let entries = childCache[path] { return entries }
        guard store.loadSummary(for: path) != nil,
              let entries = try? store.loadEntries(parentPath: path, limit: min(config.batchLimit, config.maxResidentEntries), sort: nil) else { return nil }
        while residentEntriesCount + entries.count > config.maxResidentEntries, let oldest = residentPaths.first {
            residentPaths.removeFirst()
            childCache.removeValue(forKey: oldest)
        }
        childCache[path] = entries
        residentPaths.append(path)
        return entries
    }

    func directChildren(for path: String) async throws -> [DiskEntry] {
        if let entries = cachedEntries(for: path) { return entries }
        return try await listDirectory(path)
    }

    func pagedEntries(path: String, offset: Int = 0, limit: Int = 100, search: String = "", sort: AnalyzeSort = .name) throws -> [DiskEntry] {
        try store.loadEntries(parentPath: path, offset: offset, limit: limit, search: search, sort: sort)
    }

    func streamDirectoryEntries(path: String, batchLimit: Int? = nil) -> AsyncThrowingStream<[DiskEntry], Error> {
        let limit = max(1, min(batchLimit ?? config.batchLimit, config.maxResidentEntries))
        let store = self.store
        // Unfolding produces a batch only when the consumer requests next().
        // No producer Task or unbounded AsyncStream buffer.
        let cursor = DiskPageCursor(store: store, path: path, limit: limit)
        return AsyncThrowingStream(unfolding: { try await cursor.next() })
    }

    func subtreeTotal(for path: String) -> Int64? { store.loadSummary(for: path)?.totalSize }
    func selfDeduplicatedSize(for path: String) -> Int64? { store.loadSummary(for: path)?.selfDeduplicatedSize }
    func isSubtreeReadable(for path: String) -> Bool { store.loadSummary(for: path)?.isReadable ?? false }

    func measureSubtreeOutcome(_ path: String) async -> (size: Int64?, isReadable: Bool) {
        var subscription: SessionSubscription?
        if store.loadSummary(for: path) == nil || !isFresh(path) { subscription = subscribe(path: path) }
        defer { subscription?.cancel() }
        while !Task.isCancelled, !isClosed {
            if isFresh(path), store.isComplete(path), let summary = store.loadSummary(for: path) {
                return (summary.totalSize, summary.isReadable)
            }
            if !isScanning { return (nil, false) }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return (nil, false)
    }

    func listDirectory(_ path: String) async throws -> [DiskEntry] {
        guard !isClosed else { throw DiskSessionStoreError.closed }
        let generation = sessionGeneration
        listingCount += 1
        updateScanningState()
        defer { listingCount -= 1; updateScanningState() }
        let staging = try store.makeStagingStore()
        defer { staging.close() }
        try await scanner.listDirectory(path, into: staging, batchLimit: config.batchLimit)
        try Task.checkCancellation()
        guard generation == sessionGeneration else { throw CancellationError() }
        try store.promote(staging, path: path)
        invalidateResidentCache()
        errorMessage = nil
        try store.enqueueBrowserChildren(of: path, generation: generation)
        pump()
        objectWillChange.send()
        return cachedEntries(for: path) ?? []
    }

    final class SessionSubscription: Sendable {
        private let onCancel: @Sendable () -> Void
        init(onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }
        func cancel() { onCancel() }
    }

    func subscribe(path: String) -> SessionSubscription {
        let id = UUID()
        addRequest(path: path, consumer: id, retained: false)
        return SessionSubscription { [weak self] in
            Task { @MainActor in self?.removeConsumer(id, for: path) }
        }
    }

    func enqueueMeasurement(path: String, parent: String?) {
        addRequest(path: path, consumer: nil, retained: true)
    }

    private func covers(_ ancestor: String, _ path: String) -> Bool {
        path == ancestor || path.hasPrefix(LiveDiskScanner.directoryPrefix(ancestor))
    }

    private func addRequest(path: String, consumer: UUID?, retained: Bool) {
        guard !isClosed else { return }
        if let key = running.keys.first(where: { covers($0, path) && running[$0]?.task.isCancelled == false }) {
            if let consumer { running[key]?.request.consumers.insert(consumer) }
            if retained { running[key]?.request.retainedByBrowser = true }
        } else if let index = pending.firstIndex(where: { covers($0.path, path) }) {
            if let consumer { pending[index].consumers.insert(consumer) }
            if retained { pending[index].retainedByBrowser = true }
        } else {
            pending.append(Request(id: UUID(), path: path, generation: sessionGeneration, consumers: consumer.map { [$0] } ?? [], retainedByBrowser: retained))
        }
        pump()
    }

    func removeConsumer(_ id: UUID, for path: String) {
        for index in pending.indices { pending[index].consumers.remove(id) }
        pending.removeAll { $0.consumers.isEmpty && !$0.retainedByBrowser }
        for key in Array(running.keys) {
            running[key]?.request.consumers.remove(id)
            if let run = running[key], run.request.consumers.isEmpty && !run.request.retainedByBrowser { run.task.cancel() }
        }
        updateScanningState()
    }

    func setUserVisible(_ visible: Bool) {
        userVisible = visible
        for path in running.keys {
            Task { [scheduler] in
                if visible { await scheduler.elevate(taskID: "disk:\(path)") }
                else { await scheduler.demote(taskID: "disk:\(path)") }
            }
        }
    }

    private func pump() {
        guard !isClosed else { updateScanningState(); return }
        while running.count < scheduler.maxConcurrency {
            let request: Request
            if let index = pending.firstIndex(where: { running[$0.path] == nil }) {
                request = pending.remove(at: index)
            } else {
                do {
                    guard let path = try store.takeBrowserRequest(generation: sessionGeneration) else { break }
                    if running.keys.contains(where: { covers($0, path) }) { continue }
                    request = Request(id: UUID(), path: path, generation: sessionGeneration, consumers: [], retainedByBrowser: true)
                } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.execute(request)
            }
            running[request.path] = Running(request: request, task: task)
        }
        updateScanningState()
    }

    private func execute(_ request: Request) async {
        var permit: HeavyScanPermit?
        do {
            permit = try await scheduler.acquire(taskID: "disk:\(request.path)", priority: userVisible ? .userVisible : .background)
            try Task.checkCancellation()
            let staging = try store.makeStagingStore()
            defer { staging.close() }
            try await scanner.measureSubtree(request.path, into: staging, batchLimit: config.batchLimit)
            try Task.checkCancellation()
            await permit?.release()
            permit = nil
            if request.generation == sessionGeneration, !isClosed {
                try store.promote(staging, path: request.path)
                freshPaths.insert(request.path)
                invalidateResidentCache()
                errorMessage = nil
            }
        } catch is CancellationError {
        } catch {
            if request.generation == sessionGeneration { errorMessage = error.localizedDescription }
        }
        if let permit { await permit.release() }
        retiring.remove(request.id)
        if running[request.path]?.request.id == request.id { running.removeValue(forKey: request.path) }
        pump()
        objectWillChange.send()
    }

    /// Invalidates the complete measurement generation before a fresh estimate.
    /// Existing browser lists are re-listed on their next request.
    func invalidateMeasurements() { reanalyze(path: rootPath) }

    func reanalyze(path: String) {
        cancelWorkers()
        invalidatedPaths.insert(path)
        freshPaths = freshPaths.filter { !covers(path, $0) && !covers($0, path) }
        invalidateResidentCache()
        errorMessage = nil
        updateScanningState()
        objectWillChange.send()
    }

    private func isFresh(_ path: String) -> Bool {
        if freshPaths.contains(where: { covers($0, path) }) { return true }
        return !invalidatedPaths.contains { covers($0, path) || covers(path, $0) }
    }

    func cancel() {
        cancelWorkers()
        store.clearSubtree(path: rootPath)
        invalidateResidentCache()
        updateScanningState()
        objectWillChange.send()
    }

    private func cancelWorkers() {
        sessionGeneration += 1
        for run in running.values {
            retiring.insert(run.request.id)
            run.task.cancel()
        }
        running.removeAll()
        pending.removeAll()
        store.clearBrowserRequests()
    }

    private func invalidateResidentCache() {
        childCache.removeAll()
        residentPaths.removeAll()
    }

    private func updateScanningState() {
        isScanning = listingCount > 0 || !running.isEmpty || !pending.isEmpty || !retiring.isEmpty || store.hasBrowserRequests(generation: sessionGeneration)
    }
}

private actor DiskPageCursor {
    let store: DiskSessionStore
    let path: String
    let limit: Int
    var offset = 0

    init(store: DiskSessionStore, path: String, limit: Int) {
        self.store = store
        self.path = path
        self.limit = limit
    }

    func next() throws -> [DiskEntry]? {
        try Task.checkCancellation()
        let page = try store.loadEntries(parentPath: path, offset: offset, limit: limit)
        guard !page.isEmpty else { return nil }
        offset += page.count
        return page
    }
}
