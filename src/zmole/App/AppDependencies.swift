import Combine
import Foundation

/// Process implementation used when the bundled executable is unavailable.
/// It keeps the app launchable and lets feature views render their failure state.
final class UnavailableMoleProcess: MoleProcessControlling, @unchecked Sendable {
    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        throw MoleBridgeError.executableNotFound("Contents/Resources/mole/mole")
    }

    func cancel() async {}
}

struct UnavailableMoleStreaming: MoleStreaming {
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
            if state == .empty {
                return MoleCommandResult(stdout: Self.emptyAnalyzeFixture, stderr: "", exitCode: 0)
            }
            let path = arguments.last.flatMap { $0.hasPrefix("/") || $0.hasPrefix("~") ? $0 : nil }
            return MoleCommandResult(stdout: Self.analyzeFixture(path: path), stderr: "", exitCode: 0)
        case "status":
            return MoleCommandResult(stdout: Self.statusFixture(stale: state == .stale, includeDetails: state != .partial), stderr: "", exitCode: 0)
        case "history":
            return MoleCommandResult(stdout: Self.historyFixture, stderr: "", exitCode: 0)
        case "installer":
            if arguments.contains("--list-json") {
                return MoleCommandResult(stdout: Self.installerListFixture, stderr: "", exitCode: 0)
            }
            if arguments.contains("--remove") {
                return MoleCommandResult(stdout: "Moved to Trash", stderr: "", exitCode: 0)
            }
            return MoleCommandResult(stdout: "[]", stderr: "", exitCode: 0)
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

    private static func analyzeFixture(path: String?) -> String {
        guard let path else { return defaultAnalyzeFixture }
        if path.hasSuffix("/Library/Developer") { return developerAnalyzeFixture }
        switch path {
        case "/Applications": return applicationsAnalyzeFixture
        case "/System": return systemAnalyzeFixture
        case "/Users": return usersAnalyzeFixture
        default: return defaultAnalyzeFixture
        }
    }

    private static let defaultAnalyzeFixture = """
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

    private static let applicationsAnalyzeFixture = """
    {"path":"/Applications","overview":false,"entries":[
      {"name":"Xcode.app","path":"/Applications/Xcode.app","size":22000000000,"is_dir":true},
      {"name":"Docker.app","path":"/Applications/Docker.app","size":12000000000,"is_dir":true},
      {"name":"Other","path":"/Applications/Other","size":6000000000,"is_dir":true}
    ]}
    """

    private static let systemAnalyzeFixture = """
    {"path":"/System","overview":false,"entries":[
      {"name":"Library","path":"/System/Library","size":18000000000,"is_dir":true},
      {"name":"Frameworks","path":"/System/Library/Frameworks","size":7000000000,"is_dir":true}
    ]}
    """

    private static let developerAnalyzeFixture = """
    {"path":"~/Library/Developer","overview":false,"entries":[
      {"name":"Xcode","path":"~/Library/Developer/Xcode","size":24000000000,"is_dir":true},
      {"name":"CoreSimulator","path":"~/Library/Developer/CoreSimulator","size":6000000000,"is_dir":true}
    ]}
    """

    private static let usersAnalyzeFixture = """
    {"path":"/Users","overview":false,"entries":[
      {"name":"demo","path":"/Users/demo","size":90000000000,"is_dir":true}
    ]}
    """

    private static let emptyAnalyzeFixture = """
    {"path":"/Users/demo","overview":true,"entries":[]}
    """

    private static func statusFixture(stale: Bool, includeDetails: Bool) -> String {
        let details = includeDetails ? ",\"disk_io\":{\"read_rate\":12.4,\"write_rate\":3.8},\"network\":[{\"name\":\"en0\",\"rx_rate_mbs\":4.2,\"tx_rate_mbs\":1.3,\"ip\":\"192.0.2.10\"}],\"top_processes\":[{\"pid\":101,\"name\":\"Demo Editor\",\"cpu\":12.1,\"memory\":4.2,\"memory_bytes\":536870912},{\"pid\":202,\"name\":\"swift-build\",\"cpu\":8.4,\"memory\":2.1,\"memory_bytes\":268435456} ],\"thermal\":{\"cpu_temp\":48},\"zombie_count\":0" : ""
        return """
        {"health_score":92,"cpu":{"usage":23.5},"memory":{"used":8589934592,"total":17179869184,"used_percent":50.0},"disks":[{"mount":"/","used":300647710720,"total":994662584320,"used_percent":30.2}]\(details),"process_stale":\(stale)}
        """
    }

    private static let historyFixture = """
    {"limit":20,"sessions":[{"command":"clean","ended_at":"2026-09-22T10:20:00+08:00","items":12,"size":"3.2 GB"}],"deletions":[{"path":"/Users/demo/Library/Caches","timestamp":"2026-09-22T10:20:04+08:00","mode":"clean","status":"success","size_kb":128}]}
    """

    private static let installerListFixture = """
    [{"path":"/Users/demo/Downloads/Android Studio.dmg","size_bytes":1210000000,"source":"Downloads","identity":"1:2:3"},{"path":"/Users/demo/Downloads/Figma.pkg","size_bytes":640000000,"source":"Downloads","identity":"4:5:6"},{"path":"/Users/demo/Downloads/VSCode.zip","size_bytes":310000000,"source":"Downloads","identity":"7:8:9"}]
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
        let details = includeDetails ? ",\"disk_io\":{\"read_rate\":12.4,\"write_rate\":3.8},\"network\":[{\"name\":\"en0\",\"rx_rate_mbs\":4.2,\"tx_rate_mbs\":1.3,\"ip\":\"192.0.2.10\"}],\"top_processes\":[{\"pid\":101,\"name\":\"Demo Editor\",\"cpu\":12.1,\"memory\":4.2,\"memory_bytes\":536870912},{\"pid\":202,\"name\":\"swift-build\",\"cpu\":8.4,\"memory\":2.1,\"memory_bytes\":268435456} ],\"thermal\":{\"cpu_temp\":48},\"zombie_count\":0" : ""
        return """
        {"health_score":92,"cpu":{"usage":23.5},"memory":{"used":8589934592,"total":17179869184,"used_percent":50.0},"disks":[{"mount":"/","used":300647710720,"total":994662584320,"used_percent":30.2}]\(details),"process_stale":\(stale)}
        """
    }
}

struct DemoConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let page: AppDestination
    let state: DemoState
    let dataRoot: URL?
    let language: AppLanguage?
    let appearance: DemoAppearance?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isEnabled = arguments.contains("--demo")
        page = Self.value(after: "--demo-page", in: arguments)
            .flatMap(AppDestination.init(demoValue:)) ?? .overview
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

/// Deterministic in-memory directory source for the disk page in demo mode.
/// It never reads the file system and never spawns the bundled executable.
struct DemoDiskScanner: DiskScanning {
    static let root = "/Users/demo"

    let state: DemoState

    func listDirectory(_ path: String) async throws -> [DiskEntry] {
        if state == .error {
            throw DiskScanError.unreadable(path)
        }
        if state == .empty {
            guard path == Self.root else { throw DiskScanError.unreadable(path) }
            return []
        }
        guard let level = Self.levels[path] else {
            throw DiskScanError.unreadable(path)
        }
        return level.entries.map { entry in
            var listed = entry
            if listed.isDirectory {
                listed.value = .computing
            }
            return listed
        }
    }

    func measureSubtree(_ path: String, deduplicator: HardLinkDeduplicator) async -> DiskScanResult {
        if state == .partial, path == Self.child(Self.root, "Library") {
            // Keep one subtree computing so the pending state stays visible.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard let level = Self.levels[path] else {
            return DiskScanResult(path: path, totalSize: 0, isReadable: false, levels: [:])
        }
        let prefix = LiveDiskScanner.directoryPrefix(path)
        let subtree = Self.levels.filter { $0.key == path || $0.key.hasPrefix(prefix) }
        return DiskScanResult(path: path, totalSize: level.totalSize, isReadable: true, levels: subtree)
    }

    private static func child(_ parent: String, _ name: String) -> String {
        LiveDiskScanner.childPath(parent, name)
    }

    private static func file(_ name: String, _ bytes: Int64, in parent: String) -> DiskEntry {
        DiskEntry(name: name, path: child(parent, name), isDirectory: false, value: .size(bytes))
    }

    private static func directory(_ name: String, _ bytes: Int64, in parent: String) -> DiskEntry {
        DiskEntry(name: name, path: child(parent, name), isDirectory: true, value: .size(bytes))
    }

    private static func level(_ parent: String, _ entries: [DiskEntry], total: Int64) -> (String, DiskLevel) {
        (parent, DiskLevel(entries: entries, totalSize: total))
    }

    private static let levels: [String: DiskLevel] = {
        let root = Self.root
        let applications = child(root, "Applications")
        let library = child(root, "Library")
        let projects = child(root, "Projects")
        let downloads = child(root, "Downloads with a very long name")
        let developer = child(root, "Developer SDKs")
        let media = child(root, "Media Archive")
        let config = child(root, ".config")
        let emptyFolder = child(root, "empty-folder")
        let zmoleProject = child(projects, "zmole")
        let derivedData = child(zmoleProject, "DerivedData")
        let source = child(zmoleProject, "Source")
        let xcode = child(applications, "Xcode.app")
        let docker = child(applications, "Docker.app")
        let caches = child(library, "Caches")
        let containers = child(library, "Containers")
        let clips = child(media, "Clips")

        let pairs: [(String, DiskLevel)] = [
            level(root, [
                file("notes.md", 18_304, in: root),
                file("tiny.log", 96, in: root),
                directory("Applications", 34_000_000_000, in: root),
                directory("Library", 18_123_968_512, in: root),
                directory("Projects", 12_900_270_080, in: root),
                directory("Downloads with a very long name", 5_800_038_400, in: root),
                directory("Developer SDKs", 4_200_000_000, in: root),
                directory("Media Archive", 2_100_000_000, in: root),
                directory(".config", 930_000_000, in: root),
                directory("empty-folder", 0, in: root)
            ], total: 78_054_295_392),
            level(applications, [
                directory("Xcode.app", 22_000_000_000, in: applications),
                directory("Docker.app", 12_000_000_000, in: applications)
            ], total: 34_000_000_000),
            level(xcode, [directory("Contents", 22_000_000_000, in: xcode)], total: 22_000_000_000),
            level(docker, [directory("Contents", 12_000_000_000, in: docker)], total: 12_000_000_000),
            level(library, [
                directory("Caches", 9_000_000_000, in: library),
                directory("Containers", 9_123_968_512, in: library)
            ], total: 18_123_968_512),
            level(caches, [file("com.demo.cache", 9_000_000_000, in: caches)], total: 9_000_000_000),
            level(containers, [file("com.demo.container", 9_123_968_512, in: containers)], total: 9_123_968_512),
            level(projects, [directory("zmole", 12_900_270_080, in: projects)], total: 12_900_270_080),
            level(zmoleProject, [
                directory("DerivedData", 12_000_000_000, in: zmoleProject),
                directory("Source", 900_270_080, in: zmoleProject)
            ], total: 12_900_270_080),
            level(derivedData, [file("Build.db", 12_000_000_000, in: derivedData)], total: 12_000_000_000),
            level(source, [file("main.swift", 900_270_080, in: source)], total: 900_270_080),
            level(downloads, [
                file("Android Studio.dmg", 1_210_000_000, in: downloads),
                file("Figma.pkg", 640_000_000, in: downloads),
                file("VSCode.zip", 310_000_000, in: downloads),
                file("Old Installer.dmg", 3_640_038_400, in: downloads)
            ], total: 5_800_038_400),
            level(developer, [
                file("Xcode.xip", 2_400_000_000, in: developer),
                file("CoreSimulator.dmg", 1_800_000_000, in: developer)
            ], total: 4_200_000_000),
            level(media, [directory("Clips", 2_100_000_000, in: media)], total: 2_100_000_000),
            level(clips, [
                file("Footage.mov", 2_000_000_000, in: clips),
                file("Archive.zip", 100_000_000, in: clips)
            ], total: 2_100_000_000),
            level(config, [file("settings.json", 930_000_000, in: config)], total: 930_000_000),
            level(emptyFolder, [], total: 0)
        ]
        return Dictionary(uniqueKeysWithValues: pairs)
    }()
}

@MainActor
final class AppDependencies: ObservableObject {
    let coordinator: OperationCoordinator
    let cleanViewModel: CleanViewModel
    let uninstallViewModel: UninstallViewModel
    let optimizeViewModel: OptimizeViewModel
    let purgeViewModel: PurgeViewModel
    let purgePathsViewModel: PurgePathsViewModel
    let whitelistViewModel: WhitelistViewModel
    let optimizeWhitelistViewModel: WhitelistViewModel
    let loginItemViewModel: LoginItemViewModel
    let analyzeViewModel: AnalyzeViewModel
    let statusViewModel: StatusViewModel
    let historyViewModel: HistoryViewModel
    let installersViewModel: InstallersViewModel
    let overviewViewModel: OverviewViewModel
    let demoDataRoot: URL?
    let demoCleanPreviewURL: URL?
    let lanes: MoleCommandLanes

    let demo: DemoConfiguration

    init(configuration: DemoConfiguration = DemoConfiguration()) {
        demo = configuration
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
            lanes = .demo(
                process: DemoMoleProcess(cleanPreviewURL: cleanPreviewURL, state: configuration.state),
                streaming: DemoMoleStreaming(state: configuration.state)
            )
        } else if let bridges = MoleCommandLanes.makeCommandBridges(),
                  let streamBridge = try? MoleBridge(),
                  let cleanBridge = try? MoleBridge() {
            // One bridge per one-shot consumer: a slow read no longer rejects
            // other pages as busy. Writes stay mutually exclusive via the
            // coordinator lease, not the bridge.
            lanes = MoleCommandLanes(
                history: bridges[0],
                uninstall: bridges[1],
                installer: bridges[2],
                statusCommand: bridges[3],
                cleanCommand: bridges[4],
                optimize: bridges[5],
                purge: bridges[6],
                estimate: bridges[7],
                statusStream: streamBridge,
                cleanStream: cleanBridge
            )
        } else {
            lanes = .unavailable()
        }

        coordinator = OperationCoordinator()
        let previewStore: CleanPreviewStore
        if configuration.isEnabled {
            previewStore = CleanPreviewStore(
                fileURL: cleanPreviewURL
            )
        } else {
            previewStore = .live
        }
        cleanViewModel = CleanViewModel(
            process: lanes.cleanCommand,
            previewStore: previewStore,
            coordinator: coordinator,
            streaming: lanes.cleanStream
        )
        uninstallViewModel = UninstallViewModel(process: lanes.uninstall, coordinator: coordinator)
        optimizeViewModel = OptimizeViewModel(process: lanes.optimize, coordinator: coordinator)
        purgeViewModel = PurgeViewModel(process: lanes.purge, coordinator: coordinator)
        let whitelistURL = configuration.isEnabled
            ? demoDirectory.appendingPathComponent("whitelist")
            : WhitelistStore.live.fileURL
        whitelistViewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: whitelistURL),
            coordinator: coordinator
        )
        let optimizeWhitelistURL = configuration.isEnabled
            ? demoDirectory.appendingPathComponent("whitelist_optimize")
            : WhitelistStore.optimize.fileURL
        optimizeWhitelistViewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: optimizeWhitelistURL),
            coordinator: coordinator,
            kind: .optimize
        )
        loginItemViewModel = LoginItemViewModel()
        let purgePathsURL = configuration.isEnabled
            ? demoDirectory.appendingPathComponent("purge_paths")
            : PurgePathsStore.live.fileURL
        purgePathsViewModel = PurgePathsViewModel(
            store: PurgePathsStore(fileURL: purgePathsURL),
            coordinator: coordinator
        )

        if configuration.isEnabled {
            analyzeViewModel = AnalyzeViewModel(
                scanner: DemoDiskScanner(state: configuration.state),
                root: DemoDiskScanner.root
            )
        } else {
            analyzeViewModel = AnalyzeViewModel(scanner: LiveDiskScanner(), root: "/")
        }

        let statusBox = MoleProcessBox(lanes.statusCommand)
        let statusLoader = StatusSnapshotLoader { arguments in
            try await statusBox.process.run(arguments, stdin: nil, timeout: 120)
        }
        statusViewModel = StatusViewModel(streaming: lanes.statusStream, loader: statusLoader)

        let historyBox = MoleProcessBox(lanes.history)
        let historyLoader = HistorySnapshotLoader { arguments in
            try await historyBox.process.run(arguments, stdin: nil, timeout: 120)
        }
        historyViewModel = HistoryViewModel(loader: historyLoader)
        installersViewModel = InstallersViewModel(
            interface: InstallerInterface(process: lanes.installer),
            coordinator: coordinator
        )

        let estimateBox = MoleProcessBox(lanes.estimate)
        let estimateAnalyzeLoader = AnalyzeSnapshotLoader { arguments in
            try await estimateBox.process.run(arguments, stdin: nil, timeout: 120)
        }
        let storageLoader = StorageEstimateLoader(loader: estimateAnalyzeLoader)
        overviewViewModel = OverviewViewModel(
            storageLoader: storageLoader,
            historyLoader: historyLoader,
            storageCache: configuration.isEnabled ? nil : .live,
            coordinator: coordinator
        )
    }
}
