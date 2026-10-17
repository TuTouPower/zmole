import Combine
import Foundation
import os

private let overviewLog = Logger(subsystem: "com.tutupower.zmole", category: "Overview")

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
        StatusReadout.memoryText(
            used: snapshot.memory.used,
            total: snapshot.memory.total,
            percent: snapshot.memory.usedPercent
        )
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

/// Health-card copy keyed off the live score. Missing scores keep an unknown
/// state instead of inventing one.
enum OverviewHealth {
    enum Status: Equatable, Sendable {
        case good
        case fair
        case poor
        case unknown

        var titleKey: String {
            switch self {
            case .good: "overview.health.good"
            case .fair: "overview.health.fair"
            case .poor: "overview.health.poor"
            case .unknown: "overview.health.unknown"
            }
        }
    }

    static func status(for score: Int?) -> Status {
        guard let score else { return .unknown }
        if score >= 80 { return .good }
        if score >= 60 { return .fair }
        return .poor
    }
}

/// One tile inside the health card or the system status grid.
struct OverviewTile: Equatable, Sendable, Identifiable {
    let id: String
    let titleKey: String
    let value: String
    var note: String? = nil
}

/// Values shown by the overview health card; every missing source renders the
/// unknown placeholder instead of a fabricated value.
struct OverviewHealthCard: Equatable, Sendable {
    let scoreText: String
    let status: OverviewHealth.Status
    let tiles: [OverviewTile]

    static func make(snapshot: StatusSnapshot?, reclaimBytes: Int64?) -> OverviewHealthCard {
        let metrics = snapshot.map(OverviewMetrics.init)
        let score = (snapshot?.healthScoreAvailable == true) ? snapshot?.healthScore : nil
        return OverviewHealthCard(
            scoreText: metrics?.healthText ?? "—",
            status: OverviewHealth.status(for: score),
            tiles: [
                OverviewTile(
                    id: "free_space",
                    titleKey: "overview.free_disk",
                    value: metrics?.freeDiskText ?? "—",
                    note: freeSpaceNote(snapshot: snapshot)
                ),
                OverviewTile(
                    id: "reclaimable",
                    titleKey: "overview.reclaimable",
                    value: reclaimBytes.map(OverviewMetrics.bytes) ?? "—",
                    note: reclaimBytes == nil ? "overview.reclaim_no_preview" : nil
                ),
                OverviewTile(
                    id: "cpu",
                    titleKey: "overview.cpu",
                    value: metrics?.cpuText ?? "—",
                    note: "overview.note_current_load"
                )
            ]
        )
    }

    private static func freeSpaceNote(snapshot: StatusSnapshot?) -> String? {
        guard let snapshot,
              let disk = OverviewMetrics(snapshot: snapshot).primaryDisk,
              let used = disk.used,
              let total = disk.total,
              total > 0 else { return nil }
        let percent = Double(max(0, total - used)) / Double(total) * 100
        return String(format: "%.0f%%", percent)
    }
}

/// Four-tile real-time snapshot for the system status grid.
struct OverviewStatusGrid: Equatable, Sendable {
    let tiles: [OverviewTile]

    static func make(snapshot: StatusSnapshot?) -> OverviewStatusGrid {
        guard let snapshot else {
            return OverviewStatusGrid(tiles: [
                OverviewTile(id: "cpu", titleKey: "status.stat.cpu", value: "—"),
                OverviewTile(id: "memory", titleKey: "status.stat.memory", value: "—"),
                OverviewTile(id: "temperature", titleKey: "status.stat.temperature", value: "—"),
                OverviewTile(id: "network", titleKey: "status.network", value: "—")
            ])
        }
        let metrics = OverviewMetrics(snapshot: snapshot)

        let memoryNote = (snapshot.memory.used != nil && snapshot.memory.total != nil)
            ? snapshot.memory.usedPercent.map { String(format: "%.0f%%", $0) }
            : nil

        let network: String
        if let total = snapshot.networkTotal {
            let down = StatusReadout.rate(total.rxRateMBs)
            let up = StatusReadout.rate(total.txRateMBs)
            network = "↓ \(down) · ↑ \(up)"
        } else {
            network = "—"
        }

        return OverviewStatusGrid(tiles: [
            OverviewTile(id: "cpu", titleKey: "status.stat.cpu", value: metrics.cpuText),
            OverviewTile(id: "memory", titleKey: "status.stat.memory", value: metrics.memoryText, note: memoryNote),
            OverviewTile(
                id: "temperature",
                titleKey: "status.stat.temperature",
                value: StatusReadout.temperature(snapshot.cpuTemperature)
            ),
            OverviewTile(id: "network", titleKey: "status.network", value: network)
        ])
    }
}

/// One recent-activity row (demo `activityRow`): icon, command, time, value
/// and an optional item count.
struct OverviewActivityRow: Equatable, Sendable, Identifiable {
    let id: String
    let symbol: String
    let command: String
    let time: String
    let value: String
    let items: Int?

    static func make(index: Int, symbol: String, session: HistorySession) -> OverviewActivityRow {
        OverviewActivityRow(
            id: "activity-\(index)",
            symbol: symbol,
            command: session.command,
            time: session.dateText ?? "",
            value: session.size ?? "—",
            items: session.items
        )
    }
}

enum OverviewActivity {
    static func rows(from sessions: [HistorySession], limit: Int = 4) -> [OverviewActivityRow] {
        sessions.prefix(limit).enumerated().map { index, session in
            OverviewActivityRow.make(index: index, symbol: symbol(for: session.command), session: session)
        }
    }

    static func symbol(for command: String) -> String {
        switch command.lowercased() {
        case "clean": return "sparkle"
        case "optimize": return "gauge"
        case "uninstall": return "trash"
        default: return "clock"
        }
    }
}

/// Storage card presentation: big used number, free-space copy, the five
/// segments and the free remainder.
struct OverviewStorageCard: Equatable, Sendable {
    struct Segment: Equatable, Sendable, Identifiable {
        let id: String
        let segment: StorageSegment
        let bytes: Int64
        /// Share of the used bytes.
        let fraction: Double
    }

    let usedText: String
    let freeText: String?
    let freePercentText: String?
    let capacityText: String?
    let isComplete: Bool
    let segments: [Segment]
    let freeFraction: Double?

    static func make(breakdown: StorageBreakdown, disk: StatusSnapshot.Disk?) -> OverviewStorageCard {
        let used = disk?.used
        let total = disk?.total
        let usedForSegments = used ?? StorageSegment.allCases
            .compactMap { breakdown.bytes(for: $0) }
            .reduce(Int64(0), +)

        let segments = StorageSegment.allCases.compactMap { segment -> Segment? in
            guard let bytes = breakdown.bytes(for: segment) else { return nil }
            let fraction = usedForSegments > 0 ? Double(bytes) / Double(usedForSegments) : 0
            return Segment(id: segment.rawValue, segment: segment, bytes: bytes, fraction: fraction)
        }

        let freeBytes: Int64?
        let freePercent: Double?
        if let used, let total, total > 0 {
            freeBytes = max(0, total - used)
            freePercent = Double(max(0, total - used)) / Double(total)
        } else {
            freeBytes = nil
            freePercent = nil
        }

        let capacity: String?
        if let total {
            let formatted = OverviewMetrics.bytes(total)
            capacity = disk.map { "\($0.mount) · \(formatted)" }
        } else {
            capacity = nil
        }

        return OverviewStorageCard(
            usedText: used.map(OverviewMetrics.bytes) ?? "—",
            freeText: freeBytes.map(OverviewMetrics.bytes),
            freePercentText: freePercent.map { String(format: "%.1f%%", $0 * 100) },
            capacityText: capacity,
            isComplete: breakdown.isComplete,
            segments: segments,
            freeFraction: freePercent
        )
    }
}

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published private(set) var breakdown = StorageBreakdown.placeholder
    @Published private(set) var recentOperations: [HistorySession] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?
    /// Set when a write operation invalidated the cached estimate.
    @Published private(set) var estimateInvalidated = false
    @Published private(set) var showBusyNotice = false

    private let storageLoader: StorageEstimateLoader?
    private let historyLoader: HistorySnapshotLoader?
    private let storageCache: StorageEstimateCache?
    private let now: @Sendable () -> Date
    private var cacheEntry: StorageEstimateCacheEntry?
    private var isEstimating = false
    private var invalidationCount = 0
    private var lastEstimateFailureAt: Date?
    private var coordinatorSubscription: AnyCancellable?

    /// Cool-down before a failed estimate is retried, so a persistently
    /// unreadable path does not restart a multi-process scan on every page
    /// appearance.
    static let estimateFailureCooldown: TimeInterval = 30 * 60

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
        if let lastFailureAt = lastEstimateFailureAt,
           now().timeIntervalSince(lastFailureAt) < Self.estimateFailureCooldown {
            return false
        }
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
            errorMessageKey = nil
            showBusyNotice = false
        } catch {
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                errorMessage = nil
                errorMessageKey = nil
                return
            }
            showBusyNotice = false
            recentOperations = []
            errorMessageKey = error.localizationKey
            errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
        }
    }

    /// Computes the estimate unless a valid, fresh cache already covers it.
    func refreshEstimateIfNeeded(usedBytes: Int64?) async {
        guard estimateNeedsRefresh else { return }
        await computeEstimate(usedBytes: usedBytes)
    }

    private func computeEstimate(usedBytes: Int64?) async {
        guard let storageLoader, let usedBytes, !isEstimating else { return }
        isEstimating = true
        let invalidationsAtStart = invalidationCount
        defer { isEstimating = false }
        do {
            let sums = try await storageLoader.loadSums()
            // A scan that could not read every path is not persisted and never
            // replaces the live breakdown; the next appearance retries after
            // the failure cool-down.
            guard sums.isComplete else {
                lastEstimateFailureAt = now()
                overviewLog.error("storage estimate incomplete; backing off")
                return
            }
            breakdown = sums.breakdown(usedBytes: usedBytes)
            let capturedAt = now()
            storageCache?.save(sums, capturedAt: capturedAt)
            cacheEntry = StorageEstimateCacheEntry(
                schemaVersion: StorageEstimateCache.schemaVersion,
                capturedAt: capturedAt,
                sums: sums
            )
            lastEstimateFailureAt = nil
            // Keep the estimate marked stale if a write invalidated it mid-scan.
            if invalidationCount == invalidationsAtStart {
                estimateInvalidated = false
            }
        } catch is CancellationError {
            // A cancelled scan must not write a cache later launches would
            // trust, and must not replace the current estimate.
        } catch {
            // Same rule for unexpected loader failures; record the category
            // and back off so the page does not rescan on every appearance.
            lastEstimateFailureAt = now()
            overviewLog.error("storage estimate failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}
