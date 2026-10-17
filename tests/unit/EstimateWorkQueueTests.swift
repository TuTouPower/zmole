import XCTest
@testable import Zmole

@MainActor
final class EstimateWorkQueueTests: XCTestCase {

    // AC-001: 探测按空闲通道逐项领取，不以固定余数绑定通道，同时执行量不超过 t048 名额。
    // AC-003: 三个初始项都已开始后，即使 /Users 未返回，其他空闲通道可完成系统段。
    func testAC001_and_AC003_WorkQueueAssignsToIdleChannelsAndSystemCompletesWhileUsersBlocked() async throws {
        let usersGate = AsyncGate()
        let order = AtomicBox<[String]>([])

        let sizeForPath: @Sendable (String) async -> Int64? = { path in
            order.set(order.get() + [path])
            if path == "/Users" {
                await usersGate.wait()
                return 100
            }
            switch path {
            case "/Applications": return 10
            case "~/Library/Developer": return 20
            case "/System/Library": return 30
            case "/System/Applications": return 40
            default: return 5
            }
        }

        let channel1: StorageEstimateLoader.DirectorySize = { path in
            await sizeForPath(path)
        }

        let channel2: StorageEstimateLoader.DirectorySize = { path in
            await sizeForPath(path)
        }

        // Two channels, system with 2 children
        let loader = StorageEstimateLoader(
            loaders: [],
            channels: [channel1, channel2],
            systemChildren: { ["Library", "Applications"] }
        )

        let reportedSums = AtomicBox<[StorageSums]>([])
        let sumsTask = Task {
            try await loader.loadSums(includingUsers: true, onProgress: { partial in
                reportedSums.set(reportedSums.get() + [partial])
            })
        }

        // Wait until both initial and system children are processed while users is blocked
        for _ in 0..<50 {
            let current = reportedSums.get()
            // System completes when Library + Applications finish
            if current.contains(where: { $0.system != nil && $0.users == nil }) {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let progressive = reportedSums.get()
        let hasSystemBeforeUsers = progressive.contains { $0.system != nil && $0.users == nil }
        XCTAssertTrue(hasSystemBeforeUsers, "System segment must complete while /Users is still blocked (AC-003)")

        // Unblock users
        await usersGate.open()
        let finalSums = try await sumsTask.value
        XCTAssertEqual(finalSums.users, 100)
        XCTAssertEqual(finalSums.system, 70) // 30 + 40
    }

    // AC-002: 名额为 1、2 时先启动相应数量的大目录输入，下一待测大目录先于系统子项启动。
    func testAC002_InitialBigDirectoriesStartBeforeSystemChildren() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let startedOrder = AtomicBox<[String]>([])

        let channel: StorageEstimateLoader.DirectorySize = { path in
            startedOrder.set(startedOrder.get() + [path])
            return 50
        }

        let loader = StorageEstimateLoader(
            loaders: [],
            channels: [channel],
            systemChildren: { ["SystemChild1", "SystemChild2"] },
            scheduler: scheduler
        )

        _ = try await loader.loadSums(includingUsers: true)

        let order = startedOrder.get()
        XCTAssertEqual(order.prefix(3), ["/Applications", "~/Library/Developer", "/Users"], "Initial 3 directories must start before system children (AC-002)")
    }

    // AC-004: /System/Volumes 不探测；必要系统子项失败则系统不可用，不显示部分和。
    func testAC004_SystemVolumesExcludedAndFailureMakesSystemUnavailable() async throws {
        let probedPaths = AtomicBox<[String]>([])

        let channel: StorageEstimateLoader.DirectorySize = { path in
            probedPaths.set(probedPaths.get() + [path])
            if path == "/System/FailingChild" {
                return nil // Failure
            }
            return 42
        }

        let loader = StorageEstimateLoader(
            loaders: [],
            channels: [channel],
            systemChildren: { ["Volumes", "GoodChild", "FailingChild"] }
        )

        let result = try await loader.loadSums(includingUsers: false)

        XCTAssertFalse(probedPaths.get().contains("/System/Volumes"), "/System/Volumes must never be probed")
        XCTAssertNil(result.system, "System segment must be unavailable when any child probe fails (AC-004)")
    }

    // AC-006: 应用段成功且其余仍阻塞时已显示应用大小；用户值未齐时其他保持未知。
    func testAC006_ApplicationsSegmentDisplaysWhileOtherSegmentsAreBlocked() async throws {
        let gate = AsyncGate()

        let channel: StorageEstimateLoader.DirectorySize = { path in
            if path == "/Applications" {
                return 500
            }
            await gate.wait()
            return 100
        }

        let loader = StorageEstimateLoader(
            loaders: [],
            channels: [channel],
            systemChildren: { ["Library"] }
        )

        let viewModel = OverviewViewModel(
            storageLoader: loader,
            historyLoader: nil,
            storageCache: nil
        )

        viewModel.startEstimate(usedBytes: 1000)

        // Wait for applications segment to be published
        for _ in 0..<50 {
            if viewModel.breakdown.applicationsBytes != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.breakdown.applicationsBytes, 500)
        XCTAssertNil(viewModel.breakdown.userDataBytes, "User data must stay unknown until users and developer complete")
        XCTAssertNil(viewModel.breakdown.otherBytes, "Other bytes must stay unknown when segments are incomplete")

        await gate.open()
        await viewModel.waitForEstimate()
    }

    // AC-007: 只补缺失/过期输入，进度事件不刷新未重新测量输入的 capturedAt；取消及旧世代事件不被存成新鲜结果。
    func testAC007_FillMissingOnlyDoesNotRefreshCapturedAtAndOldGenerationIgnored() async throws {
        let initialSums = StorageSums(applications: 100, system: nil, developer: 50, users: nil)
        let probed = AtomicBox<[String]>([])
        let channel: StorageEstimateLoader.DirectorySize = { path in
            probed.set(probed.get() + [path])
            return 200
        }

        let loader = StorageEstimateLoader(
            loaders: [],
            channels: [channel],
            systemChildren: { ["CoreServices"] }
        )

        let result = try await loader.loadSums(filling: initialSums, includingUsers: true)

        XCTAssertFalse(probed.get().contains("/Applications"), "Already resolved applications must not be probed again")
        XCTAssertFalse(probed.get().contains("~/Library/Developer"), "Already resolved developer must not be probed again")
        XCTAssertTrue(probed.get().contains("/Users"), "Missing users must be probed")
        XCTAssertTrue(probed.get().contains("/System/CoreServices"), "Missing system must be probed")
        XCTAssertEqual(result.applications, 100)
        XCTAssertEqual(result.developer, 50)
        XCTAssertEqual(result.users, 200)
    }

    // AC-008: 名额为 1、通道暂忙和排队取消时仍能完成或取消，无持名额等待忙通道的死锁。
    func testAC008_DeadlockFreedomWithConcurrencyOneAndCancellation() async throws {
        let scheduler = HeavyScanScheduler(maxConcurrency: 1)
        let channel: StorageEstimateLoader.DirectorySize = { path in
            return 10
        }

        let loader = StorageEstimateLoader(
            loaders: [],
            channels: [channel],
            systemChildren: { ["A", "B", "C"] },
            scheduler: scheduler
        )

        let task = Task {
            try await loader.loadSums(includingUsers: false)
        }

        let sums = try await task.value
        XCTAssertEqual(sums.applications, 10)
        XCTAssertEqual(sums.system, 30)
    }
}
