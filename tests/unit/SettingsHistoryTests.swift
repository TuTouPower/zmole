import XCTest
@testable import Zmole

@MainActor
final class SettingsHistoryTests: XCTestCase {
    func testEmptyHistoryShowsEmptyStateAndExportMatchesJSON() async throws {
        let emptyLoader = HistorySnapshotLoader { _ in
            MoleCommandResult(stdout: Self.emptyHistory, stderr: "", exitCode: 0)
        }
        let emptyViewModel = HistoryViewModel(loader: emptyLoader)
        await emptyViewModel.refresh()
        XCTAssertEqual(emptyViewModel.snapshot?.displayState, .empty)

        let loader = HistorySnapshotLoader { _ in
            MoleCommandResult(stdout: Self.history, stderr: "", exitCode: 0)
        }
        let viewModel = HistoryViewModel(loader: loader)
        await viewModel.refresh()
        guard case .content = viewModel.snapshot?.displayState else {
            return XCTFail("expected content")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")

        XCTAssertTrue(viewModel.export(to: url))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), Self.history)
    }

    func testAppAppearanceRoundTrip() {
        XCTAssertNil(AppAppearance(rawValue: "system")?.colorScheme)
        XCTAssertEqual(AppAppearance(rawValue: "light")?.colorScheme, .light)
        XCTAssertEqual(AppAppearance(rawValue: "dark")?.colorScheme, .dark)
        XCTAssertEqual(AppLanguage.storageKey, "languageOverride")
        XCTAssertEqual(AppAppearance.storageKey, "appearanceOverride")
    }

    func testLoginItemFailureKeepsToggleOffAndShowsReason() {
        let failing = FakeLoginItem(registerError: LoginItemError.registrationFailed("App is not in /Applications"))
        let viewModel = LoginItemViewModel(service: failing)
        viewModel.setEnabled(true)
        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertEqual(viewModel.failureReason, "App is not in /Applications")

        let working = FakeLoginItem()
        let successViewModel = LoginItemViewModel(service: working)
        successViewModel.setEnabled(true)
        XCTAssertTrue(successViewModel.isEnabled)
        XCTAssertNil(successViewModel.failureReason)
        successViewModel.setEnabled(false)
        XCTAssertFalse(successViewModel.isEnabled)
    }

    func testOptimizeWhitelistAcceptsTaskIDsOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("optimize-whitelist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("whitelist_optimize")
        try "# header\n# note\nsqlite_vacuum\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: fileURL),
            coordinator: OperationCoordinator(),
            kind: .optimize
        )
        viewModel.load()
        XCTAssertEqual(viewModel.patterns.map(\.value), ["sqlite_vacuum"])

        viewModel.newPattern = "not a task id"
        viewModel.addPattern()
        XCTAssertEqual(viewModel.errorMessageKey, "whitelist.error.invalid_task_id")
        XCTAssertFalse(viewModel.patterns.map(\.value).contains("not a task id"))

        viewModel.newPattern = "# comment"
        viewModel.addPattern()
        XCTAssertEqual(viewModel.errorMessageKey, "whitelist.error.comment")

        viewModel.newPattern = "dns_cache_flush"
        viewModel.addPattern()
        viewModel.save()
        let saved = try WhitelistStore(fileURL: fileURL).load()
        XCTAssertTrue(saved.patterns.contains("dns_cache_flush"))
        XCTAssertFalse(saved.comments.contains("# comment"))
    }

    func testCleanWhitelistSaveInvalidatesPreviewViaSharedCoordinator() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clean-whitelist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("whitelist")
        try "# header\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let coordinator = OperationCoordinator()

        let cleanViewModel = WhitelistViewModel(store: WhitelistStore(fileURL: fileURL), coordinator: coordinator)
        let generationBefore = coordinator.invalidationGeneration
        cleanViewModel.load()
        cleanViewModel.newPattern = "/Users/example/Library/Caches"
        cleanViewModel.addPattern()
        cleanViewModel.save()
        XCTAssertGreaterThan(coordinator.invalidationGeneration, generationBefore)
    }

    func testBundledMoleTagParsing() throws {
        XCTAssertEqual(BundledMoleInfo.parseTag("upstream_commit=abc\nupstream_tag=V1.55.0\n"), "V1.55.0")
        XCTAssertNil(BundledMoleInfo.parseTag("no tag here"))
    }

    func testNoMenuBarExtraAndQuitOnLastWindowClose() throws {
        XCTAssertFalse(AppLifecycle.hasMenuBarExtra)
        XCTAssertTrue(AppLifecycle.terminatesAfterLastWindowClosed)

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/App/ZmoleApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("MenuBarExtra("))
        XCTAssertFalse(source.contains("MenuBarExtra {"))
    }

    func testSettingsHasNoRemovedToggles() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Settings/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in ["移除前检查", "包含浏览器缓存", "ReviewBefore", "IncludeBrowserCache"] {
            XCTAssertFalse(source.contains(forbidden), "Settings must not offer: \(forbidden)")
        }
    }

    private static let history = """
    {"limit":20,"sessions":[{"command":"clean","ended_at":"2026-09-22T10:20:00+08:00","items":12,"size":"3.2 GB"}],"deletions":[]}
    """

    private static let emptyHistory = """
    {"limit":20,"sessions":[],"deletions":[]}
    """
}

private final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private let registerError: Error?

    init(registerError: Error? = nil) {
        self.registerError = registerError
    }

    func register() throws {
        if let registerError { throw registerError }
        lock.lock(); enabled = true; lock.unlock()
    }

    func unregister() throws {
        lock.lock(); enabled = false; lock.unlock()
    }

    func isEnabled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled
    }
}
