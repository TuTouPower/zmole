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
    @Published private(set) var expandedPaths: Set<String> = []
    @Published private(set) var showBusyNotice = false
    @Published private(set) var childrenByPath: [String: [AnalyzeEntry]] = [:]

    private let loader: AnalyzeSnapshotLoader?
    private let initializationError: String?
    private let revealer: FileRevealing
    private var pathStack: [String?] = [nil]

    init(loader: AnalyzeSnapshotLoader, revealer: FileRevealing = LiveFileRevealer()) {
        self.loader = loader
        self.revealer = revealer
        initializationError = nil
    }

    init() {
        revealer = LiveFileRevealer()
        if let bridge = try? MoleBridge() {
            loader = AnalyzeSnapshotLoader(bridge: bridge)
            initializationError = nil
        } else {
            loader = nil
            initializationError = "找不到捆绑 mole"
        }
    }

    var currentPath: String? { snapshot?.path }

    func loadOverview() async {
        guard !isLoading else { return }
        pathStack = [nil]
        await loadCurrentPath()
    }

    /// Reloads the current directory in place (re-analyze the current root).
    func refreshCurrent() async {
        guard !isLoading else { return }
        expandedPaths.removeAll()
        childrenByPath.removeAll()
        await loadCurrentPath()
    }

    func openDirectory(_ entry: AnalyzeEntry) async {
        guard entry.isDirectory, !isLoading else { return }
        pathStack.append(entry.path)
        expandedPaths.removeAll()
        childrenByPath.removeAll()
        await loadCurrentPath()
    }

    /// Breadcrumb jump back to an ancestor path already on the stack.
    func open(path: String) async {
        guard !isLoading else { return }
        if path == "/" {
            await loadOverview()
            return
        }
        guard let index = pathStack.firstIndex(where: { $0 == path }) else { return }
        pathStack.removeSubrange((index + 1)..<pathStack.count)
        expandedPaths.removeAll()
        childrenByPath.removeAll()
        await loadCurrentPath()
    }

    func goBack() async {
        guard pathStack.count > 1, !isLoading else { return }
        pathStack.removeLast()
        expandedPaths.removeAll()
        childrenByPath.removeAll()
        await loadCurrentPath()
    }

    func isExpanded(_ entry: AnalyzeEntry) -> Bool {
        expandedPaths.contains(entry.path)
    }

    func children(of entry: AnalyzeEntry) -> [AnalyzeEntry]? {
        childrenByPath[entry.path]
    }

    func toggleExpanded(_ entry: AnalyzeEntry) async {
        guard entry.isDirectory else { return }
        if expandedPaths.contains(entry.path) {
            expandedPaths.remove(entry.path)
            return
        }
        guard !isLoading else { return }
        expandedPaths.insert(entry.path)
        guard childrenByPath[entry.path] == nil, let loader else { return }
        if let child = try? await loader.load(path: entry.path) {
            childrenByPath[entry.path] = child.entries
        } else {
            childrenByPath[entry.path] = []
        }
    }

    func revealInFinder(_ entry: AnalyzeEntry) {
        Task { await revealer.reveal(path: entry.path) }
    }

    private func loadCurrentPath() async {
        let previous = snapshot
        snapshot = nil
        errorMessage = nil
        showBusyNotice = false
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
            if CommandBusy.isBusy(error) {
                snapshot = previous
                showBusyNotice = true
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

enum AnalyzeSort: String, CaseIterable, Identifiable, Sendable {
    case size
    case name

    var id: Self { self }
}

enum AnalyzeListOrder {
    static func sorted(_ entries: [AnalyzeEntry], by sort: AnalyzeSort) -> [AnalyzeEntry] {
        switch sort {
        case .size:
            return entries.sorted { $0.size == $1.size ? $0.name < $1.name : $0.size > $1.size }
        case .name:
            return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

enum AnalyzeArea {
    /// Share of one entry within the current layer total. Nil when the layer
    /// total is zero.
    static func share(of size: Int64, total: Int64) -> Double? {
        guard total > 0 else { return nil }
        return Double(max(0, size)) / Double(total)
    }
}
