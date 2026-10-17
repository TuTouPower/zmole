import XCTest
@testable import Zmole

@MainActor
final class OptimizePurgePageTests: XCTestCase {
    func testOptimizeArgsNeverIncludeSelectedTaskSubset() async {
        let spy = MaintenanceExecutionSpy()
        let viewModel = OptimizeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.optimize, output: "plan")
        )

        viewModel.adoptBackgroundResultIfAvailable()
        viewModel.requestConfirmation()
        await viewModel.confirmExecution()

        let invocations = await spy.invocations.map(\.arguments)
        XCTAssertEqual(invocations, [["optimize"]])
        XCTAssertFalse(invocations.contains { $0.count > 1 })
    }

    func testPurgeUsesYesAndCancelDoesNotExecute() async {
        let spy = MaintenanceExecutionSpy()
        let viewModel = PurgeViewModel(
            process: spy,
            coordinator: OperationCoordinator(),
            scan: ScanProvidingStub.maintenance(.purge, output: "plan")
        )

        viewModel.adoptBackgroundResultIfAvailable()
        XCTAssertTrue(viewModel.canConfirm)

        viewModel.requestConfirmation()
        viewModel.cancelConfirmation()
        var recorded = await spy.invocations.map(\.arguments)
        XCTAssertTrue(recorded.isEmpty, "cancelling the sheet must not execute")

        await viewModel.confirmExecution()
        recorded = await spy.invocations.map(\.arguments)
        XCTAssertTrue(recorded.isEmpty, "execution requires an open confirmation")

        viewModel.requestConfirmation()
        await viewModel.confirmExecution()
        recorded = await spy.invocations.map(\.arguments)
        XCTAssertEqual(recorded, [["purge", "--yes"]])
    }

    func testOptimizePlanParsesRealDryRunSample() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/archive/spikes/s001_mole_cli_fixtures/samples/optimize_dry_run.txt")
        let sample = try String(contentsOf: sampleURL, encoding: .utf8)
        let rows = OptimizePlanParser.rows(from: sample)

        XCTAssertEqual(rows.first?.name, "DNS & Spotlight Check")
        XCTAssertEqual(rows.first?.status, .willRun)
        XCTAssertFalse(rows.contains { $0.name.contains("WORLD") || $0.name.hasPrefix("Optimize") })

        let periodic = try XCTUnwrap(rows.first { $0.name == "Periodic Maintenance" })
        XCTAssertEqual(periodic.status, .skip)
        XCTAssertTrue(periodic.reason?.contains("skipped") ?? false)

        let launchAgents = try XCTUnwrap(rows.first { $0.name == "Launch Agents Cleanup" })
        XCTAssertTrue(launchAgents.deletesFiles)

        // No scan output means no rows at all (tasks are never marked as run).
        XCTAssertTrue(OptimizePlanParser.rows(from: "").isEmpty)
    }

    func testOptimizePlanRecognizesCurrentSkipWording() {
        let output = """
        ➤ Database Optimization
          ◎ Close these apps before database optimization: Mail
        ➤ Notifications
          → Notification Center database is healthy (12 MB)
        ➤ Launch Services Repair
          → LaunchServices repaired
        """
        let rows = OptimizePlanParser.rows(from: output)
        XCTAssertEqual(rows[0].name, "Database Optimization")
        XCTAssertEqual(rows[0].status, .skip)
        XCTAssertTrue(rows[0].reason?.contains("Close these apps") ?? false)
        XCTAssertEqual(rows[1].status, .skip)
        XCTAssertEqual(rows[2].status, .willRun)
    }

    func testPurgePathsStoreRoundTripAndValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-paths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("purge_paths")
        let store = PurgePathsStore(fileURL: fileURL)

        try store.save(["/Users/example/Projects", "~/work"])
        XCTAssertEqual(try store.load(), ["/Users/example/Projects", "~/work"])

        XCTAssertThrowsError(try store.save(["relative/path"])) { error in
            XCTAssertEqual(error as? PurgePathsError, .invalidPath("relative/path"))
        }
    }

    func testPurgePathsViewModelKeepsTextOnInvalidSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-paths-vm-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("purge_paths")
        try "~/Projects\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = PurgePathsViewModel(store: PurgePathsStore(fileURL: fileURL), coordinator: OperationCoordinator())
        viewModel.load()
        XCTAssertEqual(viewModel.text, "~/Projects")

        viewModel.text = "~/Projects\nrelative/dir"
        XCTAssertFalse(viewModel.save())
        XCTAssertEqual(viewModel.errorKey, "purge.paths.error.invalid")
        XCTAssertTrue(viewModel.text.contains("relative/dir"))

        viewModel.text = "~/Projects\n/Users/example/code"
        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(try PurgePathsStore(fileURL: fileURL).load(), ["~/Projects", "/Users/example/code"])
    }

    func testSavingScanDirectoriesInvalidatesPurgePreview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-paths-invalidate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("purge_paths")
        let coordinator = OperationCoordinator()

        let purgeViewModel = PurgeViewModel(
            process: MaintenanceExecutionSpy(),
            coordinator: coordinator,
            scan: ScanProvidingStub.maintenance(.purge, output: "plan")
        )
        let pathsViewModel = PurgePathsViewModel(store: PurgePathsStore(fileURL: fileURL), coordinator: coordinator)

        purgeViewModel.adoptBackgroundResultIfAvailable()
        XCTAssertTrue(purgeViewModel.canConfirm)

        pathsViewModel.load()
        pathsViewModel.text = "~/Projects"
        XCTAssertTrue(pathsViewModel.save())
        XCTAssertFalse(purgeViewModel.canConfirm)
        XCTAssertNil(purgeViewModel.preview)
    }

    func testDeletionRowCopyStatesPermanentDeletion() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["optimize.row_deletes_permanently"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let zh = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any])
        let value = try XCTUnwrap((zh["stringUnit"] as? [String: Any])?["value"] as? String)
        XCTAssertTrue(value.contains("永久"))
    }

    func testPermanentDeletionCopyUsesPermanentWording() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        for key in ["optimize.permanent_note", "purge.permanent_note"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let zh = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any])
            let value = try XCTUnwrap((zh["stringUnit"] as? [String: Any])?["value"] as? String)
            XCTAssertTrue(value.contains("永久删除"), "\(key) must state permanent deletion")
            XCTAssertFalse(value.contains("移入废纸篓"), "\(key) must not claim Trash")
        }
    }
}
