import XCTest
@testable import Zmole

final class ZmoleTests: XCTestCase {
    func testSidebarContainsTheFirstVersionNavigation() {
        XCTAssertEqual(
            SidebarItem.allCases.map(\.rawValue),
            [
                "status", "history", "analyze", "clean", "uninstall", "optimize",
                "purge", "whitelist", "settings"
            ]
        )
    }

    func testSidebarDoesNotExposeInstallerUpdateOrRemove() {
        let forbidden = ["installer", "update", "remove"]
        XCTAssertTrue(
            Set(SidebarItem.allCases.map(\.rawValue)).isDisjoint(with: forbidden)
        )
    }

    func testReleasesURLIsTheProjectReleasePage() {
        XCTAssertEqual(
            AppLinks.releasesURL.absoluteString,
            "https://github.com/TuTouPower/zmole/releases"
        )
    }

    func testCancellingDestructiveConfirmationDoesNotExecuteAction() {
        var executed = false
        let flow = DestructiveConfirmationFlow { executed = true }

        flow.cancel()

        XCTAssertFalse(executed)
        XCTAssertFalse(flow.isPending)
    }
}
