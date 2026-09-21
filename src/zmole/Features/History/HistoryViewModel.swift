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
        let boundedLimit = min(max(limit, 1), 200)
        let result = try await runCommand(
            ["history", "--json", "--limit", String(boundedLimit)]
        )
        guard result.exitCode == 0 else {
            throw MoleBridgeError.commandFailed(result)
        }

        guard let data = result.stdout.data(using: .utf8) else {
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
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var snapshot: HistorySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let loader: HistorySnapshotLoader?
    private let limit: Int
    private let initializationError: String?

    init(loader: HistorySnapshotLoader, limit: Int = 20) {
        self.loader = loader
        self.limit = limit
        initializationError = nil
    }

    init(limit: Int = 20) {
        self.limit = limit
        if let bridge = try? MoleBridge() {
            loader = HistorySnapshotLoader(bridge: bridge)
            initializationError = nil
        } else {
            loader = nil
            initializationError = "找不到捆绑 mole"
        }
    }

    func refresh() async {
        snapshot = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let loader else {
            errorMessage = initializationError
            return
        }

        do {
            snapshot = try await loader.load(limit: limit)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
