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
                    onConfirm: { Task { await viewModel.confirmExecution() } },
                    onCancel: { viewModel.cancelConfirmation() }
                )
            } else {
                content
            }
        }
        .navigationTitle("optimize.purge")
        .toolbar {
            ToolbarItem {
                if viewModel.isPreviewing {
                    Button("purge.cancel") { Task { await viewModel.cancelPreview() } }
                } else if viewModel.isExecuting {
                    Button("purge.cancel") { Task { await viewModel.cancelExecution() } }
                } else {
                    Button {
                        Task { await viewModel.previewPurge() }
                    } label: {
                        Label("purge.preview", systemImage: "eye")
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
            UtilityNotice(title: "purge.preview_note", symbol: "arrow.triangle.2.circlepath")
            if viewModel.isPreviewing {
                busyState(title: "purge.previewing")
            } else if viewModel.isExecuting {
                busyState(title: "purge.executing")
            } else if let preview = viewModel.preview {
                outputPanel(output: preview.output)
            } else {
                UtilityEmptyState(symbol: "trash.slash", title: "optimize.purge", message: "purge.preview_hint")
            }

            if let errorMessageKey = viewModel.errorMessageKey {
                UtilityNotice(title: LocalizedStringKey(errorMessageKey), isError: true)
            } else if let errorMessage = viewModel.errorMessage {
                UtilityNotice(title: "purge.error_title", detail: errorMessage, isError: true)
            }
            if let executionSummary = viewModel.executionSummary, !executionSummary.isEmpty {
                UtilityNotice(title: "purge.result", detail: executionSummary, symbol: "checkmark.circle")
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

    private func outputPanel(output: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("purge.preview_output").font(.system(size: 16, weight: .semibold))
                Spacer()
                UtilityBadge(title: "purge.preview_ready", symbol: "checkmark")
            }
            ScrollView {
                Text(output.isEmpty ? String(localized: "purge.empty_output") : output)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .padding(12)
            .background(UtilityStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("purge.execute", role: .destructive) { viewModel.requestConfirmation() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!viewModel.canConfirm)
            }
        }
        .padding(16)
        .background(UtilityStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(UtilityStyle.separator))
    }
}
