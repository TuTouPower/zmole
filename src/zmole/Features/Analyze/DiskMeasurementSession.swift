import Combine
import Foundation

/// Central session service that owns measurement queue, in-flight background
/// walks, scan generation, and deterministic statistical contexts.
@MainActor
final class DiskMeasurementSession: ObservableObject {
    struct Config: Sendable {
        var maxResidentEntries: Int = 4000
        var maxStorageBytes: Int64 = 100 * 1024 * 1024
        var batchLimit: Int = 100

        init(
            maxResidentEntries: Int = 4000,
            maxStorageBytes: Int64 = 100 * 1024 * 1024,
            batchLimit: Int = 100
        ) {
            self.maxResidentEntries = maxResidentEntries
            self.maxStorageBytes = maxStorageBytes
            self.batchLimit = batchLimit
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

    @Published private(set) var isScanning: Bool = false

    let scanner: DiskScanning
    let rootPath: String
    let config: Config
    let store: DiskSessionStore

    private(set) var sessionGeneration: Int = 0
    private var records: [String: LevelRecord] = [:]
    private var childCache: [String: [DiskEntry]] = [:]
    private var residentPaths: [String] = []

    var residentEntriesCount: Int {
        childCache.values.reduce(0) { $0 + $1.count }
    }

    /// Retained facts per directory subtree across walks in this session.
    private struct SubtreeFacts: Sendable {
        let selfSize: Int64
        let nonLinkedTotal: Int64
        let inodes: [HardLinkKey: Int64]
        let isReadable: Bool
    }
    private var subtreeFactsMap: [String: SubtreeFacts] = [:]

    private struct QueueItem: Sendable {
        let path: String
        let parent: String?
        let generation: Int
        var subscribers: Set<String>
        var consumers: Set<UUID>
    }

    private struct InFlightState {
        let generation: Int
        var subscribers: Set<String>
        var consumers: Set<UUID>
        var cancelAction: (@Sendable () -> Void)?
    }

    private var pendingQueue: [QueueItem] = []
    private var inFlightTasks: [String: InFlightState] = [:]
    private var workerTask: Task<Void, Never>?
    private var workerToken: Int = 0
    private var isListing: Bool = false
    private let scheduler: HeavyScanScheduler

    init(
        scanner: DiskScanning,
        root: String = "/",
        config: Config = Config(),
        store: DiskSessionStore? = nil,
        scheduler: HeavyScanScheduler? = nil
    ) {
        self.scanner = scanner
        self.rootPath = root
        self.config = config
        self.store = store ?? (try? DiskSessionStore(maxStorageBytes: config.maxStorageBytes)) ?? (try! DiskSessionStore(maxStorageBytes: 100 * 1024 * 1024))
        self.scheduler = scheduler ?? HeavyScanScheduler()
    }

    func close() {
        cancel()
        store.close()
    }

    // MARK: - Query APIs

    func levelRecord(for path: String) -> LevelRecord? {
        if let rec = records[path] { return rec }
        if let summary = store.loadSummary(for: path) {
            return LevelRecord(
                path: path,
                entries: (try? store.loadEntries(parentPath: path, limit: 100)) ?? [],
                totalSize: summary.totalSize,
                selfDeduplicatedSize: summary.selfDeduplicatedSize,
                filesTotal: 0,
                generation: sessionGeneration,
                isReadable: summary.isReadable
            )
        }
        return nil
    }

    func cachedEntries(for path: String) -> [DiskEntry]? {
        if let cached = childCache[path] {
            touchResident(path)
            return cached
        }
        if let entries = try? store.loadEntries(parentPath: path, limit: config.maxResidentEntries), !entries.isEmpty {
            storeResident(path: path, entries: entries)
            return entries
        }
        return nil
    }

    func levelSummary(for path: String) -> LevelSummary? {
        if let record = records[path] {
            let directFiles = record.entries.filter { !$0.isDirectory }.count
            let directDirs = record.entries.filter { $0.isDirectory }.count
            return LevelSummary(
                path: path,
                totalSize: record.totalSize,
                selfDeduplicatedSize: record.selfDeduplicatedSize,
                isReadable: record.isReadable,
                directFilesCount: directFiles,
                directDirectoriesCount: directDirs
            )
        }
        if let summary = store.loadSummary(for: path) {
            return LevelSummary(
                path: path,
                totalSize: summary.totalSize,
                selfDeduplicatedSize: summary.selfDeduplicatedSize,
                isReadable: summary.isReadable,
                directFilesCount: summary.directFilesCount,
                directDirectoriesCount: summary.directDirectoriesCount
            )
        }
        return nil
    }

    func directChildren(for path: String) async throws -> [DiskEntry] {
        if let cached = cachedEntries(for: path) {
            return cached
        }
        return try await listDirectory(path)
    }

    func pagedEntries(
        path: String,
        offset: Int = 0,
        limit: Int = 100,
        search: String = "",
        sort: AnalyzeSort = .name
    ) throws -> [DiskEntry] {
        try store.loadEntries(
            parentPath: path,
            offset: offset,
            limit: limit,
            search: search,
            sort: sort
        )
    }

    func streamDirectoryEntries(
        path: String,
        batchLimit: Int? = nil
    ) -> AsyncThrowingStream<[DiskEntry], Error> {
        let limit = batchLimit ?? config.batchLimit
        let store = self.store
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let total = store.countEntries(parentPath: path)
                    var offset = 0
                    while offset < total {
                        if Task.isCancelled { break }
                        let batch = try store.loadEntries(
                            parentPath: path,
                            offset: offset,
                            limit: limit,
                            search: "",
                            sort: .name
                        )
                        continuation.yield(batch)
                        offset += batch.count
                        if batch.isEmpty { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func touchResident(_ path: String) {
        if let idx = residentPaths.firstIndex(of: path) {
            residentPaths.remove(at: idx)
        }
        residentPaths.append(path)
    }

    private func storeResident(path: String, entries: [DiskEntry]) {
        childCache[path] = entries
        touchResident(path)
        enforceResidentBudget()
    }

    private func enforceResidentBudget() {
        while residentEntriesCount > config.maxResidentEntries && residentPaths.count > 1 {
            let oldest = residentPaths.removeFirst()
            childCache.removeValue(forKey: oldest)
        }
    }

    func subtreeTotal(for path: String) -> Int64? {
        records[path]?.totalSize ?? subtreeFactsMap[path]?.selfSize
    }

    func selfDeduplicatedSize(for path: String) -> Int64? {
        records[path]?.selfDeduplicatedSize ?? subtreeFactsMap[path]?.selfSize
    }

    func isSubtreeReadable(for path: String) -> Bool {
        records[path]?.isReadable ?? subtreeFactsMap[path]?.isReadable ?? true
    }

    func measureSubtreeOutcome(_ path: String) async -> (size: Int64?, isReadable: Bool) {
        if let rec = records[path] {
            return (rec.totalSize, rec.isReadable)
        }
        if let facts = subtreeFactsMap[path] {
            return (facts.selfSize, facts.isReadable)
        }
        let sub = subscribe(path: path)
        defer { sub.cancel() }

        while !Task.isCancelled {
            if let rec = records[path] {
                return (rec.totalSize, rec.isReadable)
            }
            if let facts = subtreeFactsMap[path] {
                return (facts.selfSize, facts.isReadable)
            }
            if !isScanning && inFlightTasks[path] == nil && !pendingQueue.contains(where: { $0.path == path }) {
                let rec = records[path]
                return (rec?.totalSize ?? subtreeFactsMap[path]?.selfSize, rec?.isReadable ?? subtreeFactsMap[path]?.isReadable ?? false)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return (records[path]?.totalSize ?? subtreeFactsMap[path]?.selfSize, records[path]?.isReadable ?? subtreeFactsMap[path]?.isReadable ?? false)
    }

    // MARK: - Directory Listing

    func listDirectory(_ path: String) async throws -> [DiskEntry] {
        isListing = true
        updateScanningState()
        defer {
            isListing = false
            updateScanningState()
        }

        let entries = try await scanner.listDirectory(path)
        let generation = sessionGeneration

        var claimed: Set<HardLinkKey> = []
        var filesTotal: Int64 = 0
        for entry in entries where !entry.isDirectory {
            guard let size = entry.knownSize else { continue }
            if let key = entry.linkKey {
                if claimed.insert(key).inserted {
                    filesTotal += size
                }
            } else {
                filesTotal += size
            }
        }

        // Incorporate any already measured or retained child sizes
        var resolvedEntries: [DiskEntry] = []
        for var entry in entries {
            if entry.isDirectory {
                if let facts = subtreeFactsMap[entry.path] {
                    if facts.isReadable {
                        entry.value = .size(facts.selfSize)
                        entry.selfDeduplicatedSize = facts.selfSize
                        entry.parentContribution = facts.selfSize
                    } else {
                        entry.value = .unreadable
                    }
                } else if let existing = records[entry.path], existing.generation == generation {
                    if existing.isReadable {
                        entry.value = .size(existing.totalSize)
                        entry.selfDeduplicatedSize = existing.selfDeduplicatedSize
                        entry.parentContribution = existing.totalSize
                    } else {
                        entry.value = .unreadable
                    }
                }
            }
            resolvedEntries.append(entry)
        }

        var initialTotal = filesTotal
        for entry in resolvedEntries where entry.isDirectory {
            if let size = entry.knownSize {
                initialTotal += size
            }
        }

        let record = LevelRecord(
            path: path,
            entries: resolvedEntries,
            totalSize: initialTotal,
            selfDeduplicatedSize: initialTotal,
            filesTotal: filesTotal,
            generation: generation,
            isReadable: true
        )
        records[path] = record
        let summary = DiskLevelSummary(
            path: path,
            totalSize: initialTotal,
            selfDeduplicatedSize: initialTotal,
            isReadable: true,
            directFilesCount: filesTotal > 0 ? 1 : 0,
            directDirectoriesCount: resolvedEntries.filter { $0.isDirectory }.count
        )
        try? store.saveLevel(summary: summary, entries: resolvedEntries, inodes: [:])
        storeResident(path: path, entries: resolvedEntries)
        objectWillChange.send()

        // Enqueue measurements for computing subdirectories
        for entry in resolvedEntries where entry.isDirectory && entry.value == .computing {
            enqueueMeasurement(path: entry.path, parent: path)
        }

        return resolvedEntries
    }

    // MARK: - Measurement Queue & Subscriptions

    final class SessionSubscription: Sendable {
        private let onCancel: @Sendable () -> Void
        init(onCancel: @escaping @Sendable () -> Void) {
            self.onCancel = onCancel
        }
        func cancel() {
            onCancel()
        }
    }

    func subscribe(path: String) -> SessionSubscription {
        let consumerId = UUID()
        let generation = sessionGeneration

        if let coveringKey = findCoveringInFlight(path) {
            inFlightTasks[coveringKey]?.subscribers.insert(path)
            inFlightTasks[coveringKey]?.consumers.insert(consumerId)
        } else if let index = pendingQueue.firstIndex(where: { $0.path == path || path.hasPrefix(LiveDiskScanner.directoryPrefix($0.path)) }) {
            pendingQueue[index].subscribers.insert(path)
            pendingQueue[index].consumers.insert(consumerId)
        } else {
            let item = QueueItem(
                path: path,
                parent: nil,
                generation: generation,
                subscribers: [path],
                consumers: [consumerId]
            )
            pendingQueue.append(item)
            startWorkerIfNeeded()
        }

        updateScanningState()

        return SessionSubscription { [weak self] in
            Task { @MainActor [weak self] in
                self?.removeConsumer(consumerId, for: path)
            }
        }
    }

    func enqueueMeasurement(path: String, parent: String?) {
        let generation = sessionGeneration

        // AC-004: If path is covered by an in-flight ancestor walk, subscribe to it
        if let coveringKey = findCoveringInFlight(path) {
            inFlightTasks[coveringKey]?.subscribers.insert(path)
            if let parent {
                inFlightTasks[coveringKey]?.subscribers.insert(parent)
            }
            return
        }

        // If path is already queued or covered by a queued ancestor:
        if let index = pendingQueue.firstIndex(where: { $0.path == path || path.hasPrefix(LiveDiskScanner.directoryPrefix($0.path)) }) {
            pendingQueue[index].subscribers.insert(path)
            if let parent {
                pendingQueue[index].subscribers.insert(parent)
            }
            return
        }

        let item = QueueItem(
            path: path,
            parent: parent,
            generation: generation,
            subscribers: parent != nil ? [path, parent!] : [path],
            consumers: []
        )
        pendingQueue.append(item)
        startWorkerIfNeeded()
    }

    func removeConsumer(_ consumerId: UUID, for path: String) {
        for i in 0..<pendingQueue.count {
            pendingQueue[i].consumers.remove(consumerId)
        }
        pendingQueue.removeAll { $0.consumers.isEmpty && $0.subscribers.isEmpty }

        for (key, state) in inFlightTasks {
            var updated = state
            updated.consumers.remove(consumerId)
            updated.subscribers.remove(path)
            if updated.consumers.isEmpty && updated.subscribers.isEmpty {
                state.cancelAction?()
                inFlightTasks.removeValue(forKey: key)
            } else {
                inFlightTasks[key] = updated
            }
        }

        updateScanningState()
    }

    // MARK: - Worker Execution Loop

    private func startWorkerIfNeeded() {
        guard !pendingQueue.isEmpty, workerTask == nil else { return }
        workerToken += 1
        let token = workerToken
        workerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runQueueLoop(token: token)
            if self.workerToken == token {
                self.workerTask = nil
                // AC-002: Check if any items were added while waiting for group to finish
                if !self.pendingQueue.isEmpty && !Task.isCancelled {
                    self.startWorkerIfNeeded()
                }
            }
            self.updateScanningState()
        }
        updateScanningState()
    }

    private func runQueueLoop(token: Int) async {
        await withTaskGroup(of: (String, DiskScanResult, Int).self) { group in
            var inFlight = 0
            let maxConcurrent = self.scheduler.maxConcurrency

            while !Task.isCancelled && self.workerToken == token {
                if inFlight < maxConcurrent, let nextItem = self.dequeueNext() {
                    let path = nextItem.path
                    let gen = nextItem.generation
                    let scanner = self.scanner
                    let sched = self.scheduler

                    inFlight += 1
                    var inFlightTask: Task<DiskScanResult, Never>?
                    let cancelAction: @Sendable () -> Void = {
                        inFlightTask?.cancel()
                    }

                    self.inFlightTasks[path] = InFlightState(
                        generation: gen,
                        subscribers: nextItem.subscribers,
                        consumers: nextItem.consumers,
                        cancelAction: cancelAction
                    )

                    group.addTask {
                        let permit = try? await sched.acquire(taskID: "disk:\(path)", priority: .userVisible)
                        defer {
                            if let permit {
                                Task { await permit.release() }
                            }
                        }
                        let measureTask = Task {
                            await scanner.measureSubtree(path, deduplicator: HardLinkDeduplicator())
                        }
                        inFlightTask = measureTask
                        let result = await measureTask.value
                        return (path, result, gen)
                    }
                } else if inFlight > 0 {
                    if let (path, result, gen) = await group.next() {
                        inFlight -= 1
                        if self.workerToken == token {
                            self.inFlightTasks.removeValue(forKey: path)
                            self.applyScanResult(path: path, result: result, generation: gen)
                        }
                    }
                } else {
                    break
                }
            }

            while inFlight > 0 {
                _ = await group.next()
                inFlight -= 1
            }
        }
    }

    private func dequeueNext() -> QueueItem? {
        for i in 0..<pendingQueue.count {
            let item = pendingQueue[i]
            if findCoveringInFlight(item.path) == nil {
                pendingQueue.remove(at: i)
                return item
            }
        }
        return nil
    }

    private func findCoveringInFlight(_ path: String) -> String? {
        for key in inFlightTasks.keys {
            if path == key || path.hasPrefix(LiveDiskScanner.directoryPrefix(key)) {
                return key
            }
        }
        return nil
    }

    // MARK: - Applying Results & Statistical Scope Separation

    private func applyScanResult(path: String, result: DiskScanResult, generation: Int) {
        guard generation == sessionGeneration else { return }

        var allLevels = result.levels
        if allLevels[path] == nil {
            allLevels[path] = DiskLevel(entries: [], totalSize: result.totalSize)
        }

        // Cache all direct child levels, updating any entries listed in the interim
        for (levelPath, level) in allLevels {
            if var existing = childCache[levelPath], !existing.isEmpty {
                for entry in level.entries {
                    if let idx = existing.firstIndex(where: { $0.path == entry.path }) {
                        if case .size = entry.value {
                            existing[idx].value = entry.value
                            existing[idx].selfDeduplicatedSize = entry.selfDeduplicatedSize ?? entry.knownSize
                            existing[idx].parentContribution = entry.parentContribution ?? entry.knownSize
                        } else if entry.value == .unreadable {
                            existing[idx].value = .unreadable
                        }
                    } else {
                        existing.append(entry)
                    }
                }
                childCache[levelPath] = existing
            } else {
                childCache[levelPath] = level.entries
            }
        }

        // Record facts for each level in allLevels into subtreeFactsMap
        for (levelPath, lvl) in allLevels {
            var nonLinked: Int64 = 0
            var inodes: [HardLinkKey: Int64] = [:]

            let prefix = LiveDiskScanner.directoryPrefix(levelPath)
            for (p, descendantLevel) in allLevels where p == levelPath || p.hasPrefix(prefix) {
                for entry in descendantLevel.entries where !entry.isDirectory {
                    guard let size = entry.knownSize else { continue }
                    if let key = entry.linkKey {
                        if inodes[key] == nil {
                            inodes[key] = size
                        }
                    } else {
                        nonLinked += size
                    }
                }
            }
            let rawSelf = nonLinked + inodes.values.reduce(0, +)
            let selfSize = result.isReadable ? (rawSelf > 0 ? rawSelf : (levelPath == path ? result.totalSize : lvl.totalSize)) : 0
            subtreeFactsMap[levelPath] = SubtreeFacts(
                selfSize: selfSize,
                nonLinkedTotal: nonLinked,
                inodes: inodes,
                isReadable: result.isReadable
            )
        }

        if subtreeFactsMap[path] == nil {
            subtreeFactsMap[path] = SubtreeFacts(
                selfSize: result.totalSize,
                nonLinkedTotal: result.totalSize,
                inodes: [:],
                isReadable: result.isReadable
            )
        }

        // Update records for all known directory levels in this session
        recalculateAllRecords(currentWalkPath: path, currentResult: result, generation: generation)

        updateScanningState()
        objectWillChange.send()
    }

    private func recalculateAllRecords(currentWalkPath: String, currentResult: DiskScanResult, generation: Int) {
        // Collect all directory paths that need records (allLevels + existing records)
        var pathsToUpdate = Set(records.keys)
        for (p, _) in currentResult.levels {
            pathsToUpdate.insert(p)
        }
        pathsToUpdate.insert(currentWalkPath)

        for dirPath in pathsToUpdate {
            guard let rawEntries = childCache[dirPath] ?? records[dirPath]?.entries ?? currentResult.levels[dirPath]?.entries else {
                continue
            }

            var claimedInodes: Set<HardLinkKey> = []
            var directFilesTotal: Int64 = 0
            for entry in rawEntries where !entry.isDirectory {
                guard let size = entry.knownSize else { continue }
                if let key = entry.linkKey {
                    if claimedInodes.insert(key).inserted {
                        directFilesTotal += size
                    }
                } else {
                    directFilesTotal += size
                }
            }

            // AC-005: Sibling hardlink attribution sorted by canonical normalized path
            let childDirs = rawEntries.filter { $0.isDirectory }.sorted { $0.path < $1.path }
            var childContribs: [String: Int64] = [:]

            for child in childDirs {
                if let facts = subtreeFactsMap[child.path] {
                    var contrib = facts.nonLinkedTotal
                    for (key, size) in facts.inodes {
                        if claimedInodes.insert(key).inserted {
                            contrib += size
                        }
                    }
                    if contrib == 0 && facts.inodes.isEmpty && facts.selfSize > 0 {
                        contrib = facts.selfSize
                    }
                    childContribs[child.path] = contrib
                } else if let known = child.knownSize, known > 0 {
                    childContribs[child.path] = known
                }
            }

            var resolvedEntries: [DiskEntry] = []
            for var entry in rawEntries {
                if entry.isDirectory {
                    let facts = subtreeFactsMap[entry.path]
                    let isChildReadable = facts?.isReadable ?? (entry.value != .unreadable)
                    let childSelf = facts?.selfSize ?? entry.knownSize
                    let childContrib = childContribs[entry.path] ?? entry.knownSize

                    if isChildReadable {
                        if let childContrib {
                            entry.value = .size(childContrib)
                            entry.parentContribution = childContrib
                            entry.selfDeduplicatedSize = childSelf
                        } else if entry.path == currentWalkPath && !currentResult.isReadable {
                            entry.value = .unreadable
                            entry.parentContribution = nil
                            entry.selfDeduplicatedSize = nil
                        }
                    } else {
                        entry.value = .unreadable
                        entry.parentContribution = nil
                        entry.selfDeduplicatedSize = nil
                    }
                }
                resolvedEntries.append(entry)
            }

            let selfSize = subtreeFactsMap[dirPath]?.selfSize ?? (directFilesTotal + childContribs.values.reduce(0, +))
            let computedTotal = directFilesTotal + childContribs.values.reduce(0, +)
            let total = computedTotal > 0 ? computedTotal : selfSize
            let isReadable = subtreeFactsMap[dirPath]?.isReadable ?? true

            records[dirPath] = LevelRecord(
                path: dirPath,
                entries: resolvedEntries,
                totalSize: isReadable ? total : 0,
                selfDeduplicatedSize: isReadable ? selfSize : 0,
                filesTotal: directFilesTotal,
                generation: generation,
                isReadable: isReadable
            )
            let summary = DiskLevelSummary(
                path: dirPath,
                totalSize: isReadable ? total : 0,
                selfDeduplicatedSize: isReadable ? selfSize : 0,
                isReadable: isReadable,
                directFilesCount: directFilesTotal > 0 ? 1 : 0,
                directDirectoriesCount: childDirs.count
            )
            try? store.saveLevel(summary: summary, entries: resolvedEntries, inodes: subtreeFactsMap[dirPath]?.inodes ?? [:])
            storeResident(path: dirPath, entries: resolvedEntries)
        }
    }

    // MARK: - Reanalyze & Cancel

    func reanalyze(path: String) {
        sessionGeneration += 1
        workerToken += 1
        workerTask?.cancel()
        workerTask = nil

        for (_, state) in inFlightTasks {
            state.cancelAction?()
        }
        inFlightTasks.removeAll()
        pendingQueue.removeAll()

        let prefix = LiveDiskScanner.directoryPrefix(path)
        records = records.filter { key, _ in key != path && !key.hasPrefix(prefix) }
        childCache = childCache.filter { key, _ in key != path && !key.hasPrefix(prefix) }
        subtreeFactsMap = subtreeFactsMap.filter { key, _ in key != path && !key.hasPrefix(prefix) }
        residentPaths.removeAll { $0 == path || $0.hasPrefix(prefix) }
        store.clearSubtree(path: path)

        updateScanningState()
        objectWillChange.send()
    }

    func cancel() {
        sessionGeneration += 1
        workerToken += 1
        workerTask?.cancel()
        workerTask = nil

        for (_, state) in inFlightTasks {
            state.cancelAction?()
        }
        inFlightTasks.removeAll()
        pendingQueue.removeAll()
        residentPaths.removeAll()
        store.clearSubtree(path: rootPath)

        updateScanningState()
        objectWillChange.send()
    }

    private func updateScanningState() {
        let scanning = isListing || workerTask != nil || !pendingQueue.isEmpty || !inFlightTasks.isEmpty
        if isScanning != scanning {
            isScanning = scanning
            objectWillChange.send()
        }
    }
}
