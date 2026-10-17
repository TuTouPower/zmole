import XCTest
@testable import Zmole

@MainActor
final class UninstallDetailTests: XCTestCase {
    func testConfirmingBatchUsesOnlySelectedUninstallNamesAndConfirmationInput() async {
        let process = DetailProcessSpy()
        let viewModel = makeViewModel(process: process)

        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps
        viewModel.toggleSelection(apps[0])
        viewModel.toggleSelection(apps[1])
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await process.invocations
        XCTAssertEqual(invocations.count, 1, "the confirmation must execute directly, without a preview process")
        XCTAssertEqual(invocations[0].arguments, ["uninstall", "Alpha App", "Beta Tool"])
        XCTAssertEqual(invocations[0].stdin, Data("y\n".utf8))
    }

    func testFocusAndSelectionAreIndependentOfEachOther() async {
        let viewModel = makeViewModel(process: DetailProcessSpy())
        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps

        viewModel.toggleSelection(apps[0])
        viewModel.focus(path: apps[1].path)

        XCTAssertEqual(viewModel.focusedAppID, apps[1].id)
        XCTAssertEqual(viewModel.selectedPaths, [apps[0].id])
        XCTAssertEqual(viewModel.focusedApp?.path, apps[1].path)
    }

    func testMissingVersionAndLastUsedStayUnknown() async {
        let viewModel = makeViewModel(process: DetailProcessSpy())
        await viewModel.loadListIfNeeded()

        let app = viewModel.apps[0]
        XCTAssertNil(app.version)
        XCTAssertNil(app.lastUsed)
    }

    func testVersionAndLastUsedComeFromTheListScan() async {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let viewModel = makeViewModel(
            process: DetailProcessSpy(),
            alphaVersion: "1.2.3",
            alphaLastUsed: capturedAt
        )
        await viewModel.loadListIfNeeded()

        XCTAssertEqual(viewModel.apps[0].version, "1.2.3")
        XCTAssertEqual(viewModel.apps[0].lastUsed, capturedAt)
    }

    func testRelatedPathsOnlyComeFromThatAppsDryRun() async {
        let process = DetailProcessSpy(
            dryRunOutput: "Files to be removed:\n  /Applications/Alpha.app\n  /Users/example/Library/Caches/com.example.alpha\n"
        )
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()
        let app = viewModel.apps[0]

        XCTAssertNil(viewModel.relatedPaths(for: app))

        await viewModel.loadRelatedFiles(for: app)
        XCTAssertEqual(
            viewModel.relatedPaths(for: app),
            ["/Applications/Alpha.app", "/Users/example/Library/Caches/com.example.alpha"]
        )
    }

    func testRelatedPathsAreNotLoadedWithoutAUserRequest() async {
        let process = DetailProcessSpy(
            dryRunOutput: "Files to be removed:\n  /Applications/Alpha.app\n"
        )
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()

        for app in viewModel.apps {
            XCTAssertNil(viewModel.relatedPaths(for: app))
        }
        let invocations = await process.invocations
        XCTAssertTrue(invocations.isEmpty, "the related-files dry-run runs only on demand")
    }

    func testRelatedPathsEmptyWhenDryRunHasNoPaths() async {
        let process = DetailProcessSpy(dryRunOutput: "Nothing to remove\n")
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()
        let app = viewModel.apps[0]

        await viewModel.loadRelatedFiles(for: app)
        XCTAssertEqual(viewModel.relatedPaths(for: app), [])
    }

    func testRevealInFinderUsesTheAppPath() async {
        let revealer = RevealerSpy()
        let viewModel = makeViewModel(process: DetailProcessSpy(), revealer: revealer)
        await viewModel.loadListIfNeeded()
        let app = viewModel.apps[0]

        viewModel.revealInFinder(app)
        var paths: [String] = []
        for _ in 0..<200 {
            paths = await revealer.paths
            if !paths.isEmpty { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(paths, [app.path])
    }

    func testCancelConfirmationDoesNotExecuteUninstall() async {
        let process = DetailProcessSpy()
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()
        viewModel.toggleSelection(viewModel.apps[0])
        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.canConfirm)

        viewModel.cancelConfirmation()

        let invocations = await process.invocations
        XCTAssertTrue(invocations.isEmpty, "cancel must not spawn any process")
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertFalse(viewModel.isConfirmationPresented)
    }

    func testUnknownSizeIsNilAndTotalUsesBodyEstimateWording() throws {
        let app = UninstallApp(
            name: "Alpha", bundleID: "com.example.alpha", uninstallName: "Alpha",
            path: "/Applications/Alpha.app", source: "App", size: "unknown"
        )
        XCTAssertNil(app.sizeBytes)

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["uninstall.selected_total_app_estimate"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let zh = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any])
        let value = try XCTUnwrap((zh["stringUnit"] as? [String: Any])?["value"] as? String)
        XCTAssertTrue(value.contains("本体估计"))
        XCTAssertFalse(value.contains("释放"))
    }

    func testSearchFilterHidesRowButKeepsSelection() async {
        let viewModel = makeViewModel(process: DetailProcessSpy())
        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps
        viewModel.toggleSelection(apps[0])

        let visible = UninstallListFilter.visibleListings(viewModel.listings, search: "Beta", source: "all")
        XCTAssertEqual(visible.map(\.name), ["Beta Tool"])
        XCTAssertEqual(viewModel.selectedPaths, [apps[0].id])
    }

    func testConfirmationExecutesOnlySelectedBatch() async {
        let process = DetailProcessSpy()
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps
        viewModel.toggleSelection(apps[0])
        viewModel.toggleSelection(apps[1])
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await process.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].arguments, ["uninstall", "Alpha App", "Beta Tool"])
    }

    func testZeroSizeStringIsUnknown() {
        let app = UninstallApp(
            name: "Zero", bundleID: "com.example.zero", uninstallName: "Zero",
            path: "/Applications/Zero.app", size: "0"
        )
        XCTAssertNil(app.sizeBytes)
        XCTAssertNil(app.sizeText)
    }

    func testAnotherWriteInvalidatesTheUninstallConfirmation() async {
        let coordinator = OperationCoordinator()
        let viewModel = makeViewModel(process: DetailProcessSpy(), coordinator: coordinator)

        await viewModel.loadListIfNeeded()
        viewModel.toggleSelection(viewModel.apps[0])
        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.canConfirm)

        // A write elsewhere (e.g. a clean run) bumps the shared generation.
        coordinator.invalidatePreviews()

        XCTAssertFalse(viewModel.isConfirmationPresented, "another write must close the stale sheet")
        XCTAssertFalse(viewModel.canConfirm)
    }

    private func makeViewModel(
        process: DetailProcessSpy,
        coordinator: OperationCoordinator? = nil,
        alphaVersion: String? = nil,
        alphaLastUsed: Date? = nil,
        revealer: FileRevealing = RevealerSpy()
    ) -> UninstallViewModel {
        UninstallViewModel(
            process: process,
            listStream: UninstallFixture.stream(rows: [
                UninstallAppListing(
                    path: "/Applications/Alpha.app",
                    name: "Alpha App",
                    bundleID: "com.example.alpha",
                    uninstallName: "Alpha App",
                    source: "App",
                    sizeText: "1.4 GB",
                    version: alphaVersion,
                    lastUsed: alphaLastUsed
                ),
                UninstallAppListing(
                    path: "/Applications/Beta.app",
                    name: "Beta Tool",
                    bundleID: "com.example.beta",
                    uninstallName: "Beta Tool",
                    source: "Homebrew",
                    sizeText: nil,
                    version: nil,
                    lastUsed: nil
                )
            ]),
            coordinator: coordinator ?? OperationCoordinator(),
            targetChecker: FixedTargetChecker(matches: true),
            iconProvider: NoopIconProvider(),
            revealer: revealer
        )
    }
}

private struct DetailInvocation: Sendable {
    let arguments: [String]
    let stdin: Data?
}

private actor DetailProcessSpy: MoleProcessControlling {
    private(set) var invocations: [DetailInvocation] = []
    private let dryRunOutput: String

    init(dryRunOutput: String = "") {
        self.dryRunOutput = dryRunOutput
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations.append(DetailInvocation(arguments: arguments, stdin: stdin))
        if arguments.first == "uninstall", arguments.contains("--dry-run") {
            return MoleCommandResult(stdout: dryRunOutput, stderr: "", exitCode: 0)
        }
        return MoleCommandResult(stdout: "Successfully uninstalled", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}

private actor RevealerSpy: FileRevealing {
    private(set) var paths: [String] = []

    func reveal(path: String) async {
        paths.append(path)
    }
}
