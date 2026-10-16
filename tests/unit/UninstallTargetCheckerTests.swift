import XCTest
@testable import Zmole

final class UninstallTargetCheckerTests: XCTestCase {
    func testStillMatchesRequiresThePathAndTheListedBundleIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-target-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Foo.app")
        try writeBundle(at: appURL, bundleID: "com.example.foo")

        let checker = LiveUninstallTargetChecker()
        let listed = UninstallApp(
            name: "Foo",
            bundleID: "com.example.foo",
            uninstallName: "Foo",
            path: appURL.path
        )
        let matches = await checker.stillMatches(listed)
        XCTAssertTrue(matches, "an unchanged bundle identity still matches")

        let differentIdentity = UninstallApp(
            name: "Foo",
            bundleID: "com.example.other",
            uninstallName: "Foo",
            path: appURL.path
        )
        let identityChanged = await checker.stillMatches(differentIdentity)
        XCTAssertFalse(identityChanged, "a changed bundle id must not match")

        let missing = UninstallApp(
            name: "Gone",
            bundleID: "com.example.foo",
            uninstallName: "Gone",
            path: root.appendingPathComponent("Gone.app").path
        )
        let missingMatch = await checker.stillMatches(missing)
        XCTAssertFalse(missingMatch, "a missing path must not match")

        let unknownIdentity = UninstallApp(
            name: "Foo",
            bundleID: "",
            uninstallName: "Foo",
            path: appURL.path
        )
        let unknownMatch = await checker.stillMatches(unknownIdentity)
        XCTAssertTrue(unknownMatch, "without a listed bundle id only the path is checked")
    }

    private func writeBundle(at url: URL, bundleID: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": "Foo"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
