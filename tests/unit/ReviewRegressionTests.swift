import Combine
import XCTest
@testable import Zmole

@MainActor
final class ReviewRegressionTests: XCTestCase {
    func testStoreClearRemovesEntriesAndInodesWithoutTreatingPathAsPattern() throws {
        let store = try DiskSessionStore()
        defer { store.close() }
        let key = HardLinkKey(device: 1, inode: 1)
        for path in ["/root/a_b", "/root/axb"] {
            try store.saveLevel(
                summary: summary(path, total: 10),
                entries: [DiskEntry(name: "f", path: path + "/f", isDirectory: false, value: .size(10))],
                inodes: [key: 10]
            )
        }
        store.clearSubtree(path: "/root/a_b")
        XCTAssertEqual(store.countEntries(parentPath: "/root/a_b"), 0)
        XCTAssertTrue(store.loadInodes(for: "/root/a_b").isEmpty)
        XCTAssertNotNil(store.loadSummary(for: "/root/axb"))
    }

    func testStoreReplacingLevelRemovesDeletedEntries() throws {
        let store = try DiskSessionStore()
        defer { store.close() }
        try store.saveLevel(summary: summary("/r", total: 10), entries: [
            DiskEntry(name: "old", path: "/r/old", isDirectory: false, value: .size(10))
        ], inodes: [:])
        try store.saveLevel(summary: summary("/r", total: 0), entries: [], inodes: [:])
        XCTAssertEqual(store.countEntries(parentPath: "/r"), 0)
    }

    func testSingleWideDirectoryRespectsResidentBudget() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/r"] = (0..<20).map {
            DiskEntry(name: "f\($0)", path: "/r/f\($0)", isDirectory: false, value: .size(1))
        }
        let session = DiskMeasurementSession(scanner: scanner, root: "/r", config: .init(maxResidentEntries: 3))
        defer { session.close() }
        _ = try await session.listDirectory("/r")
        XCTAssertLessThanOrEqual(session.residentEntriesCount, 3)
        XCTAssertEqual(session.store.countEntries(parentPath: "/r"), 20)
    }

    func testLateListingCannotRepopulateCancelledGeneration() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/r"] = [DiskEntry(name: "old", path: "/r/old", isDirectory: false, value: .size(1))]
        scanner.blockedListings.insert("/r")
        let session = DiskMeasurementSession(scanner: scanner, root: "/r")
        let listing = Task { try? await session.listDirectory("/r") }
        try await waitUntil { !scanner.listRequests.isEmpty }
        session.reanalyze(path: "/r")
        scanner.releaseListings()
        _ = await listing.value
        XCTAssertNil(session.levelRecord(for: "/r"))
        session.close()
    }

    func testCancelledWaiterNeverStartsDiskWalkWithoutPermit() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let occupied = try await scheduler.acquire(taskID: "occupied")
        let scanner = FakeDiskScanner()
        let session = DiskMeasurementSession(scanner: scanner, root: "/r", scheduler: scheduler)
        let subscription = session.subscribe(path: "/r")
        try await waitUntil { await scheduler.waitingCount == 1 }
        session.cancel()
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(scanner.measureRequests.isEmpty)
        subscription.cancel()
        await occupied.release()
        session.close()
    }

    func testListingPartialTotalIsNotCompletedSubtreeOutcome() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/r"] = [DiskEntry(name: "child", path: "/r/child", isDirectory: true, value: .computing)]
        scanner.results["/r/child"] = DiskScanResult(path: "/r/child", totalSize: 25, isReadable: true, levels: [:])
        scanner.blockedMeasures.insert("/r/child")
        let session = DiskMeasurementSession(scanner: scanner, root: "/r")
        _ = try await session.listDirectory("/r")
        let outcome = Task { await session.measureSubtreeOutcome("/r") }
        try await Task.sleep(nanoseconds: 30_000_000)
        scanner.releaseMeasures()
        let result = await outcome.value
        XCTAssertEqual(result.size, 25)
        session.close()
    }

    func testUnreadableDeveloperIsUnknownRatherThanZero() async throws {
        let scanner = FakeDiskScanner()
        let dev = "/Users/test/Library/Developer"
        scanner.results["/Users"] = DiskScanResult(path: "/Users", totalSize: 10, isReadable: true, levels: [
            "/Users": DiskLevel(entries: [DiskEntry(name: "Developer", path: dev, isDirectory: true, value: .unreadable)], totalSize: 10)
        ])
        let session = DiskMeasurementSession(scanner: scanner)
        let loader = StorageEstimateLoader(session: session, home: "/Users/test", systemChildren: { [] })
        let sums = try await loader.loadSums()
        XCTAssertNil(sums.developer)
        session.close()
    }

    func testInjectedEstimatePathsProduceSegments() async throws {
        let loader = StorageEstimateLoader(
            channels: [{ _ in 10 }], applicationsPath: "/fixture/apps", usersPath: "/fixture/users",
            systemChildren: { [] }, home: "/fixture/home"
        )
        let sums = try await loader.loadSums()
        XCTAssertEqual(sums.applications, 10)
        XCTAssertEqual(sums.users, 10)
    }

    func testPersistedStaleResultIsRefreshedOnLaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = BackgroundScanCache(fileURL: url)
        cache.save([.optimize: BackgroundScanResult(capturedAt: Date(), payload: .maintenance("old"), targetVersion: 1, isStale: true)])
        let process = MaintenanceExecutionSpy()
        let lanes = BackgroundScanLanes(uninstallStreaming: UnavailableMoleStreaming(), installer: InstallerInterface(process: process), installerProcess: process, clean: process, optimize: process, purge: process)
        let service = BackgroundScanService(
            lanes: lanes, cleanPreviewStore: .live,
            cache: cache, coordinator: OperationCoordinator(), periodicTick: 1000
        )
        await service.waitForHydration()
        await service.waitForScan(.optimize)
        let calls = await process.invocations.filter { $0.arguments == ["optimize", "--dry-run"] }
        XCTAssertEqual(calls.count, 1)
        _ = await service.close()
    }

    func testNavigationPublishesPolicyChangeWithoutDestinationChange() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let policy = StatusFeaturePolicy(userDefaults: defaults)
        let navigation = NavigationModel(policy: policy)
        var changes = 0
        let cancellable = navigation.objectWillChange.sink { changes += 1 }
        policy.setEnabled(false)
        XCTAssertGreaterThan(changes, 0)
        XCTAssertFalse(navigation.paletteItems.contains { $0.destination == .status })
        withExtendedLifetime(cancellable) {}
    }

    func testProductionDiskAssemblyUsesSharedSchedulerAndNativeScanner() {
        let dependencies = AppDependencies(backgroundScanEnabled: false)
        XCTAssertTrue(dependencies.analyzeViewModel.session.scanner is LiveDiskScanner)
        XCTAssertTrue(dependencies.analyzeViewModel.session.scheduler === dependencies.heavyScanScheduler)
        dependencies.analyzeViewModel.session.close()
    }

    func testFreshEstimateAfterInvalidationDoesNotReuseOldSessionFacts() async throws {
        let scanner = FakeDiskScanner()
        scanner.results["/Applications"] = DiskScanResult(path: "/Applications", totalSize: 10, isReadable: true, levels: [:])
        let session = DiskMeasurementSession(scanner: scanner)
        let loader = StorageEstimateLoader(session: session, systemChildren: { [] })
        let first = try await loader.loadSums(includingUsers: false)
        XCTAssertEqual(first.applications, 10)
        scanner.results["/Applications"] = DiskScanResult(path: "/Applications", totalSize: 20, isReadable: true, levels: [:])
        let fresh = try await loader.loadSums(includingUsers: false, refresh: true)
        XCTAssertEqual(fresh.applications, 20)
        session.close()
    }

    func testIndependentMountedSubtreeNeverContributesToParent() async throws {
        let scanner = FakeDiskScanner()
        scanner.listings["/r"] = [DiskEntry(name: "mount", path: "/r/mount", isDirectory: true, value: .otherDevice)]
        scanner.results["/r/mount"] = DiskScanResult(path: "/r/mount", totalSize: 40, isReadable: true, levels: [:])
        let session = DiskMeasurementSession(scanner: scanner, root: "/r")
        _ = try await session.listDirectory("/r")
        let mounted = await session.measureSubtreeOutcome("/r/mount")
        XCTAssertEqual(mounted.size, 40)
        XCTAssertEqual(session.levelRecord(for: "/r")?.totalSize, 0)
        XCTAssertEqual(session.levelRecord(for: "/r")?.entries.first?.value, .otherDevice)
        session.close()
    }

    func testLiveWideDirectoryUsesPagedProductionScanner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<21 { try Data(count: 1024).write(to: root.appendingPathComponent("file_\(index)")) }
        let session = DiskMeasurementSession(scanner: LiveDiskScanner(), root: root.path, config: .init(maxResidentEntries: 3, batchLimit: 2))
        let outcome = await session.measureSubtreeOutcome(root.path)
        XCTAssertTrue(outcome.isReadable)
        XCTAssertEqual(session.store.countEntries(parentPath: root.path), 21)
        XCTAssertLessThanOrEqual(session.levelRecord(for: root.path)?.entries.count ?? 100, 3)
        let vm = AnalyzeViewModel(scanner: LiveDiskScanner(), root: root.path, session: session)
        await vm.loadOverview()
        var paths: Set<String> = []
        repeat {
            paths.formUnion(vm.visibleRows(search: "", sort: .name).map { $0.entry.path })
            if !vm.hasNextPage(search: "") { break }
            vm.changePage(by: 1)
        } while true
        XCTAssertEqual(paths.count, 21)
        vm.resetPage()
        XCTAssertEqual(vm.visibleRows(search: "file_20", sort: .name).count, 1)
        session.close()
    }

    func testReplacingInstallerIdentityRevokesExistingConfirmation() async throws {
        let old = InstallerCandidate(path: "/tmp/app.dmg", sizeBytes: 10, source: "Downloads", identity: "old")
        let scan = ScanProvidingStub(results: [.installerList: BackgroundScanResult(capturedAt: Date(), payload: .installerCandidates([old]))])
        let vm = InstallersViewModel(interface: InstallerInterface(process: MaintenanceExecutionSpy()), coordinator: OperationCoordinator(), scan: scan)
        await vm.loadListIfNeeded()
        vm.toggleSelection(old)
        vm.requestConfirmation()
        XCTAssertTrue(vm.isConfirmationPresented)
        let new = InstallerCandidate(path: old.path, sizeBytes: 20, source: old.source, identity: "new")
        scan.results[.installerList] = BackgroundScanResult(capturedAt: Date().addingTimeInterval(1), payload: .installerCandidates([new]))
        try await waitUntil { vm.candidates == [new] }
        XCTAssertFalse(vm.isConfirmationPresented)
        XCTAssertFalse(vm.canConfirm)
        XCTAssertTrue(vm.selectedPaths.isEmpty)
    }

    func testFailedFirstUninstallScanCannotExecuteProgressiveRows() async throws {
        let row = UninstallAppListing(path: "/Applications/Test.app", name: "Test", bundleID: "test", uninstallName: "Test")
        let scan = ScanProvidingStub()
        scan.runningItems = [.uninstallList]
        scan.inProgressRows = [row]
        let vm = UninstallViewModel(process: MaintenanceExecutionSpy(), coordinator: OperationCoordinator(), scan: scan)
        await vm.loadListIfNeeded()
        scan.runningItems = []
        scan.failedItems = [.uninstallList]
        try await waitUntil { !vm.isListing }
        vm.toggleSelection(path: row.path)
        XCTAssertFalse(vm.canUninstall)
        vm.requestConfirmation()
        XCTAssertFalse(vm.isConfirmationPresented)
    }

    func testCancelledMaintenanceStillInvalidatesPossiblyModifiedData() async throws {
        let coordinator = OperationCoordinator()
        let spy = MaintenanceExecutionSpy()
        await spy.setExecutionBlocked(true)
        let scan = ScanProvidingStub.maintenance(.purge, output: "candidate")
        let vm = MaintenanceViewModel(kind: .purge, process: spy, coordinator: coordinator, scan: scan)
        vm.requestConfirmation()
        let execution = Task { await vm.confirmMaintenance() }
        try await spy.waitForInvocationCount(1)
        await vm.cancelExecution()
        await execution.value
        XCTAssertEqual(coordinator.version(for: .purge), 1)
        XCTAssertEqual(coordinator.version(for: .clean), 1)
        XCTAssertNil(coordinator.activeOperation)
    }

    func testCancelledUninstallRefreshRestoresStableRows() async throws {
        let old = UninstallAppListing(path: "/Applications/Old.app", name: "Old", bundleID: "old", uninstallName: "Old")
        let new = UninstallAppListing(path: "/Applications/New.app", name: "New", bundleID: "new", uninstallName: "New")
        let scan = ScanProvidingStub(results: [.uninstallList: BackgroundScanResult(capturedAt: Date(), payload: .uninstallRows([old]))])
        let vm = UninstallViewModel(process: MaintenanceExecutionSpy(), coordinator: OperationCoordinator(), scan: scan)
        await vm.loadListIfNeeded()
        scan.inProgressRows = [new]
        scan.runningItems = [.uninstallList]
        try await waitUntil { vm.listings == [new] }
        scan.runningItems = []
        try await waitUntil { !vm.isListing }
        XCTAssertEqual(vm.listings, [old])
        vm.toggleSelection(path: new.path)
        XCTAssertFalse(vm.canUninstall)
    }

    func testQuotaFailureDuringPromotionPreservesPreviousSnapshot() throws {
        let store = try DiskSessionStore(maxStorageBytes: 150_000)
        let staging = try DiskSessionStore()
        defer { staging.close(); store.close() }
        let old = DiskEntry(name: "old", path: "/r/old", isDirectory: false, value: .size(10))
        try store.saveLevel(summary: summary("/r", total: 10), entries: [old], inodes: [:])
        let entries = (0..<1000).map { index in
            DiskEntry(name: String(repeating: "a", count: 200) + String(index), path: "/r/\(index)", isDirectory: false, value: .size(1))
        }
        try staging.saveLevel(summary: summary("/r", total: 1000), entries: entries, inodes: [:])
        XCTAssertThrowsError(try store.promote(staging, path: "/r"))
        XCTAssertEqual(try store.loadEntries(parentPath: "/r"), [old])
        XCTAssertEqual(store.loadSummary(for: "/r")?.totalSize, 10)
    }

    func testCacheDeletionDuringHydrationIsAuthoritative() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        BackgroundScanCache(fileURL: url).save([.clean: BackgroundScanResult(capturedAt: Date(), payload: .maintenance("obsolete"))])
        let gate = AsyncGate()
        let storage = BackgroundScanStorage(fileURL: url, onBeforeLoadRead: { await gate.wait() })
        let load = Task { await storage.load() }
        await storage.submit(results: [:], revision: 1, isPriority: false)
        await gate.open()
        let loaded = await load.value
        XCTAssertTrue(loaded.isEmpty)
        _ = await storage.close()
    }

    func testDebouncedPersistenceUpdatesServiceWatermark() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = MaintenanceExecutionSpy()
        let lanes = BackgroundScanLanes(uninstallStreaming: UnavailableMoleStreaming(), installer: InstallerInterface(process: process), installerProcess: process, clean: process, optimize: process, purge: process)
        let service = BackgroundScanService(lanes: lanes, cleanPreviewStore: .live, cache: BackgroundScanCache(fileURL: url), coordinator: OperationCoordinator(), periodicTick: 1000)
        await service.waitForHydration()
        await service.waitForScan(.optimize)
        let revision = service.memoryRevision
        XCTAssertGreaterThan(revision, 0)
        try await waitUntil { service.persistedRevision >= revision }
        _ = await service.close()
    }

    func testCancellationKeepsScanAndPermitActiveUntilActualWalkerExits() async throws {
        let scanner = FakeDiskScanner()
        scanner.blockedMeasures.insert("/r")
        scanner.results["/r"] = DiskScanResult(path: "/r", totalSize: 99, isReadable: true, levels: [:])
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let session = DiskMeasurementSession(scanner: scanner, root: "/r", scheduler: scheduler)
        let subscription = session.subscribe(path: "/r")
        try await waitUntil { !scanner.measureRequests.isEmpty }
        session.cancel()
        XCTAssertTrue(session.isScanning)
        let occupied = await scheduler.activeCount
        XCTAssertEqual(occupied, 1)
        scanner.releaseMeasures()
        try await waitUntil { !session.isScanning }
        let released = await scheduler.activeCount
        XCTAssertEqual(released, 0)
        XCTAssertNil(session.levelRecord(for: "/r"))
        subscription.cancel()
        session.close()
    }

    private func summary(_ path: String, total: Int64) -> DiskLevelSummary {
        .init(path: path, totalSize: total, selfDeduplicatedSize: total, isReadable: true, directFilesCount: 1, directDirectoriesCount: 0)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out")
    }
}
