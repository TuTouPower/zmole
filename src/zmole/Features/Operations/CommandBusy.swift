import Foundation

/// Classifies transient "another mole command is running" contention so pages
/// can show a recoverable notice instead of a failure.
enum CommandBusy {
    static func commandDidNotStart(_ error: Error) -> Bool {
        if isBusy(error) { return true }
        guard let error = error as? MoleBridgeError else { return false }
        switch error {
        case .executableNotFound, .launchFailed: return true
        default: return false
        }
    }

    static func isBusy(_ error: Error) -> Bool {
        (error as? MoleBridgeError)?.isBusy == true
    }
}
