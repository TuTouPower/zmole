import SwiftUI

enum CleanViewCopy {
    static let executionNoteKey = "clean.execution_note"
}

@MainActor
struct CleanView: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "clean.confirm_title",
                    summary: "clean.confirm_summary",
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
        .navigationTitle("sidebar.clean")
        .toolbar {
            ToolbarItem {
                if viewModel.isPreviewing {
                    Button("clean.cancel") {
                        Task { await viewModel.cancelPreview() }
                    }
                } else if viewModel.isExecuting {
                    Button("clean.cancel") {
                        Task { await viewModel.cancelExecution() }
                    }
                } else {
                    Button("clean.preview") {
                        Task { await viewModel.previewClean() }
                    }
                    .disabled(viewModel.isConfirmationPresented)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(CleanViewCopy.executionNoteKey))
                .foregroundStyle(.secondary)

            if viewModel.isPreviewing {
                ProgressView("clean.previewing")
            } else if viewModel.isExecuting {
                ProgressView("clean.executing")
            } else if let preview = viewModel.preview {
                List(preview.entries, id: \.self) { entry in
                    Text(entry)
                        .textSelection(.enabled)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button("clean.execute") {
                        viewModel.requestConfirmation()
                    }
                    .disabled(!viewModel.canConfirm)
                    .padding()
                }
            } else {
                Text("clean.empty")
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
