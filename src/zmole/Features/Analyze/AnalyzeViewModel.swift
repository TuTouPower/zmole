import Combine
import Foundation

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

    let rootPath: String

    private let scanner: DiskScanning
    private let revealer: FileRevealing

    /// Upper bound for the per-session level cache so measuring a huge subtree
    /// cannot pin hundreds of megabytes of path strings.
    private static let maxCachedRecords = 4_000

    private var pathStack: [String] = []
    private var records: [String: LevelRecord] = [:]
    private var nextGeneration = 0
    private var pendingMeasurements: [MeasurementRequest] = []
    private var measurementWorker: Task<Void, Never>?
    private var workerToken = 0
    private var levelRevision = 0
    private var visibleCache: (revision: Int, search: String, sort: AnalyzeSort, entries: [DiskEntry])?
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
    func visibleEntries(search: String, sort: AnalyzeSort) -> [DiskEntry] {
        if let cache = visibleCache,
           cache.revision == levelRevision,
           cache.search == search,
           cache.sort == sort {
            return cache.entries
        }
        let entries = level?.entries ?? []
        let filtered = entries.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        }
        let sorted = AnalyzeListOrder.sorted(filtered, by: sort)
        visibleCache = (levelRevision, search, sort, sorted)
        return sorted
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
            touched.insert(path)
        }

        if let current = level?.path, touched.contains(current) {
            publish(records[current]!, path: current)
        }
    }

    private func invalidateSubtree(of path: String) {
        let prefix = LiveDiskScanner.directoryPrefix(path)
        records = records.filter { key, _ in
            key != path && !key.hasPrefix(prefix)
        }
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
