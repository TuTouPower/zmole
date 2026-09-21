import Foundation

struct PurgePreviewSnapshot: Equatable, Sendable {
    let generation: UUID
    let output: String
}

enum PurgeViewModelError: Error, Equatable, Sendable {
    case missingMole

    var errorKey: String {
        switch self {
        case .missingMole:
            return "purge.error.missing_mole"
        }
    }
}
