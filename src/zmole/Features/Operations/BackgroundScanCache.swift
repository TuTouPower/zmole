import Foundation

struct BackgroundScanCacheEntry: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let capturedAt: Date
    let payload: BackgroundScanPayload
    let targetVersion: UInt64
    let capturedVersion: UInt64
    let isStale: Bool
}

private struct BackgroundScanCacheFile: Codable {
    let schemaVersion: Int
    let entries: [String: BackgroundScanCacheEntry]
}

/// Persists background scan results so pages have data immediately after a
/// relaunch, before the scans finish. Stored in the app container, never in
/// `~/.config/mole/`. A corrupt or older-schema file is ignored as a whole.
struct BackgroundScanCache: Sendable {
    static let schemaVersion = 2

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static var live: BackgroundScanCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let url = base
            .appendingPathComponent("zmole", isDirectory: true)
            .appendingPathComponent("background_scan_cache.json")
        return BackgroundScanCache(fileURL: url)
    }

    func load() -> [BackgroundScanItem: BackgroundScanResult] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(BackgroundScanCacheFile.self, from: data),
              file.schemaVersion == Self.schemaVersion else {
            return [:]
        }
        var results: [BackgroundScanItem: BackgroundScanResult] = [:]
        for (key, entry) in file.entries {
            guard entry.schemaVersion == Self.schemaVersion,
                  let item = BackgroundScanItem(rawValue: key) else { continue }
            results[item] = BackgroundScanResult(
                capturedAt: entry.capturedAt,
                payload: entry.payload,
                targetVersion: entry.targetVersion,
                capturedVersion: entry.capturedVersion,
                isStale: entry.isStale
            )
        }
        return results
    }

    func save(_ results: [BackgroundScanItem: BackgroundScanResult]) {
        try? saveThrowing(results)
    }

    func saveThrowing(_ results: [BackgroundScanItem: BackgroundScanResult]) throws {
        let entries = Dictionary(
            uniqueKeysWithValues: results.map { item, result in
                (
                    item.rawValue,
                    BackgroundScanCacheEntry(
                        schemaVersion: Self.schemaVersion,
                        capturedAt: result.capturedAt,
                        payload: result.payload,
                        targetVersion: result.targetVersion,
                        capturedVersion: result.capturedVersion,
                        isStale: result.isStale
                    )
                )
            }
        )
        let data = try JSONEncoder().encode(
            BackgroundScanCacheFile(schemaVersion: Self.schemaVersion, entries: entries)
        )
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

extension BackgroundScanPayload: Codable {
    private enum PayloadType: String, Codable {
        case uninstallRows
        case installerCandidates
        case cleanPreview
        case maintenance
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case rows
        case candidates
        case cleanPreview
        case maintenance
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .uninstallRows(rows):
            try container.encode(PayloadType.uninstallRows, forKey: .type)
            try container.encode(rows, forKey: .rows)
        case let .installerCandidates(candidates):
            try container.encode(PayloadType.installerCandidates, forKey: .type)
            try container.encode(candidates, forKey: .candidates)
        case let .cleanPreview(snapshot):
            try container.encode(PayloadType.cleanPreview, forKey: .type)
            try container.encode(snapshot, forKey: .cleanPreview)
        case let .maintenance(output):
            try container.encode(PayloadType.maintenance, forKey: .type)
            try container.encode(output, forKey: .maintenance)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PayloadType.self, forKey: .type) {
        case .uninstallRows:
            self = .uninstallRows(try container.decode([UninstallAppListing].self, forKey: .rows))
        case .installerCandidates:
            self = .installerCandidates(try container.decode([InstallerCandidate].self, forKey: .candidates))
        case .cleanPreview:
            self = .cleanPreview(try container.decode(CleanPreviewSnapshot.self, forKey: .cleanPreview))
        case .maintenance:
            self = .maintenance(try container.decode(String.self, forKey: .maintenance))
        }
    }
}
