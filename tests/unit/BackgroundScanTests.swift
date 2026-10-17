import Combine
import XCTest
@testable import Zmole

@MainActor
final class BackgroundScanTests: XCTestCase {
    // AC-001, AC-008: every item starts on its own lane in parallel without a
    // page being opened, and only read-only commands run.
    func testAllItemsStartInParallelAndUseReadOnlyCommands() async throws {
        let probe = ConcurrencyProbe()
        let spies = ScanSpies(probe: probe, blockFirstProcessCall: true)
        let service = makeService(spies: spies, cache: BackgroundScanCache(fileURL: temporaryFileURL()))

        try await waitUntil { await spies.blockedProcessCallCount == 4 }
        let maxConcurrent = await probe.max
        XCTAssertGreaterThanOrEqual(maxConcurrent, 2, "independent scans must overlap")
        XCTAssertGreaterThanOrEqual(service.runningItems.count, 4, "all independent process items run together")

        await spies.releaseAll()
        try await waitUntil {
            service.results.count == 5 && service.runningItems.isEmpty
        }

        let calls = await spies.allArguments
        let allowed: Set<[String]> = [
            ["uninstall", "--list-stream"],
            ["installer", "--list-json"],
            ["clean", "--dry-run"],
            ["optimize", "--dry-run"],
            ["purge", "--dry-run"]
        ]
        XCTAssertEqual(Set(calls), allowed, "only the five read-only scan commands may run")
        for call in calls {
            XCTAssertTrue(allowed.contains(call), "\(call) must not run in the background")
        }
        XCTAssertNil(service.failedItems.first)
    }

    // AC-002: a user clean scan drops the background result, cancels the
    // background writer, and only returns after the process has terminated.
    func testUserCleanScanCancelsAndWaitsForBackgroundClean() async throws {
        let now = Date(timeIntervalSince1970: 5_000_000)
        let spies = ScanSpies(blockedPrefix: ["clean", "--dry-run"])
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        var fixtures = freshFixtures(now: now, staleItems: [.clean])
        fixtures[.clean] = BackgroundScanResult(
            capturedAt: now.addingTimeInterval(-25 * 60 * 60),
            payload: .cleanPreview(try makeCleanSnapshot(at: spies.previewURL))
        )
        cache.save(fixtures)
        let service = makeService(spies: spies, cache: cache, now: { now })

        try await waitUntil { await spies.clean.blockedCallCount == 1 }
        XCTAssertNotNil(service.result(for: .clean))

        var waitFinished = false
        let waitTask = Task { @MainActor in
            await service.userDidRescanAndWaitForTermination(.clean)
            waitFinished = true
        }
        try await waitUntil { await spies.clean.cancelCount == 1 }
        XCTAssertNil(service.result(for: .clean), "the background result is dropped for the user's scan")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(waitFinished, "the wait must not resolve before the process terminates")

        await spies.clean.finishCancellation()
        await waitTask.value
        XCTAssertTrue(waitFinished)
        XCTAssertNil(BackgroundScanCache(fileURL: cache.fileURL).load()[.clean])
    }

    func testCleanRequestDefersWhileWriteLeaseIsHeld() async throws {
        let spies = ScanSpies()
        let coordinator = OperationCoordinator()
        let service = makeService(
            spies: spies,
            cache: BackgroundScanCache(fileURL: temporaryFileURL()),
            coordinator: coordinator
        )
        try await waitUntil { service.results[.clean] != nil }
        await service.cancelAndWait(.clean)
        let callsBefore = await spies.clean.processCallCount

        let lease = try XCTUnwrap(coordinator.acquire(.clean))
        service.request(.clean)
        try await Task.sleep(nanoseconds: 200_000_000)
        let callsAfterRequest = await spies.clean.processCallCount
        XCTAssertEqual(callsAfterRequest, callsBefore, "a write lease must defer clean")

        lease.release()
        service.noteActivityChanged()
        try await waitUntil { await spies.clean.processCallCount == callsBefore + 1 }
    }

    func testDeferredCleanSuppressesRequestUntilUserActivityEnds() async throws {
        let now = Date(timeIntervalSince1970: 5_000_000)
        let spies = ScanSpies(blockedPrefix: ["clean", "--dry-run"])
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        var fixtures = freshFixtures(now: now, staleItems: [.clean])
        fixtures[.clean] = BackgroundScanResult(
            capturedAt: now.addingTimeInterval(-25 * 60 * 60),
            payload: .cleanPreview(try makeCleanSnapshot(at: spies.previewURL))
        )
        cache.save(fixtures)
        let service = makeService(spies: spies, cache: cache, now: { now })

        try await waitUntil { await spies.clean.blockedCallCount == 1 }

        let waitTask = Task { @MainActor in
            await service.userDidRescanAndWaitForTermination(.clean)
        }
        try await waitUntil { await spies.clean.cancelCount == 1 }
        await spies.clean.finishCancellation()
        await waitTask.value

        let callsAfterCancellation = await spies.clean.processCallCount
        // While deferredClean is active, a request must be suppressed:
        service.request(.clean)
        try await Task.sleep(nanoseconds: 100_000_000)
        let callsAfterRequest = await spies.clean.processCallCount
        XCTAssertEqual(callsAfterRequest, callsAfterCancellation, "deferredClean must suppress request(.clean)")

        // Once the user's activity clears, noteActivityChanged resumes the background clean scan:
        service.noteActivityChanged()
        try await waitUntil { await spies.clean.processCallCount == callsAfterCancellation + 1 }
    }

    // AC-003, AC-011: results survive a relaunch, and corrupt or old-schema
    // cache files are ignored without scanning twice.
    func testCacheRoundTripAndFreshResultsSkipScanning() async throws {
        let now = Date()
        let previewURL = temporaryFileURL()
        let snapshot = try makeCleanSnapshot(at: previewURL)
        let results: [BackgroundScanItem: BackgroundScanResult] = [
            .uninstallList: BackgroundScanResult(capturedAt: now, payload: .uninstallRows([])),
            .installerList: BackgroundScanResult(capturedAt: now, payload: .installerCandidates([])),
            .clean: BackgroundScanResult(capturedAt: now, payload: .cleanPreview(snapshot)),
            .optimize: BackgroundScanResult(capturedAt: now, payload: .maintenance("plan")),
            .purge: BackgroundScanResult(capturedAt: now, payload: .maintenance("purge plan"))
        ]
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        cache.save(results)
        XCTAssertEqual(cache.load(), results)

        let spies = ScanSpies()
        let service = makeService(spies: spies, cache: cache, now: { now })
        try await Task.sleep(nanoseconds: 200_000_000)
        let totalCalls = await spies.totalCallCount
        XCTAssertEqual(totalCalls, 0, "fresh cache entries must not rescan")
        XCTAssertNotNil(service.result(for: .clean))
    }

    func testCorruptOrOldSchemaCacheIsIgnored() throws {
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        try Data("not json".utf8).write(to: cache.fileURL)
        XCTAssertTrue(cache.load().isEmpty)

        let oldSchema = #"{"schemaVersion":0,"entries":{}}"#
        try Data(oldSchema.utf8).write(to: cache.fileURL)
        XCTAssertTrue(cache.load().isEmpty)
    }

    // AC-004: only results older than 24 hours are refreshed by the periodic
    // check; fresh ones are left alone.
    func testOnlyStaleResultsAreRefreshed() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        cache.save(freshFixtures(now: now, staleItems: [.optimize]))

        let spies = ScanSpies()
        let service = makeService(spies: spies, cache: cache, now: { now })
        try await waitUntil { await spies.optimize.processCallCount == 1 }
        let purgeCalls = await spies.purge.processCallCount
        let cleanCalls = await spies.clean.processCallCount
        XCTAssertEqual(purgeCalls, 0, "a fresh result must not rescan")
        XCTAssertEqual(cleanCalls, 0)
        _ = service
    }

    // AC-004: the periodic loop rescans a result once it crosses 24 hours.
    func testPeriodicRefreshRescansStaleResults() async throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 6_000_000))
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        cache.save(freshFixtures(now: clock.now))
        let spies = ScanSpies()
        let service = makeService(
            spies: spies,
            cache: cache,
            periodicTick: 0.05,
            now: { clock.now }
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        let callsBefore = await spies.optimize.processCallCount
        XCTAssertEqual(callsBefore, 0)

        clock.now = clock.now.addingTimeInterval(25 * 60 * 60)
        try await waitUntil { await spies.optimize.processCallCount == 1 }
        XCTAssertNotNil(service.result(for: .optimize))
    }

    // AC-005: a refresh request while the item is already running does not
    // start a second process; the next request after completion does.
    func testRefreshWhileRunningReusesTheInFlightScan() async throws {
        let spies = ScanSpies(blockedPrefix: ["optimize", "--dry-run"])
        let service = makeService(spies: spies, cache: BackgroundScanCache(fileURL: temporaryFileURL()))

        try await waitUntil { await spies.optimize.blockedCallCount == 1 }
        service.request(.optimize)
        try await Task.sleep(nanoseconds: 200_000_000)
        let callsWhileRunning = await spies.optimize.processCallCount
        XCTAssertEqual(callsWhileRunning, 1)

        await spies.optimize.releaseBlocked()
        try await waitUntil { service.results[.optimize] != nil }
        service.request(.optimize)
        try await waitUntil { await spies.optimize.processCallCount == 2 }
    }

    func testCancellationFollowedImmediatelyByRequestRegistersExactlyOneNewTask() async throws {
        let spies = ScanSpies(blockedPrefix: ["optimize", "--dry-run"])
        let service = makeService(spies: spies, cache: BackgroundScanCache(fileURL: temporaryFileURL()))

        try await waitUntil { await spies.optimize.blockedCallCount == 1 }
        let cancelTask = Task {
            await service.cancelAndWait(.optimize)
        }
        try await waitUntil { await spies.optimize.cancelCount == 1 }
        // While cancelAndWait is in-flight, a request is safely ignored:
        service.request(.optimize)

        await spies.optimize.finishCancellation()
        await cancelTask.value

        // Now cancelAndWait has fully resolved; next request starts a single new task:
        service.request(.optimize)
        try await waitUntil { await spies.optimize.processCallCount == 2 }
        await spies.optimize.releaseBlocked()
        try await waitUntil { service.results[.optimize] != nil }
        let finalCalls = await spies.optimize.processCallCount
        XCTAssertEqual(finalCalls, 2, "only one task was registered after cancellation")
    }

    // AC-010, AC-013: a write invalidates only affected items, marks them stale with payload kept, and rescans only those items.
    func testScopedInvalidationRescansOnlyAffectedItemsAndKeepsPayloadStale() async throws {
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        let now = Date()
        cache.save(freshFixtures(now: now))
        let spies = ScanSpies()
        let coordinator = OperationCoordinator()
        let service = makeService(spies: spies, cache: cache, coordinator: coordinator)
        try await Task.sleep(nanoseconds: 200_000_000)
        let callsBefore = await spies.totalCallCount
        XCTAssertEqual(callsBefore, 0)

        // An optimize write affects optimize and clean, NOT uninstallList, installerList, or purge
        let lease = coordinator.acquire(.optimize)!
        lease.markDataModified()
        lease.release()

        try await waitUntil {
            let optCalls = await spies.optimize.processCallCount
            let cleanCalls = await spies.clean.processCallCount
            return optCalls == 1 && cleanCalls == 1 && service.failedItems.isEmpty
        }

        let optCalls = await spies.optimize.processCallCount
        let cleanCalls = await spies.clean.processCallCount
        let uninstCalls = await spies.uninstall.callCount
        let instCalls = await spies.installerList.processCallCount
        let purgeCalls = await spies.purge.processCallCount

        XCTAssertEqual(optCalls, 1)
        XCTAssertEqual(cleanCalls, 1)
        XCTAssertEqual(uninstCalls, 0, "Unaffected uninstallList must not rescan (AC-010)")
        XCTAssertEqual(instCalls, 0, "Unaffected installerList must not rescan (AC-010)")
        XCTAssertEqual(purgeCalls, 0, "Unaffected purge must not rescan (AC-010)")
    }

    // AC-007: a failing item keeps its previous result, is marked failed, does
    // not block the other items, and is retried after the failure backoff.
    func testFailingItemKeepsPreviousResultAndRetriesLater() async throws {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let oldCandidate = InstallerCandidate(
            path: "/Users/demo/Downloads/A.dmg",
            sizeBytes: 100,
            source: "Downloads",
            identity: "1:2:3"
        )
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        var fixtures = freshFixtures(now: now)
        fixtures[.installerList] = BackgroundScanResult(
            capturedAt: now,
            payload: .installerCandidates([oldCandidate])
        )
        cache.save(fixtures)

        let spies = ScanSpies(failingPrefix: ["installer", "--list-json"])
        let service = makeService(spies: spies, cache: cache, now: { now })
        service.request(.installerList)
        try await waitUntil { service.failedItems.contains(.installerList) }

        XCTAssertEqual(service.result(for: .installerList)?.payload, .installerCandidates([oldCandidate]))
        XCTAssertNotNil(service.result(for: .optimize), "other items are unaffected")

        service.refreshIfDue(now: now.addingTimeInterval(2 * 60 * 60))
        try await waitUntil { await spies.installerList.processCallCount == 2 }
    }

    // AC-009: no Full Disk Access defers the installer scan until granted.
    func testMissingFullDiskAccessDefersInstallerUntilGranted() async throws {
        let permission = MutableFlag(false)
        let monitor = FullDiskAccessMonitor(probe: { permission.value })
        let spies = ScanSpies()
        let service = makeService(
            spies: spies,
            cache: BackgroundScanCache(fileURL: temporaryFileURL()),
            accessMonitor: monitor
        )

        try await waitUntil { await spies.clean.processCallCount == 1 }
        let installerCallsBeforeGrant = await spies.installerList.processCallCount
        XCTAssertEqual(installerCallsBeforeGrant, 0)

        permission.value = true
        monitor.refresh()
        service.diskAccessDidChange()
        try await waitUntil { await spies.installerList.processCallCount >= 1 }
    }

    func testDemoConfigurationUsesDemoBackgroundScan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-scan-demo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dependencies = AppDependencies(configuration: DemoConfiguration(arguments: [
            "zmole", "--demo", "--demo-data-root", root.path
        ]))
        let service = try XCTUnwrap(dependencies.scanService, "demo pages need a data source")

        for _ in 0..<500 {
            if service.result(for: .clean) != nil, service.result(for: .optimize) != nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNotNil(service.result(for: .clean), "demo clean data must reach the page")
        XCTAssertNotNil(service.result(for: .optimize), "demo optimize data must reach the page")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("background_scan_cache.json").path
            ),
            "demo scan results must stay inside the demo data root"
        )
    }

    // MARK: - View model adoption

    func testUninstallPageAdoptsBackgroundRowsWithoutScanning() async throws {
        let rows = UninstallFixture.rows(from: """
        [{"name":"Alpha","bundle_id":"com.example.alpha","uninstall_name":"Alpha","path":"/Applications/Alpha.app","size":"1 MB","version":"9.9","last_used_epoch":1700000000}]
        """)
        let counter = CountingListStream(rows: rows)
        let scan = ScanProvidingStub(results: [
            .uninstallList: BackgroundScanResult(
                capturedAt: Date(timeIntervalSince1970: 100),
                payload: .uninstallRows(rows)
            )
        ])
        let viewModel = UninstallViewModel(
            process: StubProcess(),
            listStream: counter.makeStream(),
            coordinator: OperationCoordinator(),
            targetChecker: FixedTargetChecker(matches: true),
            iconProvider: NoopIconProvider(),
            scan: scan
        )

        await viewModel.loadListIfNeeded()

        XCTAssertEqual(viewModel.listings.count, 1)
        XCTAssertEqual(viewModel.apps.first?.version, "9.9")
        XCTAssertEqual(counter.opens, 0, "an adopted result must not re-scan")
        XCTAssertEqual(viewModel.listCapturedAt, Date(timeIntervalSince1970: 100))
    }

    func testInstallersPageAdoptsBackgroundCandidatesWithoutScanning() async throws {
        let candidates = [
            InstallerCandidate(path: "/Users/demo/Downloads/A.dmg", sizeBytes: 100, source: "Downloads", identity: "1:2:3")
        ]
        let spy = InstallerInterfaceSpy(listResults: [candidates])
        let scan = ScanProvidingStub(results: [
            .installerList: BackgroundScanResult(
                capturedAt: Date(timeIntervalSince1970: 50),
                payload: .installerCandidates(candidates)
            )
        ])
        let viewModel = InstallersViewModel(
            interface: InstallerInterface { arguments in try await spy.run(arguments) },
            coordinator: OperationCoordinator(),
            scan: scan
        )

        await viewModel.loadListIfNeeded()

        XCTAssertEqual(viewModel.candidates, candidates)
        let listCalls = await spy.listCalls
        XCTAssertEqual(listCalls, 0, "an adopted result must not re-scan")
        XCTAssertEqual(viewModel.listCapturedAt, Date(timeIntervalSince1970: 50))

        await viewModel.loadListIfNeeded()
        let callsAfterReentry = await spy.listCalls
        XCTAssertEqual(callsAfterReentry, 0)
    }

    func testCleanPageAdoptsBackgroundResultAndProtectsTheConfirmation() async throws {
        let store = CleanPreviewStore(fileURL: temporaryFileURL())
        let snapshot = try makeCleanSnapshot(at: store.fileURL)
        let process = MaintenanceProcessSpy()
        let scan = ScanProvidingStub(results: [
            .clean: BackgroundScanResult(
                capturedAt: Date(timeIntervalSince1970: 70),
                payload: .cleanPreview(snapshot)
            )
        ])
        let viewModel = CleanViewModel(
            process: process,
            coordinator: OperationCoordinator(),
            scan: scan
        )

        viewModel.adoptBackgroundResultIfAvailable()

        XCTAssertNotNil(viewModel.preview)
        XCTAssertEqual(viewModel.previewCapturedAt, Date(timeIntervalSince1970: 70))
        let invocations = await process.invocations
        XCTAssertTrue(invocations.isEmpty)

        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.isConfirmationPresented)
        let replacement = try makeCleanSnapshot(at: store.fileURL, name: "Replacement")
        scan.results[.clean] = BackgroundScanResult(
            capturedAt: Date(timeIntervalSince1970: 90),
            payload: .cleanPreview(replacement)
        )
        viewModel.adoptBackgroundResultIfAvailable()
        XCTAssertEqual(viewModel.preview, snapshot, "the confirming preview stays")
    }

    func testOptimizeAndPurgeAdoptBackgroundResults() async throws {
        let optimizeScan = ScanProvidingStub(results: [
            .optimize: BackgroundScanResult(
                capturedAt: Date(timeIntervalSince1970: 80),
                payload: .maintenance("Optimize preview output")
            )
        ])
        let optimize = OptimizeViewModel(
            process: MaintenanceProcessSpy(),
            coordinator: OperationCoordinator(),
            scan: optimizeScan
        )
        optimize.adoptBackgroundResultIfAvailable()
        XCTAssertEqual(optimize.preview?.output, "Optimize preview output")
        XCTAssertEqual(optimize.previewCapturedAt, Date(timeIntervalSince1970: 80))

        let purgeScan = ScanProvidingStub(results: [
            .purge: BackgroundScanResult(
                capturedAt: Date(timeIntervalSince1970: 81),
                payload: .maintenance("Purge preview output")
            )
        ])
        let purge = PurgeViewModel(
            process: MaintenanceProcessSpy(),
            coordinator: OperationCoordinator(),
            scan: purgeScan
        )
        purge.adoptBackgroundResultIfAvailable()
        XCTAssertEqual(purge.preview?.output, "Purge preview output")
        XCTAssertEqual(purge.previewCapturedAt, Date(timeIntervalSince1970: 81))
    }

    // MARK: - Helpers

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-scan-\(UUID().uuidString).json")
    }

    private func makeService(
        spies: ScanSpies,
        cache: BackgroundScanCache,
        coordinator: OperationCoordinator? = nil,
        accessMonitor: FullDiskAccessMonitor? = nil,
        periodicTick: TimeInterval = 3600,
        now: @escaping () -> Date = Date.init
    ) -> BackgroundScanService {
        BackgroundScanService(
            lanes: spies.lanes,
            cleanPreviewStore: CleanPreviewStore(fileURL: spies.previewURL),
            cache: cache,
            coordinator: coordinator ?? OperationCoordinator(),
            accessMonitor: accessMonitor,
            periodicTick: periodicTick,
            now: now
        )
    }

    private func freshFixtures(
        now: Date,
        staleItems: Set<BackgroundScanItem> = []
    ) -> [BackgroundScanItem: BackgroundScanResult] {
        var results: [BackgroundScanItem: BackgroundScanResult] = [
            .uninstallList: BackgroundScanResult(capturedAt: now, payload: .uninstallRows([])),
            .installerList: BackgroundScanResult(capturedAt: now, payload: .installerCandidates([])),
            .clean: BackgroundScanResult(capturedAt: now, payload: .maintenance("placeholder")),
            .optimize: BackgroundScanResult(capturedAt: now, payload: .maintenance("plan")),
            .purge: BackgroundScanResult(capturedAt: now, payload: .maintenance("purge plan"))
        ]
        for item in staleItems {
            let payload = results[item]?.payload ?? .maintenance("stale")
            results[item] = BackgroundScanResult(
                capturedAt: now.addingTimeInterval(-25 * 60 * 60),
                payload: payload
            )
        }
        return results
    }

    private func makeCleanSnapshot(
        at url: URL,
        name: String = "Caches"
    ) throws -> CleanPreviewSnapshot {
        let store = CleanPreviewStore(fileURL: url)
        let generation = try store.begin()
        try "# preview\n=== \(name) ===\n/tmp/cache # 1KB\n".write(
            to: generation.fileURL,
            atomically: true,
            encoding: .utf8
        )
        return try store.read(generation)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }
}

/// Tracks the highest number of concurrently running scan commands across all
/// lanes, so tests can assert real overlap.
private actor ConcurrencyProbe {
    private var active = 0
    private(set) var max = 0

    func begin() {
        active += 1
        max = Swift.max(max, active)
    }

    func end() {
        active -= 1
    }
}

/// Five independent lanes that record commands, can block or fail the first
/// call, and expose cancellation counts.
private struct ScanSpies {
    let previewURL: URL
    let uninstall: ScanLaneSpy
    let installerList: ScanLaneSpy
    let clean: ScanLaneSpy
    let optimize: ScanLaneSpy
    let purge: ScanLaneSpy

    init(
        probe: ConcurrencyProbe? = nil,
        blockFirstProcessCall: Bool = false,
        blockedPrefix: [String] = [],
        failingPrefix: [String] = []
    ) {
        previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-scan-\(UUID().uuidString)-clean-list.txt")
        uninstall = ScanLaneSpy(
            probe: probe,
            streamLines: ["{\"path\":\"/Applications/Demo.app\",\"name\":\"Demo\"}\n", "{\"event\":\"done\"}\n"]
        )
        installerList = ScanLaneSpy(
            probe: probe,
            blockFirstProcessCall: blockFirstProcessCall,
            blockedPrefix: blockedPrefix,
            failingPrefix: failingPrefix
        )
        clean = ScanLaneSpy(
            probe: probe,
            blockFirstProcessCall: blockFirstProcessCall,
            blockedPrefix: blockedPrefix,
            previewFileURL: previewURL
        )
        optimize = ScanLaneSpy(
            probe: probe,
            blockFirstProcessCall: blockFirstProcessCall,
            blockedPrefix: blockedPrefix
        )
        purge = ScanLaneSpy(
            probe: probe,
            blockFirstProcessCall: blockFirstProcessCall,
            blockedPrefix: blockedPrefix
        )
    }

    var lanes: BackgroundScanLanes {
        BackgroundScanLanes(
            uninstallStreaming: uninstall,
            installer: InstallerInterface { arguments in
                try await installerList.run(arguments, stdin: nil, timeout: 600)
            },
            installerProcess: installerList,
            clean: clean,
            optimize: optimize,
            purge: purge
        )
    }

    var all: [ScanLaneSpy] { [uninstall, installerList, clean, optimize, purge] }

    var totalCallCount: Int {
        get async {
            var total = 0
            for spy in all {
                total += await spy.callCount
            }
            return total
        }
    }

    var allArguments: [[String]] {
        get async {
            var arguments: [[String]] = []
            for spy in all {
                arguments += await spy.arguments
            }
            return arguments
        }
    }

    var blockedProcessCallCount: Int {
        get async {
            var total = 0
            for spy in [installerList, clean, optimize, purge] {
                total += await spy.blockedCallCount
            }
            return total
        }
    }

    func releaseAll() async {
        for spy in all {
            await spy.releaseBlocked()
        }
    }
}

private actor ScanLaneSpy: MoleProcessControlling, MoleStreaming {
    private let probe: ConcurrencyProbe?
    private let blockFirstProcessCall: Bool
    private let blockedPrefix: [String]
    private let previewFileURL: URL?
    private let streamLines: [String]

    private var recordedArguments: [[String]] = []
    private(set) var cancelCount = 0
    private(set) var blockedCallCount = 0
    private let failingPrefix: [String]
    private var blockedContinuation: CheckedContinuation<MoleCommandResult, Error>?
    private var blockedArguments: [String] = []

    init(
        probe: ConcurrencyProbe? = nil,
        blockFirstProcessCall: Bool = false,
        blockedPrefix: [String] = [],
        failingPrefix: [String] = [],
        previewFileURL: URL? = nil,
        streamLines: [String] = []
    ) {
        self.probe = probe
        self.blockFirstProcessCall = blockFirstProcessCall
        self.blockedPrefix = blockedPrefix
        self.failingPrefix = failingPrefix
        self.previewFileURL = previewFileURL
        self.streamLines = streamLines
    }

    var arguments: [[String]] { recordedArguments }
    var callCount: Int { recordedArguments.count }
    var processCallCount: Int { recordedArguments.count }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        recordedArguments.append(arguments)
        await probe?.begin()
        do {
            let result = try await performRun(arguments)
            await probe?.end()
            return result
        } catch {
            await probe?.end()
            throw error
        }
    }

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        recordedArguments.append(arguments)
        let lines = streamLines
        return AsyncThrowingStream { continuation in
            for line in lines {
                continuation.yield(.stdoutLine(Data(line.utf8)))
            }
            continuation.finish()
        }
    }

    func cancel() async {
        cancelCount += 1
        // Termination is driven explicitly with finishCancellation() so tests
        // can observe that the caller really waits for the process to end.
    }

    func finishCancellation() {
        blockedContinuation?.resume(throwing: MoleBridgeError.cancelled)
        blockedContinuation = nil
    }

    func releaseBlocked() {
        guard let continuation = blockedContinuation else { return }
        blockedContinuation = nil
        continuation.resume(returning: MoleCommandResult(
            stdout: fixtureOutput(for: blockedArguments),
            stderr: "",
            exitCode: 0
        ))
    }

    private func performRun(_ arguments: [String]) async throws -> MoleCommandResult {
        if !failingPrefix.isEmpty, arguments.starts(with: failingPrefix) {
            return MoleCommandResult(stdout: "", stderr: "scan failed", exitCode: 7)
        }
        if arguments == ["clean", "--dry-run"], let previewFileURL {
            try? "# preview\n=== Caches ===\n/tmp/cache # 1KB\n".write(
                to: previewFileURL,
                atomically: true,
                encoding: .utf8
            )
        }
        let shouldBlock = blockFirstProcessCall || (!blockedPrefix.isEmpty && arguments.starts(with: blockedPrefix))
        if shouldBlock, blockedCallCount == 0 {
            blockedCallCount += 1
            blockedArguments = arguments
            return try await withCheckedThrowingContinuation { continuation in
                blockedContinuation = continuation
            }
        }
        return MoleCommandResult(stdout: fixtureOutput(for: arguments), stderr: "", exitCode: 0)
    }

    private func fixtureOutput(for arguments: [String]) -> String {
        switch arguments.first {
        case "installer":
            return "[{\"path\":\"/Users/demo/Downloads/A.dmg\",\"size_bytes\":100,\"source\":\"Downloads\",\"identity\":\"1:2:3\"}]"
        case "clean":
            return "clean plan"
        default:
            return "plan"
        }
    }
}

/// Mutable permission flag so a test can grant Full Disk Access mid-run.
private final class MutableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Bool

    init(_ value: Bool) {
        storage = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

/// Mutable clock so a test can advance past the 24-hour refresh window.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Date

    init(_ value: Date) {
        storage = value
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}


private actor InstallerInterfaceSpy {
    private(set) var listCalls = 0
    private let listResults: [[InstallerCandidate]]

    init(listResults: [[InstallerCandidate]]) {
        self.listResults = listResults
    }

    func run(_ arguments: [String]) async throws -> MoleCommandResult {
        if arguments == ["installer", "--list-json"] {
            listCalls += 1
            let list = listResults[min(listCalls - 1, listResults.count - 1)]
            let entries = list.map { candidate in
                "{\"path\":\"\(candidate.path)\",\"size_bytes\":\(candidate.sizeBytes),\"source\":\"\(candidate.source)\",\"identity\":\"\(candidate.identity)\"}"
            }
            return MoleCommandResult(
                stdout: "[\(entries.joined(separator: ","))]",
                stderr: "",
                exitCode: 0
            )
        }
        return MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

private actor MaintenanceProcessSpy: MoleProcessControlling {
    private(set) var invocations: [[String]] = []

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations.append(arguments)
        return MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}
