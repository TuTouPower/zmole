import Combine
import Foundation

@MainActor
final class CleanViewModel: ObservableObject {
    private let process: any MoleProcessControlling
    private let coordinator: OperationCoordinator
    private let session = OperationSession<CleanPreviewSnapshot>()
    private let leaseCoordinator: PreviewLeaseCoordinator
    private let scan: (any BackgroundScanProviding)?

    @Published private(set) var lastReclaimBytes: Int64?
    @Published private(set) var showBusyNotice = false
    @Published private(set) var previewCapturedAt: Date?

    private var scanCancellables: [AnyCancellable] = []

    init(
        process: any MoleProcessControlling,
        coordinator: OperationCoordinator,
        scan: (any BackgroundScanProviding)? = nil
    ) {
        self.process = process
        self.coordinator = coordinator
        self.scan = scan
        leaseCoordinator = PreviewLeaseCoordinator(coordinator: coordinator)
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        leaseCoordinator.onInvalidation = { [weak self] in
            guard let self, self.session.preview != nil else { return false }
            self.session.expirePreview(errorKey: "operation.error.stale_scan")
            self.lastReclaimBytes = nil
            return true
        }
        subscribeToBackgroundScan()
        adoptBackgroundResultIfAvailable()
    }

    var operationState: OperationState<CleanPreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var preview: CleanPreviewSnapshot? { session.preview }
    var isRefreshing: Bool { scan?.runningItems.contains(.clean) ?? false }
    var scanFailed: Bool { scan?.failedItems.contains(.clean) ?? false }
    /// True only while a user-visible clean confirmation or execution owns
    /// clean-list.txt. Showing a finished scan result is not ownership: the
    /// page must still be able to refresh.
    var ownsCleanListFile: Bool { isConfirmationPresented || isExecuting }
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
    /// the scan the page is showing.
    var confirmationDetail: String? {
        guard let preview = session.preview else { return nil }
        return String(localized: "clean.confirm_detail \(preview.entries.count) \(preview.reclaimText)")
    }

    // MARK: - Background scan

    /// Requests a background scan when the page has no data yet. Called when
    /// the page appears so a fresh install does not sit on an empty page.
    func refreshIfNeeded() {
        guard let scan else { return }
        guard scan.result(for: .clean) == nil, !scan.runningItems.contains(.clean) else { return }
        scan.request(.clean)
    }

    func refreshClean() {
        scan?.request(.clean)
    }

    func cancelRefresh() async {
        await scan?.cancelAndWait(.clean)
    }

    /// Shows the latest background result. Replaces an idle preview so a newer
    /// scan is visible, but never touches a confirmation or execution in
    /// progress.
    func adoptBackgroundResultIfAvailable() {
        guard !session.isBusy, !session.isConfirmationPresented else { return }
        guard let result = scan?.result(for: .clean),
              case let .cleanPreview(snapshot) = result.payload else { return }
        guard session.preview == nil || previewCapturedAt != result.capturedAt else { return }
        leaseCoordinator.captureGeneration()
        session.adoptPreview(snapshot)
        lastReclaimBytes = snapshot.reclaimBytes
        previewCapturedAt = result.capturedAt
    }

    private func subscribeToBackgroundScan() {
        guard let scan else { return }
        scanCancellables.append(
            scan.observeStateChanges { [weak self] in
                self?.objectWillChange.send()
                self?.adoptBackgroundResultIfAvailable()
            }
        )
    }

    // MARK: - Confirmation / execution

    func requestConfirmation() {
        guard canConfirm else { return }
        _ = session.beginConfirmation()
    }

    func cancelConfirmation() {
        guard session.isConfirmationPresented else { return }
        session.cancelConfirmation()
        leaseCoordinator.release()
        adoptBackgroundResultIfAvailable()
    }

    func confirmExecution() async {
        guard session.isConfirmationPresented, canConfirm else { return }
        // The background clean scan writes the same list file; stop it and wait
        // for the process to die before spawning the execution.
        await scan?.userDidRescanAndWaitForTermination(.clean)
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
            leaseCoordinator.markDataModified()
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            showBusyNotice = false
            let summary = MaintenanceOutput.summary(stdout: result.stdout, stderr: result.stderr)
            if result.exitCode == 0 {
                session.finish(
                    OperationResult(status: .succeeded, summary: summary),
                    id: execution.id
                )
            } else {
                session.fail(
                    OperationResult(status: .failed, summary: summary, errorKey: "clean.error.failed"),
                    id: execution.id
                )
            }
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
        } catch let error as MoleBridgeError where error == .cancelled {
            leaseCoordinator.markDataModified()
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
            session.fail(
                OperationResult(status: .failed, summary: error.localizedDescription, errorKey: nil),
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
