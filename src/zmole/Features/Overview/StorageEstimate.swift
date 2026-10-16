import Foundation

/// Five-segment disk estimate for the overview.
///
/// `mole status` only exposes total/used capacity, so the categories are
/// estimated from `analyze` directory sums. The user-data segment subtracts the
/// developer directory so the nesting between `/Users` and
/// `~/Library/Developer` is not counted twice.
struct StorageBreakdown: Equatable, Sendable {
    var applicationsBytes: Int64?
    var systemBytes: Int64?
    var developerBytes: Int64?
    var userDataBytes: Int64?
    var otherBytes: Int64?

    static let placeholder = StorageBreakdown()

    var isComplete: Bool {
        applicationsBytes != nil
            && systemBytes != nil
            && developerBytes != nil
            && userDataBytes != nil
            && otherBytes != nil
    }

    static func make(
        applications: Int64?,
        system: Int64?,
        developer: Int64?,
        users: Int64?,
        usedBytes: Int64?
    ) -> StorageBreakdown {
        let userData: Int64?
        if let users, let developer {
            userData = max(0, users - developer)
        } else {
            userData = nil
        }
        let other: Int64?
        if let usedBytes,
           let applications, let system, let developer, let userData {
            other = max(0, usedBytes - (applications + system + developer + userData))
        } else {
            other = nil
        }
        return StorageBreakdown(
            applicationsBytes: applications,
            systemBytes: system,
            developerBytes: developer,
            userDataBytes: userData,
            otherBytes: other
        )
    }
}

/// Raw directory sums behind the five-segment estimate. These are the values
/// worth caching; the final segments (including "other") are derived with the
/// live status used-space value.
struct StorageSums: Equatable, Codable, Sendable {
    var applications: Int64?
    var system: Int64?
    var developer: Int64?
    var users: Int64?

    var isComplete: Bool {
        applications != nil && system != nil && developer != nil && users != nil
    }

    func breakdown(usedBytes: Int64?) -> StorageBreakdown {
        StorageBreakdown.make(
            applications: applications,
            system: system,
            developer: developer,
            users: users,
            usedBytes: usedBytes
        )
    }
}

struct StorageEstimateLoader: Sendable {
    typealias DirectorySize = @Sendable (String) async throws -> Int64?
    typealias SystemChildren = @Sendable () throws -> [String]

    private let directorySize: DirectorySize
    private let systemChildren: SystemChildren

    init(
        directorySize: @escaping DirectorySize,
        systemChildren: @escaping SystemChildren = {
            try StorageEstimateLoader.directoryChildren(of: "/System")
        }
    ) {
        self.directorySize = directorySize
        self.systemChildren = systemChildren
    }

    init(loader: AnalyzeSnapshotLoader, home: String = NSHomeDirectory()) {
        directorySize = { path in
            let expanded = path.hasPrefix("~")
                ? home + path.dropFirst()
                : path
            do {
                let snapshot = try await loader.load(path: expanded)
                return snapshot.entries.reduce(Int64(0)) { $0 + $1.size }
            } catch let error as MoleBridgeError where error == .cancelled {
                throw CancellationError()
            } catch {
                return nil
            }
        }
        systemChildren = {
            try Self.directoryChildren(of: "/System")
        }
    }

    /// Directory-only children (files like `.DS_Store` are not system-volume
    /// content worth probing).
    private static func directoryChildren(of path: String) throws -> [String] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let children = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        return children.compactMap { child in
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return child.lastPathComponent
        }
    }

    /// Runs the directory probes sequentially on this lane's bridge. Throws
    /// `CancellationError` when the scan is cancelled, so callers never treat
    /// a cancelled pass as a complete result.
    func loadSums() async throws -> StorageSums {
        let applications = try await directorySize("/Applications")
        let system = try await systemSize()
        let developer = try await directorySize("~/Library/Developer")
        let users = try await directorySize("/Users")
        return StorageSums(
            applications: applications,
            system: system,
            developer: developer,
            users: users
        )
    }

    /// The `系统` segment only covers the read-only system volume: `/System` is
    /// summed child by child with `/System/Volumes` (the whole data volume,
    /// snapshots included) skipped. The value stays `analyze /System`'s
    /// top-level sum minus `/System/Volumes`, and the data volume is never
    /// walked, keeping the probe at seconds instead of minutes. A single
    /// unreadable child makes the whole segment unavailable: a partial sum
    /// must never masquerade as a complete one.
    private func systemSize() async throws -> Int64? {
        let children: [String]
        do {
            children = try systemChildren()
        } catch {
            return nil
        }
        let probes = children.filter { $0 != "Volumes" }.sorted()
        guard !probes.isEmpty else { return nil }
        var total: Int64 = 0
        for child in probes {
            try Task.checkCancellation()
            guard let size = try await directorySize("/System/" + child) else {
                return nil
            }
            total += size
        }
        return total
    }

    func load(usedBytes: Int64?) async throws -> StorageBreakdown {
        try await loadSums().breakdown(usedBytes: usedBytes)
    }
}
