import Combine
import Foundation

/// One visible list row: a level entry or an inline-expanded descendant.
struct AnalyzeRow: Equatable, Sendable, Identifiable {
    let entry: DiskEntry
    let depth: Int
    /// Total of the row's immediate parent, used for the "% of parent" column.
    /// Nil while the parent's own size is still computing.
    let parentTotal: Int64?

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

    private let scanner: DiskScanning
    private let revealer: FileRevealing

    /// Upper bound for the per-session level cache so measuring a huge subtree
    /// cannot pin hundreds of megabytes of path strings.
    private static let maxCachedRecords = 4_000

    private var pathStack: [String] = []
    private var records: [String: LevelRecord] = [:]
    private var childCache: [String: [DiskEntry]] = [:]
    private var nextGeneration = 0
    private var pendingMeasurements: [MeasurementRequest] = []
    private var measurementWorker: Task<Void, Never>?
    private var workerToken = 0
    private var levelRevision = 0
    private var visibleRowsCache: (revision: Int, search: String, sort: AnalyzeSort, rows: [AnalyzeRow])?
    private var tilesCache: (revision: Int, size: CGSize, tiles: [SpaceMapTile])?

    private struct LevelRecord {
        var entries: [DiskEntry]
        /// Counted sum of the level: deduplicated direct files plus every
        /// measured child directory.
        var totalSize: Int64
        /// Direct-file part of the level, sealed at listing time.
        let filesTotal: Int64
        let generation: Int
        let deduplicator: HardLinkDeduplicator
    }

    private struct MeasurementRequest: Sendable {
        let parent: String
        let child: String
        let generation: Int
        let deduplicator: HardLinkDeduplicator
    }

    init(scanner: DiskScanning, root: String = "/", revealer: FileRevealing = LiveFileRevealer()) {
        self.scanner = scanner
        rootPath = root
        self.revealer = revealer
        pathStack = [root]
    }

    var currentPath: String? { level?.path }

    /// Cached filter+sort for the visible list, keyed by level revision so
    /// repeated body evaluations do not re-sort (ICU compare) the whole level.
    /// Expanded directories contribute their children as indented rows.
    func visibleRows(search: String, sort: AnalyzeSort) -> [AnalyzeRow] {
        if let cache = visibleRowsCache,
           cache.revision == levelRevision,
           cache.search == search,
           cache.sort == sort {
            return cache.rows
        }
        var rows: [AnalyzeRow] = []
        appendRows(from: level?.entries ?? [], depth: 0, parentTotal: level?.totalSize, into: &rows, search: search, sort: sort)
        visibleRowsCache = (levelRevision, search, sort, rows)
        return rows
    }

    private func appendRows(
        from entries: [DiskEntry],
        depth: Int,
        parentTotal: Int64?,
        into rows: inout [AnalyzeRow],
        search: String,
        sort: AnalyzeSort
    ) {
        for entry in AnalyzeListOrder.sorted(entries, by: sort) {
            if search.isEmpty || entry.name.localizedCaseInsensitiveContains(search) {
                rows.append(AnalyzeRow(entry: entry, depth: depth, parentTotal: parentTotal))
            }
            guard entry.isDirectory,
                  expandedPaths.contains(entry.path),
                  let children = childCache[entry.path] else { continue }
            appendRows(
                from: children,
                depth: depth + 1,
                parentTotal: entry.knownSize,
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

    /// Looks a row up in the current level or any inline-expanded run, so the
    /// inspector keeps working for nested rows.
    func entry(for path: String) -> DiskEntry? {
        if let entry = level?.entries.first(where: { $0.path == path }) {
            return entry
        }
        for entries in childCache.values {
            if let entry = entries.first(where: { $0.path == path }) {
                return entry
            }
        }
        return nil
    }

    /// Expands or collapses a directory inline. Expansion never navigates: the
    /// current level, selection and breadcrumb stay put. Children are listed on
    /// first expansion and then served from the session cache.
    func toggleExpanded(_ entry: DiskEntry) async {
        guard entry.isDirectory else { return }
        if expandedPaths.contains(entry.path) {
            expandedPaths.remove(entry.path)
            visibleRowsCache = nil
            return
        }
        if childCache[entry.path] == nil {
            do {
                let children = try await scanner.listDirectory(entry.path)
                // A background measurement may have filled the cache while the
                // listing was in flight; its entries carry real sizes and win.
                if childCache[entry.path] == nil {
                    childCache[entry.path] = children
                }
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

    private var wantsScanningState: Bool {
        isListing || measurementWorker != nil || !pendingMeasurements.isEmpty
    }

    private func refreshScanState() {
        let scanning = wantsScanningState
        if isScanning != scanning {
            isScanning = scanning
        }
    }

    /// Lists the scan root, reusing the session cache when present.
    func loadOverview() async {
        pathStack = [rootPath]
        canGoBack = false
        await showPath(rootPath)
    }

    /// Re-analyzes the current directory and its subtree, replacing the cached
    /// result for that subtree.
    func refreshCurrent() async {
        guard !isListing, let path = level?.path else { return }
        cancelMeasurements()
        invalidateSubtree(of: path)
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
        if let record = records[path] {
            publish(record, path: path)
            return
        }
        await list(path)
    }

    /// Lists one directory level immediately, then measures its subdirectories
    /// one after another in the background.
    private func list(_ path: String) async {
        nextGeneration += 1
        let generation = nextGeneration
        isListing = true
        refreshScanState()
        defer {
            isListing = false
            refreshScanState()
        }
        do {
            let entries = try await scanner.listDirectory(path)
            let deduplicator = HardLinkDeduplicator()
            let filesTotal = Self.countedFilesTotal(entries, deduplicator: deduplicator)
            let record = LevelRecord(
                entries: entries,
                totalSize: filesTotal,
                filesTotal: filesTotal,
                generation: generation,
                deduplicator: deduplicator
            )
            records[path] = record
            childCache[path] = entries
            publish(record, path: path)
            enqueueMeasurements(
                parent: path,
                entries: entries,
                generation: generation,
                deduplicator: deduplicator
            )
        } catch {
            errorMessageKey = error.localizationKey
            errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
            // Keep the previous level on screen; the error banner explains why
            // the requested directory could not be listed.
        }
    }

    private func publish(_ record: LevelRecord, path: String) {
        levelRevision += 1
        level = LevelState(path: path, entries: record.entries, totalSize: record.totalSize)
    }

    private func enqueueMeasurements(
        parent: String,
        entries: [DiskEntry],
        generation: Int,
        deduplicator: HardLinkDeduplicator
    ) {
        for entry in entries where entry.isDirectory && entry.value == .computing {
            pendingMeasurements.append(
                MeasurementRequest(
                    parent: parent,
                    child: entry.path,
                    generation: generation,
                    deduplicator: deduplicator
                )
            )
        }
        startMeasurementWorker()
    }

    private func startMeasurementWorker() {
        guard measurementWorker == nil else { return }
        workerToken += 1
        let token = workerToken
        measurementWorker = Task { @MainActor [weak self] in
            await self?.processMeasurements()
            guard let self, self.workerToken == token else { return }
            self.measurementWorker = nil
            self.refreshScanState()
        }
        refreshScanState()
    }

    private func cancelMeasurements() {
        measurementWorker?.cancel()
        measurementWorker = nil
        workerToken += 1
        pendingMeasurements.removeAll()
        refreshScanState()
    }

    /// Measures pending subdirectories with a small concurrency window so a
    /// level with dozens of children does not serialize its whole scan.
    private func processMeasurements() async {
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            let maxConcurrent = 3
            while let request = pendingMeasurements.first {
                pendingMeasurements.removeFirst()
                if Task.isCancelled { break }
                guard records[request.parent]?.generation == request.generation else { continue }
                if let existing = records[request.child], existing.generation >= request.generation {
                    // Already measured by an in-flight parent walk or a later
                    // list of that same path.
                    continue
                }
                if inFlight >= maxConcurrent {
                    await group.next()
                    inFlight -= 1
                }
                let scanner = self.scanner
                inFlight += 1
                group.addTask { [weak self] in
                    let result = await scanner.measureSubtree(
                        request.child,
                        deduplicator: request.deduplicator
                    )
                    guard let self else { return }
                    await self.applyMeasured(result, request: request)
                }
            }
            await group.waitForAll()
        }
    }

    private func applyMeasured(_ result: DiskScanResult, request: MeasurementRequest) {
        guard records[request.parent]?.generation == request.generation else { return }
        apply(result, parent: request.parent, generation: request.generation)
    }

    private func apply(_ result: DiskScanResult, parent: String, generation: Int) {
        guard var parentRecord = records[parent], parentRecord.generation == generation else {
            return
        }
        var touched: Set<String> = []

        let childValue: DiskEntryValue = result.isReadable ? .size(result.totalSize) : .unreadable
        if let index = parentRecord.entries.firstIndex(where: { $0.path == result.path }),
           parentRecord.entries[index].value != childValue {
            parentRecord.entries[index].value = childValue
        }
        parentRecord.totalSize = parentRecord.filesTotal + parentRecord.entries.reduce(0) { sum, entry in
            guard entry.isDirectory, let size = entry.knownSize else { return sum }
            return sum + size
        }
        records[parent] = parentRecord
        touched.insert(parent)

        for (path, scannedLevel) in result.levels {
            if let existing = records[path], existing.generation >= generation { continue }
            if records[path] == nil, records.count >= Self.maxCachedRecords { continue }
            records[path] = LevelRecord(
                entries: scannedLevel.entries,
                totalSize: scannedLevel.totalSize,
                filesTotal: scannedLevel.totalSize,
                generation: generation,
                deduplicator: parentRecord.deduplicator
            )
            childCache[path] = scannedLevel.entries
            touched.insert(path)
        }

        if let current = level?.path, touched.contains(current) {
            publish(records[current]!, path: current)
        } else if !touched.isDisjoint(with: expandedPaths) {
            // An expanded subtree got fresh sizes: rebuild the visible rows.
            levelRevision += 1
            visibleRowsCache = nil
            objectWillChange.send()
        }
    }

    private func invalidateSubtree(of path: String) {
        let prefix = LiveDiskScanner.directoryPrefix(path)
        records = records.filter { key, _ in
            key != path && !key.hasPrefix(prefix)
        }
        childCache = childCache.filter { key, _ in
            key != path && !key.hasPrefix(prefix)
        }
        expandedPaths = expandedPaths.filter { key in
            key != path && !key.hasPrefix(prefix)
        }
        visibleRowsCache = nil
    }

    private static func countedFilesTotal(
        _ entries: [DiskEntry],
        deduplicator: HardLinkDeduplicator
    ) -> Int64 {
        var total: Int64 = 0
        for entry in entries {
            guard let size = entry.knownSize else { continue }
            if let key = entry.linkKey {
                if deduplicator.markIfNew(key) { total += size }
            } else {
                total += size
            }
        }
        return total
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
