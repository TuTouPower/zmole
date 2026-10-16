import XCTest
@testable import Zmole

@MainActor
final class DiskExplorerTests: XCTestCase {
    func testEnteringDirectoryAnalyzesThatPathOnly() async {
        let recorder = DiskCommandRecorder()
        let loader = AnalyzeSnapshotLoader { arguments in
            await recorder.record(arguments)
            return MoleCommandResult(stdout: Self.fixture(for: arguments.last), stderr: "", exitCode: 0)
        }
        let viewModel = AnalyzeViewModel(loader: loader)
        await viewModel.loadOverview()
        XCTAssertEqual(viewModel.snapshot?.path, "/")

        let applications = viewModel.snapshot?.entries.first { $0.name == "Applications" }
        await viewModel.openDirectory(try! XCTUnwrap(applications))

        let arguments = await recorder.arguments
        XCTAssertEqual(arguments, [["analyze", "--json"], ["analyze", "--json", "/Applications"]])
        XCTAssertEqual(viewModel.snapshot?.path, "/Applications")
        XCTAssertEqual(viewModel.snapshot?.entries.map(\.name), ["Safari.app"])
    }

    func testBreadcrumbJumpAnalyzesAncestorPath() async {
        let recorder = DiskCommandRecorder()
        let loader = AnalyzeSnapshotLoader { arguments in
            await recorder.record(arguments)
            return MoleCommandResult(stdout: Self.fixture(for: arguments.last), stderr: "", exitCode: 0)
        }
        let viewModel = AnalyzeViewModel(loader: loader)
        await viewModel.loadOverview()
        await viewModel.openDirectory(try! XCTUnwrap(viewModel.snapshot?.entries.first))
        await viewModel.open(path: "/")

        let arguments = await recorder.arguments
        XCTAssertEqual(arguments.last, ["analyze", "--json"])
        XCTAssertEqual(viewModel.snapshot?.path, "/")
    }

    func testExpandingDirectoryLoadsChildrenWithoutChangingCurrentLevel() async {
        let recorder = DiskCommandRecorder()
        let loader = AnalyzeSnapshotLoader { arguments in
            await recorder.record(arguments)
            return MoleCommandResult(stdout: Self.fixture(for: arguments.last), stderr: "", exitCode: 0)
        }
        let viewModel = AnalyzeViewModel(loader: loader)
        await viewModel.loadOverview()
        let applications = try! XCTUnwrap(viewModel.snapshot?.entries.first { $0.isDirectory })

        await viewModel.toggleExpanded(applications)

        XCTAssertTrue(viewModel.isExpanded(applications))
        XCTAssertEqual(viewModel.children(of: applications)?.map(\.name), ["Safari.app"])
        XCTAssertEqual(viewModel.snapshot?.path, "/")
    }

    func testAreaShareIsSizeOverCurrentLayerTotal() {
        XCTAssertEqual(AnalyzeArea.share(of: 25, total: 100), 0.25)
        XCTAssertNil(AnalyzeArea.share(of: 25, total: 0))
    }

    func testMapTilesCarryTheSamePathsAsCurrentLevelEntries() {
        let entries = [
            AnalyzeEntry(name: "Applications", path: "/Applications", size: 4_294_967_296, isDirectory: true),
            AnalyzeEntry(name: "readme.txt", path: "/readme.txt", size: 1_048_576, isDirectory: false)
        ]
        let tiles = SpaceMapLayout.tiles(entries: entries, in: CGRect(x: 0, y: 0, width: 400, height: 300))
        let tilePaths = Set(tiles.map(\.entry.path))
        let entryPaths = Set(entries.map(\.path))
        XCTAssertEqual(tilePaths, entryPaths)
    }

    func testNameSortReordersRowsWithoutChangingBytes() {
        let entries = [
            AnalyzeEntry(name: "Zeta", path: "/z", size: 10, isDirectory: true),
            AnalyzeEntry(name: "Alpha", path: "/a", size: 30, isDirectory: true)
        ]
        let byName = AnalyzeListOrder.sorted(entries, by: .name)
        XCTAssertEqual(byName.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(byName.map(\.size), [30, 10])

        let bySize = AnalyzeListOrder.sorted(entries, by: .size)
        XCTAssertEqual(bySize.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(Set(bySize.map(\.size)), Set([10, 30]))
    }

    func testRevealUsesEntryPath() async {
        let revealer = DiskRevealerSpy()
        let loader = AnalyzeSnapshotLoader { arguments in
            MoleCommandResult(stdout: Self.fixture(for: arguments.last), stderr: "", exitCode: 0)
        }
        let viewModel = AnalyzeViewModel(loader: loader, revealer: revealer)
        await viewModel.loadOverview()
        let leaf = try! XCTUnwrap(viewModel.snapshot?.entries.first { !$0.isDirectory })

        viewModel.revealInFinder(leaf)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let paths = await revealer.paths
        XCTAssertEqual(paths, [leaf.path])
    }

    func testDiskPageHasNoDeleteControl() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Analyze/AnalyzeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in ["delete", "trash", "trashItem", "removeItem", "clean("] {
            XCTAssertFalse(source.lowercased().contains(forbidden), "Disk page must stay read-only: \(forbidden)")
        }
    }

    nonisolated private static func fixture(for path: String?) -> String {
        switch path {
        case "/Applications":
            return """
            {"path":"/Applications","overview":false,"entries":[{"name":"Safari.app","path":"/Applications/Safari.app","size":1073741824,"is_dir":true}]}
            """
        default:
            return """
            {"path":"/","overview":true,"entries":[{"name":"Applications","path":"/Applications","size":4294967296,"is_dir":true},{"name":"readme.txt","path":"/readme.txt","size":1048576,"is_dir":false}]}
            """
        }
    }
}

private actor DiskCommandRecorder {
    private(set) var arguments: [[String]] = []
    func record(_ arguments: [String]) { self.arguments.append(arguments) }
}

private actor DiskRevealerSpy: FileRevealing {
    private(set) var paths: [String] = []
    func reveal(path: String) async { paths.append(path) }
}
