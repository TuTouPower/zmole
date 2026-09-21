import Foundation

struct AnalyzeSnapshot: Decodable, Equatable, Sendable {
    let path: String
    let overview: Bool
    let entries: [AnalyzeEntry]

    var displayState: AnalyzeDisplayState {
        AnalyzeDisplayState(path: path, overview: overview, entries: entries)
    }

    enum CodingKeys: String, CodingKey {
        case path
        case overview
        case entries
    }
}

struct AnalyzeDisplayState: Equatable, Sendable {
    let path: String
    let overview: Bool
    let entries: [AnalyzeEntry]
}

struct AnalyzeEntry: Decodable, Equatable, Identifiable, Sendable {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case size
        case isDirectory = "is_dir"
    }
}

enum AnalyzeSnapshotError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON

    var errorDescription: String? {
        "analyze JSON 无法解析"
    }
}
