import Foundation
import SwiftUI

@MainActor
struct StatusView: View {
    @StateObject private var viewModel: StatusViewModel

    init(viewModel: StatusViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? StatusViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pageHead
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(MoleTheme.background)
        }
        .navigationTitle("sidebar.status")
    }

    private var pageHead: some View {
        MolePageHead(
            eyebrow: "status.eyebrow",
            title: "status.title",
            subtitle: "status.subtitle"
        ) {
            samplingIndicator
            if viewModel.isPaused {
                Button("status.resume") { viewModel.start() }
                    .buttonStyle(.borderedProminent)
                    .tint(MoleTheme.accent)
            } else {
                Button("status.pause") { Task { await viewModel.pause() } }
                    .disabled(!viewModel.isSampling)
            }
            Button("status.refresh") { viewModel.retry() }
                .disabled(viewModel.isSampling && !viewModel.isPaused)
        }
        .padding(.bottom, 10)
    }

    private var samplingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isSampling ? UtilityStyle.accent : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
            Text(viewModel.isPaused ? "status.paused" : (viewModel.isSampling ? "status.sampling" : "status.waiting"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if let date = viewModel.lastUpdatedAt {
                Text(date, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.snapshot == nil {
            ProgressView("status.loading")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
        } else if let snapshot = viewModel.snapshot {
            StatusSnapshotContent(snapshot: snapshot, series: viewModel.series)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 14) {
                UtilityNotice(title: "status.error_title", detail: errorMessage, isError: true)
                Button("status.retry") { viewModel.retry() }
            }
            .padding(.top, 12)
            .frame(maxWidth: 560, alignment: .top)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("status.sampling").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        }
    }
}

private struct StatusSnapshotContent: View {
    let snapshot: StatusSnapshot
    let series: [StatusSeriesPoint]

    private var stats: StatusStatValues {
        StatusStatValues.make(from: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statStrip
            HStack(alignment: .top, spacing: 14) {
                loadChartCard
                networkPanel
            }
            processPanel
        }
    }

    private var statStrip: some View {
        HStack(spacing: 10) {
            MoleStatTile(value: stats.cpu, label: "status.stat.cpu", emphasized: snapshot.cpu.usageAvailable)
            MoleStatTile(value: stats.memory, label: "status.stat.memory")
            MoleStatTile(value: stats.diskWrite, label: "status.stat.disk_write")
            MoleStatTile(value: stats.temperature, label: "status.stat.temperature")
        }
    }

    private var loadChartCard: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("status.load_title").font(.system(size: 17, weight: .semibold))
                        Text("status.load_subtitle")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.muted)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 12) {
                        chartLegend("status.stat.cpu", color: UtilityStyle.accent)
                        chartLegend("status.stat.memory", color: Color.secondary.opacity(0.7))
                    }
                }
                StatusLineChart(series: series)
            }
            .padding(16)
        }
    }

    private func chartLegend(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10)).foregroundStyle(MoleTheme.muted)
        }
    }

    private var networkPanel: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("status.network").font(.system(size: 17, weight: .semibold))
                    Text("status.physical_interfaces")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.muted)
                }
                metricLine("status.download", value: rate(snapshot.networkTotal?.rxRateMBs))
                metricLine("status.upload", value: rate(snapshot.networkTotal?.txRateMBs))
                if snapshot.networkTotal == nil {
                    Text("status.sampling")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.muted)
                }
            }
            .padding(16)
        }
        .frame(width: 300)
    }

    private var processPanel: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("status.processes").font(.system(size: 17, weight: .semibold))
                        Text("status.processes_note")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.muted)
                    }
                    Spacer()
                    if snapshot.processStale { UtilityBadge(title: "status.stale", symbol: "clock") }
                    if let zombies = snapshot.zombieCount, zombies > 0 {
                        UtilityBadge(title: LocalizedStringKey("status.zombies_badge \(zombies)"), symbol: "exclamationmark.triangle")
                    }
                }
                .padding(16)
                Divider()
                if let processes = snapshot.topProcesses, !processes.isEmpty {
                    processHeader
                    ForEach(processes, id: \.pid) { process in
                        processRow(process)
                    }
                } else {
                    Text("status.processes_waiting").foregroundStyle(.secondary).padding(16)
                }
            }
        }
    }

    private var processHeader: some View {
        HStack(spacing: 10) {
            Text("status.column_process").frame(maxWidth: .infinity, alignment: .leading)
            Text("status.column_cpu").frame(width: 70, alignment: .trailing)
            Text("status.column_memory").frame(width: 70, alignment: .trailing)
            Text("status.column_pid").frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 10))
        .foregroundStyle(MoleTheme.subtle)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func processRow(_ process: StatusSnapshot.ProcessInfo) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(process.name).lineLimit(1)
                Spacer(minLength: 4)
                ProgressView(value: min(1, (process.cpu ?? 0) / 100))
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                    .opacity(process.cpu == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(process.cpu.map(percent) ?? "—")
                .frame(width: 70, alignment: .trailing)
                .font(.system(size: 11, design: .monospaced))
            Text(process.memoryBytes.map(bytes) ?? process.memoryPercent.map(percent) ?? "—")
                .frame(width: 70, alignment: .trailing)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(process.pid, format: .number)
                .frame(width: 90, alignment: .trailing)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MoleTheme.subtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 16)
        }
    }

    private func metricLine(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).font(.system(size: 12, design: .monospaced))
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
    private func rate(_ value: Double?) -> String { StatusReadout.rate(value) }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}

/// Line chart for the trailing 60-second window. Each series draws only when
/// it has at least two samples; otherwise the waiting copy shows instead of a
/// fabricated trend.
private struct StatusLineChart: View {
    let series: [StatusSeriesPoint]

    var body: some View {
        let cpuPoints = StatusChart.points(
            series,
            value: { $0.cpuUsage },
            range: 0...100
        )
        let memoryPoints = StatusChart.points(
            series,
            value: { $0.memoryUsedPercent },
            range: 0...100
        )
        let drawable = StatusChart.isDrawable(cpuPoints) || StatusChart.isDrawable(memoryPoints)

        GeometryReader { proxy in
            ZStack {
                chartGrid
                if StatusChart.isDrawable(cpuPoints) {
                    Path(StatusChart.path(cpuPoints, in: proxy.size))
                        .stroke(UtilityStyle.accent, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                if StatusChart.isDrawable(memoryPoints) {
                    Path(StatusChart.path(memoryPoints, in: proxy.size))
                        .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                }
                if !drawable {
                    Text("status.trend_waiting")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.muted)
                }
            }
        }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("status.load_title"))
    }

    private var chartGrid: some View {
        GeometryReader { proxy in
            Path { path in
                for step in 1..<4 {
                    let y = proxy.size.height * CGFloat(step) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(MoleTheme.line, lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
