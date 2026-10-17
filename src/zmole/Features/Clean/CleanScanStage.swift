import Foundation

/// A clean dry-run scan stage as printed by `start_section` ("➤ Browsers").
/// Known stages carry a localization key; unknown stages are shown verbatim.
struct CleanScanStage: Equatable, Sendable {
    let raw: String

    var localizedKey: String? { CleanStageCatalog.key(for: raw) }
}

enum CleanStageCatalog {
    private static let keys: [String: String] = [
        "App caches": "clean.stage.app_caches",
        "App leftovers": "clean.stage.app_leftovers",
        "Application Support": "clean.stage.application_support",
        "Apps & utilities": "clean.stage.apps_utilities",
        "Browsers": "clean.stage.browsers",
        "Cloud & Office": "clean.stage.cloud_office",
        "Developer tools": "clean.stage.developer_tools",
        "Device backups & firmware": "clean.stage.device_backups",
        "External volume": "clean.stage.external_volume",
        "Large files": "clean.stage.large_files",
        "Project artifacts": "clean.stage.project_artifacts",
        "System": "clean.stage.system",
        "Time Machine": "clean.stage.time_machine",
        "User essentials": "clean.stage.user_essentials",
        "Virtualization": "clean.stage.virtualization"
    ]

    static let sections: [String] = keys.keys.sorted()

    static func key(for raw: String) -> String? {
        keys[raw]
    }

    /// Extracts a stage name from one scan output line, or nil when the line is
    /// not a section header.
    static func stage(fromLine line: String) -> CleanScanStage? {
        let stripped = MaintenanceOutput.stripANSI(line).trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return nil }

        guard let arrow = stripped.range(of: "➤") else {
            let match = sections.first { $0.caseInsensitiveCompare(stripped) == .orderedSame }
            return match.map(CleanScanStage.init(raw:))
        }
        let name = stripped[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : CleanScanStage(raw: name)
    }

    /// Last stage found in a captured stdout blob (used when the preview runs
    /// without a live stream).
    static func lastStage(in output: String) -> CleanScanStage? {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { stage(fromLine: String($0)) }
            .last
    }
}
