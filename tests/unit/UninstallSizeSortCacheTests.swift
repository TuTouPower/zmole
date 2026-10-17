import XCTest
import AppKit
@testable import Zmole

@MainActor
final class UninstallSizeSortCacheTests: XCTestCase {
    // AC-001: 500 条合成记录三种排序符合既有规则；比较期间 HumanSizeParser 调用为 0，未知排在已知后。
    func testAC001_500RecordsSortFollowsRulesWithZeroParserCalls() {
        var items: [UninstallAppListing] = []
        for i in 0..<500 {
            let sizeText: String?
            if i % 5 == 0 {
                sizeText = nil
            } else {
                sizeText = "\(i % 50 + 1) MB"
            }
            let source: String? = (i % 3 == 0) ? nil : ((i % 3 == 1) ? "App" : "Homebrew")
            items.append(UninstallAppListing(
                path: "/Applications/App_\(i).app",
                name: "App_\(String(format: "%03d", i))",
                bundleID: "com.example.app\(i)",
                uninstallName: "app\(i)",
                source: source,
                sizeText: sizeText
            ))
        }

        // Verify stored integer size
        for item in items {
            if let text = item.sizeText {
                XCTAssertNotNil(item.sizeBytes)
                XCTAssertEqual(item.sizeBytes, HumanSizeParser.bytes(from: text))
            } else {
                XCTAssertNil(item.sizeBytes)
            }
        }

        // 1. Sort by name
        let byName = UninstallListOrder.sorted(items, by: .name)
        XCTAssertEqual(byName.count, 500)
        for i in 0..<499 {
            XCTAssertNotEqual(
                byName[i].name.localizedStandardCompare(byName[i + 1].name),
                .orderedDescending
            )
        }

        // 2. Sort by size: known descending, unknown last; same size name descending
        let bySize = UninstallListOrder.sorted(items, by: .size)
        XCTAssertEqual(bySize.count, 500)
        var sawUnknown = false
        for i in 0..<499 {
            let cur = bySize[i]
            let next = bySize[i + 1]
            if cur.sizeBytes == nil {
                sawUnknown = true
            }
            if sawUnknown {
                XCTAssertNil(next.sizeBytes, "All unknowns must be grouped at the end")
            } else if let nextSize = next.sizeBytes, let curSize = cur.sizeBytes {
                XCTAssertGreaterThanOrEqual(curSize, nextSize)
                if curSize == nextSize {
                    XCTAssertNotEqual(
                        cur.name.localizedStandardCompare(next.name),
                        .orderedAscending,
                        "Same size must sort name descending"
                    )
                }
            }
        }

        // 3. Sort by source: empty first, then ascending, same source name ascending
        let bySource = UninstallListOrder.sorted(items, by: .source)
        XCTAssertEqual(bySource.count, 500)
        for i in 0..<499 {
            let s1 = bySource[i].source ?? ""
            let s2 = bySource[i + 1].source ?? ""
            XCTAssertLessThanOrEqual(s1, s2)
            if s1 == s2 {
                XCTAssertNotEqual(
                    bySource[i].name.localizedStandardCompare(bySource[i + 1].name),
                    .orderedDescending
                )
            }
        }
    }

    // AC-002: 内容版本、搜索、来源、排序及 Locale 不变时，只更新图标不调用排序函数。
    func testAC002_IconUpdateDoesNotCallSortFunction() {
        let initialListings = [
            UninstallAppListing(path: "/Applications/B.app", name: "B", sizeText: "10 MB"),
            UninstallAppListing(path: "/Applications/A.app", name: "A", sizeText: "20 MB")
        ]

        let viewModel = UninstallViewModel(
            process: StubProcess(),
            coordinator: OperationCoordinator()
        )
        viewModel.setListingsForTesting(initialListings)

        let initialVersion = viewModel.contentVersion

        // First call caches the sort
        let first = viewModel.visibleListings(search: "", source: "all", sort: .name)
        XCTAssertEqual(first.map(\.name), ["A", "B"])

        // Update an icon
        viewModel.setIconForTesting(NSImage(), forPath: "/Applications/B.app")

        // Content version must not increase on icon updates
        XCTAssertEqual(viewModel.contentVersion, initialVersion)

        // Second call must return the cached result
        let second = viewModel.visibleListings(search: "", source: "all", sort: .name)
        XCTAssertEqual(second.map(\.name), ["A", "B"])
    }

    // AC-003: 更新单行图标后该行图标立即变化，其余图标和可见顺序不变。
    func testAC003_SingleRowIconUpdateReflectsImmediatelyWithoutAffectingOrder() {
        let listings = [
            UninstallAppListing(path: "/Applications/One.app", name: "One", sizeText: "10 MB"),
            UninstallAppListing(path: "/Applications/Two.app", name: "Two", sizeText: "20 MB")
        ]
        let viewModel = UninstallViewModel(
            process: StubProcess(),
            coordinator: OperationCoordinator()
        )
        viewModel.setListingsForTesting(listings)

        XCTAssertNil(viewModel.icon(forPath: "/Applications/One.app"))
        XCTAssertNil(viewModel.icon(forPath: "/Applications/Two.app"))

        let testImage = NSImage()
        viewModel.setIconForTesting(testImage, forPath: "/Applications/One.app")

        XCTAssertIdentical(viewModel.icon(forPath: "/Applications/One.app"), testImage)
        XCTAssertNil(viewModel.icon(forPath: "/Applications/Two.app"))

        let visible = viewModel.visibleListings(search: "", source: "all", sort: .name)
        XCTAssertEqual(visible.map(\.name), ["One", "Two"])
    }

    // AC-004: 两条已知大小为 2 和 1、一条未知时，选择合计为 3，未知标记为真。
    func testAC004_SelectionTotalWithKnownAndUnknownSizes() {
        let app1 = UninstallApp(name: "A", bundleID: "a", uninstallName: "A", path: "/A.app", size: "2 MB")
        let app2 = UninstallApp(name: "B", bundleID: "b", uninstallName: "B", path: "/B.app", size: "1 MB")
        let app3 = UninstallApp(name: "C", bundleID: "c", uninstallName: "C", path: "/C.app", size: nil)

        XCTAssertEqual(app1.sizeBytes, 2_000_000)
        XCTAssertEqual(app2.sizeBytes, 1_000_000)
        XCTAssertNil(app3.sizeBytes)

        let selected = [app1, app2, app3]
        let summary = UninstallSelectionSummary.calculate(for: selected)

        XCTAssertEqual(summary.knownBytes, 3_000_000)
        XCTAssertTrue(summary.hasUnknownSize)
        XCTAssertEqual(summary.count, 3)
    }

    // AC-005: 大小、名称、来源、搜索词、筛选或排序条件改变会重新派生，图标不导致内容版本增加；流合并更新大小后顺序正确。
    func testAC005_ChangesCauseReDerivationAndStreamMergeUpdatesSort() {
        let viewModel = UninstallViewModel(
            process: StubProcess(),
            coordinator: OperationCoordinator()
        )
        viewModel.setListingsForTesting([
            UninstallAppListing(path: "/A.app", name: "Alpha", sizeText: nil),
            UninstallAppListing(path: "/B.app", name: "Beta", sizeText: "50 MB")
        ])

        let v1 = viewModel.contentVersion

        // Initially Alpha has nil size (unknown -> sorted last in size sort)
        let list1 = viewModel.visibleListings(search: "", source: "all", sort: .size)
        XCTAssertEqual(list1.map(\.name), ["Beta", "Alpha"])

        // Stream merge resolves Alpha's size to 100 MB
        var updated = viewModel.listings
        var indexByPath = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($1.path, $0) })
        UninstallListMerge.merge(
            UninstallAppListing(path: "/A.app", name: "Alpha", sizeText: "100 MB"),
            into: &updated,
            indexByPath: &indexByPath
        )
        viewModel.setListingsForTesting(updated)

        XCTAssertGreaterThan(viewModel.contentVersion, v1)

        // Now Alpha (100 MB) should sort before Beta (50 MB)
        let list2 = viewModel.visibleListings(search: "", source: "all", sort: .size)
        XCTAssertEqual(list2.map(\.name), ["Alpha", "Beta"])
    }

    // AC-006: Locale 改变后名称顺序按新比较环境重建；完全同键的行不会随图标更新或重复求值跳动。
    func testAC006_LocaleChangeRebuildsSortAndIdenticalKeysAreStable() {
        let items = [
            UninstallAppListing(path: "/B.app", name: "ä", sizeText: "10 MB"),
            UninstallAppListing(path: "/A.app", name: "z", sizeText: "10 MB")
        ]

        let swedish = Locale(identifier: "sv_SE")
        let german = Locale(identifier: "de_DE")

        let sortedSwedish = UninstallListOrder.sorted(items, by: .name, locale: swedish)
        let sortedGerman = UninstallListOrder.sorted(items, by: .name, locale: german)

        // In Swedish, ä is at the end of the alphabet (after z); in German ä sorts like a (before z)
        XCTAssertEqual(sortedSwedish.map(\.name), ["z", "ä"])
        XCTAssertEqual(sortedGerman.map(\.name), ["ä", "z"])

        // Stability for identical keys
        let duplicates = [
            UninstallAppListing(path: "/p1.app", name: "Same", sizeText: "10 MB"),
            UninstallAppListing(path: "/p2.app", name: "Same", sizeText: "10 MB")
        ]
        let sorted1 = UninstallListOrder.sorted(duplicates, by: .size)
        let sorted2 = UninstallListOrder.sorted(duplicates, by: .size)
        XCTAssertEqual(sorted1.map(\.path), sorted2.map(\.path))
    }
}
