import Foundation
import XCTest
@testable import Zmole

final class DiskSQLPerformanceTests: XCTestCase {
    func testDirectoryWorkQueueDoesNotRescanDiscoveredEntries() throws {
        let store = try DiskSessionStore()
        defer { store.close() }
        let count = 512
        try store.beginLevel("/fixture")
        try store.appendEntries(parent: "/fixture", entries: (0..<count).map {
            DiskEntry(name: "d\($0)", path: "/fixture/d\($0)", isDirectory: true, value: .computing)
        })
        let start = store.sqlWorkCount
        var consumed: Set<String> = []
        while let path = try store.nextUnlistedDirectory() {
            XCTAssertTrue(consumed.insert(path).inserted)
            try store.beginLevel(path)
            try store.finishLevel(path, readable: true, complete: true)
        }
        XCTAssertEqual(consumed.count, count)
        let work = store.sqlWorkCount - start
        print("SQL queue: directories=\(count) instructions=\(work)")
        XCTAssertLessThan(work, Int64(count * 500), "Queue consumption must use indexed take/delete, not repeated full scans")
    }

    func testBottomUpStatisticsHaveBoundedSQLWorkAtScale() throws {
        let store = try DiskSessionStore()
        defer { store.close() }
        let count = 1024
        let start = store.sqlWorkCount
        try store.importResult(Self.fixture(directories: count))
        let work = store.sqlWorkCount - start
        XCTAssertEqual(store.loadSummary(for: "/fixture")?.totalSize, Int64(count * 4))
        XCTAssertEqual(store.loadSummary(for: "/fixture")?.directDirectoriesCount, count)
        print("SQL aggregation: directories=\(count) files=\(count * 4) instructions=\(work)")
        XCTAssertLessThan(work, Int64(count * 1600), "Aggregating direct children must not repeatedly query the entire subtree")
    }

    func testHardLinksRetainIndependentScopeTotalsAndDeterministicContribution() throws {
        let store = try DiskSessionStore()
        defer { store.close() }
        let key = HardLinkKey(device: 1, inode: 7)
        try store.importResult(DiskScanResult(path: "/fixture", totalSize: 25, isReadable: true, levels: [
            "/fixture": DiskLevel(entries: [
                DiskEntry(name: "A", path: "/fixture/A", isDirectory: true, value: .size(15)),
                DiskEntry(name: "B", path: "/fixture/B", isDirectory: true, value: .size(20)),
                DiskEntry(name: "direct", path: "/fixture/direct", isDirectory: false, value: .size(10), linkKey: key)
            ], totalSize: 25),
            "/fixture/A": DiskLevel(entries: [
                DiskEntry(name: "link", path: "/fixture/A/link", isDirectory: false, value: .size(10), linkKey: key),
                DiskEntry(name: "plain", path: "/fixture/A/plain", isDirectory: false, value: .size(5))
            ], totalSize: 15),
            "/fixture/B": DiskLevel(entries: [
                DiskEntry(name: "link", path: "/fixture/B/link", isDirectory: false, value: .size(10), linkKey: key),
                DiskEntry(name: "plain", path: "/fixture/B/plain", isDirectory: false, value: .size(10))
            ], totalSize: 20)
        ]))
        XCTAssertEqual(store.loadSummary(for: "/fixture")?.totalSize, 25)
        XCTAssertEqual(store.loadSummary(for: "/fixture/A")?.totalSize, 15)
        XCTAssertEqual(store.loadSummary(for: "/fixture/B")?.totalSize, 20)
        let directories = try store.loadEntries(parentPath: "/fixture").filter(\.isDirectory)
        XCTAssertEqual(directories.map(\.parentContribution), [5, 10])
    }

    func testPromotedHardLinkFactsDoNotBecomeUnlinkedBytes() throws {
        let store = try DiskSessionStore()
        let staging = try store.makeStagingStore()
        defer { staging.close(); store.close() }
        try store.beginLevel("/fixture")
        try store.appendEntries(parent: "/fixture", entries: [DiskEntry(name: "A", path: "/fixture/A", isDirectory: true, value: .computing)])
        try store.recalculateAll()
        let key = HardLinkKey(device: 1, inode: 8)
        try staging.saveLevel(
            summary: DiskLevelSummary(path: "/fixture/A", totalSize: 10, selfDeduplicatedSize: 10, isReadable: true, directFilesCount: 1, directDirectoriesCount: 0),
            entries: [DiskEntry(name: "link", path: "/fixture/A/link", isDirectory: false, value: .size(10), linkKey: key)],
            inodes: [key: 10]
        )
        try store.promote(staging, path: "/fixture/A")
        XCTAssertEqual(store.loadSummary(for: "/fixture")?.totalSize, 10)
        XCTAssertEqual(store.loadSummary(for: "/fixture/A")?.totalSize, 10)
    }

    static func fixture(directories: Int) -> DiskScanResult {
        var levels: [String: DiskLevel] = [:]
        var children: [DiskEntry] = []
        for index in 0..<directories {
            let path = "/fixture/d\(index)"
            children.append(DiskEntry(name: "d\(index)", path: path, isDirectory: true, value: .size(4)))
            levels[path] = DiskLevel(entries: (0..<4).map {
                DiskEntry(name: "f\($0)", path: path + "/f\($0)", isDirectory: false, value: .size(1))
            }, totalSize: 4)
        }
        levels["/fixture"] = DiskLevel(entries: children, totalSize: Int64(directories * 4))
        return DiskScanResult(path: "/fixture", totalSize: Int64(directories * 4), isReadable: true, levels: levels)
    }
}
