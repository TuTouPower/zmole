import XCTest
@testable import Zmole

final class AppAssemblyTests: XCTestCase {
    func testAppDependenciesFileOnlyContainsAssembly() throws {
        let source = try Self.source("App/AppDependencies.swift")
        XCTAssertFalse(
            source.contains("final class DemoMoleProcess"),
            "demo fakes must live in DemoSupport.swift"
        )
        XCTAssertNil(
            source.range(of: "\\b(class|struct|enum) Demo[A-Z]", options: .regularExpression),
            "no demo type declaration may live in DemoSupport.swift's consumer file"
        )
        XCTAssertFalse(
            source.contains("enum DemoFixtures"),
            "demo fixtures must live in DemoSupport.swift"
        )
        XCTAssertFalse(
            source.contains("\"entries\":["),
            "demo fixture literals must live in DemoSupport.swift"
        )
    }

    func testDemoSupportFileCarriesTheDemoTypes() throws {
        let source = try Self.source("App/DemoSupport.swift")
        let symbols = [
            "final class DemoMoleProcess",
            "struct DemoMoleStreaming",
            "struct DemoUninstallListStream",
            "struct DemoConfiguration",
            "struct DemoDiskScanner",
            "enum DemoFixtures"
        ]
        for symbol in symbols {
            XCTAssertTrue(source.contains(symbol), "\(symbol) must live in DemoSupport.swift")
        }
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
