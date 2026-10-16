import AppKit
import SwiftUI

@MainActor
struct SidebarView: View {
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var statusViewModel: StatusViewModel
    @ObservedObject var cleanViewModel: CleanViewModel
    @State private var showingAbout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            ForEach(AppNavigationSection.allCases) { section in
                Text(section.titleKey)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(MoleTheme.subtle)
                    .padding(.horizontal, 10)
                    .padding(.top, section == .workspace ? 0 : 14)
                    .padding(.bottom, 7)
                VStack(spacing: 2) {
                    ForEach(section.destinations) { destination in
                        navItem(destination)
                    }
                }
            }
            Spacer(minLength: 14)
            footer
        }
        .padding(.top, 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: MoleTheme.sidebarWidth)
        .background(MoleTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(MoleTheme.line).frame(width: 1)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
                .frame(width: 420, height: 420)
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            Image(nsImage: brandIcon)
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("app.name")
                    .font(.system(size: 16, weight: .bold))
                Text("app.tagline")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.subtle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 22)
    }

    /// The brand mark loads the bundled icns directly so the transparent
    /// vector rendering is shown as authored. `NSApp.applicationIconImage`
    /// goes through the system icon cache/decoration and can serve a stale or
    /// plated image for the same bundle identifier.
    private var brandIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    private func navItem(_ destination: AppDestination) -> some View {
        let isSelected = navigation.destination == destination
        return Button {
            navigation.select(destination)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 17)
                Text(destination.titleKey)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                if destination == .clean, let bytes = cleanViewModel.lastReclaimBytes {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MoleTheme.accentStrong)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(MoleTheme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                }
                if destination == .status, statusViewModel.isSampling {
                    Circle()
                        .fill(MoleTheme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(MoleTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? MoleTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: MoleTheme.radiusSM))
            .contentShape(RoundedRectangle(cornerRadius: MoleTheme.radiusSM))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(MoleTheme.line).frame(height: 1)
            HStack(spacing: 9) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: Self.machineName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(verbatim: Self.osVersion)
                        .font(.system(size: 10))
                        .foregroundStyle(MoleTheme.subtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)

            Button {
                showingAbout = true
            } label: {
                HStack {
                    Text("about.title")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.subtle)
                .padding(7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }

    private static var machineName: String {
        Host.current().localizedName ?? "Mac"
    }

    private static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
