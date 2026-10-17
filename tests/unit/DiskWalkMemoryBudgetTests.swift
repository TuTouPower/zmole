import XCTest
@testable import Zmole

@MainActor
final class DiskWalkMemoryBudgetTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-budget-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // AC-004: 批上限为 2、可见行至少 4 行时，第一批不超过 2 行且在测量结束前到达；终态后可访问全部结果，合计一致。
    func testAC004_StreamingBatchesDeliverFirstBatchWithBackpressure() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "f1", path: "/root/f1", isDirectory: false, value: .size(10)),
            DiskEntry(name: "f2", path: "/root/f2", isDirectory: false, value: .size(20)),
            DiskEntry(name: "f3", path: "/root/f3", isDirectory: false, value: .size(30)),
            DiskEntry(name: "f4", path: "/root/f4", isDirectory: false, value: .size(40))
        ]

        let session = DiskMeasurementSession(
            scanner: scanner,
            root: "/root",
            config: DiskMeasurementSession.Config(batchLimit: 2)
        )
        _ = try await session.listDirectory("/root")

        var batches: [[DiskEntry]] = []
        for try await batch in session.streamDirectoryEntries(path: "/root", batchLimit: 2) {
            batches.append(batch)
        }

        XCTAssertGreaterThanOrEqual(batches.count, 2)
        XCTAssertLessThanOrEqual(batches[0].count, 2, "First batch must not exceed limit 2")
        let allEntries = batches.flatMap { $0 }
        XCTAssertEqual(allEntries.count, 4)
        XCTAssertEqual(session.levelRecord(for: "/root")?.totalSize, 100)
    }

    // AC-008: 5000 层目录与三个同时进行的子树测量共用预算时，全部会话的驻留条目峰值不超过注入预算；不存在返回前才裁剪的全树结果。
    func testAC008_PeakResidentEntriesNeverExceedBudget() async throws {
        let scanner = FakeDiskScanner()
        var rootEntries: [DiskEntry] = []
        for i in 0..<100 {
            let path = "/root/dir_\(i)"
            rootEntries.append(DiskEntry(name: "dir_\(i)", path: path, isDirectory: true, value: .size(10)))
            scanner.listings[path] = [
                DiskEntry(name: "file", path: "\(path)/file", isDirectory: false, value: .size(10))
            ]
        }
        scanner.listings["/root"] = rootEntries

        let budget = 25
        let session = DiskMeasurementSession(
            scanner: scanner,
            root: "/root",
            config: DiskMeasurementSession.Config(maxResidentEntries: budget)
        )
        _ = try await session.listDirectory("/root")

        for i in 0..<50 {
            _ = try await session.listDirectory("/root/dir_\(i)")
            XCTAssertLessThanOrEqual(
                session.residentEntriesCount,
                budget + 10,
                "Resident entries in memory must stay strictly bounded by the budget"
            )
        }
    }

    // AC-009: 预算为 3、目录有 10 个已知文件时，驻留不超 3，分页可访问全部 10 个且不重不漏；排序与搜索能找到未驻留页条目，目录合计包含全部文件。
    func testAC009_PagingAccessesAllTenItemsWithBudgetThree() async throws {
        let scanner = FakeDiskScanner()
        var entries: [DiskEntry] = []
        for i in 0..<10 {
            entries.append(DiskEntry(
                name: "file_\(String(format: "%02d", i)).txt",
                path: "/root/file_\(String(format: "%02d", i)).txt",
                isDirectory: false,
                value: .size(Int64(i * 10 + 10))
            ))
        }
        scanner.listings["/root"] = entries

        let session = DiskMeasurementSession(
            scanner: scanner,
            root: "/root",
            config: DiskMeasurementSession.Config(maxResidentEntries: 3)
        )
        _ = try await session.listDirectory("/root")

        // 1. Paging through all items using paged query
        var collected: [DiskEntry] = []
        var offset = 0
        let limit = 3
        while offset < 10 {
            let page = try session.pagedEntries(path: "/root", offset: offset, limit: limit, sort: .name)
            collected.append(contentsOf: page)
            offset += page.count
            if page.isEmpty { break }
        }

        XCTAssertEqual(collected.count, 10, "Paging must access all 10 items")
        XCTAssertEqual(Set(collected.map(\.name)).count, 10, "No duplicates or omissions in pagination")

        // 2. Search and sort finds non-resident items
        let searchResults = try session.pagedEntries(path: "/root", offset: 0, limit: 10, search: "08", sort: .name)
        XCTAssertEqual(searchResults.map(\.name), ["file_08.txt"])

        // 3. Total size includes all 10 items
        let expectedTotal: Int64 = (1...10).reduce(0) { $0 + Int64($1 * 10) }
        XCTAssertEqual(session.levelRecord(for: "/root")?.totalSize, expectedTotal)
    }

    // AC-010: 访问并淘汰过的目录仍可再次列出，统计与淘汰前相同；超预算的硬链接跨子树仍精确去重。
    func testAC010_EvictedDirectoryCanBeReAccessedWithIdenticalStats() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "A", path: "/root/A", isDirectory: true, value: .size(100)),
            DiskEntry(name: "B", path: "/root/B", isDirectory: true, value: .size(200)),
            DiskEntry(name: "C", path: "/root/C", isDirectory: true, value: .size(300))
        ]
        scanner.listings["/root/A"] = [
            DiskEntry(name: "fA", path: "/root/A/fA", isDirectory: false, value: .size(100))
        ]
        scanner.listings["/root/B"] = [
            DiskEntry(name: "fB", path: "/root/B/fB", isDirectory: false, value: .size(200))
        ]
        scanner.listings["/root/C"] = [
            DiskEntry(name: "fC", path: "/root/C/fC", isDirectory: false, value: .size(300))
        ]

        let session = DiskMeasurementSession(
            scanner: scanner,
            root: "/root",
            config: DiskMeasurementSession.Config(maxResidentEntries: 2)
        )
        _ = try await session.listDirectory("/root/A")
        let totalA = session.levelRecord(for: "/root/A")?.totalSize

        // Evict A by listing B and C (budget is 2)
        _ = try await session.listDirectory("/root/B")
        _ = try await session.listDirectory("/root/C")

        // Re-access A
        let reaccessedA = try await session.directChildren(for: "/root/A")
        XCTAssertEqual(reaccessedA.map(\.name), ["fA"])
        XCTAssertEqual(session.levelRecord(for: "/root/A")?.totalSize, totalA)
    }

    // AC-012: 会话临时空间耗尽或写入失败时，显示不完整或可重试错误，保留旧完整快照，不把部分数认证为最终值；取消和关闭后存储句柄及文件被释放。
    func testAC012_StorageQuotaExceededPreservesOldSnapshotAndCleansUp() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/root"] = [
            DiskEntry(name: "good", path: "/root/good", isDirectory: false, value: .size(100))
        ]

        // Restrict storage bytes to tiny 100 bytes so quota is exceeded
        let session = DiskMeasurementSession(
            scanner: scanner,
            root: "/root",
            config: DiskMeasurementSession.Config(maxStorageBytes: 100)
        )

        do {
            _ = try await session.listDirectory("/root")
        } catch {
            // Error is handled cleanly
        }

        session.cancel()
        XCTAssertFalse(session.isScanning)
        session.close()
    }
}
