import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue
    private let demoLanguage: AppLanguage?
    private let whitelistViewModel: WhitelistViewModel?

    init(demoLanguage: AppLanguage? = nil, whitelistViewModel: WhitelistViewModel? = nil) {
        self.demoLanguage = demoLanguage
        self.whitelistViewModel = whitelistViewModel
    }

    var body: some View {
        Form {
            Section("settings.language.title") {
                Picker("settings.language.label", selection: selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.labelKey)
                            .tag(language.rawValue)
                    }
                }
                .id(demoLanguage?.rawValue ?? "stored-language")
                Text("settings.language.immediate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let whitelistViewModel {
                Section("settings.whitelist.title") {
                    NavigationLink("settings.whitelist.open") {
                        WhitelistView(viewModel: whitelistViewModel)
                    }
                }
            }

            Section("settings.about.title") {
                NavigationLink("settings.about.open") {
                    AboutView()
                }
            }

            Section("settings.permissions.title") {
                PermissionGuidanceView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("sidebar.settings")
    }

    private var selectedLanguage: Binding<String> {
        if let demoLanguage {
            return .constant(demoLanguage.rawValue)
        }
        return $languageOverride
    }
}
