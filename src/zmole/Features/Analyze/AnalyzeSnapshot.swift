import Foundation

struct AnalyzeSnapshotLoader: Sendable {
    typealias RunCommand = @Sendable ([String]) async throws -> MoleCommandResult

    private let runCommand: RunCommand

    init(bridge: MoleBridge, timeout: TimeInterval = 120) {
        runCommand = { arguments in
            try await bridge.run(arguments, timeout: timeout)
        }
    }

    init(runCommand: @escaping RunCommand) {
        self.runCommand = runCommand
    }

    func load(path: String? = nil) async throws -> AnalyzeSnapshot {
        var arguments = ["analyze", "--json"]
        if let path {
            arguments.append(path)
        }

        let result = try await runCommand(arguments)
        guard result.exitCode == 0 else {
            throw MoleBridgeError.commandFailed(result)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw AnalyzeSnapshotError.invalidJSON
        }

        do {
            return try JSONDecoder().decode(AnalyzeSnapshot.self, from: data)
        } catch {
            throw AnalyzeSnapshotError.invalidJSON
        }
    }
}

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
