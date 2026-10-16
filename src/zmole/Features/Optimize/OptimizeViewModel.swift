import Foundation

@MainActor
final class OptimizeViewModel: MaintenanceViewModel {
    init(
        process: any MoleProcessControlling,
        coordinator: OperationCoordinator,
        prewarm: (any PrewarmResultProviding)? = nil
    ) {
        super.init(kind: .optimize, process: process, coordinator: coordinator, prewarm: prewarm)
    }

    func previewOptimize() async { await previewMaintenance() }
    func confirmExecution() async { await confirmMaintenance() }
}
