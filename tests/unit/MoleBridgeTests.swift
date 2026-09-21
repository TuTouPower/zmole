import Darwin
import Foundation
import XCTest
@testable import Zmole

final class MoleBridgeTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-mole-bridge-\(UUID().uuidString)", isDirectory: true)
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

    func testVersionReturnsOutputFromInjectedExecutable() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            printf 'Mole version 1.55.0\\n'
            """
        )
        let bridge = try MoleBridge(executableURL: executable)

        let version = try await bridge.version()

        XCTAssertEqual(version, "Mole version 1.55.0")
    }

    func testRunCapturesArgumentsWorkingDirectoryAndStdin() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            printf 'args=%s,%s\\n' "$1" "$2"
            printf 'pwd=%s\\n' "$PWD"
            cat
            """
        )
        let bridge = try MoleBridge(executableURL: executable)

        let result = try await bridge.run(
            ["alpha", "beta"],
            stdin: Data("stdin-bytes\n".utf8)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("args=alpha,beta"))
        let logicalPath = temporaryDirectory.path
        let physicalPath = logicalPath.hasPrefix("/private/")
            ? logicalPath
            : "/private\(logicalPath)"
        XCTAssertTrue(
            result.stdout.contains("pwd=\(logicalPath)")
                || result.stdout.contains("pwd=\(physicalPath)"),
            result.stdout
        )
        XCTAssertTrue(result.stdout.contains("stdin-bytes"))
    }

    func testNonZeroExitReturnsDisplayableError() async throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            printf 'fixture failed\\n' >&2
            exit 7
            """
        )
        let bridge = try MoleBridge(executableURL: executable)

        do {
            _ = try await bridge.run()
            XCTFail("expected commandFailed")
        } catch let error as MoleBridgeError {
            guard case let .commandFailed(result) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(result.exitCode, 7)
            XCTAssertEqual(result.stderr, "fixture failed\n")
            XCTAssertNotNil(error.errorDescription)
        }
    }

    func testBusyRunDoesNotStartSecondProcess() async throws {
        let countFile = temporaryDirectory.appendingPathComponent("count")
        let executable = try makeExecutable(
            """
            #!/bin/sh
            count=0
            if [ -f "\(countFile.path)" ]; then count=$(cat "\(countFile.path)"); fi
            printf '%s' $((count + 1)) > "\(countFile.path)"
            sleep 2
            """
        )
        let bridge = try MoleBridge(executableURL: executable)
        let firstRun = Task { try await bridge.run(timeout: 5) }

        try await waitForFile(countFile)
        do {
            _ = try await bridge.run(timeout: 5)
            XCTFail("expected busy")
        } catch let error as MoleBridgeError {
            XCTAssertEqual(error, .busy)
        }

        await bridge.cancel()
        _ = try? await firstRun.value
        XCTAssertEqual(try String(contentsOf: countFile), "1")
    }

    func testTimeoutStopsProcess() async throws {
        let pidFile = temporaryDirectory.appendingPathComponent("pid")
        let executable = try makeExecutable(
            """
            #!/bin/sh
            printf '%s' "$$" > "\(pidFile.path)"
            sleep 30
            """
        )
        let bridge = try MoleBridge(executableURL: executable)

        let run = Task { try await bridge.run(timeout: 2) }
        try await waitForFile(pidFile)

        do {
            _ = try await run.value
            XCTFail("expected timeout")
        } catch let error as MoleBridgeError {
            XCTAssertEqual(error, .timedOut)
        }

        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile)))
        XCTAssertNotEqual(kill(pid, 0), 0)
    }

    func testCancelStopsProcessAndItsProcessGroup() async throws {
        let pidFile = temporaryDirectory.appendingPathComponent("cancel-pid")
        let executable = try makeExecutable(
            """
            #!/bin/sh
            printf '%s' "$$" > "\(pidFile.path)"
            sleep 30
            """
        )
        let bridge = try MoleBridge(executableURL: executable)
        let run = Task { try await bridge.run(timeout: 10) }

        try await waitForFile(pidFile)
        await bridge.cancel()

        do {
            _ = try await run.value
            XCTFail("expected cancellation")
        } catch let error as MoleBridgeError {
            XCTAssertEqual(error, .cancelled)
        }

        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile)))
        XCTAssertNotEqual(kill(pid, 0), 0)
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
}
