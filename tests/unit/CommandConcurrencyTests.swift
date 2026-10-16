import XCTest
@testable import Zmole

@MainActor
final class CommandConcurrencyTests: XCTestCase {
    private let sleepURL = URL(fileURLWithPath: "/bin/sleep")

    func testCommandBridgesAreDistinct() throws {
        let bridges = try XCTUnwrap(MoleCommandLanes.makeCommandBridges())
        XCTAssertEqual(bridges.count, MoleCommandLanes.commandLaneCount)
        let identities = bridges.map { ObjectIdentifier($0 as AnyObject) }
        XCTAssertEqual(Set(identities).count, bridges.count, "each one-shot lane must be a distinct bridge")
    }

    func testAppDependenciesWiresDistinctLanes() {
        let dependencies = AppDependencies()
        let lanes = [
            dependencies.lanes.analyze, dependencies.lanes.history, dependencies.lanes.uninstall,
            dependencies.lanes.installer, dependencies.lanes.statusCommand, dependencies.lanes.cleanCommand,
            dependencies.lanes.optimize, dependencies.lanes.purge, dependencies.lanes.estimate
        ]
        let identities = lanes.map { ObjectIdentifier($0 as AnyObject) }
        XCTAssertEqual(
            Set(identities).count, lanes.count,
            "production assembly must give each one-shot consumer its own lane"
        )
        XCTAssertNotEqual(
            ObjectIdentifier(dependencies.lanes.analyze as AnyObject),
            ObjectIdentifier(dependencies.lanes.estimate as AnyObject),
            "the overview estimate must not share the disk page analyze lane"
        )
    }

    // AC-001: a busy read lane must not reject another read lane.
    func testBusyReadLaneDoesNotBlockAnotherReadLane() async throws {
        let lanes = try makeSleepLanes()
        guard let analyze = lanes.analyze as? MoleBridge, let history = lanes.history as? MoleBridge else {
            return XCTFail("expected MoleBridge lanes")
        }

        async let longRunning = analyze.run(["3"])
        try await waitUntilBusy(analyze)

        let historyBusy = await history.isBusy
        XCTAssertFalse(historyBusy, "the history lane must not be busy while analyze runs")
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
        let result = try await lanes.analyze.run(["0"], stdin: nil, timeout: 5)
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

    private func makeSleepLanes() throws -> MoleCommandLanes {
        func bridge() throws -> any MoleProcessControlling {
            try MoleBridge(executableURL: sleepURL)
        }
        return MoleCommandLanes(
            analyze: try bridge(), history: try bridge(), uninstall: try bridge(),
            installer: try bridge(), statusCommand: try bridge(), cleanCommand: try bridge(),
            optimize: try bridge(), purge: try bridge(), estimate: try bridge(),
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
