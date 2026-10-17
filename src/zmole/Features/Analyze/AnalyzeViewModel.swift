import Combine
import Foundation

/// One visible list row: a level entry or an inline-expanded descendant.
struct AnalyzeRow: Equatable, Sendable, Identifiable {
    let entry: DiskEntry
    let depth: Int
    /// Total of the directory currently being browsed. Every row uses the same
    /// denominator, including inline-expanded descendants, so direct children
    /// of the current level sum to 100%.
    let total: Int64?

    var id: String { entry.path }
}

@MainActor
final class AnalyzeViewModel: ObservableObject {
    struct LevelState: Equatable, Sendable {
        let path: String
        var entries: [DiskEntry]
        var totalSize: Int64
    }

    @Published private(set) var level: LevelState?
    @Published private(set) var isListing = false
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var canGoBack = false
    /// Directories expanded inline in the left list (paths, not navigation).
    @Published private(set) var expandedPaths: Set<String> = []

    let rootPath: String
    let session: DiskMeasurementSession

    private let revealer: FileRevealing
    private var pathStack: [String] = []
    private var levelRevision = 0
    private var visibleRowsCache: (revision: Int, search: String, sort: AnalyzeSort, rows: [AnalyzeRow])?
    private var tilesCache: (revision: Int, size: CGSize, tiles: [SpaceMapTile])?
    private var cancellables: Set<AnyCancellable> = []

    init(
        scanner: DiskScanning,
        root: String = "/",
        revealer: FileRevealing = LiveFileRevealer(),
        session: DiskMeasurementSession? = nil
    ) {
        self.rootPath = root
        self.revealer = revealer
        let activeSession = session ?? DiskMeasurementSession(scanner: scanner, root: root)
        self.session = activeSession
        self.pathStack = [root]

        bindSession()
    }

    private func bindSession() {
        session.$isScanning
            .sink { [weak self] scanning in
                guard let self else { return }
                self.isScanning = scanning || self.isListing
            }
            .store(in: &cancellables)

        session.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncWithSession()
                }
            }
            .store(in: &cancellables)
    }

    private func syncWithSession() {
        guard let current = level?.path, let record = session.levelRecord(for: current) else {
            return
        }
        if level?.entries != record.entries || level?.totalSize != record.totalSize {
            publish(record)
        } else if !expandedPaths.isEmpty {
            levelRevision += 1
            visibleRowsCache = nil
            tilesCache = nil
            objectWillChange.send()
        }
    }

    var currentPath: String? { level?.path }

    /// Cached filter+sort for the visible list, keyed by level revision so
    /// repeated body evaluations do not re-sort (ICU compare) the whole level.
    func visibleRows(search: String, sort: AnalyzeSort) -> [AnalyzeRow] {
        if let cache = visibleRowsCache,
           cache.revision == levelRevision,
           cache.search == search,
           cache.sort == sort {
            return cache.rows
        }
        var rows: [AnalyzeRow] = []
        appendRows(
            from: level?.entries ?? [],
            depth: 0,
            total: level?.totalSize,
            into: &rows,
            search: search,
            sort: sort
        )
        visibleRowsCache = (levelRevision, search, sort, rows)
        return rows
    }

    private func appendRows(
        from entries: [DiskEntry],
        depth: Int,
        total: Int64?,
        into rows: inout [AnalyzeRow],
        search: String,
        sort: AnalyzeSort
    ) {
        for entry in AnalyzeListOrder.sorted(entries, by: sort) {
            if search.isEmpty || entry.name.localizedCaseInsensitiveContains(search) {
                rows.append(AnalyzeRow(entry: entry, depth: depth, total: total))
            }
            guard entry.isDirectory,
                  expandedPaths.contains(entry.path),
                  let children = session.cachedEntries(for: entry.path) else { continue }
            appendRows(
                from: children,
                depth: depth + 1,
                total: total,
                into: &rows,
                search: search,
                sort: sort
            )
        }
    }

    /// The inline-expanded state of a row's disclosure control.
    func isExpanded(_ entry: DiskEntry) -> Bool {
        entry.isDirectory && expandedPaths.contains(entry.path)
    }

    /// Looks a row up in the current level or any inline-expanded run.
    func entry(for path: String) -> DiskEntry? {
        if let entry = level?.entries.first(where: { $0.path == path }) {
            return entry
        }
        for expandedPath in expandedPaths {
            if let children = session.cachedEntries(for: expandedPath),
               let entry = children.first(where: { $0.path == path }) {
                return entry
            }
        }
        return nil
    }

    /// Expands or collapses a directory inline.
    func toggleExpanded(_ entry: DiskEntry) async {
        guard entry.isDirectory else { return }
        if expandedPaths.contains(entry.path) {
            expandedPaths.remove(entry.path)
            visibleRowsCache = nil
            return
        }
        if session.cachedEntries(for: entry.path) == nil {
            do {
                _ = try await session.listDirectory(entry.path)
            } catch {
                errorMessageKey = error.localizationKey
                errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
                return
            }
        }
        expandedPaths.insert(entry.path)
        visibleRowsCache = nil
    }

    /// Cached space-map layout, keyed by level revision and pane size.
    func spaceMapTiles(size: CGSize) -> [SpaceMapTile] {
        guard let level else { return [] }
        if let cache = tilesCache,
           cache.revision == levelRevision,
           cache.size == size {
            return cache.tiles
        }
        let tiles = SpaceMapLayout.tiles(
            entries: level.entries,
            in: CGRect(origin: .zero, size: size)
        )
        tilesCache = (levelRevision, size, tiles)
        return tiles
    }

    /// Lists the scan root, reusing the session cache when present.
    func loadOverview() async {
        pathStack = [rootPath]
        canGoBack = false
        await showPath(rootPath)
    }

    /// Re-analyzes the current directory and its subtree.
    func refreshCurrent() async {
        guard !isListing, let path = level?.path else { return }
        session.reanalyze(path: path)
        let prefix = LiveDiskScanner.directoryPrefix(path)
        expandedPaths = expandedPaths.filter { key in
            key != path && !key.hasPrefix(prefix)
        }
        visibleRowsCache = nil
        await list(path)
    }

    func openDirectory(_ entry: DiskEntry) async {
        guard entry.isDirectory, !isListing else { return }
        pathStack.append(entry.path)
        canGoBack = pathStack.count > 1
        await showPath(entry.path)
    }

    /// Breadcrumb jump back to an ancestor path already on the stack.
    func open(path: String) async {
        guard !isListing, let index = pathStack.firstIndex(of: path) else { return }
        if index == pathStack.count - 1 {
            await showPath(path)
            return
        }
        pathStack.removeSubrange((index + 1)...)
        canGoBack = pathStack.count > 1
        await showPath(path)
    }

    func goBack() async {
        guard pathStack.count > 1, !isListing else { return }
        pathStack.removeLast()
        canGoBack = pathStack.count > 1
        await showPath(pathStack[pathStack.count - 1])
    }

    func revealInFinder(_ entry: DiskEntry) {
        Task { await revealer.reveal(path: entry.path) }
    }

    private func showPath(_ path: String) async {
        errorMessage = nil
        errorMessageKey = nil
        if let record = session.levelRecord(for: path) {
            publish(record)
            return
        }
        await list(path)
    }

    private func list(_ path: String) async {
        isListing = true
        isScanning = true
        defer {
            isListing = false
            isScanning = session.isScanning
        }
        do {
            let entries = try await session.listDirectory(path)
            if let record = session.levelRecord(for: path) {
                publish(record)
            } else {
                levelRevision += 1
                level = LevelState(path: path, entries: entries, totalSize: 0)
            }
        } catch {
            errorMessageKey = error.localizationKey
            errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
        }
    }

    private func publish(_ record: DiskMeasurementSession.LevelRecord) {
        levelRevision += 1
        level = LevelState(path: record.path, entries: record.entries, totalSize: record.totalSize)
        visibleRowsCache = nil
        tilesCache = nil
    }
}

enum AnalyzeSort: String, CaseIterable, Identifiable, Sendable {
    case size
    case name

    var id: Self { self }
}

enum AnalyzeListOrder {
    static func sorted(_ entries: [DiskEntry], by sort: AnalyzeSort) -> [DiskEntry] {
        switch sort {
        case .size:
            return entries.sorted { lhs, rhs in
                switch (lhs.knownSize, rhs.knownSize) {
                case let (left?, right?):
                    if left == right {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
        case .name:
            return entries.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
}

enum AnalyzeArea {
    /// Share of one entry within the current layer total. Nil when the layer
    /// total is zero or the entry size is still unknown.
    static func share(of size: Int64?, total: Int64) -> Double? {
        guard total > 0, let size else { return nil }
        return Double(max(0, size)) / Double(total)
    }

    /// Bar length for a share: 0% draws nothing, over 100% clamps to full.
    static func barFraction(_ share: Double?) -> Double {
        guard let share else { return 0 }
        return min(1, max(0, share))
    }
}
