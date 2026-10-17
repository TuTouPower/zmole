import XCTest
@testable import Zmole

@MainActor
final class OverviewCacheTests: XCTestCase {
    private func makeCache(_ directory: URL) -> StorageEstimateCache {
        StorageEstimateCache(fileURL: directory.appendingPathComponent("storage_estimate.json"))
    }

    private func makeLoader(counts: EstimateCounter, failing: Set<String> = []) -> StorageEstimateLoader {
        StorageEstimateLoader(
            directorySize: { path in
                await counts.increment()
                if failing.contains(path) { return nil }
                switch path {
                case "/Applications": return 40
                case "/System/Library": return 25
                case "~/Library/Developer": return 30
                case "/Users": return 90
                default: return nil
                }
            },
            systemChildren: { ["Library", "Volumes"] }
        )
    }

    func testPrimeRendersFromCacheWithoutRunningAnalyze() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        cache.save(StorageSums(applications: 40, system: 25, developer: 30, users: 90), capturedAt: now)

        let counts = EstimateCounter()
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: counts),
            historyLoader: nil,
            storageCache: cache,
            now: { now }
        )

        viewModel.primeEstimate(usedBytes: 300)
        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 40)
        XCTAssertEqual(viewModel.breakdown.userDataBytes, 60)
        let renderCount = await counts.value
        XCTAssertEqual(renderCount, 0, "cached render must not run analyze")
    }

    func testNoCacheFallsBackToScan() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let counts = EstimateCounter()
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: counts),
            historyLoader: nil,
            storageCache: cache,
            now: { Date(timeIntervalSince1970: 5_000_000) }
        )

        viewModel.primeEstimate(usedBytes: 300)
        XCTAssertEqual(viewModel.breakdown, .placeholder)

        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()
        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 40)
        let scanCount = await counts.value
        XCTAssertGreaterThan(scanCount, 0, "missing cache must fall back to a scan")
    }

    func testFreshCacheSkipsScan() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        cache.save(StorageSums(applications: 40, system: 25, developer: 30, users: 90), capturedAt: now)

        let counts = EstimateCounter()
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: counts),
            historyLoader: nil,
            storageCache: cache,
            now: { now }
        )
        viewModel.primeEstimate(usedBytes: 300)
        XCTAssertFalse(viewModel.estimateNeedsRefresh)

        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()
        let freshCount = await counts.value
        XCTAssertEqual(freshCount, 0, "a fresh cache must not re-scan")
    }

    func testStaleCacheRefreshesInBackground() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let captured = Date(timeIntervalSince1970: 5_000_000)
        cache.save(StorageSums(applications: 1, system: 1, developer: 1, users: 1), capturedAt: captured)
        let now = captured.addingTimeInterval(StorageEstimateCache.timeToLive + 60)

        let counts = EstimateCounter()
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: counts),
            historyLoader: nil,
            storageCache: cache,
            now: { now }
        )
        viewModel.primeEstimate(usedBytes: 300)
        XCTAssertTrue(viewModel.estimateNeedsRefresh)

        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()
        let staleCount = await counts.value
        XCTAssertEqual(staleCount, 4)
        let saved = try XCTUnwrap(cache.load(now: now))
        XCTAssertEqual(saved.sums.applications, 40)
        XCTAssertEqual(saved.capturedAt, now)
    }

    func testCoordinatorInvalidationForcesRefresh() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        cache.save(StorageSums(applications: 40, system: 25, developer: 30, users: 90), capturedAt: now)
        let coordinator = OperationCoordinator()

        let counts = EstimateCounter()
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: counts),
            historyLoader: nil,
            storageCache: cache,
            coordinator: coordinator,
            now: { now }
        )
        viewModel.primeEstimate(usedBytes: 300)
        XCTAssertFalse(viewModel.estimateNeedsRefresh)

        coordinator.invalidatePreviews()
        XCTAssertTrue(viewModel.estimateInvalidated)
        XCTAssertTrue(viewModel.estimateNeedsRefresh)
        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()
        XCTAssertFalse(viewModel.estimateInvalidated)
    }

    func testIncompleteScanRendersPersistsAndRetriesMissingSegmentsOnce() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        let recorder = ProbePathRecorder()
        let loader = StorageEstimateLoader(
            directorySize: { path in
                await recorder.record(path)
                if path.hasPrefix("/System/") { return nil }
                switch path {
                case "/Applications": return 40
                case "~/Library/Developer": return 30
                case "/Users": return 90
                default: return nil
                }
            },
            systemChildren: { ["Library"] }
        )
        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            storageCache: cache,
            incompleteRetryDelay: 0.05,
            now: { now }
        )

        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()

        // The resolved segments render even though the system segment failed.
        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 40)
        XCTAssertNil(viewModel.breakdown.systemBytes)
        XCTAssertFalse(viewModel.breakdown.isComplete, "the incomplete marker stays visible")

        // The completed partial scan is persisted.
        let saved = try XCTUnwrap(cache.load(now: now))
        XCTAssertFalse(saved.sums.isComplete)
        XCTAssertEqual(saved.sums.applications, 40)
        XCTAssertNil(saved.sums.system)

        // Exactly one follow-up retry ran, and it re-probed only the missing
        // segment.
        let paths = await recorder.paths
        XCTAssertEqual(
            paths.filter { $0 == "/Applications" }.count, 1,
            "the retry must not re-probe resolved segments"
        )
        XCTAssertEqual(
            paths.filter { $0 == "/System/Library" }.count, 2,
            "exactly one follow-up retry may run per scan"
        )
    }

    func testCancelledScanDoesNotPersistAnything() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        let loader = StorageEstimateLoader(
            directorySize: { path in
                if path == "/System/Library" { throw CancellationError() }
                switch path {
                case "/Applications": return 40
                case "~/Library/Developer": return 30
                case "/Users": return 90
                default: return nil
                }
            },
            systemChildren: { ["Library"] }
        )
        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            storageCache: cache,
            now: { now }
        )

        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()

        XCTAssertEqual(viewModel.breakdown, .placeholder)
        XCTAssertNil(cache.load(now: now), "a cancelled scan must not write a cache")
    }

    func testPartialHistoricalCacheRendersFirstThenCompleteScanOverwrites() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let oldCapture = Date(timeIntervalSince1970: 5_000_000).addingTimeInterval(-3_600)
        cache.save(
            StorageSums(applications: 40, system: nil, developer: 30, users: 90),
            capturedAt: oldCapture
        )
        let now = Date(timeIntervalSince1970: 5_000_000)
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: EstimateCounter()),
            historyLoader: nil,
            storageCache: cache,
            now: { now }
        )

        viewModel.primeEstimate(usedBytes: 300)
        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 40, "the historical cache renders first")
        XCTAssertTrue(viewModel.estimateNeedsRefresh)

        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()

        XCTAssertTrue(viewModel.breakdown.isComplete)
        XCTAssertEqual(viewModel.breakdown.systemBytes, 25)
        let saved = try XCTUnwrap(cache.load(now: now))
        XCTAssertTrue(saved.sums.isComplete)
        XCTAssertEqual(
            saved.capturedAt, oldCapture,
            "the fill-only scan keeps the original capture time for the reused segments"
        )
    }

    func testSystemSegmentNeverProbesTheDataVolume() async throws {
        let recorder = ProbePathRecorder()
        let loader = StorageEstimateLoader(
            directorySize: { path in
                await recorder.record(path)
                return 1
            },
            systemChildren: { ["Library", "Volumes", "Developer"] }
        )

        _ = try await loader.loadSums()

        let paths = await recorder.paths
        XCTAssertTrue(paths.contains("/System/Library"))
        XCTAssertTrue(paths.contains("/System/Developer"))
        XCTAssertFalse(
            paths.contains("/System/Volumes"),
            "the data volume mounted at /System/Volumes must never be walked"
        )
    }

    func testSystemSegmentIsUnavailableWhenAnyChildProbeFails() async throws {
        let loader = StorageEstimateLoader(
            directorySize: { path in
                path == "/System/Library" ? nil : 5
            },
            systemChildren: { ["Library", "Developer"] }
        )

        let sums = try await loader.loadSums()

        XCTAssertNil(
            sums.system,
            "one unreadable child must make the segment unavailable, not shrink it silently"
        )
        XCTAssertFalse(sums.isComplete)
    }

    func testInvalidCacheIsIgnored() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)

        try JSONEncoder().encode(StorageEstimateCacheEntry(
            schemaVersion: 999,
            capturedAt: now,
            sums: StorageSums(applications: 1, system: 1, developer: 1, users: 1)
        )).write(to: cache.fileURL)
        XCTAssertNil(cache.load(now: now))

        try JSONEncoder().encode(StorageEstimateCacheEntry(
            schemaVersion: StorageEstimateCache.schemaVersion,
            capturedAt: now.addingTimeInterval(-StorageEstimateCache.maximumAge - 60),
            sums: StorageSums(applications: 1, system: 1, developer: 1, users: 1)
        )).write(to: cache.fileURL)
        XCTAssertNil(cache.load(now: now))
    }

    func testSchemaOneCacheIsIgnoredAfterTheSchemaBump() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)

        try JSONEncoder().encode(StorageEstimateCacheEntry(
            schemaVersion: 1,
            capturedAt: now,
            sums: StorageSums(applications: 1, system: 1, developer: 1, users: 1)
        )).write(to: cache.fileURL)

        XCTAssertNil(
            cache.load(now: now),
            "schema-1 entries carry the old data-volume-inflated system sum and must be discarded"
        )
    }

    func testEstimateRunsWithoutUsedBytesAndOtherSegmentArrivesLater() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counts = EstimateCounter()
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: counts),
            historyLoader: nil,
            now: { Date(timeIntervalSince1970: 5_000_000) }
        )

        // The scan starts with no status sample at all.
        viewModel.startEstimate(usedBytes: nil)
        await viewModel.waitForEstimate()

        XCTAssertEqual(
            viewModel.breakdown.applicationsBytes, 40,
            "the scan must not wait for the status sample"
        )
        XCTAssertEqual(viewModel.breakdown.systemBytes, 25)
        XCTAssertNil(
            viewModel.breakdown.otherBytes,
            "other stays a placeholder until used space arrives"
        )

        viewModel.usedBytesDidChange(500)
        XCTAssertEqual(
            viewModel.breakdown.otherBytes,
            500 - (40 + 25 + 30 + 60),
            "other derives from the late used-space value without rescanning"
        )
        let scanCount = await counts.value
        XCTAssertEqual(scanCount, 4, "the late used-space value must not trigger a rescan")
    }

    func testEstimateTaskIsNotTiedToTheStartingCaller() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = ScanGate()
        let loader = StorageEstimateLoader(
            directorySize: { _ in
                await gate.pauseOnce()
                return 10
            },
            systemChildren: { ["Library"] }
        )
        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            now: { Date(timeIntervalSince1970: 5_000_000) }
        )

        // Simulates the page task: it starts the scan and then lingers while
        // the scan runs; the cancellation below lands mid-scan.
        let caller = Task { @MainActor in
            viewModel.startEstimate(usedBytes: 100)
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
        await gate.waitUntilPaused()
        caller.cancel()
        await caller.value
        await gate.release()
        await viewModel.waitForEstimate()

        XCTAssertEqual(
            viewModel.breakdown.applicationsBytes, 10,
            "cancelling the starting task must not cancel the scan"
        )
    }

    func testIncompleteCacheIsNotTreatedAsFresh() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        cache.save(StorageSums(applications: 40, system: nil, developer: 30, users: 90), capturedAt: now)

        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: EstimateCounter()),
            historyLoader: nil,
            storageCache: cache,
            now: { now }
        )
        viewModel.primeEstimate(usedBytes: 300)
        XCTAssertTrue(
            viewModel.estimateNeedsRefresh,
            "a partial cache must not suppress a retry for the failed path"
        )
    }

    func testInvalidationRescansResolvedSegmentsInsteadOfOnlyFilling() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        let coordinator = OperationCoordinator()
        let recorder = ProbePathRecorder()
        let loader = StorageEstimateLoader(
            directorySize: { path in
                await recorder.record(path)
                if path.hasPrefix("/System/") { return nil }
                switch path {
                case "/Applications": return 40
                case "~/Library/Developer": return 30
                case "/Users": return 90
                default: return nil
                }
            },
            systemChildren: { ["Library"] }
        )
        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            storageCache: cache,
            coordinator: coordinator,
            incompleteRetryDelay: 5,
            now: { now }
        )

        // First scan lands partial (system segment fails) and persists it.
        viewModel.startEstimate(usedBytes: 300)
        for _ in 0..<400 where cache.load(now: now) == nil {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let afterFirstScan = await recorder.paths
        XCTAssertEqual(afterFirstScan.filter { $0 == "/Applications" }.count, 1)

        // A write invalidation must re-probe every segment, not only the
        // missing ones: the resolved segments predate the write.
        coordinator.invalidatePreviews()
        viewModel.startEstimate(usedBytes: 300)
        for _ in 0..<400 {
            let hits = await recorder.paths.filter { $0 == "/Applications" }.count
            if hits >= 2 { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let afterRescan = await recorder.paths
        XCTAssertEqual(
            afterRescan.filter { $0 == "/Applications" }.count, 2,
            "an invalidation must re-probe resolved segments, not only fill missing ones"
        )
    }

    func testEstimateLaneTimeoutIsTenMinutes() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/App/AppDependencies.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let range = try XCTUnwrap(source.range(of: "let estimateLoaders"))
        let segment = source[range.lowerBound...].prefix(420)
        XCTAssertTrue(
            segment.contains("timeout: 600"),
            "the estimate lane must allow ten minutes per command"
        )
    }

    func testFillOnlyScanDoesNotRefreshTheCacheTimestamp() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let captured = Date(timeIntervalSince1970: 5_000_000)
        cache.save(StorageSums(applications: 40, system: nil, developer: 30, users: 90), capturedAt: captured)
        let clock = MutableNow(captured.addingTimeInterval(5 * 3_600))
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: EstimateCounter()),
            historyLoader: nil,
            storageCache: cache,
            incompleteRetryDelay: 5,
            now: { clock.now }
        )

        viewModel.primeEstimate(usedBytes: 300)
        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()

        let saved = try XCTUnwrap(cache.load(now: clock.now))
        XCTAssertTrue(saved.sums.isComplete)
        XCTAssertEqual(
            saved.capturedAt, captured,
            "a fill-only scan must not refresh the cache timestamp for reused segments"
        )

        // Once the original capture time passes the TTL, the estimate goes
        // stale again and the next trigger rescans everything.
        clock.advance(by: StorageEstimateCache.timeToLive + 60)
        XCTAssertTrue(viewModel.estimateNeedsRefresh)
    }

    func testInvalidationDuringScanEscalatesFollowUpToFullRescan() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        cache.save(StorageSums(applications: 40, system: nil, developer: 30, users: 90), capturedAt: now)
        let coordinator = OperationCoordinator()
        let gate = ScanGate()
        let recorder = ProbePathRecorder()
        let loader = StorageEstimateLoader(
            directorySize: { path in
                await recorder.record(path)
                await gate.pauseOnce()
                if path.hasPrefix("/System/") { return nil }
                switch path {
                case "/Applications": return 40
                case "~/Library/Developer": return 30
                case "/Users": return 90
                default: return nil
                }
            },
            systemChildren: { ["Library"] }
        )
        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            storageCache: cache,
            coordinator: coordinator,
            incompleteRetryDelay: 0.05,
            now: { now }
        )

        // Fill-only first scan (the cache only misses the system segment).
        viewModel.primeEstimate(usedBytes: 300)
        viewModel.startEstimate(usedBytes: 300)
        await gate.waitUntilPaused()
        coordinator.invalidatePreviews()
        await gate.release()
        await viewModel.waitForEstimate()

        // The follow-up must escalate to a full rescan because a write landed
        // mid-scan; a fill-only follow-up would never re-probe /Applications.
        let paths = await recorder.paths
        XCTAssertEqual(
            paths.filter { $0 == "/Applications" }.count, 1,
            "a mid-scan invalidation must escalate the follow-up to a full rescan"
        )
        let probeCount = await recorder.paths.count
        XCTAssertEqual(
            probeCount, 5,
            "fill-only first pass probes one segment; the escalated follow-up probes all four"
        )
    }

    func testInvalidationDuringCompleteScanKeepsEstimateStaleUntilCompensationRescan() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 5_000_000)
        let coordinator = OperationCoordinator()
        let firstScanGate = ScanGate()
        let compensationGate = ScanGate()
        let recorder = ProbePathRecorder()
        let loader = StorageEstimateLoader(
            directorySize: { path in
                await recorder.record(path)
                // The first probe blocks the initial scan; the fifth probe is
                // the compensation rescan's first probe.
                let probe = await recorder.paths.count
                if probe == 1 { await firstScanGate.pauseOnce() }
                if probe == 5 { await compensationGate.pauseOnce() }
                switch path {
                case "/Applications": return 40
                case "~/Library/Developer": return 30
                case "/Users": return 90
                case "/System/Library": return 25
                default: return nil
                }
            },
            systemChildren: { ["Library"] }
        )
        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            storageCache: makeCache(directory),
            coordinator: coordinator,
            incompleteRetryDelay: 0.05,
            now: { now }
        )

        viewModel.startEstimate(usedBytes: 300)
        await firstScanGate.waitUntilPaused()
        coordinator.invalidatePreviews()
        await firstScanGate.release()

        // The invalidated first scan completes all four segments on its own;
        // the flag must survive it and only clear after the compensation.
        await compensationGate.waitUntilPaused()
        XCTAssertTrue(
            viewModel.estimateInvalidated,
            "an invalidation that lands mid-scan must not be cleared by that scan"
        )
        await compensationGate.release()
        await viewModel.waitForEstimate()

        let paths = await recorder.paths
        XCTAssertEqual(
            paths.filter { $0 == "/Applications" }.count, 2,
            "a mid-scan invalidation must trigger a full rescan even when the first scan completes"
        )
        XCTAssertEqual(
            paths.count, 8,
            "the complete first pass probes four segments; the compensation rescan probes all four again"
        )
        XCTAssertFalse(
            viewModel.estimateInvalidated,
            "the compensation rescan must clear the invalidation"
        )
    }

    private func tempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("overview-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor EstimateCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor ProbePathRecorder {
    private(set) var paths: [String] = []
    func record(_ path: String) { paths.append(path) }
}

/// Blocks the first directory probe until released, so a test can invalidate the
/// estimate while a scan is in flight.
private actor ScanGate {
    private var paused = false
    private var continuation: CheckedContinuation<Void, Never>?

    func pauseOnce() async {
        guard !paused else { return }
        paused = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilPaused() async {
        for _ in 0..<500 {
            if paused { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("ScanGate never observed a paused probe")
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

/// Injectable, advanceable clock for TTL tests.
private final class MutableNow: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value += interval
        lock.unlock()
    }
}
