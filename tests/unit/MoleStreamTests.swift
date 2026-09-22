import Darwin
import Foundation
import XCTest
@testable import Zmole

final class MoleStreamTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-mole-stream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testStreamSplitsLinesAndFlushesEOFLine() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            printf 'first'
            sleep 0.05
            printf '\\nsecond\\r\\nthird'
            printf 'stderr-a' >&2
            printf 'stderr-b' >&2
            """
        )
        let bridge = try MoleBridge(executableURL: executable)
        let stream = await bridge.stream()
        var lines = [Data]()
        var stderr = Data()

        do {
            for try await event in stream {
                switch event {
                case let .stdoutLine(line):
                    lines.append(line)
                case let .stderr(data):
                    stderr.append(data)
                }
            }
        }

        XCTAssertEqual(lines, [Data("first".utf8), Data("second".utf8), Data("third".utf8)])
        XCTAssertEqual(stderr, Data("stderr-astderr-b".utf8))
    }

    func testRunDoesNotApplyStreamingLineLimit() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            head -c 1100000 /dev/zero | tr '\\0' a
            """
        )
        let bridge = try MoleBridge(executableURL: executable)

        let result = try await bridge.run(timeout: 10)

        XCTAssertEqual(result.stdout.utf8.count, 1_100_000)
    }

    func testStreamLongOutputDoesNotUseUnboundedAggregateBuffer() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            i=0
            while [ "$i" -lt 320 ]; do
                head -c 60000 /dev/zero | tr '\\0' x
                printf '\\n'
                i=$((i + 1))
            done
            """
        )
        let bridge = try MoleBridge(executableURL: executable)
        let stream = await bridge.stream()
        var lineCount = 0

        for try await event in stream {
            if case let .stdoutLine(line) = event {
                lineCount += 1
                XCTAssertEqual(line.count, 60_000)
            }
        }

        XCTAssertEqual(lineCount, 320)
    }

    func testStreamQueueOverflowIsExplicit() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            /usr/bin/yes x | /usr/bin/head -n 100000
            """
        )
        let bridge = try MoleBridge(executableURL: executable)
        let stream = await bridge.stream()
        try await waitUntilNotBusy(bridge)

        do {
            for try await _ in stream {
                // Deliberately consume only after the process has filled the queue.
            }
            XCTFail("expected queue overflow")
        } catch let error as MoleBridgeError {
            XCTAssertEqual(
                error,
                .outputLimitExceeded(channel: "event queue", limit: 256)
            )
        }
    }

    func testStreamLineOverflowIsExplicit() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            head -c 1048577 /dev/zero | tr '\\0' x
            """
        )
        let bridge = try MoleBridge(executableURL: executable)
        let stream = await bridge.stream()

        do {
            for try await _ in stream {}
            XCTFail("expected line overflow")
        } catch let error as MoleBridgeError {
            XCTAssertEqual(
                error,
                .outputLimitExceeded(channel: "stdout line", limit: 1_048_576)
            )
        }
    }

    func testCancelWaitsForTerminationBeforeBusyIsReleased() async throws {
        let pidFile = temporaryDirectory.appendingPathComponent("stream-pid")
        let executable = try makeExecutable(
            """
            #!/bin/sh
            printf '%s' "$$" > "\(pidFile.path)"
            sleep 30
            """
        )
        let bridge = try MoleBridge(executableURL: executable)
        let stream = await bridge.stream()
        let consumer = Task {
            for try await _ in stream {}
        }
        try await waitForFile(pidFile)

        await bridge.cancel()
        let isBusy = await bridge.isBusy
        XCTAssertFalse(isBusy)
        _ = await consumer.result

        let quickExecutable = try makeExecutable(
            """
            #!/bin/sh
            printf 'finished\\n'
            """
        )
        let quickBridge = try MoleBridge(executableURL: quickExecutable)
        let result = try await quickBridge.run(timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
    }

    private func makeExecutable(_ source: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(url.path, 0o755), 0)
        return url
    }

    private func waitForFile(_ url: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: url.path) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for \(url.path)")
    }

    private func waitUntilNotBusy(_ bridge: MoleBridge) async throws {
        for _ in 0..<500 {
            if await !bridge.isBusy { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for process")
    }
}
