import XCTest
@testable import Zmole

@MainActor
final class OverviewCacheTests: XCTestCase {
    private func makeCache(_ directory: URL) -> StorageEstimateCache {
        StorageEstimateCache(fileURL: directory.appendingPathComponent("storage_estimate.json"))
    }

    private func makeLoader(counts: EstimateCounter, failing: Set<String> = []) -> StorageEstimateLoader {
        StorageEstimateLoader { path in
            await counts.increment()
            if failing.contains(path) { return nil }
            switch path {
            case "/Applications": return 40
            case "/System": return 25
            case "~/Library/Developer": return 30
            case "/Users": return 90
            default: return nil
            }
        }
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

        await viewModel.refreshEstimateIfNeeded(usedBytes: 300)
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

        await viewModel.refreshEstimateIfNeeded(usedBytes: 300)
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

        await viewModel.refreshEstimateIfNeeded(usedBytes: 300)
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
        await viewModel.refreshEstimateIfNeeded(usedBytes: 300)
        XCTAssertFalse(viewModel.estimateInvalidated)
    }

    func testFailedDirectoryLeavesPlaceholderAndSavesPartialCache() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        let counts = EstimateCounter()
        let viewModel = OverviewViewModel(
            storageLoader: makeLoader(counts: counts, failing: ["/System"]),
            historyLoader: nil,
            storageCache: cache,
            now: { now }
        )

        await viewModel.refreshEstimateIfNeeded(usedBytes: 300)
        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 40)
        XCTAssertNil(viewModel.breakdown.systemBytes)
        XCTAssertFalse(viewModel.breakdown.isComplete)
        let saved = try XCTUnwrap(cache.load(now: now))
        XCTAssertNil(saved.sums.system)
        XCTAssertEqual(saved.sums.applications, 40)
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

    func testInvalidationDuringScanKeepsEstimateStale() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let now = Date(timeIntervalSince1970: 5_000_000)
        let coordinator = OperationCoordinator()
        let gate = ScanGate()
        let loader = StorageEstimateLoader { _ in
            await gate.pauseOnce()
            return 10
        }
        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            storageCache: cache,
            coordinator: coordinator,
            now: { now }
        )

        let scan = Task { @MainActor in await viewModel.refreshEstimateIfNeeded(usedBytes: 100) }
        await gate.waitUntilPaused()
        coordinator.invalidatePreviews()
        await gate.release()
        await scan.value

        XCTAssertTrue(
            viewModel.estimateInvalidated,
            "an invalidation that lands mid-scan must not be cleared by the scan"
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
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
