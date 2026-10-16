import SwiftUI

@MainActor
struct PurgeView: View {
    @ObservedObject var viewModel: PurgeViewModel
    @ObservedObject var pathsViewModel: PurgePathsViewModel
    var onOpenSettings: () -> Void = {}
    @State private var showingPathsEditor = false

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
        .navigationTitle("sidebar.purge")
        .task { viewModel.adoptPrewarmPreviewIfAvailable() }
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
                    .tint(MoleTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showingPathsEditor) {
            PurgePathsEditorView(viewModel: pathsViewModel) { showingPathsEditor = false }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("purge.eyebrow")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MoleTheme.accentStrong)
                        .textCase(.uppercase)
                    Text("purge.title").font(.system(size: 30, weight: .bold))
                    Text("purge.page_subtitle").font(.system(size: 12)).foregroundStyle(MoleTheme.muted)
                    if let capturedAt = viewModel.previewCapturedAt {
                        Text("prewarm.scan_time \(capturedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.muted)
                    }
                }

                UtilityNotice(title: "purge.permanent_note", symbol: "exclamationmark.triangle", isError: true)
                UtilityNotice(title: "purge.preview_note", symbol: "arrow.triangle.2.circlepath", isInfo: true)

                HStack(spacing: 8) {
                    Button("purge.paths.edit") { showingPathsEditor = true }
                        .buttonStyle(.bordered)
                    Button("purge.whitelist") { onOpenSettings() }
                        .buttonStyle(.bordered)
                    Spacer()
                }

                if viewModel.isPreviewing {
                    busyState(title: "purge.previewing")
                } else if viewModel.isExecuting {
                    busyState(title: "purge.executing")
                } else if let preview = viewModel.preview {
                    outputPanel(output: preview.output)
                } else {
                    UtilityEmptyState(symbol: "hammer", title: "sidebar.purge", message: "purge.preview_hint")
                        .frame(minHeight: 200)
                }

                if viewModel.showBusyNotice {
                    RecoverableBusyNotice()
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
            .padding(24)
        }
        .background(MoleTheme.background)
    }

    private func busyState(title: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
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
            .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("purge.execute", role: .destructive) { viewModel.requestConfirmation() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!viewModel.canConfirm)
            }
        }
        .padding(16)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }
}
