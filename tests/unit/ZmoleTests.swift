import XCTest
@testable import Zmole

final class ZmoleTests: XCTestCase {
    func testSidebarProvidesInitialPlaceholders() {
        XCTAssertEqual(
            SidebarItem.allCases.map(\.rawValue),
            ["status", "history", "analyze"]
        )
    }
}
