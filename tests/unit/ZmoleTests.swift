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

    func testWhitelistStoreListsPatternsAndPreservesComments() throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-whitelist-store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        try "# header\n\n/Users/example/Library/Caches/*\n# inline note\n~/keep\n"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let store = WhitelistStore(fileURL: fileURL)
        let document = try store.load()

        XCTAssertEqual(
            document.patterns,
            ["/Users/example/Library/Caches/*", "~/keep"]
        )
        XCTAssertEqual(document.comments, ["# header", "# inline note"])

        try store.save(document.replacingPatterns(["~/keep", "~/new"]))
        let savedContents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(savedContents.contains("# header"))
        XCTAssertTrue(savedContents.contains("# inline note"))
        XCTAssertTrue(savedContents.contains("~/new"))
        XCTAssertFalse(savedContents.contains("/Users/example/Library/Caches/*"))
    }

    @MainActor
    func testWhitelistViewModelAddsDeletesAndSavesPatterns() throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-whitelist-view-model")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        try "# Mole header\n\n~/existing\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL))
        viewModel.load()
        XCTAssertEqual(viewModel.patterns.map(\.value), ["~/existing"])

        viewModel.newPattern = " ~/added "
        viewModel.addPattern()
        viewModel.save()

        var savedContents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(savedContents.contains("~/existing"))
        XCTAssertTrue(savedContents.contains("~/added"))
        XCTAssertTrue(viewModel.didSave)

        let existingID = try XCTUnwrap(viewModel.patterns.first?.id)
        viewModel.removePattern(id: existingID)
        viewModel.save()

        savedContents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(savedContents.contains("~/existing"))
        XCTAssertTrue(savedContents.contains("~/added"))
        XCTAssertTrue(savedContents.contains("# Mole header"))
    }

    @MainActor
    func testWhitelistViewModelRemovesOneDuplicatePattern() throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-whitelist-duplicate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        try "# header\n~/duplicate\n~/duplicate\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL))
        viewModel.load()
        let firstID = try XCTUnwrap(viewModel.patterns.first?.id)
        viewModel.removePattern(id: firstID)
        viewModel.save()

        let savedLines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(savedLines.filter { $0 == "~/duplicate" }.count, 1)
    }

    @MainActor
    func testWhitelistViewModelCannotOverwriteAfterLoadFailure() throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-whitelist-load-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        let originalData = Data([0xFF, 0xFE, 0xFD])
        try originalData.write(to: fileURL)

        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL))
        viewModel.load()
        viewModel.newPattern = "~/must-not-overwrite"
        viewModel.addPattern()
        viewModel.save()

        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    @MainActor
    func testWhitelistEditorUsesOnlyInjectedFilePath() throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-whitelist-no-mole")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL))

        viewModel.load()
        viewModel.newPattern = "~/safe"
        viewModel.addPattern()
        viewModel.save()

        XCTAssertEqual(viewModel.filePath, fileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @MainActor
    func testWhitelistEditorDoesNotRunMoleProcess() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-whitelist-no-process")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        let spy = WhitelistMoleProcessSpy()
        let viewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: fileURL),
            moleProcess: spy
        )

        viewModel.load()
        viewModel.newPattern = "~/safe"
        viewModel.addPattern()
        viewModel.save()

        let invocationCount = await spy.invocations
        XCTAssertEqual(invocationCount, 0)
    }

    @MainActor
    func testCleanPreviewUsesDryRunAndCurrentList() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-preview")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let spy = CleanProcessSpy(previewFileURL: listURL)
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()

        let arguments = await spy.arguments
        XCTAssertEqual(arguments, [["clean", "--dry-run"]])
        XCTAssertEqual(viewModel.preview?.entries, ["/tmp/cache # 1KB"])
        XCTAssertTrue(viewModel.canConfirm)
    }

    @MainActor
    func testCleanConfirmationCancelExpiresPreviewWithoutExecution() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-cancel")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let spy = CleanProcessSpy(previewFileURL: listURL)
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()
        viewModel.requestConfirmation()
        viewModel.cancelConfirmation()
        await viewModel.confirmExecution()

        let arguments = await spy.arguments
        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertEqual(arguments, [["clean", "--dry-run"]])
    }

    @MainActor
    func testCleanConfirmationRunsCleanWithoutDryRun() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-execute")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let spy = CleanProcessSpy(previewFileURL: listURL)
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let arguments = await spy.arguments
        XCTAssertEqual(arguments, [["clean", "--dry-run"], ["clean"]])
        XCTAssertNil(viewModel.preview)
    }

    @MainActor
    func testCleanPreviewFailureOrMissingListCannotConfirm() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        try "old preview\n".write(to: listURL, atomically: true, encoding: .utf8)
        let spy = CleanProcessSpy(previewFileURL: listURL, writesPreviewFile: false)
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()

        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertTrue(viewModel.errorMessage != nil || viewModel.errorMessageKey != nil)
    }

    @MainActor
    func testCleanNonZeroDryRunCannotConfirmOrExecute() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-dry-run-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let spy = CleanProcessSpy(
            previewFileURL: listURL,
            dryRunResult: MoleCommandResult(stdout: "partial preview", stderr: "dry-run failed", exitCode: 7)
        )
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()
        await viewModel.confirmExecution()

        let arguments = await spy.arguments
        XCTAssertNil(viewModel.preview)
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertEqual(arguments, [["clean", "--dry-run"]])
    }

    func testCleanExecutionNoteUsesLocalizedCatalogKey() throws {
        XCTAssertEqual(CleanViewCopy.executionNoteKey, "clean.execution_note")
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[CleanViewCopy.executionNoteKey] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let cleanViewURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("../Features/Clean/CleanView.swift")
            .standardizedFileURL
        let cleanViewSource = try String(contentsOf: cleanViewURL, encoding: .utf8)
        XCTAssertTrue(
            cleanViewSource.contains("Text(LocalizedStringKey(CleanViewCopy.executionNoteKey))"),
            "CleanView must render the execution rescan note"
        )
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
            let stringUnit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(stringUnit["value"] as? String)
            switch locale {
            case "en":
                XCTAssertTrue(value.contains("rescan"))
                XCTAssertTrue(value.contains("list may change"))
            case "zh-Hans":
                XCTAssertTrue(value.contains("重新扫描"))
                XCTAssertTrue(value.contains("列表可能变化"))
            case "zh-Hant":
                XCTAssertTrue(value.contains("重新掃描"))
                XCTAssertTrue(value.contains("列表可能變化"))
            default:
                XCTFail("unexpected locale")
            }
        }
    }

    @MainActor
    func testCleanDuplicateExecutionCreatesOneProcess() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-busy")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let spy = CleanProcessSpy(previewFileURL: listURL)
        await spy.setExecutionBlocked(true)
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()
        viewModel.requestConfirmation()
        let first = Task { @MainActor in await viewModel.confirmExecution() }
        try await spy.waitForArgumentCount(2)
        XCTAssertTrue(viewModel.isExecuting)
        let second = Task { @MainActor in await viewModel.confirmExecution() }
        await second.value

        let arguments = await spy.arguments
        XCTAssertEqual(arguments, [["clean", "--dry-run"], ["clean"]])

        await spy.finishExecution()
        await first.value
    }

    @MainActor
    func testCleanCancelCallsBridgeCancelAndEndsExecution() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-execution-cancel")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let spy = CleanProcessSpy(previewFileURL: listURL)
        await spy.setExecutionBlocked(true)
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()
        viewModel.requestConfirmation()
        let execution = Task { @MainActor in await viewModel.confirmExecution() }
        try await spy.waitForArgumentCount(2)
        await viewModel.cancelExecution()
        await execution.value

        let cancelCount = await spy.cancelCount
        XCTAssertEqual(cancelCount, 1)
        XCTAssertFalse(viewModel.isExecuting)
    }

    @MainActor
    func testCleanExecutionFailureShowsSummaryError() async throws {
        let directory = try makeTemporaryDirectory(prefix: "zmole-clean-execution-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let spy = CleanProcessSpy(
            previewFileURL: listURL,
            executionResult: MoleCommandResult(
                stdout: "partial output",
                stderr: "clean failed",
                exitCode: 9
            )
        )
        let viewModel = CleanViewModel(
            process: spy,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        XCTAssertNil(viewModel.preview)
        XCTAssertTrue(viewModel.errorMessage?.contains("9") == true)
        XCTAssertEqual(viewModel.executionSummary, "partial output\nclean failed")
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

        for _ in 0..<1_000 where !viewModel.isLoading {
            try? await Task.sleep(nanoseconds: 1_000_000)
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

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
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

private actor WhitelistMoleProcessSpy: MoleCommandRunning {
    private(set) var invocations = 0

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations += 1
        return MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

private actor CleanProcessSpy: MoleProcessControlling {
    private(set) var arguments: [[String]] = []
    private(set) var cancelCount = 0
    private let previewFileURL: URL?
    private let writesPreviewFile: Bool
    private let dryRunResult: MoleCommandResult
    private let executionResult: MoleCommandResult
    private var blockExecution = false
    private var executionContinuation: CheckedContinuation<MoleCommandResult, Error>?

    init(
        previewFileURL: URL?,
        writesPreviewFile: Bool = true,
        dryRunResult: MoleCommandResult = MoleCommandResult(stdout: "", stderr: "", exitCode: 0),
        executionResult: MoleCommandResult = MoleCommandResult(stdout: "cleaned", stderr: "", exitCode: 0)
    ) {
        self.previewFileURL = previewFileURL
        self.writesPreviewFile = writesPreviewFile
        self.dryRunResult = dryRunResult
        self.executionResult = executionResult
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        self.arguments.append(arguments)
        if arguments == ["clean", "--dry-run"] {
            if writesPreviewFile, let previewFileURL {
                try FileManager.default.createDirectory(
                    at: previewFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try "# preview\n=== Cache ===\n/tmp/cache # 1KB\n".write(
                    to: previewFileURL,
                    atomically: true,
                    encoding: .utf8
                )
            }
            return dryRunResult
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

    func finishExecution() {
        executionContinuation?.resume(returning: executionResult)
        executionContinuation = nil
    }

    func waitForArgumentCount(_ count: Int) async throws {
        for _ in 0..<1_000 {
            if arguments.count >= count { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        throw CleanSpyWaitError.timeout
    }
}

private enum CleanSpyWaitError: Error {
    case timeout
}
