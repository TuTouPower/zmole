import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceOverride = AppAppearance.system.rawValue
    private let demoLanguage: AppLanguage?
    private let whitelistViewModel: WhitelistViewModel?
    private let optimizeWhitelistViewModel: WhitelistViewModel?
    private let purgePathsViewModel: PurgePathsViewModel?
    @ObservedObject private var loginItemViewModel: LoginItemViewModel
    @State private var showingPurgePathsEditor = false

    init(
        demoLanguage: AppLanguage? = nil,
        whitelistViewModel: WhitelistViewModel? = nil,
        optimizeWhitelistViewModel: WhitelistViewModel? = nil,
        purgePathsViewModel: PurgePathsViewModel? = nil,
        loginItemViewModel: LoginItemViewModel? = nil
    ) {
        self.demoLanguage = demoLanguage
        self.whitelistViewModel = whitelistViewModel
        self.optimizeWhitelistViewModel = optimizeWhitelistViewModel
        self.purgePathsViewModel = purgePathsViewModel
        _loginItemViewModel = ObservedObject(wrappedValue: loginItemViewModel ?? LoginItemViewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MolePageHead(
                eyebrow: "settings.eyebrow",
                title: "settings.title",
                subtitle: "settings.subtitle"
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 10)
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            Section("settings.language.title") {
                Picker("settings.language.label", selection: selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.labelKey).tag(language.rawValue)
                    }
                }
                .id(demoLanguage?.rawValue ?? "stored-language")
                Text("settings.language.immediate").font(.caption).foregroundStyle(.secondary)
            }

            Section("settings.appearance.title") {
                Picker("settings.appearance.label", selection: $appearanceOverride) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.labelKey).tag(appearance.rawValue)
                    }
                }
            }

            Section("settings.system.title") {
                Toggle("settings.login_item", isOn: loginItemBinding)
                if let reason = loginItemViewModel.failureReason {
                    Text(verbatim: reason).font(.caption).foregroundStyle(.red)
                }
                Text("settings.login_item.note").font(.caption).foregroundStyle(.secondary)
            }

            Section("settings.developer.title") {
                if let purgePathsViewModel {
                    Button("settings.purge_paths.open") { showingPurgePathsEditor = true }
                }
                if let optimizeWhitelistViewModel {
                    NavigationLink("settings.optimize_whitelist.open") {
                        WhitelistView(viewModel: optimizeWhitelistViewModel)
                    }
                }
            }

            Section("settings.advanced.title") {
                if let whitelistViewModel {
                    NavigationLink("settings.whitelist.open") {
                        WhitelistView(viewModel: whitelistViewModel)
                    }
                }
                HStack {
                    Text("settings.cli.title")
                    Spacer()
                    Text(verbatim: cliVersionText).font(.system(size: 12, design: .monospaced))
                    Text("settings.cli.connected").font(.caption).foregroundStyle(.green)
                }
                if let path = BundledMoleInfo.executableURL()?.path {
                    Text(verbatim: path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("settings.cli.note").font(.caption).foregroundStyle(.secondary)
            }

            Section("settings.about.title") {
                NavigationLink("settings.about.open") { AboutView() }
            }

            Section("settings.permissions.title") {
                PermissionGuidanceView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("sidebar.settings")
        .task {
            if whitelistViewModel?.document == nil { whitelistViewModel?.load() }
            if optimizeWhitelistViewModel?.document == nil { optimizeWhitelistViewModel?.load() }
        }
        .sheet(isPresented: $showingPurgePathsEditor) {
            if let purgePathsViewModel {
                PurgePathsEditorView(viewModel: purgePathsViewModel) { showingPurgePathsEditor = false }
            }
        }
    }

    private var selectedLanguage: Binding<String> {
        if let demoLanguage {
            return .constant(demoLanguage.rawValue)
        }
        return $languageOverride
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemViewModel.isEnabled },
            set: { loginItemViewModel.setEnabled($0) }
        )
    }

    private var cliVersionText: String {
        BundledMoleInfo.tag() ?? "—"
    }
}
