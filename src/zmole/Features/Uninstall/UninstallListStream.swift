import Foundation

/// One progressively-refined application row from the streaming list scan.
/// Later rows for the same path supersede earlier ones; nil metadata means the
/// scan has not resolved it yet (shown as computing, never as zero).
struct UninstallAppListing: Equatable, Codable, Identifiable, Sendable {
    let path: String
    var name: String
    var bundleID: String?
    var uninstallName: String?
    var source: String?
    var sizeText: String? {
        didSet {
            sizeBytes = HumanSizeParser.bytes(from: sizeText)
        }
    }
    /// Stored normalized byte count; computed once upon creation or update (t055)
    private(set) var sizeBytes: Int64?
    var version: String?
    var lastUsed: Date?

    var id: String { path }

    init(
        path: String,
        name: String,
        bundleID: String? = nil,
        uninstallName: String? = nil,
        source: String? = nil,
        sizeText: String? = nil,
        version: String? = nil,
        lastUsed: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.bundleID = bundleID
        self.uninstallName = uninstallName
        self.source = source
        self.sizeText = sizeText
        self.sizeBytes = HumanSizeParser.bytes(from: sizeText)
        self.version = version
        self.lastUsed = lastUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        uninstallName = try container.decodeIfPresent(String.self, forKey: .uninstallName)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        sizeText = try container.decodeIfPresent(String.self, forKey: .sizeText)
        sizeBytes = HumanSizeParser.bytes(from: sizeText)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
    }

    enum CodingKeys: String, CodingKey {
        case path, name, bundleID, uninstallName, source, sizeText, version, lastUsed
    }

    /// Both identity fields resolved; only then can the row be previewed.
    var isResolved: Bool { bundleID != nil && uninstallName != nil }

    var uninstallApp: UninstallApp? {
        guard let bundleID, let uninstallName else { return nil }
        return UninstallApp(
            name: name,
            bundleID: bundleID,
            uninstallName: uninstallName,
            path: path,
            source: source,
            size: sizeText,
            version: version,
            lastUsed: lastUsed
        )
    }
}

enum UninstallListStreamError: Error, Equatable, LocalizedError, Sendable {
    /// Every JSON-looking row failed to decode; surface an error instead of a
    /// false "no apps" list when the CLI output format drifts.
    case malformedRows(skipped: Int)

    var errorDescription: String? {
        switch self {
        case let .malformedRows(skipped):
            return "mole 卸载列表输出无法解析（跳过 \(skipped) 行）"
        }
    }
}

private struct RawListingRow: Decodable {
    let event: String?
    let path: String?
    let name: String?
    let bundleID: String?
    let uninstallName: String?
    let source: String?
    let size: SizeField?
    let version: String?
    let lastUsedEpoch: Double?

    /// `size` may arrive as a string ("12.3MB") or a raw number.
    struct SizeField: Decodable {
        let text: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                text = value
            } else if let value = try? container.decode(Int64.self) {
                text = String(value)
            } else if let value = try? container.decode(Double.self) {
                text = String(value)
            } else {
                text = nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case event
        case path
        case name
        case bundleID = "bundle_id"
        case uninstallName = "uninstall_name"
        case source
        case size
        case version
        case lastUsedEpoch = "last_used_epoch"
    }
}

enum UninstallListStreamParser {
    /// Three-way parse outcome so the stream layer can tell benign markers
    /// from malformed JSON rows (which it counts and may surface as an error).
    enum Outcome: Equatable {
        case listing(UninstallAppListing)
        case marker
        case malformed
    }

    static func outcome(from line: String) -> Outcome {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .marker }
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let row = try? JSONDecoder().decode(RawListingRow.self, from: data) else {
            return .malformed
        }
        if row.event != nil { return .marker }
        guard let path = row.path, !path.isEmpty else { return .malformed }

        let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSize = row.size?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeText = rawSize.flatMap { HumanSizeParser.bytes(from: $0) != nil ? $0 : nil }
        let version = row.version?.trimmingCharacters(in: .whitespacesAndNewlines)
        var lastUsed: Date?
        if let epoch = row.lastUsedEpoch, epoch > 0 {
            lastUsed = Date(timeIntervalSince1970: epoch)
        }

        return .listing(UninstallAppListing(
            path: path,
            name: (name?.isEmpty == false) ? name! : URL(fileURLWithPath: path).lastPathComponent,
            bundleID: nonEmpty(row.bundleID),
            uninstallName: nonEmpty(row.uninstallName),
            source: nonEmpty(row.source),
            sizeText: sizeText,
            version: nonEmpty(version),
            lastUsed: lastUsed
        ))
    }

    /// Parses one JSON-lines row. Returns nil for stream markers and malformed
    /// lines, which the caller skips.
    static func listing(from line: String) -> UninstallAppListing? {
        guard case let .listing(listing) = outcome(from: line) else { return nil }
        return listing
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Later rows for the same path supersede earlier ones; first-seen order is
/// kept. Shared by the page ViewModel and the background scan service.
enum UninstallListMerge {
    static func merge(
        _ row: UninstallAppListing,
        into rows: inout [UninstallAppListing],
        indexByPath: inout [String: Int]
    ) {
        if let index = indexByPath[row.path] {
            rows[index] = row
        } else {
            indexByPath[row.path] = rows.count
            rows.append(row)
        }
    }
}

/// Streams `uninstall --list-stream` rows. Tests inject scripted streams; the
/// production initializer wraps a bundled-command lane.
struct UninstallListStream: Sendable {
    typealias Open = @Sendable () async -> AsyncThrowingStream<UninstallAppListing, Error>
    typealias Cancel = @Sendable () async -> Void

    private let open: Open
    private let cancelRunning: Cancel

    init(open: @escaping Open, cancel: @escaping Cancel) {
        self.open = open
        cancelRunning = cancel
    }

    init(streaming: any MoleStreaming, timeout: TimeInterval = 600) {
        open = {
            let events = await streaming.stream(
                ["uninstall", "--list-stream"],
                stdin: nil,
                timeout: timeout
            )
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var parsedCount = 0
                    var skippedCount = 0
                    do {
                        for try await event in events {
                            guard case let .stdoutLine(data) = event else { continue }
                            guard let line = String(data: data, encoding: .utf8) else {
                                skippedCount += 1
                                continue
                            }
                            switch UninstallListStreamParser.outcome(from: line) {
                            case let .listing(listing):
                                parsedCount += 1
                                continuation.yield(listing)
                            case .marker:
                                continue
                            case .malformed:
                                skippedCount += 1
                            }
                        }
                        if parsedCount == 0, skippedCount > 0 {
                            continuation.finish(throwing: UninstallListStreamError.malformedRows(skipped: skippedCount))
                        } else {
                            continuation.finish()
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        cancelRunning = { await streaming.cancel() }
    }

    func rows() async -> AsyncThrowingStream<UninstallAppListing, Error> {
        await open()
    }

    func cancel() async {
        await cancelRunning()
    }
}
