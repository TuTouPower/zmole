import SwiftUI

@MainActor
struct OverviewView: View {
    @ObservedObject var statusViewModel: StatusViewModel
    @ObservedObject var viewModel: OverviewViewModel
    @ObservedObject var navigation: NavigationModel
    @State private var didLoadEstimate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                heroRow
                quickCards
                lowerRow
            }
            .padding(24)
        }
        .background(MoleTheme.background)
        .navigationTitle("overview.title")
        .task {
            await viewModel.refreshHistory()
            // One-shot commands share the command bridge, so the estimate is
            // loaded only after history finishes and one used-space value is
            // available. No per-tick trigger, so the four analyze calls never
            // overlap each other or the history command.
            for _ in 0..<120 where usedBytes == nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await loadEstimateIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("overview.eyebrow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MoleTheme.accentStrong)
                .textCase(.uppercase)
            Text(greetingKey)
                .font(.system(size: 30, weight: .bold))
            Text("overview.subtitle")
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.muted)
        }
    }

    private var greetingKey: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "overview.greeting.morning"
        case 12..<18: return "overview.greeting.afternoon"
        default: return "overview.greeting.evening"
        }
    }

    @ViewBuilder
    private var heroRow: some View {
        HStack(alignment: .top, spacing: 14) {
            metricsCard
            diskCard
        }
    }

    private var metricsCard: some View {
        let metrics = statusViewModel.snapshot.map(OverviewMetrics.init)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("overview.health")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(metrics?.healthText ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(MoleTheme.accentStrong)
            }
            if metrics == nil {
                Text("overview.waiting")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.subtle)
            }
            HStack(spacing: 10) {
                metricTile("overview.cpu", metrics?.cpuText ?? "—")
                metricTile("overview.memory", metrics?.memoryText ?? "—")
                metricTile("overview.free_disk", metrics?.freeDiskText ?? "—")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func metricTile(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.subtle)
            Text(verbatim: value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: MoleTheme.radiusMD))
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("overview.storage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("overview.storage.estimate")
                    .font(.system(size: 10))
                    .foregroundStyle(MoleTheme.subtle)
            }
            HStack(alignment: .center, spacing: 18) {
                StorageRingView(breakdown: viewModel.breakdown)
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(StorageSegment.allCases) { segment in
                        legendRow(segment)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func legendRow(_ segment: StorageSegment) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(segment.color)
                .frame(width: 8, height: 8)
            Text(segment.titleKey)
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.muted)
            Spacer(minLength: 8)
            Text(verbatim: viewModel.breakdown.bytes(for: segment).map(OverviewMetrics.bytes) ?? "—")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
    }

    private var quickCards: some View {
        HStack(spacing: 12) {
            ForEach(viewModel.quickActions) { action in
                Button {
                    navigation.select(action.destination)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: action.destination.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(MoleTheme.accentStrong)
                        Text(action.destination.titleKey)
                            .font(.system(size: 13, weight: .semibold))
                        Text(action.destination.subtitleKey)
                            .font(.system(size: 10))
                            .foregroundStyle(MoleTheme.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .padding(16)
                    .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
                    .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var lowerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            activityCard
            trendCard
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("overview.recent")
                .font(.system(size: 13, weight: .semibold))
                .padding(16)
            Divider()
            if viewModel.hasRecentOperations {
                ForEach(Array(viewModel.recentOperations.prefix(4).enumerated()), id: \.offset) { _, session in
                    HStack(spacing: 10) {
                        Text(session.command)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: session.size ?? "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MoleTheme.muted)
                        Text(verbatim: session.dateText ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(MoleTheme.subtle)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    Divider().padding(.leading, 16)
                }
            } else {
                Text("overview.recent_empty")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.subtle)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("overview.trend")
                .font(.system(size: 13, weight: .semibold))
            if OverviewTrend.hasEnoughSamples(statusViewModel.series) {
                OverviewSparklineView(series: statusViewModel.series)
                    .frame(height: 80)
            } else {
                Text("overview.trend_insufficient")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.subtle)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func loadEstimateIfNeeded() async {
        guard !didLoadEstimate, let usedBytes else { return }
        didLoadEstimate = true
        await viewModel.loadEstimate(usedBytes: usedBytes)
    }

    private var usedBytes: Int64? {
        guard let disk = statusViewModel.snapshot?.disks.first(where: { $0.used != nil && $0.total != nil }) else {
            return nil
        }
        return disk.used
    }
}

enum StorageSegment: String, CaseIterable, Identifiable, Sendable {
    case system
    case applications
    case userData
    case developer
    case other

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "overview.storage.system"
        case .applications: "overview.storage.applications"
        case .userData: "overview.storage.user_data"
        case .developer: "overview.storage.developer"
        case .other: "overview.storage.other"
        }
    }

    var color: Color {
        switch self {
        case .system: Color(red: 0.35, green: 0.39, blue: 0.85)
        case .applications: Color(red: 0.54, green: 0.45, blue: 0.79)
        case .userData: Color(red: 0.36, green: 0.61, blue: 0.79)
        case .developer: Color(red: 0.85, green: 0.65, blue: 0.36)
        case .other: Color(red: 0.73, green: 0.74, blue: 0.78)
        }
    }
}

extension StorageBreakdown {
    func bytes(for segment: StorageSegment) -> Int64? {
        switch segment {
        case .system: systemBytes
        case .applications: applicationsBytes
        case .userData: userDataBytes
        case .developer: developerBytes
        case .other: otherBytes
        }
    }
}

private struct StorageRingView: View {
    let breakdown: StorageBreakdown

    var body: some View {
        ZStack {
            if breakdown.isComplete {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.start + segment.fraction)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                Circle()
                    .stroke(MoleTheme.surface3, style: StrokeStyle(lineWidth: 18))
            }
            Circle()
                .fill(MoleTheme.surface)
                .frame(width: 74, height: 74)
        }
        .accessibilityHidden(true)
    }

    private struct Segment: Hashable {
        let start: CGFloat
        let fraction: CGFloat
        let color: Color
    }

    private var segments: [Segment] {
        let total = StorageSegment.allCases
            .compactMap { breakdown.bytes(for: $0) }
            .reduce(Int64(0), +)
        guard total > 0 else { return [] }
        var start: CGFloat = 0
        return StorageSegment.allCases.compactMap { segment in
            guard let bytes = breakdown.bytes(for: segment), bytes > 0 else { return nil }
            let fraction = CGFloat(Double(bytes) / Double(total))
            let result = Segment(start: start, fraction: fraction, color: segment.color)
            start += fraction
            return result
        }
    }
}

private struct OverviewSparklineView: View {
    let series: [StatusSeriesPoint]

    var body: some View {
        GeometryReader { proxy in
            let values = series.compactMap(\.memoryUsedPercent)
            let maxValue = max(values.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MoleTheme.accent)
                        .frame(width: max(3, proxy.size.width / CGFloat(max(values.count, 1)) - 4),
                               height: max(3, proxy.size.height * CGFloat(value / maxValue)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
    }
}
