import Combine
import Foundation

/// Shared write-lease and preview-generation machinery for the three write
/// view models (clean, uninstall, maintenance). One instance per view model:
/// it owns the coordinator lease, tracks the generation the current preview
/// was produced under, and reports when another write invalidates it.
@MainActor
final class PreviewLeaseCoordinator {
    private let coordinator: OperationCoordinator
    private var lease: OperationLease?
    private var previewGeneration: UInt64?
    private var subscription: AnyCancellable?

    /// Called when another write bumps the coordinator generation past the
    /// tracked preview. Return true when the owner expired its preview; the
    /// coordinator then drops the tracked generation.
    var onInvalidation: (() -> Bool)?

    init(coordinator: OperationCoordinator) {
        self.coordinator = coordinator
        subscription = coordinator.$invalidationGeneration.sink { [weak self] generation in
            self?.handleInvalidation(generation)
        }
    }

    /// True while the current preview was produced under the coordinator's
    /// generation (no other write invalidated it since).
    var isCurrentPreview: Bool {
        guard let previewGeneration else { return false }
        return coordinator.isCurrent(previewGeneration)
    }

    /// Takes the write lease for the given operation, or false when another
    /// write holds it.
    func acquire(_ operation: WriteOperation) -> Bool {
        guard let newLease = coordinator.acquire(operation) else { return false }
        lease = newLease
        return true
    }

    /// Records the generation the next preview is produced under (or that an
    /// execution just re-anchored).
    func captureGeneration() {
        previewGeneration = coordinator.invalidationGeneration
    }

    /// A write finished: expire sibling previews and re-anchor this
    /// coordinator to the new generation.
    func invalidateAndRecapture() {
        coordinator.invalidatePreviews()
        captureGeneration()
    }

    /// Forwards a plain invalidation after an execution/teardown path.
    func invalidatePreviews() {
        coordinator.invalidatePreviews()
    }

    func markDataModified() {
        lease?.markDataModified()
    }

    func release(clearPreviewGeneration: Bool = true) {
        lease?.release()
        lease = nil
        if clearPreviewGeneration {
            previewGeneration = nil
        }
    }

    private func handleInvalidation(_ generation: UInt64) {
        guard let tracked = previewGeneration, tracked != generation else { return }
        if onInvalidation?() ?? false {
            previewGeneration = nil
        }
    }
}

/// The in-flight operation id from an `OperationState` (ready / confirming /
/// executing); binds a confirmed preview to its execution.
enum PreviewOperationID {
    static func from<Preview>(_ state: OperationState<Preview>) -> UUID? {
        switch state {
        case let .ready(id, _), let .confirming(id, _), let .executing(id, _): return id
        default: return nil
        }
    }
}
