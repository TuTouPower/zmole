import SwiftUI

/// Sidebar grouping. The demo groups the ten destinations into a workspace
/// group and a system group.
enum AppNavigationSection: String, CaseIterable, Identifiable, Sendable {
    case workspace
    case system

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .workspace: "sidebar.section.workspace"
        case .system: "sidebar.section.system"
        }
    }

    var destinations: [AppDestination] {
        AppDestination.allCases.filter { $0.section == self }
    }
}

/// The ten sidebar destinations that replaced the top five-mode navigation.
enum AppDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case clean
    case uninstall
    case disk
    case optimize
    case status
    case purge
    case installers
    case history
    case settings

    var id: Self { self }

    /// Stable localization key. Kept as a plain string so tests can parse the
    /// string catalog directly, matching the existing localization tests.
    var titleKeyString: String { "sidebar.\(rawValue)" }

    var subtitleKeyString: String { "sidebar.\(rawValue).subtitle" }

    var titleKey: LocalizedStringKey { LocalizedStringKey(titleKeyString) }

    var subtitleKey: LocalizedStringKey { LocalizedStringKey(subtitleKeyString) }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .clean: "sparkles"
        case .uninstall: "square.stack.3d.up"
        case .disk: "internaldrive"
        case .optimize: "wrench.and.screwdriver"
        case .status: "waveform.path.ecg"
        case .purge: "hammer"
        case .installers: "shippingbox"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }

    var section: AppNavigationSection {
        switch self {
        case .history, .settings: .system
        default: .workspace
        }
    }

    /// Accepts the historical demo page names used by the smoke harness in
    /// addition to the current destination raw values.
    init?(demoValue: String) {
        switch demoValue {
        case "analyze": self = .disk
        case "software": self = .uninstall
        default: self.init(rawValue: demoValue)
        }
    }
}

/// Window sizing contract from the approved visual baseline.
enum WindowMetrics {
    static let defaultWidth: CGFloat = 1200
    static let defaultHeight: CGFloat = 780
    static let minWidth: CGFloat = 1100
    static let minHeight: CGFloat = 700
}

/// Chrome contract. The shell keeps the system title bar and never draws
/// red/yellow/green traffic lights inside the content area.
enum ShellChrome {
    static let drawsCustomTrafficLights = false
}
