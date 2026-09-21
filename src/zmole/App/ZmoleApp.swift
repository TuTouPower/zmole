import SwiftUI

@main
struct ZmoleApp: App {
    var body: some Scene {
        WindowGroup("app.name") {
            AppShellView()
        }
    }
}

struct AppShellView: View {
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue

    var body: some View {
        ContentView()
            .environment(\.locale, resolvedLocale)
    }

    private var resolvedLocale: Locale {
        guard let language = AppLanguage(rawValue: languageOverride), language != .system else {
            return .current
        }
        return language.locale
    }
}
