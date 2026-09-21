import Foundation
import SwiftUI

@MainActor
struct StatusView: View {
    @StateObject private var viewModel: StatusViewModel

    init(viewModel: StatusViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? StatusViewModel())
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.snapshot == nil {
                ProgressView("status.loading")
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("status.error_title")
                        .font(.title)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = viewModel.snapshot {
                StatusSnapshotContent(snapshot: snapshot)
            } else {
                ProgressView("status.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("sidebar.status")
        .toolbar {
            ToolbarItem {
                Button("status.refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            guard viewModel.snapshot == nil, !viewModel.isLoading else { return }
            await viewModel.refresh()
        }
    }
}

private struct StatusSnapshotContent: View {
    let snapshot: StatusSnapshot

    var body: some View {
        Form {
            Section("status.health") {
                LabeledContent("status.health_score") {
                    Text("\(snapshot.healthScore)")
                }
            }

            Section("status.cpu") {
                LabeledContent("status.cpu.usage") {
                    Text(percent(snapshot.cpu.usage))
                }
            }

            Section("status.memory") {
                if let used = snapshot.memory.used, let total = snapshot.memory.total {
                    LabeledContent("status.memory.used_total") {
                        Text("\(bytes(used)) / \(bytes(total))")
                    }
                } else if let usedPercent = snapshot.memory.usedPercent {
                    LabeledContent("status.memory.used_percent") {
                        Text(percent(usedPercent))
                    }
                }
            }

            Section("status.disk") {
                ForEach(Array(snapshot.disks.enumerated()), id: \.offset) { _, disk in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(disk.mount)
                            .font(.headline)
                        if let used = disk.used, let total = disk.total {
                            LabeledContent("status.disk.used_total") {
                                Text("\(bytes(used)) / \(bytes(total))")
                            }
                        } else if let usedPercent = disk.usedPercent {
                            LabeledContent("status.disk.used_percent") {
                                Text(percent(usedPercent))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
