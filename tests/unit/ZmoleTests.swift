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

    private static let statusFixture = """
    {
      "health_score": 100,
      "cpu": {"usage": 33.033730353481815},
      "memory": {"used": 36889788416, "total": 68719476736, "used_percent": 53.68170738220215},
      "disks": [{"mount": "/", "used": 663408778609, "total": 994662584320, "used_percent": 66.69686676336968}]
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
