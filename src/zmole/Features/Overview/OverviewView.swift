import SwiftUI

/// Placeholder overview page introduced with the sidebar shell. The live
/// system sampling, disk estimate and recent activity land in a follow-up task.
@MainActor
struct OverviewView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(MoleTheme.accent)
                .accessibilityHidden(true)
            Text("overview.title")
                .font(.system(size: 22, weight: .semibold))
            Text("overview.placeholder")
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("overview.title")
    }
}
