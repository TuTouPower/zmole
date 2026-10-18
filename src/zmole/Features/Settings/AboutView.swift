import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var isSheet: Bool = false
    @State private var moleVersion = "—"

    var body: some View {
        VStack(spacing: 0) {
            if isSheet {
                sheetHeader
            }
            formContent
            if isSheet {
                sheetFooter
            }
        }
        .frame(width: isSheet ? 440 : nil, height: isSheet ? 420 : nil)
        .navigationTitle("about.title")
        .withoutFocusRing()
        .task {
            await loadMoleVersion()
        }
    }

    private var sheetHeader: some View {
        HStack {
            Text("about.title")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(MoleTheme.subtle)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.cancelAction)
            .help("about.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var formContent: some View {
        Form {
            Section("about.title") {
                Text("about.name")
                    .font(.title2)
                Text("about.source")
                Text("about.not_commercial")
                Text("about.license")
            }

            Section("about.bundled_version") {
                Text(moleVersion)
                    .font(.body.monospaced())
            }

            Section {
                Link("about.releases", destination: AppLinks.releasesURL)
                    .focusable(false)
            }
        }
        .formStyle(.grouped)
    }

    private var sheetFooter: some View {
        HStack {
            Spacer()
            Button("about.close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(MoleTheme.accent)
            .keyboardShortcut(.defaultAction)
            .focusable(false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func loadMoleVersion() async {
        guard BundledMoleInfo.executableURL() != nil, let tag = BundledMoleInfo.tag() else {
            moleVersion = String(localized: "about.version_unavailable")
            return
        }
        moleVersion = tag
    }
}

private extension View {
    @ViewBuilder
    func withoutFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}
