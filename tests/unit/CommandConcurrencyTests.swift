import XCTest
@testable import Zmole

@MainActor
final class CommandConcurrencyTests: XCTestCase {
    private let sleepURL = URL(fileURLWithPath: "/bin/sleep")

    func testCommandBridgesAreDistinct() throws {
        let bridges = try XCTUnwrap(MoleCommandLanes.makeCommandBridges())
        let oneShots: [any MoleProcessControlling] = [
            bridges.history, bridges.uninstall, bridges.installer,
            bridges.cleanCommand, bridges.optimize, bridges.purge, bridges.estimate
        ] + bridges.estimateExtras
        let identities = oneShots.map { ObjectIdentifier($0 as AnyObject) }
        XCTAssertEqual(Set(identities).count, oneShots.count, "each one-shot lane must be a distinct bridge")
    }

    func testAppDependenciesWiresDistinctLanes() {
        let dependencies = AppDependencies()
        let lanes = [
            dependencies.lanes.history, dependencies.lanes.uninstall,
            dependencies.lanes.installer, dependencies.lanes.cleanCommand,
            dependencies.lanes.optimize, dependencies.lanes.purge
        ] + dependencies.lanes.estimatePool
        let identities = lanes.map { ObjectIdentifier($0 as AnyObject) }
        XCTAssertEqual(
            Set(identities).count, lanes.count,
            "production assembly must give each one-shot consumer its own lane"
        )
    }

    // AC-001: a busy read lane must not reject another read lane.
    func testBusyReadLaneDoesNotBlockAnotherReadLane() async throws {
        let lanes = try makeSleepLanes()
        guard let estimate = lanes.estimate as? MoleBridge, let history = lanes.history as? MoleBridge else {
            return XCTFail("expected MoleBridge lanes")
        }

        async let longRunning = estimate.run(["3"])
        try await waitUntilBusy(estimate)

        let historyBusy = await history.isBusy
        XCTAssertFalse(historyBusy, "the history lane must not be busy while another read lane runs")
        let result = try await lanes.history.run(["0"], stdin: nil, timeout: 5)
        XCTAssertEqual(result.exitCode, 0)

        _ = try? await longRunning
    }

    // AC-002: an active status watch stream must not block a read command lane.
    func testActiveStatusStreamDoesNotBlockReadLane() async throws {
        let lanes = try makeSleepLanes()
        guard let streamBridge = lanes.statusStream as? MoleBridge else {
            return XCTFail("expected MoleBridge status stream")
        }

        _ = await lanes.statusStream.stream(["3"], stdin: nil, timeout: nil)
        try await waitUntilBusy(streamBridge)
        let result = try await lanes.estimate.run(["0"], stdin: nil, timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
        await lanes.statusStream.cancel()
    }

    // AC-003: two write view models on different lanes still cannot run at once.
    func testTwoWriteViewModelsCannotRunConcurrently() async throws {
        let optimizeSpy = BlockingProcessSpy()
        let purgeSpy = BlockingProcessSpy()
        let coordinator = OperationCoordinator()
        let optimize = OptimizeViewModel(process: optimizeSpy, coordinator: coordinator)
        let purge = PurgeViewModel(process: purgeSpy, coordinator: coordinator)

        let running = Task { @MainActor in await optimize.previewOptimize() }
        await optimizeSpy.waitForStart()

        await purge.previewPurge()
        // Representation-agnostic mutual exclusion: the second write must not
        // spawn a command on its own lane nor enter previewing.
        let purgeInvocations = await purgeSpy.invocations
        XCTAssertEqual(purgeInvocations, 0, "a second write must not spawn while one is active")
        XCTAssertFalse(purge.isPreviewing)

        await optimizeSpy.finish()
        await running.value
        XCTAssertTrue(optimize.canConfirm)
    }

    // AC-004: duplicate submission on one lane keeps a single command in flight.
    func testSameBridgeRejectsConcurrentRun() async throws {
        let bridge = try MoleBridge(executableURL: sleepURL)
        async let longRunning = bridge.run(["2"])
        try await waitUntilBusy(bridge)

        do {
            _ = try await bridge.run(["0"], stdin: nil, timeout: 5)
            XCTFail("expected a busy rejection on the same lane")
        } catch {
            XCTAssertEqual(error as? MoleBridgeError, .busy)
        }
        _ = try? await longRunning
    }

    func testWriteViewModelsShareThePreviewLeaseCoordinator() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "src/zmole/Features/Clean/CleanViewModel.swift",
            "src/zmole/Features/Uninstall/UninstallViewModel.swift",
            "src/zmole/Features/Operations/MaintenanceOperation.swift"
        ]
        for file in files {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(
                source.contains("PreviewLeaseCoordinator("),
                "\(file) must use the shared preview lease coordinator"
            )
            XCTAssertFalse(
                source.contains("private func releaseLease(clearPreviewGeneration"),
                "\(file) must not keep its own lease boilerplate"
            )
            XCTAssertFalse(
                source.contains("previewCoordinatorGeneration"),
                "\(file) must not track the preview generation itself"
            )
            XCTAssertFalse(
                source.contains("coordinator.$invalidationGeneration.sink"),
                "\(file) must not subscribe to the invalidation signal itself"
            )
            XCTAssertFalse(
                source.contains("private var isCurrentPreview"),
                "\(file) must not keep its own isCurrentPreview"
            )
            XCTAssertFalse(
                source.contains("private func operationID(for"),
                "\(file) must not keep its own operation-id extraction"
            )
        }
        let shared = try String(
            contentsOf: root.appendingPathComponent("src/zmole/Features/Operations/PreviewLeaseCoordinator.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(shared.contains("class PreviewLeaseCoordinator"), "the shared coordinator must exist")
    }

    private func makeSleepLanes() throws -> MoleCommandLanes {
        func bridge() throws -> any MoleProcessControlling {
            try MoleBridge(executableURL: sleepURL)
        }
        let estimateBridges: [any MoleProcessControlling] = [try bridge(), try bridge(), try bridge()]
        return MoleCommandLanes(
            history: try bridge(), uninstall: try bridge(),
            uninstallStream: try MoleBridge(executableURL: sleepURL),
            installer: try bridge(), cleanCommand: try bridge(),
            optimize: try bridge(), purge: try bridge(),
            estimate: estimateBridges[0],
            estimatePool: estimateBridges,
            prewarm: try MoleBridge(executableURL: sleepURL),
            statusStream: try MoleBridge(executableURL: sleepURL),
            cleanStream: try MoleBridge(executableURL: sleepURL)
        )
    }

    private func waitUntilBusy(_ bridge: MoleBridge) async throws {
        for _ in 0..<500 {
            if await bridge.isBusy { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("bridge never became busy")
    }
}

private actor BlockingProcessSpy: MoleProcessControlling {
    private var started = false
    private(set) var invocations = 0
    private var continuation: CheckedContinuation<MoleCommandResult, Error>?

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations += 1
        started = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() async {
        continuation?.resume(throwing: MoleBridgeError.cancelled)
        continuation = nil
    }

    func waitForStart() async {
        for _ in 0..<500 {
            if started { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func finish() {
        continuation?.resume(returning: MoleCommandResult(stdout: "ok", stderr: "", exitCode: 0))
        continuation = nil
    }
}
