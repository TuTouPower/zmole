import XCTest
@testable import Zmole

final class BatchUninstallTests: XCTestCase {
    func testDecoderKeepsSourceAndParsesHumanSize() throws {
        let apps = try UninstallListDecoder.decode("""
        [{"name":"Foo","bundle_id":"com.example.foo","uninstall_name":"Foo","path":"/Applications/Foo.app","source":"Homebrew","size":"1.5 GB"}]
        """)

        XCTAssertEqual(apps[0].source, "Homebrew")
        XCTAssertEqual(apps[0].sizeBytes, 1_500_000_000)
    }

    func testSizeParserSeparatesDecimalAndIECUnitsAndUnknown() {
        XCTAssertEqual(UninstallSizeParser.bytes(from: "1 KB"), 1_000)
        XCTAssertEqual(UninstallSizeParser.bytes(from: "1 KiB"), 1_024)
        XCTAssertEqual(UninstallSizeParser.bytes(from: "2.5 MiB"), 2_621_440)
        XCTAssertNil(UninstallSizeParser.bytes(from: "Unknown"))
        XCTAssertNil(UninstallSizeParser.bytes(from: "0"))
        XCTAssertNil(UninstallSizeParser.bytes(from: "1.2.3 GB"))
    }

    func testSelectionValidatorRejectsDuplicateNamesAndChangedIdentity() throws {
        let first = UninstallApp(
            name: "Foo", bundleID: "com.example.foo", uninstallName: "Foo",
            path: "/Applications/Foo.app", source: "App", size: "1 MB"
        )
        let duplicate = UninstallApp(
            name: "Foo", bundleID: "com.example.other", uninstallName: "Foo",
            path: "/Applications/Other.app", source: "App", size: "2 MB"
        )
        XCTAssertThrowsError(try UninstallSelectionValidator.batch(
            selectedIDs: [first.id, duplicate.id], apps: [first, duplicate]
        )) { error in
            XCTAssertEqual(error as? UninstallViewModelError, .ambiguousName)
        }

        XCTAssertThrowsError(try UninstallSelectionValidator.batch(
            selectedIDs: [first.id], apps: [duplicate]
        )) { error in
            XCTAssertEqual(error as? UninstallViewModelError, .changedTarget)
        }

        let optionLike = UninstallApp(
            name: "Option", bundleID: "com.example.option", uninstallName: "--dry-run",
            path: "/Applications/Option.app"
        )
        XCTAssertThrowsError(try UninstallSelectionValidator.batch(
            selectedIDs: [optionLike.id], apps: [optionLike]
        )) { error in
            XCTAssertEqual(error as? UninstallViewModelError, .invalidName)
        }
    }

    func testBatchResultDoesNotTreatUninformativeZeroExitAsSuccess() {
        let result = UninstallBatchResultParser.result(
            MoleCommandResult(stdout: "done", stderr: "", exitCode: 0),
            expectedCount: 2
        )
        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.errorKey, "uninstall.error.unknown_result")
    }

    func testBatchResultRecognizesLockedSummaryCounts() {
        let result = UninstallBatchResultParser.result(
            MoleCommandResult(stdout: "Uninstall complete\nRemoved 2 apps", stderr: "", exitCode: 0),
            expectedCount: 2
        )
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertNil(result.errorKey)
    }
}
