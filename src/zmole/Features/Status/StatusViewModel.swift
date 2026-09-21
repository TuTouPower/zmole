import Foundation
import Combine

struct StatusSnapshotLoader: Sendable {
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

    func load() async throws -> StatusSnapshot {
        let result = try await runCommand(["status", "--json"])
        guard result.exitCode == 0 else {
            throw MoleBridgeError.commandFailed(result)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw StatusSnapshotError.invalidJSON
        }

        do {
            return try JSONDecoder().decode(StatusSnapshot.self, from: data)
        } catch let error as StatusSnapshotError {
            throw error
        } catch {
            throw StatusSnapshotError.invalidJSON
        }
    }
}

@MainActor
final class StatusViewModel: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let loader: StatusSnapshotLoader?
    private let initializationError: String?

    init(loader: StatusSnapshotLoader) {
        self.loader = loader
        initializationError = nil
    }

    init() {
        if let bridge = try? MoleBridge() {
            loader = StatusSnapshotLoader(bridge: bridge)
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
            snapshot = try await loader.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
