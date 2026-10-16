import Foundation

struct InstallerCandidate: Equatable, Sendable, Identifiable {
    let path: String
    let sizeBytes: Int64
    let source: String
    let identity: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var type: String { URL(fileURLWithPath: path).pathExtension.uppercased() }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }

    enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size_bytes"
        case source
        case identity
    }
}

extension InstallerCandidate: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        source = try container.decode(String.self, forKey: .source)
        identity = try container.decode(String.self, forKey: .identity)
    }
}

struct InstallerRemovalFailure: Equatable, Sendable, Identifiable {
    let path: String
    let reason: String
    var id: String { path }
}

enum InstallerRemovalResult: Equatable, Sendable {
    case removed
    case failed(String)
}

/// Wraps the bundled installer non-interactive interface (t022). The page never
/// calls the full-screen menu: listing and removal both go through these argv.
struct InstallerInterface: Sendable {
    typealias Run = @Sendable ([String]) async throws -> MoleCommandResult

    private let run: Run

    init(run: @escaping Run) {
        self.run = run
    }

    init(process: any MoleProcessControlling, timeout: TimeInterval = 120) {
        run = { arguments in
            try await process.run(arguments, stdin: nil, timeout: timeout)
        }
    }

    func list() async throws -> [InstallerCandidate] {
        let result = try await run(["installer", "--list-json"])
        guard result.exitCode == 0 else {
            throw InstallerInterfaceError.commandFailed(result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw InstallerInterfaceError.invalidJSON
        }
        do {
            return try JSONDecoder().decode([InstallerCandidate].self, from: data)
        } catch {
            throw InstallerInterfaceError.invalidJSON
        }
    }

    func remove(_ candidate: InstallerCandidate) async -> InstallerRemovalResult {
        let arguments = [
            "installer", "--remove", candidate.path,
            "--size", String(candidate.sizeBytes),
            "--identity", candidate.identity
        ]
        do {
            let result = try await run(arguments)
            if result.exitCode == 0 {
                return .removed
            }
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(reason.isEmpty ? "refused" : reason)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

enum InstallerInterfaceError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON: "installer 列表 JSON 无法解析"
        case let .commandFailed(message): message.isEmpty ? "installer 命令失败" : message
        }
    }
}
