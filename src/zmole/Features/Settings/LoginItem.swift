import Combine
import Foundation
import ServiceManagement

enum LoginItemError: Error, Equatable, LocalizedError, Sendable {
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(reason): reason
        }
    }
}

protocol LoginItemControlling: Sendable {
    /// Registers the main app as a login item. Throws with a human-readable
    /// reason when registration fails (for example the app is not in
    /// /Applications).
    func register() throws
    func unregister() throws
    func isEnabled() -> Bool
}

struct SMAppServiceLoginItem: LoginItemControlling {
    func register() throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LoginItemError.registrationFailed(error.localizedDescription)
        }
    }

    func unregister() throws {
        try? SMAppService.mainApp.unregister()
    }

    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}

@MainActor
final class LoginItemViewModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var failureReason: String?

    private let service: LoginItemControlling

    init(service: LoginItemControlling = SMAppServiceLoginItem()) {
        self.service = service
        isEnabled = service.isEnabled()
    }

    /// Only reports enabled when registration actually succeeds; a failure keeps
    /// the toggle off and surfaces the reason.
    func setEnabled(_ enabled: Bool) {
        failureReason = nil
        if enabled {
            do {
                try service.register()
                if service.isEnabled() {
                    isEnabled = true
                } else {
                    isEnabled = false
                    failureReason = String(localized: "settings.login_item.pending")
                }
            } catch {
                isEnabled = false
                failureReason = error.localizedDescription
            }
        } else {
            do {
                try service.unregister()
                isEnabled = service.isEnabled()
            } catch {
                failureReason = error.localizedDescription
            }
        }
    }
}
