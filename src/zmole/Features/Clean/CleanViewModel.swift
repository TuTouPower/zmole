import Combine
import Foundation

@MainActor
final class CleanViewModel: ObservableObject {
    private let process: any MoleProcessControlling
    private let previewStore: CleanPreviewStore
    private let coordinator: OperationCoordinator
    private let streaming: (any MoleStreaming)?
    private let session = OperationSession<CleanPreviewSnapshot>()
    private var lease: OperationLease?
    private var previewCoordinatorGeneration: UInt64?
    private var coordinatorSubscription: AnyCancellable?

    @Published private(set) var currentStage: CleanScanStage?
    @Published private(set) var lastReclaimBytes: Int64?
    @Published private(set) var showBusyNotice = false
    @Published private(set) var previewCapturedAt: Date?

    private weak var prewarm: (any PrewarmResultProviding)?

    init(
        process: any MoleProcessControlling,
        previewStore: CleanPreviewStore,
        coordinator: OperationCoordinator,
        streaming: (any MoleStreaming)? = nil,
        prewarm: (any PrewarmResultProviding)? = nil
    ) {
        self.process = process
        self.previewStore = previewStore
        self.coordinator = coordinator
        self.streaming = streaming
        self.prewarm = prewarm
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        coordinatorSubscription = coordinator.$invalidationGeneration.sink { [weak self] generation in
            guard let self,
                  let previewGeneration = self.previewCoordinatorGeneration,
                  previewGeneration != generation,
                  self.session.preview != nil else { return }
            self.session.expirePreview(errorKey: "operation.error.stale_preview")
            self.previewCoordinatorGeneration = nil
            self.lastReclaimBytes = nil
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

    /// What the confirmation sheet covers: entry count and reclaim total of
    /// the current preview.
    var confirmationDetail: String? {
        guard let preview = session.preview else { return nil }
        return String(localized: "clean.confirm_detail \(preview.entries.count) \(preview.reclaimText)")
    }

    /// Shows a finished background prewarm preview without re-running the
    /// scan. Does nothing when the user already has a preview or no prewarm
    /// result is available.
    func adoptPrewarmPreviewIfAvailable() {
        guard session.preview == nil, !session.isBusy else { return }
        guard let result = prewarm?.takeResult(.cleanDryRun),
              case let .cleanPreview(snapshot) = result.payload else { return }
        previewCoordinatorGeneration = coordinator.invalidationGeneration
        session.adoptPreview(snapshot)
        lastReclaimBytes = snapshot.reclaimBytes
        previewCapturedAt = result.capturedAt
    }

    func previewClean() async {
        guard !session.isBusy else { return }
        await prewarm?.userDidRescanAndWaitForTermination(.cleanDryRun)
        previewCapturedAt = nil
        releaseLease()
        session.invalidate()
        currentStage = nil
        showBusyNotice = false
        guard let newLease = coordinator.acquire(.clean) else {
            showBusyNotice = true
            return
        }
        lease = newLease
        guard let operationID = session.beginPreview() else {
            releaseLease()
            return
        }
        previewCoordinatorGeneration = coordinator.invalidationGeneration

        do {
            let generation = try previewStore.begin()
            try await runDryRun(operationID: operationID)
            guard session.accepts(operationID), !session.isCancelling(operationID) else {
                releaseLease()
                return
            }
            guard coordinator.isCurrent(previewCoordinatorGeneration ?? 0) else {
                session.fail(
                    OperationResult(status: .failed, errorKey: "operation.error.stale_preview"),
                    id: operationID
                )
                lastReclaimBytes = nil
                releaseLease()
                return
            }
            let store = previewStore
            let snapshot = try await Task.detached { try store.read(generation) }.value
            session.acceptPreview(snapshot, id: operationID)
            lastReclaimBytes = snapshot.reclaimBytes
            releaseLease(clearPreviewGeneration: false)
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
                id: operationID
            )
            lastReclaimBytes = nil
            releaseLease()
        } catch {
            guard session.accepts(operationID) else { return }
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                session.invalidate()
                releaseLease()
                return
            }
            let summary: String?
            let errorKey: String?
            if let previewError = error as? CleanPreviewStoreError {
                summary = nil
                errorKey = previewError.errorKey
            } else if case let MoleBridgeError.commandFailed(result) = error {
                summary = MaintenanceOutput.summary(stdout: result.stdout, stderr: result.stderr)
                errorKey = "clean.error.failed"
            } else {
                summary = error.localizedDescription
                errorKey = nil
            }
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: errorKey),
                id: operationID
            )
            lastReclaimBytes = nil
            releaseLease()
        }
    }

    /// Runs `clean --dry-run`, preferring a live stream so the page can show the
    /// current scan stage. Falls back to the one-shot command path when no
    /// stream is injected (tests, demo).
    private func runDryRun(operationID: UUID) async throws {
        guard let streaming else {
            let result = try await process.run(["clean", "--dry-run"], stdin: nil, timeout: 120)
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            currentStage = CleanStageCatalog.lastStage(in: result.stdout)
            return
        }

        let stream = await streaming.stream(["clean", "--dry-run"], stdin: nil, timeout: 300)
        do {
            for try await event in stream {
                guard session.accepts(operationID), !session.isCancelling(operationID) else { return }
                if case let .stdoutLine(data) = event,
                   let line = String(data: data, encoding: .utf8),
                   let stage = CleanStageCatalog.stage(fromLine: line) {
                    currentStage = stage
                }
            }
        } catch is CancellationError {
            throw MoleBridgeError.cancelled
        }
    }

    func cancelPreview() async {
        guard let operationID = session.beginPreviewCancellation() else { return }
        if let streaming {
            await streaming.cancel()
        } else {
            await process.cancel()
        }
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
            id: operationID
        )
        lastReclaimBytes = nil
        previewCapturedAt = nil
        releaseLease()
    }

    func requestConfirmation() {
        guard canConfirm else { return }
        _ = session.beginConfirmation()
    }

    func cancelConfirmation() {
        guard session.isConfirmationPresented else { return }
        session.cancelConfirmation()
        lastReclaimBytes = nil
        previewCapturedAt = nil
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
            showBusyNotice = true
            session.cancelConfirmation()
            return
        }
        lease = newLease
        guard let execution = session.beginExecution() else {
            releaseLease()
            return
        }
        coordinator.invalidatePreviews()
        previewCoordinatorGeneration = coordinator.invalidationGeneration
        lastReclaimBytes = nil
        previewCapturedAt = nil

        do {
            let result = try await process.run(["clean"], stdin: nil, timeout: 600)
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            showBusyNotice = false
            let summary = MaintenanceOutput.summary(stdout: result.stdout, stderr: result.stderr)
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
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                session.invalidate()
                coordinator.invalidatePreviews()
                releaseLease()
                return
            }
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
}
