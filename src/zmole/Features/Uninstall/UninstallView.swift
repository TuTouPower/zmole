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
    @State private var expandedID: String?

    private var sources: [String] {
        let values = Set(viewModel.apps.compactMap(\.source)).sorted()
        return ["all"] + values
    }

    private var visibleApps: [UninstallApp] {
        viewModel.apps
            .filter { source == "all" || $0.source == source }
            .filter {
                search.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(search)
                    || $0.bundleID.localizedCaseInsensitiveContains(search)
                    || $0.path.localizedCaseInsensitiveContains(search)
            }
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
        viewModel.apps.filter { viewModel.selectedIDs.contains($0.id) }
    }

    private var knownSelectedBytes: Int64 {
        selectedApps.compactMap(\.sizeBytes).reduce(0, +)
    }

    private var hasUnknownSize: Bool {
        selectedApps.contains { $0.sizeBytes == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            if !viewModel.selectedIDs.isEmpty {
                selectionShelf
            }
            Divider()
            content
        }
        .navigationTitle("software.uninstall")
        .task {
            await viewModel.loadListIfNeeded()
        }
        .toolbar {
            ToolbarItem {
                if viewModel.isListing {
                    Button("uninstall.cancel") { Task { await viewModel.cancelList() } }
                } else if viewModel.isPreviewing {
                    Button("uninstall.cancel") { Task { await viewModel.cancelPreview() } }
                } else if viewModel.isExecuting {
                    Button("uninstall.cancel") { Task { await viewModel.cancelExecution() } }
                } else {
                    Button("uninstall.refresh") { Task { await viewModel.loadList() } }
                }
            }
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
            .background(UtilityStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 7))
            Picker("uninstall.source", selection: $source) {
                ForEach(sources, id: \.self) { value in
                    Text(value == "all" ? LocalizedStringKey("uninstall.all_sources") : LocalizedStringKey(value))
                        .tag(value)
                }
            }
            .frame(width: 130)
            Picker("uninstall.sort", selection: $sort) {
                ForEach(UninstallSort.allCases) { item in
                    Text(item.titleKey).tag(item)
                }
            }
            .frame(width: 120)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(UtilityStyle.background)
    }

    private var selectionShelf: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(UtilityStyle.accent)
            Text("uninstall.selected")
                .font(.system(size: 13, weight: .medium))
            if hasUnknownSize {
                Text("uninstall.size_unknown")
                    .foregroundStyle(.secondary)
            } else {
                Text(UtilityStyle.bytes(knownSelectedBytes))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("uninstall.clear_selection") {
                for app in selectedApps { viewModel.toggleSelection(app) }
            }
            .buttonStyle(.borderless)
            Button("uninstall.preview") {
                Task { await viewModel.previewUninstall() }
            }
            .buttonStyle(.borderedProminent)
            .tint(UtilityStyle.accent)
            .disabled(!viewModel.canPreview)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(UtilityStyle.selection)
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
        } else if viewModel.isListing {
            VStack(spacing: 12) {
                ProgressView()
                Text("uninstall.loading").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.apps.isEmpty {
            UtilityEmptyState(symbol: "square.stack.3d.up", title: "software.uninstall", message: "uninstall.empty")
        } else {
            List {
                ForEach(visibleApps) { app in
                    appRow(app)
                }
            }
            .listStyle(.inset)
            .overlay(alignment: .bottom) { resultPanel }
        }
    }

    private func appRow(_ app: UninstallApp) -> some View {
        VStack(spacing: 0) {
            Button {
                viewModel.toggleSelection(app)
            } label: {
                HStack(spacing: 11) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Image(systemName: viewModel.selectedIDs.contains(app.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(viewModel.selectedIDs.contains(app.id) ? UtilityStyle.accent : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        HStack(spacing: 7) {
                            Text(verbatim: app.source ?? String(localized: "uninstall.source_unknown"))
                            Text(verbatim: app.size ?? String(localized: "uninstall.size_unknown"))
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button {
                        expandedID = expandedID == app.id ? nil : app.id
                    } label: {
                        Image(systemName: expandedID == app.id ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help("uninstall.details")
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: UninstallAccessibility.description(for: app)))
            .accessibilityValue(
                Text(viewModel.selectedIDs.contains(app.id) ? "uninstall.selected_state" : "uninstall.not_selected_state")
            )

            if expandedID == app.id {
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.uninstallName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(app.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(app.bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.leading, 80)
                .padding(.bottom, 9)
            }
        }
        .listRowBackground(viewModel.selectedIDs.contains(app.id) ? UtilityStyle.selection : UtilityStyle.surface)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let preview = viewModel.preview {
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
                    .frame(maxHeight: 140)
                }
            }
            .padding(14)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        } else if let errorMessageKey = viewModel.errorMessageKey {
            UtilityNotice(title: LocalizedStringKey(errorMessageKey), isError: true)
                .padding(12)
        } else if let errorMessage = viewModel.errorMessage {
            UtilityNotice(title: "uninstall.error_title", detail: errorMessage, isError: true)
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
