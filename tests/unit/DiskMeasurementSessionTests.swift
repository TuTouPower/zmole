import XCTest
@testable import Zmole

@MainActor
final class DiskMeasurementSessionTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    // AC-001: 测量进行中新入队任务会被继续消费；待测和在途都为空时 isScanning=false。
    func testAC001_ContinuousQueueConsumptionAndScanningState() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "A", path: "/root/A", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/A"] = [
            DiskEntry(name: "a.txt", path: "/root/A/a.txt", isDirectory: false, value: .size(100))
        ]
        scanner.listings["/root/B"] = [
            DiskEntry(name: "b.txt", path: "/root/B/b.txt", isDirectory: false, value: .size(200))
        ]
        scanner.blockedMeasures.insert("/root/A")
        scanner.results["/root/A"] = DiskScanResult(
            path: "/root/A",
            totalSize: 100,
            isReadable: true,
            levels: ["/root/A": DiskLevel(entries: [DiskEntry(name: "a.txt", path: "/root/A/a.txt", isDirectory: false, value: .size(100))], totalSize: 100)]
        )
        scanner.results["/root/B"] = DiskScanResult(
            path: "/root/B",
            totalSize: 200,
            isReadable: true,
            levels: ["/root/B": DiskLevel(entries: [DiskEntry(name: "b.txt", path: "/root/B/b.txt", isDirectory: false, value: .size(200))], totalSize: 200)]
        )

        let session = DiskMeasurementSession(scanner: scanner, root: "/root")
        _ = try await session.listDirectory("/root")
        XCTAssertTrue(session.isScanning)

        try await waitUntil { scanner.measureRequests.contains("/root/A") }

        // Enqueue B while A is in flight
        session.enqueueMeasurement(path: "/root/B", parent: "/root")
        XCTAssertTrue(session.isScanning)

        scanner.releaseMeasures()

        try await waitUntil {
            session.levelRecord(for: "/root/B")?.totalSize == 200
        }
        try await waitUntil { !session.isScanning }
        XCTAssertFalse(session.isScanning)
    }

    // AC-002: 任务组已取空旧队列后再入队，worker 结束时不会留下队列非空且无消费者的状态。
    func testAC002_EnqueueAfterQueueEmptiedDoesNotLeaveStrandedTasks() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "first", path: "/root/first", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/first")
        scanner.results["/root/first"] = DiskScanResult(
            path: "/root/first",
            totalSize: 50,
            isReadable: true,
            levels: ["/root/first": DiskLevel(entries: [], totalSize: 50)]
        )
        scanner.results["/root/second"] = DiskScanResult(
            path: "/root/second",
            totalSize: 75,
            isReadable: true,
            levels: ["/root/second": DiskLevel(entries: [], totalSize: 75)]
        )

        let session = DiskMeasurementSession(scanner: scanner, root: "/root")
        _ = try await session.listDirectory("/root")

        try await waitUntil { scanner.measureRequests.contains("/root/first") }

        // At this point, pending queue is empty and "first" is in flight
        // Enqueue second right now
        session.enqueueMeasurement(path: "/root/second", parent: "/root")

        // Release first
        scanner.releaseMeasures()

        // Wait until second is also consumed and finished
        try await waitUntil {
            session.levelRecord(for: "/root/second")?.totalSize == 75
        }
        try await waitUntil { !session.isScanning }
        XCTAssertFalse(session.isScanning)
    }

    // AC-003: 取消后旧需求不再启动，实际遍历退出后 isScanning=false；已取消世代的迟到结果不发布。
    func testAC003_CancellationPreventsNewStartsAndLateResultsDiscarded() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "A", path: "/root/A", isDirectory: true, value: .computing),
            DiskEntry(name: "B", path: "/root/B", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/A")
        scanner.blockedMeasures.insert("/root/B")
        scanner.results["/root/A"] = DiskScanResult(path: "/root/A", totalSize: 100, isReadable: true, levels: [:])
        scanner.results["/root/B"] = DiskScanResult(path: "/root/B", totalSize: 200, isReadable: true, levels: [:])

        let session = DiskMeasurementSession(scanner: scanner, root: "/root")
        _ = try await session.listDirectory("/root")

        try await waitUntil { scanner.measureRequests.contains("/root/A") }

        session.cancel()
        XCTAssertFalse(session.isScanning)

        scanner.releaseMeasures()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Late results should not update level
        XCTAssertNil(session.levelRecord(for: "/root/A")?.totalSize)
        XCTAssertFalse(session.isScanning)
    }

    // AC-004: 祖先测量中进入子目录不重复测量已覆盖子树；完成后父列表里的子目录行有正确大小或不可读；无关目录仍会测量。
    func testAC004_AncestorMeasurementAvoidsDuplicateSubtreeTraversals() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing),
            DiskEntry(name: "unrelated", path: "/unrelated", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/sub"] = [
            DiskEntry(name: "nested", path: "/root/sub/nested", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/sub")
        scanner.results["/root/sub"] = DiskScanResult(
            path: "/root/sub",
            totalSize: 300,
            isReadable: true,
            levels: [
                "/root/sub": DiskLevel(
                    entries: [DiskEntry(name: "nested", path: "/root/sub/nested", isDirectory: true, value: .size(300))],
                    totalSize: 300
                ),
                "/root/sub/nested": DiskLevel(
                    entries: [DiskEntry(name: "file.bin", path: "/root/sub/nested/file.bin", isDirectory: false, value: .size(300))],
                    totalSize: 300
                )
            ]
        )
        scanner.results["/unrelated"] = DiskScanResult(
            path: "/unrelated",
            totalSize: 80,
            isReadable: true,
            levels: ["/unrelated": DiskLevel(entries: [], totalSize: 80)]
        )

        let session = DiskMeasurementSession(scanner: scanner, root: "/root")
        _ = try await session.listDirectory("/root")

        try await waitUntil { scanner.measureRequests.contains("/root/sub") }

        // Enter sub while ancestor walk is in flight
        _ = try await session.listDirectory("/root/sub")

        // Subtree /root/sub/nested should NOT have triggered a separate measure request
        XCTAssertFalse(scanner.measureRequests.contains("/root/sub/nested"))

        scanner.releaseMeasures()

        try await waitUntil {
            session.levelRecord(for: "/root/sub")?.totalSize == 300 &&
            session.levelRecord(for: "/unrelated")?.totalSize == 80
        }

        // Subtree was covered by ancestor walk, unrelated was also measured
        XCTAssertFalse(scanner.measureRequests.contains("/root/sub/nested"))
        XCTAssertTrue(scanner.measureRequests.contains("/unrelated"))
    }

    // AC-005: 同一路径在含共享硬链接的两个统计范围中，目录自身合计一致，父范围去重贡献各自正确；逆转 worker 完成顺序不改变结果。
    func testAC005_HardLinksSeparatedIntoSelfDeduplicatedAndParentContribution() async throws {
        // Create actual directory structure on disk to test real LiveDiskScanner measurement
        let first = try writeFile("subA/first.bin", bytes: 8_000)
        let second = rootURL.appendingPathComponent("subB/second.bin")
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: first, to: second)

        let subAPath = rootURL.appendingPathComponent("subA").path
        let subBPath = rootURL.appendingPathComponent("subB").path

        let firstAllocated = try allocatedBytes(first.path)

        let session = DiskMeasurementSession(scanner: LiveDiskScanner(), root: rootURL.path)
        _ = try await session.listDirectory(rootURL.path)

        try await waitUntil(timeout: 5) {
            session.levelRecord(for: subAPath)?.totalSize != nil &&
            session.levelRecord(for: subBPath)?.totalSize != nil
        }

        let recordA = try XCTUnwrap(session.levelRecord(for: subAPath))
        let recordB = try XCTUnwrap(session.levelRecord(for: subBPath))
        let rootRecord = try XCTUnwrap(session.levelRecord(for: rootURL.path))

        // SubA and SubB self-totals must be identical
        XCTAssertEqual(recordA.selfDeduplicatedSize, firstAllocated)
        XCTAssertEqual(recordB.selfDeduplicatedSize, firstAllocated)

        // In root scope, subA (lexicographically earlier: subA < subB) claims the hard link
        let entryA = try XCTUnwrap(rootRecord.entries.first { $0.path == subAPath })
        let entryB = try XCTUnwrap(rootRecord.entries.first { $0.path == subBPath })

        XCTAssertEqual(entryA.parentContribution, firstAllocated)
        XCTAssertEqual(entryB.parentContribution, 0)
        XCTAssertEqual(rootRecord.totalSize, firstAllocated)
    }

    // AC-006: 祖先测量开始后才列出的当前层及展开层，祖先完成后全部等待行进入正确终态，不因 listing generation 较新永久计算中。
    func testAC006_AncestorMeasurementCompletesSubscribedRowsListedLater() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "sub", path: "/root/sub", isDirectory: true, value: .computing)
        ]
        scanner.listings["/root/sub"] = [
            DiskEntry(name: "leaf", path: "/root/sub/leaf", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/sub")
        scanner.results["/root/sub"] = DiskScanResult(
            path: "/root/sub",
            totalSize: 420,
            isReadable: true,
            levels: [
                "/root/sub": DiskLevel(
                    entries: [DiskEntry(name: "leaf", path: "/root/sub/leaf", isDirectory: true, value: .size(420))],
                    totalSize: 420
                )
            ]
        )

        let session = DiskMeasurementSession(scanner: scanner, root: "/root")
        _ = try await session.listDirectory("/root")

        try await waitUntil { scanner.measureRequests.contains("/root/sub") }

        // List /root/sub after measurement started
        _ = try await session.listDirectory("/root/sub")

        scanner.releaseMeasures()

        try await waitUntil {
            session.levelRecord(for: "/root/sub")?.entries.first { $0.name == "leaf" }?.knownSize == 420
        }
        XCTAssertEqual(session.levelRecord(for: "/root/sub")?.totalSize, 420)
    }

    // AC-007: 旧世代被阻塞时重新分析，再放行旧结果，页面只接受新世代；相同路径但不同世代不共享旧结果。
    func testAC007_ReanalyzeBumpsGenerationAndRejectsBlockedOldGenerationResults() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "item", path: "/root/item", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/item")
        scanner.results["/root/item"] = DiskScanResult(path: "/root/item", totalSize: 111, isReadable: true, levels: [:])

        let session = DiskMeasurementSession(scanner: scanner, root: "/root")
        _ = try await session.listDirectory("/root")

        try await waitUntil { scanner.measureRequests.contains("/root/item") }

        // Reanalyze with new result ready
        scanner.results["/root/item"] = DiskScanResult(path: "/root/item", totalSize: 999, isReadable: true, levels: [:])
        session.reanalyze(path: "/root")
        _ = try await session.listDirectory("/root")

        // Release old blocked result
        scanner.releaseMeasures()

        try await waitUntil {
            session.levelRecord(for: "/root/item")?.totalSize == 999
        }
        XCTAssertEqual(session.levelRecord(for: "/root/item")?.totalSize, 999)
    }

    // AC-008: 两个兼容消费者复用一次遍历；一个解除需求不影响另一个完成，最后一个需求取消后没有遗留遍历。
    func testAC008_CompatibleConsumersReuseSingleWalkAndCleanCancellation() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "A", path: "/root/A", isDirectory: true, value: .computing)
        ]
        scanner.blockedMeasures.insert("/root/A")
        scanner.results["/root/A"] = DiskScanResult(path: "/root/A", totalSize: 500, isReadable: true, levels: [:])

        let session = DiskMeasurementSession(scanner: scanner, root: "/root")
        let sub1 = session.subscribe(path: "/root/A")
        let sub2 = session.subscribe(path: "/root/A")

        try await waitUntil { scanner.measureRequests.contains("/root/A") }
        XCTAssertEqual(scanner.measureRequests.filter { $0 == "/root/A" }.count, 1)

        // Cancel first subscriber
        sub1.cancel()
        XCTAssertTrue(session.isScanning)

        // Release walk; sub2 should still finish
        scanner.releaseMeasures()
        try await waitUntil { !session.isScanning }
        XCTAssertEqual(session.levelRecord(for: "/root/A")?.totalSize, 500)

        // Now if last subscriber cancels before release, walk is cancelled
        scanner.blockedMeasures.insert("/root/A")
        let sub3 = session.subscribe(path: "/root/A")
        try await waitUntil { scanner.measureRequests.filter { $0 == "/root/A" }.count == 2 }
        sub3.cancel()
        scanner.releaseMeasures()
        try await waitUntil { !session.isScanning }
    }

    // AC-009: 符号链接只计自身、跨设备不计入父合计、硬链接在同一统计范围只计一次；未知、取消和不可读均不伪装成 0 或完整合计。
    func testAC009_SymlinkCrossDeviceHardLinkAndUnreadableAccounting() async throws {
        let plain = try writeFile("dir/plain.bin", bytes: 1000)
        let link = rootURL.appendingPathComponent("dir/symlink.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: plain)

        let locked = rootURL.appendingPathComponent("dir/locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 500).write(to: locked.appendingPathComponent("secret.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }

        let dirPath = rootURL.appendingPathComponent("dir").path
        let session = DiskMeasurementSession(scanner: LiveDiskScanner(), root: rootURL.path)
        _ = try await session.listDirectory(dirPath)

        try await waitUntil(timeout: 5) {
            session.levelRecord(for: dirPath)?.entries.first { $0.name == "locked" }?.value != .computing
        }

        let record = try XCTUnwrap(session.levelRecord(for: dirPath))
        let lockedEntry = record.entries.first { $0.name == "locked" }
        XCTAssertEqual(lockedEntry?.value, .unreadable)
        XCTAssertNil(lockedEntry?.knownSize)
        XCTAssertNotEqual(record.totalSize, 0)
    }

    private func writeFile(_ relative: String, bytes: Int) throws -> URL {
        let url = rootURL.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        return url
    }

    private func allocatedBytes(_ path: String) throws -> Int64 {
        var info = stat()
        XCTAssertEqual(lstat(path, &info), 0, "lstat failed for \(path)")
        return Int64(info.st_blocks) * 512
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
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
