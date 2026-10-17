import XCTest
@testable import Zmole

@MainActor
final class StatusFeatureToggleTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private let suiteName = "test-status-toggle-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStatusFeatureDefaultsToEnabledAndPersistsAcrossRestarts() {
        let policy1 = StatusFeaturePolicy(userDefaults: testDefaults)
        XCTAssertTrue(policy1.isEnabled, "Status feature must default to enabled (AC-001)")

        policy1.setEnabled(false)
        XCTAssertFalse(policy1.isEnabled)

        let policy2 = StatusFeaturePolicy(userDefaults: testDefaults)
        XCTAssertFalse(policy2.isEnabled, "Disabled state must persist across restarts (AC-001)")

        policy2.setEnabled(true)
        XCTAssertTrue(policy2.isEnabled)

        let policy3 = StatusFeaturePolicy(userDefaults: testDefaults)
        XCTAssertTrue(policy3.isEnabled)
    }

    func testNavigationHidesStatusWhenDisabledAndRedirectsActiveStatusPage() {
        let policy = StatusFeaturePolicy(userDefaults: testDefaults)
        let navigation = NavigationModel(policy: policy)

        XCTAssertTrue(navigation.visibleDestinations(in: .workspace).contains(.status), "Status must be visible when enabled")
        XCTAssertTrue(navigation.paletteItems.contains { $0.destination == .status })

        navigation.select(.status)
        XCTAssertEqual(navigation.destination, .status)

        policy.setEnabled(false)

        XCTAssertFalse(navigation.visibleDestinations(in: .workspace).contains(.status), "Status must be hidden when disabled (AC-002)")
        XCTAssertFalse(navigation.paletteItems.contains { $0.destination == .status })
        XCTAssertEqual(navigation.destination, .overview, "Active status page must redirect to overview when disabled (AC-003)")

        navigation.select(.status)
        XCTAssertEqual(navigation.destination, .overview, "Programmatic navigation to status must be refused when disabled (AC-002)")
    }

    func testClosingFeatureTerminatesWatchProcessAndBlocksStartRetryResample() async {
        let streaming = StatusStreamingSpy()
        let watchService = StatusWatchService(streaming: streaming)
        let policy = StatusFeaturePolicy(userDefaults: testDefaults)
        let viewModel = StatusViewModel(service: watchService, policy: policy)

        viewModel.start()
        // Wait briefly for streaming to start
        for _ in 0..<10 {
            if streaming.activeProcesses > 0 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let activeBefore = streaming.activeProcesses
        XCTAssertEqual(activeBefore, 1, "Watch process must start when enabled")

        await viewModel.applyPolicyChange(enabled: false)
        XCTAssertFalse(viewModel.isSampling)

        let activeAfter = streaming.activeProcesses
        XCTAssertEqual(activeAfter, 0, "Watch process must terminate when disabled (AC-004)")

        viewModel.start()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let activeStart = streaming.activeProcesses
        XCTAssertEqual(activeStart, 0, "start() must not spawn when disabled (AC-004)")

        viewModel.retry()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let activeRetry = streaming.activeProcesses
        XCTAssertEqual(activeRetry, 0, "retry() must not spawn when disabled (AC-004)")

        await viewModel.resample()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let activeResample = streaming.activeProcesses
        XCTAssertEqual(activeResample, 0, "resample() must not spawn when disabled (AC-004)")
    }

    func testOverviewMetricsShowDisabledWhenStatusIsDisabled() {
        let snapshot = StatusSnapshot(
            healthScore: 85,
            healthScoreAvailable: true,
            cpu: StatusSnapshot.CPU(usage: 25.0, usageAvailable: true)
        )
        let healthEnabled = OverviewHealthCard.make(snapshot: snapshot, reclaimBytes: nil, isStatusEnabled: true)
        XCTAssertNotEqual(healthEnabled.scoreText, "—")

        let healthDisabled = OverviewHealthCard.make(snapshot: snapshot, reclaimBytes: nil, isStatusEnabled: false)
        XCTAssertEqual(healthDisabled.scoreText, "—", "Disabled health card must show dash (AC-006)")
        XCTAssertEqual(healthDisabled.status.titleKey, "overview.status.disabled")
        for tile in healthDisabled.tiles where tile.id != "reclaimable" {
            XCTAssertEqual(tile.value, "—")
            XCTAssertEqual(tile.note, "overview.status.disabled")
        }

        let gridDisabled = OverviewStatusGrid.make(snapshot: snapshot, isStatusEnabled: false)
        for tile in gridDisabled.tiles {
            XCTAssertEqual(tile.value, "—")
            XCTAssertEqual(tile.note, "overview.status.disabled")
        }
    }

    func testOverviewDiskCapacityWorksIndependentlyOfStatusWhenDisabled() async {
        let capacityProvider = StubVolumeCapacityProvider(
            result: VolumeCapacity(mount: "/", total: 500_000_000_000, used: 200_000_000_000, free: 300_000_000_000)
        )
        let streaming = StatusStreamingSpy()
        let viewModel = OverviewViewModel(
            storageLoader: nil,
            historyLoader: nil,
            storageCache: nil,
            coordinator: OperationCoordinator(),
            accessMonitor: FullDiskAccessMonitor(probe: { true }),
            volumeCapacityProvider: capacityProvider
        )

        await viewModel.refreshDiskCapacity()
        XCTAssertEqual(viewModel.diskCapacity?.total, 500_000_000_000)
        XCTAssertEqual(viewModel.diskCapacity?.used, 200_000_000_000)
        let inv1 = streaming.totalInvocations
        XCTAssertEqual(inv1, 0, "status-go must never run for disk capacity (AC-008)")

        let failingProvider = StubVolumeCapacityProvider(result: nil)
        let failingViewModel = OverviewViewModel(
            storageLoader: nil,
            historyLoader: nil,
            storageCache: nil,
            coordinator: OperationCoordinator(),
            accessMonitor: FullDiskAccessMonitor(probe: { true }),
            volumeCapacityProvider: failingProvider
        )
        await failingViewModel.refreshDiskCapacity()
        XCTAssertNil(failingViewModel.diskCapacity, "Failed capacity query must be nil/unknown (AC-008)")
        let inv2 = streaming.totalInvocations
        XCTAssertEqual(inv2, 0)
    }

    func testInFlightStartCancelledByDisablingDoesNotReviveSampling() async {
        let streaming = StatusStreamingSpy()
        let watchService = StatusWatchService(streaming: streaming)
        let policy = StatusFeaturePolicy(userDefaults: testDefaults)
        let viewModel = StatusViewModel(service: watchService, policy: policy)

        // Start sampling
        viewModel.start()
        // Immediately disable policy before data arrives
        await viewModel.applyPolicyChange(enabled: false)

        XCTAssertFalse(viewModel.isSampling, "Sampling must be false (AC-007)")
        XCTAssertNil(viewModel.snapshot, "Snapshot must be nil after disabling (AC-007)")
        let active = streaming.activeProcesses
        XCTAssertEqual(active, 0, "Process must terminate (AC-007)")
    }

    func testReenablingWhenOverviewIsVisibleStartsSamplingOnce() async {
        let streaming = StatusStreamingSpy()
        let watchService = StatusWatchService(streaming: streaming)
        let policy = StatusFeaturePolicy(userDefaults: testDefaults)
        let viewModel = StatusViewModel(service: watchService, policy: policy)
        let navigation = NavigationModel(initial: .settings, policy: policy)

        policy.setEnabled(false)
        await viewModel.applyPolicyChange(enabled: false)

        // Re-enabling while on settings does not start
        policy.setEnabled(true)
        if navigation.destination == .overview || navigation.destination == .status {
            viewModel.start()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let activeSettings = streaming.activeProcesses
        XCTAssertEqual(activeSettings, 0, "Must not start on settings (AC-009)")

        // Navigating to overview starts sampling
        navigation.select(.overview)
        if navigation.destination == .overview || navigation.destination == .status {
            viewModel.start()
        }
        for _ in 0..<10 {
            if streaming.activeProcesses > 0 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let activeOverview = streaming.activeProcesses
        XCTAssertEqual(activeOverview, 1, "Must start once when entering overview (AC-009)")
    }
}

private final class StatusStreamingSpy: MoleStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var _activeProcesses = 0
    private var _totalInvocations = 0

    var activeProcesses: Int {
        lock.lock()
        defer { lock.unlock() }
        return _activeProcesses
    }

    var totalInvocations: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalInvocations
    }

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        lock.lock()
        _totalInvocations += 1
        _activeProcesses += 1
        lock.unlock()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self._activeProcesses = max(0, self._activeProcesses - 1)
                self.lock.unlock()
            }
        }
    }

    func cancel() async {
        lock.lock()
        _activeProcesses = 0
        lock.unlock()
    }
}

private final class StubVolumeCapacityProvider: VolumeCapacityProviding, @unchecked Sendable {
    let result: VolumeCapacity?

    init(result: VolumeCapacity?) {
        self.result = result
    }

    func primaryVolumeCapacity() async -> VolumeCapacity? {
        result
    }
}
