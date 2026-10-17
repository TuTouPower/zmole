import AppKit
import SwiftUI

enum UninstallAccessibility {
    static func description(for app: UninstallApp) -> String {
        [app.name, app.uninstallName, app.path, app.bundleID].joined(separator: " · ")
    }
}

@MainActor
struct UninstallView: View {
    @ObservedObject var viewModel: UninstallViewModel
    @State private var search = ""
    @State private var source = "all"
    @State private var sort: UninstallSort = .name

    private var sources: [String] {
        let values = Set(viewModel.listings.compactMap(\.source)).sorted()
        return ["all"] + values
    }

    private var visibleListings: [UninstallAppListing] {
        UninstallListFilter.visibleListings(viewModel.listings, search: search, source: source)
            .sorted { lhs, rhs in
                switch sort {
                case .name:
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                case .size:
                    return (lhs.sizeBytes ?? -1, lhs.name) > (rhs.sizeBytes ?? -1, rhs.name)
                case .source:
                    return (lhs.source ?? "", lhs.name) < (rhs.source ?? "", rhs.name)
                }
            }
    }

    private var selectedApps: [UninstallApp] {
        viewModel.selectedApps
    }

    private var knownSelectedBytes: Int64 {
        selectedApps.compactMap(\.sizeBytes).reduce(0, +)
    }

    private var hasUnknownSize: Bool {
        selectedApps.contains { $0.sizeBytes == nil }
    }

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "uninstall.confirm_title",
                    summary: "uninstall.confirm_summary",
                    detail: viewModel.confirmationDetail,
                    onConfirm: { Task { await viewModel.confirmExecution() } },
                    onCancel: { viewModel.cancelConfirmation() }
                )
            } else {
                mainContent
            }
        }
        .navigationTitle("sidebar.uninstall")
        .task { await viewModel.loadListIfNeeded() }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            MolePageHead(
                title: "uninstall.title",
                subtitle: "uninstall.subtitle"
            ) {
                listActionButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            controls
            if !viewModel.selectedPaths.isEmpty {
                selectionShelf
            }
            Divider()
            content
        }
    }

    /// Page action: re-list, or cancel whatever the page is currently doing.
    @ViewBuilder
    private var listActionButton: some View {
        if viewModel.isListing {
            Button("uninstall.cancel") { Task { await viewModel.cancelList() } }
        } else if viewModel.isPreviewing {
            Button("uninstall.cancel") { Task { await viewModel.cancelPreview() } }
        } else if viewModel.isExecuting {
            Button("uninstall.cancel") { Task { await viewModel.cancelExecution() } }
        } else {
            Button {
                Task { await viewModel.loadList() }
            } label: {
                Label("uninstall.refresh_list", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(MoleTheme.accent)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("uninstall.search", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("uninstall.search")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 260)
            Picker("uninstall.source", selection: $source) {
                ForEach(sources, id: \.self) { value in
                    Text(value == "all" ? LocalizedStringKey("uninstall.all_sources") : LocalizedStringKey(value))
                        .tag(value)
                }
            }
            .frame(width: 140)
            Picker("uninstall.sort", selection: $sort) {
                ForEach(UninstallSort.allCases) { item in
                    Text(item.titleKey).tag(item)
                }
            }
            .frame(width: 120)
            if let capturedAt = viewModel.listCapturedAt {
                Text("prewarm.scan_time \(capturedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MoleTheme.background)
    }

    private var selectionShelf: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(MoleTheme.accent)
            Text("uninstall.selected")
                .font(.system(size: 13, weight: .medium))
            if hasUnknownSize {
                Text("uninstall.size_unknown").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    Text(verbatim: UtilityStyle.bytes(knownSelectedBytes))
                        .font(.system(size: 12, design: .monospaced))
                    Text("uninstall.selected_total_app_estimate")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("uninstall.clear_selection") { viewModel.clearSelection() }
                .buttonStyle(.borderless)
            Button("uninstall.preview") { Task { await viewModel.previewUninstall() } }
                .buttonStyle(.borderedProminent)
                .tint(MoleTheme.accent)
                .disabled(!viewModel.canPreview)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(MoleTheme.selection)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isExecuting {
            VStack(spacing: 12) {
                ProgressView()
                Text("uninstall.executing").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isListing, viewModel.listings.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("uninstall.loading").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.listings.isEmpty {
            if viewModel.listWasCancelled {
                VStack(spacing: 14) {
                    UtilityNotice(title: "uninstall.list_cancelled", symbol: "exclamationmark.circle")
                    Button("uninstall.list_resume") { Task { await viewModel.loadList() } }
                        .buttonStyle(.borderedProminent)
                        .tint(MoleTheme.accent)
                }
                .frame(maxWidth: 480)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UtilityEmptyState(symbol: "square.stack.3d.up", title: "sidebar.uninstall", message: "uninstall.empty")
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                listPane
                Divider()
                detailPane
            }
            .overlay(alignment: .bottom) { resultPanel }
        }
    }

    private var listPane: some View {
        List {
            ForEach(visibleListings) { listing in
                listingRow(listing)
                    .listRowBackground(viewModel.focusedAppID == listing.path ? MoleTheme.surface2 : Color.clear)
            }
        }
        .listStyle(.inset)
        .frame(minWidth: 320)
    }

    private func listingRow(_ listing: UninstallAppListing) -> some View {
        HStack(spacing: 11) {
            Button {
                viewModel.toggleSelection(path: listing.path)
            } label: {
                Image(systemName: viewModel.selectedPaths.contains(listing.path) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(viewModel.selectedPaths.contains(listing.path) ? MoleTheme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(viewModel.selectedPaths.contains(listing.path) ? "uninstall.selected_state" : "uninstall.not_selected_state"))

            Button {
                viewModel.focus(path: listing.path)
            } label: {
                HStack(spacing: 11) {
                    // Icons load after the list is interactive; a placeholder
                    // keeps rendering from blocking on synchronous icon reads.
                    if let icon = viewModel.icon(forPath: listing.path) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 32, height: 32)
                    } else {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(MoleTheme.surface2)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(listing.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        HStack(spacing: 7) {
                            Text(verbatim: versionLine(listing))
                            Spacer(minLength: 0)
                            Text(verbatim: sizeLabel(listing))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityDescription(listing)))
        }
        .padding(.vertical, 6)
    }

    private func versionLine(_ listing: UninstallAppListing) -> String {
        let version = listing.version ?? String(localized: "uninstall.unknown")
        return String(localized: "uninstall.version_line") + " " + version
    }

    /// Unknown size never renders as zero: while the scan runs it reads as
    /// computing, afterwards as unknown.
    private func sizeLabel(_ listing: UninstallAppListing) -> String {
        if let size = listing.sizeText { return size }
        if viewModel.isListing { return String(localized: "uninstall.size_computing") }
        return String(localized: "uninstall.size_unknown")
    }

    private func accessibilityDescription(_ listing: UninstallAppListing) -> String {
        if let app = listing.uninstallApp {
            return UninstallAccessibility.description(for: app)
        }
        return [listing.name, listing.path].joined(separator: " · ")
    }

    private var detailPane: some View {
        Group {
            if let app = viewModel.focusedApp {
                detailContent(app)
            } else {
                Text("uninstall.detail.empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 360)
    }

    private func detailContent(_ app: UninstallApp) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    if let icon = viewModel.icon(for: app) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 52, height: 52)
                    } else {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(MoleTheme.surface2)
                            .frame(width: 52, height: 52)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        Text(verbatim: "\(String(localized: "uninstall.version_line")) \(app.version ?? String(localized: "uninstall.unknown"))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: app.sizeText ?? String(localized: "uninstall.size_unknown"))
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        Text("uninstall.app_size_estimate").font(.system(size: 9)).foregroundStyle(MoleTheme.subtle)
                    }
                }

                detailRow("uninstall.last_used", lastUsedText(app))
                detailRow("uninstall.path", app.path)
                detailRow("uninstall.bundle_id", app.bundleID)

                VStack(alignment: .leading, spacing: 6) {
                    Text("uninstall.files_title").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    if let paths = viewModel.relatedPaths(for: app) {
                        if paths.isEmpty {
                            Text("uninstall.files_none").font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            ForEach(paths, id: \.self) { path in
                                Text(verbatim: path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("uninstall.files_not_loaded").font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("uninstall.files_check") {
                                Task { await viewModel.loadRelatedFiles(for: app) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: MoleTheme.radiusMD))

                HStack(spacing: 8) {
                    Button {
                        viewModel.revealInFinder(app)
                    } label: {
                        Label("uninstall.reveal", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        viewModel.clearSelection()
                        viewModel.toggleSelection(app)
                        Task { await viewModel.previewUninstall() }
                    } label: {
                        Label("uninstall.trash", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(18)
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func lastUsedText(_ app: UninstallApp) -> String {
        guard let date = app.lastUsed else {
            return String(localized: "uninstall.unknown")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if viewModel.listWasCancelled {
            VStack(alignment: .leading, spacing: 8) {
                UtilityNotice(title: "uninstall.list_cancelled", symbol: "exclamationmark.circle")
                Button("uninstall.list_resume") { Task { await viewModel.loadList() } }
                    .buttonStyle(.bordered)
            }
            .padding(12)
        } else if viewModel.showBusyNotice {
            RecoverableBusyNotice()
                .padding(12)
        } else if let preview = viewModel.preview {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("uninstall.preview_result").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("uninstall.execute") { viewModel.requestConfirmation() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!viewModel.canConfirm)
                }
                Text(preview.apps.map(\.name).joined(separator: " · "))
                    .font(.system(size: 12))
                if !preview.output.isEmpty {
                    ScrollView(.vertical) {
                        Text(preview.output)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            }
            .padding(14)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        } else if let errorMessageKey = viewModel.errorMessageKey {
            UtilityNotice(
                title: LocalizedStringKey(errorMessageKey),
                detail: viewModel.executionSummary,
                isError: true
            )
            .padding(12)
        } else if let errorMessage = viewModel.errorMessage {
            UtilityNotice(title: "uninstall.error_title", detail: errorMessage, isError: true)
                .padding(12)
        } else if let listError = viewModel.listErrorMessage {
            UtilityNotice(title: "uninstall.error_title", detail: listError, isError: true)
                .padding(12)
        } else if let executionSummary = viewModel.executionSummary, !executionSummary.isEmpty {
            UtilityNotice(title: "uninstall.result", detail: executionSummary)
                .padding(12)
        }
    }
}

private enum UninstallSort: String, CaseIterable, Identifiable {
    case name
    case size
    case source

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .name: "uninstall.sort_name"
        case .size: "uninstall.sort_size"
        case .source: "uninstall.sort_source"
        }
    }
}
