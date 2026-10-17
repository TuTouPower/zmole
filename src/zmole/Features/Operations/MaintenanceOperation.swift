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
    let output: String
}

@MainActor
class MaintenanceViewModel: ObservableObject {
    private let process: any MoleProcessControlling
    private let coordinator: OperationCoordinator
    private let kind: MaintenanceKind
    private let session = OperationSession<MaintenancePreviewSnapshot>()
    private let scan: (any BackgroundScanProviding)?
    private let leaseCoordinator: PreviewLeaseCoordinator

    @Published private(set) var showBusyNotice = false
    @Published private(set) var previewCapturedAt: Date?

    private var scanCancellables: [AnyCancellable] = []

    init(
        kind: MaintenanceKind,
        process: any MoleProcessControlling,
        coordinator: OperationCoordinator,
        scan: (any BackgroundScanProviding)? = nil
    ) {
        self.kind = kind
        self.process = process
        self.coordinator = coordinator
        self.scan = scan
        leaseCoordinator = PreviewLeaseCoordinator(coordinator: coordinator)
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        leaseCoordinator.onInvalidation = { [weak self] in
            guard let self, self.session.preview != nil else { return false }
            self.session.expirePreview(errorKey: "operation.error.stale_scan")
            return true
        }
        subscribeToBackgroundScan()
        adoptBackgroundResultIfAvailable()
    }

    var operationState: OperationState<MaintenancePreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var preview: MaintenancePreviewSnapshot? { session.preview }
    var isRefreshing: Bool { item.map { scan?.runningItems.contains($0) ?? false } ?? false }
    var scanFailed: Bool { item.map { scan?.failedItems.contains($0) ?? false } ?? false }
    var isExecuting: Bool { session.isExecuting }
    var isConfirmationPresented: Bool { session.isConfirmationPresented }
    var canConfirm: Bool { session.canConfirm && leaseCoordinator.isCurrentPreview }
    var executionSummary: String? { session.result?.summary }
    var errorMessageKey: String? { session.result?.errorKey }
    var errorMessage: String? {
        guard let result = session.result, result.errorKey == nil else { return nil }
        return result.summary
    }

    private var item: BackgroundScanItem? { kind.scanItem }

    /// What the confirmation sheet covers: the number of output rows the
    /// current scan would act on.
    var confirmationDetail: String? {
        guard let preview else { return nil }
        let lineCount = preview.output
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        return String(localized: "maintenance.confirm_detail \(lineCount)")
    }

    // MARK: - Background scan

    /// Requests a background scan when the page has no data yet.
    func refreshIfNeeded() {
        guard let scan, let item else { return }
        guard scan.result(for: item) == nil, !scan.runningItems.contains(item) else { return }
        scan.request(item)
    }

    func refreshMaintenance() {
        guard let item else { return }
        scan?.request(item)
    }

    func cancelRefresh() async {
        guard let item else { return }
        await scan?.cancelAndWait(item)
    }

    /// Shows the latest background result and keeps a confirmation or
    /// execution already on screen untouched.
    func adoptBackgroundResultIfAvailable() {
        guard !session.isBusy, !session.isConfirmationPresented else { return }
        guard let item,
              let result = scan?.result(for: item),
              case let .maintenance(output) = result.payload else { return }
        guard session.preview == nil || previewCapturedAt != result.capturedAt else { return }
        leaseCoordinator.captureGeneration()
        session.adoptPreview(MaintenancePreviewSnapshot(output: output))
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

    func confirmMaintenance() async {
        guard session.isConfirmationPresented, canConfirm else { return }
        guard leaseCoordinator.acquire(kind.writeOperation) else {
            showBusyNotice = true
            session.cancelConfirmation()
            return
        }
        guard let execution = session.beginExecution() else {
            leaseCoordinator.release()
            return
        }
        showBusyNotice = false
        leaseCoordinator.invalidateAndRecapture()
        previewCapturedAt = nil

        do {
            let result = try await process.run(kind.executionArguments, stdin: nil, timeout: 600)
            leaseCoordinator.markDataModified()
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
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: execution.id)
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
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
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
        }
    }

    func cancelExecution() async {
        guard let operationID = session.beginExecutionCancellation() else { return }
        await process.cancel()
        session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: operationID)
        leaseCoordinator.invalidatePreviews()
        leaseCoordinator.release()
    }
}

private extension MaintenanceKind {
    var writeOperation: WriteOperation {
        switch self {
        case .optimize: return .optimize
        case .purge: return .purge
        }
    }

    var scanItem: BackgroundScanItem? {
        switch self {
        case .optimize: return .optimize
        case .purge: return .purge
        }
    }
}
