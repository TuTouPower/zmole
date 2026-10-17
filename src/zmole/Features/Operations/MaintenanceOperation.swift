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
    private weak var scan: (any BackgroundScanProviding)?
    private let leaseCoordinator: PreviewLeaseCoordinator

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
            self.session.expirePreview(errorKey: "operation.error.stale_preview")
            return true
        }
    }

    var operationState: OperationState<MaintenancePreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var preview: MaintenancePreviewSnapshot? { session.preview }
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
    @Published private(set) var showBusyNotice = false
    @Published private(set) var previewCapturedAt: Date?

    /// What the confirmation sheet covers: the number of output rows the
    /// current preview would act on.
    var confirmationDetail: String? {
        guard let preview else { return nil }
        let lineCount = preview.output
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        return String(localized: "maintenance.confirm_detail \(lineCount)")
    }

    /// Shows a finished background scan result without re-running the scan.
    /// Does nothing when the user already has a preview or no result is
    /// available.
    func adoptPrewarmPreviewIfAvailable() {
        guard session.preview == nil, !session.isBusy else { return }
        guard let item = kind.scanItem,
              let result = scan?.result(for: item),
              case let .maintenance(output) = result.payload else { return }
        leaseCoordinator.captureGeneration()
        session.adoptPreview(MaintenancePreviewSnapshot(generation: UUID(), output: output))
        previewCapturedAt = result.capturedAt
    }

    func previewMaintenance() async {
        guard !session.isBusy else { return }
        if let item = kind.scanItem {
            scan?.userDidRescan(item)
        }
        previewCapturedAt = nil
        leaseCoordinator.release()
        session.invalidate()
        showBusyNotice = false
        guard leaseCoordinator.acquire(kind.writeOperation) else {
            showBusyNotice = true
            return
        }
        guard let operationID = session.beginPreview() else {
            leaseCoordinator.release()
            return
        }
        leaseCoordinator.captureGeneration()

        do {
            let result = try await process.run(
                [kind.command, "--dry-run"],
                stdin: nil,
                timeout: 120
            )
            guard session.accepts(operationID), !session.isCancelling(operationID) else { return }
            guard leaseCoordinator.isCurrentPreview else {
                session.fail(OperationResult(status: .failed, errorKey: "operation.error.stale_preview"), id: operationID)
                leaseCoordinator.release()
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
            leaseCoordinator.release(clearPreviewGeneration: false)
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: operationID)
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
            if case let MoleBridgeError.commandFailed(result) = error {
                summary = MaintenanceOutput.summary(stdout: result.stdout, stderr: result.stderr)
            } else {
                summary = error.localizedDescription
            }
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: kind.failedKey),
                id: operationID
            )
            leaseCoordinator.release()
        }
    }

    func cancelPreview() async {
        guard let operationID = session.beginPreviewCancellation() else { return }
        await process.cancel()
        session.finishCancelled(OperationResult(status: .cancelled, errorKey: kind.cancelledKey), id: operationID)
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
