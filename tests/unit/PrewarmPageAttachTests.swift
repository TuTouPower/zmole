import Combine
import XCTest
@testable import Zmole

@MainActor
final class PrewarmPageAttachTests: XCTestCase {
    private var cancellables: [AnyCancellable] = []

    func testUninstallPageReusesOngoingBackgroundScanWithoutRestarting() async throws {
        // AC-001
        let mockStream = PausableUninstallStream()
        let lanes = makeBackgroundLanes(uninstallStreaming: mockStream)
        let coordinator = OperationCoordinator()
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        let service = BackgroundScanService(
            lanes: lanes,
            cleanPreviewStore: .live,
            cache: cache,
            coordinator: coordinator
        )

        service.request(.uninstallList)
        for _ in 0..<20 {
            if mockStream.activeCalls > 0 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let callsInit = mockStream.activeCalls
        XCTAssertEqual(callsInit, 1)

        let viewModel = UninstallViewModel(
            process: LocalNoopProcess(),
            coordinator: coordinator,
            scan: service
        )

        await viewModel.loadListIfNeeded()
        let callsAfter = mockStream.activeCalls
        XCTAssertEqual(callsAfter, 1, "Page opening must not spawn second scan (AC-001)")

        mockStream.yieldRow("{\"path\":\"/Applications/App1.app\",\"name\":\"App1\",\"bundle_id\":\"com.app1\",\"uninstall_name\":\"App1\"}\n")
        mockStream.yieldRow("{\"event\":\"done\"}\n")
        mockStream.finish()

        try await waitUntil { !service.runningItems.contains(.uninstallList) }
        try await waitUntil { viewModel.apps.count == 1 }
        XCTAssertEqual(viewModel.apps.first?.name, "App1")
    }

    func testProgressivePublishingFlushesWithin100ms() async throws {
        // AC-002
        let mockStream = PausableUninstallStream()
        let lanes = makeBackgroundLanes(uninstallStreaming: mockStream)
        let coordinator = OperationCoordinator()
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        let service = BackgroundScanService(
            lanes: lanes,
            cleanPreviewStore: .live,
            cache: cache,
            coordinator: coordinator
        )

        service.request(.uninstallList)
        mockStream.yieldRow("{\"path\":\"/Applications/Fast.app\",\"name\":\"Fast\"}\n")

        // Wait 120ms (>= 100ms trailing throttle) without sending done
        try await Task.sleep(nanoseconds: 120_000_000)

        let inProgress = service.inProgressUninstallList()
        XCTAssertFalse(inProgress.isEmpty, "Merged rows must be visible within 100ms of arriving (AC-002)")
        XCTAssertEqual(inProgress.first?.name, "Fast")

        mockStream.yieldRow("{\"event\":\"done\"}\n")
        mockStream.finish()
    }

    func testInstallerPageReusesOngoingBackgroundScan() async throws {
        // AC-003
        let installerSpy = InstallerProcessSpy()
        let lanes = makeBackgroundLanes(installerProcess: installerSpy)
        let coordinator = OperationCoordinator()
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        let service = BackgroundScanService(
            lanes: lanes,
            cleanPreviewStore: .live,
            cache: cache,
            coordinator: coordinator
        )

        service.request(.installerList)
        for _ in 0..<20 {
            if installerSpy.invocationCount > 0 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let invocationsBefore = installerSpy.invocationCount
        XCTAssertEqual(invocationsBefore, 1)

        let viewModel = InstallersViewModel(
            interface: InstallerInterface(process: installerSpy),
            coordinator: coordinator,
            scan: service,
            accessMonitor: FullDiskAccessMonitor(probe: { true })
        )

        await viewModel.loadListIfNeeded()
        let invocationsAfter = installerSpy.invocationCount
        XCTAssertEqual(invocationsAfter, 1, "Must not duplicate installer scan (AC-003)")
    }

    func testPartialScanFailureDoesNotCorruptCacheAndPreventsUninstallExecution() async throws {
        // AC-007
        let oldApp = UninstallAppListing(
            path: "/Applications/Old.app",
            name: "Old",
            bundleID: "com.old",
            uninstallName: "Old",
            source: "App Store",
            sizeText: "10 MB",
            version: "1.0",
            lastUsed: Date()
        )
        let now = Date(timeIntervalSince1970: 50_000)
        let cache = BackgroundScanCache(fileURL: temporaryFileURL())
        cache.save([.uninstallList: BackgroundScanResult(capturedAt: now, payload: .uninstallRows([oldApp]))])

        let mockStream = PausableUninstallStream()
        let lanes = makeBackgroundLanes(uninstallStreaming: mockStream)
        let coordinator = OperationCoordinator()
        let service = BackgroundScanService(
            lanes: lanes,
            cleanPreviewStore: .live,
            cache: cache,
            coordinator: coordinator
        )

        let viewModel = UninstallViewModel(
            process: LocalNoopProcess(),
            coordinator: coordinator,
            scan: service
        )
        await viewModel.loadListIfNeeded()
        XCTAssertEqual(viewModel.apps.count, 1)

        // Request new scan that emits a row and then fails
        service.request(.uninstallList)
        mockStream.yieldRow("{\"path\":\"/Applications/New.app\",\"name\":\"New\"}\n")
        try await Task.sleep(nanoseconds: 120_000_000)

        // In-progress rows visible, but cannot uninstall during in-progress scan
        XCTAssertFalse(viewModel.canUninstall, "Cannot uninstall while listing is in progress (AC-007)")

        mockStream.fail(with: MoleBridgeError.commandFailed(MoleCommandResult(stdout: "", stderr: "err", exitCode: 1)))

        try await waitUntil { service.failedItems.contains(.uninstallList) }

        // Cache must still hold old snapshot, not partial
        let currentResult = service.result(for: .uninstallList)
        if case let .uninstallRows(rows) = currentResult?.payload {
            XCTAssertEqual(rows.first?.name, "Old", "Failed scan must keep previous valid snapshot (AC-007)")
            XCTAssertEqual(currentResult?.capturedAt, now)
        } else {
            XCTFail("Missing payload")
        }
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("prewarm-test-\(UUID().uuidString).json")
    }

    private func makeBackgroundLanes(
        uninstallStreaming: (any MoleStreaming)? = nil,
        installerProcess: (any MoleProcessControlling)? = nil
    ) -> BackgroundScanLanes {
        let dummyProcess = LocalNoopProcess()
        let instProc = installerProcess ?? dummyProcess
        return BackgroundScanLanes(
            uninstallStreaming: uninstallStreaming ?? UnavailableMoleStreaming(),
            installer: InstallerInterface(process: instProc),
            installerProcess: instProc,
            clean: dummyProcess,
            optimize: dummyProcess,
            purge: dummyProcess
        )
    }

    private func waitUntil(timeout: TimeInterval = 2.0, condition: @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private final class LocalNoopProcess: MoleProcessControlling, @unchecked Sendable {
    func run(_ arguments: [String], stdin: Data?, timeout: TimeInterval) async throws -> MoleCommandResult {
        MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }
    func cancel() async {}
}

private final class PausableUninstallStream: MoleStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var streamContinuation: AsyncThrowingStream<MoleOutputEvent, Error>.Continuation?
    private var pendingRows: [String] = []
    private var _activeCalls = 0

    var activeCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _activeCalls
    }

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        lock.lock()
        _activeCalls += 1
        lock.unlock()
        return AsyncThrowingStream { cont in
            self.lock.lock()
            self.streamContinuation = cont
            for line in self.pendingRows {
                cont.yield(.stdoutLine(Data(line.utf8)))
            }
            self.pendingRows.removeAll()
            self.lock.unlock()
        }
    }

    func yieldRow(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if let cont = streamContinuation {
            cont.yield(.stdoutLine(Data(line.utf8)))
        } else {
            pendingRows.append(line)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        streamContinuation?.finish()
    }

    func fail(with error: Error) {
        lock.lock()
        defer { lock.unlock() }
        streamContinuation?.finish(throwing: error)
    }

    func cancel() async {
        lock.lock()
        defer { lock.unlock() }
        streamContinuation?.finish(throwing: CancellationError())
    }
}

private final class InstallerProcessSpy: MoleProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _invocations: [[String]] = []

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _invocations.count
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        lock.lock()
        _invocations.append(arguments)
        lock.unlock()
        if arguments == ["installer", "--list-json"] {
            return MoleCommandResult(stdout: "[]", stderr: "", exitCode: 0)
        }
        return MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}
