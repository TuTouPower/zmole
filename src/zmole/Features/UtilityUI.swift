import AppKit
import SwiftUI

enum UtilityStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.33, green: 0.84, blue: 0.70, alpha: 1)
            : NSColor(srgbRed: 0.04, green: 0.50, blue: 0.41, alpha: 1)
    })
    static let surface = Color(nsColor: .textBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let secondarySurface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color.primary.opacity(0.09)
    static let selection = accent.opacity(0.10)

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

struct UtilityToolbar<Actions: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            actions()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .background(UtilityStyle.surface)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct UtilityPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UtilityStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(UtilityStyle.separator))
    }
}

struct UtilityEmptyState: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(UtilityStyle.accent)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UtilityNotice: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    var symbol = "info.circle"
    var isError = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(isError ? .red : UtilityStyle.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.medium)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background((isError ? Color.red : UtilityStyle.accent).opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct UtilityBadge: View {
    let title: LocalizedStringKey
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(UtilityStyle.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(UtilityStyle.selection, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct UtilityMetric: View {
    let title: LocalizedStringKey
    let value: String
    var detail: LocalizedStringKey = ""
    var fraction: Double? = nil
    var emphasized = false

    var body: some View {
        UtilityPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(emphasized ? UtilityStyle.accent : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let fraction {
                    GeometryReader { proxy in
                        Capsule().fill(UtilityStyle.selection)
                            .overlay(alignment: .leading) {
                                Capsule().fill(UtilityStyle.accent)
                                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
                            }
                    }
                    .frame(height: 5)
                    .accessibilityHidden(true)
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        }
    }
}
