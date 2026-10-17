import Foundation
import os

private let probeLog = Logger(subsystem: "com.tutupower.zmole", category: "StorageEstimate")

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

    /// Each channel is an independent analyze runner; probes are distributed
    /// across channels so several paths can be measured in parallel.
    private let channels: [DirectorySize]
    private let systemChildren: SystemChildren
    private let scheduler: HeavyScanScheduler?

    init(
        directorySize: @escaping DirectorySize,
        systemChildren: @escaping SystemChildren = {
            try StorageEstimateLoader.directoryChildren(of: "/System")
        },
        scheduler: HeavyScanScheduler? = nil
    ) {
        channels = [directorySize]
        self.systemChildren = systemChildren
        self.scheduler = scheduler
    }

    init(
        loader: AnalyzeSnapshotLoader,
        home: String = NSHomeDirectory(),
        scheduler: HeavyScanScheduler? = nil
    ) {
        channels = [Self.directorySize(for: loader, home: home)]
        systemChildren = {
            try Self.directoryChildren(of: "/System")
        }
        self.scheduler = scheduler
    }

    /// Multi-channel initializer: each loader owns an independent analyze
    /// runner, so probes are distributed across channels and run in parallel.
    init(
        loaders: [AnalyzeSnapshotLoader],
        home: String = NSHomeDirectory(),
        scheduler: HeavyScanScheduler? = nil
    ) {
        precondition(!loaders.isEmpty, "at least one analyze loader is required")
        channels = loaders.map { Self.directorySize(for: $0, home: home) }
        systemChildren = {
            try Self.directoryChildren(of: "/System")
        }
        self.scheduler = scheduler
    }

    private static func directorySize(for loader: AnalyzeSnapshotLoader, home: String) -> DirectorySize {
        { path in
            let expanded = path.hasPrefix("~")
                ? home + path.dropFirst()
                : path
            do {
                let snapshot = try await loader.load(path: expanded)
                return snapshot.entries.reduce(Int64(0)) { $0 + $1.size }
            } catch let error as MoleBridgeError where error == .cancelled {
                throw CancellationError()
            } catch {
                probeLog.debug("analyze probe failed for \(path, privacy: .private): \(String(describing: type(of: error)), privacy: .public)")
                return nil
            }
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

    /// Runs the directory probes concurrently across channels (each channel
    /// executes at most one command at a time). Throws `CancellationError`
    /// when the scan is cancelled, so callers never treat a cancelled pass as
    /// a complete result. Segments already resolved in `existing` are not
    /// probed again, so a follow-up scan only fills the missing segments.
    /// `includingUsers` is false without Full Disk Access: the `/Users` walk
    /// would reach protected folders and raise TCC dialogs.
    func loadSums(
        filling existing: StorageSums? = nil,
        includingUsers: Bool = true
    ) async throws -> StorageSums {
        let applicationsPath = "/Applications"
        let developerPath = "~/Library/Developer"
        let usersPath = "/Users"

        var probePaths: [String] = []
        if existing?.applications == nil { probePaths.append(applicationsPath) }
        if existing?.developer == nil { probePaths.append(developerPath) }
        if includingUsers, existing?.users == nil { probePaths.append(usersPath) }

        var systemPaths: [String] = []
        if existing?.system == nil {
            let systemChildrenNames: [String]
            do {
                systemChildrenNames = try systemChildren().filter { $0 != "Volumes" }.sorted()
            } catch {
                systemChildrenNames = []
            }
            systemPaths = systemChildrenNames.map { "/System/" + $0 }
        }

        let sizes = try await probeSizes(for: probePaths + systemPaths)

        var system: Int64? = existing?.system
        if system == nil {
            var systemTotal: Int64 = 0
            var systemComplete = !systemPaths.isEmpty
            for path in systemPaths {
                if let size = sizes[path] ?? nil {
                    systemTotal += size
                } else {
                    systemComplete = false
                    break
                }
            }
            system = systemComplete ? systemTotal : nil
        }

        return StorageSums(
            applications: existing?.applications ?? (sizes[applicationsPath] ?? nil),
            system: system,
            developer: existing?.developer ?? (sizes[developerPath] ?? nil),
            users: includingUsers ? (existing?.users ?? (sizes[usersPath] ?? nil)) : nil
        )
    }

    /// The `系统` segment only covers the read-only system volume: `/System`
    /// is summed child by child (round-robin across channels) with
    /// `/System/Volumes` (the whole data volume, snapshots included) skipped.
    /// The data volume is never walked, keeping the probe at seconds instead
    /// of minutes. A single unreadable child makes the whole segment
    /// unavailable: a partial sum must never masquerade as a complete one.
    private func probeSizes(for paths: [String]) async throws -> [String: Int64?] {
        guard !paths.isEmpty else { return [:] }
        var slices = Array(repeating: [String](), count: channels.count)
        for (index, path) in paths.enumerated() {
            slices[index % channels.count].append(path)
        }
        return try await withThrowingTaskGroup(of: [String: Int64?].self) { group in
            for (channelIndex, slice) in slices.enumerated() where !slice.isEmpty {
                let channel = channels[channelIndex]
                let sched = self.scheduler
                group.addTask {
                    var results: [String: Int64?] = [:]
                    for path in slice {
                        try Task.checkCancellation()
                        if let sched {
                            let permit = try await sched.acquire(taskID: "estimate:\(path)", priority: .background)
                            defer {
                                Task { await permit.release() }
                            }
                            results[path] = try await channel(path)
                        } else {
                            results[path] = try await channel(path)
                        }
                    }
                    return results
                }
            }
            var merged: [String: Int64?] = [:]
            for try await partial in group {
                merged.merge(partial) { _, new in new }
            }
            return merged
        }
    }

    func load(usedBytes: Int64?) async throws -> StorageBreakdown {
        try await loadSums().breakdown(usedBytes: usedBytes)
    }
}
