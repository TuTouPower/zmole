import SwiftUI

/// Inline guidance shown on pages whose scans need protected user folders.
struct FullDiskAccessNotice: View {
    @ObservedObject var monitor: FullDiskAccessMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(MoleTheme.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("permissions.full_disk_access.title")
                    .fontWeight(.medium)
                Text("permissions.full_disk_access.detail")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("permissions.full_disk_access.open") {
                        FullDiskAccess.openSettings()
                    }
                    Button("permissions.full_disk_access.recheck") {
                        monitor.refresh()
                    }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(MoleTheme.blueSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Settings row with the current grant state.
struct FullDiskAccessSettingsRow: View {
    @ObservedObject var monitor: FullDiskAccessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("permissions.full_disk_access.title")
                Spacer()
                Text(
                    LocalizedStringKey(
                        monitor.isGranted
                            ? "permissions.status.granted"
                            : "permissions.status.required"
                    )
                )
                .font(.caption)
                .foregroundStyle(monitor.isGranted ? Color.green : Color.secondary)
            }
            Text("permissions.full_disk_access.detail")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("permissions.full_disk_access.open") {
                    FullDiskAccess.openSettings()
                }
                Button("permissions.full_disk_access.recheck") {
                    monitor.refresh()
                }
            }
            .controlSize(.small)
        }
        .onAppear { monitor.refresh() }
    }
}
