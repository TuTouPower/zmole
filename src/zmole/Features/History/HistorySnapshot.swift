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
