import AppKit
import SwiftUI

enum DiskSplitLayout {
    static let minimumPaneWidth: CGFloat = 320
    static let handleWidth: CGFloat = 11

    static func defaultListWidth(total: CGFloat) -> CGFloat {
        clamped(total * 0.45, total: total)
    }

    static func clamped(_ width: CGFloat, total: CGFloat) -> CGFloat {
        let maximum = max(minimumPaneWidth, total - minimumPaneWidth)
        return min(max(width, minimumPaneWidth), maximum)
    }

    static func resized(start: CGFloat, translation: CGFloat, total: CGFloat) -> CGFloat {
        clamped(start + translation, total: total)
    }
}

@MainActor
struct AnalyzeView: View {
    @StateObject private var viewModel: AnalyzeViewModel
    @State private var selectedPath: String?
    @State private var search = ""
    @State private var sort: AnalyzeSort = .size
    @State private var storedListWidth: CGFloat?
    @State private var dragStartWidth: CGFloat?

    init(viewModel: AnalyzeViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AnalyzeViewModel(scanner: LiveDiskScanner()))
    }

    private var entries: [DiskEntry] { viewModel.level?.entries ?? [] }
    private var selected: DiskEntry? { selectedPath.flatMap { viewModel.entry(for: $0) } }
    private var visibleRows: [AnalyzeRow] {
        viewModel.visibleRows(search: search, sort: sort)
    }

    var body: some View {
        VStack(spacing: 0) {
            MolePageHead(
                title: "analyze.title",
                subtitle: "analyze.read_only"
            ) {
                Button("analyze.back") { Task { await viewModel.goBack() } }
                    .disabled(!viewModel.canGoBack)
                Button {
                    Task { await viewModel.refreshCurrent() }
                } label: {
                    Label("analyze.rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(MoleTheme.accent)
                .disabled(viewModel.isListing || viewModel.level == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            content
        }
        .background(MoleTheme.background)
        .navigationTitle("sidebar.disk")
        .task {
            if viewModel.level == nil, !viewModel.isListing { await viewModel.loadOverview() }
        }
        .onChange(of: viewModel.currentPath) { _ in
            selectedPath = nil
            search = ""
        }
    }

    @ViewBuilder
    private var content: some View {
        if let level = viewModel.level {
            VStack(spacing: 0) {
                if let errorKey = viewModel.errorMessageKey {
                    UtilityNotice(title: LocalizedStringKey(errorKey), isError: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                } else if let error = viewModel.errorMessage {
                    UtilityNotice(title: "analyze.error_title", detail: error, isError: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }
                splitPanes(level: level)
            }
        } else if viewModel.isListing {
            VStack(spacing: 12) {
                ProgressView()
                Text("analyze.loading").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorKey = viewModel.errorMessageKey {
            VStack(spacing: 18) {
                UtilityNotice(title: LocalizedStringKey(errorKey), isError: true)
                if viewModel.canGoBack {
                    Button("analyze.back") { Task { await viewModel.goBack() } }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 18) {
                UtilityNotice(title: "analyze.error_title", detail: error, isError: true)
                if viewModel.canGoBack {
                    Button("analyze.back") { Task { await viewModel.goBack() } }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            UtilityEmptyState(symbol: "internaldrive", title: "analyze.title", message: "analyze.start")
        }
    }

    private func splitPanes(level: AnalyzeViewModel.LevelState) -> some View {
        GeometryReader { proxy in
            let listWidth = DiskSplitLayout.clamped(
                storedListWidth ?? DiskSplitLayout.defaultListWidth(total: proxy.size.width),
                total: proxy.size.width
            )
            HStack(spacing: 0) {
                directoryPane(level: level).frame(width: listWidth)
                resizeHandle(total: proxy.size.width, current: listWidth)
                mapPane(level: level).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resizeHandle(total: CGFloat, current: CGFloat) -> some View {
        ZStack {
            Color.clear
            Rectangle().fill(UtilityStyle.separator).frame(width: 1)
        }
        .frame(width: DiskSplitLayout.handleWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStartWidth ?? current
                    if dragStartWidth == nil { dragStartWidth = start }
                    storedListWidth = DiskSplitLayout.resized(
                        start: start,
                        translation: value.translation.width,
                        total: total
                    )
                }
                .onEnded { _ in dragStartWidth = nil }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityLabel(Text("analyze.resize"))
    }

    private var crumbs: [(label: String, path: String)] {
        guard let path = viewModel.level?.path else { return [] }
        let root = viewModel.rootPath
        var result: [(String, String)] = [("analyze.root", root)]
        guard path != root else { return result }
        let remainder = path.hasPrefix(root)
            ? String(path.dropFirst(root == "/" ? 1 : root.count))
            : path
        var accumulated = root
        for component in remainder.split(separator: "/") {
            accumulated = accumulated == "/"
                ? "/" + component
                : accumulated + "/" + component
            result.append((String(component), accumulated))
        }
        return result
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
                        Task { await viewModel.open(path: crumb.path) }
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

    private func directoryPane(level: AnalyzeViewModel.LevelState) -> some View {
        VStack(spacing: 0) {
            breadcrumb
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("analyze.filter", text: $search).textFieldStyle(.plain)
                Picker("analyze.sort", selection: $sort) {
                    Text("analyze.sort_size").tag(AnalyzeSort.size)
                    Text("analyze.sort_name").tag(AnalyzeSort.name)
                }
                .frame(width: 110)
                .controlSize(.small)
            }
            .padding(8)
            .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            columnHeader
            List(selection: $selectedPath) {
                ForEach(visibleRows) { row in
                    entryRow(row)
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack(spacing: 8) {
                Text("analyze.current_total").foregroundStyle(.secondary)
                if level.entries.contains(where: { $0.value == .computing }) {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Text(UtilityStyle.bytes(level.totalSize)).monospacedDigit()
            }
            .font(.system(size: 11)).padding(12)
        }
        .background(MoleTheme.background)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("analyze.sort_name")
            Spacer(minLength: 8)
            Text("analyze.column_share").frame(width: 108, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func entryRow(_ row: AnalyzeRow) -> some View {
        HStack(spacing: 8) {
            disclosureButton(row)
            Image(systemName: row.entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 15))
                .foregroundStyle(row.entry.isDirectory ? Color.blue.opacity(0.75) : .secondary)
                .accessibilityHidden(true)
            Text(verbatim: row.entry.name).fontWeight(.medium).lineLimit(1)
            sizeText(for: row.entry)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer(minLength: 8)
            percentCell(row.entry, total: row.total)
                .frame(width: 108, alignment: .trailing)
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .padding(.vertical, 5)
        .tag(row.entry.path)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openDirectory(row.entry) }
    }

    /// Inline fold control: expands the directory's children in place without
    /// navigating. Files get an invisible spacer so names stay aligned.
    private func disclosureButton(_ row: AnalyzeRow) -> some View {
        Button {
            Task { await viewModel.toggleExpanded(row.entry) }
        } label: {
            Image(systemName: viewModel.isExpanded(row.entry) ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 18)
        }
        .buttonStyle(.borderless)
        .opacity(row.entry.isDirectory ? 1 : 0)
        .disabled(!row.entry.isDirectory)
        .help(LocalizedStringKey(viewModel.isExpanded(row.entry) ? "analyze.collapse" : "analyze.expand"))
        .accessibilityLabel(
            Text(LocalizedStringKey(viewModel.isExpanded(row.entry) ? "analyze.collapse" : "analyze.expand"))
        )
    }

    private func sizeText(for entry: DiskEntry) -> Text {
        switch entry.value {
        case .size(let bytes):
            return Text(UtilityStyle.bytes(max(0, bytes))).monospacedDigit()
        case .computing:
            return Text("analyze.computing")
        case .unreadable:
            return Text("analyze.unscanned")
        case .otherDevice:
            return Text("analyze.other_volume")
        }
    }

    @ViewBuilder
    private func percentCell(_ entry: DiskEntry, total: Int64?) -> some View {
        if let total, let share = AnalyzeArea.share(of: entry.knownSize, total: total) {
            let fraction = AnalyzeArea.barFraction(share)
            HStack(spacing: 6) {
                Capsule()
                    .fill(UtilityStyle.selection)
                    .frame(width: 52, height: 5)
                    .overlay(alignment: .leading) {
                        if fraction > 0 {
                            Capsule()
                                .fill(UtilityStyle.accent)
                                .frame(width: 52 * CGFloat(fraction))
                        }
                    }
                    .accessibilityHidden(true)
                Text(String(format: "%.1f%%", min(1, share) * 100))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        } else {
            Text(verbatim: "—")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func mapPane(level: AnalyzeViewModel.LevelState) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("analyze.space_map").fontWeight(.semibold)
                Text("analyze.area_hint").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            Divider()
            let drawable = level.entries.filter { ($0.knownSize ?? 0) > 0 }
            if drawable.isEmpty {
                UtilityEmptyState(symbol: "folder", title: "analyze.no_sizes", message: "analyze.no_sizes_detail")
            } else {
                GeometryReader { proxy in
                    let tiles = viewModel.spaceMapTiles(size: proxy.size)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                            mapTile(tile, index: index)
                                .frame(width: max(0, tile.rect.width - 4), height: max(0, tile.rect.height - 4))
                                .position(x: tile.rect.midX, y: tile.rect.midY)
                        }
                    }
                }
                .padding(10)
            }
            Divider()
            inspector(level: level)
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
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 6).fill(colors[index % colors.count])
            if tile.rect.width > 80, tile.rect.height > 48 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tile.entry.name).font(.system(size: 12, weight: .semibold))
                    if let size = tile.entry.knownSize {
                        Text(UtilityStyle.bytes(size)).font(.system(size: 11)).opacity(0.8)
                    }
                }
                .lineLimit(1).foregroundStyle(.white).padding(12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(selectedPath == tile.entry.path ? 0.95 : 0.12),
                              lineWidth: selectedPath == tile.entry.path ? 3 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) { openDirectory(tile.entry) }
        .onTapGesture(count: 1) { selectedPath = tile.entry.path }
        .accessibilityLabel(Text(verbatim: tile.entry.name + ", " + UtilityStyle.bytes(tile.entry.knownSize ?? 0)))
        .help(tile.entry.path + " · " + UtilityStyle.bytes(tile.entry.knownSize ?? 0))
    }

    private func inspector(level: AnalyzeViewModel.LevelState) -> some View {
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
                    sizeText(for: selected).fontWeight(.semibold)
                    Text(shareText(for: selected, total: level.totalSize))
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
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

    private func shareText(for entry: DiskEntry, total: Int64) -> String {
        guard let share = AnalyzeArea.share(of: entry.knownSize, total: total) else { return "—" }
        return String(format: "%.1f%%", min(1, share) * 100)
    }

    private func openDirectory(_ entry: DiskEntry) {
        guard entry.isDirectory else { return }
        Task { await viewModel.openDirectory(entry) }
    }
}
