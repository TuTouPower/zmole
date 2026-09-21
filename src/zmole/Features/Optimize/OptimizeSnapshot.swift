import Foundation

struct OptimizePreviewSnapshot: Equatable, Sendable {
    let generation: UUID
    let output: String
}

enum OptimizeViewModelError: Error, Equatable, Sendable {
    case missingMole

    var errorKey: String {
        switch self {
        case .missingMole:
            return "optimize.error.missing_mole"
        }
    }
}
