import Foundation

@MainActor
final class PurgeViewModel: MaintenanceViewModel {
    init(process: any MoleProcessControlling, coordinator: OperationCoordinator) {
        super.init(kind: .purge, process: process, coordinator: coordinator)
    }

    func previewPurge() async { await previewMaintenance() }
    func confirmExecution() async { await confirmMaintenance() }
}
