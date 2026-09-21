import SwiftUI

@MainActor
struct UninstallView: View {
    @ObservedObject var viewModel: UninstallViewModel

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "uninstall.confirm_title",
                    summary: "uninstall.confirm_summary",
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
        .navigationTitle("sidebar.uninstall")
        .task {
            await viewModel.loadListIfNeeded()
        }
        .toolbar {
            ToolbarItem {
                if viewModel.isListing {
                    Button("uninstall.cancel") {
                        Task { await viewModel.cancelList() }
                    }
                } else if viewModel.isPreviewing {
                    Button("uninstall.cancel") {
                        Task { await viewModel.cancelPreview() }
                    }
                } else if viewModel.isExecuting {
                    Button("uninstall.cancel") {
                        Task { await viewModel.cancelExecution() }
                    }
                } else {
                    Button("uninstall.refresh") {
                        Task { await viewModel.loadList() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isExecuting {
                ProgressView("uninstall.executing")
            } else if viewModel.isListing {
                ProgressView("uninstall.loading")
            } else if viewModel.apps.isEmpty {
                Text("uninstall.empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.apps) { app in
                    Button {
                        viewModel.toggleSelection(app)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: viewModel.selectedIDs.contains(app.id)
                                ? "checkmark.square.fill"
                                : "square")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                Text(app.uninstallName)
                                    .font(.caption)
                                Text(app.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(app.bundleID)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button("uninstall.preview") {
                        Task { await viewModel.previewUninstall() }
                    }
                    .disabled(!viewModel.canPreview)
                    if viewModel.isPreviewing {
                        ProgressView("uninstall.previewing")
                    }
                }
            }

            if let preview = viewModel.preview {
                Text("uninstall.preview_result")
                    .font(.headline)
                Text(preview.target.name)
                if !preview.output.isEmpty {
                    Text(preview.output)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("uninstall.execute") {
                    viewModel.requestConfirmation()
                }
                .disabled(!viewModel.canConfirm)
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
