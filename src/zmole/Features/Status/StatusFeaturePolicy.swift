import Combine
import Foundation

@MainActor
final class StatusFeaturePolicy: ObservableObject {
    static let storageKey = "feature.status.enabled"

    @Published private(set) var isEnabled: Bool

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.storageKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = userDefaults.bool(forKey: Self.storageKey)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        userDefaults.set(enabled, forKey: Self.storageKey)
    }
}
