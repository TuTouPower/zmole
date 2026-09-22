import Foundation

typealias PurgePreviewSnapshot = MaintenancePreviewSnapshot

enum PurgeViewModelError: Error, Equatable, Sendable {
    case missingMole

    var errorKey: String {
        switch self {
        case .missingMole:
            return "purge.error.missing_mole"
        }
    }
}
