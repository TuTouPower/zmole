import SwiftUI

@MainActor
struct OptimizeView: View {
    @ObservedObject var viewModel: OptimizeViewModel

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "optimize.confirm_title",
                    summary: "optimize.confirm_summary",
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
        .navigationTitle("sidebar.optimize")
        .toolbar {
            ToolbarItem {
                if viewModel.isPreviewing {
                    Button("optimize.cancel") {
                        Task { await viewModel.cancelPreview() }
                    }
                } else if viewModel.isExecuting {
                    Button("optimize.cancel") {
                        Task { await viewModel.cancelExecution() }
                    }
                } else {
                    Button("optimize.preview") {
                        Task { await viewModel.previewOptimize() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isPreviewing {
                ProgressView("optimize.previewing")
            } else if viewModel.isExecuting {
                ProgressView("optimize.executing")
            } else if let preview = viewModel.preview {
                Text("optimize.output")
                    .font(.headline)
                ScrollView {
                    if preview.output.isEmpty {
                        Text("optimize.empty_output")
                    } else {
                        Text(preview.output)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxHeight: .infinity)
                Button("optimize.execute") {
                    viewModel.requestConfirmation()
                }
                .disabled(!viewModel.canConfirm)
            } else {
                Text("optimize.empty")
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
