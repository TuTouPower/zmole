import XCTest
@testable import Zmole

@MainActor
final class NavigationTests: XCTestCase {
    func testSidebarExposesTenDestinationsAcrossTwoSections() {
        XCTAssertEqual(
            AppDestination.allCases.map(\.rawValue),
            [
                "overview", "clean", "uninstall", "disk", "optimize",
                "status", "purge", "installers", "history", "settings"
            ]
        )

        let workspace = AppNavigationSection.workspace.destinations
        let system = AppNavigationSection.system.destinations
        XCTAssertEqual(
            workspace,
            [.overview, .clean, .uninstall, .disk, .optimize, .status, .purge, .installers]
        )
        XCTAssertEqual(system, [.history, .settings])
        XCTAssertEqual(workspace.count + system.count, AppDestination.allCases.count)
    }

    func testNavigationStartsOnOverviewAndSelectsDestinations() {
        let navigation = NavigationModel()
        XCTAssertEqual(navigation.destination, .overview)

        navigation.select(.disk)
        XCTAssertEqual(navigation.destination, .disk)
    }

    func testSettingsCommandSelectsSidebarSettingsPage() {
        // The SwiftUI `.appSettings` command group wiring itself is only
        // exercisable in a running window; its action is `navigation.select(.settings)`,
        // which is what this asserts. The end-to-end menu behaviour is covered by
        // the demo/manual pass.
        let navigation = NavigationModel()
        navigation.select(.disk)
        navigation.select(.settings)
        XCTAssertEqual(navigation.destination, .settings)
    }

    func testCommandPaletteOnlyContainsNavigationRows() {
        let items = CommandPaletteItem.all
        // Every palette row must map onto exactly one sidebar destination.
        // CommandPaletteItem carries nothing but a destination, so a future
        // execution action would have to be a destination and fail this
        // equality against the navigation-only destination set.
        XCTAssertEqual(items.count, AppDestination.allCases.count)
        XCTAssertEqual(Set(items.map(\.destination)), Set(AppDestination.allCases))
        XCTAssertEqual(Set(items.map(\.id)), Set(AppDestination.allCases.map(\.rawValue)))
    }

    func testCommandPaletteFiltersByQueryAndPerformsNavigation() throws {
        let navigation = NavigationModel()
        navigation.presentCommandPalette()
        XCTAssertTrue(navigation.isCommandPalettePresented)

        navigation.commandQuery = "disk"
        let filtered = navigation.filteredPaletteItems.map(\.destination)
        XCTAssertTrue(filtered.contains(.disk))
        XCTAssertFalse(filtered.contains(.clean))

        navigation.commandQuery = "zzz-no-match"
        XCTAssertTrue(navigation.filteredPaletteItems.isEmpty)

        navigation.commandQuery = ""
        let item = try XCTUnwrap(navigation.filteredPaletteItems.first { $0.destination == .history })
        navigation.perform(item)
        XCTAssertEqual(navigation.destination, .history)
        XCTAssertFalse(navigation.isCommandPalettePresented)
    }

    func testWindowMinimumSizeMeetsBaseline() {
        XCTAssertEqual(WindowMetrics.defaultWidth, 1200)
        XCTAssertEqual(WindowMetrics.defaultHeight, 780)
        XCTAssertGreaterThanOrEqual(WindowMetrics.minWidth, 1100)
        XCTAssertGreaterThanOrEqual(WindowMetrics.minHeight, 700)
    }

    // The former testShellKeepsSystemTitleBarWithoutCustomTrafficLights
    // asserted the constant ShellChrome.drawsCustomTrafficLights, which was
    // removed: the shell keeps the system title bar structurally (no custom
    // chrome exists in the view tree), so a constant asserting its own value
    // could not catch a real regression.

    func testSidebarDestinationsHaveThreeLocalizedLabels() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        for destination in AppDestination.allCases {
            for key in [destination.titleKeyString, destination.subtitleKeyString] {
                let entry = try XCTUnwrap(strings[key] as? [String: Any], "missing \(key)")
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
                for locale in ["en", "zh-Hans", "zh-Hant"] {
                    let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
                    let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                    let value = try XCTUnwrap(unit["value"] as? String)
                    XCTAssertFalse(value.isEmpty, "empty \(key) for \(locale)")
                }
            }
        }
    }

    func testCommandPaletteFiltersAcrossAllSupportedLanguages() {
        let navigation = NavigationModel()
        // displayNames resolves per-language labels from the string catalog.
        // If the catalog is unavailable in the test host it falls back to the
        // resource key, which still exercises the multi-locale resolution path.
        let names = navigation.displayNames(for: .clean)
        XCTAssertFalse(names.isEmpty)
        XCTAssertTrue(names.contains("清理"))
        navigation.commandQuery = "清理"
        XCTAssertTrue(navigation.filteredPaletteItems.contains { $0.destination == .clean })
    }

    func testSidebarProductNameIsZmoleNotMole() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["app.name"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
            let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
            XCTAssertEqual(unit["value"] as? String, "zmole")
        }
    }
}
