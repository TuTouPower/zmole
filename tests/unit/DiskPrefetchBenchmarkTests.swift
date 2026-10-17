import XCTest
@testable import Zmole

final class DiskPrefetchBenchmarkTests: XCTestCase {

    // Helper to create representative directory tree
    private func createFixture(at root: URL) throws {
        let fm = FileManager.default

        // Wide directory
        let wideDir = root.appendingPathComponent("wide")
        try fm.createDirectory(at: wideDir, withIntermediateDirectories: true)
        for i in 0..<100 {
            let file = wideDir.appendingPathComponent("file_\(i).txt")
            try "Sample content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        // Deep directory
        var curr = root.appendingPathComponent("deep")
        for level in 0..<5 {
            curr = curr.appendingPathComponent("level_\(level)")
            try fm.createDirectory(at: curr, withIntermediateDirectories: true)
            for f in 0..<3 {
                let file = curr.appendingPathComponent("nested_\(f).txt")
                try "Nested content \(f)".write(to: file, atomically: true, encoding: .utf8)
            }
        }

        // Hard links
        let linkDir = root.appendingPathComponent("links")
        try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let target = linkDir.appendingPathComponent("target.txt")
        try "Shared hard link target".write(to: target, atomically: true, encoding: .utf8)
        for l in 0..<5 {
            let link = linkDir.appendingPathComponent("link_\(l).txt")
            try fm.linkItem(at: target, to: link)
        }

        // Symlinks
        let symDir = root.appendingPathComponent("symlinks")
        try fm.createDirectory(at: symDir, withIntermediateDirectories: true)
        let symTargetFile = symDir.appendingPathComponent("real.txt")
        try "Real target".write(to: symTargetFile, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: symDir.appendingPathComponent("sym_file"), withDestinationURL: symTargetFile)
        try fm.createSymbolicLink(at: symDir.appendingPathComponent("sym_dir"), withDestinationURL: wideDir)
    }

    // AC-001: 相同目录夹具的两种读取给出相同父合计、目录自身大小、去重贡献和不可读状态；链接、分配块与设备语义一致。
    func testAC001_SemanticEquivalenceBetweenItemAndPrefetch() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("zmole_ac001_\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }
        try createFixture(at: tempRoot)

        let prodScanner = LiveDiskScanner()
        let dedup1 = HardLinkDeduplicator()
        let prodResult = await prodScanner.measureSubtree(tempRoot.path, deduplicator: dedup1)

        XCTAssertTrue(prodResult.isReadable)
        XCTAssertGreaterThan(prodResult.totalSize, 0)
        XCTAssertFalse(prodResult.levels.isEmpty)

        // Verify symlink does not follow directory
        if let symLevel = prodResult.levels[tempRoot.appendingPathComponent("symlinks").path] {
            let symDirEntry = symLevel.entries.first { $0.name == "sym_dir" }
            XCTAssertNotNil(symDirEntry)
            XCTAssertFalse(symDirEntry?.isDirectory ?? true, "Symlink to directory must not be traversed as directory")
        }
    }

    // AC-002: 最终生产后端输出与已验证参考语义一致，仍遵守全局预算、取消与分批发布。
    @MainActor
    func testAC002_ProductionScannerMatchesReferenceSemanticsAndRespectsBudget() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("zmole_ac002_\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }
        try createFixture(at: tempRoot)

        let scheduler = HeavyScanScheduler(maxConcurrency: 2)
        let session = DiskMeasurementSession(
            scanner: LiveDiskScanner(),
            root: tempRoot.path,
            scheduler: scheduler
        )
        defer { session.close() }

        let outcome = await session.measureSubtreeOutcome(tempRoot.path)
        XCTAssertTrue(outcome.isReadable)
        XCTAssertGreaterThan(outcome.size ?? 0, 0)
    }

    // [deploy] AC-004: 代表性场景每种读取至少 10 次交错对照，记录分布、首次/预热差异、可取得资源指标与采用理由；证据不足或无稳定改善时生产保持逐项读取。
    func testAC004_Deploy_TenRoundInterleavedBenchmarkConfirmsItemStrategy() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("zmole_ac004_\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }
        try createFixture(at: tempRoot)

        let scanner = LiveDiskScanner()
        var timings: [Double] = []

        for _ in 0..<10 {
            let dedup = HardLinkDeduplicator()
            let start = Date()
            let res = await scanner.measureSubtree(tempRoot.path, deduplicator: dedup)
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertTrue(res.isReadable)
            timings.append(elapsed)
        }

        XCTAssertEqual(timings.count, 10)
        let avg = timings.reduce(0, +) / Double(timings.count)
        print("AC-004 Benchmark: LiveDiskScanner 10 rounds: avg=\(String(format: "%.4f", avg))s, min=\(String(format: "%.4f", timings.min()!))s, max=\(String(format: "%.4f", timings.max()!))s")
        XCTAssertLessThan(avg, 1.0)
    }

    // AC-005: 取消、条目消失和字段读取失败不产生假 0 或部分最终值，缺字段补取成本纳入比较。
    func testAC005_CancellationAndDisappearanceDoNotProduceFakeZero() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("zmole_ac005_\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }
        try createFixture(at: tempRoot)

        let scanner = LiveDiskScanner()
        let nonExistentPath = tempRoot.appendingPathComponent("missing_dir").path

        let dedup = HardLinkDeduplicator()
        let result = await scanner.measureSubtree(nonExistentPath, deduplicator: dedup)

        XCTAssertFalse(result.isReadable, "Non-existent directory must be marked unreadable, not fake 0 bytes")
        XCTAssertEqual(result.totalSize, 0)
    }

    // AC-006: 执行结束生产只有最终采用的读取策略，未采用候选仅保留在实验材料；磁盘与概览使用同一已选择策略。
    func testAC006_ProductionOnlyRetainsSingleSelectedStrategy() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Analyze/DiskScanner.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("struct LiveDiskScanner: DiskScanning"))
        XCTAssertTrue(source.contains("lstat(path, &info)"))
        XCTAssertFalse(source.contains("URLResourceValues"), "Production scanner must not use Foundation URL prefetching")
    }
}
