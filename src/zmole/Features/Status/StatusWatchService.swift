import Foundation

struct StatusSeriesPoint: Equatable, Sendable {
    let collectedAt: Date
    let cpuUsage: Double?
    let memoryUsedPercent: Double?
    let networkRxRateMBs: Double?
    let networkTxRateMBs: Double?
    let diskReadRate: Double?
    let diskWriteRate: Double?
    let diskIOIsWarming: Bool

    init(snapshot: StatusSnapshot, receivedAt: Date, diskIOIsWarming: Bool? = nil) {
        collectedAt = snapshot.collectedAt ?? receivedAt
        cpuUsage = snapshot.cpu.usageAvailable ? snapshot.cpu.usage : nil
        memoryUsedPercent = snapshot.memory.usedPercent
        networkRxRateMBs = snapshot.networkTotal?.rxRateMBs
        networkTxRateMBs = snapshot.networkTotal?.txRateMBs
        let warming = diskIOIsWarming ?? snapshot.diskIOIsWarming
        self.diskIOIsWarming = warming
        diskReadRate = warming ? nil : snapshot.diskIO?.readRate
        diskWriteRate = warming ? nil : snapshot.diskIO?.writeRate
    }
}

struct StatusWatchUpdate: Equatable, Sendable {
    let snapshot: StatusSnapshot
    let series: [StatusSeriesPoint]
    let receivedAt: Date

    var diskIOIsWarming: Bool {
        series.last?.diskIOIsWarming ?? false
    }
}

enum StatusWatchError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON
    case disconnected
    case bufferOverflow

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "status 流返回了无法解析的数据"
        case .disconnected:
            return "status 流已断开"
        case .bufferOverflow:
            return "status 订阅者处理过慢，快照队列已满"
        }
    }
}

protocol StatusWatchProviding: Sendable {
    func start() async
    func subscribe() async -> AsyncThrowingStream<StatusWatchUpdate, Error>
    func pause() async
    func stop() async
    func retry() async
    var snapshot: StatusSnapshot? { get async }
    var series: [StatusSeriesPoint] { get async }
}

/// Owns one mole watch process and fans its samples out to all visible views.
/// A stream ending with an error is terminal; only `retry()` starts a new
/// process, so a broken helper cannot cause an unbounded restart loop.
actor StatusWatchService: StatusWatchProviding {
    private let streaming: any MoleStreaming
    private let intervalArgument: String
    private let historyLimit: Int
    private var subscribers: [UUID: AsyncThrowingStream<StatusWatchUpdate, Error>.Continuation] = [:]
    private var processTask: Task<Void, Never>?
    private var stopInProgress = false
    private var streamEndInProgress = false
    private var generation = 0
    private var wantsRunning = false
    private var isPaused = false
    private var lastSnapshot: StatusSnapshot?
    private var points: [StatusSeriesPoint] = []
    private var diskIOSampleSeen = false

    init(
        streaming: any MoleStreaming,
        interval: TimeInterval = 1,
        historyLimit: Int = 60
    ) {
        self.streaming = streaming
        intervalArgument = Self.intervalArgument(for: interval)
        self.historyLimit = max(1, historyLimit)
    }

    var snapshot: StatusSnapshot? { lastSnapshot }
    var series: [StatusSeriesPoint] { points }

    func start() async {
        wantsRunning = true
        isPaused = false
        startProcessIfNeeded()
    }

    func subscribe() async -> AsyncThrowingStream<StatusWatchUpdate, Error> {
        let id = UUID()
        var continuation: AsyncThrowingStream<StatusWatchUpdate, Error>.Continuation!
        let stream = AsyncThrowingStream<StatusWatchUpdate, Error>(
            bufferingPolicy: .bufferingOldest(8)
        ) { continuation = $0 }
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        subscribers[id] = continuation
        if let lastSnapshot {
            continuation.yield(
                StatusWatchUpdate(snapshot: lastSnapshot, series: points, receivedAt: Date())
            )
        }
        startProcessIfNeeded()
        return stream
    }

    func pause() async {
        guard subscribers.count <= 1 else { return }
        isPaused = true
        wantsRunning = false
        finishSubscribers()
        await stopProcess()
    }

    func stop() async {
        guard subscribers.count <= 1 else { return }
        isPaused = false
        wantsRunning = false
        finishSubscribers()
        await stopProcess()
    }

    func retry() async {
        wantsRunning = true
        isPaused = false
        startProcessIfNeeded()
    }

    private func startProcessIfNeeded() {
        guard wantsRunning, !isPaused, !subscribers.isEmpty, processTask == nil else { return }
        generation += 1
        let currentGeneration = generation
        let streaming = self.streaming
        let arguments = ["status", "--watch", "--interval", intervalArgument]
        diskIOSampleSeen = false
        processTask = Task { [weak self] in
            let stream = await streaming.stream(arguments, stdin: nil, timeout: nil)
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { return }
                    if case let .stdoutLine(data) = event {
                        await self?.receive(data: data, generation: currentGeneration)
                    }
                }
                guard !Task.isCancelled else { return }
                await self?.streamEnded(generation: currentGeneration, error: StatusWatchError.disconnected)
            } catch is CancellationError {
                // Cancellation is the normal pause/leave-page path.
            } catch {
                guard !Task.isCancelled else { return }
                await self?.streamEnded(generation: currentGeneration, error: error)
            }
        }
    }

    private func receive(data: Data, generation: Int) async {
        guard generation == self.generation, !subscribers.isEmpty else { return }
        let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        guard let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: Data(line.utf8)) else {
            await streamEnded(generation: generation, error: StatusWatchError.invalidJSON)
            return
        }
        let now = Date()
        let hasDiskIO = snapshot.diskIO != nil
        let diskIOIsWarming = hasDiskIO && !diskIOSampleSeen
            && snapshot.diskIO?.readRate == 0
            && snapshot.diskIO?.writeRate == 0
        if hasDiskIO {
            diskIOSampleSeen = true
        }
        lastSnapshot = snapshot
        points.append(
            StatusSeriesPoint(
                snapshot: snapshot,
                receivedAt: now,
                diskIOIsWarming: diskIOIsWarming
            )
        )
        if points.count > historyLimit {
            points.removeFirst(points.count - historyLimit)
        }
        let update = StatusWatchUpdate(snapshot: snapshot, series: points, receivedAt: now)
        var droppedIDs: [UUID] = []
        for (id, continuation) in subscribers {
            if case .dropped = continuation.yield(update) {
                continuation.finish(throwing: StatusWatchError.bufferOverflow)
                droppedIDs.append(id)
            }
        }
        for id in droppedIDs {
            subscribers.removeValue(forKey: id)
        }
        if subscribers.isEmpty {
            wantsRunning = false
            // `receive` runs on the watch task. Do not await that task from
            // itself; the scheduled stop can cancel and then join it after
            // this callback returns.
            Task { await self.stopProcess() }
        }
    }

    private func streamEnded(generation: Int, error: Error) async {
        guard generation == self.generation else { return }
        streamEndInProgress = true
        self.generation += 1
        wantsRunning = false
        for continuation in subscribers.values {
            continuation.finish(throwing: error)
        }
        subscribers.removeAll()
        await streaming.cancel()
        processTask = nil
        streamEndInProgress = false
    }

    private func removeSubscriber(_ id: UUID) async {
        subscribers.removeValue(forKey: id)
        if subscribers.isEmpty, processTask != nil, !streamEndInProgress {
            wantsRunning = false
            await stopProcess()
        }
    }

    private func finishSubscribers() {
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
    }

    private func stopProcess() async {
        guard processTask != nil, !stopInProgress else { return }
        stopInProgress = true
        generation += 1
        let task = processTask
        task?.cancel()
        await streaming.cancel()
        await task?.value
        processTask = nil
        stopInProgress = false
        startProcessIfNeeded()
    }

    private static func intervalArgument(for interval: TimeInterval) -> String {
        let clamped = max(0.1, interval)
        if clamped.rounded() == clamped {
            return "\(Int(clamped))s"
        }
        return String(format: "%.3gs", clamped)
    }
}
