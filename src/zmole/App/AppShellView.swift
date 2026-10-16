import SwiftUI

@MainActor
struct AppShellView: View {
    @ObservedObject var dependencies: AppDependencies
    @ObservedObject var navigation: NavigationModel
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(navigation: navigation)
            NavigationStack {
                destinationView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: WindowMetrics.minWidth, minHeight: WindowMetrics.minHeight)
        .background(MoleTheme.background)
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, resolvedLocale)
        .animation(.easeInOut(duration: 0.18), value: navigation.destination)
        .overlay {
            if navigation.isCommandPalettePresented {
                CommandPaletteView(navigation: navigation)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.presentCommandPalette()
                } label: {
                    Label("palette.open", systemImage: "magnifyingglass")
                }
                .help("palette.open")
            }
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch navigation.destination {
        case .overview:
            OverviewView()
        case .clean:
            CleanView(viewModel: dependencies.cleanViewModel)
        case .uninstall:
            UninstallView(viewModel: dependencies.uninstallViewModel)
        case .disk:
            AnalyzeView(viewModel: dependencies.analyzeViewModel)
        case .optimize:
            OptimizeView(viewModel: dependencies.optimizeViewModel)
        case .status:
            StatusView(viewModel: dependencies.statusViewModel)
        case .purge:
            PurgeView(viewModel: dependencies.purgeViewModel)
        case .installers:
            InstallersView()
        case .history:
            HistoryView(viewModel: dependencies.historyViewModel)
        case .settings:
            SettingsView(
                demoLanguage: dependencies.demo.language,
                whitelistViewModel: dependencies.whitelistViewModel
            )
        }
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

    private var preferredColorScheme: ColorScheme? {
        switch dependencies.demo.appearance {
        case .light: return .light
        case .dark: return .dark
        case nil: return nil
        }
    }
}
