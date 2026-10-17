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

    private let session: DiskMeasurementSession?
    private let channels: [DirectorySize]
    private let systemChildren: SystemChildren
    private let scheduler: HeavyScanScheduler?
    private let homeDirectory: String
    private let applicationsPath: String
    private let usersPath: String

    init(
        session: DiskMeasurementSession,
        home: String = NSHomeDirectory(),
        applicationsPath: String = "/Applications",
        usersPath: String = "/Users",
        systemChildren: @escaping SystemChildren = {
            try StorageEstimateLoader.directoryChildren(of: "/System")
        },
        scheduler: HeavyScanScheduler? = nil
    ) {
        self.session = session
        self.channels = []
        self.homeDirectory = home
        self.applicationsPath = applicationsPath
        self.usersPath = usersPath
        self.systemChildren = systemChildren
        self.scheduler = scheduler
    }

    init(
        directorySize: @escaping DirectorySize,
        applicationsPath: String = "/Applications",
        usersPath: String = "/Users",
        systemChildren: @escaping SystemChildren = {
            try StorageEstimateLoader.directoryChildren(of: "/System")
        },
        scheduler: HeavyScanScheduler? = nil
    ) {
        self.session = nil
        self.channels = [directorySize]
        self.homeDirectory = NSHomeDirectory()
        self.applicationsPath = applicationsPath
        self.usersPath = usersPath
        self.systemChildren = systemChildren
        self.scheduler = scheduler
    }

    init(
        loader: AnalyzeSnapshotLoader,
        home: String = NSHomeDirectory(),
        applicationsPath: String = "/Applications",
        usersPath: String = "/Users",
        scheduler: HeavyScanScheduler? = nil
    ) {
        self.session = nil
        self.channels = [Self.directorySize(for: loader, home: home)]
        self.homeDirectory = home
        self.applicationsPath = applicationsPath
        self.usersPath = usersPath
        self.systemChildren = {
            try Self.directoryChildren(of: "/System")
        }
        self.scheduler = scheduler
    }

    /// Multi-channel initializer: each loader owns an independent analyze
    /// runner, so probes are distributed across channels and run in parallel.
    init(
        loaders: [AnalyzeSnapshotLoader] = [],
        channels: [DirectorySize] = [],
        applicationsPath: String = "/Applications",
        usersPath: String = "/Users",
        systemChildren: @escaping SystemChildren = {
            try StorageEstimateLoader.directoryChildren(of: "/System")
        },
        scheduler: HeavyScanScheduler? = nil,
        home: String = NSHomeDirectory()
    ) {
        self.session = nil
        if !channels.isEmpty {
            self.channels = channels
        } else if !loaders.isEmpty {
            self.channels = loaders.map { Self.directorySize(for: $0, home: home) }
        } else {
            self.channels = []
        }
        self.homeDirectory = home
        self.applicationsPath = applicationsPath
        self.usersPath = usersPath
        self.systemChildren = systemChildren
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

    /// Runs the directory probes concurrently across available channels via a shared work queue.
    /// Throws `CancellationError` when the scan is cancelled, so callers never treat a cancelled pass
    /// as a complete result. Segments already resolved in `existing` are not probed again.
    func loadSums(
        filling existing: StorageSums? = nil,
        includingUsers: Bool = true,
        refresh: Bool = false,
        onProgress: (@Sendable (StorageSums) -> Void)? = nil
    ) async throws -> StorageSums {
        let expandedHome = homeDirectory.hasPrefix("~") ? (NSHomeDirectory() + homeDirectory.dropFirst()) : homeDirectory
        let developerPath = expandedHome + "/Library/Developer"
        let applicationsPath = self.applicationsPath
        let usersPath = self.usersPath

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

        if let session {
            if refresh { await session.invalidateMeasurements() }
            var initialPaths: [String] = []
            if existing?.applications == nil { initialPaths.append(applicationsPath) }
            if includingUsers {
                if existing?.users == nil || existing?.developer == nil {
                    initialPaths.append(usersPath)
                }
            } else {
                if existing?.developer == nil {
                    initialPaths.append(developerPath)
                }
            }

            let allPaths = initialPaths + systemPaths
            guard !allPaths.isEmpty else {
                let res = existing ?? StorageSums()
                onProgress?(res)
                return res
            }

            let aggregator = ProbeAggregator(
                initialSums: existing ?? StorageSums(),
                systemPaths: Set(systemPaths),
                developerPath: developerPath,
                applicationsPath: applicationsPath, usersPath: usersPath,
                onProgress: onProgress
            )

            let workQueue = ProbeWorkQueue(paths: allPaths)
            let workerCount = min(allPaths.count, max(1, scheduler?.maxConcurrency ?? 3))

            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<workerCount {
                    group.addTask { @MainActor in
                        while !Task.isCancelled {
                            guard let path = await workQueue.dequeue() else { break }
                            try Task.checkCancellation()

                            if path == usersPath {
                                let outcome = await session.measureSubtreeOutcome(usersPath)
                                if outcome.isReadable {
                                    let usersTotal = outcome.size ?? 0
                                    let devSize = session.isSubtreeReadable(for: developerPath) ? session.selfDeduplicatedSize(for: developerPath) : nil
                                    await aggregator.recordUsersAndDeveloper(usersTotal: usersTotal, developerSize: devSize)
                                } else {
                                    await aggregator.record(path: usersPath, size: nil)
                                }
                            } else {
                                let outcome = await session.measureSubtreeOutcome(path)
                                await aggregator.record(path: path, size: outcome.isReadable ? outcome.size : nil)
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }

            try Task.checkCancellation()
            return await aggregator.finalSums(includingUsers: includingUsers, hadExistingUsers: existing?.users != nil)
        }

        // Fallback for mock channels/directorySize
        let channelDevPath = homeDirectory == NSHomeDirectory() ? "~/Library/Developer" : developerPath
        var probePaths: [String] = []
        if existing?.applications == nil { probePaths.append(applicationsPath) }
        if existing?.developer == nil { probePaths.append(channelDevPath) }
        if includingUsers, existing?.users == nil { probePaths.append(usersPath) }

        let allPaths = probePaths + systemPaths
        guard !allPaths.isEmpty else {
            let res = existing ?? StorageSums()
            onProgress?(res)
            return res
        }

        let aggregator = ProbeAggregator(
            initialSums: existing ?? StorageSums(),
            systemPaths: Set(systemPaths),
            developerPath: channelDevPath,
            applicationsPath: applicationsPath, usersPath: usersPath,
            onProgress: onProgress
        )

        let workQueue = ProbeWorkQueue(paths: allPaths)
        let sched = self.scheduler

        try await withThrowingTaskGroup(of: Void.self) { group in
            for channel in channels {
                group.addTask {
                    while !Task.isCancelled {
                        guard let path = await workQueue.dequeue() else { break }
                        try Task.checkCancellation()
                        if let sched {
                            let permit = try await sched.acquire(taskID: "estimate:\(path)", priority: .background)
                            defer {
                                Task { await permit.release() }
                            }
                            let size = try await channel(path)
                            await aggregator.record(path: path, size: size)
                        } else {
                            let size = try await channel(path)
                            await aggregator.record(path: path, size: size)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        try Task.checkCancellation()
        return await aggregator.finalSums(includingUsers: includingUsers, hadExistingUsers: existing?.users != nil)
    }

    func load(usedBytes: Int64?) async throws -> StorageBreakdown {
        try await loadSums().breakdown(usedBytes: usedBytes)
    }
}

private actor ProbeAggregator {
    private var currentSums: StorageSums
    private let systemPaths: Set<String>
    private let developerPath: String
    private let applicationsPath: String
    private let usersPath: String
    private var systemSizes: [String: Int64] = [:]
    private var systemHasFailure = false
    private let onProgress: (@Sendable (StorageSums) -> Void)?

    init(
        initialSums: StorageSums,
        systemPaths: Set<String>,
        developerPath: String = "~/Library/Developer",
        applicationsPath: String = "/Applications", usersPath: String = "/Users",
        onProgress: (@Sendable (StorageSums) -> Void)?
    ) {
        self.currentSums = initialSums
        self.systemPaths = systemPaths
        self.developerPath = developerPath
        self.applicationsPath = applicationsPath
        self.usersPath = usersPath
        self.onProgress = onProgress
    }

    func recordUsersAndDeveloper(usersTotal: Int64, developerSize: Int64?) {
        currentSums.users = usersTotal
        currentSums.developer = developerSize
        onProgress?(currentSums)
    }

    func record(path: String, size: Int64?) {
        if path == applicationsPath {
            currentSums.applications = size
            onProgress?(currentSums)
        } else if path == developerPath || path == "~/Library/Developer" {
            currentSums.developer = size
            onProgress?(currentSums)
        } else if path == usersPath {
            currentSums.users = size
            onProgress?(currentSums)
        } else if systemPaths.contains(path) {
            if let size {
                systemSizes[path] = size
            } else {
                systemHasFailure = true
            }
            if systemHasFailure {
                currentSums.system = nil
                onProgress?(currentSums)
            } else if systemSizes.count == systemPaths.count {
                let total = systemSizes.values.reduce(Int64(0), +)
                currentSums.system = total
                onProgress?(currentSums)
            }
        }
    }

    func finalSums(includingUsers: Bool, hadExistingUsers: Bool) -> StorageSums {
        var result = currentSums
        if !systemPaths.isEmpty {
            if systemHasFailure || systemSizes.count < systemPaths.count {
                result.system = nil
            } else {
                result.system = systemSizes.values.reduce(Int64(0), +)
            }
        }
        if !includingUsers && !hadExistingUsers {
            result.users = nil
        }
        return result
    }
}

private actor ProbeWorkQueue {
    private var queue: [String]

    init(paths: [String]) {
        self.queue = paths
    }

    func dequeue() -> String? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
}
