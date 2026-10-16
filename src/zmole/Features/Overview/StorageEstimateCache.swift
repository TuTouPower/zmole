import Foundation

/// Persisted cache of the four directory sums used by the overview estimate.
/// Stored in the app container, never in `~/.config/mole/`.
struct StorageEstimateCacheEntry: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let capturedAt: Date
    let sums: StorageSums
}

struct StorageEstimateCache: Sendable {
    /// Bumped to 2 when the system segment moved to the read-only system
    /// volume: schema-1 entries carry the old (data-volume-inflated) sums and
    /// must not be treated as authoritative.
    static let schemaVersion = 2
    /// Refresh the estimate in the background when older than this.
    static let timeToLive: TimeInterval = 6 * 60 * 60
    /// Treat the entry as unusable when older than this.
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static var live: StorageEstimateCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let url = base
            .appendingPathComponent("zmole", isDirectory: true)
            .appendingPathComponent("storage_estimate.json")
        return StorageEstimateCache(fileURL: url)
    }

    /// Returns a usable entry, or nil when missing, wrong schema, unreadable or
    /// older than the maximum age.
    func load(now: Date = Date()) -> StorageEstimateCacheEntry? {
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder().decode(StorageEstimateCacheEntry.self, from: data) else {
            return nil
        }
        guard entry.schemaVersion == Self.schemaVersion else { return nil }
        guard now.timeIntervalSince(entry.capturedAt) <= Self.maximumAge else { return nil }
        return entry
    }

    func save(_ sums: StorageSums, capturedAt: Date = Date()) {
        let entry = StorageEstimateCacheEntry(
            schemaVersion: Self.schemaVersion,
            capturedAt: capturedAt,
            sums: sums
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func isStale(_ entry: StorageEstimateCacheEntry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.capturedAt) > Self.timeToLive
    }
}
