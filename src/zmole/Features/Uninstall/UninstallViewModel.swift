import Combine
import Foundation

@MainActor
final class UninstallViewModel: ObservableObject {
    @Published private(set) var apps: [UninstallApp] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var hasLoaded = false

    private let process: any MoleProcessControlling
    private let coordinator: OperationCoordinator
    private let session = OperationSession<UninstallPreviewSnapshot>()
    private let listSession = OperationSession<UninstallListSnapshot>()
    private var lease: OperationLease?
    private var previewCoordinatorGeneration: UInt64?
    private var listGeneration = UUID()
    private var transientErrorKey: String?
    private var coordinatorSubscription: AnyCancellable?

    init(process: any MoleProcessControlling, coordinator: OperationCoordinator) {
        self.process = process
        self.coordinator = coordinator
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        listSession.onChange = { [weak self] in self?.objectWillChange.send() }
        coordinatorSubscription = coordinator.$invalidationGeneration.sink { [weak self] generation in
            self?.expirePreviewIfNeeded(generation: generation)
        }
    }

    var operationState: OperationState<UninstallPreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var preview: UninstallPreviewSnapshot? { session.preview }
    var isListing: Bool { listSession.isPreviewing }
    var isPreviewing: Bool { session.isPreviewing }
    var isExecuting: Bool { session.isExecuting }
    var isConfirmationPresented: Bool { session.isConfirmationPresented }
    var canPreview: Bool {
        !selectedIDs.isEmpty && !isListing && !session.isBusy && selectedIDs.allSatisfy { id in
            apps.contains { $0.id == id }
        }
    }
    var canConfirm: Bool { session.canConfirm && isCurrentPreview }
    var executionSummary: String? { session.result?.summary }
    var errorMessageKey: String? { transientErrorKey ?? session.result?.errorKey }
    var errorMessage: String? {
        if transientErrorKey != nil { return nil }
        return session.result?.summary
    }

    func loadListIfNeeded() async {
        guard !hasLoaded else { return }
        await loadList()
    }

    func loadList() async {
        guard !isListing, !session.isBusy else { return }
        releaseLease()
        session.invalidate()
        selectedIDs.removeAll()
        clearTransientError()

        guard let operationID = listSession.beginPreview() else { return }
        do {
            let snapshot = try await fetchList()
            guard listSession.accepts(operationID), !listSession.isCancelling(operationID) else { return }
            apps = snapshot.apps
            listGeneration = snapshot.generation
            hasLoaded = true
            listSession.invalidate()
        } catch let error as MoleBridgeError where error == .cancelled {
            listSession.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
                id: operationID
            )
        } catch {
            guard listSession.accepts(operationID), !listSession.isCancelling(operationID) else { return }
            apps = []
            hasLoaded = false
            listSession.fail(
                OperationResult(status: .failed, summary: error.localizedDescription, errorKey: nil),
                id: operationID
            )
        }
    }

    func cancelList() async {
        guard let operationID = listSession.beginPreviewCancellation() else { return }
        await process.cancel()
        listSession.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
            id: operationID
        )
    }

    func cancelPreview() async {
        guard let operationID = session.beginPreviewCancellation() else { return }
        await process.cancel()
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
            id: operationID
        )
        releaseLease()
    }

    func toggleSelection(_ app: UninstallApp) {
        guard !isListing, !session.isBusy else { return }
        if selectedIDs.contains(app.id) {
            selectedIDs.remove(app.id)
        } else {
            selectedIDs.insert(app.id)
        }
        releaseLease()
        session.invalidate()
        clearTransientError()
    }

    func selectAll(_ ids: Set<String>) {
        guard !isListing, !session.isBusy else { return }
        selectedIDs = Set(apps.map(\.id)).intersection(ids.isEmpty ? Set(apps.map(\.id)) : ids)
        releaseLease()
        session.invalidate()
        clearTransientError()
    }

    func clearSelection() {
        guard !isListing, !session.isBusy else { return }
        selectedIDs.removeAll()
        releaseLease()
        session.invalidate()
        clearTransientError()
    }

    func previewUninstall() async {
        guard !isListing, !session.isBusy else { return }
        releaseLease()
        session.invalidate()
        clearTransientError()
        let batch: [UninstallApp]
        do {
            batch = try UninstallSelectionValidator.batch(selectedIDs: selectedIDs, apps: apps)
        } catch {
            setTransientError(error)
            return
        }
        guard let operationID = session.beginPreview() else { return }
        guard let newLease = coordinator.acquire(.uninstall) else {
            session.fail(
                OperationResult(status: .failed, errorKey: "operation.error.busy"),
                id: operationID
            )
            return
        }
        lease = newLease
        previewCoordinatorGeneration = coordinator.invalidationGeneration

        do {
            let result = try await process.run(
                ["uninstall", "--dry-run"] + batch.map(\.uninstallName),
                stdin: Self.confirmationInput,
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
            session.acceptPreview(
                UninstallPreviewSnapshot(
                    generation: operationID,
                    apps: batch,
                    selectedIDs: selectedIDs,
                    output: outputSummary(result)
                ),
                id: operationID
            )
            releaseLease(clearPreviewGeneration: false)
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
                id: operationID
            )
            releaseLease()
        } catch {
            guard session.accepts(operationID) else { return }
            let summary = (error as? MoleBridgeError).flatMap { commandError -> String? in
                if case let .commandFailed(result) = commandError { return outputSummary(result) }
                return commandError.localizedDescription
            }
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: "uninstall.error.failed"),
                id: operationID
            )
            releaseLease()
        }
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
              let currentPreview = session.preview,
              let previewID = operationID(for: session.state) else { return }
        guard let newLease = coordinator.acquire(.uninstall) else {
            session.fail(
                OperationResult(status: .failed, errorKey: "operation.error.busy"),
                id: previewID
            )
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
            let current = try await fetchList()
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            guard selectedIDs == currentPreview.selectedIDs else {
                throw UninstallViewModelError.changedTarget
            }
            let currentBatch = try UninstallSelectionValidator.batch(
                selectedIDs: currentPreview.selectedIDs,
                apps: current.apps
            )
            guard Set(currentBatch.map(\.identity)) == currentPreview.identities else {
                throw UninstallViewModelError.changedTarget
            }
            apps = current.apps
            listGeneration = current.generation
            let result = try await process.run(
                ["uninstall"] + currentBatch.map(\.uninstallName),
                stdin: Self.confirmationInput,
                timeout: 600
            )
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            let operationResult = UninstallBatchResultParser.result(
                result,
                expectedCount: currentBatch.count
            )
            session.finish(operationResult, id: execution.id)
            coordinator.invalidatePreviews()
            releaseLease()
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
                id: execution.id
            )
            coordinator.invalidatePreviews()
            releaseLease()
        } catch {
            guard session.accepts(execution.id) else { return }
            let result: OperationResult
            if let commandError = error as? MoleBridgeError,
               case let .commandFailed(commandResult) = commandError {
                result = UninstallBatchResultParser.result(
                    commandResult,
                    expectedCount: currentPreview.apps.count
                )
            } else if let domainError = error as? UninstallViewModelError {
                result = OperationResult(status: .failed, errorKey: domainError.errorKey)
            } else {
                result = OperationResult(status: .failed, summary: error.localizedDescription, errorKey: "uninstall.error.failed")
            }
            session.fail(result, id: execution.id)
            releaseLease()
        }
    }

    func cancelExecution() async {
        guard let operationID = session.beginExecutionCancellation() else { return }
        await process.cancel()
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
            id: operationID
        )
        coordinator.invalidatePreviews()
        releaseLease()
    }

    private func fetchList() async throws -> UninstallListSnapshot {
        let result = try await process.run(["uninstall", "--list"], stdin: nil, timeout: 120)
        guard result.exitCode == 0 else { throw MoleBridgeError.commandFailed(result) }
        return UninstallListSnapshot(
            generation: UUID(),
            apps: try UninstallListDecoder.decode(result.stdout)
        )
    }

    private func operationID(for state: OperationState<UninstallPreviewSnapshot>) -> UUID? {
        switch state {
        case let .ready(id, _), let .confirming(id, _), let .executing(id, _): return id
        default: return nil
        }
    }

    private var isCurrentPreview: Bool {
        guard let generation = previewCoordinatorGeneration else { return false }
        return coordinator.isCurrent(generation)
    }

    private func expirePreviewIfNeeded(generation: UInt64) {
        guard let previewGeneration = previewCoordinatorGeneration,
              previewGeneration != generation,
              session.preview != nil else { return }
        session.expirePreview(errorKey: "operation.error.stale_preview")
        previewCoordinatorGeneration = nil
    }

    private func releaseLease(clearPreviewGeneration: Bool = true) {
        lease?.release()
        lease = nil
        if clearPreviewGeneration {
            previewCoordinatorGeneration = nil
        }
    }

    private func clearTransientError() {
        transientErrorKey = nil
        objectWillChange.send()
    }

    private func setTransientError(_ error: Error) {
        transientErrorKey = (error as? UninstallViewModelError)?.errorKey
            ?? "uninstall.error.failed"
        objectWillChange.send()
    }

    private func outputSummary(_ result: MoleCommandResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let confirmationInput = Data("y\n".utf8)
}
