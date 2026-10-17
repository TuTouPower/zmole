import SwiftUI

enum CleanViewCopy {
    static let executionNoteKey = "clean.execution_note"
}

@MainActor
struct CleanView: View {
    @ObservedObject var viewModel: CleanViewModel
    @ObservedObject var whitelistViewModel: WhitelistViewModel
    var onOpenWhitelist: () -> Void = {}
    @State private var protectErrorKey: String?
    @State private var protectErrorDetail: String?

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "clean.confirm_title",
                    summary: "clean.confirm_summary",
                    detail: viewModel.confirmationDetail,
                    onConfirm: { Task { await viewModel.confirmExecution() } },
                    onCancel: { viewModel.cancelConfirmation() }
                )
            } else {
                content
            }
        }
        .navigationTitle("sidebar.clean")
        .task {
            if whitelistViewModel.document == nil { whitelistViewModel.load() }
            viewModel.adoptPrewarmPreviewIfAvailable()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                head
                statStrip
                HStack(alignment: .top, spacing: 14) {
                    listCard
                    protectionCard
                }
                resultNotices
            }
            .padding(24)
        }
        .background(MoleTheme.background)
    }

    private var head: some View {
        MolePageHead(eyebrow: "clean.eyebrow", title: "clean.title", subtitle: "clean.subtitle") {
            if viewModel.isPreviewing {
                Button("clean.cancel") { Task { await viewModel.cancelPreview() } }
            } else if viewModel.isExecuting {
                Button("clean.cancel") { Task { await viewModel.cancelExecution() } }
            } else {
                Button {
                    Task { await viewModel.previewClean() }
                } label: {
                    Label("clean.preview", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(MoleTheme.accent)
                .disabled(viewModel.isConfirmationPresented)
            }
            if let capturedAt = viewModel.previewCapturedAt {
                Text("prewarm.scan_time \(capturedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.muted)
            }
        }
    }

    private var statStrip: some View {
        HStack(spacing: 10) {
            MoleStatTile(value: viewModel.preview?.reclaimText ?? "—", label: "clean.stat.reclaimable")
            MoleStatTile(value: "\(viewModel.preview?.sections.count ?? 0)", label: "clean.stat.categories")
            MoleStatTile(value: "\(viewModel.preview?.entries.count ?? 0)", label: "clean.stat.items")
            MoleStatTile(value: String(localized: "clean.stat.trash"), label: "clean.stat.destination")
        }
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("clean.list.title").font(.system(size: 13, weight: .semibold))
                    Text("clean.list.subtitle").font(.system(size: 10)).foregroundStyle(MoleTheme.subtle)
                }
                Spacer()
            }
            .padding(16)
            Divider()

            if viewModel.isPreviewing {
                scanningState
            } else if viewModel.isExecuting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("clean.executing").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if let preview = viewModel.preview {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(preview.sections) { section in
                        sectionHeader(section)
                        ForEach(section.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            } else {
                UtilityEmptyState(symbol: "sparkles", title: "clean.empty", message: "clean.preview_hint")
                    .frame(minHeight: 200)
            }

            if let preview = viewModel.preview, !viewModel.isPreviewing {
                Divider()
                HStack {
                    Text("clean.action.footer").font(.system(size: 11)).foregroundStyle(MoleTheme.muted)
                    Spacer()
                    Button("clean.execute") { viewModel.requestConfirmation() }
                        .buttonStyle(.borderedProminent)
                        .tint(MoleTheme.accent)
                        .disabled(!viewModel.canConfirm)
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private var scanningState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("clean.scanning").font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 7) {
                Text("clean.stage.current").font(.system(size: 10)).foregroundStyle(MoleTheme.subtle)
                if let stage = viewModel.currentStage {
                    if let key = stage.localizedKey {
                        Text(LocalizedStringKey(key)).font(.system(size: 12, weight: .medium))
                    } else {
                        Text(verbatim: stage.raw).font(.system(size: 12, weight: .medium))
                    }
                } else {
                    Text("clean.stage.unknown").font(.system(size: 12)).foregroundStyle(MoleTheme.subtle)
                }
            }
            Text("clean.scan_hint").font(.system(size: 10)).foregroundStyle(MoleTheme.subtle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
    }

    private func sectionHeader(_ section: CleanPreviewSection) -> some View {
        HStack {
            Text(verbatim: section.name)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(MoleTheme.subtle)
            Spacer()
            Text(verbatim: section.reclaimText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MoleTheme.subtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(MoleTheme.surface2)
    }

    private func entryRow(_ entry: CleanPreviewEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: entry.itemNote == nil ? "doc" : "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(MoleTheme.muted)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let note = entry.itemNote {
                        Text(verbatim: note).font(.system(size: 9)).foregroundStyle(MoleTheme.subtle)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: entry.sizeText ?? String(localized: "status.unknown"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Button {
                    protect(entry)
                } label: {
                    Label("clean.protect", systemImage: "shield")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("clean.protect")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            Divider().padding(.leading, 16)
        }
    }

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("clean.protection.title").font(.system(size: 13, weight: .semibold))
            Text("clean.protection.body")
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.muted)
            Divider()
            HStack {
                Text("clean.protection.count").font(.system(size: 11)).foregroundStyle(MoleTheme.muted)
                Spacer()
                Text(verbatim: "\(whitelistViewModel.patterns.count)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            Button("clean.protection.manage") { onOpenWhitelist() }
            Divider()
            Text(LocalizedStringKey(CleanViewCopy.executionNoteKey))
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.subtle)
        }
        .padding(18)
        .frame(width: 300, alignment: .topLeading)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    @ViewBuilder
    private var resultNotices: some View {
        if viewModel.showBusyNotice {
            RecoverableBusyNotice()
        }
        if let errorMessageKey = viewModel.errorMessageKey {
            UtilityNotice(
                title: LocalizedStringKey(errorMessageKey),
                detail: viewModel.executionSummary,
                isError: true
            )
        } else if let errorMessage = viewModel.errorMessage {
            UtilityNotice(title: "clean.error_title", detail: errorMessage, isError: true)
        }
        if let executionSummary = viewModel.executionSummary,
           !executionSummary.isEmpty,
           viewModel.result?.status == .succeeded {
            UtilityNotice(title: "clean.result", detail: executionSummary, symbol: "checkmark.circle")
        }
        if let protectErrorKey {
            UtilityNotice(
                title: LocalizedStringKey(protectErrorKey),
                detail: protectErrorDetail,
                isError: true
            )
        }
    }

    private func protect(_ entry: CleanPreviewEntry) {
        whitelistViewModel.newPattern = entry.path
        guard whitelistViewModel.addPattern() else {
            reflectProtectFailure()
            return
        }
        whitelistViewModel.save()
        reflectProtectFailure()
    }

    private func reflectProtectFailure() {
        if let key = whitelistViewModel.errorMessageKey {
            protectErrorKey = key
            protectErrorDetail = nil
        } else if let message = whitelistViewModel.errorMessage {
            protectErrorKey = "clean.protect_failed"
            protectErrorDetail = message
        } else {
            protectErrorKey = nil
            protectErrorDetail = nil
        }
    }
}
