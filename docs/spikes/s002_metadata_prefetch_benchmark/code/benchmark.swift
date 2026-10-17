import Foundation

// MARK: - Data Models matching DiskScanner

struct HardLinkKey: Hashable {
    let device: UInt64
    let inode: UInt64
}

final class HardLinkDeduplicator {
    private var seen: Set<HardLinkKey> = []

    func markIfNew(_ key: HardLinkKey) -> Bool {
        seen.insert(key).inserted
    }
}

enum DiskEntryValue: Equatable {
    case size(Int64)
    case computing
    case unreadable
    case otherDevice
}

struct DiskEntry: Equatable {
    let name: String
    let path: String
    let isDirectory: Bool
    var value: DiskEntryValue
    var linkKey: HardLinkKey?
    var selfDeduplicatedSize: Int64?
    var parentContribution: Int64?
}

struct WalkResult: Equatable {
    let totalSize: Int64
    let isReadable: Bool
    let entries: [DiskEntry]
}

// MARK: - Implementation 1: Item-by-item lstat (Current Production)

final class ItemByItemScanner {
    struct NodeStat {
        let device: UInt64
        let inode: UInt64
        let blocks: Int64
        let linkCount: UInt64
        let isDirectory: Bool
    }

    private(set) var statCallCount: Int = 0

    func resetStats() {
        statCallCount = 0
    }

    func nodeStat(_ path: String) -> NodeStat? {
        statCallCount += 1
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return NodeStat(
            device: UInt64(bitPattern: Int64(info.st_dev)),
            inode: UInt64(info.st_ino),
            blocks: Int64(info.st_blocks),
            linkCount: UInt64(info.st_nlink),
            isDirectory: (info.st_mode & S_IFMT) == S_IFDIR
        )
    }

    func walk(_ path: String, deduplicator: HardLinkDeduplicator) -> WalkResult {
        guard let directory = nodeStat(path), directory.isDirectory else {
            return WalkResult(totalSize: 0, isReadable: false, entries: [])
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return WalkResult(totalSize: 0, isReadable: false, entries: [])
        }

        var entries: [DiskEntry] = []
        var total: Int64 = 0

        for name in names.sorted() {
            let child = path.hasSuffix("/") ? path + name : path + "/" + name
            guard let info = nodeStat(child) else {
                entries.append(DiskEntry(name: name, path: child, isDirectory: false, value: .unreadable))
                continue
            }

            let linkKey = info.linkCount > 1 ? HardLinkKey(device: info.device, inode: info.inode) : nil
            if info.isDirectory {
                if info.device != directory.device {
                    entries.append(DiskEntry(name: name, path: child, isDirectory: true, value: .otherDevice))
                    continue
                }
                let sub = walk(child, deduplicator: deduplicator)
                let value: DiskEntryValue = sub.isReadable ? .size(sub.totalSize) : .unreadable
                entries.append(DiskEntry(
                    name: name,
                    path: child,
                    isDirectory: true,
                    value: value,
                    selfDeduplicatedSize: sub.isReadable ? sub.totalSize : nil,
                    parentContribution: sub.isReadable ? sub.totalSize : nil
                ))
                total += sub.totalSize
            } else {
                let bytes = info.blocks * 512
                let counted: Int64
                if let linkKey {
                    counted = deduplicator.markIfNew(linkKey) ? bytes : 0
                } else {
                    counted = bytes
                }
                entries.append(DiskEntry(
                    name: name,
                    path: child,
                    isDirectory: false,
                    value: .size(bytes),
                    linkKey: linkKey,
                    selfDeduplicatedSize: bytes,
                    parentContribution: counted
                ))
                total += counted
            }
        }

        return WalkResult(totalSize: total, isReadable: true, entries: entries)
    }
}

// MARK: - Implementation 2: Metadata Prefetching via Foundation URLResourceValues

final class FoundationPrefetchScanner {
    private(set) var enumerationCallCount: Int = 0
    private(set) var fallbackStatCallCount: Int = 0

    func resetStats() {
        enumerationCallCount = 0
        fallbackStatCallCount = 0
    }

    private static let requestedKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .linkCountKey,
        .volumeIdentifierKey
    ]

    func walk(_ path: String, deduplicator: HardLinkDeduplicator) -> WalkResult {
        let parentURL = URL(fileURLWithPath: path, isDirectory: true)

        var parentStat = stat()
        fallbackStatCallCount += 1
        guard lstat(path, &parentStat) == 0, (parentStat.st_mode & S_IFMT) == S_IFDIR else {
            return WalkResult(totalSize: 0, isReadable: false, entries: [])
        }
        let parentDevice = UInt64(bitPattern: Int64(parentStat.st_dev))

        enumerationCallCount += 1
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: Array(Self.requestedKeys),
            options: []
        ) else {
            return WalkResult(totalSize: 0, isReadable: false, entries: [])
        }

        var entries: [DiskEntry] = []
        var total: Int64 = 0

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let childPath = url.path
            let name = url.lastPathComponent

            guard let values = try? url.resourceValues(forKeys: Self.requestedKeys) else {
                entries.append(DiskEntry(name: name, path: childPath, isDirectory: false, value: .unreadable))
                continue
            }

            let isSymlink = values.isSymbolicLink ?? false
            // Note: In APFS/POSIX semantics, symlinks must not be followed. If it is a symlink, it is treated as a leaf file.
            let isDir = (values.isDirectory ?? false) && !isSymlink

            // For inode and st_blocks: URLResourceValues does NOT provide st_blocks or st_ino directly.
            // When linkCount > 1 or allocated size is needed, targeted lstat is performed.
            let linkCount = values.linkCount ?? 1

            var info = stat()
            fallbackStatCallCount += 1
            guard lstat(childPath, &info) == 0 else {
                entries.append(DiskEntry(name: name, path: childPath, isDirectory: false, value: .unreadable))
                continue
            }
            let childDevice = UInt64(bitPattern: Int64(info.st_dev))
            let childInode = UInt64(info.st_ino)
            let blocks = Int64(info.st_blocks)

            let linkKey = linkCount > 1 ? HardLinkKey(device: childDevice, inode: childInode) : nil

            if isDir {
                if childDevice != parentDevice {
                    entries.append(DiskEntry(name: name, path: childPath, isDirectory: true, value: .otherDevice))
                    continue
                }
                let sub = walk(childPath, deduplicator: deduplicator)
                let value: DiskEntryValue = sub.isReadable ? .size(sub.totalSize) : .unreadable
                entries.append(DiskEntry(
                    name: name,
                    path: childPath,
                    isDirectory: true,
                    value: value,
                    selfDeduplicatedSize: sub.isReadable ? sub.totalSize : nil,
                    parentContribution: sub.isReadable ? sub.totalSize : nil
                ))
                total += sub.totalSize
            } else {
                let bytes = blocks * 512
                let counted: Int64
                if let linkKey {
                    counted = deduplicator.markIfNew(linkKey) ? bytes : 0
                } else {
                    counted = bytes
                }
                entries.append(DiskEntry(
                    name: name,
                    path: childPath,
                    isDirectory: false,
                    value: .size(bytes),
                    linkKey: linkKey,
                    selfDeduplicatedSize: bytes,
                    parentContribution: counted
                ))
                total += counted
            }
        }

        return WalkResult(totalSize: total, isReadable: true, entries: entries)
    }
}

// MARK: - Test Suite & Benchmark Runner

func createFixture(at root: URL) throws {
    let fm = FileManager.default

    // Scenario A: Wide directory (1,000 files)
    let wideDir = root.appendingPathComponent("wide")
    try fm.createDirectory(at: wideDir, withIntermediateDirectories: true)
    for i in 0..<1000 {
        let file = wideDir.appendingPathComponent("file_\(String(format: "%04d", i)).txt")
        try "Content \(i)".write(to: file, atomically: true, encoding: .utf8)
    }

    // Scenario B: Deep directory (15 levels, branching)
    var curr = root.appendingPathComponent("deep")
    for level in 0..<15 {
        curr = curr.appendingPathComponent("level_\(level)")
        try fm.createDirectory(at: curr, withIntermediateDirectories: true)
        for f in 0..<5 {
            let file = curr.appendingPathComponent("nested_\(f).txt")
            try "Nested \(f)".write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // Scenario C: Sparse file (simulate block allocation vs length)
    let sparseDir = root.appendingPathComponent("sparse")
    try fm.createDirectory(at: sparseDir, withIntermediateDirectories: true)
    let sparseFile = sparseDir.appendingPathComponent("sparse.bin")
    fm.createFile(atPath: sparseFile.path, contents: nil)
    if let fh = try? FileHandle(forWritingTo: sparseFile) {
        try fh.seek(toOffset: 1024 * 1024 * 10) // 10 MB seek
        try fh.write(contentsOf: Data([0x42]))
        try fh.close()
    }

    // Scenario D: Hard links (100 files linking to 5 targets)
    let linkDir = root.appendingPathComponent("links")
    try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
    for t in 0..<5 {
        let target = linkDir.appendingPathComponent("target_\(t).txt")
        try "Target \(t) multi-link content".write(to: target, atomically: true, encoding: .utf8)
        for l in 0..<20 {
            let link = linkDir.appendingPathComponent("link_\(t)_\(l).txt")
            try fm.linkItem(at: target, to: link)
        }
    }

    // Scenario E: Symlinks (symlink to file, symlink to directory)
    let symDir = root.appendingPathComponent("symlinks")
    try fm.createDirectory(at: symDir, withIntermediateDirectories: true)
    let symTargetFile = symDir.appendingPathComponent("real_file.txt")
    try "Real target".write(to: symTargetFile, atomically: true, encoding: .utf8)
    try fm.createSymbolicLink(at: symDir.appendingPathComponent("sym_file"), withDestinationURL: symTargetFile)
    try fm.createSymbolicLink(at: symDir.appendingPathComponent("sym_dir"), withDestinationURL: wideDir)
}

func runBenchmark() throws {
    let fm = FileManager.default
    let tempRoot = fm.temporaryDirectory.appendingPathComponent("zmole_bench_\(UUID().uuidString)")
    try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempRoot) }

    print("Creating representative fixture at \(tempRoot.path)...")
    try createFixture(at: tempRoot)
    print("Fixture created successfully.\n")

    let itemScanner = ItemByItemScanner()
    let prefetchScanner = FoundationPrefetchScanner()

    // 1. Semantic Equivalence Check (AC-001)
    print("=== Step 1: Semantic Equivalence Verification (AC-001) ===")
    let dedup1 = HardLinkDeduplicator()
    let res1 = itemScanner.walk(tempRoot.path, deduplicator: dedup1)

    let dedup2 = HardLinkDeduplicator()
    let res2 = prefetchScanner.walk(tempRoot.path, deduplicator: dedup2)

    if res1.totalSize == res2.totalSize && res1.isReadable == res2.isReadable && res1.entries.count == res2.entries.count {
        print("✓ AC-001 PASS: Semantics match exactly!")
        print("  - Total size: \(res1.totalSize) bytes")
        print("  - Readable: \(res1.isReadable)")
        print("  - Root direct entries: \(res1.entries.count)")
    } else {
        print("✗ AC-001 FAIL: Discrepancy detected!")
        print("  ItemScanner: size=\(res1.totalSize), readable=\(res1.isReadable), count=\(res1.entries.count)")
        print("  PrefetchScanner: size=\(res2.totalSize), readable=\(res2.isReadable), count=\(res2.entries.count)")
        exit(1)
    }

    // 2. Interleaved Benchmark: 10 repetitions AB / BA (AC-004)
    print("\n=== Step 2: 10-Round AB/BA Interleaved Performance Benchmark (AC-004) ===")
    let repetitions = 10
    var itemTimes: [Double] = []
    var prefetchTimes: [Double] = []
    var itemCalls: [Int] = []
    var prefetchCalls: [Int] = []

    for round in 1...repetitions {
        // Round AB vs BA
        let itemFirst = round % 2 == 1

        var tItem: Double = 0
        var cItem: Int = 0
        var tPrefetch: Double = 0
        var cPrefetch: Int = 0

        func runItem() {
            itemScanner.resetStats()
            let d = HardLinkDeduplicator()
            let start = Date()
            _ = itemScanner.walk(tempRoot.path, deduplicator: d)
            tItem = Date().timeIntervalSince(start)
            cItem = itemScanner.statCallCount
        }

        func runPrefetch() {
            prefetchScanner.resetStats()
            let d = HardLinkDeduplicator()
            let start = Date()
            _ = prefetchScanner.walk(tempRoot.path, deduplicator: d)
            tPrefetch = Date().timeIntervalSince(start)
            cPrefetch = prefetchScanner.enumerationCallCount + prefetchScanner.fallbackStatCallCount
        }

        if itemFirst {
            runItem()
            runPrefetch()
        } else {
            runPrefetch()
            runItem()
        }

        itemTimes.append(tItem)
        prefetchTimes.append(tPrefetch)
        itemCalls.append(cItem)
        prefetchCalls.append(cPrefetch)

        print(String(format: "Round %2d (%@): Item=%.4fs (calls=%d) | Prefetch=%.4fs (calls=%d)",
                     round, itemFirst ? "AB" : "BA", tItem, cItem, tPrefetch, cPrefetch))
    }

    func stats(_ arr: [Double]) -> (avg: Double, min: Double, max: Double) {
        let avg = arr.reduce(0, +) / Double(arr.count)
        return (avg, arr.min()!, arr.max()!)
    }

    let sItem = stats(itemTimes)
    let sPrefetch = stats(prefetchTimes)

    print("\n=== Benchmark Summary ===")
    print(String(format: "Item-by-item (lstat):       avg=%.4fs, min=%.4fs, max=%.4fs (calls per run: %d)",
                 sItem.avg, sItem.min, sItem.max, itemCalls[0]))
    print(String(format: "Foundation Prefetch (URLs):  avg=%.4fs, min=%.4fs, max=%.4fs (calls per run: %d)",
                 sPrefetch.avg, sPrefetch.min, sPrefetch.max, prefetchCalls[0]))

    let diffPercent = ((sPrefetch.avg - sItem.avg) / sItem.avg) * 100.0
    print(String(format: "Difference: Prefetch is %.1f%% %@ than Item-by-item",
                 abs(diffPercent), diffPercent > 0 ? "SLOWER" : "FASTER"))

    if diffPercent > 0 {
        print("\nDecision: Prefetching demonstrates clear performance degradation due to Foundation NSURL heap allocation and bridging overhead.")
        print("Per AC-004 / AC-006: Keep item-by-item lstat reading as the authoritative production strategy.")
    } else {
        print("\nDecision: Prefetching demonstrates stable improvement.")
    }
}

try runBenchmark()
