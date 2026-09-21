import XCTest
@testable import Zmole

final class PurgeTests: XCTestCase {
    @MainActor
    func testPurgePreviewUsesDryRunAndDisplaysStrippedOutput() async throws {
        let spy = PurgeProcessSpy(previewResults: [
            MoleCommandResult(
                stdout: "\u{001B}[31mPlan\u{001B}[0m\n",
                stderr: "",
                exitCode: 0
            )
        ])
        let viewModel = PurgeViewModel(process: spy)

        await viewModel.previewPurge()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["purge", "--dry-run"]])
        XCTAssertNil(invocations[0].stdin)
        XCTAssertEqual(viewModel.preview?.output, "Plan")

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Purge/PurgeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("ScrollView"))
        XCTAssertTrue(source.contains("preview.output"))
    }

    @MainActor
    func testPurgePreviewFailureExpiresPreviousPreview() async throws {
        let spy = PurgeProcessSpy(previewResults: [
            MoleCommandResult(stdout: "old plan", stderr: "", exitCode: 0),
            MoleCommandResult(stdout: "new plan", stderr: "purge failed", exitCode: 7)
        ])
        let viewModel = PurgeViewModel(process: spy)

        await viewModel.previewPurge()
        XCTAssertEqual(viewModel.preview?.output, "old plan")

        await viewModel.previewPurge()

        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertEqual(viewModel.errorMessageKey, "purge.error.failed")
        XCTAssertEqual(viewModel.executionSummary, "new plan\npurge failed")
    }

    @MainActor
    func testPurgeDoesNotExecuteBeforeConfirmation() async throws {
        let spy = PurgeProcessSpy(previewResults: [
            MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)
        ])
        let viewModel = PurgeViewModel(process: spy)

        await viewModel.previewPurge()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["purge", "--dry-run"]])
        XCTAssertNil(viewModel.executionSummary)
    }

    @MainActor
    func testPurgeConfirmationExecutesWithoutDryRun() async throws {
        let spy = PurgeProcessSpy(
            previewResults: [MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)],
            executionResult: MoleCommandResult(
                stdout: "purged",
                stderr: "",
                exitCode: 0
            )
        )
        let viewModel = PurgeViewModel(process: spy)

        await viewModel.previewPurge()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["purge", "--dry-run"],
            ["purge", "--yes"]
        ])
        XCTAssertEqual(viewModel.executionSummary, "purged")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testPurgeConfirmationCancelRequiresNewPreview() async throws {
        let spy = PurgeProcessSpy(previewResults: [
            MoleCommandResult(stdout: "first plan", stderr: "", exitCode: 0),
            MoleCommandResult(stdout: "second plan", stderr: "", exitCode: 0)
        ])
        let viewModel = PurgeViewModel(process: spy)

        await viewModel.previewPurge()
        viewModel.requestConfirmation()
        viewModel.cancelConfirmation()
        await viewModel.confirmExecution()
        XCTAssertNil(viewModel.preview)

        await viewModel.previewPurge()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["purge", "--dry-run"],
            ["purge", "--dry-run"],
            ["purge", "--yes"]
        ])
    }

    @MainActor
    func testPurgeExecutionFailureShowsSummary() async throws {
        let spy = PurgeProcessSpy(
            previewResults: [MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)],
            executionResult: MoleCommandResult(
                stdout: "partial purge",
                stderr: "purge failed",
                exitCode: 9
            )
        )
        let viewModel = PurgeViewModel(process: spy)

        await viewModel.previewPurge()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        XCTAssertEqual(viewModel.executionSummary, "partial purge\npurge failed")
        XCTAssertEqual(viewModel.errorMessageKey, "purge.error.failed")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testPurgeBusyExecutionCannotStartTwiceAndCanCancel() async throws {
        let spy = PurgeProcessSpy(
            previewResults: [MoleCommandResult(stdout: "plan", stderr: "", exitCode: 0)]
        )
        await spy.setExecutionBlocked(true)
        let viewModel = PurgeViewModel(process: spy)

        await viewModel.previewPurge()
        viewModel.requestConfirmation()
        let execution = Task { @MainActor in await viewModel.confirmExecution() }

        try await spy.waitForInvocationCount(2)
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

private struct PurgeInvocation: Equatable, Sendable {
    let arguments: [String]
    let stdin: Data?
}

private actor PurgeProcessSpy: MoleProcessControlling {
    private(set) var invocations: [PurgeInvocation] = []
    private(set) var cancelCount = 0
    private var previewResults: [MoleCommandResult]
    private let executionResult: MoleCommandResult
    private var blockExecution = false
    private var executionContinuation: CheckedContinuation<MoleCommandResult, Error>?

    init(
        previewResults: [MoleCommandResult],
        executionResult: MoleCommandResult = MoleCommandResult(
            stdout: "purged",
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
        invocations.append(PurgeInvocation(arguments: arguments, stdin: stdin))
        if arguments == ["purge", "--dry-run"] {
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
        throw PurgeSpyWaitError.timeout
    }
}

private enum PurgeSpyWaitError: Error {
    case timeout
}
