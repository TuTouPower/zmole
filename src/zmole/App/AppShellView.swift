import AppKit
import SwiftUI

@MainActor
struct AppShellView: View {
    @ObservedObject var dependencies: AppDependencies
    @ObservedObject var navigation: NavigationModel
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceOverride = AppAppearance.system.rawValue

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
        .onAppear { updateStatusWatch() }
        .onChange(of: navigation.destination) { _ in updateStatusWatch() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            dependencies.fullDiskAccessMonitor.refresh()
        }
        .onReceive(dependencies.statusPolicy.$isEnabled) { _ in
            Task { @MainActor in
                let enabled = dependencies.statusPolicy.isEnabled
                await dependencies.statusViewModel.applyPolicyChange(enabled: enabled)
                updateStatusWatch()
            }
        }
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
            OverviewView(
                statusViewModel: dependencies.statusViewModel,
                viewModel: dependencies.overviewViewModel,
                cleanViewModel: dependencies.cleanViewModel,
                navigation: navigation,
                accessMonitor: dependencies.fullDiskAccessMonitor
            )
        case .clean:
            CleanView(
                viewModel: dependencies.cleanViewModel,
                whitelistViewModel: dependencies.whitelistViewModel,
                onOpenWhitelist: { navigation.select(.settings) }
            )
        case .uninstall:
            UninstallView(viewModel: dependencies.uninstallViewModel)
        case .disk:
            AnalyzeView(viewModel: dependencies.analyzeViewModel)
        case .optimize:
            OptimizeView(
                viewModel: dependencies.optimizeViewModel,
                onOpenSettings: { navigation.select(.settings) }
            )
        case .status:
            StatusView(viewModel: dependencies.statusViewModel)
        case .purge:
            PurgeView(
                viewModel: dependencies.purgeViewModel,
                pathsViewModel: dependencies.purgePathsViewModel,
                onOpenSettings: { navigation.select(.settings) }
            )
        case .installers:
            InstallersView(
                viewModel: dependencies.installersViewModel,
                accessMonitor: dependencies.fullDiskAccessMonitor
            )
        case .history:
            HistoryView(viewModel: dependencies.historyViewModel)
        case .settings:
            SettingsView(
                demoLanguage: dependencies.demo.language,
                whitelistViewModel: dependencies.whitelistViewModel,
                optimizeWhitelistViewModel: dependencies.optimizeWhitelistViewModel,
                purgePathsViewModel: dependencies.purgePathsViewModel,
                loginItemViewModel: dependencies.loginItemViewModel,
                accessMonitor: dependencies.fullDiskAccessMonitor,
                statusPolicy: dependencies.statusPolicy
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
        case nil:
            return AppAppearance(rawValue: appearanceOverride)?.colorScheme
        }
    }

    /// The status watch runs only while the overview or status page is visible.
    /// Navigating away stops the shared process, satisfying the leave-page rule.
    private func updateStatusWatch() {
        let selectedItem: BackgroundScanItem?
        switch navigation.destination {
        case .uninstall: selectedItem = .uninstallList
        case .installers: selectedItem = .installerList
        case .clean: selectedItem = .clean
        case .optimize: selectedItem = .optimize
        case .purge: selectedItem = .purge
        default: selectedItem = nil
        }
        for item in BackgroundScanItem.allCases {
            dependencies.scanService?.setPriority(item, item == selectedItem ? .userVisible : .background)
        }
        dependencies.analyzeViewModel.session.setUserVisible(navigation.destination == .disk || navigation.destination == .overview)

        guard dependencies.statusPolicy.isEnabled else {
            Task { await dependencies.statusViewModel.stop() }
            return
        }
        switch navigation.destination {
        case .overview, .status:
            dependencies.statusViewModel.start()
        default:
            Task { await dependencies.statusViewModel.stop() }
        }
    }
}
