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

protocol MoleCommandRunning {
    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult
}

protocol MoleProcessControlling: MoleCommandRunning {
    func cancel() async
}

public enum MoleOutputEvent: Sendable, Equatable {
    case stdoutLine(Data)
    case stderr(Data)
}

public protocol MoleStreaming: Sendable {
    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error>
    func cancel() async
}

public extension MoleStreaming {
    func cancel() async {}
}

public actor MoleBridge: MoleStreaming {
    private let executableURL: URL
    private var activeRunner: MoleProcessRunner?
    private var activeGeneration = 0

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

        activeGeneration += 1
        let generation = activeGeneration
        let runner = MoleProcessRunner(
            executableURL: executableURL,
            arguments: arguments,
            stdin: stdin,
            timeout: timeout,
            streamContinuation: nil,
            onFinished: nil
        )
        activeRunner = runner
        defer {
            if activeGeneration == generation, activeRunner === runner {
                activeRunner = nil
            }
        }
        return try await runner.run()
    }

    public func stream(
        _ arguments: [String] = [],
        stdin: Data? = nil,
        timeout: TimeInterval? = nil
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        guard activeRunner == nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: MoleBridgeError.busy)
            }
        }

        activeGeneration += 1
        let generation = activeGeneration
        var streamContinuation: AsyncThrowingStream<MoleOutputEvent, Error>.Continuation!
        let stream = AsyncThrowingStream<MoleOutputEvent, Error>(
            bufferingPolicy: .bufferingOldest(MoleProcessRunner.eventQueueLimit)
        ) { continuation in
            streamContinuation = continuation
        }
        let runner = MoleProcessRunner(
            executableURL: executableURL,
            arguments: arguments,
            stdin: stdin,
            timeout: timeout,
            streamContinuation: streamContinuation,
            onFinished: { [weak self] in
                Task { await self?.releaseRunner(generation: generation) }
            }
        )
        streamContinuation.onTermination = { @Sendable [weak runner] _ in
            runner?.cancel()
        }
        activeRunner = runner
        runner.start()
        return stream
    }

    public func version(timeout: TimeInterval = 10) async throws -> String {
        let result = try await run(["--version"], timeout: timeout)
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw MoleBridgeError.emptyOutput
        }
        return version
    }

    public func cancel() async {
        guard let runner = activeRunner else { return }
        await runner.cancelAndWait()
        if activeRunner === runner {
            activeRunner = nil
        }
    }

    private func releaseRunner(generation: Int) {
        guard generation == activeGeneration else { return }
        activeRunner = nil
    }
}

extension MoleBridge: MoleProcessControlling {}

private final class MoleProcessRunner: @unchecked Sendable {
    static let eventQueueLimit = 256
    private static let readChunkSize = 64 * 1024
    private static let maxLineBytes = 1024 * 1024
    private static let maxAggregateBytes = 16 * 1024 * 1024
    private static let diagnosticTailBytes = 64 * 1024

    private let process: Process
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe = Pipe()
    private let stdin: Data?
    private let timeout: TimeInterval?
    private let streamContinuation: AsyncThrowingStream<MoleOutputEvent, Error>.Continuation?
    private let onFinished: (@Sendable () -> Void)?
    private let lock = NSLock()

    private var continuation: CheckedContinuation<MoleCommandResult, Error>?
    private var finished = false
    private var cancelRequested = false
    private var timeoutRequested = false
    private var processStarted = false
    private var processGroupConfigured = false
    private var timeoutWorkItem: DispatchWorkItem?
    private var processTerminated = false
    private var stdoutEOF = false
    private var stderrEOF = false
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var stdoutLineBuffer = Data()
    private var forcedError: MoleBridgeError?
    private var outputAborted = false
    private var terminationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        executableURL: URL,
        arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?,
        streamContinuation: AsyncThrowingStream<MoleOutputEvent, Error>.Continuation?,
        onFinished: (@Sendable () -> Void)?
    ) {
        process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        self.stdin = stdin
        self.timeout = timeout.map { max(0.01, $0) }
        self.streamContinuation = streamContinuation
        self.onFinished = onFinished
    }

    func run() async throws -> MoleCommandResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation: continuation)
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

    func cancelAndWait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
                return
            }
            terminationWaiters.append(continuation)
            lock.unlock()
            cancel()
        }
    }

    func start() {
        lock.lock()
        guard !finished, !cancelRequested else {
            finished = true
            lock.unlock()
            streamContinuation?.finish(throwing: MoleBridgeError.cancelled)
            onFinished?()
            return
        }
        lock.unlock()
        startProcess()
    }

    private func start(continuation: CheckedContinuation<MoleCommandResult, Error>) {
        lock.lock()
        if finished {
            finished = true
            lock.unlock()
            continuation.resume(throwing: MoleBridgeError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()
        startProcess()
    }

    private func startProcess() {
        lock.lock()
        if finished || cancelRequested {
            lock.unlock()
            finish(.failure(MoleBridgeError.cancelled))
            return
        }
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

        lock.lock()
        let pid = process.processIdentifier
        let didSetProcessGroup = setpgid(pid, pid) == 0
        processGroupConfigured = didSetProcessGroup || getpgid(pid) == pid
        lock.unlock()

        if isCancellationRequested {
            terminateProcessGroup()
        } else {
            scheduleTimeout()
        }

        DispatchQueue.global(qos: .utility).async { [stdinPipe, stdin] in
            if let stdin {
                stdinPipe.fileHandleForWriting.write(stdin)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        }
        startOutputReader(stdoutPipe.fileHandleForReading, channel: .stdout)
        startOutputReader(stderrPipe.fileHandleForReading, channel: .stderr)
    }

    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }

    private func scheduleTimeout() {
        guard let timeout else { return }
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
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
                _ = kill(-pid, SIGKILL)
            }
        } else {
            process.terminate()
        }
    }

    private func processDidTerminate() {
        lock.lock()
        processTerminated = true
        lock.unlock()
        finishIfReady()
    }

    private enum OutputChannel {
        case stdout
        case stderr
    }

    private func startOutputReader(_ handle: FileHandle, channel: OutputChannel) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                while let data = try handle.read(upToCount: Self.readChunkSize), !data.isEmpty {
                    self.consume(data, channel: channel)
                }
            } catch {
                self.fail(.outputReadFailed(error.localizedDescription))
            }
            self.outputDidReachEOF(channel)
        }
    }

    private func consume(_ data: Data, channel: OutputChannel) {
        lock.lock()
        guard !finished, !outputAborted else {
            lock.unlock()
            return
        }
        if streamContinuation == nil {
            let aggregateCount = channel == .stdout ? stdoutBuffer.count : stderrBuffer.count
            guard aggregateCount + data.count <= Self.maxAggregateBytes else {
                lock.unlock()
                fail(.outputLimitExceeded(
                    channel: channel == .stdout ? "stdout" : "stderr",
                    limit: Self.maxAggregateBytes
                ))
                return
            }
            if channel == .stdout {
                stdoutBuffer.append(data)
            } else {
                stderrBuffer.append(data)
            }
        } else {
            if channel == .stdout {
                appendDiagnosticTail(data, to: &stdoutBuffer)
            } else {
                appendDiagnosticTail(data, to: &stderrBuffer)
            }
        }
        let shouldParseStdout = streamContinuation != nil && channel == .stdout
        lock.unlock()

        switch channel {
        case .stdout:
            guard shouldParseStdout else { return }
            for byte in data {
                if byte == 0x0A {
                    lock.lock()
                    let line = stdoutLineBuffer.last == 0x0D
                        ? stdoutLineBuffer.dropLast()
                        : stdoutLineBuffer[...]
                    let lineData = Data(line)
                    stdoutLineBuffer.removeAll(keepingCapacity: true)
                    lock.unlock()
                    emit(.stdoutLine(lineData))
                } else {
                    lock.lock()
                    stdoutLineBuffer.append(byte)
                    let tooLong = stdoutLineBuffer.count > Self.maxLineBytes
                    lock.unlock()
                    if tooLong {
                        fail(.outputLimitExceeded(channel: "stdout line", limit: Self.maxLineBytes))
                        return
                    }
                }
            }
        case .stderr:
            emit(.stderr(data))
        }
    }

    private func outputDidReachEOF(_ channel: OutputChannel) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        if channel == .stdout, !stdoutLineBuffer.isEmpty {
            let line = stdoutLineBuffer.last == 0x0D
                ? stdoutLineBuffer.dropLast()
                : stdoutLineBuffer[...]
            let lineData = Data(line)
            stdoutLineBuffer.removeAll(keepingCapacity: true)
            lock.unlock()
            emit(.stdoutLine(lineData))
            lock.lock()
        }
        if channel == .stdout {
            stdoutEOF = true
        } else {
            stderrEOF = true
        }
        lock.unlock()
        finishIfReady()
    }

    private func emit(_ event: MoleOutputEvent) {
        guard let streamContinuation else { return }
        lock.lock()
        let shouldEmit = !finished && !outputAborted
        lock.unlock()
        guard shouldEmit else { return }
        if case .dropped = streamContinuation.yield(event) {
            fail(.outputLimitExceeded(channel: "event queue", limit: Self.eventQueueLimit))
        }
    }

    private func fail(_ error: MoleBridgeError) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        outputAborted = true
        if forcedError == nil {
            forcedError = error
        }
        lock.unlock()
        terminateProcessGroup()
    }

    private func finishIfReady() {
        lock.lock()
        guard !finished, processTerminated, stdoutEOF, stderrEOF else {
            lock.unlock()
            return
        }
        let timedOut = timeoutRequested
        let cancelled = cancelRequested
        let forcedError = self.forcedError
        let result = MoleCommandResult(
            stdout: String(decoding: stdoutBuffer, as: UTF8.self),
            stderr: String(decoding: stderrBuffer, as: UTF8.self),
            exitCode: process.terminationStatus
        )
        lock.unlock()

        if let forcedError {
            finish(.failure(forcedError))
        } else if timedOut {
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
        let streamContinuation = self.streamContinuation
        let terminationWaiters = self.terminationWaiters
        self.terminationWaiters.removeAll()
        lock.unlock()

        switch outcome {
        case let .success(result):
            continuation?.resume(returning: result)
            streamContinuation?.finish()
        case let .failure(error):
            continuation?.resume(throwing: error)
            streamContinuation?.finish(throwing: error)
        }
        for waiter in terminationWaiters {
            waiter.resume()
        }
        onFinished?()
    }

    private func appendDiagnosticTail(_ data: Data, to buffer: inout Data) {
        buffer.append(data)
        if buffer.count > Self.diagnosticTailBytes {
            buffer.removeFirst(buffer.count - Self.diagnosticTailBytes)
        }
    }
}
