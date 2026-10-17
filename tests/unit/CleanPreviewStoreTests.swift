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

    func testMissingFileMapsToMissingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        let generation = try store.begin()

        XCTAssertThrowsError(try store.read(generation)) { error in
            XCTAssertEqual(error as? CleanPreviewStoreError, .missingFile)
        }
    }

    func testBeginRemovesThePreviousList() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        try "/tmp/old # 1KB\n".write(to: fileURL, atomically: true, encoding: .utf8)

        _ = try store.begin()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testInvalidUTF8MapsToInvalidUTF8() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        let generation = try store.begin()
        try Data([0xFF, 0xFE, 0xFD]).write(to: fileURL)

        XCTAssertThrowsError(try store.read(generation)) { error in
            XCTAssertEqual(error as? CleanPreviewStoreError, .invalidUTF8)
        }
    }

    func testForeignGenerationIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        try "/tmp/cache # 1KB\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let foreign = CleanPreviewGeneration(
            id: UUID(),
            fileURL: directory.appendingPathComponent("other.txt")
        )

        XCTAssertThrowsError(try store.read(foreign)) { error in
            XCTAssertEqual(error as? CleanPreviewStoreError, .missingFile)
        }
    }

    func testValidListReadsEntriesAndSections() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clean-list.txt")
        let store = CleanPreviewStore(fileURL: fileURL)
        let generation = try store.begin()
        try "# preview\n=== Cache ===\n/tmp/cache # 1KB\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let snapshot = try store.read(generation)

        XCTAssertEqual(snapshot.entries, ["/tmp/cache # 1KB"])
        XCTAssertEqual(snapshot.sections.map(\.name), ["Cache"])
        XCTAssertEqual(snapshot.reclaimBytes, 1_000)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-clean-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
