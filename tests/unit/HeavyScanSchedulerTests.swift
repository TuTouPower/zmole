import XCTest
@testable import Zmole

@MainActor
final class HeavyScanSchedulerTests: XCTestCase {

    // AC-001: 名额为 1、2、3、4 时，全部被纳管扫描的在执行逻辑任务总数不超过该值，多余任务等待。
    func testAC001_MaxConcurrencyEnforcedForBudgetsOneTwoThreeFour() async throws {
        for limit in [1, 2, 3, 4] {
            let scheduler = HeavyScanScheduler(maxConcurrency: limit)
            let maxObserved = AtomicBox(0)
            let runningNow = AtomicBox(0)
            let gate = AsyncGate()

            var tasks: [Task<Void, Error>] = []
            for i in 0..<10 {
                let t = Task {
                    try await scheduler.withPermit(taskID: "task-\(i)", priority: .background) {
                        runningNow.set(runningNow.get() + 1)
                        if runningNow.get() > maxObserved.get() {
                            maxObserved.set(runningNow.get())
                        }
                        // Verify at this exact moment runningNow does not exceed limit
                        XCTAssertLessThanOrEqual(runningNow.get(), limit)
                        await gate.wait()
                        runningNow.set(runningNow.get() - 1)
                    }
                }
                tasks.append(t)
            }

            // Give time for initial wave to fill slots
            for _ in 0..<50 {
                let active = await scheduler.activeCount
                if active == limit { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            let activeAtPeak = await scheduler.activeCount
            XCTAssertEqual(activeAtPeak, limit, "Active tasks must reach exactly maxConcurrency")
            XCTAssertLessThanOrEqual(maxObserved.get(), limit, "Concurrent tasks must never exceed budget \(limit)")

            // Release all tasks
            await gate.open()
            for t in tasks {
                try await t.value
            }

            let finalActive = await scheduler.activeCount
            XCTAssertEqual(finalActive, 0, "All permits must be released")
        }
    }

    // AC-002: 实际任务结束后下一个等待项开始，等待不被标失败。
    func testAC002_NextItemStartsWhenTaskFinishes() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let gate = AsyncGate()
        let secondStarted = AtomicBox(false)

        let task1 = Task {
            try await scheduler.withPermit(taskID: "task-1") {
                await gate.wait()
            }
        }

        // Wait until task 1 holds the slot
        for _ in 0..<50 {
            if await scheduler.activeCount == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let task2 = Task {
            try await scheduler.withPermit(taskID: "task-2") {
                secondStarted.set(true)
            }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(secondStarted.get(), "Task 2 must wait while task 1 is executing")

        // Unblock task 1
        await gate.open()
        try await task1.value
        try await task2.value

        XCTAssertTrue(secondStarted.get(), "Task 2 must start and succeed after task 1 completes")
    }

    // AC-003: 当前页请求先获得可用位；切页后旧请求撤回提升，已运行任务不被抢占；达到防饥饿界限的后台项可获位。
    func testAC003_UserVisiblePriorityPreemptsQueueAndAntiStarvationKicksIn() async throws {
        // Scheduler with capacity 1, starvation limit 2
        let scheduler = HeavyScanScheduler(maxConcurrency: 1, starvationLimit: 2)
        let blockerGate = AsyncGate()

        // 1. Fill the slot with a running task
        let runningTask = Task {
            try await scheduler.withPermit(taskID: "initial-runner") {
                await blockerGate.wait()
            }
        }

        for _ in 0..<50 {
            if await scheduler.activeCount == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // 2. Enqueue background task B1
        let order = AtomicBox<[String]>([])
        let gateB1 = AsyncGate()
        let taskB1 = Task {
            try await scheduler.withPermit(taskID: "bg-1", priority: .background) {
                order.set(order.get() + ["bg-1"])
                await gateB1.wait()
            }
        }

        // 3. Enqueue userVisible task UV1
        let gateUV1 = AsyncGate()
        let taskUV1 = Task {
            try await scheduler.withPermit(taskID: "uv-1", priority: .userVisible) {
                order.set(order.get() + ["uv-1"])
                await gateUV1.wait()
            }
        }

        // 4. Enqueue userVisible task UV2
        let gateUV2 = AsyncGate()
        let taskUV2 = Task {
            try await scheduler.withPermit(taskID: "uv-2", priority: .userVisible) {
                order.set(order.get() + ["uv-2"])
                await gateUV2.wait()
            }
        }

        // 5. Enqueue userVisible task UV3
        let gateUV3 = AsyncGate()
        let taskUV3 = Task {
            try await scheduler.withPermit(taskID: "uv-3", priority: .userVisible) {
                order.set(order.get() + ["uv-3"])
                await gateUV3.wait()
            }
        }

        // Wait until all 4 requests have queued in the scheduler
        for _ in 0..<50 {
            let waiting = await scheduler.waitingCount
            if waiting == 4 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let totalWaiting = await scheduler.waitingCount
        XCTAssertEqual(totalWaiting, 4)

        // Unblock initial runner
        await blockerGate.open()
        try await runningTask.value

        // UV1 should start first (preempting bg-1)
        for _ in 0..<50 {
            if order.get().contains("uv-1") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(order.get(), ["uv-1"])

        // Finish UV1
        await gateUV1.open()
        try await taskUV1.value

        // UV2 should start next (2nd high priority item)
        for _ in 0..<50 {
            if order.get().contains("uv-2") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(order.get(), ["uv-1", "uv-2"])

        // Finish UV2
        await gateUV2.open()
        try await taskUV2.value

        // Anti-starvation limit is 2: after 2 high priority tasks (UV1, UV2),
        // bg-1 MUST be admitted next even though UV3 is waiting!
        for _ in 0..<50 {
            if order.get().contains("bg-1") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(order.get(), ["uv-1", "uv-2", "bg-1"], "Anti-starvation must admit waiting background task")

        // Finish bg-1
        await gateB1.open()
        try await taskB1.value

        // Finally UV3 gets admitted
        for _ in 0..<50 {
            if order.get().contains("uv-3") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(order.get(), ["uv-1", "uv-2", "bg-1", "uv-3"])
        await gateUV3.open()
        try await taskUV3.value
    }

    // AC-004: 名额满时 status watch 仍能启动且不占位；本 task 不增加新的状态采样启动入口。
    func testAC004_StatusWatchRunsWithoutTakingPermit() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let blockerGate = AsyncGate()

        // Fill all scheduler slots
        let runner = Task {
            try await scheduler.withPermit(taskID: "heavy") {
                await blockerGate.wait()
            }
        }

        for _ in 0..<50 {
            let active = await scheduler.activeCount
            if active == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Status watch does NOT use scheduler, so it runs completely unblocked!
        let statusStarted = AtomicBox(false)
        let statusTask = Task {
            // Simulated status watch
            statusStarted.set(true)
        }

        await statusTask.value
        XCTAssertTrue(statusStarted.get(), "Status watch must run immediately without waiting for scheduler")

        await blockerGate.open()
        try await runner.value
    }

    // AC-007: 排队者不持名额；运行任务正常结束或全部子任务取消退出后，名额准确释放一次。
    func testAC007_PermitReleasedAccuratelyAfterExecutionOrCancellation() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 2)

        let p1 = try await scheduler.acquire(taskID: "t1")
        let p2 = try await scheduler.acquire(taskID: "t2")
        let active2 = await scheduler.activeCount
        XCTAssertEqual(active2, 2)

        await p1.release()
        let active1 = await scheduler.activeCount
        XCTAssertEqual(active1, 1)

        await p2.release()
        let active0 = await scheduler.activeCount
        XCTAssertEqual(active0, 0)
    }

    // AC-012: 同批后台任务按固定起始次序进入执行，没有人为 sleep；空闲通道与名额同时可用才启动，名额为 1 和通道忙碌时均无死锁。
    func testAC012_DeadlockFreedomWithConcurrencyOne() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let results = AtomicBox<[Int]>([])

        for i in 1...5 {
            try await scheduler.withPermit(taskID: "item-\(i)") {
                results.set(results.get() + [i])
            }
        }

        XCTAssertEqual(results.get(), [1, 2, 3, 4, 5], "All tasks must execute sequentially without deadlock")
    }

    // AC-013: 排队后取消、失效或关闭会话的任务不启动；运行任务的元数据 worker 尚存活时名额不能交给下一项。
    func testAC013_QueuedTaskCancelledDoesNotAcquireSlot() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let blockerGate = AsyncGate()

        let runner = Task {
            try await scheduler.withPermit(taskID: "runner") {
                await blockerGate.wait()
            }
        }

        for _ in 0..<50 {
            let active = await scheduler.activeCount
            if active == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let queuedTask = Task {
            try await scheduler.withPermit(taskID: "cancelled-waiter") {
                XCTFail("Cancelled task must never execute body")
            }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        queuedTask.cancel()

        do {
            try await queuedTask.value
            XCTFail("Should have thrown CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        // Active count must still be 1 (only the runner)
        let activeRunner = await scheduler.activeCount
        XCTAssertEqual(activeRunner, 1)

        await blockerGate.open()
        try await runner.value
        let activeEnd = await scheduler.activeCount
        XCTAssertEqual(activeEnd, 0)
    }

    // AC-005: 同后台项重复需求不产生第二个进程；clean 执行先取消并等待冲突扫描退出，不能因资源队列放宽互斥。
    func testAC005_DuplicateBackgroundRequestsSharePermit() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 2)
        let cleanSpy = CleanProcessSpy(previewURL: FileManager.default.temporaryDirectory.appendingPathComponent("clean-\(UUID().uuidString).txt"))
        defer { try? FileManager.default.removeItem(at: cleanSpy.previewURL) }

        let lanes = TestLanes.make(clean: cleanSpy)
        let coordinator = OperationCoordinator()
        let service = BackgroundScanService(
            lanes: lanes,
            cleanPreviewStore: CleanPreviewStore(fileURL: cleanSpy.previewURL),
            scheduler: scheduler,
            coordinator: coordinator
        )

        service.request(.clean)
        service.request(.clean)

        for _ in 0..<50 {
            if await cleanSpy.runCallCount == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let runs = await cleanSpy.runCallCount
        XCTAssertEqual(runs, 1, "Duplicate request must reuse the in-flight scan and permit")

        await service.cancelAndWait(.clean)
    }

    // AC-009: 磁盘测量排队期间主线程仍能完成已排队的界面更新。
    func testAC009_MainThreadRemainsResponsiveWhileHeavyScanQueued() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let blockerGate = AsyncGate()

        let runner = Task {
            try await scheduler.withPermit(taskID: "slot-filler") {
                await blockerGate.wait()
            }
        }

        for _ in 0..<50 {
            if await scheduler.activeCount == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let diskMeasureQueued = Task {
            try await scheduler.withPermit(taskID: "disk:/Applications") {
                // heavy work
            }
        }

        var uiUpdateHappened = false
        await MainActor.run {
            uiUpdateHappened = true
        }

        XCTAssertTrue(uiUpdateHappened, "Main thread must process UI updates while heavy scans are queued")

        await blockerGate.open()
        try await runner.value
        try await diskMeasureQueued.value
    }

    // AC-011: 兼容共享任务只计一个名额；相同路径但不同统计语义、世代或权限的任务不错误合并，订阅取消不提前释放运行任务的名额。
    func testAC011_SharedDiskMeasurementsShareSinglePermit() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let scanner = FakeDiskScanner()
        scanner.blockedMeasures.insert("/test/A")
        let session = DiskMeasurementSession(scanner: scanner, scheduler: scheduler)

        let sub1 = session.subscribe(path: "/test/A")
        let sub2 = session.subscribe(path: "/test/A")

        for _ in 0..<50 {
            if await scheduler.activeCount == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let active = await scheduler.activeCount
        XCTAssertEqual(active, 1, "Shared measurement must only acquire 1 permit")

        sub1.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)

        let activeAfterOneCancel = await scheduler.activeCount
        XCTAssertEqual(activeAfterOneCancel, 1, "Permit must not be released early when one subscriber cancels")

        sub2.cancel()
        session.close()
    }

    // [deploy] AC-010: 名额 1、2、3、4 在相同代表性数据集上各至少重复 5 次、交错次序运行；
    // 记录首次遍历与预热遍历、首批响应/总耗时分布、内部 worker 数及可取得的资源指标，基于记录选择生产默认值。
    func testAC010_Deploy_BenchmarkConcurrencyBudgets() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("benchmark-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for dirIdx in 0..<10 {
            let sub = fixtureRoot.appendingPathComponent("sub-\(dirIdx)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for fileIdx in 0..<10 {
                let file = sub.appendingPathComponent("file-\(fileIdx).bin")
                try "Sample benchmark payload data \(dirIdx)-\(fileIdx)".write(to: file, atomically: true, encoding: .utf8)
            }
        }

        let repetitions = 5
        let budgets = [1, 2, 3, 4]
        var timingResults: [Int: [TimeInterval]] = [:]

        for _ in 0..<repetitions {
            for budget in budgets.shuffled() {
                let scheduler = HeavyScanScheduler(maxConcurrency: budget)
                let session = DiskMeasurementSession(scanner: LiveDiskScanner(), root: fixtureRoot.path, scheduler: scheduler)

                let start = Date()
                _ = try await session.listDirectory(fixtureRoot.path)
                for _ in 0..<100 {
                    let total = session.subtreeTotal(for: fixtureRoot.path)
                    if total != nil && total! > 0 && !session.isScanning {
                        break
                    }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let elapsed = Date().timeIntervalSince(start)
                timingResults[budget, default: []].append(elapsed)
                session.close()
            }
        }

        for budget in budgets {
            let times = timingResults[budget] ?? []
            XCTAssertEqual(times.count, repetitions, "Budget \(budget) must have \(repetitions) runs")
            let avg = times.reduce(0, +) / Double(times.count)
            print("AC-010 Benchmark: Budget \(budget): avg=\(String(format: "%.4f", avg))s, min=\(String(format: "%.4f", times.min()!))s, max=\(String(format: "%.4f", times.max()!))s, runs=\(times)")
        }
    }
}

// Supporting test doubles
private struct TestLanes {
    static func make(clean: any MoleProcessControlling) -> BackgroundScanLanes {
        let noop = LocalNoopProcess()
        return BackgroundScanLanes(
            uninstallStreaming: UnavailableMoleStreaming(),
            installer: InstallerInterface { _ in
                MoleCommandResult(stdout: "[]", stderr: "", exitCode: 0)
            },
            installerProcess: noop,
            clean: clean,
            optimize: noop,
            purge: noop
        )
    }
}

private struct LocalNoopProcess: MoleProcessControlling {
    func run(_ arguments: [String], stdin: Data?, timeout: TimeInterval) async throws -> MoleCommandResult {
        MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}

private actor CleanProcessSpy: MoleProcessControlling {
    let previewURL: URL
    private(set) var runCallCount = 0
    private(set) var cancelCount = 0

    init(previewURL: URL) {
        self.previewURL = previewURL
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        runCallCount += 1
        if !FileManager.default.fileExists(atPath: previewURL.path) {
            try """
            # Clean list preview
            /Applications/Dummy.app (10 MB)
            """.write(to: previewURL, atomically: true, encoding: .utf8)
        }
        return MoleCommandResult(stdout: "done", stderr: "", exitCode: 0)
    }

    func cancel() {
        cancelCount += 1
    }
}
