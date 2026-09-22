import Combine
import Foundation

enum WriteOperation: Hashable, Sendable {
    case clean
    case uninstall
    case optimize
    case purge
    case protectionRules
}

@MainActor
final class OperationCoordinator: ObservableObject {
    @Published private(set) var invalidationGeneration: UInt64 = 0
    @Published private(set) var activeOperation: WriteOperation?

    private var activeLeaseID: UUID?

    @discardableResult
    func acquire(_ operation: WriteOperation) -> OperationLease? {
        guard activeLeaseID == nil else { return nil }
        let id = UUID()
        activeLeaseID = id
        activeOperation = operation
        return OperationLease(id: id, operation: operation, coordinator: self)
    }

    func invalidatePreviews() {
        invalidationGeneration &+= 1
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == invalidationGeneration
    }

    fileprivate func release(_ lease: OperationLease) {
        guard activeLeaseID == lease.id else { return }
        activeLeaseID = nil
        activeOperation = nil
    }
}

@MainActor
final class OperationLease {
    fileprivate let id: UUID
    let operation: WriteOperation
    private weak var coordinator: OperationCoordinator?
    private var isReleased = false

    fileprivate init(id: UUID, operation: WriteOperation, coordinator: OperationCoordinator) {
        self.id = id
        self.operation = operation
        self.coordinator = coordinator
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        coordinator?.release(self)
    }
}
