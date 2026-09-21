import Combine
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

@MainActor
final class AnalyzeViewModel: ObservableObject {
    @Published private(set) var snapshot: AnalyzeSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var canGoBack = false

    private let loader: AnalyzeSnapshotLoader?
    private let initializationError: String?
    private var pathStack: [String?] = [nil]

    init(loader: AnalyzeSnapshotLoader) {
        self.loader = loader
        initializationError = nil
    }

    init() {
        if let bridge = try? MoleBridge() {
            loader = AnalyzeSnapshotLoader(bridge: bridge)
            initializationError = nil
        } else {
            loader = nil
            initializationError = "找不到捆绑 mole"
        }
    }

    func loadOverview() async {
        guard !isLoading else { return }
        pathStack = [nil]
        await loadCurrentPath()
    }

    func openDirectory(_ entry: AnalyzeEntry) async {
        guard entry.isDirectory, !isLoading else { return }
        pathStack.append(entry.path)
        await loadCurrentPath()
    }

    func goBack() async {
        guard pathStack.count > 1, !isLoading else { return }
        pathStack.removeLast()
        await loadCurrentPath()
    }

    private func loadCurrentPath() async {
        snapshot = nil
        errorMessage = nil
        isLoading = true
        canGoBack = pathStack.count > 1
        defer { isLoading = false }

        guard let loader else {
            errorMessage = initializationError
            return
        }

        do {
            snapshot = try await loader.load(path: pathStack.last ?? nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
