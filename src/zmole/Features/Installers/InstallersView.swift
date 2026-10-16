import SwiftUI

/// Placeholder installer page introduced with the sidebar shell. The
/// non-interactive installer interface and preview flow land in a follow-up task.
@MainActor
struct InstallersView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(MoleTheme.accent)
                .accessibilityHidden(true)
            Text("installers.title")
                .font(.system(size: 22, weight: .semibold))
            Text("installers.placeholder")
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("installers.title")
    }
}
