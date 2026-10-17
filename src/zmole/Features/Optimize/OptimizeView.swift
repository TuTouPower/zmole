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
        .task {
            viewModel.adoptBackgroundResultIfAvailable()
            viewModel.refreshIfNeeded()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            MolePageHead(
                title: "optimize.title",
                subtitle: "optimize.subtitle"
            ) {
                refreshOrCancelButton
                if let capturedAt = viewModel.previewCapturedAt {
                    Text("prewarm.scan_time \(capturedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.muted)
                }
            }

            UtilityNotice(title: "optimize.permanent_note", symbol: "exclamationmark.triangle", isError: true)
            UtilityNotice(title: "optimize.scan_note", symbol: "arrow.triangle.2.circlepath", isInfo: true)

            HStack {
                Button("optimize.whitelist") { onOpenSettings() }
                    .buttonStyle(.bordered)
                Spacer()
            }

            if viewModel.isRefreshing {
                UtilityBusyState(title: "optimize.refreshing")
                Spacer()
            } else if viewModel.isExecuting {
                UtilityBusyState(title: "optimize.executing")
                Spacer()
            } else if viewModel.preview != nil {
                planCard
            } else if viewModel.scanFailed {
                VStack(spacing: 12) {
                    UtilityNotice(title: "optimize.scan_failed", symbol: "exclamationmark.triangle", isError: true)
                    Button("optimize.refresh") { viewModel.refreshMaintenance() }
                        .buttonStyle(.bordered)
                }
                .frame(minHeight: 200)
                Spacer()
            } else {
                UtilityEmptyState(symbol: "wrench.and.screwdriver", title: "optimize.empty", message: "optimize.empty_hint")
                    .frame(minHeight: 200)
                Spacer()
            }

            if viewModel.showBusyNotice {
                RecoverableBusyNotice()
            }
            if viewModel.scanFailed, viewModel.preview != nil {
                UtilityNotice(title: "optimize.scan_failed", symbol: "exclamationmark.triangle", isError: true)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MoleTheme.background)
    }

    /// Page action: refresh, or cancel whatever the page is currently doing.
    @ViewBuilder
    private var refreshOrCancelButton: some View {
        if viewModel.isRefreshing {
            Button("optimize.cancel") { Task { await viewModel.cancelRefresh() } }
        } else if viewModel.isExecuting {
            Button("optimize.cancel") { Task { await viewModel.cancelExecution() } }
        } else {
            Button {
                viewModel.refreshMaintenance()
            } label: {
                Label("optimize.refresh", systemImage: "arrow.clockwise")
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
                UtilityBadge(title: "optimize.scan_ready", symbol: "checkmark")
            }
            .padding(16)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
