import Foundation

/// Serial owner of background scan cache persistence, running off the MainActor.
/// Holds accepted revisions, pending snapshots, and persisted watermarks.
actor BackgroundScanStorage {
    let fileURL: URL
    private let cache: BackgroundScanCache

    private(set) var persistedRevision: UInt64 = 0
    private(set) var acceptedRevision: UInt64 = 0
    private(set) var persistedResults: [BackgroundScanItem: BackgroundScanResult] = [:]
    private(set) var pendingSnapshot: [BackgroundScanItem: BackgroundScanResult]?
    private(set) var pendingRevision: UInt64?
    private(set) var lastWriteError: Error?

    private var debounceTask: Task<Void, Never>?
    private var firstPendingTime: Date?

    private let nowProvider: @Sendable () -> Date
    private let sleepProvider: @Sendable (TimeInterval) async -> Void
    private let onEncodeOrWrite: (@Sendable () -> Void)?
    private let onDecodeOrRead: (@Sendable () -> Void)?
    private let onBeforeLoadRead: (@Sendable () async -> Void)?
    private var failingWrite: Bool = false

    init(
        fileURL: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { duration in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        },
        onEncodeOrWrite: (@Sendable () -> Void)? = nil,
        onDecodeOrRead: (@Sendable () -> Void)? = nil,
        onBeforeLoadRead: (@Sendable () async -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.cache = BackgroundScanCache(fileURL: fileURL)
        self.nowProvider = now
        self.sleepProvider = sleep
        self.onEncodeOrWrite = onEncodeOrWrite
        self.onDecodeOrRead = onDecodeOrRead
        self.onBeforeLoadRead = onBeforeLoadRead
    }

    func setFailingWrite(_ failing: Bool) {
        self.failingWrite = failing
    }

    func load() async -> [BackgroundScanItem: BackgroundScanResult] {
        if let onBeforeLoadRead {
            await onBeforeLoadRead()
        }
        onDecodeOrRead?()

        let loaded = cache.load()

        var merged = loaded
        if let pending = pendingSnapshot {
            for (key, val) in pending {
                merged[key] = val
            }
        }
        for (key, val) in persistedResults {
            merged[key] = val
        }

        persistedResults = merged
        return merged
    }

    func submit(
        results: [BackgroundScanItem: BackgroundScanResult],
        revision: UInt64,
        isPriority: Bool
    ) async {
        if revision < acceptedRevision {
            return
        }
        acceptedRevision = revision
        pendingSnapshot = results
        pendingRevision = revision

        if isPriority {
            debounceTask?.cancel()
            debounceTask = nil
            firstPendingTime = nil
            await writePendingToDisk()
        } else {
            let now = nowProvider()
            if firstPendingTime == nil {
                firstPendingTime = now
            }
            let elapsed = now.timeIntervalSince(firstPendingTime!)
            if elapsed >= 0.5 {
                debounceTask?.cancel()
                debounceTask = nil
                firstPendingTime = nil
                await writePendingToDisk()
            } else {
                let remaining = max(0.001, 0.5 - elapsed)
                let delay = min(0.1, remaining)
                debounceTask?.cancel()
                debounceTask = Task { [weak self] in
                    guard let self else { return }
                    await self.sleepProvider(delay)
                    guard !Task.isCancelled else { return }
                    await self.writePendingFromDebounce()
                }
            }
        }
    }

    func writePendingFromDebounce() async {
        firstPendingTime = nil
        debounceTask = nil
        await writePendingToDisk()
    }

    func flush() async -> UInt64 {
        debounceTask?.cancel()
        debounceTask = nil
        firstPendingTime = nil
        if pendingSnapshot != nil {
            await writePendingToDisk()
        }
        return persistedRevision
    }

    func close(budget: TimeInterval = 1.0) async -> UInt64 {
        return await flush()
    }

    func retryPending() async {
        if pendingSnapshot != nil {
            await writePendingToDisk()
        }
    }

    private func writePendingToDisk() async {
        guard let snapshot = pendingSnapshot, let rev = pendingRevision else { return }
        if failingWrite {
            lastWriteError = NSError(
                domain: "BackgroundScanStorage",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated write failure"]
            )
            return
        }

        onEncodeOrWrite?()

        do {
            try cache.saveThrowing(snapshot)
            persistedRevision = rev
            persistedResults = snapshot
            pendingSnapshot = nil
            pendingRevision = nil
            lastWriteError = nil
        } catch {
            lastWriteError = error
        }
    }
}
