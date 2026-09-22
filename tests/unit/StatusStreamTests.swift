import Foundation
import XCTest
@testable import Zmole

final class StatusStreamTests: XCTestCase {
    func test首帧缺少慢字段仍可解码并显式标记进程过期() throws {
        let json = #"{"health_score":100,"cpu":{"usage":0},"memory":{},"disks":[],"disk_io":{"read_rate":0,"write_rate":0}}"#
        let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: Data(json.utf8))

        XCTAssertTrue(snapshot.healthScoreAvailable)
        XCTAssertTrue(snapshot.cpu.usageAvailable)
        XCTAssertTrue(snapshot.diskIO?.readRate == 0)
        XCTAssertNil(snapshot.topProcesses)
        XCTAssertTrue(snapshot.processStale)
        XCTAssertFalse(snapshot.disksAvailable)
    }

    func test零值是有效采样而不是未知() throws {
        let json = #"{"health_score":0,"cpu":{"usage":0},"memory":{"used":0,"total":0,"used_percent":0},"disks":[{"mount":"/","used":0,"total":0,"used_percent":0}],"network":[{"name":"en0","rx_rate_mbs":0,"tx_rate_mbs":0}]}"#
        let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: Data(json.utf8))

        XCTAssertTrue(snapshot.healthScoreAvailable)
        XCTAssertTrue(snapshot.cpu.usageAvailable)
        XCTAssertEqual(snapshot.memory.usedPercent, 0)
        XCTAssertEqual(snapshot.disks.first?.usedPercent, 0)
        XCTAssertEqual(snapshot.networkTotal?.rxRateMBs, 0)
        XCTAssertEqual(snapshot.networkTotal?.txRateMBs, 0)
    }

    func test网络聚合忽略会镜像流量的虚拟接口() throws {
        let json = #"{"network":[{"name":"en0","rx_rate_mbs":2,"tx_rate_mbs":3},{"name":"utun0","rx_rate_mbs":9,"tx_rate_mbs":11},{"name":"lo0","rx_rate_mbs":4,"tx_rate_mbs":5}]}"#
        let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.networkTotal?.rxRateMBs, 2)
        XCTAssertEqual(snapshot.networkTotal?.txRateMBs, 3)
    }

    func test状态服务共享一个流且趋势有界() async throws {
        let streaming = FakeStatusStreaming()
        let service = StatusWatchService(streaming: streaming, historyLimit: 2)
        let first = await service.subscribe()
        let second = await service.subscribe()
        await service.start()
        await streaming.waitForStream()

        let firstUpdate = Task { try await first.firstUpdate() }
        let secondUpdate = Task { try await second.firstUpdate() }
        await streaming.emit(sample(collectedAt: "2026-09-21T13:07:56.625037+08:00", rx: 1))
        let updateA = try await firstUpdate.value
        let updateB = try await secondUpdate.value

        XCTAssertEqual(updateA.snapshot, updateB.snapshot)
        XCTAssertTrue(updateA.diskIOIsWarming)
        let initialCallCount = await streaming.streamCallCount
        XCTAssertEqual(initialCallCount, 1)

        for index in 2...4 {
            await streaming.emit(
                sample(
                    collectedAt: "2026-09-21T13:07:5\(index).625037+08:00",
                    rx: Double(index),
                    readRate: Double(index * 10)
                )
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let seriesCount = await service.series.count
        XCTAssertEqual(seriesCount, 2)
        let latestPoint = await service.series.last
        XCTAssertFalse(latestPoint?.diskIOIsWarming ?? true)
        XCTAssertEqual(latestPoint?.diskReadRate, 40)
        await service.stop()
    }

    func test断流报告错误且不会自动重启() async throws {
        let streaming = FakeStatusStreaming()
        let service = StatusWatchService(streaming: streaming)
        let stream = await service.subscribe()
        await service.start()
        await streaming.waitForStream()
        await streaming.finish(with: StatusWatchError.disconnected)

        do {
            for try await _ in stream {}
            XCTFail("expected disconnected error")
        } catch let error as StatusWatchError {
            XCTAssertEqual(error, .disconnected)
        }
        let firstCallCount = await streaming.streamCallCount
        XCTAssertEqual(firstCallCount, 1)
        // A terminal stream also terminates its subscriber. Manual recovery
        // creates a fresh subscription before asking the service to retry.
        let retryStream = await service.subscribe()
        await service.retry()
        await streaming.waitForStream(count: 2)
        let secondCallCount = await streaming.streamCallCount
        XCTAssertEqual(secondCallCount, 2)
        _ = retryStream
        await service.stop()
    }

    private func sample(collectedAt: String, rx: Double, readRate: Double = 0) -> Data {
        let json = "{\"collected_at\":\"\(collectedAt)\",\"health_score\":100,\"cpu\":{\"usage\":12},\"memory\":{\"used\":1,\"total\":2,\"used_percent\":50},\"disks\":[],\"disk_io\":{\"read_rate\":\(readRate),\"write_rate\":0},\"network\":[{\"name\":\"en0\",\"rx_rate_mbs\":\(rx),\"tx_rate_mbs\":0}],\"process_stale\":false}"
        return Data(json.utf8)
    }
}

private extension AsyncThrowingStream where Element == StatusWatchUpdate, Failure == Error {
    func firstUpdate() async throws -> StatusWatchUpdate {
        for try await update in self { return update }
        throw StatusWatchError.disconnected
    }
}

private actor FakeStatusStreaming: MoleStreaming {
    private var continuations: [AsyncThrowingStream<MoleOutputEvent, Error>.Continuation] = []
    private(set) var streamCallCount = 0

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        streamCallCount += 1
        var continuation: AsyncThrowingStream<MoleOutputEvent, Error>.Continuation!
        let stream = AsyncThrowingStream<MoleOutputEvent, Error> { continuation = $0 }
        continuations.append(continuation)
        return stream
    }

    func emit(_ data: Data) {
        continuations.last?.yield(.stdoutLine(data))
    }

    func finish(with error: Error? = nil) {
        if let error {
            continuations.last?.finish(throwing: error)
        } else {
            continuations.last?.finish()
        }
    }

    func waitForStream(count: Int = 1) async {
        while streamCallCount < count {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
