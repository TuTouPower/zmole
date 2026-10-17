import Combine
import Foundation

@MainActor
final class CleanViewModel: ObservableObject {
    private let process: any MoleProcessControlling
    private let previewStore: CleanPreviewStore
    private let coordinator: OperationCoordinator
    private let streaming: (any MoleStreaming)?
    private let session = OperationSession<CleanPreviewSnapshot>()
    private let leaseCoordinator: PreviewLeaseCoordinator

    @Published private(set) var currentStage: CleanScanStage?
    @Published private(set) var lastReclaimBytes: Int64?
    @Published private(set) var showBusyNotice = false
    @Published private(set) var previewCapturedAt: Date?

    private weak var scan: (any BackgroundScanProviding)?

    init(
        process: any MoleProcessControlling,
        previewStore: CleanPreviewStore,
        coordinator: OperationCoordinator,
        streaming: (any MoleStreaming)? = nil,
        scan: (any BackgroundScanProviding)? = nil
    ) {
        self.process = process
        self.previewStore = previewStore
        self.coordinator = coordinator
        self.streaming = streaming
        self.scan = scan
        leaseCoordinator = PreviewLeaseCoordinator(coordinator: coordinator)
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        leaseCoordinator.onInvalidation = { [weak self] in
            guard let self, self.session.preview != nil else { return false }
            self.session.expirePreview(errorKey: "operation.error.stale_preview")
            self.lastReclaimBytes = nil
            return true
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
    var canConfirm: Bool { session.canConfirm && leaseCoordinator.isCurrentPreview }
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

    /// Shows a finished background scan result without re-running the scan.
    /// Does nothing when the user already has a preview or no result is
    /// available.
    func adoptPrewarmPreviewIfAvailable() {
        guard session.preview == nil, !session.isBusy else { return }
        guard let result = scan?.result(for: .clean),
              case let .cleanPreview(snapshot) = result.payload else { return }
        leaseCoordinator.captureGeneration()
        session.adoptPreview(snapshot)
        lastReclaimBytes = snapshot.reclaimBytes
        previewCapturedAt = result.capturedAt
    }

    func previewClean() async {
        guard !session.isBusy else { return }
        await scan?.userDidRescanAndWaitForTermination(.clean)
        previewCapturedAt = nil
        leaseCoordinator.release()
        session.invalidate()
        currentStage = nil
        showBusyNotice = false
        guard leaseCoordinator.acquire(.clean) else {
            showBusyNotice = true
            return
        }
        guard let operationID = session.beginPreview() else {
            leaseCoordinator.release()
            return
        }
        leaseCoordinator.captureGeneration()

        do {
            let generation = try previewStore.begin()
            try await runDryRun(operationID: operationID)
            guard session.accepts(operationID), !session.isCancelling(operationID) else {
                leaseCoordinator.release()
                return
            }
            guard leaseCoordinator.isCurrentPreview else {
                session.fail(
                    OperationResult(status: .failed, errorKey: "operation.error.stale_preview"),
                    id: operationID
                )
                lastReclaimBytes = nil
                leaseCoordinator.release()
                return
            }
            let store = previewStore
            let snapshot = try await Task.detached { try store.read(generation) }.value
            session.acceptPreview(snapshot, id: operationID)
            lastReclaimBytes = snapshot.reclaimBytes
            leaseCoordinator.release(clearPreviewGeneration: false)
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
                id: operationID
            )
            lastReclaimBytes = nil
            leaseCoordinator.release()
        } catch {
            guard session.accepts(operationID) else { return }
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                session.invalidate()
                leaseCoordinator.release()
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
            leaseCoordinator.release()
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
        leaseCoordinator.release()
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
        leaseCoordinator.release()
    }

    func confirmExecution() async {
        guard session.isConfirmationPresented, canConfirm,
              let snapshot = session.preview,
              let previewID = PreviewOperationID.from(session.state) else { return }
        // The background clean scan writes the same list file; stop it and wait
        // for the process to die before verifying or spawning the execution.
        await scan?.userDidRescanAndWaitForTermination(.clean)
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
            leaseCoordinator.release()
            return
        }
        guard leaseCoordinator.acquire(.clean) else {
            showBusyNotice = true
            session.cancelConfirmation()
            return
        }
        guard let execution = session.beginExecution() else {
            leaseCoordinator.release()
            return
        }
        leaseCoordinator.invalidateAndRecapture()
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
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
                id: execution.id
            )
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
        } catch {
            guard session.accepts(execution.id) else { return }
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                session.invalidate()
                leaseCoordinator.invalidatePreviews()
                leaseCoordinator.release()
                return
            }
            let summary = (error as? CleanPreviewStoreError)?.errorDescription
                ?? error.localizedDescription
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: nil),
                id: execution.id
            )
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
        }
    }

    func cancelExecution() async {
        guard let operationID = session.beginExecutionCancellation() else { return }
        await process.cancel()
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "clean.cancelled"),
            id: operationID
        )
        leaseCoordinator.invalidatePreviews()
        leaseCoordinator.release()
    }
}
