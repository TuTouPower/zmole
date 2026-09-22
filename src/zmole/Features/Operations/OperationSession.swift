import Foundation

enum OperationActivity: Equatable, Sendable {
    case preview
    case execution
}

enum OperationResultStatus: Equatable, Sendable {
    case succeeded
    case partial
    case failed
    case cancelled
    case unknown
}

struct OperationResult: Equatable, Sendable {
    let status: OperationResultStatus
    let summary: String?
    let errorKey: String?

    init(
        status: OperationResultStatus,
        summary: String? = nil,
        errorKey: String? = nil
    ) {
        self.status = status
        self.summary = summary
        self.errorKey = errorKey
    }

    var isCancelled: Bool { status == .cancelled }
    var isPartial: Bool { status == .partial }
    var isFailure: Bool { status == .failed }
}

enum OperationState<Preview: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case previewing(UUID)
    case ready(UUID, Preview)
    case confirming(UUID, Preview)
    case executing(UUID, Preview)
    case cancelling(OperationActivity, UUID)
    case finished(OperationResult)
    case failed(OperationResult)
    case cancelled(OperationResult)
}

@MainActor
final class OperationSession<Preview: Equatable & Sendable> {
    private(set) var state: OperationState<Preview> = .idle {
        didSet { onChange?() }
    }

    var onChange: (() -> Void)?

    var preview: Preview? {
        switch state {
        case let .ready(_, preview), let .confirming(_, preview), let .executing(_, preview):
            return preview
        case .idle, .previewing, .cancelling, .finished, .failed, .cancelled:
            return nil
        }
    }

    var result: OperationResult? {
        switch state {
        case let .finished(result), let .failed(result), let .cancelled(result):
            return result
        case .idle, .previewing, .ready, .confirming, .executing, .cancelling:
            return nil
        }
    }

    var isPreviewing: Bool {
        switch state {
        case .previewing, .cancelling(.preview, _):
            return true
        default:
            return false
        }
    }

    var isExecuting: Bool {
        switch state {
        case .executing, .cancelling(.execution, _):
            return true
        default:
            return false
        }
    }

    var isBusy: Bool { isPreviewing || isExecuting }

    var isConfirmationPresented: Bool {
        if case .confirming = state { return true }
        return false
    }

    var canConfirm: Bool {
        switch state {
        case .ready, .confirming:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func beginPreview() -> UUID? {
        guard !isBusy else { return nil }
        let id = UUID()
        state = .previewing(id)
        return id
    }

    func acceptPreview(_ preview: Preview, id: UUID) {
        guard case let .previewing(activeID) = state, activeID == id else { return }
        state = .ready(id, preview)
    }

    @discardableResult
    func beginConfirmation() -> Bool {
        guard case let .ready(id, preview) = state else { return false }
        state = .confirming(id, preview)
        return true
    }

    func cancelConfirmation() {
        guard case .confirming = state else { return }
        state = .idle
    }

    func expirePreview(errorKey: String) {
        switch state {
        case .ready, .confirming:
            state = .failed(
                OperationResult(status: .failed, errorKey: errorKey)
            )
        default:
            return
        }
    }

    func isCancelling(_ id: UUID) -> Bool {
        guard case let .cancelling(_, activeID) = state else { return false }
        return activeID == id
    }

    @discardableResult
    func beginExecution() -> (id: UUID, preview: Preview)? {
        guard case let .confirming(id, preview) = state else { return nil }
        state = .executing(id, preview)
        return (id, preview)
    }

    @discardableResult
    func beginPreviewCancellation() -> UUID? {
        guard case let .previewing(id) = state else { return nil }
        state = .cancelling(.preview, id)
        return id
    }

    @discardableResult
    func beginExecutionCancellation() -> UUID? {
        guard case let .executing(id, _) = state else { return nil }
        state = .cancelling(.execution, id)
        return id
    }

    func finish(_ result: OperationResult, id: UUID) {
        guard case let .executing(activeID, _) = state, activeID == id else { return }
        state = .finished(result)
    }

    func fail(_ result: OperationResult, id: UUID) {
        switch state {
        case let .previewing(activeID), let .ready(activeID, _), let .confirming(activeID, _),
             let .executing(activeID, _):
            guard activeID == id else { return }
        default:
            return
        }
        state = .failed(result)
    }

    func finishCancelled(_ result: OperationResult, id: UUID) {
        switch state {
        case let .previewing(activeID), let .executing(activeID, _),
             let .cancelling(_, activeID):
            guard activeID == id else { return }
        default:
            return
        }
        state = .cancelled(result)
    }

    func invalidate() {
        state = .idle
    }

    func accepts(_ id: UUID) -> Bool {
        switch state {
        case let .previewing(activeID), let .ready(activeID, _), let .confirming(activeID, _),
             let .executing(activeID, _), let .cancelling(_, activeID):
            return activeID == id
        case .idle, .finished, .failed, .cancelled:
            return false
        }
    }
}
