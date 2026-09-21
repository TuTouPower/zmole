import SwiftUI

@MainActor
struct PurgeView: View {
    @ObservedObject var viewModel: PurgeViewModel

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "purge.confirm_title",
                    summary: "purge.confirm_summary",
                    onConfirm: {
                        Task { await viewModel.confirmExecution() }
                    },
                    onCancel: {
                        viewModel.cancelConfirmation()
                    }
                )
            } else {
                content
            }
        }
        .navigationTitle("sidebar.purge")
        .toolbar {
            ToolbarItem {
                if viewModel.isPreviewing {
                    Button("purge.cancel") {
                        Task { await viewModel.cancelPreview() }
                    }
                } else if viewModel.isExecuting {
                    Button("purge.cancel") {
                        Task { await viewModel.cancelExecution() }
                    }
                } else {
                    Button("purge.preview") {
                        Task { await viewModel.previewPurge() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isPreviewing {
                ProgressView("purge.previewing")
            } else if viewModel.isExecuting {
                ProgressView("purge.executing")
            } else if let preview = viewModel.preview {
                Text("purge.output")
                    .font(.headline)
                ScrollView {
                    if preview.output.isEmpty {
                        Text("purge.empty_output")
                    } else {
                        Text(preview.output)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxHeight: .infinity)
                Button("purge.execute") {
                    viewModel.requestConfirmation()
                }
                .disabled(!viewModel.canConfirm)
            } else {
                Text("purge.empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let errorMessageKey = viewModel.errorMessageKey {
                Text(LocalizedStringKey(errorMessageKey))
                    .foregroundStyle(.red)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            if let executionSummary = viewModel.executionSummary, !executionSummary.isEmpty {
                Text(executionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
