import XCTest
@testable import Zmole

final class StatusChartTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testWindowKeepsOnlyTheTrailingSamples() {
        let series = [
            point(secondsAgo: 90, cpu: 10),
            point(secondsAgo: 45, cpu: 20),
            point(secondsAgo: 5, cpu: 30)
        ]

        let windowed = StatusChart.windowed(series, seconds: 60, now: now)

        XCTAssertEqual(windowed.map(\.cpuUsage), [20, 30])
    }

    func testFewerThanTwoSamplesProduceNoLine() {
        let single = [point(secondsAgo: 5, cpu: 10)]
        XCTAssertTrue(StatusChart.points(single, now: now, value: { $0.cpuUsage }, range: 0...100).isEmpty)
        XCTAssertTrue(StatusChart.points([], now: now, value: { $0.cpuUsage }, range: 0...100).isEmpty)
        XCTAssertFalse(StatusChart.isDrawable([]))
    }

    func testPointsNormalizeIntoUnitSpaceAndClamp() {
        let series = [
            point(secondsAgo: 40, cpu: -10),
            point(secondsAgo: 20, cpu: 50),
            point(secondsAgo: 1, cpu: 150)
        ]

        let points = StatusChart.points(series, now: now, value: { $0.cpuUsage }, range: 0...100)

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(Double(points[0].x), 0, accuracy: 0.0001)
        XCTAssertEqual(Double(points[2].x), 1, accuracy: 0.0001)
        XCTAssertEqual(Double(points[0].y), 0, accuracy: 0.0001, "values below the range clamp to the floor")
        XCTAssertEqual(Double(points[2].y), 1, accuracy: 0.0001, "values above the range clamp to the ceiling")
        XCTAssertEqual(Double(points[1].y), 0.5, accuracy: 0.0001)
    }

    func testMissingValuesAreSkippedAndCanLeaveNoLine() {
        let series = [
            point(secondsAgo: 30, cpu: nil),
            point(secondsAgo: 10, cpu: 42)
        ]

        let points = StatusChart.points(series, now: now, value: { $0.cpuUsage }, range: 0...100)

        XCTAssertTrue(points.isEmpty, "one usable sample cannot draw a line")
    }

    func testPathMapsUnitSpaceWithFlippedY() {
        let path = StatusChart.path([CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0)], in: CGSize(width: 200, height: 100))
        let bounds = path.boundingBox

        XCTAssertEqual(bounds.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxX, 200, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxY, 100, accuracy: 0.0001)
    }

    private func point(secondsAgo: TimeInterval, cpu: Double?) -> StatusSeriesPoint {
        let date = now.addingTimeInterval(-secondsAgo)
        let snapshot = StatusSnapshot(
            collectedAt: date,
            cpu: StatusSnapshot.CPU(usage: cpu ?? 0, usageAvailable: cpu != nil)
        )
        return StatusSeriesPoint(snapshot: snapshot, receivedAt: date)
    }
}

final class StatusStatValuesTests: XCTestCase {
    func testMissingFieldsRenderTheUnknownPlaceholder() {
        let snapshot = StatusSnapshot(healthScore: 0, healthScoreAvailable: false)

        let stats = StatusStatValues.make(from: snapshot)

        XCTAssertEqual(stats.cpu, StatusReadout.unknown)
        XCTAssertEqual(stats.memory, StatusReadout.unknown)
        XCTAssertEqual(stats.diskWrite, StatusReadout.unknown)
        XCTAssertEqual(stats.temperature, StatusReadout.unknown)
    }

    func testAvailableFieldsRenderRealValues() {
        let snapshot = StatusSnapshot(
            cpu: StatusSnapshot.CPU(usage: 23.5, usageAvailable: true),
            memory: StatusSnapshot.Memory(used: 8_589_934_592, total: 17_179_869_184),
            cpuTemperature: 48
        )

        let stats = StatusStatValues.make(from: snapshot)

        XCTAssertEqual(stats.cpu, "23.5%")
        let used = ByteCountFormatter.string(fromByteCount: 8_589_934_592, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: 17_179_869_184, countStyle: .file)
        XCTAssertEqual(stats.memory, "\(used) / \(total)")
        XCTAssertEqual(stats.temperature, "48°C")
    }

    func testWarmingDiskIOShowsSamplingInsteadOfZero() {
        let snapshot = StatusSnapshot(
            diskIO: StatusSnapshot.DiskIO(readRate: 0, writeRate: 0)
        )

        XCTAssertTrue(snapshot.diskIOIsWarming)
        XCTAssertEqual(
            StatusStatValues.make(from: snapshot).diskWrite,
            String(localized: "status.sampling"),
            "a warming zero must not be displayed as a measured rate"
        )
    }
}

final class HistoryTableTests: XCTestCase {
    func testEmptyStateProducesNoRows() {
        XCTAssertTrue(HistoryTable.rows(from: .empty).isEmpty)
    }

    func testSessionAndDeletionRowsShareTheFourColumns() throws {
        let snapshot = try Self.snapshot(
            sessions: """
            [{"command":"clean","ended_at":"2026-09-22T10:20:00+08:00","items":12,"size":"3.2 GB"}]
            """,
            deletions: """
            [{"path":"/Users/demo/Library/Caches/app/cache.db","timestamp":"2026-09-22T10:20:04+08:00","mode":"clean","status":"success","size_kb":128}]
            """
        )

        let rows = HistoryTable.rows(from: snapshot.displayState)

        XCTAssertEqual(rows.count, 2)
        let session = try XCTUnwrap(rows.first)
        XCTAssertEqual(session.kind, HistoryTableRow.Kind.session)
        XCTAssertEqual(session.date, "2026-09-22T10:20:00+08:00")
        XCTAssertEqual(session.action, "clean")
        XCTAssertEqual(session.result, "12 · 3.2 GB")
        XCTAssertEqual(session.status, .done)

        let deletion = try XCTUnwrap(rows.last)
        XCTAssertEqual(deletion.kind, HistoryTableRow.Kind.deletion)
        XCTAssertEqual(deletion.date, "2026-09-22T10:20:04+08:00")
        XCTAssertEqual(deletion.action, "/Users/demo/Library/Caches/app/cache.db")
        XCTAssertEqual(deletion.fullPath, deletion.action, "deletion rows keep the full path for the tooltip")
        XCTAssertEqual(deletion.status, .verbatim("success"))
        XCTAssertFalse(deletion.result.isEmpty)
    }

    func testMissingPartsFallBackToPlaceholders() throws {
        let snapshot = try Self.snapshot(
            sessions: """
            [{"command":"optimize","ended_at":"2026-09-22T10:20:00+08:00","items":3}]
            """,
            deletions: """
            [{"path":"/tmp/gone","timestamp":"","mode":"clean","status":"success"}]
            """
        )

        let rows = HistoryTable.rows(from: snapshot.displayState)

        let session = try XCTUnwrap(rows.first)
        XCTAssertEqual(session.result, "3", "a session without a size shows only the item count")
        let deletion = try XCTUnwrap(rows.last)
        XCTAssertEqual(deletion.date, "—", "an empty deletion timestamp shows a placeholder")
        XCTAssertEqual(deletion.result, "—", "a deletion without a size shows a placeholder")
    }

    private static func snapshot(sessions: String, deletions: String) throws -> HistorySnapshot {
        try JSONDecoder().decode(HistorySnapshot.self, from: Data("""
        {"limit":20,"sessions":\(sessions),"deletions":\(deletions)}
        """.utf8))
    }
}

final class NoticeToneTests: XCTestCase {
    func testToneMappingKeepsErrorAndInfoDistinct() {
        XCTAssertEqual(UtilityNotice.tone(isInfo: false, isError: true), .error)
        XCTAssertEqual(UtilityNotice.tone(isInfo: true, isError: false), .info)
        XCTAssertEqual(UtilityNotice.tone(isInfo: false, isError: false), .accent)
        XCTAssertEqual(
            UtilityNotice.tone(isInfo: true, isError: true),
            .error,
            "error always wins so danger styling is never replaced by the info banner"
        )
    }
}

/// Page-structure guardrails. These assert on production source text on
/// purpose: they exist to catch a regression (a page dropping the shared head
/// or re-adding a duplicate toolbar), not to prove rendering behavior — the
/// behavior itself is covered by the page ViewModel tests.
final class PageHeadAdoptionTests: XCTestCase {
    func testTheFivePagesUseTheSharedPageHead() throws {
        let pages = [
            "Features/Uninstall/UninstallView.swift",
            "Features/Analyze/AnalyzeView.swift",
            "Features/Status/StatusView.swift",
            "Features/History/HistoryView.swift",
            "Features/Settings/SettingsView.swift"
        ]
        for page in pages {
            let source = try Self.source(page)
            XCTAssertTrue(
                source.contains("MolePageHead("),
                "\(page) must use the shared page head"
            )
        }
    }

    func testUninstallAndHistoryDroppedTheirWindowToolbars() throws {
        for page in ["Features/Uninstall/UninstallView.swift", "Features/History/HistoryView.swift"] {
            let source = try Self.source(page)
            XCTAssertFalse(
                source.contains(".toolbar {"),
                "\(page) must not duplicate page actions in the window toolbar"
            )
        }
    }

    func testExplanatoryBannersUseTheInfoStyle() throws {
        let expectations = [
            "Features/Optimize/OptimizeView.swift": "optimize.preview_note",
            "Features/Purge/PurgeView.swift": "purge.preview_note",
            "Features/History/HistoryView.swift": "history.info_note"
        ]
        for (page, key) in expectations {
            let source = try Self.source(page)
            let range = try XCTUnwrap(source.range(of: key))
            let tail = source[range.lowerBound...].prefix(160)
            XCTAssertTrue(
                tail.contains("isInfo: true"),
                "\(key) in \(page) must render the blue info banner"
            )
        }
    }

    func testDangerAndWarningBannersStayUnchanged() throws {
        let optimize = try Self.source("Features/Optimize/OptimizeView.swift")
        let range = try XCTUnwrap(optimize.range(of: "optimize.permanent_note"))
        XCTAssertTrue(optimize[range.lowerBound...].prefix(160).contains("isError: true"))
        let purge = try Self.source("Features/Purge/PurgeView.swift")
        let purgeRange = try XCTUnwrap(purge.range(of: "purge.permanent_note"))
        XCTAssertTrue(purge[purgeRange.lowerBound...].prefix(160).contains("isError: true"))
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
