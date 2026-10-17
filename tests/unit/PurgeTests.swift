import XCTest
@testable import Zmole

final class PurgeTests: XCTestCase {
    @MainActor
    func testPurgeDisplaysBackgroundResultWithoutSpawningCommands() async throws {
        let spy = MaintenanceExecutionSpy()
        let scan = ScanProvidingStub.maintenance(.purge, output: "Plan")
        let viewModel = PurgeViewModel(process: spy, coordinator: OperationCoordinator(), scan: scan)

        viewModel.adoptBackgroundResultIfAvailable()

        XCTAssertEqual(viewModel.preview?.output, "Plan")
        XCTAssertTrue(viewModel.canConfirm)
        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty, "the page must use the background result, not run its own scan")

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Purge/PurgeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("ScrollView"))
        XCTAssertTrue(source.contains("preview.output"))
        XCTAssertTrue(source.contains("purge.scan_output"))
    }

    @MainActor
    func testNewBackgroundResultReplacesIdlePreview() async throws {
        let scan = ScanProvidingStub.maintenance(.purge, output: "first")
        let viewModel = PurgeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )
        viewModel.adoptBackgroundResultIfAvailable()
        XCTAssertEqual(viewModel.preview?.output, "first")

        scan.results[.purge] = BackgroundScanResult(
            capturedAt: Date(),
            payload: .maintenance("second")
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.preview?.output, "second", "a new background result fills the idle page")
    }

    @MainActor
    func testPurgeDoesNotExecuteBeforeConfirmation() async throws {
        let spy = MaintenanceExecutionSpy()
        let viewModel = PurgeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.purge, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()

        viewModel.requestConfirmation()

        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertNil(viewModel.executionSummary)
    }

    @MainActor
    func testCancelConfirmationKeepsTheBackgroundResult() async throws {
        let viewModel = PurgeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.purge, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        viewModel.cancelConfirmation()

        XCTAssertFalse(viewModel.isConfirmationPresented)
        XCTAssertEqual(viewModel.preview?.output, "plan")
    }

    @MainActor
    func testPurgeConfirmationExecutesOnceWithTheExpectedArgv() async throws {
        let spy = MaintenanceExecutionSpy(
            executionResult: MoleCommandResult(stdout: "purged", stderr: "", exitCode: 0)
        )
        let viewModel = PurgeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.purge, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["purge", "--yes"]])
        XCTAssertEqual(viewModel.executionSummary, "purged")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testPurgeExecutionFailureShowsSummary() async throws {
        let spy = MaintenanceExecutionSpy(
            executionResult: MoleCommandResult(
                stdout: "partial purge",
                stderr: "purge failed",
                exitCode: 9
            )
        )
        let viewModel = PurgeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.purge, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        await viewModel.confirmExecution()

        XCTAssertEqual(viewModel.executionSummary, "partial purge\npurge failed")
        XCTAssertEqual(viewModel.errorMessageKey, "purge.error.failed")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testPurgeBusyExecutionCannotStartTwiceAndCanCancel() async throws {
        let spy = MaintenanceExecutionSpy()
        await spy.setExecutionBlocked(true)
        let viewModel = PurgeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.purge, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        let execution = Task { @MainActor in await viewModel.confirmExecution() }
        try await spy.waitForInvocationCount(1)
        XCTAssertTrue(viewModel.isExecuting)

        await viewModel.confirmExecution()
        let beforeCancel = await spy.invocations
        XCTAssertEqual(beforeCancel.filter { $0.arguments == ["purge", "--yes"] }.count, 1)

        await viewModel.cancelExecution()
        await execution.value

        let cancelCount = await spy.cancelCount
        XCTAssertEqual(cancelCount, 1)
        XCTAssertFalse(viewModel.isExecuting)
        XCTAssertEqual(viewModel.errorMessageKey, "purge.cancelled")
    }
}
