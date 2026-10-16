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

    private let storageLoader: StorageEstimateLoader?
    private let historyLoader: HistorySnapshotLoader?
    private var isEstimating = false

    init(storageLoader: StorageEstimateLoader?, historyLoader: HistorySnapshotLoader?) {
        self.storageLoader = storageLoader
        self.historyLoader = historyLoader
    }

    init() {
        storageLoader = nil
        historyLoader = nil
    }

    var quickActions: [OverviewQuickAction] { OverviewQuickAction.all }

    var hasRecentOperations: Bool { !recentOperations.isEmpty }

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

    /// Directory sizes change slowly; load the estimate at most once while a
    /// used-space value is available. Re-entrancy is guarded so overlapping
    /// triggers cannot overwrite a newer result with an older one.
    func loadEstimate(usedBytes: Int64?) async {
        guard let storageLoader, let usedBytes, !isEstimating else { return }
        isEstimating = true
        defer { isEstimating = false }
        breakdown = await storageLoader.load(usedBytes: usedBytes)
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
