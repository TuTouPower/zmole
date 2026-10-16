import Foundation

/// One progressively-refined application row from the streaming list scan.
/// Later rows for the same path supersede earlier ones; nil metadata means the
/// scan has not resolved it yet (shown as computing, never as zero).
struct UninstallAppListing: Equatable, Identifiable, Sendable {
    let path: String
    var name: String
    var bundleID: String?
    var uninstallName: String?
    var source: String?
    var sizeText: String?
    var version: String?
    var lastUsed: Date?

    var id: String { path }

    var sizeBytes: Int64? { UninstallSizeParser.bytes(from: sizeText) }

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

enum UninstallListStreamParser {
    /// Parses one JSON-lines row. Returns nil for stream markers and malformed
    /// lines, which the caller skips.
    static func listing(from line: String) -> UninstallAppListing? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if object["event"] != nil { return nil }
        guard let path = object["path"] as? String, !path.isEmpty else { return nil }

        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSize = (object["size"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeText = rawSize.flatMap { UninstallSizeParser.bytes(from: $0) != nil ? $0 : nil }
        let version = (object["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var lastUsed: Date?
        if let epoch = object["last_used_epoch"] as? NSNumber, epoch.doubleValue > 0 {
            lastUsed = Date(timeIntervalSince1970: epoch.doubleValue)
        }

        return UninstallAppListing(
            path: path,
            name: (name?.isEmpty == false) ? name! : URL(fileURLWithPath: path).lastPathComponent,
            bundleID: nonEmpty(object["bundle_id"] as? String),
            uninstallName: nonEmpty(object["uninstall_name"] as? String),
            source: nonEmpty(object["source"] as? String),
            sizeText: sizeText,
            version: nonEmpty(version),
            lastUsed: lastUsed
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Later rows for the same path supersede earlier ones; first-seen order is
/// kept. Shared by the page ViewModel and the prewarm service.
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
                    do {
                        for try await event in events {
                            guard case let .stdoutLine(data) = event,
                                  let line = String(data: data, encoding: .utf8),
                                  let listing = UninstallListStreamParser.listing(from: line) else {
                                continue
                            }
                            continuation.yield(listing)
                        }
                        continuation.finish()
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
