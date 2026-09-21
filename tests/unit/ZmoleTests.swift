import XCTest
@testable import Zmole

final class ZmoleTests: XCTestCase {
    func testSidebarContainsTheFirstVersionNavigation() {
        XCTAssertEqual(
            SidebarItem.allCases.map(\.rawValue),
            [
                "status", "history", "analyze", "clean", "uninstall", "optimize",
                "purge", "whitelist", "settings"
            ]
        )
    }

    func testSidebarDoesNotExposeInstallerUpdateOrRemove() {
        let forbidden = ["installer", "update", "remove"]
        XCTAssertTrue(
            Set(SidebarItem.allCases.map(\.rawValue)).isDisjoint(with: forbidden)
        )
    }

    func testReleasesURLIsTheProjectReleasePage() {
        XCTAssertEqual(
            AppLinks.releasesURL.absoluteString,
            "https://github.com/TuTouPower/zmole/releases"
        )
    }

    func testCancellingDestructiveConfirmationDoesNotExecuteAction() {
        var executed = false
        let flow = DestructiveConfirmationFlow { executed = true }

        flow.cancel()

        XCTAssertFalse(executed)
        XCTAssertFalse(flow.isPending)
    }

    func testStatusLoaderPassesExplicitJSONArgumentsAndDecodesMetrics() async throws {
        let recorder = CommandRecorder()
        let loader = StatusSnapshotLoader { arguments in
            await recorder.record(arguments)
            return MoleCommandResult(stdout: Self.statusFixture, stderr: "", exitCode: 0)
        }

        let snapshot = try await loader.load()

        let arguments = await recorder.arguments
        XCTAssertEqual(arguments, ["status", "--json"])
        XCTAssertEqual(snapshot.healthScore, 100)
        XCTAssertEqual(snapshot.cpu.usage, 33.033730353481815)
        XCTAssertEqual(snapshot.memory.used, 36_889_788_416)
        XCTAssertEqual(snapshot.disks.first?.total, 994_662_584_320)
    }

    @MainActor
    func testStatusViewModelClearsSuccessDataWhenRefreshFails() async {
        let sequence = CommandSequence(outputs: [
            Self.statusFixture,
            "{not-json"
        ])
        let loader = StatusSnapshotLoader { _ in
            await sequence.next()
        }
        let viewModel = StatusViewModel(loader: loader)

        await viewModel.refresh()
        XCTAssertNotNil(viewModel.snapshot)

        await viewModel.refresh()
        XCTAssertNil(viewModel.snapshot)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testStatusViewModelShowsCommandFailureWithoutStaleData() async {
        let loader = StatusSnapshotLoader { _ in
            throw MoleBridgeError.commandFailed(
                MoleCommandResult(stdout: "", stderr: "status failed", exitCode: 7)
            )
        }
        let viewModel = StatusViewModel(loader: loader)

        await viewModel.refresh()

        XCTAssertNil(viewModel.snapshot)
        XCTAssertEqual(viewModel.errorMessage, "mole 命令失败（7）：status failed")
    }

    func testHistoryLoaderUsesDefaultLimitAndDecodesSessionSummary() async throws {
        let recorder = CommandRecorder()
        let loader = HistorySnapshotLoader { arguments in
            await recorder.record(arguments)
            return MoleCommandResult(stdout: Self.historyFixture, stderr: "", exitCode: 0)
        }

        let snapshot = try await loader.load()

        let arguments = await recorder.arguments
        XCTAssertEqual(arguments, ["history", "--json", "--limit", "20"])
        XCTAssertEqual(snapshot.sessions.first?.command, "clean")
        XCTAssertEqual(snapshot.sessions.first?.dateText, "2026-09-21T12:59:00+08:00")
    }

    func testHistoryDisplayStateProjectsSessionAndEmptyUIStates() throws {
        let decoder = JSONDecoder()
        let populated = try decoder.decode(
            HistorySnapshot.self,
            from: Data(Self.historyFixture.utf8)
        )
        let empty = try decoder.decode(
            HistorySnapshot.self,
            from: Data(Self.emptyHistoryFixture.utf8)
        )

        guard case let .content(sessions, _) = populated.displayState else {
            return XCTFail("expected populated display state")
        }
        XCTAssertEqual(sessions.first?.command, "clean")
        XCTAssertEqual(sessions.first?.dateText, "2026-09-21T12:59:00+08:00")
        XCTAssertEqual(empty.displayState, .empty)
    }

    func testHistoryLoaderUsesRequestedLimitWithoutSendingZero() async throws {
        let recorder = CommandRecorder()
        let loader = HistorySnapshotLoader { arguments in
            await recorder.record(arguments)
            return MoleCommandResult(stdout: Self.emptyHistoryFixture, stderr: "", exitCode: 0)
        }

        _ = try await loader.load(limit: 1)

        let arguments = await recorder.arguments
        XCTAssertEqual(arguments, ["history", "--json", "--limit", "1"])
    }

    @MainActor
    func testHistoryViewModelKeepsSuccessfulEmptyResponseDistinctFromFailure() async {
        let loader = HistorySnapshotLoader { _ in
            MoleCommandResult(stdout: Self.emptyHistoryFixture, stderr: "", exitCode: 0)
        }
        let viewModel = HistoryViewModel(loader: loader)

        await viewModel.refresh()

        XCTAssertNotNil(viewModel.snapshot)
        XCTAssertTrue(viewModel.snapshot?.sessions.isEmpty == true)
        XCTAssertTrue(viewModel.snapshot?.deletions.isEmpty == true)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testHistoryViewModelShowsFailureForInvalidJSONAndNonZeroExit() async {
        let invalidLoader = HistorySnapshotLoader { _ in
            MoleCommandResult(stdout: "{not-json", stderr: "", exitCode: 0)
        }
        let invalidViewModel = HistoryViewModel(loader: invalidLoader)

        await invalidViewModel.refresh()

        XCTAssertNil(invalidViewModel.snapshot)
        XCTAssertNotNil(invalidViewModel.errorMessage)

        let failedLoader = HistorySnapshotLoader { _ in
            throw MoleBridgeError.commandFailed(
                MoleCommandResult(stdout: "", stderr: "history failed", exitCode: 9)
            )
        }
        let failedViewModel = HistoryViewModel(loader: failedLoader)

        await failedViewModel.refresh()

        XCTAssertNil(failedViewModel.snapshot)
        XCTAssertEqual(failedViewModel.errorMessage, "mole 命令失败（9）：history failed")
    }

    private static let statusFixture = """
    {
      "health_score": 100,
      "cpu": {"usage": 33.033730353481815},
      "memory": {"used": 36889788416, "total": 68719476736, "used_percent": 53.68170738220215},
      "disks": [{"mount": "/", "used": 663408778609, "total": 994662584320, "used_percent": 66.69686676336968}]
    }
    """

    private static let historyFixture = """
    {
      "logs": {"operations": "operations.log", "deletions": "deletions.log"},
      "limit": 20,
      "sessions": [{
        "command": "clean",
        "started_at": "2026-09-21T12:59:00+08:00",
        "ended_at": "",
        "items": 3,
        "size": "1.2 GB",
        "operation_count": 3,
        "failed_tasks": 0,
        "actions": {"removed": 2, "trashed": 1, "skipped": 0, "failed": 0, "rebuilt": 0, "other": 0}
      }],
      "deletions": []
    }
    """

    private static let emptyHistoryFixture = """
    {
      "logs": {"operations": "operations.log", "deletions": "deletions.log"},
      "limit": 20,
      "sessions": [],
      "deletions": []
    }
    """
}

private actor CommandRecorder {
    private(set) var arguments: [String] = []

    func record(_ arguments: [String]) {
        self.arguments = arguments
    }
}

private actor CommandSequence {
    private var outputs: [String]

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func next() -> MoleCommandResult {
        MoleCommandResult(stdout: outputs.removeFirst(), stderr: "", exitCode: 0)
    }
}
