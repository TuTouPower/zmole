import Combine
import Foundation

@MainActor
final class CleanViewModel: ObservableObject {
    @Published private(set) var preview: CleanPreviewSnapshot?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isExecuting = false
    @Published private(set) var isConfirmationPresented = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var executionSummary: String?

    private let process: (any MoleProcessControlling)?
    private let initializationErrorKey: String?
    private let previewStore: CleanPreviewStore
    private var activeOperationID: UUID?

    var canConfirm: Bool {
        preview != nil && !isPreviewing && !isExecuting
    }

    init(
        process: any MoleProcessControlling,
        previewStore: CleanPreviewStore
    ) {
        self.process = process
        initializationErrorKey = nil
        self.previewStore = previewStore
    }

    init(previewStore: CleanPreviewStore = .live) {
        self.previewStore = previewStore
        if let bridge = try? MoleBridge() {
            process = bridge
            initializationErrorKey = nil
        } else {
            process = nil
            initializationErrorKey = "clean.error.missing_mole"
        }
    }

    func previewClean() async {
        guard !isPreviewing, !isExecuting else { return }
        invalidatePreview()
        errorMessage = nil
        errorMessageKey = nil
        executionSummary = nil

        let operationID = UUID()
        activeOperationID = operationID
        isPreviewing = true
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
                isPreviewing = false
            }
        }

        guard let process else {
            errorMessageKey = initializationErrorKey
            return
        }

        do {
            let generation = try previewStore.begin()
            let result = try await process.run(
                ["clean", "--dry-run"],
                stdin: nil,
                timeout: 120
            )
            guard activeOperationID == operationID else { return }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            preview = try previewStore.read(generation)
        } catch {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            setError(error)
        }
    }

    func cancelPreview() async {
        guard isPreviewing else { return }
        activeOperationID = nil
        isPreviewing = false
        invalidatePreview()
        await process?.cancel()
    }

    func requestConfirmation() {
        guard canConfirm else { return }
        isConfirmationPresented = true
    }

    func cancelConfirmation() {
        guard isConfirmationPresented else { return }
        isConfirmationPresented = false
        invalidatePreview()
    }

    func confirmExecution() async {
        guard isConfirmationPresented, let preview, canConfirm, let process else { return }
        do {
            try previewStore.verifyUnchanged(preview)
        } catch {
            invalidatePreview()
            setError(error)
            return
        }

        isConfirmationPresented = false
        errorMessage = nil
        errorMessageKey = nil
        executionSummary = nil
        isExecuting = true
        let operationID = UUID()
        activeOperationID = operationID
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
                isExecuting = false
            }
        }

        do {
            let result = try await process.run(["clean"], stdin: nil, timeout: 600)
            guard activeOperationID == operationID else { return }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            executionSummary = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            invalidatePreview()
        } catch let error as MoleBridgeError where error == .cancelled {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            errorMessage = nil
            errorMessageKey = "clean.cancelled"
        } catch {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            if case let MoleBridgeError.commandFailed(result) = error {
                executionSummary = outputSummary(result)
            }
            setError(error)
        }
    }

    func cancelExecution() async {
        guard isExecuting else { return }
        await process?.cancel()
    }

    private func invalidatePreview() {
        preview = nil
        isConfirmationPresented = false
    }

    private func setError(_ error: Error) {
        errorMessage = error.localizedDescription
        if let error = error as? CleanPreviewStoreError {
            errorMessage = nil
            errorMessageKey = error.errorKey
        } else {
            errorMessageKey = nil
        }
    }

    private func outputSummary(_ result: MoleCommandResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
