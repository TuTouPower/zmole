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
                    onConfirm: { Task { await viewModel.confirmExecution() } },
                    onCancel: { viewModel.cancelConfirmation() }
                )
            } else {
                content
            }
        }
        .navigationTitle("optimize.maintenance")
        .toolbar {
            ToolbarItem {
                if viewModel.isPreviewing {
                    Button("optimize.cancel") { Task { await viewModel.cancelPreview() } }
                } else if viewModel.isExecuting {
                    Button("optimize.cancel") { Task { await viewModel.cancelExecution() } }
                } else {
                    Button {
                        Task { await viewModel.previewOptimize() }
                    } label: {
                        Label("optimize.preview", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(UtilityStyle.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            UtilityNotice(title: "optimize.preview_note", symbol: "arrow.triangle.2.circlepath")
            if viewModel.isPreviewing {
                busyState(title: "optimize.previewing")
            } else if viewModel.isExecuting {
                busyState(title: "optimize.executing")
            } else if let preview = viewModel.preview {
                outputPanel(title: "optimize.preview_output", output: preview.output) {
                    Button("optimize.execute", role: .destructive) {
                        viewModel.requestConfirmation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!viewModel.canConfirm)
                }
            } else {
                UtilityEmptyState(symbol: "wrench.and.screwdriver", title: "optimize.empty", message: "optimize.preview_hint")
            }

            if let errorMessageKey = viewModel.errorMessageKey {
                UtilityNotice(title: LocalizedStringKey(errorMessageKey), isError: true)
            } else if let errorMessage = viewModel.errorMessage {
                UtilityNotice(title: "optimize.error_title", detail: errorMessage, isError: true)
            }
            if let executionSummary = viewModel.executionSummary, !executionSummary.isEmpty {
                UtilityNotice(title: "optimize.result", detail: executionSummary, symbol: "checkmark.circle")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(UtilityStyle.background)
    }

    private func busyState(title: LocalizedStringKey) -> some View {
        UtilityPanel {
            VStack(spacing: 12) {
                ProgressView()
                Text(title).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func outputPanel<Action: View>(
        title: LocalizedStringKey,
        output: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                UtilityBadge(title: "optimize.preview_ready", symbol: "checkmark")
            }
            ScrollView {
                Text(output.isEmpty ? String(localized: "optimize.empty_output") : output)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .padding(12)
            .background(UtilityStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); action() }
        }
        .padding(16)
        .background(UtilityStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(UtilityStyle.separator))
    }
}
