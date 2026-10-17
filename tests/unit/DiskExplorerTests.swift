import XCTest
@testable import Zmole

@MainActor
final class DiskExplorerTests: XCTestCase {
    func testListingAppearsBeforeDirectorySizesFinish() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "Gamma", path: "/root/Gamma", isDirectory: true, value: .computing),
            DiskEntry(name: "Beta", path: "/root/Beta", isDirectory: true, value: .computing),
            DiskEntry(name: "alpha.txt", path: "/root/alpha.txt", isDirectory: false, value: .size(100))
        ]
        scanner.results["/root/Gamma"] = Self.result(
            path: "/root/Gamma", total: 300, files: [("delta.log", 300)]
        )
        scanner.blockedMeasures.insert("/root/Beta")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")

        await viewModel.loadOverview()

        let entries = try XCTUnwrap(viewModel.level?.entries)
        XCTAssertEqual(entries.map(\.name), ["Gamma", "Beta", "alpha.txt"])
        XCTAssertEqual(entries.first { $0.name == "alpha.txt" }?.knownSize, 100)
        XCTAssertEqual(entries.first { $0.name == "Beta" }?.value, .computing)
        XCTAssertNil(entries.first { $0.name == "Beta" }?.knownSize)

        try await waitUntil { viewModel.level?.totalSize == 400 }
        let beta = try XCTUnwrap(viewModel.level?.entries.first { $0.name == "Beta" })
        XCTAssertEqual(beta.value, .computing, "the blocked sibling still computes")
        scanner.releaseMeasures()
    }

    func testComputingDirectoriesDrawNoAreaAndStayOutOfTheTotal() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "Pending", path: "/root/Pending", isDirectory: true, value: .computing),
            DiskEntry(name: "ready.bin", path: "/root/ready.bin", isDirectory: false, value: .size(50))
        ]
        scanner.blockedMeasures.insert("/root/Pending")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        XCTAssertEqual(viewModel.level?.totalSize, 50, "computing entries must not count")
        let entries = try XCTUnwrap(viewModel.level?.entries)
        let tiles = SpaceMapLayout.tiles(entries: entries, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(tiles.map(\.entry.name), ["ready.bin"])
        scanner.releaseMeasures()
    }

    func testCompletedLevelIsServedFromTheSessionCacheWithoutRelisting() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing)
        ]
        scanner.results["/root/sub"] = Self.result(
            path: "/root/sub", total: 500, files: [("inside.txt", 500)]
        )
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()
        try await waitUntil { viewModel.level?.entries.first?.knownSize == 500 }

        await viewModel.openDirectory(try XCTUnwrap(viewModel.level?.entries.first))

        XCTAssertEqual(viewModel.level?.path, "/root/sub")
        XCTAssertEqual(viewModel.level?.entries.map(\.name), ["inside.txt"])
        XCTAssertEqual(viewModel.level?.entries.first?.knownSize, 500)
        XCTAssertEqual(scanner.listRequests, ["/root"], "a cached level must not list again")
    }

    func testReanalyzeReplacesTheCachedSubtree() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/sub"] = [
            DiskEntry(name: "inside.txt", path: "/root/sub/inside.txt", isDirectory: false, value: .size(500))
        ]
        scanner.results["/root/sub"] = Self.result(
            path: "/root/sub", total: 500, files: [("inside.txt", 500)]
        )
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()
        try await waitUntil { viewModel.level?.entries.first?.knownSize == 500 }
        await viewModel.openDirectory(try XCTUnwrap(viewModel.level?.entries.first))

        scanner.listings["/root/sub"] = [
            DiskEntry(name: "inside.txt", path: "/root/sub/inside.txt", isDirectory: false, value: .size(900))
        ]
        await viewModel.refreshCurrent()

        XCTAssertEqual(viewModel.level?.entries.first?.knownSize, 900)
        XCTAssertEqual(scanner.listRequests, ["/root", "/root/sub"])
        XCTAssertEqual(viewModel.level?.totalSize, 900)
    }

    func testSiblingMeasurementsDoNotBlockListingAnotherDirectory() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "Alpha", path: "/root/Alpha", isDirectory: true, value: .computing),
            DiskEntry(name: "Beta", path: "/root/Beta", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/Beta"] = [
            DiskEntry(name: "beta.txt", path: "/root/Beta/beta.txt", isDirectory: false, value: .size(20))
        ]
        scanner.blockedMeasures.insert("/root/Alpha")
        scanner.results["/root/Beta"] = Self.result(
            path: "/root/Beta", total: 20, files: [("beta.txt", 20)]
        )
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        await viewModel.openDirectory(
            try XCTUnwrap(viewModel.level?.entries.first { $0.name == "Beta" })
        )

        XCTAssertEqual(viewModel.level?.path, "/root/Beta")
        XCTAssertEqual(viewModel.level?.entries.map(\.name), ["beta.txt"])
        XCTAssertEqual(scanner.listRequests, ["/root", "/root/Beta"])
        scanner.releaseMeasures()
    }

    func testNavigationBackToCachedLevelIsImmediate() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "Alpha", path: "/root/Alpha", isDirectory: true, value: .computing),
            DiskEntry(name: "Beta", path: "/root/Beta", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/Beta"] = []
        scanner.blockedMeasures.insert("/root/Alpha")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()
        await viewModel.openDirectory(
            try XCTUnwrap(viewModel.level?.entries.first { $0.name == "Beta" })
        )

        await viewModel.goBack()

        XCTAssertEqual(viewModel.level?.path, "/root")
        XCTAssertEqual(scanner.listRequests, ["/root", "/root/Beta"], "back must reuse the cache")
        scanner.releaseMeasures()
    }

    func testBackIsIgnoredWhileListing() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/sub"] = [
            DiskEntry(name: "inside.txt", path: "/root/sub/inside.txt", isDirectory: false, value: .size(10))
        ]
        scanner.blockedListings.insert("/root/sub")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        let openTask = Task { @MainActor in
            await viewModel.openDirectory(DiskEntry(
                name: "sub", path: "/root/sub", isDirectory: true, value: .computing
            ))
        }
        try await waitUntil { viewModel.isListing }
        await viewModel.goBack()
        XCTAssertEqual(viewModel.level?.path, "/root", "back during a listing is ignored")

        scanner.releaseListings()
        await openTask.value
        XCTAssertEqual(viewModel.level?.path, "/root/sub")
    }

    func testUnreadableDirectoryIsMarkedAndExcluded() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "secret", path: "/root/secret", isDirectory: true, value: .computing),
            DiskEntry(name: "file.bin", path: "/root/file.bin", isDirectory: false, value: .size(64))
        ]
        scanner.results["/root/secret"] = DiskScanResult(
            path: "/root/secret", totalSize: 0, isReadable: false, levels: [:]
        )
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()
        try await waitUntil { viewModel.level?.entries.first?.value == .unreadable }

        XCTAssertEqual(viewModel.level?.totalSize, 64, "unreadable entries must not count")
        XCTAssertNil(viewModel.level?.entries.first?.knownSize)
    }

    func testOtherDeviceDirectoryStaysOutOfTheParentTotal() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "volume", path: "/root/volume", isDirectory: true, value: .otherDevice),
            DiskEntry(name: "file.bin", path: "/root/file.bin", isDirectory: false, value: .size(64))
        ]
        scanner.listings["/root/volume"] = [
            DiskEntry(name: "mounted.bin", path: "/root/volume/mounted.bin", isDirectory: false, value: .size(900))
        ]
        scanner.results["/root/volume"] = Self.result(
            path: "/root/volume", total: 900, files: [("mounted.bin", 900)]
        )
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        XCTAssertEqual(viewModel.level?.totalSize, 64)
        XCTAssertEqual(scanner.measureRequests, [], "other-device directories are not measured with the parent")

        await viewModel.openDirectory(
            try XCTUnwrap(viewModel.level?.entries.first { $0.name == "volume" })
        )

        XCTAssertEqual(viewModel.level?.path, "/root/volume")
        XCTAssertEqual(viewModel.level?.totalSize, 900, "entering measures it on its own")
    }

    func testHardLinkedFilesCountOnceInTheLevelTotal() async throws {
        let key = HardLinkKey(device: 1, inode: 42)
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "a.bin", path: "/root/a.bin", isDirectory: false, value: .size(4096), linkKey: key),
            DiskEntry(name: "b.bin", path: "/root/b.bin", isDirectory: false, value: .size(4096), linkKey: key)
        ]
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        XCTAssertEqual(viewModel.level?.totalSize, 4096, "hard links count once per scan")
        XCTAssertEqual(viewModel.level?.entries.map(\.knownSize), [4096, 4096], "rows still show their own size")
    }

    func testSizeSortKeepsUnknownEntriesAfterKnownOnes() {
        let entries = [
            DiskEntry(name: "unknown", path: "/u", isDirectory: true, value: .computing),
            DiskEntry(name: "small", path: "/s", isDirectory: false, value: .size(10)),
            DiskEntry(name: "large", path: "/l", isDirectory: false, value: .size(99))
        ]

        let sorted = AnalyzeListOrder.sorted(entries, by: .size)

        XCTAssertEqual(sorted.map(\.name), ["large", "small", "unknown"])
    }

    func testShareAndBarFractionHandleBoundaries() {
        XCTAssertEqual(AnalyzeArea.share(of: 25, total: 100), 0.25)
        XCTAssertNil(AnalyzeArea.share(of: 25, total: 0))
        XCTAssertNil(AnalyzeArea.share(of: nil, total: 100))
        XCTAssertEqual(AnalyzeArea.share(of: 0, total: 100), 0)
        XCTAssertEqual(AnalyzeArea.barFraction(0), 0, "0% draws no bar")
        XCTAssertEqual(AnalyzeArea.barFraction(1), 1, "100% fills the bar")
        XCTAssertEqual(AnalyzeArea.barFraction(1.4), 1, "over 100% clamps")
        XCTAssertEqual(AnalyzeArea.barFraction(nil), 0)
    }

    func testSplitLayoutClampsBothPanes() {
        XCTAssertEqual(DiskSplitLayout.clamped(10, total: 1000), DiskSplitLayout.minimumPaneWidth)
        XCTAssertEqual(DiskSplitLayout.clamped(999, total: 1000), 1000 - DiskSplitLayout.minimumPaneWidth)
        XCTAssertEqual(DiskSplitLayout.resized(start: 500, translation: 600, total: 1000),
                       1000 - DiskSplitLayout.minimumPaneWidth)
        XCTAssertEqual(DiskSplitLayout.resized(start: 500, translation: -600, total: 1000),
                       DiskSplitLayout.minimumPaneWidth)
        XCTAssertEqual(DiskSplitLayout.defaultListWidth(total: 1000), 450)
    }

    func testOpeningAFileDoesNotEnterIt() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "readme.txt", path: "/root/readme.txt", isDirectory: false, value: .size(10))
        ]
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        await viewModel.openDirectory(try XCTUnwrap(viewModel.level?.entries.first))

        XCTAssertEqual(viewModel.level?.path, "/root")
        XCTAssertEqual(scanner.listRequests, ["/root"], "files are not enterable")
    }

    func testBreadcrumbJumpReturnsToCachedAncestor() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/sub"] = [
            DiskEntry(name: "deep", path: "/root/sub/deep", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/sub/deep"] = []
        scanner.results["/root/sub"] = DiskScanResult(
            path: "/root/sub",
            totalSize: 0,
            isReadable: true,
            levels: [
                "/root/sub": DiskLevel(
                    entries: [
                        DiskEntry(name: "deep", path: "/root/sub/deep", isDirectory: true, value: .size(0))
                    ],
                    totalSize: 0
                )
            ]
        )
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()
        try await waitUntil { viewModel.level?.entries.first?.value == .size(0) }
        await viewModel.openDirectory(
            try XCTUnwrap(viewModel.level?.entries.first { $0.name == "sub" })
        )
        await viewModel.openDirectory(
            try XCTUnwrap(viewModel.level?.entries.first { $0.name == "deep" })
        )
        XCTAssertEqual(viewModel.level?.path, "/root/sub/deep")

        await viewModel.open(path: "/root/sub")

        XCTAssertEqual(viewModel.level?.path, "/root/sub", "breadcrumb jump pops the stack")
        XCTAssertTrue(viewModel.canGoBack)
        await viewModel.open(path: "/root")
        XCTAssertEqual(viewModel.level?.path, "/root")
        XCTAssertFalse(viewModel.canGoBack)
        XCTAssertEqual(scanner.listRequests, ["/root", "/root/sub/deep"])
    }

    func testNameSortOrdersRowsAndKeepsTheirSizes() {
        let entries = [
            DiskEntry(name: "Zeta", path: "/z", isDirectory: true, value: .size(10)),
            DiskEntry(name: "Alpha", path: "/a", isDirectory: true, value: .size(30)),
            DiskEntry(name: "Beta", path: "/b", isDirectory: false, value: .computing)
        ]

        let byName = AnalyzeListOrder.sorted(entries, by: .name)

        XCTAssertEqual(byName.map(\.name), ["Alpha", "Beta", "Zeta"])
        XCTAssertEqual(byName.map(\.knownSize), [30, nil, 10])

        let bySize = AnalyzeListOrder.sorted(entries, by: .size)
        XCTAssertEqual(bySize.map(\.name), ["Alpha", "Zeta", "Beta"])
    }

    func testListingFailureShowsErrorAndStillAllowsGoingBack() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing)
        ]
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        await viewModel.openDirectory(DiskEntry(
            name: "sub", path: "/root/sub", isDirectory: true, value: .computing
        ))

        // A failed listing keeps the previous level on screen and shows the
        // error banner instead of blanking the whole browse state.
        XCTAssertEqual(viewModel.level?.path, "/root")
        XCTAssertNotNil(viewModel.errorMessageKey)
        XCTAssertTrue(viewModel.canGoBack)

        await viewModel.goBack()
        XCTAssertEqual(viewModel.level?.path, "/root")
        XCTAssertNil(viewModel.errorMessageKey)
    }

    func testRevealForwardsTheEntryPath() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "readme.txt", path: "/root/readme.txt", isDirectory: false, value: .size(10))
        ]
        let revealer = DiskRevealerSpy()
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root", revealer: revealer)
        await viewModel.loadOverview()

        viewModel.revealInFinder(try XCTUnwrap(viewModel.level?.entries.first))
        for _ in 0..<200 {
            if await revealer.paths == ["/root/readme.txt"] { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let paths = await revealer.paths
        XCTAssertEqual(paths, ["/root/readme.txt"])
    }

    func testDiskSourcesDoNotRunMoleCommands() throws {
        for file in ["AnalyzeView.swift", "AnalyzeViewModel.swift", "DiskScanner.swift"] {
            let source = try Self.analyzeSource(file)
            for forbidden in ["MoleBridge", "MoleProcess", "\"analyze\"", "Process("] {
                XCTAssertFalse(
                    source.contains(forbidden),
                    "\(file) must not run mole commands: \(forbidden)"
                )
            }
        }
        let assembly = try Self.assemblySource()
        XCTAssertTrue(
            assembly.contains("AnalyzeViewModel(scanner: LiveDiskScanner(), root: \"/\")"),
            "production assembly must drive the disk page from the in-app scanner"
        )
        XCTAssertTrue(
            assembly.contains("scanner: DemoDiskScanner(state: configuration.state)"),
            "demo assembly must drive the disk page from the in-memory scanner"
        )
    }

    func testDiskPageHasNoDeleteControl() throws {
        let source = try Self.analyzeSource("AnalyzeView.swift").lowercased()
        for forbidden in ["delete", "trash", "removeItem", "clean("] {
            XCTAssertFalse(source.contains(forbidden), "Disk page must stay read-only: \(forbidden)")
        }
    }

    func testDiskListRowDropsOpenButtonAndKeepsDoubleClickEntry() throws {
        let source = try Self.analyzeSource("AnalyzeView.swift")
        let rowStart = try XCTUnwrap(source.range(of: "private func entryRow"))
        let rowEnd = try XCTUnwrap(source.range(of: "private func sizeText"))
        let rowSource = String(source[rowStart.lowerBound..<rowEnd.lowerBound])
        XCTAssertTrue(rowSource.contains(".onTapGesture(count: 2)"), "double-click enters directories")
        XCTAssertFalse(
            rowSource.contains("analyze.open_directory"),
            "the row must not keep the separate open-directory button"
        )
        XCTAssertTrue(
            source.contains(".onTapGesture(count: 2) { openDirectory(tile.entry) }"),
            "double-clicking a map tile enters directories"
        )
    }

    func testSplitHandleBindsDragGesture() throws {
        let source = try Self.analyzeSource("AnalyzeView.swift")
        XCTAssertTrue(source.contains("DragGesture"), "the divider must be draggable")
        XCTAssertTrue(source.contains("DiskSplitLayout.resized"), "the drag must resize the panes")
    }

    nonisolated private static func analyzeSource(_ file: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Analyze/\(file)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    nonisolated private static func assemblySource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/App/AppDependencies.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func result(
        path: String,
        total: Int64,
        files: [(String, Int64)]
    ) -> DiskScanResult {
        let entries = files.map { name, size in
            DiskEntry(
                name: name,
                path: path.hasSuffix("/") ? path + name : path + "/" + name,
                isDirectory: false,
                value: .size(size)
            )
        }
        return DiskScanResult(
            path: path,
            totalSize: total,
            isReadable: true,
            levels: [path: DiskLevel(entries: entries, totalSize: total)]
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }
}

private actor DiskRevealerSpy: FileRevealing {
    private(set) var paths: [String] = []
    func reveal(path: String) async { paths.append(path) }
}

/// Thread-safe in-memory directory source with controllable blocking.
final class FakeDiskScanner: DiskScanning, @unchecked Sendable {
    var listings: [String: [DiskEntry]] = [:]
    var results: [String: DiskScanResult] = [:]
    var blockedMeasures: Set<String> = []
    var blockedListings: Set<String> = []

    private let lock = NSLock()
    private var recordedListRequests: [String] = []
    private var recordedMeasureRequests: [String] = []
    private var listingContinuations: [String: [CheckedContinuation<[DiskEntry], Error>]] = [:]
    private var measureContinuations: [String: [CheckedContinuation<DiskScanResult, Never>]] = [:]

    var listRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedListRequests
    }

    var measureRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedMeasureRequests
    }

    func listDirectory(_ path: String) async throws -> [DiskEntry] {
        lock.lock()
        recordedListRequests.append(path)
        let blocked = blockedListings.contains(path)
        let listing = listings[path]
        lock.unlock()

        if blocked {
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                listingContinuations[path, default: []].append(continuation)
                lock.unlock()
            }
        }
        guard let listing else { throw DiskScanError.unreadable(path) }
        return listing
    }

    func measureSubtree(_ path: String, deduplicator: HardLinkDeduplicator) async -> DiskScanResult {
        lock.lock()
        recordedMeasureRequests.append(path)
        let blocked = blockedMeasures.contains(path)
        let result = results[path]
        lock.unlock()

        if blocked {
            return await withCheckedContinuation { continuation in
                lock.lock()
                measureContinuations[path, default: []].append(continuation)
                lock.unlock()
            }
        }
        return result ?? DiskScanResult(path: path, totalSize: 0, isReadable: false, levels: [:])
    }

    func releaseListings() {
        lock.lock()
        let continuations = listingContinuations
        listingContinuations = [:]
        blockedListings = []
        let pending = listings
        lock.unlock()
        for (path, waiting) in continuations {
            for continuation in waiting {
                if let listing = pending[path] {
                    continuation.resume(returning: listing)
                } else {
                    continuation.resume(throwing: DiskScanError.unreadable(path))
                }
            }
        }
    }

    func releaseMeasures() {
        lock.lock()
        let continuations = measureContinuations
        measureContinuations = [:]
        blockedMeasures = []
        let pending = results
        lock.unlock()
        for (path, waiting) in continuations {
            for continuation in waiting {
                let result = pending[path]
                    ?? DiskScanResult(path: path, totalSize: 0, isReadable: false, levels: [:])
                continuation.resume(returning: result)
            }
        }
    }
}
