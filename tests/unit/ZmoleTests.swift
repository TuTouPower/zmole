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

    func testAnalyzeLoaderUsesJSONBeforeOverviewPathAndDecodesEntries() async throws {
        let recorder = CommandRecorder()
        let loader = AnalyzeSnapshotLoader { arguments in
            await recorder.record(arguments)
            return MoleCommandResult(stdout: Self.analyzeOverviewFixture, stderr: "", exitCode: 0)
        }

        let snapshot = try await loader.load()

        let arguments = await recorder.arguments
        XCTAssertEqual(arguments, ["analyze", "--json"])
        XCTAssertEqual(snapshot.entries.first?.name, "Applications")
        XCTAssertEqual(snapshot.entries.first?.size, 34_400_550_912)
    }

    func testAnalyzeDisplayStateProjectsOverviewAndDirectoryEntries() throws {
        let decoder = JSONDecoder()
        let overview = try decoder.decode(
            AnalyzeSnapshot.self,
            from: Data(Self.analyzeOverviewFixture.utf8)
        )
        let directory = try decoder.decode(
            AnalyzeSnapshot.self,
            from: Data(Self.analyzePathFixture.utf8)
        )

        XCTAssertEqual(overview.displayState.path, "/")
        XCTAssertEqual(overview.displayState.entries.first?.name, "Applications")
        XCTAssertEqual(overview.displayState.entries.first?.size, 34_400_550_912)
        XCTAssertEqual(directory.displayState.path, "/Applications")
        XCTAssertEqual(directory.displayState.entries.first?.name, "Utilities")
        XCTAssertEqual(directory.displayState.entries.first?.size, 1024)
    }

    @MainActor
    func testAnalyzeViewModelNavigatesToDirectoryAndBack() async {
        let sequence = AnalyzeCommandSequence(results: [
            (Self.analyzeOverviewFixture, ["analyze", "--json"]),
            (Self.analyzePathFixture, ["analyze", "--json", "/Applications"]),
            (Self.analyzeOverviewFixture, ["analyze", "--json"])
        ])
        let loader = AnalyzeSnapshotLoader { arguments in
            await sequence.next(arguments)
        }
        let viewModel = AnalyzeViewModel(loader: loader)

        await viewModel.loadOverview()
        XCTAssertEqual(viewModel.snapshot?.path, "/")

        let directory = AnalyzeEntry(
            name: "Applications", path: "/Applications", size: 1, isDirectory: true
        )
        await viewModel.openDirectory(directory)
        XCTAssertEqual(viewModel.snapshot?.path, "/Applications")
        XCTAssertEqual(viewModel.snapshot?.entries.first?.name, "Utilities")
        XCTAssertEqual(viewModel.snapshot?.entries.first?.size, 1024)
        XCTAssertTrue(viewModel.canGoBack)

        await viewModel.goBack()
        XCTAssertEqual(viewModel.snapshot?.path, "/")
        XCTAssertFalse(viewModel.canGoBack)

        let arguments = await sequence.recordedArguments
        XCTAssertEqual(
            arguments,
            [
                ["analyze", "--json"],
                ["analyze", "--json", "/Applications"],
                ["analyze", "--json"]
            ]
        )
    }

    @MainActor
    func testAnalyzeViewModelIgnoresBackWhileDirectoryLoads() async {
        let command = BlockingAnalyzeCommand()
        let loader = AnalyzeSnapshotLoader { arguments in
            await command.run(arguments)
        }
        let viewModel = AnalyzeViewModel(loader: loader)

        await viewModel.loadOverview()
        let directory = AnalyzeEntry(
            name: "Applications", path: "/Applications", size: 1, isDirectory: true
        )
        let loadTask = Task { @MainActor in
            await viewModel.openDirectory(directory)
        }

        for _ in 0..<10 where !viewModel.isLoading {
            await Task.yield()
        }
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.canGoBack)

        await viewModel.goBack()

        let arguments = await command.recordedArguments
        XCTAssertEqual(
            arguments,
            [
                ["analyze", "--json"],
                ["analyze", "--json", "/Applications"]
            ]
        )

        await command.finishDirectoryLoad()
        await loadTask.value
        XCTAssertEqual(viewModel.snapshot?.path, "/Applications")
    }

    @MainActor
    func testAnalyzeViewModelShowsFailureWithoutDeleteAction() async {
        let loader = AnalyzeSnapshotLoader { _ in
            throw MoleBridgeError.commandFailed(
                MoleCommandResult(stdout: "", stderr: "analyze failed", exitCode: 8)
            )
        }
        let viewModel = AnalyzeViewModel(loader: loader)

        await viewModel.loadOverview()

        XCTAssertNil(viewModel.snapshot)
        XCTAssertEqual(viewModel.errorMessage, "mole 命令失败（8）：analyze failed")
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

    fileprivate static let analyzeOverviewFixture = """
    {
      "path": "/",
      "overview": true,
      "entries": [{"name": "Applications", "path": "/Applications", "size": 34400550912, "is_dir": true}],
      "total_size": 41304723772
    }
    """

    fileprivate static let analyzePathFixture = """
    {
      "path": "/Applications",
      "overview": false,
      "entries": [{"name": "Utilities", "path": "/Applications/Utilities", "size": 1024, "is_dir": true}],
      "total_size": 1024,
      "total_files": 1
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

private actor AnalyzeCommandSequence {
    private var results: [(String, [String])]
    private(set) var recordedArguments: [[String]] = []

    init(results: [(String, [String])]) {
        self.results = results
    }

    func next(_ arguments: [String]) -> MoleCommandResult {
        let result = results.removeFirst()
        recordedArguments.append(arguments)
        return MoleCommandResult(stdout: result.0, stderr: "", exitCode: 0)
    }
}

private actor BlockingAnalyzeCommand {
    private(set) var recordedArguments: [[String]] = []
    private var directoryContinuation: CheckedContinuation<MoleCommandResult, Never>?

    func run(_ arguments: [String]) async -> MoleCommandResult {
        recordedArguments.append(arguments)
        guard arguments.last == "/Applications" else {
            return MoleCommandResult(stdout: ZmoleTests.analyzeOverviewFixture, stderr: "", exitCode: 0)
        }

        return await withCheckedContinuation { continuation in
            directoryContinuation = continuation
        }
    }

    func finishDirectoryLoad() {
        directoryContinuation?.resume(
            returning: MoleCommandResult(
                stdout: ZmoleTests.analyzePathFixture,
                stderr: "",
                exitCode: 0
            )
        )
        directoryContinuation = nil
    }
}
