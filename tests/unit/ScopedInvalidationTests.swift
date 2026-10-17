import Combine
import XCTest
@testable import Zmole

@MainActor
final class ScopedInvalidationTests: XCTestCase {
    private var cancellables: [AnyCancellable] = []

    func testScopedInvalidationMatrixMatchesContract() {
        // AC-010, AC-018
        let cleanImpact = DataImpact.forOperation(.clean)
        XCTAssertEqual(cleanImpact.scanItems, Set(BackgroundScanItem.allCases))
        XCTAssertEqual(cleanImpact.overviewInputs, Set(OverviewDirectoryInput.allCases))

        let uninstallImpact = DataImpact.forOperation(.uninstall)
        XCTAssertEqual(uninstallImpact.scanItems, Set(BackgroundScanItem.allCases))
        XCTAssertEqual(uninstallImpact.overviewInputs, Set(OverviewDirectoryInput.allCases))

        let optimizeImpact = DataImpact.forOperation(.optimize)
        XCTAssertEqual(optimizeImpact.scanItems, [.optimize, .clean])
        XCTAssertEqual(optimizeImpact.overviewInputs, [.userData, .system])

        let purgeImpact = DataImpact.forOperation(.purge)
        XCTAssertEqual(purgeImpact.scanItems, [.purge, .clean])
        XCTAssertEqual(purgeImpact.overviewInputs, [.developer, .userData])

        let installerImpact = DataImpact.forOperation(.installer)
        XCTAssertEqual(installerImpact.scanItems, [.installerList, .clean])
        XCTAssertEqual(installerImpact.overviewInputs, [.userData])

        let cleanWhitelistImpact = DataImpact.forOperation(.cleanWhitelist)
        XCTAssertEqual(cleanWhitelistImpact.scanItems, [.clean])
        XCTAssertTrue(cleanWhitelistImpact.overviewInputs.isEmpty)

        let optimizeWhitelistImpact = DataImpact.forOperation(.optimizeWhitelist)
        XCTAssertEqual(optimizeWhitelistImpact.scanItems, [.optimize])
        XCTAssertTrue(optimizeWhitelistImpact.overviewInputs.isEmpty)

        let purgePathsImpact = DataImpact.forOperation(.purgePaths)
        XCTAssertEqual(purgePathsImpact.scanItems, [.purge, .clean])
        XCTAssertTrue(purgePathsImpact.overviewInputs.isEmpty)
    }

    func testFailedConfigSaveReleasesLeaseWithoutInvalidatingBackgroundData() {
        // AC-007
        let coordinator = OperationCoordinator()
        var settledCount = 0
        coordinator.settledOperations.sink { _ in settledCount += 1 }.store(in: &cancellables)

        let genBefore = coordinator.invalidationGeneration
        let lease = coordinator.acquire(.purgePaths)!
        // Simulate failed save with no file modification
        lease.release()
        coordinator.invalidatePreviews()

        XCTAssertNil(coordinator.activeOperation, "Lease must be released")
        XCTAssertNotEqual(coordinator.invalidationGeneration, genBefore, "Confirmation generation must bump")
        XCTAssertEqual(settledCount, 0, "Failed save without modification must not emit settled operation (AC-007)")
    }

    func testSuccessfulWriteSettlesImpactOnceAndBumpsVersions() {
        // AC-011, AC-012
        let coordinator = OperationCoordinator()
        var settledImpacts: [DataImpact] = []
        coordinator.settledOperations.sink { _, impact in settledImpacts.append(impact) }.store(in: &cancellables)

        let lease = coordinator.acquire(.purge)!
        XCTAssertEqual(coordinator.version(for: .purge), 0)
        XCTAssertEqual(coordinator.version(for: .clean), 0)
        XCTAssertEqual(coordinator.version(for: .optimize), 0)

        lease.markDataModified()
        lease.release()

        XCTAssertEqual(settledImpacts.count, 1, "Must settle exactly once on release (AC-011)")
        XCTAssertEqual(coordinator.version(for: .purge), 1)
        XCTAssertEqual(coordinator.version(for: .clean), 1)
        XCTAssertEqual(coordinator.version(for: .optimize), 0, "Unaffected item version must not bump (AC-010)")
    }

    func testBackgroundScanResultStalenessAndVersionTracking() {
        // AC-013, AC-014
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = BackgroundScanResult(
            capturedAt: now,
            payload: .maintenance("ok"),
            targetVersion: 1,
            capturedVersion: 1,
            isStale: false
        )
        XCTAssertFalse(fresh.isStale)

        let stale = fresh.markingStale(targetVersion: 2)
        XCTAssertTrue(stale.isStale, "Must be marked stale (AC-013)")
        XCTAssertEqual(stale.capturedAt, now, "Old capturedAt must be preserved (AC-013)")
        XCTAssertEqual(stale.targetVersion, 2)
        XCTAssertEqual(stale.capturedVersion, 1)

        // Older scan cannot clear stale state (AC-014)
        let oldScanArrived = BackgroundScanResult(
            capturedAt: now.addingTimeInterval(5),
            payload: .maintenance("old"),
            targetVersion: stale.targetVersion,
            capturedVersion: 1,
            isStale: false
        )
        XCTAssertTrue(oldScanArrived.isStale, "Old capturedVersion < targetVersion must stay stale (AC-014)")

        // Fresh scan matching target version clears stale state
        let freshScan = BackgroundScanResult(
            capturedAt: now.addingTimeInterval(10),
            payload: .maintenance("fresh"),
            targetVersion: stale.targetVersion,
            capturedVersion: 2,
            isStale: false
        )
        XCTAssertFalse(freshScan.isStale, "Matching version clears stale state (AC-013)")
    }

    func testCacheSchemaVersion2PersistsAndDiscardsOlderSchema() throws {
        // AC-016
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("cache.json")

        // Write schema 1 content
        let schema1JSON = """
        {"schemaVersion":1,"entries":{}}
        """
        try schema1JSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let cache = BackgroundScanCache(fileURL: fileURL)
        let loaded = cache.load()
        XCTAssertTrue(loaded.isEmpty, "Schema 1 cache must be discarded (AC-016)")

        // Save schema 2
        let result = BackgroundScanResult(
            capturedAt: Date(),
            payload: .maintenance("output"),
            targetVersion: 2,
            capturedVersion: 1,
            isStale: true
        )
        cache.save([.optimize: result])

        let loaded2 = cache.load()
        let opt = try XCTUnwrap(loaded2[.optimize])
        XCTAssertEqual(opt.targetVersion, 2)
        XCTAssertEqual(opt.capturedVersion, 1)
        XCTAssertTrue(opt.isStale, "Stale state must persist across reload (AC-016)")
    }
}
