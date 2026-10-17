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

    func testExpandingDirectoryShowsChildrenInlineWithoutChangingLevel() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "Applications", path: "/root/Applications", isDirectory: true, value: .computing),
            DiskEntry(name: "notes.txt", path: "/root/notes.txt", isDirectory: false, value: .size(50))
        ]
        scanner.listings["/root/Applications"] = [
            DiskEntry(name: "Safari.app", path: "/root/Applications/Safari.app", isDirectory: true, value: .computing)
        ]
        scanner.results["/root/Applications"] = Self.result(
            path: "/root/Applications", total: 300, files: [("Safari.app", 300)]
        )
        scanner.blockedMeasures.insert("/root/Applications")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        let applications = try XCTUnwrap(viewModel.level?.entries.first { $0.name == "Applications" })
        await viewModel.toggleExpanded(applications)

        XCTAssertEqual(viewModel.level?.path, "/root", "expansion must not navigate")
        XCTAssertTrue(viewModel.isExpanded(applications))
        let rows = viewModel.visibleRows(search: "", sort: .size)
        let child = try XCTUnwrap(rows.first { $0.entry.name == "Safari.app" })
        XCTAssertEqual(child.depth, 1)
        XCTAssertEqual(child.total, 50, "every row shares the current level total")
        XCTAssertEqual(scanner.listRequests, ["/root", "/root/Applications"])

        scanner.releaseMeasures()
        try await waitUntil {
            let refreshed = viewModel.visibleRows(search: "", sort: .size)
            let freshChild = refreshed.first { $0.entry.name == "Safari.app" }
            return freshChild?.entry.knownSize == 300 && freshChild?.total == 350
        }
    }

    func testCurrentLevelDirectChildrenSumToFullShare() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "Alpha", path: "/root/Alpha", isDirectory: true, value: .size(300)),
            DiskEntry(name: "Big", path: "/root/Big", isDirectory: true, value: .size(700)),
            DiskEntry(name: "notes.txt", path: "/root/notes.txt", isDirectory: false, value: .size(100))
        ]
        scanner.blockedMeasures.insert("/root/Alpha")
        scanner.blockedMeasures.insert("/root/Big")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        let rows = viewModel.visibleRows(search: "", sort: .size)
        let total = try XCTUnwrap(rows.first?.total)
        let shares = rows.compactMap { AnalyzeArea.share(of: $0.entry.knownSize, total: total) }
        XCTAssertEqual(shares.reduce(0, +), 1.0, accuracy: 0.0001)
        scanner.releaseMeasures()
    }

    func testCollapsingDirectoryHidesInlineChildren() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "Applications", path: "/root/Applications", isDirectory: true, value: .size(300)),
            DiskEntry(name: "notes.txt", path: "/root/notes.txt", isDirectory: false, value: .size(50))
        ]
        scanner.listings["/root/Applications"] = [
            DiskEntry(name: "Safari.app", path: "/root/Applications/Safari.app", isDirectory: true, value: .size(300))
        ]
        scanner.blockedMeasures.insert("/root/Applications")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        let applications = try XCTUnwrap(viewModel.level?.entries.first { $0.name == "Applications" })
        await viewModel.toggleExpanded(applications)
        XCTAssertEqual(viewModel.visibleRows(search: "", sort: .size).count, 3)

        await viewModel.toggleExpanded(applications)

        XCTAssertFalse(viewModel.isExpanded(applications))
        XCTAssertEqual(
            viewModel.visibleRows(search: "", sort: .size).map(\.entry.name),
            ["Applications", "notes.txt"]
        )
        scanner.releaseMeasures()
    }

    func testTogglingAFileDoesNotExpandIt() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "notes.txt", path: "/root/notes.txt", isDirectory: false, value: .size(50))
        ]
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        let file = try XCTUnwrap(viewModel.level?.entries.first)
        await viewModel.toggleExpanded(file)

        XCTAssertFalse(viewModel.isExpanded(file))
        XCTAssertEqual(viewModel.visibleRows(search: "", sort: .size).map(\.entry.name), ["notes.txt"])
        XCTAssertEqual(scanner.listRequests, ["/root"], "expanding a file must not list anything")
    }

    func testRefreshCurrentCollapsesExpandedSubtree() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .size(500))
        ]
        scanner.listings["/root/sub"] = [
            DiskEntry(name: "inside.txt", path: "/root/sub/inside.txt", isDirectory: false, value: .size(500))
        ]
        scanner.blockedMeasures.insert("/root/sub")
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        let sub = try XCTUnwrap(viewModel.level?.entries.first)
        await viewModel.toggleExpanded(sub)
        XCTAssertEqual(viewModel.visibleRows(search: "", sort: .size).count, 2)

        await viewModel.refreshCurrent()

        XCTAssertFalse(viewModel.isExpanded(sub), "re-analyzing clears the inline expansion")
        XCTAssertEqual(viewModel.visibleRows(search: "", sort: .size).map(\.entry.name), ["sub"])
        XCTAssertEqual(scanner.listRequests, ["/root", "/root/sub", "/root"])
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

    func testDiskListRowHasInlineDisclosureControl() throws {
        let source = try Self.analyzeSource("AnalyzeView.swift")
        let rowStart = try XCTUnwrap(source.range(of: "private func entryRow"))
        let rowEnd = try XCTUnwrap(source.range(of: "private func sizeText"))
        let rowSource = String(source[rowStart.lowerBound..<rowEnd.lowerBound])
        XCTAssertTrue(rowSource.contains("disclosureButton"), "rows must render the inline fold control")
        XCTAssertTrue(
            rowSource.contains("chevron.down") || source.contains("chevron.down"),
            "the fold control must show the expanded chevron"
        )
        XCTAssertTrue(source.contains("viewModel.toggleExpanded"), "the chevron toggles inline expansion")
        XCTAssertFalse(
            rowSource.contains("viewModel.openDirectory"),
            "the chevron must not navigate away from the current level"
        )
    }

    func testSplitHandleBindsDragGesture() throws {
        let source = try Self.analyzeSource("AnalyzeView.swift")
        XCTAssertTrue(source.contains("DragGesture"), "the divider must be draggable")
        XCTAssertTrue(source.contains("DiskSplitLayout.resized"), "the drag must resize the panes")
    }

    func testQueueWorkerConsumesRequestsEnqueuedWhileInFlightFinishes() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "A", path: "/root/A", isDirectory: true, value: .computing)
        ]
        scanner.listings["/other"] = [
            DiskEntry(name: "B", path: "/other/B", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/A")
        scanner.results["/root/A"] = Self.result(path: "/root/A", total: 100, files: [("A_file.txt", 100)])
        scanner.results["/other/B"] = Self.result(path: "/other/B", total: 200, files: [("B_file.txt", 200)])

        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        try await waitUntil { scanner.measureRequests.contains("/root/A") }

        await viewModel.openDirectory(DiskEntry(name: "other", path: "/other", isDirectory: true, value: .size(0)))

        scanner.releaseMeasures()

        try await waitUntil {
            viewModel.level?.entries.first { $0.name == "B" }?.knownSize == 200
        }
        XCTAssertFalse(viewModel.isScanning)
    }

    func testAncestorMeasurementCompletesChildrenListedLaterWithoutStallingOnGeneration() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/sub"] = [
            DiskEntry(name: "leaf", path: "/root/sub/leaf", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/sub")
        scanner.results["/root/sub"] = DiskScanResult(
            path: "/root/sub",
            totalSize: 420,
            isReadable: true,
            levels: [
                "/root/sub": DiskLevel(
                    entries: [
                        DiskEntry(name: "leaf", path: "/root/sub/leaf", isDirectory: true, value: .size(420))
                    ],
                    totalSize: 420
                )
            ]
        )
        let viewModel = AnalyzeViewModel(scanner: scanner, root: "/root")
        await viewModel.loadOverview()

        try await waitUntil { scanner.measureRequests.contains("/root/sub") }

        await viewModel.openDirectory(DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing))

        scanner.releaseMeasures()

        try await waitUntil {
            viewModel.level?.entries.first { $0.name == "leaf" }?.knownSize == 420
        }
        XCTAssertEqual(viewModel.level?.totalSize, 420)
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
