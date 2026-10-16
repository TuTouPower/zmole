import Combine
import Foundation

/// Read-only scans the app runs when idle so pages open with data already in
/// place. Order is fixed; one item runs at a time; no write lease is taken.
enum PrewarmItem: String, CaseIterable, Sendable {
    case uninstallList
    case installerList
    case cleanDryRun
    case optimizeDryRun
    case purgeDryRun
}

enum PrewarmPayload: Sendable {
    case uninstallRows([UninstallAppListing])
    case installerCandidates([InstallerCandidate])
    case cleanPreview(CleanPreviewSnapshot)
    case maintenance(String)
}

struct PrewarmResult: Sendable {
    let capturedAt: Date
    let payload: PrewarmPayload
}

@MainActor
protocol PrewarmResultProviding: AnyObject {
    /// Takes the finished result once; the page adopts it instead of scanning.
    func takeResult(_ item: PrewarmItem) -> PrewarmResult?
    /// The user started their own scan of this item: cancel the prewarm run
    /// and drop its result so the user's scan becomes authoritative.
    func userDidRescan(_ item: PrewarmItem)
}

/// Idle-time read-only scan queue. The service never executes a write command
/// and never holds an `OperationCoordinator` lease; a write starting or a
/// user-visible scan pauses the queue.
@MainActor
final class PrewarmService: ObservableObject, PrewarmResultProviding {
    @Published private(set) var runningItem: PrewarmItem?

    private let process: any MoleProcessControlling
    private let uninstallStream: UninstallListStream
    private let installerInterface: InstallerInterface
    private let cleanPreviewStore: CleanPreviewStore
    private let coordinator: OperationCoordinator

    private(set) var results: [PrewarmItem: PrewarmResult] = [:]
    private var queue: [PrewarmItem] = []
    private var retryItems: Set<PrewarmItem> = []
    private var droppedItems: Set<PrewarmItem> = []
    private var resultGeneration = 0
    private var worker: Task<Void, Never>?
    private var wasIdle = false
    private var coordinatorSubscription: AnyCancellable?
    private var invalidationSubscription: AnyCancellable?

    /// User-visible activity that is not coordinated by a write lease: page
    /// scans and a clean preview the user is looking at.
    var externalActivityProvider: @MainActor () -> Bool = { false }
    /// When true the clean item is deferred so it cannot overwrite the list
    /// file behind a preview the user is working with.
    var cleanPreviewActiveProvider: @MainActor () -> Bool = { false }

    init(
        process: any MoleProcessControlling & MoleStreaming,
        installerInterface: InstallerInterface? = nil,
        cleanPreviewStore: CleanPreviewStore,
        coordinator: OperationCoordinator
    ) {
        self.process = process
        uninstallStream = UninstallListStream(streaming: process)
        self.installerInterface = installerInterface ?? InstallerInterface(process: process)
        self.cleanPreviewStore = cleanPreviewStore
        self.coordinator = coordinator
        queue = PrewarmItem.allCases
        // Published properties fire before the mutation lands; hop one main
        // actor turn so the idle check reads the new value.
        coordinatorSubscription = coordinator.$activeOperation.sink { [weak self] _ in
            Task { @MainActor in self?.noteActivityChanged() }
        }
        invalidationSubscription = coordinator.$invalidationGeneration.sink { [weak self] _ in
            Task { @MainActor in self?.invalidateResults() }
        }
    }

    // MARK: - PrewarmResultProviding

    func takeResult(_ item: PrewarmItem) -> PrewarmResult? {
        results.removeValue(forKey: item)
    }

    func userDidRescan(_ item: PrewarmItem) {
        results.removeValue(forKey: item)
        retryItems.remove(item)
        droppedItems.insert(item)
        queue.removeAll { $0 == item }
        if runningItem == item {
            cancelCurrent(requeue: false)
        }
    }

    // MARK: - Control

    /// Called on every activity change. Starting an activity cancels the
    /// current prewarm run; going idle resumes the queue and retries failures.
    func noteActivityChanged() {
        if isIdle() {
            if !wasIdle {
                // A cancelled item can be both requeued and marked for retry;
                // keep a single copy in the queue.
                let retries = PrewarmItem.allCases.filter { retryItems.contains($0) }
                queue = retries + queue.filter { !retryItems.contains($0) }
                retryItems.removeAll()
            }
            wasIdle = true
            poke()
        } else {
            wasIdle = false
            cancelCurrent(requeue: true)
        }
    }

    func poke() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !queue.isEmpty, isIdle() {
            let item = queue.removeFirst()
            await run(item)
        }
        worker = nil
    }

    private func isIdle() -> Bool {
        coordinator.activeOperation == nil && !externalActivityProvider()
    }

    private func cancelCurrent(requeue: Bool) {
        guard let item = runningItem else { return }
        if requeue, !queue.contains(item) {
            queue.insert(item, at: 0)
        }
        Task { [process, uninstallStream] in
            await uninstallStream.cancel()
            await process.cancel()
        }
    }

    private func invalidateResults() {
        results.removeAll()
        queue = PrewarmItem.allCases
        retryItems.removeAll()
        droppedItems.removeAll()
        resultGeneration += 1
        poke()
    }

    private func run(_ item: PrewarmItem) async {
        if item == .cleanDryRun, cleanPreviewActiveProvider() {
            retryItems.insert(item)
            return
        }
        let generation = resultGeneration
        runningItem = item
        defer { runningItem = nil }
        do {
            let payload = try await payload(for: item)
            guard generation == resultGeneration else { return }
            results[item] = PrewarmResult(capturedAt: Date(), payload: payload)
        } catch is CancellationError {
            noteFailure(item)
        } catch MoleBridgeError.cancelled {
            noteFailure(item)
        } catch {
            // Continue with the remaining items; the failed item is retried on
            // the next idle transition.
            noteFailure(item)
        }
    }

    private func noteFailure(_ item: PrewarmItem) {
        guard !droppedItems.contains(item) else { return }
        retryItems.insert(item)
    }

    private func payload(for item: PrewarmItem) async throws -> PrewarmPayload {
        switch item {
        case .uninstallList:
            var rows: [UninstallAppListing] = []
            var indexByPath: [String: Int] = [:]
            for try await row in await uninstallStream.rows() {
                UninstallListMerge.merge(row, into: &rows, indexByPath: &indexByPath)
            }
            return .uninstallRows(rows)
        case .installerList:
            return .installerCandidates(try await installerInterface.list())
        case .cleanDryRun:
            let generation = try cleanPreviewStore.begin()
            let result = try await process.run(
                ["clean", "--dry-run"],
                stdin: nil,
                timeout: 600
            )
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            return .cleanPreview(try cleanPreviewStore.read(generation))
        case .optimizeDryRun:
            let result = try await process.run(
                ["optimize", "--dry-run"],
                stdin: nil,
                timeout: 600
            )
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            return .maintenance(MaintenanceOutput.summary(stdout: result.stdout))
        case .purgeDryRun:
            let result = try await process.run(
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
}
