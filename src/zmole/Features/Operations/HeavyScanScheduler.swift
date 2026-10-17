import Foundation

enum ScanPriority: Int, Comparable, Sendable {
    case background = 0
    case userVisible = 1

    static func < (lhs: ScanPriority, rhs: ScanPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

actor HeavyScanScheduler {
    static let shared = HeavyScanScheduler()
    static let defaultConcurrency = 3
    static let defaultStarvationLimit = 3

    let maxConcurrency: Int
    let starvationLimit: Int

    private(set) var activeCount = 0
    private var highPriorityCountSinceLastBackground = 0
    private var sequenceCounter: UInt64 = 0

    private struct QueuedRequest {
        let id: UUID
        let taskID: String
        var priority: ScanPriority
        let sequence: UInt64
        let continuation: CheckedContinuation<HeavyScanPermit, Error>
    }

    private var highPriorityQueue: [QueuedRequest] = []
    private var backgroundQueue: [QueuedRequest] = []
    private var activePermitIDs: Set<UUID> = []

    var waitingCount: Int {
        highPriorityQueue.count + backgroundQueue.count
    }

    var highPriorityWaitingCount: Int {
        highPriorityQueue.count
    }

    var backgroundWaitingCount: Int {
        backgroundQueue.count
    }

    init(
        maxConcurrency: Int = HeavyScanScheduler.defaultConcurrency,
        starvationLimit: Int = HeavyScanScheduler.defaultStarvationLimit
    ) {
        self.maxConcurrency = max(1, maxConcurrency)
        self.starvationLimit = max(1, starvationLimit)
    }

    func acquire(
        taskID: String,
        priority: ScanPriority = .background
    ) async throws -> HeavyScanPermit {
        try Task.checkCancellation()
        if activeCount < maxConcurrency {
            activeCount += 1
            let permitID = UUID()
            activePermitIDs.insert(permitID)
            return HeavyScanPermit(id: permitID, scheduler: self)
        }

        let requestID = UUID()
        sequenceCounter += 1
        let seq = sequenceCounter

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let req = QueuedRequest(
                    id: requestID,
                    taskID: taskID,
                    priority: priority,
                    sequence: seq,
                    continuation: continuation
                )
                if priority == .userVisible {
                    highPriorityQueue.append(req)
                } else {
                    backgroundQueue.append(req)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelRequest(requestID)
            }
        }
    }

    func elevate(taskID: String) {
        if let index = backgroundQueue.firstIndex(where: { $0.taskID == taskID }) {
            var req = backgroundQueue.remove(at: index)
            req.priority = .userVisible
            highPriorityQueue.append(req)
        }
    }

    func demote(taskID: String) {
        if let index = highPriorityQueue.firstIndex(where: { $0.taskID == taskID }) {
            var req = highPriorityQueue.remove(at: index)
            req.priority = .background
            backgroundQueue.append(req)
        }
    }

    func cancelRequest(_ requestID: UUID) {
        if let index = highPriorityQueue.firstIndex(where: { $0.id == requestID }) {
            let req = highPriorityQueue.remove(at: index)
            req.continuation.resume(throwing: CancellationError())
        } else if let index = backgroundQueue.firstIndex(where: { $0.id == requestID }) {
            let req = backgroundQueue.remove(at: index)
            req.continuation.resume(throwing: CancellationError())
        }
    }

    func releasePermit(id: UUID) {
        guard activePermitIDs.remove(id) != nil else { return }
        activeCount -= 1
        dispatchNext()
    }

    private func dispatchNext() {
        guard activeCount < maxConcurrency else { return }

        if highPriorityCountSinceLastBackground >= starvationLimit, !backgroundQueue.isEmpty {
            let nextReq = backgroundQueue.removeFirst()
            highPriorityCountSinceLastBackground = 0
            admit(nextReq)
            return
        }

        if !highPriorityQueue.isEmpty {
            let nextReq = highPriorityQueue.removeFirst()
            highPriorityCountSinceLastBackground += 1
            admit(nextReq)
            return
        }

        if !backgroundQueue.isEmpty {
            let nextReq = backgroundQueue.removeFirst()
            highPriorityCountSinceLastBackground = 0
            admit(nextReq)
            return
        }
    }

    private func admit(_ req: QueuedRequest) {
        activeCount += 1
        let permitID = UUID()
        activePermitIDs.insert(permitID)
        let permit = HeavyScanPermit(id: permitID, scheduler: self)
        req.continuation.resume(returning: permit)
    }

    func withPermit<T: Sendable>(
        taskID: String,
        priority: ScanPriority = .background,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let permit = try await acquire(taskID: taskID, priority: priority)
        do {
            let result = try await operation()
            await permit.release()
            return result
        } catch {
            await permit.release()
            throw error
        }
    }
}

final class HeavyScanPermit: Sendable {
    let id: UUID
    private let scheduler: HeavyScanScheduler
    private let lock = NSLock()
    private var isReleased = false

    init(id: UUID, scheduler: HeavyScanScheduler) {
        self.id = id
        self.scheduler = scheduler
    }

    func release() async {
        lock.lock()
        if isReleased {
            lock.unlock()
            return
        }
        isReleased = true
        lock.unlock()
        await scheduler.releasePermit(id: id)
    }

    deinit {
        lock.lock()
        let shouldRelease = !isReleased
        isReleased = true
        lock.unlock()
        if shouldRelease {
            let s = scheduler
            let pid = id
            Task {
                await s.releasePermit(id: pid)
            }
        }
    }
}
