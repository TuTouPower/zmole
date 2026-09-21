import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case status
    case history
    case analyze
    case clean
    case uninstall
    case optimize
    case purge
    case whitelist
    case settings

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .status: "sidebar.status"
        case .history: "sidebar.history"
        case .analyze: "sidebar.analyze"
        case .clean: "sidebar.clean"
        case .uninstall: "sidebar.uninstall"
        case .optimize: "sidebar.optimize"
        case .purge: "sidebar.purge"
        case .whitelist: "sidebar.whitelist"
        case .settings: "sidebar.settings"
        }
    }

}

struct ContentView: View {
    @State private var selection: SidebarItem? = .status
    @StateObject private var cleanViewModel: CleanViewModel

    init(cleanViewModel: CleanViewModel? = nil) {
        _cleanViewModel = StateObject(wrappedValue: cleanViewModel ?? CleanViewModel())
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Text(item.titleKey)
                    .tag(item)
            }
            .navigationTitle("app.name")
        } detail: {
            NavigationStack {
                destination(for: selection ?? .status)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: SidebarItem) -> some View {
        switch item {
        case .status:
            StatusView()
        case .history:
            HistoryView()
        case .analyze:
            AnalyzeView()
        case .whitelist:
            WhitelistView()
        case .clean:
            CleanView(viewModel: cleanViewModel)
        case .settings:
            SettingsView()
        case .uninstall, .optimize, .purge:
            DestructiveConfirmationView(
                title: item.titleKey,
                summary: "destructive.summary",
                onConfirm: {},
                onCancel: {}
            )
        }
    }
}

struct PlaceholderFeatureView: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title)
            Text("placeholder.summary")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}
