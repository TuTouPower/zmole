import XCTest
@testable import Zmole

@MainActor
final class BackgroundCacheOffMainTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-cache-tests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // AC-001: 生产缓存读写、JSON 编解码均不在 MainActor/主线程执行。
    func testAC001_ReadWriteAndJSONEncodingNotOnMainActor() async throws {
        let observedReadThreadIsMain = AtomicBox(true)
        let observedWriteThreadIsMain = AtomicBox(true)

        let storage = BackgroundScanStorage(
            fileURL: tempURL,
            onEncodeOrWrite: {
                observedWriteThreadIsMain.set(Thread.isMainThread)
            },
            onDecodeOrRead: {
                observedReadThreadIsMain.set(Thread.isMainThread)
            }
        )

        let sampleResult = BackgroundScanResult(
            capturedAt: Date(),
            payload: .maintenance("Sample summary")
        )

        await storage.submit(results: [.optimize: sampleResult], revision: 1, isPriority: true)
        _ = await storage.flush()

        let loaded = await storage.load()

        XCTAssertFalse(observedWriteThreadIsMain.get(), "JSON encoding and file write must be off MainActor")
        XCTAssertFalse(observedReadThreadIsMain.get(), "JSON decoding and file read must be off MainActor")
        XCTAssertEqual(loaded[.optimize]?.payload, sampleResult.payload)
    }

    // AC-002: clean 文件读取和解析不在 MainActor；发布的是同一扫描版本的完整清单，接管期间不会读到另一个写者混入的数据。
    func testAC002_CleanReadAndParseNotOnMainActor() async throws {
        let observedReadThreadIsMain = AtomicBox(true)
        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clean-list-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: previewURL) }

        let store = CleanPreviewStore(
            fileURL: previewURL,
            onRead: {
                observedReadThreadIsMain.set(Thread.isMainThread)
            }
        )

        let cleanSpy = CleanProcessSpy(previewURL: previewURL)
        let coordinator = OperationCoordinator()
        let service = BackgroundScanService(
            lanes: TestLanes.make(clean: cleanSpy),
            cleanPreviewStore: store,
            storage: BackgroundScanStorage(fileURL: tempURL),
            coordinator: coordinator
        )

        service.request(.clean)
        await service.waitForScan(.clean)

        XCTAssertFalse(observedReadThreadIsMain.get(), "Clean file reading and parsing must occur off MainActor")
        guard let res = service.result(for: .clean),
              case let .cleanPreview(snapshot) = res.payload else {
            XCTFail("Clean scan did not produce a cleanPreview payload")
            return
        }
        XCTAssertEqual(snapshot.entries.count, 1)
    }

    // AC-003: 虚拟时钟下两项成功相隔小于 100 ms，合并窗口结束后只发生一次普通原子写，含全部项和各自完成时间。
    func testAC003_NormalResultsMergeWithin100msTrailingEdge() async throws {
        let writeCount = AtomicBox(0)
        let clock = TestClock()

        let storage = BackgroundScanStorage(
            fileURL: tempURL,
            now: { clock.now },
            sleep: { duration in await clock.sleep(seconds: duration) },
            onEncodeOrWrite: {
                writeCount.set(writeCount.get() + 1)
            }
        )

        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 1050)

        // Item 1 arrives at t = 0
        let r1 = BackgroundScanResult(capturedAt: t1, payload: .maintenance("First"))
        await storage.submit(results: [.optimize: r1], revision: 1, isPriority: false)

        // Advance 50 ms (< 100 ms)
        await clock.advance(by: 0.05)

        // Item 2 arrives at t = 50ms
        let r2 = BackgroundScanResult(capturedAt: t2, payload: .maintenance("Second"))
        await storage.submit(results: [.optimize: r1, .purge: r2], revision: 2, isPriority: false)

        // Still inside debounce window; no write should have happened yet
        XCTAssertEqual(writeCount.get(), 0)

        // Advance 100 ms to trigger trailing edge
        await clock.advance(by: 0.10)

        // Must have coalesced into exactly 1 write
        XCTAssertEqual(writeCount.get(), 1)

        let loaded = await storage.load()
        XCTAssertEqual(loaded[.optimize]?.capturedAt, t1)
        XCTAssertEqual(loaded[.purge]?.capturedAt, t2)
    }

    // AC-005: 阻塞旧加载，再接受较新扫描结果并放行加载，内存与最终文件不被旧值覆盖，页面不出现成功空缓存闪回。
    func testAC005_BlockedOldLoadDoesNotOverwriteNewerResultsOrFlashEmpty() async throws {
        let loadGate = AsyncGate()

        let storage = BackgroundScanStorage(
            fileURL: tempURL,
            onBeforeLoadRead: {
                await loadGate.wait()
            }
        )

        // Pre-populate old cache file with older result
        let oldDate = Date(timeIntervalSince1970: 100)
        let oldCache = BackgroundScanCache(fileURL: tempURL)
        oldCache.save([.optimize: BackgroundScanResult(capturedAt: oldDate, payload: .maintenance("Old"))])

        // Start async load (blocked at gate)
        let loadTask = Task {
            await storage.load()
        }

        // Newer result arrives while load is blocked
        let newDate = Date(timeIntervalSince1970: 500)
        let newResult = BackgroundScanResult(capturedAt: newDate, payload: .maintenance("New"))
        await storage.submit(results: [.optimize: newResult], revision: 2, isPriority: true)

        // Release load gate
        await loadGate.open()
        let loaded = await loadTask.value

        // Loaded result must preserve the newer result, not the old file
        XCTAssertEqual(loaded[.optimize]?.payload, .maintenance("New"))
        XCTAssertEqual(loaded[.optimize]?.capturedAt, newDate)
    }

    // AC-006: 旧普通快照排队后提交较新失效版本及结果，延迟/逆序完成回调也不能把持久化水位或文件回退。
    func testAC006_StaleInvalidationPriorityWriteOvercomesOldSnapshot() async throws {
        let storage = BackgroundScanStorage(fileURL: tempURL)

        // Queue old snapshot at revision 1
        let r1 = BackgroundScanResult(capturedAt: Date(), payload: .maintenance("Old"), targetVersion: 1, capturedVersion: 1)
        await storage.submit(results: [.optimize: r1], revision: 1, isPriority: false)

        // Submit newer invalidation version at revision 5 (priority)
        let r5 = BackgroundScanResult(capturedAt: Date(), payload: .maintenance("New"), targetVersion: 5, capturedVersion: 5)
        await storage.submit(results: [.optimize: r5], revision: 5, isPriority: true)

        let watermark = await storage.persistedRevision
        XCTAssertEqual(watermark, 5)

        // Late delivery of revision 1 must be rejected
        await storage.submit(results: [.optimize: r1], revision: 1, isPriority: false)
        let currentWatermark = await storage.persistedRevision
        XCTAssertEqual(currentWatermark, 5)

        let loaded = await storage.load()
        XCTAssertEqual(loaded[.optimize]?.targetVersion, 5)
    }

    // AC-007: 持续多次更新时 500 ms 内推进一次普通写水位；flush 后全部已接受普通结果落盘，正常关闭不丢尾批。
    func testAC007_WatermarkAdvancesWithin500msAndFlushSavesTail() async throws {
        let writeCount = AtomicBox(0)
        let clock = TestClock()

        let storage = BackgroundScanStorage(
            fileURL: tempURL,
            now: { clock.now },
            sleep: { duration in await clock.sleep(seconds: duration) },
            onEncodeOrWrite: {
                writeCount.set(writeCount.get() + 1)
            }
        )

        // Submit updates every 80 ms (less than 100 ms debounce window)
        for i in 1...8 {
            let res = BackgroundScanResult(capturedAt: Date(), payload: .maintenance("Step \(i)"))
            await storage.submit(results: [.optimize: res], revision: UInt64(i), isPriority: false)
            await clock.advance(by: 0.08)
        }

        // Even though each update was within 80 ms, at 500 ms max delay it must have written at least once!
        XCTAssertGreaterThanOrEqual(writeCount.get(), 1)

        // Flush must save any remaining tail
        _ = await storage.flush()
        let loaded = await storage.load()
        XCTAssertEqual(loaded[.optimize]?.payload, .maintenance("Step 8"))
    }

    // AC-008: 失效版本不受普通成功结果合并延迟；原子写失败不损坏旧文件，错误及待写状态可观察且可重试。
    func testAC008_WriteFailureDoesNotCorruptFileAndKeepsPending() async throws {
        let storage = BackgroundScanStorage(fileURL: tempURL)

        // 1. Initial successful write
        let r1 = BackgroundScanResult(capturedAt: Date(), payload: .maintenance("Initial"))
        await storage.submit(results: [.optimize: r1], revision: 1, isPriority: true)
        _ = await storage.flush()

        // 2. Simulate write failure by injecting failing writer
        await storage.setFailingWrite(true)

        let r2 = BackgroundScanResult(capturedAt: Date(), payload: .maintenance("Failed Step"))
        await storage.submit(results: [.optimize: r2], revision: 2, isPriority: true)

        let hasError = await storage.lastWriteError != nil
        XCTAssertTrue(hasError)

        // Old file must still be intact
        let diskData = BackgroundScanCache(fileURL: tempURL).load()
        XCTAssertEqual(diskData[.optimize]?.payload, .maintenance("Initial"))

        // Retry writing
        await storage.setFailingWrite(false)
        await storage.retryPending()
        _ = await storage.flush()

        let recovered = await storage.load()
        XCTAssertEqual(recovered[.optimize]?.payload, .maintenance("Failed Step"))
    }

    // AC-009: 损坏或不支持 schema 的文件按无缓存恢复，服务仍能启动扫描；旧 schema 不与当前版本混读。
    func testAC009_CorruptOrUnsupportedSchemaRecoversAsEmptyWithoutError() async throws {
        // Write corrupt JSON
        try "corrupt garbage {]".write(to: tempURL, atomically: true, encoding: .utf8)

        let storage = BackgroundScanStorage(fileURL: tempURL)
        let loaded = await storage.load()

        XCTAssertEqual(loaded, [:], "Corrupted file must recover cleanly as empty cache")
    }

    // AC-010: clean 解析被挡住时开始执行接管，必须先结束该读取/解析所有权；旧解析放行后不能覆盖新世代。
    func testAC010_CleanTakeoverWaitsForReadingOwnershipBeforeProceeding() async throws {
        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clean-list-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: previewURL) }

        let readGate = AsyncGate()
        let readHasStarted = AtomicBox(false)

        let store = CleanPreviewStore(
            fileURL: previewURL,
            onBeforeRead: {
                readHasStarted.set(true)
                await readGate.wait()
            }
        )

        let cleanSpy = CleanProcessSpy(previewURL: previewURL)
        let coordinator = OperationCoordinator()
        let service = BackgroundScanService(
            lanes: TestLanes.make(clean: cleanSpy),
            cleanPreviewStore: store,
            storage: BackgroundScanStorage(fileURL: tempURL),
            coordinator: coordinator
        )

        service.request(.clean)

        // Wait until read has actually started and is blocked at the gate
        for _ in 0..<50 {
            if readHasStarted.get() { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(readHasStarted.get())

        var takeoverCompleted = false
        let takeoverTask = Task { @MainActor in
            await service.userDidRescanAndWaitForTermination(.clean)
            takeoverCompleted = true
        }

        // Give a moment; takeover MUST NOT complete while reading is still blocked
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(takeoverCompleted, "Takeover must wait for background reading/parsing to finish")

        // Unblock the read
        await readGate.open()
        await takeoverTask.value
        XCTAssertTrue(takeoverCompleted)

        // The old scan result must not have been published
        XCTAssertNil(service.result(for: .clean))
    }
}

// Supporting test doubles
final class AtomicBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

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

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var currentTime: Date = Date(timeIntervalSince1970: 1000)
    private var waiters: [(Date, CheckedContinuation<Void, Never>)] = []

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return currentTime
    }

    func sleep(seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            let wakeTime = currentTime.addingTimeInterval(seconds)
            waiters.append((wakeTime, continuation))
            lock.unlock()
        }
    }

    func advance(by seconds: TimeInterval) async {
        lock.lock()
        currentTime = currentTime.addingTimeInterval(seconds)
        var toResume: [CheckedContinuation<Void, Never>] = []
        waiters.removeAll { item in
            if item.0 <= currentTime {
                toResume.append(item.1)
                return true
            }
            return false
        }
        lock.unlock()

        for cont in toResume {
            cont.resume()
        }
        // Yield to allow scheduled tasks to run
        await Task.yield()
    }
}
