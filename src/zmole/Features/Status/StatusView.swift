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
            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.isSampling ? UtilityStyle.accent : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(viewModel.isPaused ? "status.paused" : (viewModel.isSampling ? "status.sampling" : "status.waiting"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if let date = viewModel.lastUpdatedAt {
                    Text(date, style: .time)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if viewModel.isPaused {
                    Button("status.resume") { viewModel.start() }
                } else {
                    Button("status.pause") { Task { await viewModel.pause() } }
                        .disabled(!viewModel.isSampling)
                }
                Button("status.refresh") { viewModel.retry() }
                    .disabled(viewModel.isSampling && !viewModel.isPaused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(UtilityStyle.background)
            Divider()
            content
        }
        .navigationTitle("mode.status")
        .task {
            guard viewModel.snapshot == nil, !viewModel.isSampling else { return }
            viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.snapshot == nil {
            ProgressView("status.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot = viewModel.snapshot {
            StatusSnapshotContent(snapshot: snapshot, series: viewModel.series)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 14) {
                UtilityNotice(title: "status.error_title", detail: errorMessage, isError: true)
                Button("status.retry") { viewModel.retry() }
            }
            .padding(24)
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("status.sampling").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StatusSnapshotContent: View {
    let snapshot: StatusSnapshot
    let series: [StatusSeriesPoint]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    UtilityMetric(
                        title: "status.health",
                        value: snapshot.healthScoreAvailable ? "\(snapshot.healthScore)" : "—",
                        detail: "status.health_detail",
                        emphasized: snapshot.healthScoreAvailable
                    )
                    UtilityMetric(
                        title: "status.cpu",
                        value: snapshot.cpu.usageAvailable ? percent(snapshot.cpu.usage) : "—",
                        detail: "status.cpu.detail",
                        fraction: snapshot.cpu.usageAvailable ? snapshot.cpu.usage / 100 : nil
                    )
                    UtilityMetric(
                        title: "status.memory",
                        value: memoryValue,
                        detail: "status.memory.detail",
                        fraction: snapshot.memory.usedPercent.map { $0 / 100 }
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    diskPanel
                    ioPanel
                    networkPanel
                }

                processPanel
            }
            .padding(20)
        }
        .background(UtilityStyle.background)
    }

    private var memoryValue: String {
        if let used = snapshot.memory.used, let total = snapshot.memory.total {
            return "\(bytes(used)) / \(bytes(total))"
        }
        if let percent = snapshot.memory.usedPercent { return self.percent(percent) }
        return "—"
    }

    private var diskPanel: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("status.disk").font(.system(size: 14, weight: .semibold))
                ForEach(Array(snapshot.disks.prefix(2).enumerated()), id: \.offset) { _, disk in
                    HStack {
                        Text(disk.mount).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        if let used = disk.used, let total = disk.total {
                            Text("\(bytes(used)) / \(bytes(total))")
                                .font(.system(size: 11, design: .monospaced))
                        } else if let usedPercent = disk.usedPercent {
                            Text(self.percent(usedPercent)).font(.system(size: 11, design: .monospaced))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
                if snapshot.disks.isEmpty { Text("status.unavailable").foregroundStyle(.secondary) }
            }
            .padding(14)
        }
    }

    private var ioPanel: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("status.disk_io").font(.system(size: 14, weight: .semibold))
                metricLine("status.read", value: snapshot.diskIOIsWarming ? String(localized: "status.sampling") : rate(snapshot.diskIO?.readRate))
                metricLine("status.write", value: snapshot.diskIOIsWarming ? String(localized: "status.sampling") : rate(snapshot.diskIO?.writeRate))
                Text(snapshot.diskIOIsWarming ? "status.disk_io_warming" : (series.count < 2 ? "status.trend_waiting" : "status.trend_ready"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var networkPanel: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("status.network").font(.system(size: 14, weight: .semibold))
                metricLine("status.download", value: rate(snapshot.networkTotal?.rxRateMBs))
                metricLine("status.upload", value: rate(snapshot.networkTotal?.txRateMBs))
                Text("status.physical_interfaces")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var processPanel: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("status.processes").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if snapshot.processStale { UtilityBadge(title: "status.stale", symbol: "clock") }
                }
                .padding(14)
                Divider()
                if let processes = snapshot.topProcesses, !processes.isEmpty {
                    ForEach(processes, id: \.pid) { process in
                        HStack(spacing: 10) {
                            Text("\(process.pid)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                            Text(process.name).lineLimit(1)
                            Spacer()
                            Text(process.cpu.map(percent) ?? "—").font(.system(size: 11, design: .monospaced))
                            Text(process.memoryBytes.map(bytes) ?? process.memoryPercent.map(percent) ?? "—")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        Divider().padding(.leading, 14)
                    }
                } else {
                    Text("status.processes_waiting").foregroundStyle(.secondary).padding(14)
                }
            }
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
    private func rate(_ value: Double?) -> String { value.map { String(format: "%.2f MB/s", $0) } ?? "—" }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}
