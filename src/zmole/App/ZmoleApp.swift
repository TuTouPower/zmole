import SwiftUI

@main
struct ZmoleApp: App {
    @StateObject private var dependencies: AppDependencies
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue

    init() {
        _dependencies = StateObject(
            wrappedValue: AppDependencies(configuration: DemoConfiguration())
        )
    }

    var body: some Scene {
        WindowGroup("app.name") {
            AppShellView(dependencies: dependencies)
        }
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(demoLanguage: dependencies.demo.language)
                .environment(\.locale, resolvedLocale)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var resolvedLocale: Locale {
        if let language = dependencies.demo.language {
            return language.locale
        }
        guard let language = AppLanguage(rawValue: languageOverride), language != .system else {
            return .current
        }
        return language.locale
    }

    private var preferredColorScheme: ColorScheme? {
        switch dependencies.demo.appearance {
        case .light: return .light
        case .dark: return .dark
        case nil: return nil
        }
    }
}

struct AppShellView: View {
    @ObservedObject var dependencies: AppDependencies
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        ContentView(dependencies: dependencies)
            .environment(\.locale, resolvedLocale)
    }

    private var resolvedLocale: Locale {
        if let demoLanguage = dependencies.demo.language {
            return demoLanguage.locale
        }
        guard let language = AppLanguage(rawValue: languageOverride), language != .system else {
            return .current
        }
        return language.locale
    }
}
