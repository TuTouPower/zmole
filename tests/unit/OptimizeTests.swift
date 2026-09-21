import XCTest
@testable import Zmole

final class OptimizeTests: XCTestCase {
    @MainActor
    func testOptimizePreviewUsesDryRunAndDisplaysStrippedOutput() async throws {
        let spy = OptimizeProcessSpy(previewResults: [
            MoleCommandResult(
                stdout: "\u{001B}[31mPlan\u{001B}[0m\n",
                stderr: "",
                exitCode: 0
            )
        ])
        let viewModel = OptimizeViewModel(process: spy)

        await viewModel.previewOptimize()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["optimize", "--dry-run"]])
        XCTAssertNil(invocations[0].stdin)
        XCTAssertEqual(viewModel.preview?.output, "Plan")

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Optimize/OptimizeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("ScrollView"))
        XCTAssertTrue(source.contains("preview.output"))
    }

    @MainActor
    func testOptimizePreviewFailureExpiresPreviousPreview() async throws {
        let spy = OptimizeProcessSpy(previewResults: [
            MoleCommandResult(stdout: "old plan", stderr: "", exitCode: 0),
            MoleCommandResult(stdout: "new plan", stderr: "optimize failed", exitCode: 7)
        ])
        let viewModel = OptimizeViewModel(process: spy)

        await viewModel.previewOptimize()
        XCTAssertEqual(viewModel.preview?.output, "old plan")

        await viewModel.previewOptimize()

        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertEqual(viewModel.errorMessageKey, "optimize.error.failed")
        XCTAssertEqual(viewModel.executionSummary, "new plan\noptimize failed")
    }

    @MainActor
    func testOptimizeDoesNotExecuteBeforeConfirmation() async throws {
        let spy = OptimizeProcessSpy(previewResults: [
            MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)
        ])
        let viewModel = OptimizeViewModel(process: spy)

        await viewModel.previewOptimize()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["optimize", "--dry-run"]])
        XCTAssertNil(viewModel.executionSummary)
    }

    @MainActor
    func testOptimizeConfirmationExecutesWithoutDryRun() async throws {
        let spy = OptimizeProcessSpy(
            previewResults: [MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)],
            executionResult: MoleCommandResult(
                stdout: "optimized",
                stderr: "",
                exitCode: 0
            )
        )
        let viewModel = OptimizeViewModel(process: spy)

        await viewModel.previewOptimize()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["optimize", "--dry-run"],
            ["optimize"]
        ])
        XCTAssertEqual(viewModel.executionSummary, "optimized")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testOptimizeConfirmationCancelRequiresNewPreview() async throws {
        let spy = OptimizeProcessSpy(previewResults: [
            MoleCommandResult(stdout: "first plan", stderr: "", exitCode: 0),
            MoleCommandResult(stdout: "second plan", stderr: "", exitCode: 0)
        ])
        let viewModel = OptimizeViewModel(process: spy)

        await viewModel.previewOptimize()
        viewModel.requestConfirmation()
        viewModel.cancelConfirmation()
        await viewModel.confirmExecution()
        XCTAssertNil(viewModel.preview)

        await viewModel.previewOptimize()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["optimize", "--dry-run"],
            ["optimize", "--dry-run"],
            ["optimize"]
        ])
    }

    @MainActor
    func testOptimizeExecutionFailureShowsSummary() async throws {
        let spy = OptimizeProcessSpy(
            previewResults: [MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)],
            executionResult: MoleCommandResult(
                stdout: "partial optimize",
                stderr: "optimize failed",
                exitCode: 9
            )
        )
        let viewModel = OptimizeViewModel(process: spy)

        await viewModel.previewOptimize()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        XCTAssertEqual(viewModel.executionSummary, "partial optimize\noptimize failed")
        XCTAssertEqual(viewModel.errorMessageKey, "optimize.error.failed")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testOptimizeBusyExecutionCannotStartTwiceAndCanCancel() async throws {
        let spy = OptimizeProcessSpy(
            previewResults: [MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)]
        )
        await spy.setExecutionBlocked(true)
        let viewModel = OptimizeViewModel(process: spy)

        await viewModel.previewOptimize()
        viewModel.requestConfirmation()
        let execution = Task { @MainActor in await viewModel.confirmExecution() }

        try await spy.waitForInvocationCount(2)
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

private struct OptimizeInvocation: Equatable, Sendable {
    let arguments: [String]
    let stdin: Data?
}

private actor OptimizeProcessSpy: MoleProcessControlling {
    private(set) var invocations: [OptimizeInvocation] = []
    private(set) var cancelCount = 0
    private var previewResults: [MoleCommandResult]
    private let executionResult: MoleCommandResult
    private var blockExecution = false
    private var executionContinuation: CheckedContinuation<MoleCommandResult, Error>?

    init(
        previewResults: [MoleCommandResult],
        executionResult: MoleCommandResult = MoleCommandResult(
            stdout: "optimized",
            stderr: "",
            exitCode: 0
        )
    ) {
        self.previewResults = previewResults
        self.executionResult = executionResult
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations.append(OptimizeInvocation(arguments: arguments, stdin: stdin))
        if arguments == ["optimize", "--dry-run"] {
            return previewResults.isEmpty
                ? MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
                : previewResults.removeFirst()
        }
        guard blockExecution else { return executionResult }
        return try await withCheckedThrowingContinuation { continuation in
            executionContinuation = continuation
        }
    }

    func cancel() async {
        cancelCount += 1
        executionContinuation?.resume(throwing: MoleBridgeError.cancelled)
        executionContinuation = nil
    }

    func setExecutionBlocked(_ blocked: Bool) {
        blockExecution = blocked
    }

    func waitForInvocationCount(_ count: Int) async throws {
        for _ in 0..<1_000 {
            if invocations.count >= count { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        throw OptimizeSpyWaitError.timeout
    }
}

private enum OptimizeSpyWaitError: Error {
    case timeout
}
