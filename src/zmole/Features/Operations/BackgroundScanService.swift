import Combine
import Foundation

/// One read-only background scan item. Raw values key the on-disk cache;
/// renaming a case requires a cache schema bump.
enum BackgroundScanItem: String, CaseIterable, Codable, Sendable {
    case uninstallList
    case installerList
    case clean
    case optimize
    case purge
}

enum BackgroundScanPayload: Equatable, Sendable {
    case uninstallRows([UninstallAppListing])
    case installerCandidates([InstallerCandidate])
    case cleanPreview(CleanPreviewSnapshot)
    case maintenance(String)
}

struct BackgroundScanResult: Equatable, Sendable {
    let capturedAt: Date
    let payload: BackgroundScanPayload
    let targetVersion: UInt64
    let capturedVersion: UInt64
    let isStale: Bool

    init(
        capturedAt: Date,
        payload: BackgroundScanPayload,
        targetVersion: UInt64 = 0,
        capturedVersion: UInt64 = 0,
        isStale: Bool = false
    ) {
        self.capturedAt = capturedAt
        self.payload = payload
        self.targetVersion = targetVersion
        self.capturedVersion = capturedVersion
        self.isStale = isStale || (capturedVersion < targetVersion)
    }

    func markingStale(targetVersion: UInt64) -> BackgroundScanResult {
        BackgroundScanResult(
            capturedAt: capturedAt,
            payload: payload,
            targetVersion: max(self.targetVersion, targetVersion),
            capturedVersion: capturedVersion,
            isStale: true
        )
    }
}

/// Read-only scan lanes for the background scanner. Every item gets its own
/// command lane so independent scans can run in parallel; the clean item is
/// the only one that serializes with user activity (shared clean-list.txt).
struct BackgroundScanLanes {
    let uninstallStreaming: any MoleStreaming
    let installer: InstallerInterface
    let installerProcess: any MoleProcessControlling
    let clean: any MoleProcessControlling
    let optimize: any MoleProcessControlling
    let purge: any MoleProcessControlling
}

/// What write-capable view models need from the background scanner: the latest
/// result, the live state for the page, and a way to yield an item to a
/// user-visible refresh.
@MainActor
protocol BackgroundScanProviding: AnyObject {
    var runningItems: Set<BackgroundScanItem> { get }
    var failedItems: Set<BackgroundScanItem> { get }
    /// Emits whenever results, running state or failure state changes.
    var statePublisher: AnyPublisher<Void, Never> { get }
    func result(for item: BackgroundScanItem) -> BackgroundScanResult?
    /// Starts (or reuses) the scan for one item. Used by refresh buttons and by
    /// a page that has no data yet.
    func request(_ item: BackgroundScanItem)
    /// Cancels the item's scan and resolves after its process has terminated.
    func cancelAndWait(_ item: BackgroundScanItem) async
    /// The user started their own scan of this item: cancel the background run
    /// and drop its result so the user's scan becomes authoritative.
    func userDidRescan(_ item: BackgroundScanItem)
    /// Like `userDidRescan`, but resolves after the cancelled background
    /// process has fully terminated, so the caller can safely rewrite a shared
    /// file (such as clean-list.txt) without racing a dying writer.
    func userDidRescanAndWaitForTermination(_ item: BackgroundScanItem) async
}

extension BackgroundScanProviding {
    func userDidRescanAndWaitForTermination(_ item: BackgroundScanItem) async {
        userDidRescan(item)
    }

    /// Subscribes to scan state changes and hops onto the main actor, so pages
    /// can republish and adopt without duplicating Combine plumbing.
    func observeStateChanges(_ handler: @escaping @MainActor () -> Void) -> AnyCancellable {
        statePublisher.sink { _ in
            Task { @MainActor in handler() }
        }
    }
}

/// Runs the five read-only scans in parallel, persists their results and keeps
/// them fresh. The service never executes a write command and never holds an
/// `OperationCoordinator` lease; a user clean scan or execution cancels and
/// waits for the background clean writer before touching clean-list.txt.
@MainActor
final class BackgroundScanService: ObservableObject, BackgroundScanProviding {
    /// Results older than this are rescanned by the periodic check.
    static let refreshInterval: TimeInterval = 24 * 60 * 60
    /// A failed item without any result is retried at most this often.
    static let failureRetryInterval: TimeInterval = 60 * 60

    @Published private(set) var results: [BackgroundScanItem: BackgroundScanResult]
    @Published private(set) var runningItems: Set<BackgroundScanItem> = []
    @Published private(set) var failedItems: Set<BackgroundScanItem> = []

    /// Reports whether a user-visible clean preview/execution owns the shared
    /// clean-list.txt right now; a deferred clean scan starts once it clears.
    var cleanBusyProvider: @MainActor () -> Bool = { false }

    private let lanes: BackgroundScanLanes
    private let uninstallStream: UninstallListStream
    private let cleanPreviewStore: CleanPreviewStore
    private let cache: BackgroundScanCache
    private let coordinator: OperationCoordinator
    private let accessMonitor: FullDiskAccessMonitor?
    private let periodicTick: TimeInterval
    private let nowProvider: () -> Date

    private var tasks: [BackgroundScanItem: Task<Void, Never>] = [:]
    private var lastFailureAt: [BackgroundScanItem: Date] = [:]
    private var deferredClean = false
    private var deferredInstaller = false
    private var periodicTask: Task<Void, Never>?
    private var subscriptions: [AnyCancellable] = []

    init(
        lanes: BackgroundScanLanes,
        cleanPreviewStore: CleanPreviewStore,
        cache: BackgroundScanCache,
        coordinator: OperationCoordinator,
        accessMonitor: FullDiskAccessMonitor? = nil,
        periodicTick: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.lanes = lanes
        self.uninstallStream = UninstallListStream(streaming: lanes.uninstallStreaming)
        self.cleanPreviewStore = cleanPreviewStore
        self.cache = cache
        self.coordinator = coordinator
        self.accessMonitor = accessMonitor
        self.periodicTick = periodicTick
        nowProvider = now
        results = cache.load()
        coordinator.settledOperations.sink { [weak self] _, impact in
            Task { @MainActor in await self?.applyImpact(impact) }
        }
        .store(in: &subscriptions)
        refreshIfDue()
        startPeriodicRefresh()
    }

    // MARK: - BackgroundScanProviding

    var statePublisher: AnyPublisher<Void, Never> {
        Publishers.Merge3(
            $results.map { _ in () },
            $runningItems.map { _ in () },
            $failedItems.map { _ in () }
        )
        .eraseToAnyPublisher()
    }

    func result(for item: BackgroundScanItem) -> BackgroundScanResult? {
        results[item]
    }

    func userDidRescan(_ item: BackgroundScanItem) {
        if item == .clean { deferredClean = true }
        if item == .installerList { deferredInstaller = false }
        if results.removeValue(forKey: item) != nil {
            cache.save(results)
        }
        failedItems.remove(item)
        lastFailureAt.removeValue(forKey: item)
        Task { @MainActor [weak self] in
            await self?.cancelAndWait(item)
        }
    }

    func userDidRescanAndWaitForTermination(_ item: BackgroundScanItem) async {
        // Keep clean deferred until the user's own preview/execution releases
        // the file, so a periodic tick cannot start a competing writer in the
        // gap between the cancellation and the user's lease acquisition.
        if item == .clean { deferredClean = true }
        if item == .installerList { deferredInstaller = false }
        if results.removeValue(forKey: item) != nil {
            cache.save(results)
        }
        failedItems.remove(item)
        lastFailureAt.removeValue(forKey: item)
        await cancelAndWait(item)
    }

    // MARK: - Control

    /// Starts a scan unless that item is already running. Used by the manual
    /// refresh path and by the periodic freshness check.
    func request(_ item: BackgroundScanItem) {
        guard tasks[item] == nil else { return }
        if item == .installerList, !diskAccessGranted {
            // The installer scan walks Downloads/Desktop/Documents; wait for
            // the user to grant Full Disk Access instead of raising TCC dialogs.
            deferredInstaller = true
            return
        }
        if item == .clean {
            if isCleanBusy {
                deferredClean = true
                return
            }
            // A user takeover set the deferred flag; only `noteActivityChanged`
            // may clear it, so no competing writer starts in the gap between
            // the user's cancellation and their own scan.
            if deferredClean { return }
        }
        tasks[item] = Task { @MainActor [weak self] in
            await self?.run(item)
        }
    }

    func cancelAndWait(_ item: BackgroundScanItem) async {
        guard let task = tasks[item] else { return }
        // Flip the cancellation bit before waiting on the lane so a scan that
        // finishes in the meantime cannot write its stale result back.
        task.cancel()
        await cancelLane(item)
        await task.value
        // `run`'s defer clears the registry entry before the task completes,
        // so a newer task can never be overwritten here.
    }

    /// Rescans every item whose cached result is missing or older than
    /// `refreshInterval`. Failures without a result back off to
    /// `failureRetryInterval`; failures with a cached result keep it.
    func refreshIfDue(now: Date? = nil) {
        let now = now ?? nowProvider()
        for item in BackgroundScanItem.allCases {
            guard shouldRefresh(item, now: now) else { continue }
            request(item)
        }
    }

    /// Called when user-visible clean activity starts or ends; a deferred clean
    /// scan restarts once the user no longer owns clean-list.txt.
    func noteActivityChanged() {
        if deferredClean, !isCleanBusy {
            deferredClean = false
            request(.clean)
        }
        if deferredInstaller, diskAccessGranted {
            deferredInstaller = false
            request(.installerList)
        }
    }

    func diskAccessDidChange() {
        noteActivityChanged()
    }

    // MARK: - Execution

    private func shouldRefresh(_ item: BackgroundScanItem, now: Date) -> Bool {
        if failedItems.contains(item), let failedAt = lastFailureAt[item] {
            return now.timeIntervalSince(failedAt) >= Self.failureRetryInterval
        }
        if let result = results[item] {
            return now.timeIntervalSince(result.capturedAt) >= Self.refreshInterval
        }
        if let failedAt = lastFailureAt[item] {
            return now.timeIntervalSince(failedAt) >= Self.failureRetryInterval
        }
        return true
    }

    private var diskAccessGranted: Bool {
        accessMonitor?.isGranted ?? true
    }

    private var isCleanBusy: Bool {
        cleanBusyProvider() || coordinator.activeOperation == .clean
    }

    private func startPeriodicRefresh() {
        periodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let tick = max(0.05, self.periodicTick)
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.refreshIfDue()
            }
        }
    }

    private func cancelLane(_ item: BackgroundScanItem) async {
        switch item {
        case .uninstallList:
            await uninstallStream.cancel()
        case .installerList:
            await lanes.installerProcess.cancel()
        case .clean:
            await lanes.clean.cancel()
        case .optimize:
            await lanes.optimize.cancel()
        case .purge:
            await lanes.purge.cancel()
        }
    }

    private func run(_ item: BackgroundScanItem) async {
        runningItems.insert(item)
        let startedVersion = coordinator.version(for: item)
        defer {
            runningItems.remove(item)
            tasks[item] = nil
        }
        do {
            let payload = try await payload(for: item)
            guard !Task.isCancelled else { return }
            let currentVersion = coordinator.version(for: item)
            let isStale = (startedVersion < currentVersion)
            results[item] = BackgroundScanResult(
                capturedAt: nowProvider(),
                payload: payload,
                targetVersion: currentVersion,
                capturedVersion: startedVersion,
                isStale: isStale
            )
            failedItems.remove(item)
            lastFailureAt.removeValue(forKey: item)
            cache.save(results)
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            // Keep the previous result, if any; surface the failure so the page
            // can offer a retry without blocking other items.
            failedItems.insert(item)
            lastFailureAt[item] = nowProvider()
        }
    }

    private func applyImpact(_ impact: DataImpact) async {
        for item in impact.scanItems {
            await cancelAndWait(item)
            let currentVersion = coordinator.version(for: item)
            if let existing = results[item] {
                results[item] = existing.markingStale(targetVersion: currentVersion)
            }
        }
        cache.save(results)
        for item in impact.scanItems {
            request(item)
        }
    }

    private func payload(for item: BackgroundScanItem) async throws -> BackgroundScanPayload {
        switch item {
        case .uninstallList:
            var rows: [UninstallAppListing] = []
            var indexByPath: [String: Int] = [:]
            for try await row in await uninstallStream.rows() {
                UninstallListMerge.merge(row, into: &rows, indexByPath: &indexByPath)
            }
            return .uninstallRows(rows)
        case .installerList:
            return .installerCandidates(try await lanes.installer.list())
        case .clean:
            let generation = try cleanPreviewStore.begin()
            let result = try await lanes.clean.run(
                ["clean", "--dry-run"],
                stdin: nil,
                timeout: 600
            )
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            return .cleanPreview(try cleanPreviewStore.read(generation))
        case .optimize:
            let result = try await lanes.optimize.run(
                ["optimize", "--dry-run"],
                stdin: nil,
                timeout: 600
            )
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            return .maintenance(MaintenanceOutput.summary(stdout: result.stdout))
        case .purge:
            let result = try await lanes.purge.run(
                ["purge", "--dry-run"],
                stdin: nil,
                timeout: 600
            )
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            return .maintenance(MaintenanceOutput.summary(stdout: result.stdout))
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let bridgeError = error as? MoleBridgeError, bridgeError == .cancelled {
            return true
        }
        return false
    }
}
