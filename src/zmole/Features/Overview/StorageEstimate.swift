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

struct StorageEstimateLoader: Sendable {
    typealias DirectorySize = @Sendable (String) async -> Int64?

    private let directorySize: DirectorySize

    init(directorySize: @escaping DirectorySize) {
        self.directorySize = directorySize
    }

    init(loader: AnalyzeSnapshotLoader, home: String = NSHomeDirectory()) {
        directorySize = { path in
            let expanded = path.hasPrefix("~")
                ? home + path.dropFirst()
                : path
            guard let snapshot = try? await loader.load(path: expanded) else { return nil }
            return snapshot.entries.reduce(Int64(0)) { $0 + $1.size }
        }
    }

    func load(usedBytes: Int64?) async -> StorageBreakdown {
        // The command bridge allows one in-flight process, so the four directory
        // probes run sequentially instead of concurrently.
        let applications = await directorySize("/Applications")
        let system = await directorySize("/System")
        let developer = await directorySize("~/Library/Developer")
        let users = await directorySize("/Users")
        return StorageBreakdown.make(
            applications: applications,
            system: system,
            developer: developer,
            users: users,
            usedBytes: usedBytes
        )
    }
}
