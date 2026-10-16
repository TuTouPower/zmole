import Combine
import Foundation

/// Formats a status snapshot for the overview headline metrics. Kept as a pure
/// value type so the mapping can be asserted without rendering SwiftUI.
struct OverviewMetrics: Equatable, Sendable {
    let snapshot: StatusSnapshot

    var healthText: String {
        snapshot.healthScoreAvailable ? "\(snapshot.healthScore)" : "—"
    }

    var cpuText: String {
        snapshot.cpu.usageAvailable ? String(format: "%.1f%%", snapshot.cpu.usage) : "—"
    }

    var memoryText: String {
        if let used = snapshot.memory.used, let total = snapshot.memory.total {
            return "\(OverviewMetrics.bytes(used)) / \(OverviewMetrics.bytes(total))"
        }
        if let percent = snapshot.memory.usedPercent {
            return String(format: "%.1f%%", percent)
        }
        return "—"
    }

    var primaryDisk: StatusSnapshot.Disk? {
        snapshot.disks.first { $0.used != nil && $0.total != nil } ?? snapshot.disks.first
    }

    var freeDiskBytes: Int64? {
        guard let disk = primaryDisk, let total = disk.total, let used = disk.used else { return nil }
        return max(0, total - used)
    }

    var freeDiskText: String {
        freeDiskBytes.map(OverviewMetrics.bytes) ?? "—"
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

enum OverviewTrend {
    static let minimumSamples = 3

    static func hasEnoughSamples(_ series: [StatusSeriesPoint]) -> Bool {
        series.filter { $0.cpuUsage != nil || $0.memoryUsedPercent != nil }.count >= minimumSamples
    }
}

/// A shortcut card. Cards can only navigate, never run an operation.
struct OverviewQuickAction: Identifiable, Equatable, Sendable {
    let destination: AppDestination
    var id: String { destination.rawValue }

    static let all: [OverviewQuickAction] = [
        OverviewQuickAction(destination: .clean),
        OverviewQuickAction(destination: .optimize),
        OverviewQuickAction(destination: .disk)
    ]
}

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published private(set) var breakdown = StorageBreakdown.placeholder
    @Published private(set) var recentOperations: [HistorySession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// Set when a write operation invalidated the cached estimate.
    @Published private(set) var estimateInvalidated = false

    private let storageLoader: StorageEstimateLoader?
    private let historyLoader: HistorySnapshotLoader?
    private let storageCache: StorageEstimateCache?
    private let now: @Sendable () -> Date
    private var cacheEntry: StorageEstimateCacheEntry?
    private var isEstimating = false
    private var invalidationCount = 0
    private var coordinatorSubscription: AnyCancellable?

    init(
        storageLoader: StorageEstimateLoader?,
        historyLoader: HistorySnapshotLoader?,
        storageCache: StorageEstimateCache? = nil,
        coordinator: OperationCoordinator? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.storageLoader = storageLoader
        self.historyLoader = historyLoader
        self.storageCache = storageCache
        self.now = now
        if let coordinator {
            coordinatorSubscription = coordinator.$invalidationGeneration
                .dropFirst()
                .sink { [weak self] _ in
                    self?.invalidationCount += 1
                    self?.estimateInvalidated = true
                }
        }
    }

    init() {
        storageLoader = nil
        historyLoader = nil
        storageCache = nil
        now = Date.init
    }

    var quickActions: [OverviewQuickAction] { OverviewQuickAction.all }

    var hasRecentOperations: Bool { !recentOperations.isEmpty }

    /// Renders a cached estimate immediately (no analyze). Call before
    /// `refreshEstimateIfNeeded` so the page never waits on a scan.
    func primeEstimate(usedBytes: Int64?) {
        guard breakdown == .placeholder else { return }
        guard let entry = storageCache?.load(now: now()) else { return }
        cacheEntry = entry
        breakdown = entry.sums.breakdown(usedBytes: usedBytes)
    }

    var estimateNeedsRefresh: Bool {
        guard storageLoader != nil else { return false }
        if estimateInvalidated { return true }
        guard let cacheEntry else { return true }
        // A partial cache must not suppress a retry for the failed paths.
        guard cacheEntry.sums.isComplete else { return true }
        return storageCache?.isStale(cacheEntry, now: now()) ?? true
    }

    /// Loads the recent history once per overview appearance.
    func refreshHistory() async {
        guard let historyLoader else { return }
        do {
            recentOperations = try await historyLoader.load(limit: 5).sessions
            errorMessage = nil
        } catch {
            recentOperations = []
            errorMessage = error.localizedDescription
        }
    }

    /// Computes the estimate unless a valid, fresh cache already covers it.
    func refreshEstimateIfNeeded(usedBytes: Int64?) async {
        guard estimateNeedsRefresh else { return }
        await computeEstimate(usedBytes: usedBytes)
    }

    /// Forced recompute (tests and explicit refresh).
    func loadEstimate(usedBytes: Int64?) async {
        guard usedBytes != nil else { return }
        await computeEstimate(usedBytes: usedBytes)
    }

    private func computeEstimate(usedBytes: Int64?) async {
        guard let storageLoader, let usedBytes, !isEstimating else { return }
        isEstimating = true
        let invalidationsAtStart = invalidationCount
        defer { isEstimating = false }
        let sums = await storageLoader.loadSums()
        breakdown = sums.breakdown(usedBytes: usedBytes)
        let capturedAt = now()
        storageCache?.save(sums, capturedAt: capturedAt)
        cacheEntry = StorageEstimateCacheEntry(
            schemaVersion: StorageEstimateCache.schemaVersion,
            capturedAt: capturedAt,
            sums: sums
        )
        // Keep the estimate marked stale if a write invalidated it mid-scan.
        if invalidationCount == invalidationsAtStart {
            estimateInvalidated = false
        }
    }

    /// Convenience used by tests: load history and, when a used-space value is
    /// known, the estimate.
    func refresh(usedBytes: Int64?) async {
        isLoading = true
        defer { isLoading = false }
        await refreshHistory()
        await loadEstimate(usedBytes: usedBytes)
    }
}
