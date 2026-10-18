import XCTest
@testable import Zmole

@MainActor
final class OverviewStreamingEstimateTests: XCTestCase {
    func testLedgerAttributesSharedHardLinkToDeveloperInEitherOrder() {
        let key = HardLinkKey(device: 1, inode: 9)
        var documentsFirst = SubtreeLedger(developerRequested: true)
        documentsFirst.addFile(bytes: 50, link: nil, underDeveloper: false)
        documentsFirst.addFile(bytes: 10, link: key, underDeveloper: false)
        documentsFirst.addFile(bytes: 10, link: key, underDeveloper: true)

        var developerFirst = SubtreeLedger(developerRequested: true)
        developerFirst.addFile(bytes: 10, link: key, underDeveloper: true)
        developerFirst.addFile(bytes: 50, link: nil, underDeveloper: false)
        developerFirst.addFile(bytes: 10, link: key, underDeveloper: false)

        XCTAssertEqual(documentsFirst.totalSize, 60)
        XCTAssertEqual(documentsFirst.developerSize, 10)
        XCTAssertEqual(documentsFirst, developerFirst)
    }

    func testLiveWalkDedupesHardLinksAndDoesNotOpenTheSessionStore() async throws {
        let fixture = try makeTree()
        defer {
            if fixture.lockedChild { chmod(fixture.locked.path, 0o755) }
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let session = DiskMeasurementSession(
            scanner: LiveDiskScanner(),
            root: fixture.root.path,
            config: .init(maxStorageBytes: 1),
            scheduler: HeavyScanScheduler(maxConcurrency: 2)
        )
        defer { session.close() }
        let storeURL = session.store.fileURL
        let sizeBefore = byteCount(storeURL)
        let loader = StorageEstimateLoader(
            session: session,
            home: fixture.home.path,
            applicationsPath: fixture.applications.path,
            usersPath: fixture.users.path,
            systemChildren: { [] },
            scheduler: session.scheduler,
            measurer: LiveDiskScanner()
        )

        let sums = try await loader.loadSums(includingUsers: true)

        XCTAssertEqual(byteCount(storeURL), sizeBefore, "overview must not write the disk-page session store")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path + "-journal"))
        XCTAssertEqual(sums.applications, allocated(fixture.appFile))
        XCTAssertEqual(sums.users, fixture.expectedUsers)
        XCTAssertEqual(sums.developer, fixture.expectedDeveloper)
        XCTAssertLessThan(allocated(fixture.symlink), allocated(fixture.plain), "a symlink counts its own blocks")
    }

    func testMissingDeveloperPublishesZeroAndUnreadableDeveloperDropsUsers() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let users = root.appendingPathComponent("Users")
        let home = users.appendingPathComponent("me")
        let plain = home.appendingPathComponent("plain.txt")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 2048).write(to: plain)
        let session = DiskMeasurementSession(
            scanner: LiveDiskScanner(),
            root: root.path,
            config: .init(maxStorageBytes: 1)
        )
        defer { session.close() }
        let loader = StorageEstimateLoader(
            session: session,
            home: home.path,
            applicationsPath: root.appendingPathComponent("Applications").path,
            usersPath: users.path,
            systemChildren: { [] },
            measurer: LiveDiskScanner()
        )

        let missing = try await loader.loadSums(includingUsers: true)
        XCTAssertEqual(missing.developer, 0)
        XCTAssertEqual(missing.users, allocated(plain))

        let developer = home.appendingPathComponent("Library/Developer")
        try FileManager.default.createDirectory(at: developer, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(to: developer.appendingPathComponent("tool.bin"))
        XCTAssertEqual(chmod(developer.path, 0), 0)
        defer { chmod(developer.path, 0o755) }
        if let handle = opendir(developer.path) {
            closedir(handle)
            throw XCTSkip("this account can still list a mode-000 directory")
        }

        let unreadable = try await loader.loadSums(includingUsers: true, refresh: true)
        XCTAssertNil(unreadable.developer)
        XCTAssertNil(unreadable.users)
    }

    func testAccumulatorLoaderSkipsVolumesAndDoesNotMeasureDeveloperTwice() async throws {
        let home = "/Users/test"
        let developer = home + "/Library/Developer"
        let measurer = ScriptedMeasurer()
        let session = DiskMeasurementSession(scanner: FakeDiskScanner(), root: "/")
        defer { session.close() }
        let loader = StorageEstimateLoader(
            session: session,
            home: home,
            systemChildren: { ["Library", "Volumes"] },
            measurer: measurer
        )

        let sums = try await loader.loadSums(includingUsers: true)

        XCTAssertEqual(sums.users, 100)
        XCTAssertEqual(sums.developer, 30)
        XCTAssertEqual(sums.applications, 25)
        XCTAssertEqual(sums.system, 25)
        let paths = measurer.paths()
        XCTAssertTrue(paths.contains("/Users"))
        XCTAssertTrue(paths.contains("/Applications"))
        XCTAssertTrue(paths.contains("/System/Library"))
        XCTAssertFalse(paths.contains(developer))
        XCTAssertFalse(paths.contains("/System/Volumes"))
        XCTAssertEqual(measurer.developerPrefix(for: "/Users"), developer)
    }

    func testNoFullDiskAccessMeasuresDeveloperWithoutUsers() async throws {
        let home = "/Users/test"
        let developer = home + "/Library/Developer"
        let measurer = ScriptedMeasurer()
        let session = DiskMeasurementSession(scanner: FakeDiskScanner(), root: "/")
        defer { session.close() }
        let loader = StorageEstimateLoader(
            session: session,
            home: home,
            systemChildren: { [] },
            measurer: measurer
        )

        let sums = try await loader.loadSums(includingUsers: false)

        XCTAssertNil(sums.users)
        XCTAssertEqual(sums.developer, 25)
        XCTAssertFalse(measurer.paths().contains("/Users"))
        XCTAssertTrue(measurer.paths().contains(developer))
    }

    func testFreshSessionSummaryIsReusedUntilRefresh() async throws {
        let scanner = FakeDiskScanner()
        let developer = "/Users/test/Library/Developer"
        scanner.results["/Applications"] = DiskScanResult(path: "/Applications", totalSize: 10, isReadable: true, levels: [:])
        scanner.results[developer] = DiskScanResult(path: developer, totalSize: 4, isReadable: true, levels: [:])
        let session = DiskMeasurementSession(scanner: scanner, root: "/")
        defer { session.close() }
        let seeded = StorageEstimateLoader(
            session: session,
            home: "/Users/test",
            systemChildren: { [] }
        )
        let first = try await seeded.loadSums(includingUsers: false)
        XCTAssertEqual(first.applications, 10)
        XCTAssertEqual(first.developer, 4)

        let measurer = ScriptedMeasurer(plain: 99)
        let live = StorageEstimateLoader(
            session: session,
            home: "/Users/test",
            systemChildren: { [] },
            measurer: measurer
        )
        let reused = try await live.loadSums(includingUsers: false)
        XCTAssertEqual(reused.applications, 10)
        XCTAssertEqual(reused.developer, 4)
        XCTAssertTrue(measurer.paths().isEmpty)

        let refreshed = try await live.loadSums(includingUsers: false, refresh: true)
        XCTAssertEqual(refreshed.applications, 99)
        XCTAssertEqual(refreshed.developer, 99)
        XCTAssertEqual(Set(measurer.paths()), ["/Applications", developer])
    }

    func testTotalFailureKeepsTheCachedEstimateAndDoesNotRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StorageEstimateCache(fileURL: directory.appendingPathComponent("storage_estimate.json"))
        let now = Date(timeIntervalSince1970: 5_000_000)
        let captured = now.addingTimeInterval(-(StorageEstimateCache.timeToLive + 60))
        let previous = StorageSums(applications: 40, system: 25, developer: 30, users: 90)
        cache.save(previous, capturedAt: captured)
        let recorder = PathRecorder()
        let loader = StorageEstimateLoader(
            directorySize: { path in
                await recorder.record(path)
                return nil
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

        viewModel.primeEstimate(usedBytes: 300)
        viewModel.startEstimate(usedBytes: 300)
        await viewModel.waitForEstimate()

        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 40)
        XCTAssertEqual(viewModel.breakdown.systemBytes, 25)
        let saved = try XCTUnwrap(cache.load(now: now))
        XCTAssertEqual(saved.sums, previous)
        XCTAssertEqual(saved.capturedAt, captured)
        let paths = await recorder.paths
        XCTAssertEqual(paths.filter { $0 == "/Applications" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/System/Library" }.count, 1)
    }
}

private struct LiveFixture {
    let root: URL
    let applications: URL
    let users: URL
    let home: URL
    let appFile: URL
    let plain: URL
    let symlink: URL
    let locked: URL
    let expectedUsers: Int64
    let expectedDeveloper: Int64
    let lockedChild: Bool
}

@MainActor
private func makeTree() throws -> LiveFixture {
    let root = temporaryRoot()
    let applications = root.appendingPathComponent("Applications")
    let users = root.appendingPathComponent("Users")
    let home = users.appendingPathComponent("me")
    let documents = home.appendingPathComponent("Documents")
    let developer = home.appendingPathComponent("Library/Developer")
    let locked = home.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: developer, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)

    let appFile = applications.appendingPathComponent("App.bin")
    let plain = documents.appendingPathComponent("plain.txt")
    let shared = documents.appendingPathComponent("shared.bin")
    let note = developer.appendingPathComponent("note.txt")
    let sharedLink = developer.appendingPathComponent("shared.bin")
    let secret = locked.appendingPathComponent("secret.txt")
    let symlink = home.appendingPathComponent("plain-link")
    try Data(repeating: 1, count: 128).write(to: appFile)
    try Data(repeating: 2, count: 256 * 1024).write(to: plain)
    try Data(repeating: 3, count: 4096).write(to: shared)
    try Data(repeating: 4, count: 64).write(to: note)
    try Data(repeating: 5, count: 32).write(to: secret)
    try FileManager.default.linkItem(at: shared, to: sharedLink)
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: plain)

    var lockedChild = false
    if chmod(locked.path, 0) == 0 {
        if let handle = opendir(locked.path) {
            closedir(handle)
            chmod(locked.path, 0o755)
        } else {
            lockedChild = true
        }
    }

    var expectedUsers = allocated(plain) + allocated(shared) + allocated(note) + allocated(symlink)
    let expectedDeveloper = allocated(shared) + allocated(note)
    if !lockedChild {
        expectedUsers += allocated(secret)
    }
    return LiveFixture(
        root: root,
        applications: applications,
        users: users,
        home: home,
        appFile: appFile,
        plain: plain,
        symlink: symlink,
        locked: locked,
        expectedUsers: expectedUsers,
        expectedDeveloper: expectedDeveloper,
        lockedChild: lockedChild
    )
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("overview-stream-\(UUID().uuidString)", isDirectory: true)
}

private func allocated(_ url: URL) -> Int64 {
    LiveDiskScanner.nodeStat(url.path)!.blocks * 512
}

private func byteCount(_ url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
}

private final class ScriptedMeasurer: OverviewSubtreeMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(path: String, developerPrefix: String?)] = []
    let plain: Int64
    let users: Int64
    let developer: Int64

    init(plain: Int64 = 25, users: Int64 = 100, developer: Int64 = 30) {
        self.plain = plain
        self.users = users
        self.developer = developer
    }

    func accumulateSubtree(
        _ path: String,
        developerPrefix: String?,
        missingRootCountsAsZero: Bool
    ) async throws -> SubtreeAccumulation {
        lock.lock()
        calls.append((path, developerPrefix))
        lock.unlock()
        if developerPrefix != nil {
            return SubtreeAccumulation(totalSize: users, developerSize: developer, rootReadable: true, developerUnlisted: false)
        }
        return SubtreeAccumulation(totalSize: plain, developerSize: nil, rootReadable: true, developerUnlisted: false)
    }

    func paths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls.map(\.path)
    }

    func developerPrefix(for path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return calls.first { $0.path == path }?.developerPrefix
    }
}

private actor PathRecorder {
    private(set) var paths: [String] = []
    func record(_ path: String) { paths.append(path) }
}
