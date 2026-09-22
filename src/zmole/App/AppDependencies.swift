import Combine
import Foundation

/// Process implementation used when the bundled executable is unavailable.
/// It keeps the app launchable and lets feature views render their failure state.
private final class UnavailableMoleProcess: MoleProcessControlling, @unchecked Sendable {
    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        throw MoleBridgeError.executableNotFound("Contents/Resources/mole/mole")
    }

    func cancel() async {}
}

private struct UnavailableMoleStreaming: MoleStreaming {
    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: MoleBridgeError.executableNotFound("Contents/Resources/mole/mole"))
        }
    }
}

private final class MoleProcessBox: @unchecked Sendable {
    let process: any MoleProcessControlling

    init(_ process: any MoleProcessControlling) {
        self.process = process
    }
}

/// Deterministic command source for screenshot and UI review runs.
/// It never resolves or launches the bundled executable.
private final class DemoMoleProcess: MoleProcessControlling, @unchecked Sendable {
    private let cleanPreviewURL: URL?
    private let state: DemoState

    init(cleanPreviewURL: URL? = nil, state: DemoState = .populated) {
        self.cleanPreviewURL = cleanPreviewURL
        self.state = state
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        guard let command = arguments.first else {
            return MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        switch command {
        case "clean" where arguments.contains("--dry-run"):
            if state == .error {
                return MoleCommandResult(stdout: "", stderr: "Demo clean failed", exitCode: 7)
            }
            if let cleanPreviewURL {
                try? "~/Library/Caches/demo\n~/Library/Logs/demo\n".write(
                    to: cleanPreviewURL,
                    atomically: true,
                    encoding: .utf8
                )
            }
            return MoleCommandResult(stdout: "Demo clean preview", stderr: "", exitCode: 0)
        case "analyze":
            if state == .error {
                return MoleCommandResult(stdout: "", stderr: "Demo analyze failed", exitCode: 7)
            }
            return MoleCommandResult(stdout: state == .empty ? Self.emptyAnalyzeFixture : Self.analyzeFixture, stderr: "", exitCode: 0)
        case "status":
            return MoleCommandResult(stdout: Self.statusFixture(stale: state == .stale, includeDetails: state != .partial), stderr: "", exitCode: 0)
        case "history":
            return MoleCommandResult(stdout: Self.historyFixture, stderr: "", exitCode: 0)
        case "uninstall":
            if arguments.contains("--dry-run") {
                return MoleCommandResult(
                    stdout: Self.uninstallPreviewSummary(arguments: arguments),
                    stderr: "",
                    exitCode: 0
                )
            }
            if !arguments.contains("--list"), arguments.count > 1 {
                let names = arguments.dropFirst().filter { !$0.hasPrefix("--") }
                let summary = names.map { "Successfully uninstalled \($0)" }.joined(separator: "\n")
                return MoleCommandResult(stdout: summary, stderr: "", exitCode: 0)
            }
            return MoleCommandResult(stdout: Self.uninstallFixture, stderr: "", exitCode: 0)
        case "--version":
            return MoleCommandResult(stdout: "mole demo", stderr: "", exitCode: 0)
        default:
            return MoleCommandResult(
                stdout: "Demo preview for \(command)\nNo command was executed.",
                stderr: "",
                exitCode: 0
            )
        }
    }

    func cancel() async {}

    private static let analyzeFixture = """
    {"path":"/Users/demo","overview":true,"entries":[
      {"name":"Applications","path":"/Users/demo/Applications","size":34400550912,"is_dir":true},
      {"name":"Library","path":"/Users/demo/Library","size":18123968512,"is_dir":true},
      {"name":"Projects","path":"/Users/demo/Projects","size":12900270080,"is_dir":true},
      {"name":"Downloads with a very long name","path":"/Users/demo/Downloads with a very long name","size":5800038400,"is_dir":true},
      {"name":"Developer SDKs","path":"/Users/demo/Developer/SDKs","size":4200000000,"is_dir":true},
      {"name":"Media Archive","path":"/Users/demo/Media/Archive","size":2100000000,"is_dir":true},
      {"name":".config","path":"/Users/demo/.config","size":930000000,"is_dir":true},
      {"name":"notes.md","path":"/Users/demo/notes.md","size":18304,"is_dir":false},
      {"name":"tiny.log","path":"/Users/demo/tiny.log","size":96,"is_dir":false},
      {"name":"empty-folder","path":"/Users/demo/empty-folder","size":0,"is_dir":true}
    ]}
    """

    private static let emptyAnalyzeFixture = """
    {"path":"/Users/demo","overview":true,"entries":[]}
    """

    private static func statusFixture(stale: Bool, includeDetails: Bool) -> String {
        let details = includeDetails ? ",\"disk_io\":{\"read_rate\":12.4,\"write_rate\":3.8},\"network\":[{\"name\":\"en0\",\"rx_rate_mbs\":4.2,\"tx_rate_mbs\":1.3,\"ip\":\"192.0.2.10\"}],\"top_processes\":[{\"pid\":101,\"name\":\"Demo Editor\",\"cpu\":12.1,\"memory\":4.2,\"memory_bytes\":536870912},{\"pid\":202,\"name\":\"swift-build\",\"cpu\":8.4,\"memory\":2.1,\"memory_bytes\":268435456} ]" : ""
        return """
        {"health_score":92,"cpu":{"usage":23.5},"memory":{"used":8589934592,"total":17179869184,"used_percent":50.0},"disks":[{"mount":"/","used":300647710720,"total":994662584320,"used_percent":30.2}]\(details),"process_stale":\(stale)}
        """
    }

    private static let historyFixture = """
    {"limit":20,"sessions":[{"command":"clean","ended_at":"2026-09-22T10:20:00+08:00","items":12,"size":"3.2 GB"}],"deletions":[{"path":"/Users/demo/Library/Caches","timestamp":"2026-09-22T10:20:04+08:00","mode":"clean","status":"success","size_kb":128}]}
    """

    private static let uninstallFixture = """
    [{"name":"Demo Editor","bundle_id":"com.example.demo-editor","uninstall_name":"Demo Editor","path":"/Applications/Demo Editor.app","source":"App","size":"1.4 GB"},{"name":"Brew Tool","bundle_id":"com.example.brew-tool","uninstall_name":"Brew Tool","path":"/Applications/Brew Tool.app","source":"Homebrew","size":"820 MB"},{"name":"Photo Vault","bundle_id":"com.example.photo-vault","uninstall_name":"Photo Vault","path":"/Applications/Photo Vault.app","source":"App","size":"2.1 GB"},{"name":"Terminal Plus","bundle_id":"com.example.terminal-plus","uninstall_name":"Terminal Plus","path":"/Applications/Terminal Plus.app","source":"App","size":null},{"name":"Note Studio with a Long Name","bundle_id":"com.example.note-studio","uninstall_name":"Note Studio with a Long Name","path":"/Applications/Note Studio with a Long Name.app","source":"Homebrew","size":"640 MB"},{"name":"Render Farm","bundle_id":"com.example.render-farm","uninstall_name":"Render Farm","path":"/Applications/Render Farm.app","source":"App","size":"3.8 GB"},{"name":"Data Tools","bundle_id":"com.example.data-tools","uninstall_name":"Data Tools","path":"/Applications/Data Tools.app","source":"Homebrew","size":"120 MB"},{"name":"Legacy Client","bundle_id":"com.example.legacy-client","uninstall_name":"Legacy Client","path":"/Applications/Legacy Client.app","source":"App","size":"55 MB"}]
    """

    private static func uninstallPreviewSummary(arguments: [String]) -> String {
        let names: ArraySlice<String>
        if let dryRunIndex = arguments.firstIndex(of: "--dry-run") {
            names = arguments.dropFirst(dryRunIndex + 1)
        } else {
            names = []
        }
        let selectedNames = Set(names)
        let selected = (try? JSONDecoder().decode(
            [UninstallApp].self,
            from: Data(uninstallFixture.utf8)
        ))?.filter { selectedNames.contains($0.uninstallName) } ?? []
        let rows = selected.map { app in
            "• \(app.name) — \(app.size ?? "Size unknown")\n  \(app.path)"
        }
        return (["Files to be removed:"] + rows + ["Uninstall dry run complete"])
            .joined(separator: "\n")
    }
}

private struct DemoMoleStreaming: MoleStreaming {
    let state: DemoState

    init(state: DemoState = .populated) {
        self.state = state
    }

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let keepsRunning = state == .populated || state == .partial || state == .stale
                var sampleCount = 0
                while keepsRunning || sampleCount < 3 {
                    guard !Task.isCancelled else { return }
                    if state == .error {
                        continuation.finish(throwing: StatusWatchError.disconnected)
                        return
                    }
                    continuation.yield(.stdoutLine(Data(Self.statusFixture(stale: state == .stale, includeDetails: state != .partial).utf8)))
                    sampleCount += 1
                    try? await Task.sleep(nanoseconds: state == .busy ? 3_000_000_000 : 800_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func statusFixture(stale: Bool, includeDetails: Bool) -> String {
        let details = includeDetails ? ",\"disk_io\":{\"read_rate\":12.4,\"write_rate\":3.8},\"network\":[{\"name\":\"en0\",\"rx_rate_mbs\":4.2,\"tx_rate_mbs\":1.3,\"ip\":\"192.0.2.10\"}],\"top_processes\":[{\"pid\":101,\"name\":\"Demo Editor\",\"cpu\":12.1,\"memory\":4.2,\"memory_bytes\":536870912},{\"pid\":202,\"name\":\"swift-build\",\"cpu\":8.4,\"memory\":2.1,\"memory_bytes\":268435456} ]" : ""
        return """
        {"health_score":92,"cpu":{"usage":23.5},"memory":{"used":8589934592,"total":17179869184,"used_percent":50.0},"disks":[{"mount":"/","used":300647710720,"total":994662584320,"used_percent":30.2}]\(details),"process_stale":\(stale)}
        """
    }
}

struct DemoConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let page: AppMode
    let state: DemoState
    let dataRoot: URL?
    let language: AppLanguage?
    let appearance: DemoAppearance?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isEnabled = arguments.contains("--demo")
        page = Self.value(after: "--demo-page", in: arguments).flatMap(AppMode.init(rawValue:)) ?? .analyze
        state = Self.value(after: "--demo-state", in: arguments).flatMap(DemoState.init(rawValue:)) ?? .populated
        let root = Self.value(after: "--demo-data-root", in: arguments).map { URL(fileURLWithPath: $0, isDirectory: true) }
        dataRoot = isEnabled ? root : nil
        language = Self.value(after: "--demo-language", in: arguments).flatMap(AppLanguage.init(rawValue:))
        appearance = Self.value(after: "--demo-appearance", in: arguments).flatMap(DemoAppearance.init(rawValue:))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

enum DemoState: String, CaseIterable, Sendable {
    case populated
    case empty
    case busy
    case error
    case partial
    case stale
}

enum DemoAppearance: String, Sendable {
    case light
    case dark
}

@MainActor
final class AppDependencies: ObservableObject {
    let coordinator: OperationCoordinator
    let cleanViewModel: CleanViewModel
    let uninstallViewModel: UninstallViewModel
    let optimizeViewModel: OptimizeViewModel
    let purgeViewModel: PurgeViewModel
    let whitelistViewModel: WhitelistViewModel
    let analyzeViewModel: AnalyzeViewModel
    let statusViewModel: StatusViewModel
    let historyViewModel: HistoryViewModel
    let demoDataRoot: URL?
    let demoCleanPreviewURL: URL?

    let demo: DemoConfiguration

    init(configuration: DemoConfiguration = DemoConfiguration()) {
        demo = configuration
        let process: any MoleProcessControlling
        let streaming: any MoleStreaming
        let demoDirectory = configuration.dataRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole-demo-\(UUID().uuidString)", isDirectory: true)
        let demoCleanPreviewURL = configuration.isEnabled
            ? demoDirectory.appendingPathComponent("clean-list.txt")
            : nil
        demoDataRoot = configuration.isEnabled ? demoDirectory : nil
        self.demoCleanPreviewURL = demoCleanPreviewURL
        if configuration.isEnabled {
            try? FileManager.default.createDirectory(
                at: demoDirectory,
                withIntermediateDirectories: true
            )
        }
        let cleanPreviewURL = demoCleanPreviewURL ?? demoDirectory.appendingPathComponent("clean-list.txt")
        if configuration.isEnabled {
            process = DemoMoleProcess(cleanPreviewURL: cleanPreviewURL, state: configuration.state)
            streaming = DemoMoleStreaming(state: configuration.state)
        } else if let bridge = try? MoleBridge() {
            process = bridge
            streaming = bridge
        } else {
            process = UnavailableMoleProcess()
            streaming = UnavailableMoleStreaming()
        }

        coordinator = OperationCoordinator()
        let processBox = MoleProcessBox(process)
        let previewStore: CleanPreviewStore
        if configuration.isEnabled {
            previewStore = CleanPreviewStore(
                fileURL: cleanPreviewURL
            )
        } else {
            previewStore = .live
        }
        cleanViewModel = CleanViewModel(
            process: process,
            previewStore: previewStore,
            coordinator: coordinator
        )
        uninstallViewModel = UninstallViewModel(process: process, coordinator: coordinator)
        optimizeViewModel = OptimizeViewModel(process: process, coordinator: coordinator)
        purgeViewModel = PurgeViewModel(process: process, coordinator: coordinator)
        let whitelistURL = configuration.isEnabled
            ? demoDirectory.appendingPathComponent("whitelist")
            : WhitelistStore.live.fileURL
        whitelistViewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: whitelistURL),
            coordinator: coordinator
        )

        let loader = AnalyzeSnapshotLoader { arguments in
            try await processBox.process.run(arguments, stdin: nil, timeout: 120)
        }
        analyzeViewModel = AnalyzeViewModel(loader: loader)

        let statusLoader = StatusSnapshotLoader { arguments in
            try await processBox.process.run(arguments, stdin: nil, timeout: 120)
        }
        statusViewModel = StatusViewModel(streaming: streaming, loader: statusLoader)

        let historyLoader = HistorySnapshotLoader { arguments in
            try await processBox.process.run(arguments, stdin: nil, timeout: 120)
        }
        historyViewModel = HistoryViewModel(loader: historyLoader)
    }
}
