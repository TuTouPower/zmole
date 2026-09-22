import AppKit
import SwiftUI

enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case clean
    case software
    case optimize
    case analyze
    case status

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .clean: "mode.clean"
        case .software: "mode.software"
        case .optimize: "mode.optimize"
        case .analyze: "mode.analyze"
        case .status: "mode.status"
        }
    }

    var symbol: String {
        switch self {
        case .clean: "sparkles"
        case .software: "square.stack.3d.up"
        case .optimize: "wrench.and.screwdriver"
        case .analyze: "square.grid.2x2"
        case .status: "waveform.path.ecg"
        }
    }
}

enum SoftwareMode: String, CaseIterable, Identifiable {
    case uninstall
    case whitelist

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .uninstall: "software.uninstall"
        case .whitelist: "software.whitelist"
        }
    }
}

enum OptimizeMode: String, CaseIterable, Identifiable {
    case maintenance
    case purge

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .maintenance: "optimize.maintenance"
        case .purge: "optimize.purge"
        }
    }
}

enum StatusMode: String, CaseIterable, Identifiable {
    case live
    case history

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .live: "status.live"
        case .history: "status.history"
        }
    }
}

@MainActor
struct ContentView: View {
    @StateObject private var dependencies: AppDependencies
    @State private var mode: AppMode
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue

    init(dependencies: AppDependencies? = nil) {
        let dependencies = dependencies ?? AppDependencies()
        _dependencies = StateObject(wrappedValue: dependencies)
        _mode = State(initialValue: dependencies.demo.isEnabled ? dependencies.demo.page : .clean)
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            NavigationStack {
                destination(for: mode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(UtilityStyle.background)
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, resolvedLocale)
    }

    private var modeBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(UtilityStyle.accent)
                    .accessibilityHidden(true)
                Text("app.name")
                    .font(.system(size: 15, weight: .semibold))
            }
            Picker("app.mode", selection: $mode) {
                ForEach(AppMode.allCases) { item in
                    Label(item.titleKey, systemImage: item.symbol).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)
            .accessibilityLabel("app.mode")
            Spacer(minLength: 0)
            settingsButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(UtilityStyle.surface)
    }

    private var settingsButton: some View {
        Button {
            openSettingsWindow()
        } label: {
            Label("settings.open", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .help("settings.open")
    }

    private func openSettingsWindow() {
        // SettingsLink is macOS 14+. On macOS 13 SwiftUI installs the working
        // menu item, so invoke that item with its own target/action pair.
        for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            guard let index = menu.items.firstIndex(where: { item in
                let title = item.title
                return title.localizedCaseInsensitiveContains("settings")
                    || title.contains("设置")
                    || title.contains("設定")
            }) else { continue }
            menu.performActionForItem(at: index)
            return
        }
    }

    @ViewBuilder
    private func destination(for mode: AppMode) -> some View {
        switch mode {
        case .clean:
            CleanView(viewModel: dependencies.cleanViewModel)
        case .software:
            SoftwareFeatureView(
                uninstallViewModel: dependencies.uninstallViewModel,
                whitelistViewModel: dependencies.whitelistViewModel
            )
        case .optimize:
            OptimizeFeatureView(
                optimizeViewModel: dependencies.optimizeViewModel,
                purgeViewModel: dependencies.purgeViewModel
            )
        case .analyze:
            AnalyzeView(viewModel: dependencies.analyzeViewModel)
        case .status:
            StatusFeatureView(
                statusViewModel: dependencies.statusViewModel,
                historyViewModel: dependencies.historyViewModel
            )
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

@MainActor
private struct SoftwareFeatureView: View {
    @ObservedObject var uninstallViewModel: UninstallViewModel
    @ObservedObject var whitelistViewModel: WhitelistViewModel
    @State private var selection: SoftwareMode = .uninstall

    var body: some View {
        VStack(spacing: 0) {
            UtilityToolbar(title: "mode.software", subtitle: "software.subtitle") {
                Picker("software.mode", selection: $selection) {
                    ForEach(SoftwareMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            Group {
                switch selection {
                case .uninstall:
                    UninstallView(viewModel: uninstallViewModel)
                case .whitelist:
                    WhitelistView(viewModel: whitelistViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private struct OptimizeFeatureView: View {
    @ObservedObject var optimizeViewModel: OptimizeViewModel
    @ObservedObject var purgeViewModel: PurgeViewModel
    @State private var selection: OptimizeMode = .maintenance

    var body: some View {
        VStack(spacing: 0) {
            UtilityToolbar(title: "mode.optimize", subtitle: "optimize.subtitle") {
                Picker("optimize.mode", selection: $selection) {
                    ForEach(OptimizeMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
            }
            Group {
                switch selection {
                case .maintenance:
                    OptimizeView(viewModel: optimizeViewModel)
                case .purge:
                    PurgeView(viewModel: purgeViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private struct StatusFeatureView: View {
    @ObservedObject var statusViewModel: StatusViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @State private var selection: StatusMode = .live

    var body: some View {
        VStack(spacing: 0) {
            UtilityToolbar(title: "mode.status", subtitle: "status.subtitle") {
                Picker("status.mode", selection: $selection) {
                    ForEach(StatusMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            Group {
                switch selection {
                case .live:
                    StatusView(viewModel: statusViewModel)
                case .history:
                    HistoryView(viewModel: historyViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
