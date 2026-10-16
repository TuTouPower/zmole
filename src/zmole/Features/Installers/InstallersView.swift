import SwiftUI

@MainActor
struct InstallersView: View {
    @ObservedObject var viewModel: InstallersViewModel
    @State private var search = ""

    private var visibleCandidates: [InstallerCandidate] {
        viewModel.candidates.filter {
            search.isEmpty
                || $0.name.localizedCaseInsensitiveContains(search)
                || $0.source.localizedCaseInsensitiveContains(search)
                || $0.type.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "installers.confirm_title",
                    summary: "installers.confirm_summary",
                    detail: viewModel.confirmationDetail,
                    onConfirm: { Task { await viewModel.confirmRemoval() } },
                    onCancel: { viewModel.cancelConfirmation() }
                )
            } else {
                content
            }
        }
        .navigationTitle("sidebar.installers")
        .task {
            await viewModel.loadListIfNeeded()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                head
                statStrip
                UtilityNotice(title: "installers.trash_note", symbol: "trash")
                listCard
                failuresCard
                if viewModel.showBusyNotice {
                    RecoverableBusyNotice()
                }
                if let errorMessage = viewModel.errorMessage {
                    UtilityNotice(title: "installers.error_title", detail: errorMessage, isError: true)
                }
            }
            .padding(24)
        }
        .background(MoleTheme.background)
    }

    private var head: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("installers.eyebrow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MoleTheme.accentStrong)
                    .textCase(.uppercase)
                Text("installers.title").font(.system(size: 30, weight: .bold))
                Text("installers.subtitle").font(.system(size: 12)).foregroundStyle(MoleTheme.muted)
                if let capturedAt = viewModel.listCapturedAt {
                    Text("prewarm.scan_time \(capturedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.muted)
                }
            }
            Spacer()
            Button {
                Task { await viewModel.scan() }
            } label: {
                Label("installers.scan", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isListing || viewModel.isRemoving)
        }
    }

    private var statStrip: some View {
        HStack(spacing: 10) {
            statTile("installers.stat.found", "\(viewModel.candidates.count)")
            statTile("installers.stat.selected", "\(viewModel.selectedPaths.count)")
            statTile("installers.stat.size", ByteCountFormatter.string(fromByteCount: viewModel.selectedBytes, countStyle: .file))
            statTile("installers.stat.destination", String(localized: "installers.stat.trash"))
        }
    }

    private func statTile(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 10)).foregroundStyle(MoleTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusMD))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusMD).strokeBorder(MoleTheme.line))
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("installers.search", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 240)
                Spacer()
                Button("installers.select_all") { viewModel.selectAll() }
                    .buttonStyle(.borderless)
                Button("installers.clear_selection") { viewModel.clearSelection() }
                    .buttonStyle(.borderless)
            }
            .padding(14)
            Divider()

            if viewModel.isListing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("installers.listing").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if viewModel.candidates.isEmpty {
                UtilityEmptyState(symbol: "shippingbox", title: "installers.empty", message: "installers.empty_detail")
                    .frame(minHeight: 200)
            } else {
                ForEach(visibleCandidates) { candidate in
                    row(candidate)
                    Divider().padding(.leading, 16)
                }
            }

            if !viewModel.candidates.isEmpty {
                Divider()
                HStack {
                    Text("installers.action_footer").font(.system(size: 11)).foregroundStyle(MoleTheme.muted)
                    Spacer()
                    Button("installers.remove") { viewModel.requestConfirmation() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!viewModel.canConfirm || viewModel.isRemoving)
                }
                .padding(14)
            }
        }
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func row(_ candidate: InstallerCandidate) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleSelection(candidate)
            } label: {
                Image(systemName: viewModel.selectedPaths.contains(candidate.path) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(viewModel.selectedPaths.contains(candidate.path) ? MoleTheme.accent : .secondary)
            }
            .buttonStyle(.plain)
            Text(candidate.type)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MoleTheme.muted)
                .frame(width: 42, height: 26)
                .background(MoleTheme.surface3, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: candidate.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(verbatim: candidate.source).font(.system(size: 10)).foregroundStyle(MoleTheme.subtle)
            }
            Spacer(minLength: 8)
            Text(verbatim: candidate.sizeText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var failuresCard: some View {
        if !viewModel.failures.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("installers.failures_title").font(.system(size: 13, weight: .semibold))
                Text("installers.failures_body").font(.system(size: 11)).foregroundStyle(MoleTheme.muted)
                ForEach(viewModel.failures) { failure in
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: URL(fileURLWithPath: failure.path).lastPathComponent)
                            .font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 8)
                        Text(verbatim: failure.reason).font(.system(size: 11)).foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
            .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(Color.red.opacity(0.2)))
        }
    }
}
