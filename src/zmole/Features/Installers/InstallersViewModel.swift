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
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var showBusyNotice = false
    @Published private(set) var listCapturedAt: Date?

    /// Snapshot of the listing that the current selection/confirmation binds to.
    /// A new scan replaces it and clears the selection.
    private var lastListing: [InstallerCandidate] = []

    private let interface: InstallerInterface
    private let coordinator: OperationCoordinator
    private let accessMonitor: FullDiskAccessMonitor?
    private weak var scan: (any BackgroundScanProviding)?
    private var lease: OperationLease?
    private var removalCancelled = false

    init(
        interface: InstallerInterface,
        coordinator: OperationCoordinator,
        scan: (any BackgroundScanProviding)? = nil,
        accessMonitor: FullDiskAccessMonitor? = nil
    ) {
        self.interface = interface
        self.coordinator = coordinator
        self.scan = scan
        self.accessMonitor = accessMonitor
    }

    private var diskAccessGranted: Bool {
        accessMonitor?.isGranted ?? true
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

    /// Uses the background scan result when it exists; otherwise scans now.
    /// The session list is kept until the user re-scans or a removal updates it.
    func loadListIfNeeded() async {
        guard diskAccessGranted else { return }
        guard candidates.isEmpty, !isListing, !isRemoving else { return }
        if adoptPrewarmList() { return }
        await scan()
    }

    func scan() async {
        guard diskAccessGranted else { return }
        guard !isListing, !isRemoving else { return }
        scan?.userDidRescan(.installerList)
        isListing = true
        errorMessage = nil
        errorMessageKey = nil
        showBusyNotice = false
        failures = []
        listCapturedAt = nil
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
            errorMessageKey = error.localizationKey
            errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
        }
    }

    private func adoptPrewarmList() -> Bool {
        guard let result = scan?.result(for: .installerList),
              case let .installerCandidates(list) = result.payload else { return false }
        candidates = list
        lastListing = list
        selectedPaths.removeAll()
        isConfirmationPresented = false
        listCapturedAt = result.capturedAt
        return true
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

    /// Stops the batch after the item that is currently being removed.
    func cancelRemoval() {
        guard isRemoving else { return }
        removalCancelled = true
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
        removalCancelled = false
        isConfirmationPresented = false
        defer {
            isRemoving = false
            removalCancelled = false
            lease?.release()
            lease = nil
            coordinator.invalidatePreviews()
        }

        var rejected: [InstallerRemovalFailure] = []
        var removedPaths: Set<String> = []
        removal: for candidate in batch {
            if removalCancelled { break removal }
            switch await interface.remove(candidate) {
            case .removed:
                removedPaths.insert(candidate.path)
            case .busy:
                // Transient contention: stop the batch, keep the remaining
                // selection, and surface the recoverable notice.
                showBusyNotice = true
                break removal
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
