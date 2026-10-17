import Combine
import Foundation

enum WriteOperation: Hashable, Sendable {
    case clean
    case uninstall
    case optimize
    case purge
    case installer
    case protectionRules
    case cleanWhitelist
    case optimizeWhitelist
    case purgePaths
}

enum OverviewDirectoryInput: String, CaseIterable, Hashable, Sendable {
    case applications
    case system
    case developer
    case userData
}

struct DataImpact: Equatable, Sendable {
    let scanItems: Set<BackgroundScanItem>
    let overviewInputs: Set<OverviewDirectoryInput>

    static let empty = DataImpact(scanItems: [], overviewInputs: [])

    static func forOperation(_ operation: WriteOperation, paths: [String]? = nil) -> DataImpact {
        switch operation {
        case .clean:
            return DataImpact(
                scanItems: Set(BackgroundScanItem.allCases),
                overviewInputs: Set(OverviewDirectoryInput.allCases)
            )
        case .uninstall:
            return DataImpact(
                scanItems: Set(BackgroundScanItem.allCases),
                overviewInputs: Set(OverviewDirectoryInput.allCases)
            )
        case .optimize:
            return DataImpact(
                scanItems: [.optimize, .clean],
                overviewInputs: [.userData, .system]
            )
        case .purge:
            return DataImpact(
                scanItems: [.purge, .clean],
                overviewInputs: [.developer, .userData]
            )
        case .installer:
            return DataImpact(
                scanItems: [.installerList, .clean],
                overviewInputs: [.userData]
            )
        case .cleanWhitelist, .protectionRules:
            return DataImpact(
                scanItems: [.clean],
                overviewInputs: []
            )
        case .optimizeWhitelist:
            return DataImpact(
                scanItems: [.optimize],
                overviewInputs: []
            )
        case .purgePaths:
            return DataImpact(
                scanItems: [.purge, .clean],
                overviewInputs: []
            )
        }
    }
}

@MainActor
final class OperationCoordinator: ObservableObject {
    @Published private(set) var invalidationGeneration: UInt64 = 0
    @Published private(set) var activeOperation: WriteOperation?

    private(set) var scanItemVersions: [BackgroundScanItem: UInt64] = [:]
    private(set) var overviewInputVersions: [OverviewDirectoryInput: UInt64] = [:]

    let settledOperations = PassthroughSubject<(id: UUID, impact: DataImpact), Never>()

    private var activeLeaseID: UUID?

    @discardableResult
    func acquire(_ operation: WriteOperation, impact: DataImpact? = nil) -> OperationLease? {
        guard activeLeaseID == nil else { return nil }
        let id = UUID()
        activeLeaseID = id
        activeOperation = operation
        let resolvedImpact = impact ?? DataImpact.forOperation(operation)
        return OperationLease(id: id, operation: operation, impact: resolvedImpact, coordinator: self)
    }

    func restoreVersion(_ version: UInt64, for item: BackgroundScanItem) {
        scanItemVersions[item] = max(scanItemVersions[item] ?? 0, version)
    }

    func version(for item: BackgroundScanItem) -> UInt64 {
        scanItemVersions[item] ?? 0
    }

    func version(for input: OverviewDirectoryInput) -> UInt64 {
        overviewInputVersions[input] ?? 0
    }

    func invalidatePreviews() {
        invalidationGeneration &+= 1
    }

    func invalidateConfirmations() {
        invalidationGeneration &+= 1
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == invalidationGeneration
    }

    fileprivate func release(_ lease: OperationLease) {
        guard activeLeaseID == lease.id else { return }
        activeLeaseID = nil
        activeOperation = nil

        if lease.hasModifiedData {
            for item in lease.impact.scanItems {
                scanItemVersions[item] = (scanItemVersions[item] ?? 0) &+ 1
            }
            for input in lease.impact.overviewInputs {
                overviewInputVersions[input] = (overviewInputVersions[input] ?? 0) &+ 1
            }
            settledOperations.send((lease.id, lease.impact))
        }
    }
}

@MainActor
final class OperationLease {
    fileprivate let id: UUID
    let operation: WriteOperation
    let impact: DataImpact
    private(set) var hasModifiedData = false
    private weak var coordinator: OperationCoordinator?
    private var isReleased = false

    fileprivate init(
        id: UUID,
        operation: WriteOperation,
        impact: DataImpact,
        coordinator: OperationCoordinator
    ) {
        self.id = id
        self.operation = operation
        self.impact = impact
        self.coordinator = coordinator
    }

    func markDataModified() {
        hasModifiedData = true
    }

    func markDataUnmodified() {
        hasModifiedData = false
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        coordinator?.release(self)
    }
}
