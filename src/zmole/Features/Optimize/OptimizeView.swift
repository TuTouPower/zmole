import SwiftUI

@MainActor
struct OptimizeView: View {
    @ObservedObject var viewModel: OptimizeViewModel
    var onOpenSettings: () -> Void = {}

    private var rows: [OptimizePlanRow] {
        viewModel.planRows()
    }

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "optimize.confirm_title",
                    summary: "optimize.confirm_summary",
                    detail: viewModel.confirmationDetail,
                    onConfirm: { Task { await viewModel.confirmExecution() } },
                    onCancel: { viewModel.cancelConfirmation() }
                )
            } else {
                content
            }
        }
        .navigationTitle("sidebar.optimize")
        .task { viewModel.adoptPrewarmPreviewIfAvailable() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MolePageHead(
                    title: "optimize.title",
                    subtitle: "optimize.subtitle"
                ) {
                    previewOrCancelButton
                    if let capturedAt = viewModel.previewCapturedAt {
                        Text("prewarm.scan_time \(capturedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.muted)
                    }
                }

                UtilityNotice(title: "optimize.permanent_note", symbol: "exclamationmark.triangle", isError: true)
                UtilityNotice(title: "optimize.preview_note", symbol: "arrow.triangle.2.circlepath", isInfo: true)

                HStack {
                    Button("optimize.whitelist") { onOpenSettings() }
                        .buttonStyle(.bordered)
                    Spacer()
                }

                if viewModel.isPreviewing {
                    UtilityBusyState(title: "optimize.previewing")
                } else if viewModel.isExecuting {
                    UtilityBusyState(title: "optimize.executing")
                } else if viewModel.preview != nil {
                    planCard
                } else {
                    UtilityEmptyState(symbol: "wrench.and.screwdriver", title: "optimize.empty", message: "optimize.preview_hint")
                        .frame(minHeight: 200)
                }

                if viewModel.showBusyNotice {
                    RecoverableBusyNotice()
                }
                if let errorMessageKey = viewModel.errorMessageKey {
                    UtilityNotice(title: LocalizedStringKey(errorMessageKey), isError: true)
                } else if let errorMessage = viewModel.errorMessage {
                    UtilityNotice(title: "optimize.error_title", detail: errorMessage, isError: true)
                }
                if let executionSummary = viewModel.executionSummary,
                   !executionSummary.isEmpty,
                   viewModel.result?.status == .succeeded {
                    UtilityNotice(title: "optimize.result", detail: executionSummary, symbol: "checkmark.circle")
                }
            }
            .padding(24)
        }
        .background(MoleTheme.background)
    }

    /// Page action: preview, or cancel whatever the page is currently doing.
    @ViewBuilder
    private var previewOrCancelButton: some View {
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
            .tint(MoleTheme.accent)
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("optimize.tasks_title").font(.system(size: 13, weight: .semibold))
                Spacer()
                UtilityBadge(title: "optimize.preview_ready", symbol: "checkmark")
            }
            .padding(16)
            Divider()
            if rows.isEmpty {
                Text("optimize.empty_output").foregroundStyle(MoleTheme.subtle).padding(16)
            } else {
                ForEach(rows) { row in
                    rowView(row)
                    Divider().padding(.leading, 16)
                }
            }
            if let output = viewModel.preview?.output, !output.isEmpty {
                Divider()
                DisclosureGroup("optimize.raw_output") {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("optimize.execute", role: .destructive) {
                    viewModel.requestConfirmation()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!viewModel.canConfirm)
            }
            .padding(14)
        }
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func rowView(_ row: OptimizePlanRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.status == .willRun ? "checkmark.circle" : "minus.circle")
                .foregroundStyle(row.status == .willRun ? MoleTheme.accent : MoleTheme.subtle)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.name).font(.system(size: 12, weight: .medium))
                if let reason = row.reason {
                    Text(verbatim: reason).font(.system(size: 10)).foregroundStyle(MoleTheme.subtle)
                }
            }
            Spacer(minLength: 8)
            if row.deletesFiles {
                Text("optimize.row_deletes_permanently")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            Text(row.status == .willRun ? LocalizedStringKey("optimize.row_will_run") : LocalizedStringKey("optimize.row_skipped"))
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
