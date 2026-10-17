import AppKit
import XCTest
@testable import Zmole

final class AppIconTests: XCTestCase {
    func testIconSourcesLiveInAssets() throws {
        let root = Self.repoRoot
        let colored = try String(
            contentsOf: root.appendingPathComponent("assets/app_icon_source.svg"),
            encoding: .utf8
        )
        XCTAssertTrue(
            colored.contains("linearGradient"),
            "the main source must be the colored gradient version"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/app_icon_source_mono.svg").path),
            "the black-and-white backup source is kept in assets/"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("gemini-svg.svg").path),
            "the scratch colored SVG must not stay at the repository root"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("gemini-svg (1).svg").path),
            "the scratch monochrome SVG must not stay at the repository root"
        )
    }

    // The former byte-for-byte regenerability test was removed: its
    // byte-equality assertion flaked across PNG/sips toolchain updates and the
    // per-run `swift` compile turned the unit target into a heavy integration
    // check. Reproducibility is a release-time check (`scripts/build_app_icon.sh`
    // + a manual diff of the regenerated icns); the structural invariants
    // (all sizes, transparent corner, opaque glyph) stay covered below.

    func testAppIconCarriesAllRequiredSizes() throws {
        let root = Self.repoRoot
        let shipped = root.appendingPathComponent("src/zmole/Resources/AppIcon.icns")
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
        defer { try? FileManager.default.removeItem(at: iconset) }

        try run("/usr/bin/iconutil", ["-c", "iconset", "-o", iconset.path, shipped.path])

        let expected = [
            "icon_16x16.png", "icon_16x16@2x.png",
            "icon_32x32.png", "icon_32x32@2x.png",
            "icon_128x128.png", "icon_128x128@2x.png",
            "icon_256x256.png", "icon_256x256@2x.png",
            "icon_512x512.png", "icon_512x512@2x.png"
        ]
        for name in expected {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: iconset.appendingPathComponent(name).path),
                "the icns must carry \(name)"
            )
        }
    }

    func testAppIconKeepsATransparentBackground() throws {
        let shipped = Self.repoRoot.appendingPathComponent("src/zmole/Resources/AppIcon.icns")
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
        defer { try? FileManager.default.removeItem(at: iconset) }
        try run("/usr/bin/iconutil", ["-c", "iconset", "-o", iconset.path, shipped.path])

        let data = try Data(contentsOf: iconset.appendingPathComponent("icon_512x512.png"))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        let corner = try XCTUnwrap(rep.colorAt(x: 2, y: 2))
        XCTAssertEqual(
            corner.alphaComponent,
            0,
            accuracy: 0.01,
            "the icon background must stay transparent (no white preview page)"
        )
        let center = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
        XCTAssertGreaterThan(center.alphaComponent, 0.5, "the glyph stays opaque")
    }

    func testNoStaleIconSourceReferences() throws {
        let root = Self.repoRoot
        for file in ["project.yml", "scripts/build_app_icon.sh", "src/zmole/Info.plist"] {
            let text = try String(
                contentsOf: root.appendingPathComponent(file),
                encoding: .utf8
            )
            XCTAssertFalse(
                text.contains("app_icon_source.png"),
                "\(file) still references the retired PNG source"
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/app_icon_source.png").path),
            "the retired PNG source is replaced by the SVG source"
        )
    }

    // Renamed in the icon hotfix: the sidebar now loads the bundled icns
    // directly (NSApp.applicationIconImage goes through the system icon
    // cache/decoration and served a plated image), with the system icon as a
    // fallback only.
    func testSidebarLoadsTheBundledIconDirectly() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("src/zmole/App/SidebarView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("Bundle.main.url(forResource: \"AppIcon\", withExtension: \"icns\")"),
            "the sidebar must load the bundled icns directly"
        )
        XCTAssertTrue(source.contains("NSApp.applicationIconImage"), "a fallback stays for missing resources")
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errorTail = String(decoding: errorData.suffix(2_048), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            process.terminationStatus,
            0,
            "\(executable) failed: \(errorTail.isEmpty ? "no stderr output" : errorTail)"
        )
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
