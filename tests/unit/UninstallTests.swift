import XCTest
@testable import Zmole

final class UninstallTests: XCTestCase {
    @MainActor
    // Replaces the old source-text wiring test. UI semantics are now verified
    // through the accessibility description consumed by the production row.
    func testUninstallAccessibilityKeepsCompleteApplicationIdentityReachable() async throws {
        let spy = UninstallProcessSpy()
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallListFixture)

        await viewModel.loadList()

        let app = try XCTUnwrap(viewModel.apps.first)
        XCTAssertEqual(app.name, "Example")
        XCTAssertEqual(app.uninstallName, "Example")
        XCTAssertEqual(app.path, "/Applications/Example.app")
        XCTAssertEqual(app.bundleID, "com.example.app")

        let accessibilityDescription = UninstallAccessibility.description(for: app)
        XCTAssertTrue(accessibilityDescription.contains(app.name))
        XCTAssertTrue(accessibilityDescription.contains(app.uninstallName))
        XCTAssertTrue(accessibilityDescription.contains(app.path))
        XCTAssertTrue(accessibilityDescription.contains(app.bundleID))
    }

    @MainActor
    func testUninstallConfirmationOpensDirectlyFromSelection() async throws {
        let spy = UninstallProcessSpy()
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallListFixture)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        viewModel.requestConfirmation()

        XCTAssertTrue(viewModel.isConfirmationPresented)
        XCTAssertTrue(viewModel.canConfirm)
        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty, "opening the sheet must not spawn a preview process")
    }

    @MainActor
    func testUninstallConfirmationExecutesWithoutPermanentAndShowsSummary() async throws {
        let spy = UninstallProcessSpy(
            executionResult: MoleCommandResult(
                stdout: "Successfully uninstalled Example",
                stderr: "",
                exitCode: 0
            )
        )
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallListFixture)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["uninstall", "Example"]])
        XCTAssertEqual(invocations[0].stdin, Data("y\n".utf8))
        XCTAssertFalse(invocations.contains { $0.arguments.contains("--permanent") })
        XCTAssertFalse(
            invocations.contains { $0.arguments.contains("--list") },
            "confirm must reuse the session list instead of rescanning sizes"
        )
        XCTAssertEqual(viewModel.executionSummary, "Successfully uninstalled Example")
        XCTAssertNil(viewModel.result?.errorKey)
    }

    @MainActor
    func testUninstallNoSelectionDoesNotOpenConfirmationOrExecute() async throws {
        let spy = UninstallProcessSpy()
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallListFixture)

        await viewModel.loadList()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertFalse(viewModel.isConfirmationPresented)
        XCTAssertFalse(viewModel.canUninstall)
    }

    @MainActor
    func testUninstallDuplicateNameCannotConfirm() async throws {
        let spy = UninstallProcessSpy()
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallDuplicateListFixture)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        viewModel.requestConfirmation()

        let invocations = await spy.invocations
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.error.ambiguous")
        XCTAssertFalse(viewModel.isConfirmationPresented)
    }

    @MainActor
    func testChangingSelectionRebuildsTheConfirmationBatch() async throws {
        let spy = UninstallProcessSpy()
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallTwoAppsFixture)

        await viewModel.loadList()
        let first = try XCTUnwrap(viewModel.apps.first)
        let second = try XCTUnwrap(viewModel.apps.last)
        viewModel.toggleSelection(first)
        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.isConfirmationPresented)

        viewModel.toggleSelection(second)
        XCTAssertFalse(viewModel.isConfirmationPresented, "changing the selection closes the stale sheet")
        XCTAssertFalse(viewModel.canConfirm)

        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["uninstall", "First", "Second"]
        ])
    }

    @MainActor
    // Replaces the former "changed path" and "missing target" list-rescan
    // tests: identity is now checked cheaply at confirm time via the injected
    // target checker, and a mismatch refuses execution and re-scans the list.
    func testUninstallChangedTargetCannotExecuteAndRescansTheList() async throws {
        let spy = UninstallProcessSpy()
        let counter = CountingListStream(rows: UninstallFixture.rows(from: Self.uninstallListFixture))
        let viewModel = UninstallViewModel(
            process: spy,
            listStream: counter.makeStream(),
            coordinator: OperationCoordinator(),
            targetChecker: FixedTargetChecker(matches: false),
            iconProvider: NoopIconProvider()
        )

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertTrue(
            invocations.isEmpty,
            "a changed target must not spawn the uninstall command"
        )
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.error.changed_target")
        XCTAssertEqual(counter.opens, 2, "the refused execution must re-scan the list")
        XCTAssertEqual(viewModel.listings.map(\.path).count, Set(viewModel.listings.map(\.path)).count,
                       "the re-scan must not duplicate rows")
        XCTAssertEqual(viewModel.listings.count, 1, "the re-scan replaces the listing")
    }

    @MainActor
    func testBatchUninstallResultPreservesStructuredPartialOutcome() async throws {
        let spy = UninstallProcessSpy(
            executionResult: MoleCommandResult(
                stdout: "Successfully uninstalled Example\nFailed to remove Example data",
                stderr: "",
                exitCode: 9
            )
        )
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallListFixture)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        XCTAssertEqual(
            viewModel.executionSummary,
            "Successfully uninstalled Example\nFailed to remove Example data"
        )
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.error.failed")
        XCTAssertEqual(viewModel.result?.status, .partial)
    }

    @MainActor
    func testUninstallBusyExecutionCannotStartTwiceAndCanCancel() async throws {
        let spy = UninstallProcessSpy()
        await spy.setExecutionBlocked(true)
        let viewModel = makeUninstallViewModel(process: spy, listJSON: Self.uninstallListFixture)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        viewModel.requestConfirmation()
        let execution = Task { @MainActor in await viewModel.confirmExecution() }

        try await spy.waitForInvocationCount(1)
        XCTAssertTrue(viewModel.isExecuting)
        await viewModel.confirmExecution()
        let beforeCancel = await spy.invocations
        XCTAssertEqual(beforeCancel.filter { $0.arguments == ["uninstall", "Example"] }.count, 1)

        await viewModel.cancelExecution()
        await execution.value

        let cancelCount = await spy.cancelCount
        XCTAssertEqual(cancelCount, 1)
        XCTAssertFalse(viewModel.isExecuting)
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.cancelled")
    }

    fileprivate static let uninstallListFixture = """
    [
      {
        "name": "Example",
        "bundle_id": "com.example.app",
        "source": "App",
        "uninstall_name": "Example",
        "path": "/Applications/Example.app",
        "size": "1 MB"
      }
    ]
    """

    fileprivate static let uninstallDuplicateListFixture = """
    [
      {
        "name": "Example",
        "bundle_id": "com.example.one",
        "source": "App",
        "uninstall_name": "Example",
        "path": "/Applications/Example.app",
        "size": "1 MB"
      },
      {
        "name": "Example Copy",
        "bundle_id": "com.example.two",
        "source": "App",
        "uninstall_name": "Example",
        "path": "/Applications/Example Copy.app",
        "size": "1 MB"
      }
    ]
    """

    fileprivate static let uninstallTwoAppsFixture = """
    [
      {
        "name": "First",
        "bundle_id": "com.example.first",
        "source": "App",
        "uninstall_name": "First",
        "path": "/Applications/First.app",
        "size": "1 MB"
      },
      {
        "name": "Second",
        "bundle_id": "com.example.second",
        "source": "App",
        "uninstall_name": "Second",
        "path": "/Applications/Second.app",
        "size": "1 MB"
      }
    ]
    """
}

private struct UninstallInvocation: Equatable, Sendable {
    let arguments: [String]
    let stdin: Data?
}

private actor UninstallProcessSpy: MoleProcessControlling {
    private(set) var invocations: [UninstallInvocation] = []
    private(set) var cancelCount = 0
    private let executionResult: MoleCommandResult
    private var blockExecution = false
    private var executionContinuation: CheckedContinuation<MoleCommandResult, Error>?

    init(
        executionResult: MoleCommandResult = MoleCommandResult(
            stdout: "uninstalled selected app",
            stderr: "",
            exitCode: 0
        )
    ) {
        self.executionResult = executionResult
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations.append(UninstallInvocation(arguments: arguments, stdin: stdin))
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
        throw UninstallSpyWaitError.timeout
    }
}

private enum UninstallSpyWaitError: Error {
    case timeout
}
