import XCTest
@testable import Zmole

final class WhitelistOperationTests: XCTestCase {
    @MainActor
    func testBusyCoordinatorPreventsWhitelistWrite() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        try "# header\n~/before\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let coordinator = OperationCoordinator()
        let viewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: fileURL),
            coordinator: coordinator
        )
        viewModel.load()
        viewModel.newPattern = "~/after"
        viewModel.addPattern()
        let lease = try XCTUnwrap(coordinator.acquire(.clean))

        viewModel.save()

        XCTAssertEqual(viewModel.errorMessageKey, "operation.error.busy")
        XCTAssertFalse(viewModel.didSave)
        XCTAssertEqual(
            try String(contentsOf: fileURL, encoding: .utf8),
            "# header\n~/before\n"
        )
        lease.release()
    }

    @MainActor
    func testSuccessfulSaveReleasesLeaseAndInvalidatesPreviews() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("whitelist")
        let coordinator = OperationCoordinator()
        let viewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: fileURL),
            coordinator: coordinator
        )
        viewModel.load()
        viewModel.newPattern = "~/protected"
        viewModel.addPattern()
        let generation = coordinator.invalidationGeneration

        viewModel.save()

        XCTAssertTrue(viewModel.didSave)
        XCTAssertNil(coordinator.activeOperation)
        XCTAssertFalse(coordinator.isCurrent(generation))
    }

    @MainActor
    func testFailedSaveReleasesLeaseAndInvalidatesPreviews() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedParent = directory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blockedParent)
        let coordinator = OperationCoordinator()
        let viewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: blockedParent.appendingPathComponent("whitelist")),
            coordinator: coordinator
        )
        viewModel.load()
        viewModel.newPattern = "~/protected"
        viewModel.addPattern()
        let generation = coordinator.invalidationGeneration

        viewModel.save()

        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNil(coordinator.activeOperation)
        XCTAssertFalse(coordinator.isCurrent(generation))
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-whitelist-operations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
