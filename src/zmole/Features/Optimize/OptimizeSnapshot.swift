import Foundation

typealias OptimizePreviewSnapshot = MaintenancePreviewSnapshot

enum OptimizeViewModelError: Error, Equatable, Sendable {
    case missingMole

    var errorKey: String {
        switch self {
        case .missingMole:
            return "optimize.error.missing_mole"
        }
    }
}
