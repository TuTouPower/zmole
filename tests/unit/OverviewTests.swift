import XCTest
@testable import Zmole

@MainActor
final class OverviewTests: XCTestCase {
    func testStorageBreakdownComputesFiveSegmentsAndSubtractsDeveloper() {
        let breakdown = StorageBreakdown.make(
            applications: 40_000_000_000,
            system: 25_000_000_000,
            developer: 30_000_000_000,
            users: 90_000_000_000,
            usedBytes: 300_000_000_000
        )

        XCTAssertEqual(breakdown.userDataBytes, 60_000_000_000)
        XCTAssertEqual(
            breakdown.otherBytes,
            300_000_000_000 - (40_000_000_000 + 25_000_000_000 + 30_000_000_000 + 60_000_000_000)
        )
        XCTAssertTrue(breakdown.isComplete)
    }

    func testStorageBreakdownClampsNegativeValuesToZero() {
        let breakdown = StorageBreakdown.make(
            applications: 10,
            system: 10,
            developer: 500,
            users: 100,
            usedBytes: 50
        )

        XCTAssertEqual(breakdown.userDataBytes, 0)
        XCTAssertEqual(breakdown.otherBytes, 0)
    }

    func testStorageBreakdownIsPlaceholderWhenAnyInputMissing() {
        let breakdown = StorageBreakdown.make(
            applications: 10,
            system: nil,
            developer: 10,
            users: 10,
            usedBytes: 100
        )

        XCTAssertFalse(breakdown.isComplete)
        XCTAssertNil(breakdown.otherBytes)
        XCTAssertNil(StorageBreakdown.placeholder.applicationsBytes)
    }

    func testStorageEstimateLoaderSumsAnalyzeEntriesPerSegment() async throws {
        let sizes: [String: Int64] = [
            "/Applications": 40,
            "/System/Library": 20,
            "/System/Developer": 5,
            "/System/Volumes": 1_470_000_000_000,
            "~/Library/Developer": 30,
            "/Users": 90
        ]
        let loader = StorageEstimateLoader(
            directorySize: { sizes[$0] },
            systemChildren: { ["Library", "Developer", "Volumes"] }
        )
        let breakdown = try await loader.load(usedBytes: 300)

        XCTAssertEqual(breakdown.applicationsBytes, 40)
        XCTAssertEqual(
            breakdown.systemBytes,
            25,
            "system = analyze /System top-level children except /System/Volumes"
        )
        XCTAssertEqual(breakdown.developerBytes, 30)
        XCTAssertEqual(breakdown.userDataBytes, 60)
        XCTAssertEqual(breakdown.otherBytes, 145)
    }

    func testOverviewMetricsMatchInjectedSnapshot() {
        let snapshot = StatusSnapshot(
            healthScore: 87,
            healthScoreAvailable: true,
            cpu: .init(usage: 21.5, usageAvailable: true),
            memory: .init(used: 8_589_934_592, total: 17_179_869_184, usedPercent: 50),
            disks: [.init(mount: "/", used: 300_000_000_000, total: 1_000_000_000_000)],
            disksAvailable: true
        )
        let metrics = OverviewMetrics(snapshot: snapshot)

        XCTAssertEqual(metrics.healthText, "87")
        XCTAssertEqual(metrics.cpuText, "21.5%")
        XCTAssertEqual(metrics.freeDiskBytes, 700_000_000_000)
        XCTAssertFalse(metrics.memoryText.isEmpty)
    }

    func testOverviewMetricsShowUnknownWhenFieldsMissing() {
        let metrics = OverviewMetrics(snapshot: StatusSnapshot())
        XCTAssertEqual(metrics.healthText, "—")
        XCTAssertEqual(metrics.cpuText, "—")
        XCTAssertEqual(metrics.freeDiskText, "—")
    }

    // The t036 demo alignment removed the overview trend bar and the quick
    // cards, so `testOverviewTrendNeedsMinimumSamples` and
    // `testOverviewQuickActionsOnlyNavigateToDestinations` were deleted with
    // their types; the new page layout tests live in OverviewLayoutTests.

    func testOverviewViewModelLoadsBreakdownAndHistoryAndHandlesEmptyHistory() async {
        let loader = StorageEstimateLoader(
            directorySize: { _ in 10 },
            systemChildren: { ["Library"] }
        )
        let historyLoader = HistorySnapshotLoader { _ in
            MoleCommandResult(stdout: Self.historyFixture, stderr: "", exitCode: 0)
        }
        let viewModel = OverviewViewModel(storageLoader: loader, historyLoader: historyLoader)

        await viewModel.refreshHistory()
        await viewModel.refreshEstimateIfNeeded(usedBytes: 100)
        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 10)
        XCTAssertTrue(viewModel.hasRecentOperations)
        XCTAssertEqual(viewModel.recentOperations.first?.command, "clean")

        let emptyLoader = HistorySnapshotLoader { _ in
            MoleCommandResult(stdout: Self.emptyHistoryFixture, stderr: "", exitCode: 0)
        }
        let emptyViewModel = OverviewViewModel(storageLoader: loader, historyLoader: emptyLoader)
        await emptyViewModel.refreshHistory()
        XCTAssertFalse(emptyViewModel.hasRecentOperations)
    }

    func testStatusSnapshotDecodesTemperatureZombieAndMissingAsUnknown() throws {
        let withFields = """
        {"health_score":90,"thermal":{"cpu_temp":47},"zombie_count":2}
        """
        let decoded = try JSONDecoder().decode(StatusSnapshot.self, from: Data(withFields.utf8))
        XCTAssertEqual(decoded.cpuTemperature, 47)
        XCTAssertEqual(decoded.zombieCount, 2)

        let withoutFields = try JSONDecoder().decode(StatusSnapshot.self, from: Data("{}".utf8))
        XCTAssertNil(withoutFields.cpuTemperature)
        XCTAssertNil(withoutFields.zombieCount)
    }

    func testStatusReadoutShowsUnknownForMissingValues() {
        XCTAssertEqual(StatusReadout.temperature(nil), StatusReadout.unknown)
        XCTAssertEqual(StatusReadout.rate(nil), StatusReadout.unknown)
        XCTAssertEqual(StatusReadout.count(nil), StatusReadout.unknown)
        XCTAssertEqual(StatusReadout.temperature(47), "47°C")
        XCTAssertEqual(StatusReadout.count(0), "0")
    }

    func testStatusViewModelStopEndsSamplingAndStopsTheSharedService() async {
        let service = WatchServiceSpy()
        let viewModel = StatusViewModel(service: service)
        viewModel.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isSampling)

        await viewModel.stop()
        XCTAssertFalse(viewModel.isSampling)

        let stopCount = await service.stopCallCount
        XCTAssertGreaterThanOrEqual(stopCount, 1)
    }

    @MainActor
    func testOverviewRefreshResamplesByRestartingTheSubscription() async {
        let service = WatchServiceSpy()
        let viewModel = StatusViewModel(service: service)
        viewModel.start()
        try? await Task.sleep(nanoseconds: 100_000_000)

        await viewModel.resample()

        let pauseCount = await service.pauseCallCount
        XCTAssertGreaterThanOrEqual(pauseCount, 1, "refresh pauses the current subscription")
        XCTAssertTrue(viewModel.isSampling, "refresh immediately starts a fresh subscription")
    }

    private static let historyFixture = """
    {"limit":20,"sessions":[{"command":"clean","ended_at":"2026-09-22T10:20:00+08:00","items":12,"size":"3.2 GB"}],"deletions":[]}
    """

    private static let emptyHistoryFixture = """
    {"limit":20,"sessions":[],"deletions":[]}
    """
}

private actor WatchServiceSpy: StatusWatchProviding {
    private(set) var stopCallCount = 0
    private(set) var pauseCallCount = 0
    private var currentSnapshot: StatusSnapshot?
    private var currentSeries: [StatusSeriesPoint] = []

    var snapshot: StatusSnapshot? { currentSnapshot }
    var series: [StatusSeriesPoint] { currentSeries }

    func start() async {}
    func pause() async { pauseCallCount += 1 }
    func stop() async { stopCallCount += 1 }
    func retry() async {}

    func subscribe() async -> AsyncThrowingStream<StatusWatchUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                StatusWatchUpdate(snapshot: StatusSnapshot(), series: [], receivedAt: Date())
            )
        }
    }
}
