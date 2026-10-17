import Foundation

@MainActor
final class PurgeViewModel: MaintenanceViewModel {
    init(
        process: any MoleProcessControlling,
        coordinator: OperationCoordinator,
        scan: (any BackgroundScanProviding)? = nil
    ) {
        super.init(kind: .purge, process: process, coordinator: coordinator, scan: scan)
    }

    func previewPurge() async { await previewMaintenance() }
    func confirmExecution() async { await confirmMaintenance() }
}
