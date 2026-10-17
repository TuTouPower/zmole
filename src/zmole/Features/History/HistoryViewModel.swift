import Combine
import Foundation

struct HistorySnapshotLoader: Sendable {
    typealias RunCommand = @Sendable ([String]) async throws -> MoleCommandResult

    private let runCommand: RunCommand

    init(bridge: MoleBridge) {
        runCommand = { arguments in
            try await bridge.run(arguments)
        }
    }

    init(runCommand: @escaping RunCommand) {
        self.runCommand = runCommand
    }

    func load(limit: Int = 20) async throws -> HistorySnapshot {
        let raw = try await loadRaw(limit: limit)
        return try Self.decode(raw)
    }

    static func decode(_ raw: String) throws -> HistorySnapshot {
        guard let data = raw.data(using: .utf8) else {
            throw HistorySnapshotError.invalidJSON
        }
        do {
            return try JSONDecoder().decode(HistorySnapshot.self, from: data)
        } catch let error as HistorySnapshotError {
            throw error
        } catch {
            throw HistorySnapshotError.invalidJSON
        }
    }

    /// Returns the exact `history --json` payload, used by the export action.
    func loadRaw(limit: Int = 20) async throws -> String {
        let boundedLimit = min(max(limit, 1), 200)
        let result = try await runCommand(
            ["history", "--json", "--limit", String(boundedLimit)]
        )
        guard result.exitCode == 0 else {
            throw MoleBridgeError.commandFailed(result)
        }
        return result.stdout
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var snapshot: HistorySnapshot?
    @Published private(set) var rawJSON: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var showBusyNotice = false

    private let loader: HistorySnapshotLoader?
    private let limit: Int

    init(loader: HistorySnapshotLoader, limit: Int = 20) {
        self.loader = loader
        self.limit = limit
    }

    init(limit: Int = 20) {
        self.limit = limit
        loader = (try? MoleBridge()).map { HistorySnapshotLoader(bridge: $0) }
    }

    func refresh() async {
        let previousSnapshot = snapshot
        let previousRaw = rawJSON
        snapshot = nil
        rawJSON = nil
        errorMessage = nil
        errorMessageKey = nil
        showBusyNotice = false
        isLoading = true
        defer { isLoading = false }

        guard let loader else {
            errorMessageKey = "mole.error.executable_not_found"
            return
        }

        do {
            let raw = try await loader.loadRaw(limit: limit)
            snapshot = try HistorySnapshotLoader.decode(raw)
            rawJSON = raw
        } catch {
            if CommandBusy.isBusy(error) {
                snapshot = previousSnapshot
                rawJSON = previousRaw
                showBusyNotice = true
                return
            }
            rawJSON = nil
            errorMessageKey = error.localizationKey
            errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
        }
    }

    /// Writes the exact JSON from the latest refresh to the chosen file.
    @discardableResult
    func export(to url: URL) -> Bool {
        guard let rawJSON else { return false }
        do {
            try rawJSON.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            errorMessageKey = nil
            errorMessage = error.localizedDescription
            return false
        }
    }
}
