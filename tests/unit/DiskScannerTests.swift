import XCTest
@testable import Zmole

final class DiskScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-disk-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testListingMarksDirectoriesComputingAndFilesSized() async throws {
        let plain = try writeFile("plain.bin", bytes: 200)
        try writeFile("sub/nested.bin", bytes: 100)

        let entries = try await LiveDiskScanner().listDirectory(root.path)

        XCTAssertEqual(entries.first { $0.name == "sub" }?.value, .computing)
        XCTAssertEqual(entries.first { $0.name == "plain.bin" }?.knownSize, try allocatedBytes(plain.path))
        XCTAssertEqual(entries.first { $0.name == "plain.bin" }?.isDirectory, false)
    }

    func testMeasureSumsDescendantsAndDedupesHardLinks() async throws {
        let first = try writeFile("sub/first.bin", bytes: 8_000)
        try FileManager.default.linkItem(
            at: first,
            to: root.appendingPathComponent("sub/second.bin")
        )
        let other = try writeFile("sub/other.bin", bytes: 4_000)
        let sub = root.appendingPathComponent("sub").path

        let result = await LiveDiskScanner().measureSubtree(
            root.path,
            deduplicator: HardLinkDeduplicator()
        )

        let firstAllocation = try allocatedBytes(first.path)
        let otherAllocation = try allocatedBytes(other.path)
        XCTAssertTrue(result.isReadable)
        XCTAssertEqual(result.levels[sub]?.totalSize, firstAllocation + otherAllocation)
        XCTAssertEqual(result.totalSize, firstAllocation + otherAllocation)

        let rows = try XCTUnwrap(result.levels[sub]?.entries)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(
            rows.first { $0.name == "second.bin" }?.knownSize,
            firstAllocation,
            "each row still displays its own allocation"
        )
    }

    func testSymlinkCountsOnlyItself() async throws {
        let targetDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-disk-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: targetDirectory) }
        let target = targetDirectory.appendingPathComponent("big.bin")
        try Data(count: 2_000_000).write(to: target)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = await LiveDiskScanner().measureSubtree(
            root.path,
            deduplicator: HardLinkDeduplicator()
        )

        let linkAllocation = try allocatedBytes(link.path)
        XCTAssertEqual(result.totalSize, linkAllocation)
        let entry = result.levels[root.path]?.entries.first { $0.name == "link" }
        XCTAssertEqual(entry?.isDirectory, false)
        XCTAssertEqual(entry?.knownSize, linkAllocation)
    }

    func testUnreadableDirectoryIsMarkedAndExcluded() async throws {
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 1_234).write(to: locked.appendingPathComponent("hidden.bin"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: locked.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path
            )
        }

        let result = await LiveDiskScanner().measureSubtree(
            root.path,
            deduplicator: HardLinkDeduplicator()
        )

        XCTAssertTrue(result.isReadable)
        XCTAssertEqual(
            result.levels[root.path]?.entries.first { $0.name == "locked" }?.value,
            .unreadable
        )
        XCTAssertEqual(result.totalSize, 0, "unreadable directories never count as zero bytes")
    }

    @MainActor
    func testSessionCacheKeepsScanResultsUntilReanalyze() async throws {
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let inside = sub.appendingPathComponent("inside.bin")
        try Data(count: 4_000).write(to: inside)

        let viewModel = AnalyzeViewModel(scanner: LiveDiskScanner(), root: root.path)
        await viewModel.loadOverview()
        try await waitUntil {
            viewModel.level?.entries.first { $0.name == "sub" }?.knownSize != nil
        }
        let measured = try XCTUnwrap(
            viewModel.level?.entries.first { $0.name == "sub" }?.knownSize
        )

        await viewModel.openDirectory(
            try XCTUnwrap(viewModel.level?.entries.first { $0.name == "sub" })
        )
        XCTAssertEqual(viewModel.level?.entries.map(\.name), ["inside.bin"])
        let insideSize = try XCTUnwrap(viewModel.level?.entries.first?.knownSize)
        XCTAssertEqual(insideSize, try allocatedBytes(inside.path))

        let extra = sub.appendingPathComponent("extra.bin")
        try Data(count: 20_000).write(to: extra)
        await viewModel.goBack()
        XCTAssertEqual(
            viewModel.level?.entries.first { $0.name == "sub" }?.knownSize,
            measured,
            "disk changes must not alter cached sizes"
        )
        await viewModel.openDirectory(
            try XCTUnwrap(viewModel.level?.entries.first { $0.name == "sub" })
        )
        XCTAssertNil(viewModel.level?.entries.first { $0.name == "extra.bin" })

        await viewModel.refreshCurrent()
        let extraSize = try allocatedBytes(extra.path)
        try await waitUntil {
            viewModel.level?.totalSize == insideSize + extraSize
        }
        XCTAssertNotNil(viewModel.level?.entries.first { $0.name == "extra.bin" })
    }

    private func writeFile(_ relative: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: bytes).write(to: url)
        return url
    }

    private func allocatedBytes(_ path: String) throws -> Int64 {
        var info = stat()
        XCTAssertEqual(lstat(path, &info), 0, "lstat failed for \(path)")
        return Int64(info.st_blocks) * 512
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }
}
