import XCTest
@testable import Zmole

@MainActor
final class RecoverableBusyTests: XCTestCase {
    // The disk page no longer runs a mole command (t028 moved it to an
    // in-app read-only scanner), so its former busy-recovery tests were
    // removed with the command lane. The busy semantics below stay covered
    // for every page that still spawns mole.

    func testWriteBusyFromCoordinatorIsRecoverable() async {
        let coordinator = OperationCoordinator()
        _ = coordinator.acquire(.clean) // another write holds the single lease

        let viewModel = OptimizeViewModel(process: NoopProcess(), coordinator: coordinator)
        await viewModel.previewOptimize()

        XCTAssertTrue(viewModel.showBusyNotice)
        XCTAssertFalse(viewModel.isPreviewing)
        XCTAssertNil(viewModel.errorMessageKey, "busy must not be reported as a failure")
    }

    func testInstallersScanBusyKeepsListAndClearsOnRetry() async {
        let runner = FlakyInstallerRunner()
        let interface = InstallerInterface { arguments in try await runner.run(arguments) }
        let viewModel = InstallersViewModel(interface: interface, coordinator: OperationCoordinator())

        await viewModel.scan()
        XCTAssertEqual(viewModel.candidates.count, 1)

        await runner.setBusy(true)
        await viewModel.scan()
        XCTAssertTrue(viewModel.showBusyNotice)
        XCTAssertEqual(viewModel.candidates.count, 1, "busy must not clear the listing")
        XCTAssertNil(viewModel.errorMessage)

        await runner.setBusy(false)
        await viewModel.scan()
        XCTAssertFalse(viewModel.showBusyNotice)
        XCTAssertEqual(viewModel.candidates.count, 1)
    }

    func testHistoryBusyKeepsSnapshot() async {
        let gate = BusyGate()
        let loader = HistorySnapshotLoader { _ in
            if await gate.isBusy { throw MoleBridgeError.busy }
            return MoleCommandResult(stdout: Self.historyJSON, stderr: "", exitCode: 0)
        }
        let viewModel = HistoryViewModel(loader: loader)

        await viewModel.refresh()
        XCTAssertNotNil(viewModel.snapshot)

        await gate.setBusy(true)
        await viewModel.refresh()
        XCTAssertTrue(viewModel.showBusyNotice)
        XCTAssertNotNil(viewModel.snapshot)
        XCTAssertNil(viewModel.errorMessage)
    }

    private static let historyJSON = """
    {"limit":20,"sessions":[{"command":"clean","ended_at":"2026-09-22T10:20:00+08:00","items":12,"size":"3.2 GB"}],"deletions":[]}
    """
}

private actor BusyGate {
    private(set) var isBusy = false
    func setBusy(_ value: Bool) { isBusy = value }
}

private actor FlakyInstallerRunner {
    private var busy = false
    private let listJSON = """
    [{"path":"/Users/demo/Downloads/A.dmg","size_bytes":100,"source":"Downloads","identity":"1"}]
    """

    func setBusy(_ value: Bool) { busy = value }

    func run(_ arguments: [String]) async throws -> MoleCommandResult {
        if busy { throw MoleBridgeError.busy }
        return MoleCommandResult(stdout: listJSON, stderr: "", exitCode: 0)
    }
}

private final class NoopProcess: MoleProcessControlling, @unchecked Sendable {
    func run(_ arguments: [String], stdin: Data?, timeout: TimeInterval) async throws -> MoleCommandResult {
        MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }
    func cancel() async {}
}
