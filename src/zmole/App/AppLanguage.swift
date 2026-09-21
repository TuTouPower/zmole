import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    static let storageKey = "languageOverride"

    var id: Self { self }

    var labelKey: LocalizedStringKey {
        switch self {
        case .system: "settings.language.system"
        case .english: "settings.language.en"
        case .simplifiedChinese: "settings.language.zh-Hans"
        case .traditionalChinese: "settings.language.zh-Hant"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}
