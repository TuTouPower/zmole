import Foundation

@MainActor
final class OptimizeViewModel: MaintenanceViewModel {
    init(process: any MoleProcessControlling, coordinator: OperationCoordinator) {
        super.init(kind: .optimize, process: process, coordinator: coordinator)
    }

    func previewOptimize() async { await previewMaintenance() }
    func confirmExecution() async { await confirmMaintenance() }
}
