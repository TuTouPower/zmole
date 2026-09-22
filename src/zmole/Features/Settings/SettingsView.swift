import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue
    private let demoLanguage: AppLanguage?

    init(demoLanguage: AppLanguage? = nil) {
        self.demoLanguage = demoLanguage
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
