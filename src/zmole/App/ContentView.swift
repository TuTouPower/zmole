import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case status
    case history
    case analyze

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .status

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Text(item.title)
                    .tag(item)
            }
            .navigationTitle("zmole")
        } detail: {
            VStack(spacing: 8) {
                Text(selection?.title ?? "zmole")
                    .font(.title)
                Text("Placeholder")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
