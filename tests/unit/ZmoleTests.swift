import XCTest
@testable import Zmole

final class ZmoleTests: XCTestCase {
    // The former `testTopModeContainsFivePrimaryWorkModes` and
    // `testTopModeDoesNotExposeSecondaryOrUnsupportedCommands` asserted the
    // retired top five-mode bar. The sidebar shell replaces that navigation, so
    // those tests are removed and their intent is re-covered by
    // `NavigationTests` against the ten-destination model.

    func testDemoConfigurationSelectsPageLanguageAndAppearance() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-demo-data", isDirectory: true)
        let configuration = DemoConfiguration(arguments: [
            "zmole", "--demo", "--demo-page", "analyze",
            "--demo-state", "partial", "--demo-language", "zh-Hans", "--demo-appearance", "light",
            "--demo-data-root", root.path
        ])

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.page, .disk)
        XCTAssertEqual(configuration.state, .partial)
        XCTAssertEqual(configuration.language, .simplifiedChinese)
        XCTAssertEqual(configuration.appearance, .light)
        XCTAssertEqual(configuration.dataRoot?.standardizedFileURL, root.standardizedFileURL)
    }

    func testDemoConfigurationRejectsDataRootOutsideTemporaryDirectory() {
        let configuration = DemoConfiguration(arguments: [
            "zmole", "--demo", "--demo-data-root", "/tmp/zmole-demo-data"
        ])

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertNil(configuration.dataRoot)
    }

    func testDemoLanguageFlagsRequireDemoGate() {
        let configuration = DemoConfiguration(arguments: [
            "zmole", "--demo-language", "zh-Hans", "--demo-appearance", "light"
        ])

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertNil(configuration.language)
        XCTAssertNil(configuration.appearance)
    }

    @MainActor
    func testDemoDependenciesInjectCleanAndWhitelistPathsWithoutMoleConfig() async throws {
        let root = try makeTemporaryDirectory(prefix: "zmole-demo-data-root")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = DemoConfiguration(arguments: [
            "zmole", "--demo", "--demo-data-root", root.path
        ])

        let dependencies = AppDependencies(configuration: configuration)

        XCTAssertEqual(dependencies.demoDataRoot?.standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(
            dependencies.demoCleanPreviewURL?.standardizedFileURL,
            root.appendingPathComponent("clean-list.txt").standardizedFileURL
        )
        XCTAssertEqual(
            URL(fileURLWithPath: dependencies.whitelistViewModel.filePath).standardizedFileURL,
            root.appendingPathComponent("whitelist").standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(dependencies.whitelistViewModel.filePath.contains("/.config/mole/"))

        await dependencies.analyzeViewModel.loadOverview()
        XCTAssertEqual(dependencies.analyzeViewModel.currentPath, DemoDiskScanner.root)
    }

    @MainActor
    func testDemoUninstallExecutesOnlySelectedApplications() async throws {
        let root = try makeTemporaryDirectory(prefix: "zmole-demo-uninstall-confirm")
        defer { try? FileManager.default.removeItem(at: root) }
        let dependencies = AppDependencies(configuration: DemoConfiguration(arguments: [
            "zmole", "--demo", "--demo-page", "software", "--demo-data-root", root.path
        ]))
        let viewModel = dependencies.uninstallViewModel

        await viewModel.loadList()
        let selected = viewModel.apps.filter { ["Brew Tool", "Data Tools"].contains($0.name) }
        XCTAssertEqual(selected.count, 2)
        selected.forEach(viewModel.toggleSelection)
        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.isConfirmationPresented)

        await viewModel.confirmExecution()

        let summary = viewModel.executionSummary ?? ""
        XCTAssertTrue(summary.contains("Brew Tool"))
        XCTAssertTrue(summary.contains("Data Tools"))
        XCTAssertFalse(summary.contains("Demo Editor"))
        XCTAssertNil(viewModel.result?.errorKey)
    }

    @MainActor
    func testPopulatedDemoStatusKeepsSamplingUntilPaused() async throws {
        let root = try makeTemporaryDirectory(prefix: "zmole-demo-status-stream")
        defer { try? FileManager.default.removeItem(at: root) }
        let dependencies = AppDependencies(configuration: DemoConfiguration(arguments: [
            "zmole", "--demo", "--demo-page", "status", "--demo-state", "populated",
            "--demo-data-root", root.path
        ]))
        let viewModel = dependencies.statusViewModel

        viewModel.start()
        // Demo samples arrive every 800ms; wait with an upper bound instead of
        // a fixed sleep so a slow machine does not flake.
        for _ in 0..<200 where viewModel.snapshot == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNotNil(viewModel.snapshot)
        XCTAssertTrue(viewModel.isSampling)

        await viewModel.pause()
        XCTAssertFalse(viewModel.isSampling)
        XCTAssertTrue(viewModel.isPaused)
    }

    // Renamed and re-keyed in t035: the status rebuild retired the old
    // metric-detail cards, and these are the metric labels the page renders
    // now. Same intent: every status metric label is localized in three
    // languages.
    func testStatusStatKeysHaveLocalizedValues() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        for key in ["status.stat.cpu", "status.stat.memory", "status.stat.disk_write", "status.stat.temperature"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for locale in ["en", "zh-Hans", "zh-Hant"] {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertFalse(value.isEmpty)
                XCTAssertNotEqual(value, key)
            }
        }
    }

    func testReleasesURLIsTheProjectReleasePage() {
        XCTAssertEqual(
            AppLinks.releasesURL.absoluteString,
            "https://github.com/TuTouPower/zmole/releases"
        )
    }

    // DestructiveConfirmationFlow and the StatusViewModel one-shot refresh
    // path (with its StatusSnapshotLoader) were removed together with their
    // only call sites; confirmation now runs through OperationSession and the
    // status page owns a watch stream (behavior covered by StatusStreamTests
    // and the OperationSession tests). The former flow/loader/refresh tests
    // were deleted with those APIs.

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
        XCTAssertEqual(invalidViewModel.errorMessageKey, "history.error.invalid_json")
        XCTAssertNil(invalidViewModel.errorMessage)

        let failedLoader = HistorySnapshotLoader { _ in
            throw MoleBridgeError.commandFailed(
                MoleCommandResult(stdout: "", stderr: "history failed", exitCode: 9)
            )
        }
        let failedViewModel = HistoryViewModel(loader: failedLoader)

        await failedViewModel.refresh()

        XCTAssertNil(failedViewModel.snapshot)
        XCTAssertEqual(failedViewModel.errorMessageKey, "mole.error.command_failed")
        XCTAssertNil(failedViewModel.errorMessage)
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

        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL), coordinator: OperationCoordinator())
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

        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL), coordinator: OperationCoordinator())
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

        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL), coordinator: OperationCoordinator())
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
        let viewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL), coordinator: OperationCoordinator())

        viewModel.load()
        viewModel.newPattern = "~/safe"
        viewModel.addPattern()
        viewModel.save()

        XCTAssertEqual(viewModel.filePath, fileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // The former testWhitelistEditorDoesNotRunMoleProcess asserted that the
    // editor never invokes its injected mole process; the unused moleProcess
    // dependency was removed, so that assertion has no subject anymore. The
    // "editor writes only the whitelist file" behavior stays covered by
    // testWhitelistEditorSavesPatternsToStore above.

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

    // The former mole-driven disk ViewModel tests moved to DiskExplorerTests,
    // which drives the same navigation states through an injected directory
    // source instead of `analyze --json` command recording.

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
