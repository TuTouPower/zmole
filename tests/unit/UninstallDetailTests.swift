import XCTest
@testable import Zmole

@MainActor
final class UninstallDetailTests: XCTestCase {
    func testBatchPreviewUsesOnlySelectedUninstallNamesAndConfirmationInput() async {
        let process = DetailProcessSpy(listJSON: Self.listJSON)
        let viewModel = makeViewModel(process: process)

        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps
        viewModel.toggleSelection(apps[0])
        viewModel.toggleSelection(apps[1])
        await viewModel.previewUninstall()

        let invocations = await process.invocations
        let preview = invocations.last { $0.arguments.contains("--dry-run") }
        XCTAssertEqual(preview?.arguments, ["uninstall", "--dry-run", "Alpha App", "Beta Tool"])
        XCTAssertEqual(preview?.stdin, Data("y\n".utf8))
    }

    func testFocusAndSelectionAreIndependentOfEachOther() async {
        let viewModel = makeViewModel(process: DetailProcessSpy(listJSON: Self.listJSON))
        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps

        viewModel.toggleSelection(apps[0])
        viewModel.focus(apps[1])
        await viewModel.loadDetail(for: apps[1])

        XCTAssertEqual(viewModel.focusedAppID, apps[1].id)
        XCTAssertEqual(viewModel.selectedIDs, [apps[0].id])
        XCTAssertEqual(viewModel.focusedApp?.path, apps[1].path)
    }

    func testMetadataShowsUnknownWhenMissing() async {
        let provider = FakeMetadataProvider(values: [:])
        let viewModel = makeViewModel(process: DetailProcessSpy(listJSON: Self.listJSON), metadata: provider)
        await viewModel.loadListIfNeeded()
        await viewModel.loadDetail(for: viewModel.apps[0])

        let metadata = viewModel.metadata(for: viewModel.apps[0])
        XCTAssertNotNil(metadata)
        XCTAssertNil(metadata?.version)
        XCTAssertNil(metadata?.lastUsed)
    }

    func testMetadataFromLocalProviderIsSurfaced() async {
        let version = UninstallAppMetadata(version: "1.2.3", lastUsed: Date(timeIntervalSince1970: 1_700_000_000))
        let provider = FakeMetadataProvider(values: ["/Applications/Alpha.app": version])
        let viewModel = makeViewModel(process: DetailProcessSpy(listJSON: Self.listJSON), metadata: provider)
        await viewModel.loadListIfNeeded()
        await viewModel.loadDetail(for: viewModel.apps[0])

        XCTAssertEqual(viewModel.metadata(for: viewModel.apps[0])?.version, "1.2.3")
    }

    func testRelatedPathsOnlyComeFromThatAppsDryRun() async {
        let process = DetailProcessSpy(
            listJSON: Self.listJSON,
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

    func testRelatedPathsEmptyWhenDryRunHasNoPaths() async {
        let process = DetailProcessSpy(listJSON: Self.listJSON, dryRunOutput: "Nothing to remove\n")
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()
        let app = viewModel.apps[0]

        await viewModel.loadRelatedFiles(for: app)
        XCTAssertEqual(viewModel.relatedPaths(for: app), [])
    }

    func testRevealInFinderUsesTheAppPath() async {
        let revealer = RevealerSpy()
        let viewModel = makeViewModel(process: DetailProcessSpy(listJSON: Self.listJSON), revealer: revealer)
        await viewModel.loadListIfNeeded()
        let app = viewModel.apps[0]

        viewModel.revealInFinder(app)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let paths = await revealer.paths
        XCTAssertEqual(paths, [app.path])
    }

    func testCancelConfirmationDoesNotExecuteUninstall() async {
        let process = DetailProcessSpy(listJSON: Self.listJSON)
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()
        viewModel.toggleSelection(viewModel.apps[0])
        await viewModel.previewUninstall()
        XCTAssertTrue(viewModel.canConfirm)

        viewModel.requestConfirmation()
        viewModel.cancelConfirmation()

        let invocations = await process.invocations
        XCTAssertFalse(invocations.contains { $0.arguments.first == "uninstall" && !$0.arguments.contains("--dry-run") && !$0.arguments.contains("--list") })
        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)
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
        let viewModel = makeViewModel(process: DetailProcessSpy(listJSON: Self.listJSON))
        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps
        viewModel.toggleSelection(apps[0])

        let visible = UninstallListFilter.visible(viewModel.apps, search: "Beta", source: "all")
        XCTAssertEqual(visible.map(\.name), ["Beta Tool"])
        XCTAssertEqual(viewModel.selectedIDs, [apps[0].id])
    }

    func testConfirmationExecutesOnlySelectedBatch() async {
        let process = DetailProcessSpy(listJSON: Self.listJSON)
        let viewModel = makeViewModel(process: process)
        await viewModel.loadListIfNeeded()
        let apps = viewModel.apps
        viewModel.toggleSelection(apps[0])
        viewModel.toggleSelection(apps[1])
        await viewModel.previewUninstall()

        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await process.invocations
        let execution = invocations.last { invocation in
            invocation.arguments.first == "uninstall"
                && !invocation.arguments.contains("--list")
                && !invocation.arguments.contains("--dry-run")
        }
        XCTAssertEqual(execution?.arguments, ["uninstall", "Alpha App", "Beta Tool"])
        XCTAssertNil(viewModel.preview)
    }

    func testZeroSizeStringIsUnknown() {
        let app = UninstallApp(
            name: "Zero", bundleID: "com.example.zero", uninstallName: "Zero",
            path: "/Applications/Zero.app", size: "0"
        )
        XCTAssertNil(app.sizeBytes)
        XCTAssertNil(app.sizeText)
    }

    private func makeViewModel(
        process: DetailProcessSpy,
        metadata: UninstallMetadataProviding = FakeMetadataProvider(values: [:]),
        revealer: FileRevealing = RevealerSpy()
    ) -> UninstallViewModel {
        UninstallViewModel(
            process: process,
            coordinator: OperationCoordinator(),
            metadataProvider: metadata,
            revealer: revealer
        )
    }

    private static let listJSON = """
    [
      {"name":"Alpha App","bundle_id":"com.example.alpha","uninstall_name":"Alpha App","path":"/Applications/Alpha.app","source":"App","size":"1.4 GB"},
      {"name":"Beta Tool","bundle_id":"com.example.beta","uninstall_name":"Beta Tool","path":"/Applications/Beta.app","source":"Homebrew","size":"unknown"}
    ]
    """
}

private struct DetailInvocation: Sendable {
    let arguments: [String]
    let stdin: Data?
}

private actor DetailProcessSpy: MoleProcessControlling {
    private(set) var invocations: [DetailInvocation] = []
    private let listJSON: String
    private let dryRunOutput: String

    init(listJSON: String, dryRunOutput: String = "") {
        self.listJSON = listJSON
        self.dryRunOutput = dryRunOutput
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations.append(DetailInvocation(arguments: arguments, stdin: stdin))
        if arguments == ["uninstall", "--list"] {
            return MoleCommandResult(stdout: listJSON, stderr: "", exitCode: 0)
        }
        if arguments.first == "uninstall", arguments.contains("--dry-run") {
            return MoleCommandResult(stdout: dryRunOutput, stderr: "", exitCode: 0)
        }
        return MoleCommandResult(stdout: "Successfully uninstalled", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}

private struct FakeMetadataProvider: UninstallMetadataProviding {
    let values: [String: UninstallAppMetadata]

    func metadata(forAppAt path: String) async -> UninstallAppMetadata {
        values[path] ?? UninstallAppMetadata(version: nil, lastUsed: nil)
    }
}

private actor RevealerSpy: FileRevealing {
    private(set) var paths: [String] = []

    func reveal(path: String) async {
        paths.append(path)
    }
}
