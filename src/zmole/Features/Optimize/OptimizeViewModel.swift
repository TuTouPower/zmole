import Combine
import Foundation

@MainActor
final class OptimizeViewModel: ObservableObject {
    @Published private(set) var preview: OptimizePreviewSnapshot?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isExecuting = false
    @Published private(set) var isConfirmationPresented = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var executionSummary: String?

    private let process: (any MoleProcessControlling)?
    private let initializationErrorKey: String?
    private var activeOperationID: UUID?

    var canConfirm: Bool {
        preview != nil && !isPreviewing && !isExecuting
    }

    init(process: any MoleProcessControlling) {
        self.process = process
        initializationErrorKey = nil
    }

    init() {
        if let bridge = try? MoleBridge() {
            process = bridge
            initializationErrorKey = nil
        } else {
            process = nil
            initializationErrorKey = "optimize.error.missing_mole"
        }
    }

    func previewOptimize() async {
        guard !isPreviewing, !isExecuting else { return }
        invalidatePreview()
        clearError()
        executionSummary = nil

        guard let process else {
            errorMessageKey = initializationErrorKey
            return
        }

        let operationID = UUID()
        activeOperationID = operationID
        isPreviewing = true
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
                isPreviewing = false
            }
        }

        do {
            let result = try await process.run(
                ["optimize", "--dry-run"],
                stdin: nil,
                timeout: 120
            )
            guard activeOperationID == operationID else { return }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            preview = OptimizePreviewSnapshot(
                generation: UUID(),
                output: OptimizeOutput.summary(stdout: result.stdout)
            )
        } catch {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            if case let MoleBridgeError.commandFailed(result) = error {
                executionSummary = OptimizeOutput.summary(
                    stdout: result.stdout,
                    stderr: result.stderr
                )
            }
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
        invalidatePreview()
    }

    func confirmExecution() async {
        guard isConfirmationPresented, canConfirm else { return }
        guard let process else {
            invalidatePreview()
            setError(OptimizeViewModelError.missingMole)
            return
        }

        isConfirmationPresented = false
        clearError()
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
            let result = try await process.run(["optimize"], stdin: nil, timeout: 600)
            guard activeOperationID == operationID else { return }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            executionSummary = OptimizeOutput.summary(
                stdout: result.stdout,
                stderr: result.stderr
            )
            invalidatePreview()
        } catch let error as MoleBridgeError where error == .cancelled {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            errorMessageKey = "optimize.cancelled"
        } catch {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            if case let MoleBridgeError.commandFailed(result) = error {
                executionSummary = OptimizeOutput.summary(
                    stdout: result.stdout,
                    stderr: result.stderr
                )
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

    private func clearError() {
        errorMessage = nil
        errorMessageKey = nil
    }

    private func setError(_ error: Error) {
        if let error = error as? OptimizeViewModelError {
            errorMessage = nil
            errorMessageKey = error.errorKey
        } else if error is MoleBridgeError {
            errorMessage = nil
            errorMessageKey = "optimize.error.failed"
        } else {
            errorMessage = error.localizedDescription
            errorMessageKey = nil
        }
    }
}
