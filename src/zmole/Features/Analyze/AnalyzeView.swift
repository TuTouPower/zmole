import SwiftUI

@MainActor
struct AnalyzeView: View {
    @StateObject private var viewModel: AnalyzeViewModel
    @State private var selectedPath: String?
    @State private var search = ""

    init(viewModel: AnalyzeViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AnalyzeViewModel())
    }

    private var entries: [AnalyzeEntry] { viewModel.snapshot?.entries ?? [] }
    private var selected: AnalyzeEntry? { entries.first { $0.path == selectedPath } }
    private var filtered: [AnalyzeEntry] {
        entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.size == $1.size ? $0.name < $1.name : $0.size > $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            UtilityToolbar(title: "analyze.title", subtitle: "analyze.read_only") {
                UtilityBadge(title: "analyze.read_only", symbol: "lock")
                Button {
                    Task { await viewModel.loadOverview() }
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
            } else if let snapshot = viewModel.snapshot {
                HStack(spacing: 0) {
                    directoryPane(snapshot: snapshot).frame(width: 276)
                    Divider()
                    mapPane
                }
            } else {
                UtilityEmptyState(symbol: "square.grid.2x2", title: "analyze.title", message: "analyze.start")
            }
        }
        .background(UtilityStyle.surface)
        .task {
            if viewModel.snapshot == nil, !viewModel.isLoading { await viewModel.loadOverview() }
        }
        .onChange(of: viewModel.snapshot?.path) { _ in
            selectedPath = nil
            search = ""
        }
    }

    private func directoryPane(snapshot: AnalyzeSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.goBack() }
                } label: { Image(systemName: "chevron.left") }
                .disabled(!viewModel.canGoBack)
                .help("analyze.back")
                .accessibilityLabel("analyze.back")
                Text(verbatim: snapshot.path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(12)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("analyze.filter", text: $search).textFieldStyle(.plain)
            }
            .padding(8)
            .background(UtilityStyle.surface, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            List(selection: $selectedPath) {
                ForEach(filtered) { entry in
                    HStack(spacing: 9) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(entry.isDirectory ? Color.blue.opacity(0.75) : .secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: entry.name).fontWeight(.medium).lineLimit(1)
                            Text(UtilityStyle.bytes(max(0, entry.size)))
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if entry.isDirectory {
                            Button { open(entry) } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.borderless)
                                .help("analyze.open_directory")
                                .accessibilityLabel(Text("analyze.open_directory") + Text(" ") + Text(verbatim: entry.name))
                        }
                    }
                    .padding(.vertical, 6)
                    .tag(entry.path)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { open(entry) }
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
        .background(UtilityStyle.background)
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
        .background(UtilityStyle.background.opacity(0.5))
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
                    let denominator = entries.reduce(0.0) { $0 + Double(max(0, $1.size)) }
                    Text(denominator > 0 ? String(format: "%.1f%%", Double(max(0, selected.size)) / denominator * 100) : "—")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                if selected.isDirectory {
                    Button("analyze.open_directory") { open(selected) }
                }
            }
        }
        .padding(18)
        .frame(minHeight: 96)
        .background(UtilityStyle.surface)
    }

    private func open(_ entry: AnalyzeEntry) {
        guard entry.isDirectory else { return }
        Task { await viewModel.openDirectory(entry) }
    }
}
