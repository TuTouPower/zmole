import Darwin
import Foundation

enum MoleBundleLocator {
    static let relativeExecutablePath = "mole/mole"

    static func executableURL(in bundle: Bundle) throws -> URL {
        guard let resourceURL = bundle.resourceURL else {
            throw MoleBridgeError.executableNotFound(relativeExecutablePath)
        }

        let executableURL = resourceURL.appendingPathComponent(relativeExecutablePath)
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw MoleBridgeError.executableNotFound(executableURL.path)
        }
        return executableURL
    }
}

public actor MoleBridge {
    private let executableURL: URL
    private var activeRunner: MoleProcessRunner?

    public init(bundle: Bundle = .main, executableURL: URL? = nil) throws {
        if let executableURL {
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                throw MoleBridgeError.executableNotFound(executableURL.path)
            }
            self.executableURL = executableURL
        } else {
            self.executableURL = try MoleBundleLocator.executableURL(in: bundle)
        }
    }

    public var isBusy: Bool {
        activeRunner != nil
    }

    public func run(
        _ arguments: [String] = [],
        stdin: Data? = nil,
        timeout: TimeInterval = 30
    ) async throws -> MoleCommandResult {
        guard activeRunner == nil else {
            throw MoleBridgeError.busy
        }

        let runner = MoleProcessRunner(
            executableURL: executableURL,
            arguments: arguments,
            stdin: stdin,
            timeout: timeout
        )
        activeRunner = runner
        defer { activeRunner = nil }
        return try await runner.run()
    }

    public func version(timeout: TimeInterval = 10) async throws -> String {
        let result = try await run(["--version"], timeout: timeout)
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw MoleBridgeError.emptyOutput
        }
        return version
    }

    public func cancel() {
        activeRunner?.cancel()
    }
}

private final class MoleProcessRunner: @unchecked Sendable {
    private let process: Process
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe = Pipe()
    private let stdin: Data?
    private let timeout: TimeInterval
    private let lock = NSLock()

    private var continuation: CheckedContinuation<MoleCommandResult, Error>?
    private var finished = false
    private var cancelRequested = false
    private var timeoutRequested = false
    private var processStarted = false
    private var processGroupConfigured = false
    private var timeoutWorkItem: DispatchWorkItem?

    init(executableURL: URL, arguments: [String], stdin: Data?, timeout: TimeInterval) {
        process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        self.stdin = stdin
        self.timeout = max(0.01, timeout)
    }

    func run() async throws -> MoleCommandResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                begin(continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let shouldTerminate = processStarted && !finished
        let shouldFinishBeforeStart = !processStarted && continuation != nil && !finished
        lock.unlock()

        if shouldFinishBeforeStart {
            finish(.failure(MoleBridgeError.cancelled))
        } else if shouldTerminate {
            terminateProcessGroup()
        }
    }

    private func begin(_ continuation: CheckedContinuation<MoleCommandResult, Error>) {
        lock.lock()
        if finished || cancelRequested {
            finished = true
            lock.unlock()
            continuation.resume(throwing: MoleBridgeError.cancelled)
            return
        }
        self.continuation = continuation
        processStarted = true
        lock.unlock()

        process.terminationHandler = { [weak self] _ in
            self?.processDidTerminate()
        }

        do {
            try process.run()
        } catch {
            finish(.failure(MoleBridgeError.launchFailed(error.localizedDescription)))
            return
        }

        processGroupConfigured = setpgid(process.processIdentifier, process.processIdentifier) == 0

        if isCancellationRequested {
            terminateProcessGroup()
        } else {
            scheduleTimeout()
        }

        if let stdin {
            stdinPipe.fileHandleForWriting.write(stdin)
        }
        stdinPipe.fileHandleForWriting.closeFile()
    }

    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.timeoutAndTerminate()
        }
        lock.lock()
        timeoutWorkItem = workItem
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeout,
            execute: workItem
        )
    }

    private func timeoutAndTerminate() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        timeoutRequested = true
        lock.unlock()
        terminateProcessGroup()
    }

    private func terminateProcessGroup() {
        let pid = process.processIdentifier
        guard pid > 0, process.isRunning else { return }

        if processGroupConfigured {
            _ = kill(-pid, SIGTERM)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.process.isRunning else { return }
                _ = kill(-pid, SIGKILL)
            }
        } else {
            process.terminate()
        }
    }

    private func processDidTerminate() {
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let result = MoleCommandResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            exitCode: process.terminationStatus
        )

        lock.lock()
        let timedOut = timeoutRequested
        let cancelled = cancelRequested
        lock.unlock()

        if timedOut {
            finish(.failure(MoleBridgeError.timedOut))
        } else if cancelled {
            finish(.failure(MoleBridgeError.cancelled))
        } else if result.exitCode == 0 {
            finish(.success(result))
        } else {
            finish(.failure(MoleBridgeError.commandFailed(result)))
        }
    }

    private func finish(_ outcome: Result<MoleCommandResult, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        timeoutWorkItem?.cancel()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return }
        switch outcome {
        case let .success(result):
            continuation.resume(returning: result)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
