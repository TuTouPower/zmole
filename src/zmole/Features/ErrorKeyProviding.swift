import Foundation

/// Errors that expose a string-catalog key for their user-facing copy, so
/// views render through the localized string catalog (and the app's language
/// override) instead of a hardcoded description.
protocol ErrorKeyProviding {
    var errorKey: String { get }
}

extension Error {
    /// The localization key carried by this error, when it provides one.
    var localizationKey: String? {
        (self as? ErrorKeyProviding)?.errorKey
    }
}
