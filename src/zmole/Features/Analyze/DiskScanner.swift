import Foundation

/// Identity of a file with more than one hard link inside one scan.
struct HardLinkKey: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

/// Counts hard-linked nodes once per scan generation. The controller seeds it
/// with the direct files of the listed level before sibling subtrees are
/// measured, so a link shared across the level counts once overall.
final class HardLinkDeduplicator: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<HardLinkKey> = []

    /// Returns true when this node was not counted before.
    func markIfNew(_ key: HardLinkKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seen.insert(key).inserted
    }
}

/// Size state of one directory-list row.
enum DiskEntryValue: Equatable, Sendable {
    /// Allocated bytes, `st_blocks × 512` for files and the counted subtree
    /// sum for directories.
    case size(Int64)
    /// Directory whose subtree is still being measured.
    case computing
    /// The entry could not be read or stat'd; never shown as zero bytes.
    case unreadable
    /// Directory on a different device than its parent; not part of the parent
    /// total and measured separately when entered.
    case otherDevice
}

struct DiskEntry: Identifiable, Equatable, Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    var value: DiskEntryValue
    /// Present when the node has more than one hard link.
    var linkKey: HardLinkKey?

    init(
        name: String,
        path: String,
        isDirectory: Bool,
        value: DiskEntryValue,
        linkKey: HardLinkKey? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.value = value
        self.linkKey = linkKey
    }

    var id: String { path }

    var knownSize: Int64? {
        if case .size(let bytes) = value { return bytes }
        return nil
    }
}

/// One measured directory level: its direct children plus the counted sum,
/// which stays exact even when hard-linked files are displayed more than once.
struct DiskLevel: Equatable, Sendable {
    var entries: [DiskEntry]
    var totalSize: Int64
}

/// Result of walking one directory subtree. `levels` holds the direct children
/// of every visited directory so later entries into those directories are
/// served from the session cache without re-reading the disk.
struct DiskScanResult: Equatable, Sendable {
    let path: String
    let totalSize: Int64
    let isReadable: Bool
    let levels: [String: DiskLevel]
}

enum DiskScanError: Error, Equatable, LocalizedError, Sendable, ErrorKeyProviding {
    case unreadable(String)

    var errorKey: String { "disk.error.unreadable" }

    var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "无法读取目录：\(path)"
        }
    }
}

protocol DiskScanning: Sendable {
    /// Lists one directory level immediately. Direct files carry their
    /// allocated size; same-device directories are `.computing` until their
    /// subtree is measured.
    func listDirectory(_ path: String) async throws -> [DiskEntry]

    /// Walks the subtree rooted at `path` read-only. Files count
    /// `st_blocks × 512`; hard links count once per deduplicator; symlinks
    /// count only themselves; cross-device directories are excluded.
    func measureSubtree(_ path: String, deduplicator: HardLinkDeduplicator) async -> DiskScanResult
}

/// Real file-system scanner. Read-only: everything comes from `lstat` and
/// directory listings; no bundle command is involved.
struct LiveDiskScanner: DiskScanning {
    func listDirectory(_ path: String) async throws -> [DiskEntry] {
        try await Task.detached(priority: .utility) {
            try Self.list(path)
        }.value
    }

    func measureSubtree(_ path: String, deduplicator: HardLinkDeduplicator) async -> DiskScanResult {
        let work = Task.detached(priority: .utility) {
            var levels: [String: DiskLevel] = [:]
            let outcome = Self.walk(path, deduplicator: deduplicator, levels: &levels)
            return DiskScanResult(
                path: path,
                totalSize: outcome.totalSize,
                isReadable: outcome.isReadable,
                levels: levels
            )
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    struct NodeStat {
        let device: UInt64
        let inode: UInt64
        let blocks: Int64
        let linkCount: UInt64
        let isDirectory: Bool
    }

    static func nodeStat(_ path: String) -> NodeStat? {
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

    static func childPath(_ parent: String, _ name: String) -> String {
        parent.hasSuffix("/") ? parent + name : parent + "/" + name
    }

    /// Prefix that matches every path below `path`.
    static func directoryPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private static func list(_ path: String) throws -> [DiskEntry] {
        guard let directory = nodeStat(path), directory.isDirectory else {
            throw DiskScanError.unreadable(path)
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            throw DiskScanError.unreadable(path)
        }
        return names.sorted().compactMap { name in
            entry(name: name, parent: path, parentDevice: directory.device)
        }
    }

    private static func entry(name: String, parent: String, parentDevice: UInt64) -> DiskEntry? {
        let child = childPath(parent, name)
        guard let info = nodeStat(child) else {
            return DiskEntry(name: name, path: child, isDirectory: false, value: .unreadable)
        }
        let linkKey = info.linkCount > 1
            ? HardLinkKey(device: info.device, inode: info.inode)
            : nil
        if info.isDirectory {
            let value: DiskEntryValue = info.device == parentDevice ? .computing : .otherDevice
            return DiskEntry(name: name, path: child, isDirectory: true, value: value)
        }
        return DiskEntry(
            name: name,
            path: child,
            isDirectory: false,
            value: .size(info.blocks * 512),
            linkKey: linkKey
        )
    }

    private struct WalkOutcome {
        var totalSize: Int64
        var isReadable: Bool
    }

    private static func walk(
        _ path: String,
        deduplicator: HardLinkDeduplicator,
        levels: inout [String: DiskLevel]
    ) -> WalkOutcome {
        guard let directory = nodeStat(path), directory.isDirectory else {
            return WalkOutcome(totalSize: 0, isReadable: false)
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return WalkOutcome(totalSize: 0, isReadable: false)
        }
        var entries: [DiskEntry] = []
        var total: Int64 = 0
        for name in names.sorted() {
            if Task.isCancelled {
                // Partial result; the caller discards it once the measurable
                // task has been cancelled.
                levels[path] = DiskLevel(entries: entries, totalSize: total)
                return WalkOutcome(totalSize: total, isReadable: false)
            }
            let child = childPath(path, name)
            guard let info = nodeStat(child) else {
                entries.append(
                    DiskEntry(name: name, path: child, isDirectory: false, value: .unreadable)
                )
                continue
            }
            let linkKey = info.linkCount > 1
                ? HardLinkKey(device: info.device, inode: info.inode)
                : nil
            if info.isDirectory {
                if info.device != directory.device {
                    entries.append(
                        DiskEntry(name: name, path: child, isDirectory: true, value: .otherDevice)
                    )
                    continue
                }
                let outcome = walk(child, deduplicator: deduplicator, levels: &levels)
                let value: DiskEntryValue = outcome.isReadable ? .size(outcome.totalSize) : .unreadable
                entries.append(
                    DiskEntry(name: name, path: child, isDirectory: true, value: value)
                )
                total += outcome.totalSize
            } else {
                let bytes = info.blocks * 512
                let counted: Int64
                if let linkKey {
                    counted = deduplicator.markIfNew(linkKey) ? bytes : 0
                } else {
                    counted = bytes
                }
                entries.append(
                    DiskEntry(
                        name: name,
                        path: child,
                        isDirectory: false,
                        value: .size(bytes),
                        linkKey: linkKey
                    )
                )
                total += counted
            }
        }
        levels[path] = DiskLevel(entries: entries, totalSize: total)
        return WalkOutcome(totalSize: total, isReadable: true)
    }
}
