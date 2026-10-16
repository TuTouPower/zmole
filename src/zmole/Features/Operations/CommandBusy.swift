import Foundation

/// Classifies transient "another mole command is running" contention so pages
/// can show a recoverable notice instead of a failure.
enum CommandBusy {
    static func isBusy(_ error: Error) -> Bool {
        (error as? MoleBridgeError)?.isBusy == true
    }
}
