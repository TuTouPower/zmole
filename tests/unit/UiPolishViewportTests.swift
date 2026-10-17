import XCTest
@testable import Zmole

final class UiPolishViewportTests: XCTestCase {
    func testSidebarBrandDropsTagline() throws {
        let source = try Self.source("App/SidebarView.swift")
        XCTAssertFalse(source.contains("app.tagline"), "Sidebar brand must not display app.tagline (AC-002)")
    }

    func testSidebarDropsCleanReclaimBadgeAndStatusDot() throws {
        let source = try Self.source("App/SidebarView.swift")
        XCTAssertFalse(source.contains("lastReclaimBytes"), "Sidebar must not display clean reclaim badge (AC-003)")
        XCTAssertFalse(source.contains("statusViewModel.isSampling"), "Sidebar must not display status sampling dot (AC-004)")
        XCTAssertFalse(source.contains("statusViewModel:"), "Sidebar must drop statusViewModel dependency (AC-004)")
        XCTAssertFalse(source.contains("cleanViewModel:"), "Sidebar must drop cleanViewModel dependency (AC-003)")
    }

    func testSidebarSuppressesSystemFocusRingAndStylesThemeFocus() throws {
        let source = try Self.source("App/SidebarView.swift")
        XCTAssertTrue(
            source.contains("withoutSystemFocusRing") || source.contains("focusEffectDisabled"),
            "Sidebar must suppress system blue focus ring (AC-001)"
        )
        XCTAssertTrue(
            source.contains("focusedDestination") || source.contains("@FocusState"),
            "Sidebar must track keyboard focus state for theme styling (AC-011)"
        )
        XCTAssertTrue(
            source.contains("MoleTheme.accent"),
            "Sidebar must style keyboard focus with theme accent (AC-011)"
        )
    }

    func testSettingsUsesMoleThemeBackground() throws {
        let source = try Self.source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(
            source.contains("MoleTheme.background"),
            "SettingsView must use MoleTheme.background (AC-009)"
        )
        XCTAssertTrue(
            source.contains("scrollContentBackground(.hidden)"),
            "SettingsView grouped Form must hide default scroll content background (AC-009)"
        )
    }

    func testInstallersListHasDedicatedScrollViewAndFixedFooter() throws {
        let source = try Self.source("Features/Installers/InstallersView.swift")
        // The outer content must not be wrapped in an unconstrained ScrollView that scrolls the footer off
        XCTAssertFalse(
            source.contains("private var content: some View {\n        ScrollView"),
            "Installers outer content must not be wrapped in an unconstrained ScrollView (AC-005)"
        )
        // Candidate list must have its own scrolling container
        XCTAssertTrue(
            source.contains("ScrollView"),
            "Installers candidates must scroll in a dedicated ScrollView (AC-005)"
        )
        // Action footer must remain outside the list scrollview
        XCTAssertTrue(
            source.contains("installers.remove"),
            "Installers remove action must remain present and accessible (AC-005)"
        )
    }

    func testOptimizePlanSeparatesScrollableContentFromFixedExecuteButton() throws {
        let source = try Self.source("Features/Optimize/OptimizeView.swift")
        XCTAssertFalse(
            source.contains("private var content: some View {\n        ScrollView"),
            "Optimize outer content must not be wrapped in an unconstrained ScrollView (AC-006)"
        )
        XCTAssertTrue(
            source.contains("optimize.execute"),
            "Optimize execute button must remain present (AC-006)"
        )
    }

    func testPurgeOutputSeparatesScrollableOutputFromFixedExecuteButton() throws {
        let source = try Self.source("Features/Purge/PurgeView.swift")
        XCTAssertFalse(
            source.contains("private var content: some View {\n        ScrollView"),
            "Purge outer content must not be wrapped in an unconstrained ScrollView (AC-007)"
        )
        XCTAssertTrue(
            source.contains("purge.execute"),
            "Purge execute button must remain present (AC-007)"
        )
    }

    func testHistoryTableSeparatesScrollableRowsFromFixedHeader() throws {
        let source = try Self.source("Features/History/HistoryView.swift")
        XCTAssertFalse(
            source.contains("var body: some View {\n        ScrollView"),
            "History body must not be wrapped in an outer ScrollView that scrolls head off (AC-008)"
        )
        XCTAssertTrue(
            source.contains("headerRow"),
            "History headerRow must stay defined and separated from scrolling rows (AC-008)"
        )
    }

    private static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/\(relative)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
