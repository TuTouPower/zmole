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
    let prewarmService: PrewarmService?

    private var prewarmSubscriptions: [AnyCancellable] = []

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
                streaming: DemoMoleStreaming(state: configuration.state),
                uninstallStream: DemoUninstallListStream(state: configuration.state)
            )
        } else if let bridges = MoleCommandLanes.makeCommandBridges(),
                   let streamBridge = try? MoleBridge(),
                   let cleanBridge = try? MoleBridge(),
                   let uninstallStreamBridge = try? MoleBridge(),
                   let prewarmBridge = try? MoleBridge() {
            // One bridge per one-shot consumer: a slow read no longer rejects
            // other pages as busy. Writes stay mutually exclusive via the
            // coordinator lease, not the bridge.
            lanes = MoleCommandLanes(
                history: bridges.history,
                uninstall: bridges.uninstall,
                uninstallStream: uninstallStreamBridge,
                installer: bridges.installer,
                cleanCommand: bridges.cleanCommand,
                optimize: bridges.optimize,
                purge: bridges.purge,
                estimate: bridges.estimate,
                estimatePool: [bridges.estimate] + bridges.estimateExtras,
                prewarm: prewarmBridge,
                statusStream: streamBridge,
                cleanStream: cleanBridge
            )
        } else {
            lanes = .unavailable()
        }

        let sharedCoordinator = OperationCoordinator()
        coordinator = sharedCoordinator
        let previewStore: CleanPreviewStore
        if configuration.isEnabled {
            previewStore = CleanPreviewStore(
                fileURL: cleanPreviewURL
            )
        } else {
            previewStore = .live
        }
        let prewarm = lanes.prewarm.map { lane in
            PrewarmService(
                process: lane,
                installerInterface: InstallerInterface(process: lane),
                cleanPreviewStore: previewStore,
                coordinator: sharedCoordinator
            )
        }
        prewarmService = prewarm
        cleanViewModel = CleanViewModel(
            process: lanes.cleanCommand,
            previewStore: previewStore,
            coordinator: coordinator,
            streaming: lanes.cleanStream,
            prewarm: prewarm
        )
        uninstallViewModel = UninstallViewModel(
            process: lanes.uninstall,
            listStream: UninstallListStream(streaming: lanes.uninstallStream),
            coordinator: coordinator,
            prewarm: prewarm
        )
        optimizeViewModel = OptimizeViewModel(
            process: lanes.optimize,
            coordinator: coordinator,
            prewarm: prewarm
        )
        purgeViewModel = PurgeViewModel(
            process: lanes.purge,
            coordinator: coordinator,
            prewarm: prewarm
        )
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

        statusViewModel = StatusViewModel(streaming: lanes.statusStream)

        let historyBox = MoleProcessBox(lanes.history)
        let historyLoader = HistorySnapshotLoader { arguments in
            try await historyBox.process.run(arguments, stdin: nil, timeout: 120)
        }
        historyViewModel = HistoryViewModel(loader: historyLoader)
        installersViewModel = InstallersViewModel(
            interface: InstallerInterface(process: lanes.installer),
            coordinator: coordinator,
            prewarm: prewarm
        )

        let estimateLoaders = lanes.estimatePool.map { lane in
            let box = MoleProcessBox(lane)
            return AnalyzeSnapshotLoader { arguments in
                try await box.process.run(arguments, stdin: nil, timeout: 600)
            }
        }
        let storageLoader = StorageEstimateLoader(loaders: estimateLoaders)
        overviewViewModel = OverviewViewModel(
            storageLoader: storageLoader,
            historyLoader: historyLoader,
            storageCache: configuration.isEnabled ? nil : .live,
            coordinator: coordinator
        )

        if let prewarm {
            prewarm.externalActivityProvider = { [weak analyzeViewModel, weak uninstallViewModel, weak installersViewModel, weak cleanViewModel] in
                (analyzeViewModel?.isScanning ?? false)
                    || (uninstallViewModel?.isListing ?? false)
                    || (installersViewModel?.isListing ?? false)
                    || (cleanViewModel?.preview != nil)
                    || (cleanViewModel?.isConfirmationPresented ?? false)
            }
            prewarm.cleanPreviewActiveProvider = { [weak cleanViewModel] in
                guard let cleanViewModel else { return false }
                return cleanViewModel.preview != nil
                    || cleanViewModel.isConfirmationPresented
                    || cleanViewModel.isPreviewing
            }
            // Published changes fire before the mutation lands; hop one main
            // actor turn so the idle check reads the new values. A short
            // coalescing window keeps scan-time publish storms from spawning
            // one MainActor task per change.
            let coalescer = ActivityCoalescer(prewarm: prewarm)
            prewarmSubscriptions = [
                analyzeViewModel.objectWillChange.sink { _ in
                    Task { @MainActor in coalescer.notify() }
                },
                uninstallViewModel.objectWillChange.sink { _ in
                    Task { @MainActor in coalescer.notify() }
                },
                installersViewModel.objectWillChange.sink { _ in
                    Task { @MainActor in coalescer.notify() }
                },
                cleanViewModel.objectWillChange.sink { _ in
                    Task { @MainActor in coalescer.notify() }
                }
            ]
            prewarm.noteActivityChanged()
        }

        if !configuration.isEnabled {
            installShutdownHandler()
        }
    }

    /// Cancels every active command lane and stream at app termination,
    /// waiting up to two seconds so destructive children (bash/rm) cannot
    /// outlive the GUI.
    private func installShutdownHandler() {
        let processLanes = lanes.allProcessLanes
        let streams = lanes.allStreams
        AppDelegate.shutdownHandler = {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                await withTaskGroup(of: Void.self) { group in
                    for lane in processLanes {
                        group.addTask { await lane.cancel() }
                    }
                    for stream in streams {
                        group.addTask { await stream.cancel() }
                    }
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2)
        }
    }
}

/// Coalesces activity-change notifications into one prewarm poke per short
/// window so high-frequency publishes cannot flood the main actor.
@MainActor
private final class ActivityCoalescer {
    private weak var prewarm: PrewarmService?
    private var pending: Task<Void, Never>?
    private static let windowNanoseconds: UInt64 = 200_000_000

    init(prewarm: PrewarmService) {
        self.prewarm = prewarm
    }

    func notify() {
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.windowNanoseconds)
            guard let self else { return }
            self.pending = nil
            self.prewarm?.noteActivityChanged()
        }
    }
}
