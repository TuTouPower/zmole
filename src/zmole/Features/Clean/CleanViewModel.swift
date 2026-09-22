import Combine
import Foundation

@MainActor
final class CleanViewModel: ObservableObject {
    private let process: any MoleProcessControlling
    private let previewStore: CleanPreviewStore
    private let coordinator: OperationCoordinator
    private let session = OperationSession<CleanPreviewSnapshot>()
    private var lease: OperationLease?
    private var previewCoordinatorGeneration: UInt64?
    private var coordinatorSubscription: AnyCancellable?

    init(
        process: any MoleProcessControlling,
        previewStore: CleanPreviewStore,
        coordinator: OperationCoordinator
    ) {
        self.process = process
        self.previewStore = previewStore
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

    // Kept for the existing Clean domain tests; production assembly must pass the shared coordinator.
    convenience init(
        process: any MoleProcessControlling,
        previewStore: CleanPreviewStore
    ) {
        self.init(
            process: process,
            previewStore: previewStore,
            coordinator: OperationCoordinator()
        )
    }

    var operationState: OperationState<CleanPreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var preview: CleanPreviewSnapshot? { session.preview }
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

    func previewClean() async {
        guard !session.isBusy else { return }
        releaseLease()
        session.invalidate()
        guard let operationID = session.beginPreview() else { return }
        guard let newLease = coordinator.acquire(.clean) else {
            session.fail(
                OperationResult(status: .failed, errorKey: "operation.error.busy"),
                id: operationID
            )
            return
        }
        lease = newLease
        previewCoordinatorGeneration = coordinator.invalidationGeneration

        do {
            let generation = try previewStore.begin()
            let result = try await process.run(
                ["clean", "--dry-run"],
                stdin: nil,
                timeout: 120
            )
            guard session.accepts(operationID), !session.isCancelling(operationID) else { return }
            guard coordinator.isCurrent(previewCoordinatorGeneration ?? 0) else {
                session.fail(
                    OperationResult(status: .failed, errorKey: "operation.error.stale_preview"),
                    id: operationID
                )
                releaseLease()
                return
            }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            session.acceptPreview(try previewStore.read(generation), id: operationID)
            releaseLease(clearPreviewGeneration: false)
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
                id: operationID
            )
            releaseLease()
        } catch {
            guard session.accepts(operationID) else { return }
            let summary: String?
            let errorKey: String?
            if let previewError = error as? CleanPreviewStoreError {
                summary = nil
                errorKey = previewError.errorKey
            } else if case let MoleBridgeError.commandFailed(result) = error {
                summary = outputSummary(result)
                errorKey = "clean.error.failed"
            } else {
                summary = error.localizedDescription
                errorKey = nil
            }
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: errorKey),
                id: operationID
            )
            releaseLease()
        }
    }

    func cancelPreview() async {
        guard let operationID = session.beginPreviewCancellation() else { return }
        await process.cancel()
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
            id: operationID
        )
        releaseLease()
    }

    func requestConfirmation() {
        guard canConfirm else { return }
        _ = session.beginConfirmation()
    }

    func cancelConfirmation() {
        guard session.isConfirmationPresented else { return }
        session.cancelConfirmation()
        releaseLease()
    }

    func confirmExecution() async {
        guard session.isConfirmationPresented, canConfirm,
              let snapshot = session.preview,
              let previewID = operationID(for: session.state) else { return }
        do {
            try previewStore.verifyUnchanged(snapshot)
        } catch {
            session.fail(
                OperationResult(
                    status: .failed,
                    errorKey: (error as? CleanPreviewStoreError)?.errorKey
                ),
                id: previewID
            )
            releaseLease()
            return
        }
        guard let newLease = coordinator.acquire(.clean) else {
            session.fail(OperationResult(status: .failed, errorKey: "operation.error.busy"), id: previewID)
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
            let result = try await process.run(["clean"], stdin: nil, timeout: 600)
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            let summary = outputSummary(result)
            let operationResult: OperationResult
            if result.exitCode == 0 {
                operationResult = OperationResult(status: .succeeded, summary: summary)
                session.finish(operationResult, id: execution.id)
            } else {
                operationResult = OperationResult(
                    status: .failed,
                    summary: summary,
                    errorKey: "clean.error.failed"
                )
                session.fail(operationResult, id: execution.id)
            }
            coordinator.invalidatePreviews()
            releaseLease()
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
                id: execution.id
            )
            coordinator.invalidatePreviews()
            releaseLease()
        } catch {
            guard session.accepts(execution.id) else { return }
            let summary = (error as? CleanPreviewStoreError)?.errorDescription
                ?? error.localizedDescription
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: nil),
                id: execution.id
            )
            coordinator.invalidatePreviews()
            releaseLease()
        }
    }

    func cancelExecution() async {
        guard let operationID = session.beginExecutionCancellation() else { return }
        await process.cancel()
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
            id: operationID
        )
        coordinator.invalidatePreviews()
        releaseLease()
    }

    private var isCurrentPreview: Bool {
        guard let generation = previewCoordinatorGeneration else { return false }
        return coordinator.isCurrent(generation)
    }

    private func operationID(for state: OperationState<CleanPreviewSnapshot>) -> UUID? {
        switch state {
        case let .ready(id, _), let .confirming(id, _), let .executing(id, _): return id
        default: return nil
        }
    }

    private func releaseLease(clearPreviewGeneration: Bool = true) {
        lease?.release()
        lease = nil
        if clearPreviewGeneration {
            previewCoordinatorGeneration = nil
        }
    }

    private func outputSummary(_ result: MoleCommandResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
