import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageOverride = AppLanguage.system.rawValue

    var body: some View {
        Form {
            Section("settings.language.title") {
                Picker("settings.language.label", selection: $languageOverride) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.labelKey)
                            .tag(language.rawValue)
                    }
                }
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
}
