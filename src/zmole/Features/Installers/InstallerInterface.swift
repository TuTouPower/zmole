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
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        identity = try container.decodeIfPresent(String.self, forKey: .identity) ?? ""
    }
}

/// Decodes one row leniently so a single malformed element is skipped instead
/// of failing the whole listing.
private struct LenientCandidate: Decodable {
    let value: InstallerCandidate?

    init(from decoder: Decoder) throws {
        value = try? InstallerCandidate(from: decoder)
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
    /// Transient lane contention; the caller should stop the batch, keep the
    /// selection, and offer a retry.
    case busy
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
            throw InstallerInterfaceError.commandFailed(Self.failureDetail(from: result))
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw InstallerInterfaceError.invalidJSON
        }
        guard let rows = try? JSONDecoder().decode([LenientCandidate].self, from: data) else {
            throw InstallerInterfaceError.invalidJSON
        }
        let candidates = rows.compactMap(\.value)
        if candidates.isEmpty, !rows.isEmpty {
            throw InstallerInterfaceError.invalidJSON
        }
        return candidates
    }

    func remove(_ candidate: InstallerCandidate) async -> InstallerRemovalResult {
        guard candidate.path.hasPrefix("/"),
              candidate.sizeBytes > 0,
              !candidate.identity.isEmpty else {
            return .failed("refused")
        }
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
            let reason = Self.failureDetail(from: result)
            return .failed(reason.isEmpty ? "refused" : reason)
        } catch {
            if CommandBusy.isBusy(error) {
                return .busy
            }
            return .failed(error.localizedDescription)
        }
    }

    private static func failureDetail(from result: MoleCommandResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum InstallerInterfaceError: Error, Equatable, LocalizedError, Sendable, ErrorKeyProviding {
    case invalidJSON
    case commandFailed(String)

    var errorKey: String {
        switch self {
        case .invalidJSON:
            return "installers.error.invalid_json"
        case .commandFailed:
            return "installers.error.command_failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidJSON: "installer 列表 JSON 无法解析"
        case let .commandFailed(message): message.isEmpty ? "installer 命令失败" : message
        }
    }
}
