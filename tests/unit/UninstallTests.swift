import XCTest
@testable import Zmole

final class UninstallTests: XCTestCase {
    @MainActor
    func testUninstallListDecodesDisplayedFieldsAndViewWiring() async throws {
        let spy = UninstallProcessSpy(listResults: [
            MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0)
        ])
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()

        let app = try XCTUnwrap(viewModel.apps.first)
        XCTAssertEqual(app.name, "Example")
        XCTAssertEqual(app.uninstallName, "Example")
        XCTAssertEqual(app.path, "/Applications/Example.app")
        XCTAssertEqual(app.bundleID, "com.example.app")

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Uninstall/UninstallView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("Text(app.name)"))
        XCTAssertTrue(source.contains("Text(app.uninstallName)"))
        XCTAssertTrue(source.contains("Text(app.path)"))
        XCTAssertTrue(source.contains("Text(app.bundleID)"))
    }

    @MainActor
    func testUninstallPreviewUsesSelectedNameAndConfirmationInput() async throws {
        let spy = UninstallProcessSpy(listResults: [
            MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0)
        ])
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        let app = try XCTUnwrap(viewModel.apps.first)
        viewModel.toggleSelection(app)
        await viewModel.previewUninstall()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["uninstall", "--list"],
            ["uninstall", "--dry-run", "Example"]
        ])
        XCTAssertEqual(invocations[1].stdin, Data("y\n".utf8))
        XCTAssertTrue(viewModel.canConfirm)
    }

    @MainActor
    func testUninstallConfirmationExecutesWithoutPermanentAndShowsSummary() async throws {
        let spy = UninstallProcessSpy(
            listResults: [
                MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0),
                MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0)
            ],
            executionResult: MoleCommandResult(
                stdout: "moved Example to Trash",
                stderr: "",
                exitCode: 0
            )
        )
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        await viewModel.previewUninstall()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["uninstall", "--list"],
            ["uninstall", "--dry-run", "Example"],
            ["uninstall", "--list"],
            ["uninstall", "Example"]
        ])
        XCTAssertEqual(invocations[3].stdin, Data("y\n".utf8))
        XCTAssertFalse(invocations.contains { $0.arguments.contains("--permanent") })
        XCTAssertEqual(viewModel.executionSummary, "moved Example to Trash")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testUninstallNoSelectionDoesNotPreviewOrExecute() async throws {
        let spy = UninstallProcessSpy(listResults: [
            MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0)
        ])
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        await viewModel.previewUninstall()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["uninstall", "--list"]])
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.error.no_selection")
        XCTAssertFalse(viewModel.canConfirm)
    }

    @MainActor
    func testUninstallDuplicateNameCannotPreview() async throws {
        let spy = UninstallProcessSpy(listResults: [
            MoleCommandResult(stdout: Self.uninstallDuplicateListFixture, stderr: "", exitCode: 0)
        ])
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        await viewModel.previewUninstall()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["uninstall", "--list"]])
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.error.ambiguous")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testUninstallChangingSelectionExpiresPreviewUntilNewPreview() async throws {
        let spy = UninstallProcessSpy(listResults: [
            MoleCommandResult(stdout: Self.uninstallTwoAppsFixture, stderr: "", exitCode: 0)
        ])
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        let first = try XCTUnwrap(viewModel.apps.first)
        let second = try XCTUnwrap(viewModel.apps.last)
        viewModel.toggleSelection(first)
        await viewModel.previewUninstall()
        XCTAssertTrue(viewModel.canConfirm)

        viewModel.toggleSelection(second)
        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)

        await viewModel.previewUninstall()
        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["uninstall", "--list"],
            ["uninstall", "--dry-run", "First"],
            ["uninstall", "--dry-run", "Second"]
        ])
        XCTAssertEqual(viewModel.preview?.target.uninstallName, "Second")
    }

    @MainActor
    func testUninstallChangedTargetCannotExecute() async throws {
        let spy = UninstallProcessSpy(listResults: [
            MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0),
            MoleCommandResult(stdout: Self.uninstallChangedPathFixture, stderr: "", exitCode: 0)
        ])
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        await viewModel.previewUninstall()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["uninstall", "--list"],
            ["uninstall", "--dry-run", "Example"],
            ["uninstall", "--list"]
        ])
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.error.changed_target")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testUninstallMissingTargetCannotExecute() async throws {
        let spy = UninstallProcessSpy(listResults: [
            MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0),
            MoleCommandResult(stdout: "[]", stderr: "", exitCode: 0)
        ])
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        await viewModel.previewUninstall()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.map(\.arguments), [
            ["uninstall", "--list"],
            ["uninstall", "--dry-run", "Example"],
            ["uninstall", "--list"]
        ])
        XCTAssertEqual(viewModel.errorMessageKey, "uninstall.error.changed_target")
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testUninstallAbortedPreviewCannotConfirm() async throws {
        let spy = UninstallProcessSpy(
            listResults: [
                MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0)
            ],
            previewResult: MoleCommandResult(
                stdout: "Proceed with uninstallation? [y/N]",
                stderr: "Aborted",
                exitCode: 1
            )
        )
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        await viewModel.previewUninstall()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertTrue(viewModel.errorMessage?.contains("Aborted") == true)
    }

    @MainActor
    func testUninstallExecutionFailureShowsSummary() async throws {
        let spy = UninstallProcessSpy(
            listResults: [
                MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0),
                MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0)
            ],
            executionResult: MoleCommandResult(
                stdout: "removed partial data",
                stderr: "uninstall failed",
                exitCode: 9
            )
        )
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        await viewModel.previewUninstall()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        XCTAssertEqual(viewModel.executionSummary, "removed partial data\nuninstall failed")
        XCTAssertTrue(viewModel.errorMessage?.contains("9") == true)
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testUninstallBusyExecutionCannotStartTwiceAndCanCancel() async throws {
        let spy = UninstallProcessSpy(
            listResults: [
                MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0),
                MoleCommandResult(stdout: Self.uninstallListFixture, stderr: "", exitCode: 0)
            ]
        )
        await spy.setExecutionBlocked(true)
        let viewModel = UninstallViewModel(process: spy)

        await viewModel.loadList()
        viewModel.toggleSelection(try XCTUnwrap(viewModel.apps.first))
        await viewModel.previewUninstall()
        viewModel.requestConfirmation()
        let execution = Task { @MainActor in await viewModel.confirmExecution() }

        try await spy.waitForInvocationCount(4)
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

    fileprivate static let uninstallChangedPathFixture = """
    [
      {
        "name": "Example",
        "bundle_id": "com.example.app",
        "source": "App",
        "uninstall_name": "Example",
        "path": "/Applications/Other.app",
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
    private var listResults: [MoleCommandResult]
    private let previewResult: MoleCommandResult
    private let executionResult: MoleCommandResult
    private var blockExecution = false
    private var executionContinuation: CheckedContinuation<MoleCommandResult, Error>?

    init(
        listResults: [MoleCommandResult],
        previewResult: MoleCommandResult = MoleCommandResult(
            stdout: "would uninstall selected app",
            stderr: "",
            exitCode: 0
        ),
        executionResult: MoleCommandResult = MoleCommandResult(
            stdout: "uninstalled selected app",
            stderr: "",
            exitCode: 0
        )
    ) {
        self.listResults = listResults
        self.previewResult = previewResult
        self.executionResult = executionResult
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations.append(UninstallInvocation(arguments: arguments, stdin: stdin))
        if arguments == ["uninstall", "--list"] {
            return listResults.isEmpty
                ? MoleCommandResult(stdout: "[]", stderr: "", exitCode: 0)
                : listResults.removeFirst()
        }
        if arguments.first == "uninstall", arguments.contains("--dry-run") {
            return previewResult
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
        throw UninstallSpyWaitError.timeout
    }
}

private enum UninstallSpyWaitError: Error {
    case timeout
}
