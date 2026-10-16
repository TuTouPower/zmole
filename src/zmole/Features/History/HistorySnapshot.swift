import Foundation

struct HistorySnapshot: Decodable, Equatable, Sendable {
    let limit: Int
    let sessions: [HistorySession]
    let deletions: [HistoryDeletion]

    enum CodingKeys: String, CodingKey {
        case limit
        case sessions
        case deletions
    }

    var displayState: HistoryDisplayState {
        if sessions.isEmpty && deletions.isEmpty {
            return .empty
        }
        return .content(
            sessions: sessions.map(HistorySessionDisplay.init),
            deletions: deletions.map(HistoryDeletionDisplay.init)
        )
    }
}

enum HistoryDisplayState: Equatable, Sendable {
    case empty
    case content(sessions: [HistorySessionDisplay], deletions: [HistoryDeletionDisplay])
}

/// One row of the aligned history table (demo `.history-row` semantics).
struct HistoryTableRow: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case session
        case deletion
    }

    /// Status text resolves in the view's locale: sessions always report
    /// completion, deletions carry the raw command status.
    enum Status: Equatable, Sendable {
        case done
        case verbatim(String)
    }

    let id: String
    let kind: Kind
    let date: String
    let action: String
    let result: String
    let status: Status
    /// Deletion rows keep the full path for the hover tooltip.
    let fullPath: String?
}

enum HistoryTable {
    /// Sessions first, then deletions; both kinds share the four columns
    /// 日期 / 操作 / 结果 / 状态.
    static func rows(from state: HistoryDisplayState) -> [HistoryTableRow] {
        switch state {
        case .empty:
            return []
        case let .content(sessions, deletions):
            let sessionRows = sessions.enumerated().map { index, session in
                HistoryTableRow(
                    id: "session-\(index)",
                    kind: .session,
                    date: session.dateText.isEmpty ? "—" : session.dateText,
                    action: session.command,
                    result: resultText(items: session.items, size: session.size),
                    status: .done,
                    fullPath: nil
                )
            }
            let deletionRows = deletions.enumerated().map { index, deletion in
                HistoryTableRow(
                    id: "deletion-\(index)",
                    kind: .deletion,
                    date: deletion.timestamp.isEmpty ? "—" : deletion.timestamp,
                    action: deletion.path,
                    result: deletion.sizeKB.map {
                        ByteCountFormatter.string(fromByteCount: $0 * 1024, countStyle: .file)
                    } ?? "—",
                    status: .verbatim(deletion.status),
                    fullPath: deletion.path
                )
            }
            return sessionRows + deletionRows
        }
    }

    private static func resultText(items: Int?, size: String?) -> String {
        var parts: [String] = []
        if let items {
            parts.append("\(items)")
        }
        if let size, !size.isEmpty {
            parts.append(size)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

struct HistorySessionDisplay: Equatable, Sendable {
    let command: String
    let dateText: String
    let items: Int?
    let size: String?

    init(session: HistorySession) {
        command = session.command
        dateText = session.dateText ?? ""
        items = session.items
        size = session.size
    }
}

struct HistoryDeletionDisplay: Equatable, Sendable {
    let timestamp: String
    let mode: String
    let status: String
    let sizeKB: Int64?
    let path: String

    init(deletion: HistoryDeletion) {
        timestamp = deletion.timestamp
        mode = deletion.mode
        status = deletion.status
        sizeKB = deletion.sizeKB
        path = deletion.path
    }
}

struct HistorySession: Decodable, Equatable, Sendable {
    let command: String
    let startedAt: String?
    let endedAt: String?
    let items: Int?
    let size: String?

    var dateText: String? {
        nonEmpty(endedAt) ?? nonEmpty(startedAt)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    enum CodingKeys: String, CodingKey {
        case command
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case items
        case size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        items = try container.decodeIfPresent(Int.self, forKey: .items)
        size = try container.decodeIfPresent(String.self, forKey: .size)

        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              dateText != nil,
              items != nil || size != nil else {
            throw HistorySnapshotError.invalidSession
        }
    }
}

struct HistoryDeletion: Decodable, Equatable, Sendable {
    let timestamp: String
    let mode: String
    let status: String
    let sizeKB: Int64?
    let path: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case mode
        case status
        case sizeKB = "size_kb"
        case path
    }
}

enum HistorySnapshotError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON
    case invalidSession

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "history JSON 无法解析"
        case .invalidSession:
            return "history JSON 缺少会话摘要字段"
        }
    }
}
