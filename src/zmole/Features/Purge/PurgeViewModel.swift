import Foundation

@MainActor
final class PurgeViewModel: MaintenanceViewModel {
    init(
        process: any MoleProcessControlling,
        coordinator: OperationCoordinator,
        prewarm: (any PrewarmResultProviding)? = nil
    ) {
        super.init(kind: .purge, process: process, coordinator: coordinator, prewarm: prewarm)
    }

    func previewPurge() async { await previewMaintenance() }
    func confirmExecution() async { await confirmMaintenance() }
}
