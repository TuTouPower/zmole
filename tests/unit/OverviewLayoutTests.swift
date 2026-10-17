import XCTest
@testable import Zmole

final class OverviewLayoutTests: XCTestCase {
    // MARK: - Health card

    func testHealthCardUsesRealValuesAndPlaceholdersForMissingSources() {
        let snapshot = StatusSnapshot(
            healthScore: 87,
            healthScoreAvailable: true,
            cpu: .init(usage: 21.5, usageAvailable: true),
            disks: [.init(mount: "/", used: 300_000_000_000, total: 1_000_000_000_000)],
            disksAvailable: true
        )

        let card = OverviewHealthCard.make(snapshot: snapshot, reclaimBytes: 12_400_000_000)

        XCTAssertEqual(card.scoreText, "87")
        XCTAssertEqual(card.status, .good)
        XCTAssertEqual(card.tiles.map(\.id), ["free_space", "reclaimable", "cpu"])
        XCTAssertEqual(card.tiles[0].value, OverviewMetrics.bytes(700_000_000_000))
        XCTAssertEqual(card.tiles[1].value, OverviewMetrics.bytes(12_400_000_000))
        XCTAssertEqual(card.tiles[2].value, "21.5%")
    }

    func testHealthCardShowsPlaceholdersWithoutSamples() {
        let card = OverviewHealthCard.make(snapshot: nil, reclaimBytes: nil)

        XCTAssertEqual(card.scoreText, "—")
        XCTAssertEqual(card.status, .unknown)
        XCTAssertEqual(card.tiles.map(\.value), ["—", "—", "—"])
        XCTAssertEqual(card.tiles[1].note, "overview.reclaim_no_scan")
    }

    func testHealthStatusThresholds() {
        XCTAssertEqual(OverviewHealth.status(for: nil), .unknown)
        XCTAssertEqual(OverviewHealth.status(for: 95), .good)
        XCTAssertEqual(OverviewHealth.status(for: 80), .good)
        XCTAssertEqual(OverviewHealth.status(for: 70), .fair)
        XCTAssertEqual(OverviewHealth.status(for: 10), .poor)
    }

    // MARK: - System status grid

    func testStatusGridMapsRealSamplesAndPlaceholders() {
        let snapshot = StatusSnapshot(
            cpu: .init(usage: 38, usageAvailable: true),
            memory: .init(used: 8_589_934_592, total: 17_179_869_184, usedPercent: 50),
            network: [StatusSnapshot.NetworkInterface(name: "en0", rxRateMBs: 2.1, txRateMBs: 0.3)],
            cpuTemperature: 54
        )

        let grid = OverviewStatusGrid.make(snapshot: snapshot)

        XCTAssertEqual(grid.tiles.map(\.id), ["cpu", "memory", "temperature", "network"])
        XCTAssertEqual(grid.tiles[0].value, "38.0%")
        XCTAssertTrue(grid.tiles[1].value.contains("/"))
        XCTAssertEqual(grid.tiles[2].value, "54°C")
        XCTAssertTrue(grid.tiles[3].value.contains("2.10 MB/s"))
        XCTAssertTrue(grid.tiles[3].value.contains("0.30 MB/s"))
    }

    func testStatusGridWithoutSampleShowsOnlyPlaceholders() {
        let grid = OverviewStatusGrid.make(snapshot: nil)

        XCTAssertEqual(grid.tiles.map(\.value), ["—", "—", "—", "—"])
    }

    // MARK: - Activity rows

    func testActivityRowsMapHistorySessionsInOrder() throws {
        let snapshot = try JSONDecoder().decode(HistorySnapshot.self, from: Data("""
        {"limit":20,"sessions":[
          {"command":"clean","ended_at":"2026-09-22T10:20:00+08:00","items":12,"size":"3.2 GB"},
          {"command":"optimize","ended_at":"2026-09-21T10:20:00+08:00","items":3,"size":"1.1 GB"}
        ],"deletions":[]}
        """.utf8))

        let rows = OverviewActivity.rows(from: snapshot.sessions)

        XCTAssertEqual(rows.map(\.command), ["clean", "optimize"])
        XCTAssertEqual(rows.map(\.symbol), ["sparkle", "gauge"])
        XCTAssertEqual(rows.first?.value, "3.2 GB")
        XCTAssertEqual(rows.first?.items, 12)
        XCTAssertEqual(rows.first?.time, "2026-09-22T10:20:00+08:00")
    }

    func testActivityRowsAreEmptyWithoutHistory() {
        XCTAssertTrue(OverviewActivity.rows(from: []).isEmpty)
    }

    // MARK: - Storage card

    func testStorageCardBuildsSegmentsAndFreeSpace() {
        let breakdown = StorageBreakdown.make(
            applications: 40_000_000_000,
            system: 25_000_000_000,
            developer: 30_000_000_000,
            users: 90_000_000_000,
            usedBytes: 300_000_000_000
        )
        let disk = StatusSnapshot.Disk(mount: "/", used: 300_000_000_000, total: 1_000_000_000_000)

        let card = OverviewStorageCard.make(breakdown: breakdown, disk: disk)

        XCTAssertEqual(card.usedText, OverviewMetrics.bytes(300_000_000_000))
        XCTAssertEqual(card.freeText, OverviewMetrics.bytes(700_000_000_000))
        XCTAssertEqual(card.freePercentText, "70.0%")
        XCTAssertEqual(card.capacityText, "/ · " + OverviewMetrics.bytes(1_000_000_000_000))
        XCTAssertTrue(card.isComplete)
        XCTAssertEqual(card.segments.count, 5)
        let fractionSum = card.segments.map(\.fraction).reduce(0, +)
        XCTAssertEqual(fractionSum, 1, accuracy: 0.0001, "segments cover the used bytes")
    }

    func testStorageCardReportsIncompleteEstimate() {
        let card = OverviewStorageCard.make(
            breakdown: .make(applications: 40, system: nil, developer: 30, users: 90, usedBytes: 300),
            disk: StatusSnapshot.Disk(mount: "/", used: 300, total: 1000)
        )

        XCTAssertFalse(card.isComplete)
        XCTAssertEqual(card.segments.count, 3, "missing segments render no bar piece")
    }

    // MARK: - Page structure

    func testOverviewDroppedQuickCardsAndTrend() throws {
        let source = try Self.source("Features/Overview/OverviewView.swift")
        XCTAssertFalse(source.contains("quickCards"))
        XCTAssertFalse(source.contains("trendCard"))
        XCTAssertFalse(source.contains("OverviewQuickAction"))
        XCTAssertFalse(source.contains("OverviewTrend"))
        XCTAssertTrue(source.contains("OverviewHealthCard"))
        XCTAssertTrue(source.contains("OverviewStatusGrid"))
        XCTAssertTrue(source.contains("OverviewActivity.rows"))
    }

    private static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/\(relative)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
