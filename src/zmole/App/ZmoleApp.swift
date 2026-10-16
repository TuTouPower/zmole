import SwiftUI

@main
struct ZmoleApp: App {
    @StateObject private var dependencies: AppDependencies
    @StateObject private var navigation: NavigationModel

    init() {
        let dependencies = AppDependencies(configuration: DemoConfiguration())
        _dependencies = StateObject(wrappedValue: dependencies)
        _navigation = StateObject(
            wrappedValue: NavigationModel(
                initial: dependencies.demo.isEnabled ? dependencies.demo.page : .overview
            )
        )
    }

    var body: some Scene {
        WindowGroup("app.name") {
            AppShellView(dependencies: dependencies, navigation: navigation)
        }
        .defaultSize(width: WindowMetrics.defaultWidth, height: WindowMetrics.defaultHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("settings.open") {
                    navigation.select(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("palette.open") {
                    navigation.presentCommandPalette()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
