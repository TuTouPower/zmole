import SwiftUI

struct AboutView: View {
    @State private var moleVersion = "—"

    var body: some View {
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
            }
        }
        .formStyle(.grouped)
        .navigationTitle("about.title")
        .task {
            await loadMoleVersion()
        }
    }

    private func loadMoleVersion() async {
        guard let bridge = try? MoleBridge() else { return }
        moleVersion = (try? await bridge.version()) ?? "—"
    }
}
