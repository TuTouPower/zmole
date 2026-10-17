import AppKit
import SwiftUI

enum UtilityStyle {
    /// Accent family is the shared theme accent (app icon blue gradients).
    static let accent = MoleTheme.accent
    static let surface = Color(nsColor: .textBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let separator = Color.primary.opacity(0.09)
    static let selection = accent.opacity(0.10)

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// Shared page head from the visual demo: eyebrow + title + subtitle on the
/// left, page actions on the right. Pages put their primary actions here;
/// in-progress cancel buttons may stay next to the content they cancel.
struct MolePageHead<Actions: View>: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder let actions: () -> Actions

    init(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(MoleTheme.accentStrong)
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.muted)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                actions()
            }
        }
    }
}

extension MolePageHead where Actions == EmptyView {
    init(eyebrow: LocalizedStringKey, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Demo stat-strip tile: bold value on top, muted label below.
struct MoleStatTile: View {
    let value: String
    let label: LocalizedStringKey
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(emphasized ? MoleTheme.accentStrong : Color.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.muted)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoleTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: MoleTheme.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: MoleTheme.radiusMD)
                .strokeBorder(MoleTheme.line)
        )
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

/// Shared busy placeholder with a fixed height so plan/output panels do not
/// jump while a preview or execution is running.
struct UtilityBusyState: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// Semantic tone of a notice. Info is the demo `.info-banner` style; error and
/// the default accent style keep their existing appearance.
enum NoticeTone: Equatable {
    case accent
    case info
    case error
}

struct UtilityNotice: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    var symbol = "info.circle"
    var isError = false
    var isInfo = false

    static func tone(isInfo: Bool, isError: Bool) -> NoticeTone {
        if isError { return .error }
        return isInfo ? .info : .accent
    }

    private var tone: NoticeTone {
        Self.tone(isInfo: isInfo, isError: isError)
    }

    private var tint: Color {
        switch tone {
        case .accent: return UtilityStyle.accent
        case .info: return MoleTheme.blue
        case .error: return .red
        }
    }

    private var background: Color {
        switch tone {
        case .accent: return UtilityStyle.accent.opacity(0.07)
        case .info: return MoleTheme.blueSoft
        case .error: return Color.red.opacity(0.07)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.medium).foregroundStyle(tone == .info ? tint : Color.primary)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.system(size: 12))
                        .foregroundStyle(tone == .info ? tint : Color.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Neutral, recoverable notice for transient command contention. Never rendered
/// as a failure.
struct RecoverableBusyNotice: View {
    var body: some View {
        UtilityNotice(title: "command.busy", symbol: "hourglass")
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
