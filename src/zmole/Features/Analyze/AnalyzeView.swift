import SwiftUI

@MainActor
struct AnalyzeView: View {
    @StateObject private var viewModel: AnalyzeViewModel
    @State private var selectedPath: String?
    @State private var search = ""
    @State private var sort: AnalyzeSort = .size

    init(viewModel: AnalyzeViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AnalyzeViewModel())
    }

    private var entries: [AnalyzeEntry] { viewModel.snapshot?.entries ?? [] }
    private var selected: AnalyzeEntry? { entries.first { $0.path == selectedPath } }
    private var visibleEntries: [AnalyzeEntry] {
        let filtered = entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return AnalyzeListOrder.sorted(filtered, by: sort)
    }

    var body: some View {
        VStack(spacing: 0) {
            UtilityToolbar(title: "analyze.title", subtitle: "analyze.read_only") {
                UtilityBadge(title: "analyze.read_only", symbol: "lock")
                Picker("analyze.sort", selection: $sort) {
                    Text("analyze.sort_size").tag(AnalyzeSort.size)
                    Text("analyze.sort_name").tag(AnalyzeSort.name)
                }
                .frame(width: 120)
                Button {
                    Task { await viewModel.refreshCurrent() }
                } label: { Label("analyze.refresh", systemImage: "arrow.clockwise") }
                .disabled(viewModel.isLoading)
            }
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("analyze.loading").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 18) {
                    UtilityNotice(title: "analyze.error_title", detail: error, isError: true)
                    if viewModel.canGoBack {
                        Button("analyze.back") { Task { await viewModel.goBack() } }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if viewModel.snapshot != nil {
                HStack(spacing: 0) {
                    directoryPane.frame(minWidth: 340)
                    Divider()
                    mapPane
                }
            } else {
                UtilityEmptyState(symbol: "internaldrive", title: "analyze.title", message: "analyze.start")
            }
        }
        .background(MoleTheme.background)
        .navigationTitle("sidebar.disk")
        .overlay(alignment: .top) {
            if viewModel.showBusyNotice {
                RecoverableBusyNotice().padding(16)
            }
        }
        .task {
            if viewModel.snapshot == nil, !viewModel.isLoading { await viewModel.loadOverview() }
        }
        .onChange(of: viewModel.snapshot?.path) { _ in
            selectedPath = nil
            search = ""
        }
    }

    private var crumbs: [(label: String, path: String)] {
        guard let path = viewModel.snapshot?.path else { return [] }
        let components = path.split(separator: "/").map(String.init)
        var result: [(String, String)] = [("analyze.root", "/")]
        var accumulated = ""
        for component in components {
            accumulated += "/" + component
            result.append((component, accumulated))
        }
        return result
    }

    private var directoryPane: some View {
        VStack(spacing: 0) {
            breadcrumb
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("analyze.filter", text: $search).textFieldStyle(.plain)
            }
            .padding(8)
            .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            List(selection: $selectedPath) {
                ForEach(visibleEntries) { entry in
                    entryRow(entry, depth: 0)
                    if entry.isDirectory, viewModel.isExpanded(entry), let children = viewModel.children(of: entry) {
                        ForEach(AnalyzeListOrder.sorted(children, by: sort)) { child in
                            entryRow(child, depth: 1)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                Text("analyze.current_total").foregroundStyle(.secondary)
                Spacer()
                Text(UtilityStyle.bytes(totalSize)).monospacedDigit()
            }
            .font(.system(size: 11)).padding(12)
        }
        .background(MoleTheme.background)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    Task { await viewModel.goBack() }
                } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canGoBack)
                .help("analyze.back")
                ForEach(Array(crumbs.enumerated()), id: \.offset) { _, crumb in
                    Button {
                        Task { await open(crumb.path) }
                    } label: {
                        if crumb.label == "analyze.root" {
                            Text("analyze.root").font(.system(size: 11, design: .monospaced))
                        } else {
                            Text(verbatim: crumb.label).font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .buttonStyle(.borderless)
                    if crumb.path != crumbs.last?.path {
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func open(_ path: String) async {
        if path == "/" {
            await viewModel.loadOverview()
        } else {
            await viewModel.open(path: path)
        }
    }

    private func entryRow(_ entry: AnalyzeEntry, depth: Int) -> some View {
        HStack(spacing: 9) {
            if entry.isDirectory {
                Button {
                    Task { await viewModel.toggleExpanded(entry) }
                } label: {
                    Image(systemName: viewModel.isExpanded(entry) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("analyze.expand")
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(entry.isDirectory ? Color.blue.opacity(0.75) : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.name).fontWeight(.medium).lineLimit(1)
                Text(UtilityStyle.bytes(max(0, entry.size)))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.isDirectory {
                Button { openDirectory(entry) } label: { Image(systemName: "arrow.right.circle") }
                    .buttonStyle(.borderless)
                    .help("analyze.open_directory")
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 6)
        .tag(entry.path)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openDirectory(entry) }
    }

    private var totalSize: Int64 {
        let total = entries.reduce(0.0) { $0 + Double(max(0, $1.size)) }
        return total >= Double(Int64.max) ? .max : Int64(total)
    }

    private var mapPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("analyze.space_map").fontWeight(.semibold)
                Text("analyze.area_hint").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            Divider()
            if entries.contains(where: { $0.size > 0 }) {
                GeometryReader { proxy in
                    let tiles = SpaceMapLayout.tiles(entries: entries, in: CGRect(origin: .zero, size: proxy.size))
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                            mapTile(tile, index: index)
                                .frame(width: max(0, tile.rect.width - 4), height: max(0, tile.rect.height - 4))
                                .position(x: tile.rect.midX, y: tile.rect.midY)
                        }
                    }
                }
                .padding(10)
            } else {
                UtilityEmptyState(symbol: "folder", title: "analyze.no_sizes", message: "analyze.no_sizes_detail")
            }
            Divider()
            inspector
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoleTheme.background.opacity(0.5))
    }

    private func mapTile(_ tile: SpaceMapTile, index: Int) -> some View {
        let colors: [Color] = [Color(red: 0.19, green: 0.48, blue: 0.47),
                               Color(red: 0.33, green: 0.40, blue: 0.64),
                               Color(red: 0.41, green: 0.46, blue: 0.51),
                               Color(red: 0.55, green: 0.40, blue: 0.31),
                               Color(red: 0.42, green: 0.35, blue: 0.56)]
        return Button {
            selectedPath = tile.entry.path
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 6).fill(colors[index % colors.count])
                if tile.rect.width > 80, tile.rect.height > 48 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: tile.entry.name).font(.system(size: 12, weight: .semibold))
                        Text(UtilityStyle.bytes(tile.entry.size)).font(.system(size: 11)).opacity(0.8)
                    }
                    .lineLimit(1).foregroundStyle(.white).padding(12)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(selectedPath == tile.entry.path ? 0.95 : 0.12),
                                  lineWidth: selectedPath == tile.entry.path ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: tile.entry.name + ", " + UtilityStyle.bytes(tile.entry.size)))
        .help(tile.entry.path + " · " + UtilityStyle.bytes(tile.entry.size))
    }

    private var inspector: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: selected?.name ?? "—").font(.system(size: 14, weight: .semibold))
                if let selected {
                    Text(verbatim: selected.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                } else {
                    Text("analyze.select_hint").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let selected {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(UtilityStyle.bytes(max(0, selected.size))).fontWeight(.semibold).monospacedDigit()
                    Text(shareText(for: selected)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                if selected.isDirectory {
                    Button("analyze.open_directory") { openDirectory(selected) }
                }
                Button("analyze.reveal") { viewModel.revealInFinder(selected) }
            }
        }
        .padding(18)
        .frame(minHeight: 96)
        .background(MoleTheme.surface)
    }

    private func shareText(for entry: AnalyzeEntry) -> String {
        guard let share = AnalyzeArea.share(of: entry.size, total: totalSize) else { return "—" }
        return String(format: "%.1f%%", share * 100)
    }

    private func openDirectory(_ entry: AnalyzeEntry) {
        guard entry.isDirectory else { return }
        Task { await viewModel.openDirectory(entry) }
    }
}
