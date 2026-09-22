import Combine
import Foundation

struct StatusSnapshotLoader: Sendable {
    typealias RunCommand = @Sendable ([String]) async throws -> MoleCommandResult

    private let runCommand: RunCommand

    init(bridge: MoleBridge) {
        runCommand = { arguments in try await bridge.run(arguments) }
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
    @Published private(set) var series: [StatusSeriesPoint] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSampling = false
    @Published private(set) var isPaused = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var errorMessage: String?

    private let loader: StatusSnapshotLoader?
    private let watchService: (any StatusWatchProviding)?
    private var watchTask: Task<Void, Never>?

    init(loader: StatusSnapshotLoader) {
        self.loader = loader
        watchService = nil
    }

    init(service: any StatusWatchProviding, loader: StatusSnapshotLoader? = nil) {
        self.loader = loader
        watchService = service
    }

    convenience init(streaming: any MoleStreaming, loader: StatusSnapshotLoader? = nil) {
        self.init(service: StatusWatchService(streaming: streaming), loader: loader)
    }

    /// Kept for SwiftUI previews and old call sites. Production App assembly
    /// must inject a service; this initializer never creates a Bridge.
    init() {
        loader = nil
        watchService = nil
    }

    deinit {
        watchTask?.cancel()
    }

    /// Explicit one-shot snapshot path, useful for diagnostics and settings
    /// that do not need a long-running watch process.
    func refresh() async {
        watchTask?.cancel()
        await watchService?.pause()
        isSampling = false
        isPaused = false
        snapshot = nil
        series = []
        lastUpdatedAt = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        if let loader {
            do {
                snapshot = try await loader.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        if let watchService, let current = await watchService.snapshot {
            snapshot = current
            series = await watchService.series
            lastUpdatedAt = current.collectedAt
        } else {
            errorMessage = "状态服务未注入"
        }
    }

    /// Starts one subscription for this view. The service itself is shared;
    /// multiple view models do not spawn multiple mole processes.
    func start() {
        guard let watchService else {
            errorMessage = "状态服务未注入"
            isSampling = false
            return
        }
        watchTask?.cancel()
        errorMessage = nil
        isPaused = false
        isSampling = true
        watchTask = Task { [weak self] in
            let stream = await watchService.subscribe()
            await watchService.start()
            guard let self else { return }
            do {
                for try await update in stream {
                    guard !Task.isCancelled else { return }
                    self.snapshot = update.snapshot
                    self.series = update.series
                    self.lastUpdatedAt = update.receivedAt
                    self.isSampling = true
                }
                if !Task.isCancelled {
                    self.isSampling = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isSampling = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func pause() async {
        watchTask?.cancel()
        watchTask = nil
        isPaused = true
        isSampling = false
        await watchService?.pause()
    }

    func stop() async {
        watchTask?.cancel()
        watchTask = nil
        isPaused = false
        isSampling = false
        await watchService?.stop()
    }

    /// Manual recovery only. There is intentionally no automatic retry loop.
    func retry() {
        errorMessage = nil
        isPaused = false
        start()
    }
}
