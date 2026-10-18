import Foundation

/// Allocated-byte total for one overview probe.
///
/// The disk page keeps a full SQLite index. Overview only needs category sums,
/// so this result never stores per-file rows.
struct SubtreeAccumulation: Equatable, Sendable {
    var totalSize: Int64
    /// Set when a developer prefix was requested. `nil` means that directory
    /// exists but cannot be listed. `0` means it is absent or empty.
    var developerSize: Int64?
    var rootReadable: Bool
    /// The developer directory itself cannot be listed. The users segment that
    /// depends on it is unavailable.
    var developerUnlisted: Bool
}

protocol OverviewSubtreeMeasuring: Sendable {
    func accumulateSubtree(
        _ path: String,
        developerPrefix: String?,
        missingRootCountsAsZero: Bool
    ) async throws -> SubtreeAccumulation
}

extension LiveDiskScanner: OverviewSubtreeMeasuring {
    func accumulateSubtree(
        _ path: String,
        developerPrefix: String?,
        missingRootCountsAsZero: Bool
    ) async throws -> SubtreeAccumulation {
        let work = Task.detached(priority: .utility) {
            try SubtreeAccumulator.accumulate(
                root: path,
                developerPrefix: developerPrefix,
                missingRootCountsAsZero: missingRootCountsAsZero
            )
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }
}

/// Counts a hard-linked inode once. A link seen under the developer prefix is
/// attributed there no matter which path is visited first.
struct SubtreeLedger: Equatable, Sendable {
    let developerRequested: Bool
    private var unlinked: Int64 = 0
    private var links: [HardLinkKey: Int64] = [:]
    private var developerUnlinked: Int64 = 0
    private var developerLinks: Set<HardLinkKey> = []

    init(developerRequested: Bool) {
        self.developerRequested = developerRequested
    }

    mutating func addFile(bytes: Int64, link: HardLinkKey?, underDeveloper: Bool) {
        if let link {
            if links[link] == nil { links[link] = bytes }
            if underDeveloper { developerLinks.insert(link) }
        } else {
            unlinked += bytes
            if underDeveloper { developerUnlinked += bytes }
        }
    }

    var totalSize: Int64 {
        unlinked + links.values.reduce(0, +)
    }

    var developerSize: Int64? {
        guard developerRequested else { return nil }
        let linked = developerLinks.reduce(Int64(0)) { $0 + (links[$1] ?? 0) }
        return developerUnlinked + linked
    }
}

enum SubtreeAccumulator {
    private enum Presence {
        case missing
        case unreadable
        case directory
        case other
    }

    private struct Frame {
        let path: String
        let device: UInt64
        let underDeveloper: Bool
    }

    static func accumulate(
        root: String,
        developerPrefix: String?,
        missingRootCountsAsZero: Bool
    ) throws -> SubtreeAccumulation {
        if let developerPrefix {
            switch presence(developerPrefix) {
            case .unreadable:
                return SubtreeAccumulation(totalSize: 0, developerSize: nil, rootReadable: true, developerUnlisted: true)
            case .directory where !canList(developerPrefix):
                return SubtreeAccumulation(totalSize: 0, developerSize: nil, rootReadable: true, developerUnlisted: true)
            case .missing, .directory, .other:
                break
            }
        }

        let rootPresence = presence(root)
        guard rootPresence == .directory, canList(root), let rootInfo = LiveDiskScanner.nodeStat(root), rootInfo.isDirectory else {
            if missingRootCountsAsZero, rootPresence == .missing {
                return SubtreeAccumulation(totalSize: 0, developerSize: nil, rootReadable: true, developerUnlisted: false)
            }
            return SubtreeAccumulation(totalSize: 0, developerSize: nil, rootReadable: false, developerUnlisted: false)
        }

        var ledger = SubtreeLedger(developerRequested: developerPrefix != nil)
        var stack = [Frame(path: root, device: rootInfo.device, underDeveloper: isUnder(root, developerPrefix))]
        while let frame = stack.popLast() {
            try Task.checkCancellation()
            guard let handle = opendir(frame.path) else { continue }
            defer { closedir(handle) }
            while true {
                try Task.checkCancellation()
                errno = 0
                guard let node = readdir(handle) else { break }
                let name = withUnsafePointer(to: &node.pointee.d_name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                let child = LiveDiskScanner.childPath(frame.path, name)
                guard let info = LiveDiskScanner.nodeStat(child) else { continue }
                if info.isDirectory {
                    // Another volume mounted here keeps its own total.
                    if info.device != frame.device { continue }
                    stack.append(Frame(
                        path: child,
                        device: info.device,
                        underDeveloper: frame.underDeveloper || isUnder(child, developerPrefix)
                    ))
                } else {
                    let link = info.linkCount > 1
                        ? HardLinkKey(device: info.device, inode: info.inode)
                        : nil
                    ledger.addFile(
                        bytes: info.blocks * 512,
                        link: link,
                        underDeveloper: frame.underDeveloper || isUnder(child, developerPrefix)
                    )
                }
            }
        }
        return SubtreeAccumulation(
            totalSize: ledger.totalSize,
            developerSize: ledger.developerSize,
            rootReadable: true,
            developerUnlisted: false
        )
    }

    private static func isUnder(_ path: String, _ prefix: String?) -> Bool {
        guard let prefix else { return false }
        return path == prefix || path.hasPrefix(LiveDiskScanner.directoryPrefix(prefix))
    }

    private static func presence(_ path: String) -> Presence {
        var info = stat()
        if lstat(path, &info) != 0 {
            return errno == ENOENT ? .missing : .unreadable
        }
        return (info.st_mode & S_IFMT) == S_IFDIR ? .directory : .other
    }

    private static func canList(_ path: String) -> Bool {
        guard let handle = opendir(path) else { return false }
        closedir(handle)
        return true
    }
}
