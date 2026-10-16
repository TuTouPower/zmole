import AppKit
import SwiftUI

/// Design tokens taken from `docs/design/mole_desktop_demo_cn_final.html`.
/// Values are adaptive so the same names resolve in light and dark appearance.
enum MoleTheme {
    static let background = adaptive(light: 0xF5F5F7, dark: 0x1C1C1E)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x2A2A2C)
    static let surface2 = adaptive(light: 0xF8F8FA, dark: 0x242426)
    static let surface3 = adaptive(light: 0xF1F1F4, dark: 0x333336)
    static let text = adaptive(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let muted = adaptive(light: 0x6E6E73, dark: 0xA1A1A6)
    static let subtle = adaptive(light: 0x8E8E93, dark: 0x85858B)
    static let line = adaptive(light: 0x1D1D1F, dark: 0xFFFFFF).opacity(0.10)
    static let accent = adaptive(light: 0x2F8F68, dark: 0x58B889)
    static let accentStrong = adaptive(light: 0x237554, dark: 0x73C69D)
    static let accentSoft = adaptive(light: 0xE8F4EE, dark: 0x23342C)
    static let sidebar = adaptive(light: 0xF5F5F7, dark: 0x1C1C1E).opacity(0.82)
    static let selection = adaptive(light: 0xE2E2E6, dark: 0x3A3A3E)

    static let radiusXL: CGFloat = 22
    static let radiusLG: CGFloat = 17
    static let radiusMD: CGFloat = 13
    static let radiusSM: CGFloat = 10

    static let sidebarWidth: CGFloat = 236
    static let titlebarHeight: CGFloat = 54

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
