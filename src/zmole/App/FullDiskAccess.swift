import AppKit
import Combine
import Foundation

/// Full Disk Access detection and guidance.
///
/// Opening the system TCC database requires the same privilege as reading
/// protected folders, but unlike touching Desktop/Documents/Downloads it does
/// not raise a consent dialog. Nothing is read from the database.
enum FullDiskAccess {
    private static let probeURL = URL(
        fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"
    )

    static var isGranted: Bool {
        guard let handle = try? FileHandle(forReadingFrom: probeURL) else {
            return false
        }
        try? handle.close()
        return true
    }

    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// Shared, refreshable snapshot of the Full Disk Access grant. The app refreshes
/// it when it becomes active; views react to the published value.
@MainActor
final class FullDiskAccessMonitor: ObservableObject {
    @Published private(set) var isGranted: Bool

    private let probe: () -> Bool

    init(probe: @escaping () -> Bool = { FullDiskAccess.isGranted }) {
        self.probe = probe
        isGranted = probe()
    }

    func refresh() {
        let granted = probe()
        if granted != isGranted {
            isGranted = granted
        }
    }
}
