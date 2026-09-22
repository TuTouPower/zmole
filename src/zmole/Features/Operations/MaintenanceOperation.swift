import Combine
import Foundation

enum MaintenanceKind: Sendable {
    case optimize
    case purge

    var command: String {
        switch self {
        case .optimize: return "optimize"
        case .purge: return "purge"
        }
    }

    var failedKey: String {
        "\(command).error.failed"
    }

    var cancelledKey: String {
        "\(command).cancelled"
    }

    var executionArguments: [String] {
        switch self {
        case .optimize:
            return [command]
        case .purge:
            return [command, "--yes"]
        }
    }
}

struct MaintenancePreviewSnapshot: Equatable, Sendable {
    let generation: UUID
    let output: String
}

@MainActor
class MaintenanceViewModel: ObservableObject {
    private let process: any MoleProcessControlling
    private let coordinator: OperationCoordinator
    private let kind: MaintenanceKind
    private let session = OperationSession<MaintenancePreviewSnapshot>()
    private var lease: OperationLease?
    private var previewCoordinatorGeneration: UInt64?
    private var coordinatorSubscription: AnyCancellable?

    init(
        kind: MaintenanceKind,
        process: any MoleProcessControlling,
        coordinator: OperationCoordinator
    ) {
        self.kind = kind
        self.process = process
        self.coordinator = coordinator
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        coordinatorSubscription = coordinator.$invalidationGeneration.sink { [weak self] generation in
            guard let self,
                  let previewGeneration = self.previewCoordinatorGeneration,
                  previewGeneration != generation,
                  self.session.preview != nil else { return }
            self.session.expirePreview(errorKey: "operation.error.stale_preview")
            self.previewCoordinatorGeneration = nil
        }
    }

    var operationState: OperationState<MaintenancePreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var preview: MaintenancePreviewSnapshot? { session.preview }
    var isPreviewing: Bool { session.isPreviewing }
    var isExecuting: Bool { session.isExecuting }
    var isConfirmationPresented: Bool { session.isConfirmationPresented }
    var canConfirm: Bool { session.canConfirm && isCurrentPreview }
    var executionSummary: String? { session.result?.summary }
    var errorMessageKey: String? { session.result?.errorKey }
    var errorMessage: String? {
        guard let result = session.result, result.errorKey == nil else { return nil }
        return result.summary
    }

    func previewMaintenance() async {
        guard !session.isBusy else { return }
        releaseLease()
        session.invalidate()
        guard let operationID = session.beginPreview() else { return }
        guard let newLease = coordinator.acquire(kind.writeOperation) else {
            session.fail(OperationResult(status: .failed, errorKey: "operation.error.busy"), id: operationID)
            return
        }
        lease = newLease
        previewCoordinatorGeneration = coordinator.invalidationGeneration

        do {
            let result = try await process.run(
                [kind.command, "--dry-run"],
                stdin: nil,
                timeout: 120
            )
            guard session.accepts(operationID), !session.isCancelling(operationID) else { return }
            guard coordinator.isCurrent(previewCoordinatorGeneration ?? 0) else {
                session.fail(OperationResult(status: .failed, errorKey: "operation.error.stale_preview"), id: operationID)
                releaseLease()
                return
            }
            guard result.exitCode == 0 else { throw MoleBridgeError.commandFailed(result) }
            session.acceptPreview(
                MaintenancePreviewSnapshot(
                    generation: operationID,
                    output: MaintenanceOutput.summary(stdout: result.stdout)
                ),
                id: operationID
            )
            releaseLease(clearPreviewGeneration: false)
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: operationID)
            releaseLease()
        } catch {
            guard session.accepts(operationID) else { return }
            let summary: String?
            if case let MoleBridgeError.commandFailed(result) = error {
                summary = MaintenanceOutput.summary(stdout: result.stdout, stderr: result.stderr)
            } else {
                summary = error.localizedDescription
            }
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: kind.failedKey),
                id: operationID
            )
            releaseLease()
        }
    }

    func cancelPreview() async {
        guard let operationID = session.beginPreviewCancellation() else { return }
        await process.cancel()
        session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: operationID)
        releaseLease()
    }

    func requestConfirmation() {
        guard canConfirm else { return }
        _ = session.beginConfirmation()
    }

    func cancelConfirmation() {
        guard session.isConfirmationPresented else { return }
        session.cancelConfirmation()
    }

    func confirmMaintenance() async {
        guard session.isConfirmationPresented, canConfirm else { return }
        guard let newLease = coordinator.acquire(kind.writeOperation) else {
            if let id = operationID(for: session.state) {
                session.fail(OperationResult(status: .failed, errorKey: "operation.error.busy"), id: id)
            }
            return
        }
        lease = newLease
        guard let execution = session.beginExecution() else {
            releaseLease()
            return
        }
        coordinator.invalidatePreviews()
        previewCoordinatorGeneration = coordinator.invalidationGeneration

        do {
            let result = try await process.run(kind.executionArguments, stdin: nil, timeout: 600)
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            let summary = MaintenanceOutput.summary(stdout: result.stdout, stderr: result.stderr)
            if result.exitCode == 0 {
                session.finish(OperationResult(status: .succeeded, summary: summary), id: execution.id)
            } else {
                session.fail(
                    OperationResult(status: .failed, summary: summary, errorKey: kind.failedKey),
                    id: execution.id
                )
            }
            coordinator.invalidatePreviews()
            releaseLease()
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: execution.id)
            coordinator.invalidatePreviews()
            releaseLease()
        } catch {
            guard session.accepts(execution.id) else { return }
            let summary: String?
            if case let MoleBridgeError.commandFailed(result) = error {
                summary = MaintenanceOutput.summary(stdout: result.stdout, stderr: result.stderr)
            } else {
                summary = error.localizedDescription
            }
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: kind.failedKey),
                id: execution.id
            )
            coordinator.invalidatePreviews()
            releaseLease()
        }
    }

    func cancelExecution() async {
        guard let operationID = session.beginExecutionCancellation() else { return }
        await process.cancel()
        session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: operationID)
        coordinator.invalidatePreviews()
        releaseLease()
    }

    private var isCurrentPreview: Bool {
        guard let generation = previewCoordinatorGeneration else { return false }
        return coordinator.isCurrent(generation)
    }

    private func operationID(for state: OperationState<MaintenancePreviewSnapshot>) -> UUID? {
        switch state {
        case let .ready(id, _), let .confirming(id, _), let .executing(id, _): return id
        default: return nil
        }
    }

    private func releaseLease(clearPreviewGeneration: Bool = true) {
        lease?.release()
        lease = nil
        if clearPreviewGeneration { previewCoordinatorGeneration = nil }
    }
}

private extension MaintenanceKind {
    var writeOperation: WriteOperation {
        switch self {
        case .optimize: return .optimize
        case .purge: return .purge
        }
    }
}
