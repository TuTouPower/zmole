import XCTest
@testable import Zmole

@MainActor
final class PrewarmTests: XCTestCase {
    func testQueueRunsEachItemOnceInOrderWithoutOverlap() async throws {
        let previewURL = temporaryPreviewURL()
        let spy = PrewarmLaneSpy(previewFileURL: previewURL)
        let coordinator = OperationCoordinator()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: previewURL),
            coordinator: coordinator
        )

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 5 }

        let calls = await spy.calls.map { $0.arguments }
        XCTAssertEqual(calls, [
            ["uninstall", "--list-stream"],
            ["installer", "--list-json"],
            ["clean", "--dry-run"],
            ["optimize", "--dry-run"],
            ["purge", "--dry-run"]
        ])
        let maxConcurrent = await spy.maxConcurrent
        XCTAssertEqual(maxConcurrent, 1, "one prewarm item at a time")
        XCTAssertNil(coordinator.activeOperation, "prewarm never takes the write lease")
        XCTAssertNotNil(service.results[.uninstallList])
        XCTAssertNotNil(service.results[.installerList])
        XCTAssertNotNil(service.results[.cleanDryRun])
    }

    func testMissingFullDiskAccessDefersInstallerPrewarmUntilGranted() async throws {
        let previewURL = temporaryPreviewURL()
        let permission = MutableFlag(false)
        let monitor = FullDiskAccessMonitor(probe: { permission.value })
        let spy = PrewarmLaneSpy(previewFileURL: previewURL)
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: previewURL),
            coordinator: OperationCoordinator(),
            accessMonitor: monitor
        )

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 4 }
        let skippedCalls = await spy.calls.filter { $0.arguments == ["installer", "--list-json"] }.count
        XCTAssertEqual(skippedCalls, 0, "without Full Disk Access the installer prewarm must not run")
        XCTAssertNil(service.results[.installerList])

        permission.value = true
        monitor.refresh()
        service.diskAccessDidChange()
        try await waitUntil { await spy.calls.count == 5 }
        XCTAssertNotNil(service.results[.installerList])
    }

    func testCancelledItemIsRequeuedExactlyOnce() async throws {
        let previewURL = temporaryPreviewURL()
        let spy = PrewarmLaneSpy(
            blockedPrefix: ["installer", "--list-json"],
            previewFileURL: previewURL
        )
        let coordinator = OperationCoordinator()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: previewURL),
            coordinator: coordinator
        )

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.contains { $0.arguments == ["installer", "--list-json"] } }

        let lease = try XCTUnwrap(coordinator.acquire(.clean))
        try await waitUntil { await spy.cancelCount > 0 }
        lease.release()

        // uninstall + cancelled installer + installer retry + clean/optimize/purge.
        try await waitUntil { await spy.calls.count == 6 }
        try await Task.sleep(nanoseconds: 200_000_000)
        let installerCalls = await spy.calls.filter { $0.arguments == ["installer", "--list-json"] }.count
        XCTAssertEqual(installerCalls, 2, "the cancelled item runs again exactly once")
        let totalCalls = await spy.calls.count
        XCTAssertEqual(totalCalls, 6, "no duplicate item execution after the write finished")
        XCTAssertNotNil(service.results[.uninstallList])
    }

    func testPrewarmOnlyUsesReadOnlyDryRunCommands() async throws {
        let spy = PrewarmLaneSpy()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: temporaryPreviewURL()),
            coordinator: OperationCoordinator()
        )

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 5 }

        let banned: Set<[String]> = [["clean"], ["optimize"], ["purge", "--yes"], ["uninstall"]]
        for call in await spy.calls {
            XCTAssertFalse(banned.contains(call.arguments), "\(call.arguments) must not run in prewarm")
        }
    }

    func testStartingAWriteCancelsTheCurrentPrewarmRun() async throws {
        let spy = PrewarmLaneSpy(blockedPrefix: ["clean", "--dry-run"])
        let coordinator = OperationCoordinator()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: temporaryPreviewURL()),
            coordinator: coordinator
        )

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.contains { $0.arguments == ["clean", "--dry-run"] } }
        XCTAssertEqual(service.runningItem, .cleanDryRun)

        let lease = try XCTUnwrap(coordinator.acquire(.clean))
        try await waitUntil { await spy.cancelCount > 0 }
        XCTAssertNil(service.results[.cleanDryRun], "a cancelled item produces no result")

        // The write can proceed right away; the lease was already granted.
        XCTAssertEqual(coordinator.activeOperation, .clean)
        lease.release()
    }

    func testInvalidationClearsResultsAndRequeuesEverything() async throws {
        let previewURL = temporaryPreviewURL()
        let spy = PrewarmLaneSpy(previewFileURL: previewURL)
        let coordinator = OperationCoordinator()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: previewURL),
            coordinator: coordinator
        )

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 5 }
        XCTAssertNotNil(service.results[.installerList])

        coordinator.invalidatePreviews()
        try await waitUntil { await spy.calls.count == 10 }
        XCTAssertNotNil(service.results[.installerList])
    }

    func testUserRescanDropsThatItemFromTheQueue() async throws {
        let spy = PrewarmLaneSpy()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: temporaryPreviewURL()),
            coordinator: OperationCoordinator()
        )
        service.externalActivityProvider = { true }

        service.noteActivityChanged()
        await Task.yield()
        service.userDidRescan(.installerList)
        service.externalActivityProvider = { false }
        service.noteActivityChanged()

        try await waitUntil { await spy.calls.count == 4 }
        let calls = await spy.calls.map { $0.arguments }
        XCTAssertFalse(calls.contains(["installer", "--list-json"]))
    }

    func testFailedItemContinuesAndRetriesOnTheNextIdleTransition() async throws {
        let previewURL = temporaryPreviewURL()
        let spy = PrewarmLaneSpy(
            failingCommands: [["installer", "--list-json"]],
            previewFileURL: previewURL
        )
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: previewURL),
            coordinator: OperationCoordinator()
        )

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 5 }
        XCTAssertNil(service.results[.installerList])
        XCTAssertNotNil(service.results[.cleanDryRun], "a failure must not stop later items")

        service.externalActivityProvider = { true }
        service.noteActivityChanged()
        service.externalActivityProvider = { false }
        service.noteActivityChanged()

        try await waitUntil {
            await spy.calls.filter { $0.arguments == ["installer", "--list-json"] }.count == 2
        }
    }

    func testDiskScanningBlocksPrewarmUntilIdle() async throws {
        let spy = PrewarmLaneSpy()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: temporaryPreviewURL()),
            coordinator: OperationCoordinator()
        )
        service.externalActivityProvider = { true }

        service.noteActivityChanged()
        await Task.yield()
        let callsWhileScanning = await spy.calls.count
        XCTAssertEqual(callsWhileScanning, 0, "a disk scan counts as user activity")

        service.externalActivityProvider = { false }
        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 5 }
    }

    func testActiveCleanPreviewDefersOnlyTheCleanItem() async throws {
        let spy = PrewarmLaneSpy()
        let service = PrewarmService(
            process: spy,
            cleanPreviewStore: CleanPreviewStore(fileURL: temporaryPreviewURL()),
            coordinator: OperationCoordinator()
        )
        service.cleanPreviewActiveProvider = { true }

        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 4 }
        let calls = await spy.calls.map { $0.arguments }
        XCTAssertFalse(calls.contains(["clean", "--dry-run"]))
        XCTAssertNil(service.results[.cleanDryRun])

        service.cleanPreviewActiveProvider = { false }
        service.externalActivityProvider = { true }
        service.noteActivityChanged()
        service.externalActivityProvider = { false }
        service.noteActivityChanged()
        try await waitUntil { await spy.calls.count == 5 }
    }

    func testDemoConfigurationDisablesPrewarm() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-prewarm-demo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dependencies = AppDependencies(configuration: DemoConfiguration(arguments: [
            "zmole", "--demo", "--demo-data-root", root.path
        ]))

        XCTAssertNil(dependencies.prewarmService)
    }

    func testUninstallPageAdoptsPrewarmRowsWithoutScanning() async throws {
        let rows = UninstallFixture.rows(from: """
        [{"name":"Alpha","bundle_id":"com.example.alpha","uninstall_name":"Alpha","path":"/Applications/Alpha.app","size":"1 MB","version":"9.9","last_used_epoch":1700000000}]
        """)
        let counter = CountingListStream(rows: rows)
        let prewarm = PrewarmStub(results: [
            .uninstallList: PrewarmResult(capturedAt: Date(timeIntervalSince1970: 100), payload: .uninstallRows(rows))
        ])
        let viewModel = UninstallViewModel(
            process: StubProcess(),
            listStream: counter.makeStream(),
            coordinator: OperationCoordinator(),
            targetChecker: FixedTargetChecker(matches: true),
            iconProvider: NoopIconProvider(),
            prewarm: prewarm
        )

        await viewModel.loadListIfNeeded()

        XCTAssertEqual(viewModel.listings.count, 1)
        XCTAssertEqual(viewModel.apps.first?.version, "9.9")
        XCTAssertEqual(counter.opens, 0, "an adopted result must not re-scan")
        XCTAssertEqual(viewModel.listCapturedAt, Date(timeIntervalSince1970: 100))
    }

    func testInstallersPageAdoptsPrewarmCandidatesWithoutScanning() async throws {
        let candidates = [
            InstallerCandidate(path: "/Users/demo/Downloads/A.dmg", sizeBytes: 100, source: "Downloads", identity: "1:2:3")
        ]
        let spy = InstallerInterfaceSpy(listResults: [candidates])
        let prewarm = PrewarmStub(results: [
            .installerList: PrewarmResult(capturedAt: Date(timeIntervalSince1970: 50), payload: .installerCandidates(candidates))
        ])
        let viewModel = InstallersViewModel(
            interface: InstallerInterface { arguments in try await spy.run(arguments) },
            coordinator: OperationCoordinator(),
            prewarm: prewarm
        )

        await viewModel.loadListIfNeeded()

        XCTAssertEqual(viewModel.candidates, candidates)
        let listCalls = await spy.listCalls
        XCTAssertEqual(listCalls, 0, "an adopted result must not re-scan")
        XCTAssertEqual(viewModel.listCapturedAt, Date(timeIntervalSince1970: 50))

        // Page re-entry reuses the session list.
        await viewModel.loadListIfNeeded()
        let callsAfterReentry = await spy.listCalls
        XCTAssertEqual(callsAfterReentry, 0)
    }

    func testCleanPageAdoptsPrewarmPreviewAndProtectsTheConfirmation() async throws {
        let store = CleanPreviewStore(fileURL: temporaryPreviewURL())
        let snapshot = try makeCleanSnapshot(store: store)
        let process = MaintenanceProcessSpy()
        let prewarm = PrewarmStub(results: [
            .cleanDryRun: PrewarmResult(capturedAt: Date(timeIntervalSince1970: 70), payload: .cleanPreview(snapshot))
        ])
        let viewModel = CleanViewModel(
            process: process,
            previewStore: store,
            coordinator: OperationCoordinator(),
            prewarm: prewarm
        )

        viewModel.adoptPrewarmPreviewIfAvailable()

        XCTAssertNotNil(viewModel.preview)
        XCTAssertEqual(viewModel.previewCapturedAt, Date(timeIntervalSince1970: 70))
        let invocations = await process.invocations
        XCTAssertTrue(invocations.isEmpty)

        // With the confirmation on screen, a new result never replaces it.
        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.isConfirmationPresented)
        let replacement = try makeCleanSnapshot(store: store, name: "Replacement")
        prewarm.results[.cleanDryRun] = PrewarmResult(
            capturedAt: Date(timeIntervalSince1970: 90),
            payload: .cleanPreview(replacement)
        )
        viewModel.adoptPrewarmPreviewIfAvailable()
        XCTAssertEqual(viewModel.preview, snapshot, "the confirming preview stays")
    }

    func testOptimizeAndPurgeAdoptPrewarmPreviews() async throws {
        let optimizePrewarm = PrewarmStub(results: [
            .optimizeDryRun: PrewarmResult(
                capturedAt: Date(timeIntervalSince1970: 80),
                payload: .maintenance("Optimize preview output")
            )
        ])
        let optimize = OptimizeViewModel(
            process: MaintenanceProcessSpy(),
            coordinator: OperationCoordinator(),
            prewarm: optimizePrewarm
        )
        optimize.adoptPrewarmPreviewIfAvailable()
        XCTAssertEqual(optimize.preview?.output, "Optimize preview output")
        XCTAssertEqual(optimize.previewCapturedAt, Date(timeIntervalSince1970: 80))

        let purgePrewarm = PrewarmStub(results: [
            .purgeDryRun: PrewarmResult(
                capturedAt: Date(timeIntervalSince1970: 81),
                payload: .maintenance("Purge preview output")
            )
        ])
        let purge = PurgeViewModel(
            process: MaintenanceProcessSpy(),
            coordinator: OperationCoordinator(),
            prewarm: purgePrewarm
        )
        purge.adoptPrewarmPreviewIfAvailable()
        XCTAssertEqual(purge.preview?.output, "Purge preview output")
        XCTAssertEqual(purge.previewCapturedAt, Date(timeIntervalSince1970: 81))
    }

    // MARK: - Helpers

    private func temporaryPreviewURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-prewarm-\(UUID().uuidString)-clean-list.txt")
    }

    private func makeCleanSnapshot(
        store: CleanPreviewStore,
        name: String = "Caches"
    ) throws -> CleanPreviewSnapshot {
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

@MainActor
private final class PrewarmStub: PrewarmResultProviding {
    var results: [PrewarmItem: PrewarmResult]

    init(results: [PrewarmItem: PrewarmResult]) {
        self.results = results
    }

    func takeResult(_ item: PrewarmItem) -> PrewarmResult? {
        results.removeValue(forKey: item)
    }

    func userDidRescan(_ item: PrewarmItem) {
        results.removeValue(forKey: item)
    }
}

/// Records every command, can block or fail specific arguments, and detects
/// overlapping runs.
actor PrewarmLaneSpy: MoleProcessControlling, MoleStreaming {
    struct Call: Sendable {
        let arguments: [String]
    }

    private(set) var calls: [Call] = []
    private(set) var cancelCount = 0
    private(set) var maxConcurrent = 0

    private var active = 0
    private let blockedPrefix: [String]
    private let failingCommands: Set<[String]>
    private let previewFileURL: URL?
    private var hasBlocked = false
    private var blockedContinuations: [CheckedContinuation<MoleCommandResult, Error>] = []

    init(
        blockedPrefix: [String] = [],
        failingCommands: Set<[String]> = [],
        previewFileURL: URL? = nil
    ) {
        self.blockedPrefix = blockedPrefix
        self.failingCommands = failingCommands
        self.previewFileURL = previewFileURL
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        calls.append(Call(arguments: arguments))
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        defer { active -= 1 }

        if failingCommands.contains(arguments) {
            return MoleCommandResult(stdout: "", stderr: "prewarm failed", exitCode: 7)
        }
        if !blockedPrefix.isEmpty, !hasBlocked, arguments.starts(with: blockedPrefix) {
            hasBlocked = true
            return try await withCheckedThrowingContinuation { continuation in
                blockedContinuations.append(continuation)
            }
        }
        if arguments == ["clean", "--dry-run"], let previewFileURL {
            try? "# preview\n=== Caches ===\n/tmp/cache # 1KB\n".write(
                to: previewFileURL,
                atomically: true,
                encoding: .utf8
            )
        }
        return MoleCommandResult(stdout: fixtureOutput(for: arguments), stderr: "", exitCode: 0)
    }

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        calls.append(Call(arguments: arguments))
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        defer { active -= 1 }
        return AsyncThrowingStream { continuation in
            let line = "{\"path\":\"/Applications/Demo.app\",\"name\":\"Demo\"}\n"
            continuation.yield(.stdoutLine(Data(line.utf8)))
            continuation.yield(.stdoutLine(Data("{\"event\":\"done\"}\n".utf8)))
            continuation.finish()
        }
    }

    func cancel() async {
        cancelCount += 1
        let continuations = blockedContinuations
        blockedContinuations = []
        for continuation in continuations {
            continuation.resume(throwing: MoleBridgeError.cancelled)
        }
    }

    private func fixtureOutput(for arguments: [String]) -> String {
        switch arguments.first {
        case "installer":
            return "[{\"path\":\"/Users/demo/Downloads/A.dmg\",\"size_bytes\":100,\"source\":\"Downloads\",\"identity\":\"1:2:3\"}]"
        default:
            return "preview output"
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
