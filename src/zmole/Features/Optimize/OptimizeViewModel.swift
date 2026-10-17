import Foundation

@MainActor
final class OptimizeViewModel: MaintenanceViewModel {
    private var cachedPlanRows: (output: String, rows: [OptimizePlanRow])?

    init(
        process: any MoleProcessControlling,
        coordinator: OperationCoordinator,
        scan: (any BackgroundScanProviding)? = nil
    ) {
        super.init(kind: .optimize, process: process, coordinator: coordinator, scan: scan)
    }

    /// Dry-run rows parsed once per preview output so repeated body
    /// evaluations do not re-split and re-scan the text.
    func planRows() -> [OptimizePlanRow] {
        guard let preview else { return [] }
        if let cache = cachedPlanRows, cache.output == preview.output {
            return cache.rows
        }
        let rows = OptimizePlanParser.rows(from: preview.output)
        cachedPlanRows = (preview.output, rows)
        return rows
    }

    func confirmExecution() async { await confirmMaintenance() }
}
