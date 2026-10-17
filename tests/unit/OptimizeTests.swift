import XCTest
@testable import Zmole

final class OptimizeTests: XCTestCase {
    @MainActor
    func testOptimizeDisplaysBackgroundResultWithoutSpawningCommands() async throws {
        let spy = MaintenanceExecutionSpy()
        let scan = ScanProvidingStub.maintenance(.optimize, output: "Plan")
        let viewModel = OptimizeViewModel(process: spy, coordinator: OperationCoordinator(), scan: scan)

        viewModel.adoptBackgroundResultIfAvailable()

        XCTAssertEqual(viewModel.preview?.output, "Plan")
        XCTAssertTrue(viewModel.canConfirm)
        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty, "the page must use the background result, not run its own scan")

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Optimize/OptimizeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("ScrollView"))
        XCTAssertTrue(source.contains("viewModel.preview?.output"))
        XCTAssertTrue(source.contains("planRows()"))
    }

    @MainActor
    func testNewBackgroundResultReplacesIdlePreview() async throws {
        let scan = ScanProvidingStub.maintenance(.optimize, output: "first")
        let viewModel = OptimizeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )
        viewModel.adoptBackgroundResultIfAvailable()
        XCTAssertEqual(viewModel.preview?.output, "first")

        scan.results[.optimize] = BackgroundScanResult(
            capturedAt: Date(),
            payload: .maintenance("second")
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.preview?.output, "second", "a new background result fills the idle page")
    }

    @MainActor
    func testRefreshButtonRequestsTheBackgroundScan() async throws {
        let scan = ScanProvidingStub.maintenance(.optimize, output: "plan")
        let viewModel = OptimizeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )

        viewModel.refreshMaintenance()

        XCTAssertEqual(scan.requestedItems, [.optimize])
    }

    @MainActor
    func testCancelRefreshYieldsTheBackgroundScan() async throws {
        let scan = ScanProvidingStub.maintenance(.optimize, output: "plan")
        let viewModel = OptimizeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )

        await viewModel.cancelRefresh()

        XCTAssertEqual(scan.cancelledItems, [.optimize])
    }

    @MainActor
    func testOptimizeDoesNotExecuteBeforeConfirmation() async throws {
        let spy = MaintenanceExecutionSpy()
        let viewModel = OptimizeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.optimize, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()

        viewModel.requestConfirmation()

        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertNil(viewModel.executionSummary)
    }

    @MainActor
    func testConfirmingResultIsNotReplacedByANewBackgroundResult() async throws {
        let scan = ScanProvidingStub.maintenance(.optimize, output: "plan")
        let viewModel = OptimizeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: scan
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        scan.results[.optimize] = BackgroundScanResult(
            capturedAt: Date(),
            payload: .maintenance("replacement")
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        viewModel.adoptBackgroundResultIfAvailable()

        XCTAssertEqual(viewModel.preview?.output, "plan", "the confirming result stays")
    }

    @MainActor
    func testCancelConfirmationKeepsTheBackgroundResult() async throws {
        let viewModel = OptimizeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.optimize, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        viewModel.cancelConfirmation()

        XCTAssertFalse(viewModel.isConfirmationPresented)
        XCTAssertEqual(viewModel.preview?.output, "plan")
    }

    @MainActor
    func testOptimizeConfirmationExecutesOnceWithTheExpectedArgv() async throws {
        let spy = MaintenanceExecutionSpy(
            executionResult: MoleCommandResult(stdout: "optimized", stderr: "", exitCode: 0)
        )
        let viewModel = OptimizeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.optimize, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["optimize"]])
        XCTAssertEqual(viewModel.executionSummary, "optimized")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testOptimizeExecutionFailureShowsSummary() async throws {
        let spy = MaintenanceExecutionSpy(
            executionResult: MoleCommandResult(
                stdout: "partial optimize",
                stderr: "optimize failed",
                exitCode: 9
            )
        )
        let viewModel = OptimizeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.optimize, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        await viewModel.confirmExecution()

        XCTAssertEqual(viewModel.executionSummary, "partial optimize\noptimize failed")
        XCTAssertEqual(viewModel.errorMessageKey, "optimize.error.failed")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testOptimizeBusyExecutionCannotStartTwiceAndCanCancel() async throws {
        let spy = MaintenanceExecutionSpy()
        await spy.setExecutionBlocked(true)
        let viewModel = OptimizeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.optimize, output: "plan")
        )
        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()

        let execution = Task { @MainActor in await viewModel.confirmExecution() }
        try await spy.waitForInvocationCount(1)
        XCTAssertTrue(viewModel.isExecuting)

        await viewModel.confirmExecution()
        let beforeCancel = await spy.invocations
        XCTAssertEqual(beforeCancel.filter { $0.arguments == ["optimize"] }.count, 1)

        await viewModel.cancelExecution()
        await execution.value

        let cancelCount = await spy.cancelCount
        XCTAssertEqual(cancelCount, 1)
        XCTAssertFalse(viewModel.isExecuting)
        XCTAssertEqual(viewModel.errorMessageKey, "optimize.cancelled")
    }
}
