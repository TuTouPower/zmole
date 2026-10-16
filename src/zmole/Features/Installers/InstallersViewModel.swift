import Combine
import Foundation

@MainActor
final class InstallersViewModel: ObservableObject {
    @Published private(set) var candidates: [InstallerCandidate] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var failures: [InstallerRemovalFailure] = []
    @Published private(set) var isListing = false
    @Published private(set) var isRemoving = false
    @Published private(set) var isConfirmationPresented = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var showBusyNotice = false

    /// Snapshot of the listing that the current selection/confirmation binds to.
    /// A new scan replaces it and clears the selection.
    private var lastListing: [InstallerCandidate] = []

    private let interface: InstallerInterface
    private let coordinator: OperationCoordinator
    private var lease: OperationLease?

    init(interface: InstallerInterface, coordinator: OperationCoordinator) {
        self.interface = interface
        self.coordinator = coordinator
    }

    var selectedCandidates: [InstallerCandidate] {
        lastListing.filter { selectedPaths.contains($0.path) }
    }

    var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    var canConfirm: Bool {
        !isListing && !isRemoving
            && !selectedPaths.isEmpty
            && selectedPaths.isSubset(of: Set(lastListing.map(\.path)))
    }

    /// Human-readable count + size used by the confirmation dialog.
    var confirmationDetail: String {
        let count = selectedCandidates.count
        let unit = String(localized: "installers.confirm_count_unit")
        let size = ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
        return "\(count) \(unit) · \(size)"
    }

    func scan() async {
        guard !isListing, !isRemoving else { return }
        isListing = true
        errorMessage = nil
        showBusyNotice = false
        failures = []
        defer { isListing = false }
        do {
            let list = try await interface.list()
            candidates = list
            lastListing = list
            selectedPaths.removeAll()
            isConfirmationPresented = false
        } catch {
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                return
            }
            candidates = []
            lastListing = []
            selectedPaths.removeAll()
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(_ candidate: InstallerCandidate) {
        guard !isListing, !isRemoving else { return }
        if selectedPaths.contains(candidate.path) {
            selectedPaths.remove(candidate.path)
        } else {
            selectedPaths.insert(candidate.path)
        }
    }

    func selectAll() {
        guard !isListing, !isRemoving else { return }
        selectedPaths = Set(candidates.map(\.path))
    }

    func clearSelection() {
        guard !isListing, !isRemoving else { return }
        selectedPaths.removeAll()
    }

    func requestConfirmation() {
        guard canConfirm else { return }
        isConfirmationPresented = true
    }

    func cancelConfirmation() {
        isConfirmationPresented = false
    }

    func confirmRemoval() async {
        guard isConfirmationPresented, canConfirm else { return }
        let batch = selectedCandidates
        guard !batch.isEmpty else { return }
        guard let newLease = coordinator.acquire(.installer) else {
            showBusyNotice = true
            isConfirmationPresented = false
            return
        }
        lease = newLease
        showBusyNotice = false
        isRemoving = true
        isConfirmationPresented = false
        defer {
            isRemoving = false
            lease?.release()
            lease = nil
            coordinator.invalidatePreviews()
        }

        var rejected: [InstallerRemovalFailure] = []
        var removedPaths: Set<String> = []
        for candidate in batch {
            switch await interface.remove(candidate) {
            case .removed:
                removedPaths.insert(candidate.path)
            case let .failed(reason):
                rejected.append(InstallerRemovalFailure(path: candidate.path, reason: reason))
            }
        }
        selectedPaths.subtract(removedPaths)
        failures = rejected
        candidates = candidates.filter { !removedPaths.contains($0.path) }
        lastListing = lastListing.filter { !removedPaths.contains($0.path) }
    }
}
