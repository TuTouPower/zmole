import Combine
import Foundation

@MainActor
final class UninstallViewModel: ObservableObject {
    @Published private(set) var apps: [UninstallApp] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var preview: UninstallPreviewSnapshot?
    @Published private(set) var isListing = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var isExecuting = false
    @Published private(set) var isConfirmationPresented = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var executionSummary: String?

    private let process: (any MoleProcessControlling)?
    private let initializationErrorKey: String?
    private var listGeneration = UUID()
    private var activeOperationID: UUID?

    var canPreview: Bool {
        selectedIDs.count == 1 && !isListing && !isPreviewing && !isExecuting
    }

    var canConfirm: Bool {
        guard let preview else { return false }
        return selectedIDs == preview.selectedIDs
            && !isListing
            && !isPreviewing
            && !isExecuting
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
            initializationErrorKey = "uninstall.error.missing_mole"
        }
    }

    func loadListIfNeeded() async {
        guard !hasLoaded else { return }
        await loadList()
    }

    func loadList() async {
        guard !isListing, !isPreviewing, !isExecuting else { return }
        invalidatePreview()
        selectedIDs.removeAll()
        clearError()
        executionSummary = nil

        let operationID = UUID()
        activeOperationID = operationID
        isListing = true
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
                isListing = false
            }
        }

        do {
            let snapshot = try await fetchList()
            guard activeOperationID == operationID else { return }
            apps = snapshot.apps
            listGeneration = snapshot.generation
            hasLoaded = true
        } catch {
            guard activeOperationID == operationID else { return }
            apps = []
            hasLoaded = false
            setError(error)
        }
    }

    func cancelList() async {
        guard isListing else { return }
        activeOperationID = nil
        isListing = false
        await process?.cancel()
    }

    func cancelPreview() async {
        guard isPreviewing else { return }
        activeOperationID = nil
        isPreviewing = false
        invalidatePreview()
        await process?.cancel()
    }

    func toggleSelection(_ app: UninstallApp) {
        guard !isListing, !isPreviewing, !isExecuting else { return }
        if selectedIDs.contains(app.id) {
            selectedIDs.remove(app.id)
        } else {
            selectedIDs = [app.id]
        }
        invalidatePreview()
        clearError()
        executionSummary = nil
    }

    func previewUninstall() async {
        guard !isListing, !isPreviewing, !isExecuting else { return }
        invalidatePreview()
        clearError()
        executionSummary = nil

        let target: UninstallApp
        do {
            target = try selectedTarget(in: apps)
        } catch {
            setError(error)
            return
        }
        guard process != nil else {
            setError(UninstallViewModelError.missingMole)
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
            guard let process else { throw UninstallViewModelError.missingMole }
            let result = try await process.run(
                ["uninstall", "--dry-run", target.uninstallName],
                stdin: Self.confirmationInput,
                timeout: 120
            )
            guard activeOperationID == operationID else { return }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            preview = UninstallPreviewSnapshot(
                generation: listGeneration,
                target: target,
                selectedIDs: selectedIDs,
                output: outputSummary(result)
            )
        } catch {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            setError(error)
        }
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
        guard isConfirmationPresented, let preview, canConfirm else { return }
        guard process != nil else {
            invalidatePreview()
            setError(UninstallViewModelError.missingMole)
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
            let current = try await fetchList()
            guard activeOperationID == operationID else { return }
            guard selectedIDs == preview.selectedIDs else {
                throw UninstallViewModelError.changedTarget
            }

            guard let target = current.apps.first(where: { $0.id == preview.target.id }),
                  current.apps.filter({ $0.uninstallName == preview.target.uninstallName }).count == 1 else {
                throw UninstallViewModelError.changedTarget
            }

            apps = current.apps
            listGeneration = current.generation
            guard let process else { throw UninstallViewModelError.missingMole }
            let result = try await process.run(
                ["uninstall", target.uninstallName],
                stdin: Self.confirmationInput,
                timeout: 600
            )
            guard activeOperationID == operationID else { return }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            executionSummary = outputSummary(result)
            invalidatePreview()
        } catch let error as MoleBridgeError where error == .cancelled {
            guard activeOperationID == operationID else { return }
            invalidatePreview()
            errorMessageKey = "uninstall.cancelled"
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

    private func fetchList() async throws -> UninstallListSnapshot {
        guard let process else { throw UninstallViewModelError.missingMole }
        let result = try await process.run(
            ["uninstall", "--list"],
            stdin: nil,
            timeout: 120
        )
        guard result.exitCode == 0 else {
            throw MoleBridgeError.commandFailed(result)
        }
        return UninstallListSnapshot(
            generation: UUID(),
            apps: try UninstallListDecoder.decode(result.stdout)
        )
    }

    private func selectedTarget(in apps: [UninstallApp]) throws -> UninstallApp {
        guard let selectedID = selectedIDs.first,
              selectedIDs.count == 1,
              let target = apps.first(where: { $0.id == selectedID }) else {
            throw UninstallViewModelError.noSelection
        }
        guard apps.filter({ $0.uninstallName == target.uninstallName }).count == 1 else {
            throw UninstallViewModelError.ambiguousName
        }
        return target
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
        if let error = error as? UninstallViewModelError {
            errorMessage = nil
            errorMessageKey = error.errorKey
        } else {
            errorMessage = error.localizedDescription
            errorMessageKey = nil
        }
    }

    private func outputSummary(_ result: MoleCommandResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let confirmationInput = Data("y\n".utf8)
}
