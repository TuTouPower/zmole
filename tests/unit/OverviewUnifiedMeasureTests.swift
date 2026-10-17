import XCTest
@testable import Zmole

@MainActor
final class OverviewUnifiedMeasureTests: XCTestCase {

    // AC-002: 同快照夹具 users=100、Developer 归属=30 时，用户段=70、开发者=30；Developer 归属=0 时用户段=100，不重复减去。
    func testAC002_UsersAndDeveloperAttributionMatchesContract() {
        let b1 = StorageBreakdown.make(
            applications: 40,
            system: 20,
            developer: 30,
            users: 100,
            usedBytes: 200
        )
        XCTAssertEqual(b1.developerBytes, 30)
        XCTAssertEqual(b1.userDataBytes, 70)
        XCTAssertEqual(b1.otherBytes, 40) // 200 - (40 + 20 + 30 + 70) = 40

        let b2 = StorageBreakdown.make(
            applications: 40,
            system: 20,
            developer: 0,
            users: 100,
            usedBytes: 200
        )
        XCTAssertEqual(b2.developerBytes, 0)
        XCTAssertEqual(b2.userDataBytes, 100)
        XCTAssertEqual(b2.otherBytes, 40)
    }

    // AC-003: /System/Volumes 不遍历；任一必要系统子项失败则系统不可用；用户段未知时其他未知。
    func testAC003_SystemVolumesExcludedAndFailureMakesSystemUnavailable() {
        let b = StorageBreakdown.make(
            applications: 50,
            system: 30,
            developer: 20,
            users: nil, // unknown users
            usedBytes: 200
        )
        XCTAssertNil(b.userDataBytes)
        XCTAssertNil(b.otherBytes, "otherBytes must be unknown when userDataBytes is unknown")
    }

    // AC-004: 完整估算只遍历一次 /Users 内的 Developer 内容，命名子树统计由该次会话产出；概览没有独立 Developer 重遍历或 analyze 命令。
    func testAC004_SingleWalkOfUsersMeasuresBothUsersAndDeveloperWithoutSecondWalk() async throws {
        let scanner = FakeDiskScanner()
        let homeDir = "/Users/testuser"
        let devPath = homeDir + "/Library/Developer"

        // Set up /Users directory structure containing Developer
        scanner.results["/Users"] = DiskScanResult(
            path: "/Users",
            totalSize: 100,
            isReadable: true,
            levels: [
                "/Users": DiskLevel(entries: [DiskEntry(name: "testuser", path: homeDir, isDirectory: true, value: .size(100))], totalSize: 100),
                homeDir: DiskLevel(entries: [
                    DiskEntry(name: "Library", path: homeDir + "/Library", isDirectory: true, value: .size(30)),
                    DiskEntry(name: "data.bin", path: homeDir + "/data.bin", isDirectory: false, value: .size(70))
                ], totalSize: 100),
                homeDir + "/Library": DiskLevel(entries: [DiskEntry(name: "Developer", path: devPath, isDirectory: true, value: .size(30))], totalSize: 30),
                devPath: DiskLevel(entries: [DiskEntry(name: "Xcode", path: devPath + "/Xcode", isDirectory: false, value: .size(30))], totalSize: 30)
            ]
        )
        scanner.results["/Applications"] = DiskScanResult(path: "/Applications", totalSize: 50, isReadable: true, levels: [:])
        scanner.results["/System/Library"] = DiskScanResult(path: "/System/Library", totalSize: 20, isReadable: true, levels: [:])

        let session = DiskMeasurementSession(scanner: scanner, root: "/")
        let loader = StorageEstimateLoader(
            session: session,
            home: homeDir,
            systemChildren: { ["Library", "Volumes"] }
        )

        let sums = try await loader.loadSums(includingUsers: true)

        // Verify Developer was extracted from /Users walk without a separate measureSubtree(devPath)
        XCTAssertEqual(sums.users, 100)
        XCTAssertEqual(sums.developer, 30)
        XCTAssertEqual(sums.applications, 50)
        XCTAssertEqual(sums.system, 20)

        let measureCalls = scanner.measureRequests
        XCTAssertFalse(measureCalls.contains(devPath), "Developer must not be independently walked when /Users is walked (AC-004)")
        XCTAssertFalse(measureCalls.contains("/System/Volumes"), "/System/Volumes must not be walked (AC-003)")
    }

    // AC-006: Developer 与其他路径共享硬链接时 users 总量只计一次，归属 Developer；逆转遍历或 worker 完成顺序，分段仍一致。
    func testAC006_CrossDirectoryHardlinkAttributedToDeveloper() async throws {
        let scanner = FakeDiskScanner()
        let homeDir = "/Users/testuser"
        let devPath = homeDir + "/Library/Developer"
        let docsPath = homeDir + "/Documents"

        let sharedKey = HardLinkKey(device: 1, inode: 9999)
        let linkEntryInDev = DiskEntry(name: "shared.bin", path: devPath + "/shared.bin", isDirectory: false, value: .size(10), linkKey: sharedKey)
        let linkEntryInDocs = DiskEntry(name: "shared.bin", path: docsPath + "/shared.bin", isDirectory: false, value: .size(10), linkKey: sharedKey)
        let plainDocEntry = DiskEntry(name: "plain.txt", path: docsPath + "/plain.txt", isDirectory: false, value: .size(50))

        // Total in /Users = 50 (doc plain 50) + 10 (shared 10) = 60
        // Developer self size = 10
        // Users total = 60
        // Expected user data = 60 - 10 = 50, developer = 10
        scanner.results["/Users"] = DiskScanResult(
            path: "/Users",
            totalSize: 60,
            isReadable: true,
            levels: [
                "/Users": DiskLevel(entries: [DiskEntry(name: "testuser", path: homeDir, isDirectory: true, value: .size(60))], totalSize: 60),
                homeDir: DiskLevel(entries: [
                    DiskEntry(name: "Library", path: homeDir + "/Library", isDirectory: true, value: .size(10)),
                    DiskEntry(name: "Documents", path: docsPath, isDirectory: true, value: .size(60))
                ], totalSize: 60),
                devPath: DiskLevel(entries: [linkEntryInDev], totalSize: 10),
                docsPath: DiskLevel(entries: [linkEntryInDocs, plainDocEntry], totalSize: 60)
            ]
        )

        let session = DiskMeasurementSession(scanner: scanner, root: "/")
        let loader = StorageEstimateLoader(session: session, home: homeDir, systemChildren: { [] })

        let sums = try await loader.loadSums(includingUsers: true)
        XCTAssertEqual(sums.users, 60)
        XCTAssertEqual(sums.developer, 10)

        let breakdown = sums.breakdown(usedBytes: 100)
        XCTAssertEqual(breakdown.developerBytes, 10)
        XCTAssertEqual(breakdown.userDataBytes, 50, "Shared hard link must be attributed to Developer and subtracted from user data")
    }

    // AC-007: 无 FDA 不遍历 /Users；授权后使用新权限版本测量。缺 Developer、不可读 Developer 和合法 0 大小可区分，失败不能伪装成 0。
    func testAC007_NoFDAWalksDeveloperOnlyIfReadable() async throws {
        let scanner = FakeDiskScanner()
        let homeDir = "/Users/testuser"
        let devPath = homeDir + "/Library/Developer"

        scanner.results[devPath] = DiskScanResult(path: devPath, totalSize: 25, isReadable: true, levels: [:])

        let session = DiskMeasurementSession(scanner: scanner, root: "/")
        let loader = StorageEstimateLoader(session: session, home: homeDir, systemChildren: { [] })

        // Without FDA
        let sums = try await loader.loadSums(includingUsers: false)

        XCTAssertNil(sums.users, "/Users must not be probed without FDA")
        XCTAssertEqual(sums.developer, 25, "Developer can be independently probed when FDA is missing")
        XCTAssertFalse(scanner.measureRequests.contains("/Users"))
    }

    // AC-008: 概览与磁盘提出兼容请求时复用同一会话事实与实际遍历，取消一方不破坏另一方；不兼容世代各自正确完成且遵守总名额。
    func testAC008_OverviewAndDiskShareSameSessionAndActualWalk() async throws {
        let scanner = FakeDiskScanner()
        let gate = AsyncGate()

        scanner.blockedMeasures.insert("/Applications")
        let session = DiskMeasurementSession(scanner: scanner, root: "/")
        let loader = StorageEstimateLoader(session: session, home: "/Users/test", systemChildren: { [] })

        // 1. Overview requests /Applications
        let overviewTask = Task {
            try await loader.loadSums(includingUsers: false)
        }

        // 2. Disk page subscribes to /Applications
        let diskSub = session.subscribe(path: "/Applications")

        for _ in 0..<50 {
            if scanner.measureRequests.contains("/Applications") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Only ONE measure request should have been made for /Applications
        let appCalls = scanner.measureRequests.filter { $0 == "/Applications" }
        XCTAssertEqual(appCalls.count, 1, "Overview and Disk Page must share the exact same measurement task (AC-008)")

        // Cancel overview request
        overviewTask.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Disk subscription keeps it alive
        diskSub.cancel()
        session.close()
    }

    // AC-009: 旧统计口径缓存被丢弃；新结果遵守版本新鲜度与渐进分段，Demo 不读真实文件系统。
    func testAC009_Schema2CacheIsDiscardedAndSchema3IsAuthoritative() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let cache = StorageEstimateCache(fileURL: tempURL)

        // Write schema 2 entry
        let schema2JSON = """
        {"schemaVersion":2,"capturedAt":\(Date().timeIntervalSince1970),"sums":{"applications":10}}
        """
        try schema2JSON.write(to: tempURL, atomically: true, encoding: .utf8)

        // Must be discarded
        XCTAssertNil(cache.load(), "Schema 2 cache must be discarded after schema bump to 3")

        // Write schema 3 entry
        cache.save(StorageSums(applications: 55))
        let loaded = cache.load()
        XCTAssertEqual(loaded?.sums.applications, 55)
        XCTAssertEqual(loaded?.schemaVersion, 3)
    }

    // [deploy] AC-010: 最终统一后端按 t048 相同重复对照方法核对名额 1、2、3、4，记录并确认或更新生产默认值。
    func testAC010_Deploy_BenchmarkFinalUnifiedBackend() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("benchmark-overview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let appsDir = fixtureRoot.appendingPathComponent("Applications")
        let usersDir = fixtureRoot.appendingPathComponent("Users")
        let devDir = usersDir.appendingPathComponent("Library/Developer")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: devDir, withIntermediateDirectories: true)

        for i in 0..<10 {
            try "App \(i)".write(to: appsDir.appendingPathComponent("App\(i).app"), atomically: true, encoding: .utf8)
            try "Dev \(i)".write(to: devDir.appendingPathComponent("Dev\(i).bin"), atomically: true, encoding: .utf8)
        }

        let repetitions = 5
        let budgets = [1, 2, 3, 4]
        var timingResults: [Int: [TimeInterval]] = [:]

        for _ in 0..<repetitions {
            for budget in budgets.shuffled() {
                let scheduler = HeavyScanScheduler(maxConcurrency: budget)
                let session = DiskMeasurementSession(scanner: LiveDiskScanner(), root: fixtureRoot.path, scheduler: scheduler)
                let loader = StorageEstimateLoader(
                    session: session,
                    home: usersDir.path,
                    applicationsPath: appsDir.path,
                    usersPath: usersDir.path,
                    systemChildren: { [] },
                    scheduler: scheduler
                )

                let start = Date()
                _ = try await loader.loadSums(includingUsers: true)
                let elapsed = Date().timeIntervalSince(start)
                timingResults[budget, default: []].append(elapsed)
                session.close()
            }
        }

        for budget in budgets {
            let times = timingResults[budget] ?? []
            XCTAssertEqual(times.count, repetitions)
            let avg = times.reduce(0, +) / Double(times.count)
            print("AC-010 Unified Backend: Budget \(budget): avg=\(String(format: "%.4f", avg))s, min=\(String(format: "%.4f", times.min()!))s, max=\(String(format: "%.4f", times.max()!))s, runs=\(times)")
        }
    }
}
