import XCTest
@testable import Zmole

final class CleanPreviewStoreTests: XCTestCase {
    func testHeadersOnlyPreviewIsNotReady() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        let generation = try store.begin()
        try "# preview\n=== Cache ===\n".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.read(generation)) { error in
            XCTAssertEqual(error as? CleanPreviewStoreError, .emptyFile)
        }
    }

    func testVerifyMissingPreviewFileMapsToMissingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        let generation = try store.begin()
        try "/tmp/cache # 1KB\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let snapshot = try store.read(generation)
        try FileManager.default.removeItem(at: fileURL)

        XCTAssertThrowsError(try store.verifyUnchanged(snapshot)) { error in
            XCTAssertEqual(error as? CleanPreviewStoreError, .missingFile)
        }
    }

    func testVerifyUnreadablePreviewMapsToChangedSincePreview() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        let generation = try store.begin()
        try "/tmp/cache # 1KB\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let snapshot = try store.read(generation)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try store.verifyUnchanged(snapshot)) { error in
            XCTAssertEqual(error as? CleanPreviewStoreError, .changedSincePreview)
        }
    }

    @MainActor
    func testCleanConfirmationSurfacesMissingPreviewKey() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let process = CleanPreviewProcessSpy(fileURL: fileURL)
        let viewModel = CleanViewModel(
            process: process,
            previewStore: CleanPreviewStore(fileURL: fileURL),
            coordinator: OperationCoordinator()
        )

        await viewModel.previewClean()
        viewModel.requestConfirmation()
        try FileManager.default.removeItem(at: fileURL)
        await viewModel.confirmExecution()

        XCTAssertEqual(viewModel.errorMessageKey, "clean.error.missing_list")
        XCTAssertNil(viewModel.preview)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-clean-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor CleanPreviewProcessSpy: MoleProcessControlling {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        if arguments == ["clean", "--dry-run"] {
            try "# preview\n=== Cache ===\n/tmp/cache # 1KB\n"
                .write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}
