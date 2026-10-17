import XCTest
@testable import Zmole

@MainActor
final class CleanPageTests: XCTestCase {
    func testReclaimBytesParseHumanSizes() {
        XCTAssertEqual(CleanPreviewParser.parseHumanSize("2.40GB"), 2_400_000_000)
        XCTAssertEqual(CleanPreviewParser.parseHumanSize("512MB, 18 items"), 512_000_000)
        XCTAssertEqual(CleanPreviewParser.parseHumanSize("123KB"), 123_000)
        XCTAssertEqual(CleanPreviewParser.parseHumanSize("512B"), 512)
        XCTAssertEqual(CleanPreviewParser.parseHumanSize("2.4 GB"), 2_400_000_000)
        XCTAssertNil(CleanPreviewParser.parseHumanSize("size unknown"))
        XCTAssertNil(CleanPreviewParser.parseHumanSize("99999999999999999999999TB"))
    }

    func testExecutionRunsOnlyAfterConfirmationWithBackgroundData() async throws {
        let spy = MaintenanceExecutionSpy(
            executionResult: MoleCommandResult(stdout: "cleaned", stderr: "", exitCode: 0)
        )
        let viewModel = CleanViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub(results: [.clean: makeResult()])
        )
        viewModel.adoptBackgroundResultIfAvailable()
        XCTAssertTrue(viewModel.canConfirm)

        let beforeConfirmation = await spy.invocations
        XCTAssertTrue(beforeConfirmation.isEmpty, "the page must use the background scan, not spawn a preview")

        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["clean"]])
        XCTAssertEqual(viewModel.executionSummary, "cleaned")
    }

    func testReclaimAppearsOnlyWithBackgroundData() async throws {
        let expected: Int64 = 2_400_000_000 + 512_000_000
        let failedStub = ScanProvidingStub()
        failedStub.failedItems.insert(.clean)
        let failedViewModel = CleanViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: failedStub
        )
        failedViewModel.adoptBackgroundResultIfAvailable()
        XCTAssertNil(failedViewModel.lastReclaimBytes)
        XCTAssertNil(failedViewModel.preview)
        XCTAssertTrue(failedViewModel.scanFailed)

        let viewModel = CleanViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub(results: [.clean: makeResult()])
        )
        viewModel.adoptBackgroundResultIfAvailable()

        XCTAssertEqual(viewModel.lastReclaimBytes, expected)
        XCTAssertEqual(viewModel.previewCapturedAt, Date(timeIntervalSince1970: 70))
    }

    func testRefreshButtonRequestsTheBackgroundScan() async throws {
        let scan = ScanProvidingStub()
        let viewModel = CleanViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )

        viewModel.refreshIfNeeded()
        viewModel.refreshClean()
        await viewModel.cancelRefresh()

        XCTAssertEqual(scan.requestedItems, [.clean, .clean])
        XCTAssertEqual(scan.cancelledItems, [.clean])
    }

    func testProtectingPathInvalidatesTheShownScan() async throws {
        let directory = try makeTemporaryDirectory(prefix: "clean-page-protect")
        defer { try? FileManager.default.removeItem(at: directory) }
        let whitelistURL = directory.appendingPathComponent("whitelist")
        try "# header\n".write(to: whitelistURL, atomically: true, encoding: .utf8)
        let coordinator = OperationCoordinator()

        let cleanViewModel = CleanViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: coordinator,
            scan: ScanProvidingStub(results: [.clean: makeResult()])
        )
        let whitelistViewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: whitelistURL),
            coordinator: coordinator
        )

        cleanViewModel.adoptBackgroundResultIfAvailable()
        XCTAssertNotNil(cleanViewModel.preview)
        XCTAssertTrue(cleanViewModel.canConfirm)

        whitelistViewModel.load()
        whitelistViewModel.newPattern = "/Users/example/Library/Caches/a"
        whitelistViewModel.addPattern()
        whitelistViewModel.save()

        XCTAssertNil(cleanViewModel.preview)
        XCTAssertFalse(cleanViewModel.canConfirm)
        XCTAssertNil(cleanViewModel.lastReclaimBytes)
    }

    func testCleanViewHasNoSubsetExecutionControl() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Clean/CleanView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in ["Toggle(", "Checkbox", "selectedEntries", "cleanSelected", "selectAll"] {
            XCTAssertFalse(source.contains(forbidden), "CleanView must not offer subset execution: \(forbidden)")
        }
    }

    func testZhHansCleanCopyMentionsTrash() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        for key in ["clean.execution_note", "clean.confirm_summary", "clean.subtitle"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let zh = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any])
            let value = try XCTUnwrap((zh["stringUnit"] as? [String: Any])?["value"] as? String)
            XCTAssertTrue(value.contains("废纸篓"), "\(key) must mention 废纸篓")
            XCTAssertFalse(value.contains("永久删除"), "\(key) must not say 永久删除")
        }
    }

    func testNewBackgroundResultFillsTheIdleCleanPage() async throws {
        let scan = ScanProvidingStub(results: [.clean: makeResult()])
        let viewModel = CleanViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )
        viewModel.adoptBackgroundResultIfAvailable()
        XCTAssertNotNil(viewModel.preview)

        scan.results[.clean] = makeResult(capturedAt: Date(timeIntervalSince1970: 90))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.previewCapturedAt, Date(timeIntervalSince1970: 90))
    }

    func testCancelConfirmationKeepsTheScanAndDoesNotExecute() async throws {
        let spy = MaintenanceExecutionSpy()
        let viewModel = CleanViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub(results: [.clean: makeResult()])
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.isConfirmationPresented)

        viewModel.cancelConfirmation()

        XCTAssertFalse(viewModel.isConfirmationPresented)
        XCTAssertNotNil(viewModel.preview, "cancelling must keep the background scan visible")
        XCTAssertTrue(viewModel.canConfirm)
        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty, "cancelling must not execute")
    }

    func testRefreshingStateFollowsTheBackgroundScan() async throws {
        let scan = ScanProvidingStub(results: [.clean: makeResult()])
        let viewModel = CleanViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )
        viewModel.adoptBackgroundResultIfAvailable()
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.ownsCleanListFile)

        scan.runningItems.insert(.clean)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.isRefreshing, "the page must show the scanning state")
        XCTAssertFalse(viewModel.ownsCleanListFile, "showing scan data is not owning the list file")

        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.ownsCleanListFile, "an open confirmation owns the shared list file")
        viewModel.cancelConfirmation()
        XCTAssertFalse(viewModel.ownsCleanListFile)
    }

    func testCleanExecutionFailureShowsSummary() async throws {
        let spy = MaintenanceExecutionSpy(
            executionResult: MoleCommandResult(
                stdout: "partial output",
                stderr: "clean failed",
                exitCode: 9
            )
        )
        let viewModel = CleanViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub(results: [.clean: makeResult()])
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        await viewModel.confirmExecution()

        XCTAssertNil(viewModel.preview)
        XCTAssertEqual(viewModel.errorMessageKey, "clean.error.failed")
        XCTAssertEqual(viewModel.executionSummary, "partial output\nclean failed")
    }

    func testCleanBusyExecutionCreatesOneProcessAndCanCancel() async throws {
        let spy = MaintenanceExecutionSpy()
        await spy.setExecutionBlocked(true)
        let viewModel = CleanViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub(results: [.clean: makeResult()])
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        let first = Task { @MainActor in await viewModel.confirmExecution() }
        try await spy.waitForInvocationCount(1)
        XCTAssertTrue(viewModel.isExecuting)

        await viewModel.confirmExecution()
        let arguments = await spy.invocations.map(\.arguments)
        XCTAssertEqual(arguments, [["clean"]], "duplicate submission must not create a second process")

        await viewModel.cancelExecution()
        await first.value

        let cancelCount = await spy.cancelCount
        XCTAssertEqual(cancelCount, 1)
        XCTAssertFalse(viewModel.isExecuting)
        XCTAssertEqual(viewModel.errorMessageKey, "clean.cancelled")
    }

    private static let fixture = """
    # Mole Cleanup Preview
    === Browsers ===
    /Users/example/Library/Caches/a  # 2.40GB, 18 items
    === Developer tools ===
    /Users/example/.npm  # 512MB
    """

    private func makeResult(capturedAt: Date = Date(timeIntervalSince1970: 70)) -> BackgroundScanResult {
        BackgroundScanResult(
            capturedAt: capturedAt,
            payload: .cleanPreview(
                CleanPreviewSnapshot(
                    generation: CleanPreviewGeneration(
                        id: UUID(),
                        fileURL: URL(fileURLWithPath: "/tmp/clean-list.txt")
                    ),
                    contents: Self.fixture,
                    entries: [],
                    sections: CleanPreviewParser.sections(from: Self.fixture)
                )
            )
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
