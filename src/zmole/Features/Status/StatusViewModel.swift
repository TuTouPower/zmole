import Combine
import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot?
    @Published private(set) var series: [StatusSeriesPoint] = []
    @Published private(set) var isSampling = false
    @Published private(set) var isPaused = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?

    private let watchService: (any StatusWatchProviding)?
    private let policy: StatusFeaturePolicy?
    private var watchTask: Task<Void, Never>?
    /// Bumped on every start/pause/stop so a stale async start cannot
    /// resurrect the shared watch process after the page was left.
    private var watchGeneration = 0

    var isFeatureEnabled: Bool {
        policy?.isEnabled ?? true
    }

    init(service: (any StatusWatchProviding)?, policy: StatusFeaturePolicy? = nil) {
        watchService = service
        self.policy = policy
    }

    convenience init(streaming: any MoleStreaming, policy: StatusFeaturePolicy? = nil) {
        self.init(service: StatusWatchService(streaming: streaming), policy: policy)
    }

    /// Kept for SwiftUI previews and old call sites. Production App assembly
    /// must inject a service; this initializer never creates a Bridge.
    init() {
        watchService = nil
        policy = nil
    }

    deinit {
        watchTask?.cancel()
    }

    /// Starts one subscription for this view. The service itself is shared;
    /// multiple view models do not spawn multiple mole processes.
    func start() {
        guard isFeatureEnabled else {
            isSampling = false
            return
        }
        guard let watchService else {
            errorMessageKey = "status.error.no_service"
            errorMessage = nil
            isSampling = false
            return
        }
        watchTask?.cancel()
        watchGeneration += 1
        let generation = watchGeneration
        errorMessage = nil
        errorMessageKey = nil
        isPaused = false
        isSampling = true
        watchTask = Task { [weak self] in
            let stream = await watchService.subscribe()
            // A stop/pause that raced this start bumps the generation; let the
            // discarded subscription terminate instead of restarting the
            // shared watch for a page the user already left.
            guard let self, self.watchGeneration == generation, self.isFeatureEnabled else { return }
            await watchService.start()
            do {
                for try await update in stream {
                    guard !Task.isCancelled, self.isFeatureEnabled else { return }
                    self.snapshot = update.snapshot
                    self.series = update.series
                    self.lastUpdatedAt = update.receivedAt
                    self.isSampling = true
                }
                if !Task.isCancelled {
                    self.isSampling = false
                }
            } catch {
                guard !Task.isCancelled, self.isFeatureEnabled else { return }
                self.isSampling = false
                self.errorMessageKey = error.localizationKey
                self.errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
            }
        }
    }

    func pause() async {
        watchTask?.cancel()
        watchTask = nil
        watchGeneration += 1
        isPaused = true
        isSampling = false
        await watchService?.pause()
    }

    func stop() async {
        watchTask?.cancel()
        watchTask = nil
        watchGeneration += 1
        isPaused = false
        isSampling = false
        await watchService?.stop()
    }

    /// Manual recovery only. There is intentionally no automatic retry loop.
    func retry() {
        guard isFeatureEnabled else { return }
        errorMessage = nil
        errorMessageKey = nil
        isPaused = false
        start()
    }

    /// Explicit user refresh: restarts the subscription so a fresh sample
    /// arrives even while the stream is already running.
    func resample() async {
        guard isFeatureEnabled else { return }
        await pause()
        start()
    }

    func applyPolicyChange(enabled: Bool) async {
        policy?.setEnabled(enabled)
        if !enabled {
            await stop()
            snapshot = nil
            series = []
            isSampling = false
        }
    }
}
