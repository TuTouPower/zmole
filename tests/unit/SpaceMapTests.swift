import XCTest
@testable import Zmole

final class SpaceMapTests: XCTestCase {
    func testAreaIsProportionalAndRectanglesDoNotOverlap() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let tiles = SpaceMapLayout.tiles(
            entries: [entry("large", 80), entry("medium", 15), entry("small", 5)],
            in: bounds
        )
        XCTAssertEqual(tiles.count, 3)
        for tile in tiles {
            XCTAssertEqual(tile.rect.width * tile.rect.height / 400_000,
                           Double(tile.entry.size) / 100, accuracy: 0.000001)
            XCTAssertTrue(bounds.contains(tile.rect))
        }
        for i in tiles.indices {
            for j in tiles.indices where i < j {
                let overlap = tiles[i].rect.intersection(tiles[j].rect)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height == 0)
            }
        }
    }

    func testZeroAndNegativeSizesDoNotInventArea() {
        let tiles = SpaceMapLayout.tiles(
            entries: [entry("empty", 0), entry("invalid", -1), entry("file", 1)],
            in: CGRect(x: 0, y: 0, width: 20, height: 30)
        )
        XCTAssertEqual(tiles.map(\.entry.name), ["file"])
        XCTAssertEqual(tiles.first?.rect.size, CGSize(width: 20, height: 30))
        XCTAssertTrue(SpaceMapLayout.tiles(entries: [entry("empty", 0)], in: .zero).isEmpty)
    }

    func testLargestSizesDoNotOverflowAndLayoutIsDeterministic() {
        let entries = [entry("a", .max), entry("b", .max), entry("c", 1)]
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let first = SpaceMapLayout.tiles(entries: entries, in: bounds)
        let second = SpaceMapLayout.tiles(entries: entries.reversed(), in: bounds)
        XCTAssertEqual(first.map(\.entry.id), second.map(\.entry.id))
        XCTAssertEqual(first.map(\.rect), second.map(\.rect))
        XCTAssertTrue(first.allSatisfy { $0.rect.width.isFinite && $0.rect.height.isFinite })
    }

    private func entry(_ name: String, _ size: Int64) -> AnalyzeEntry {
        AnalyzeEntry(name: name, path: "/" + name, size: size, isDirectory: true)
    }
}
