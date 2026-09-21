import AppKit
import SwiftUI

struct PermissionGuidanceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.permissions.description")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("settings.permissions.open") {
                openAccessibilitySettings()
            }
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
