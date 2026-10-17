import Foundation

/// Named execution lanes for the bundled mole CLI. One-shot read commands get
/// independent lanes so a slow scan cannot reject other pages as busy. Writes
/// are still mutually exclusive through the shared `OperationCoordinator`
/// lease, and long-lived streams keep their own lanes.
@MainActor
final class MoleCommandLanes {
    let history: any MoleProcessControlling
    let uninstall: any MoleProcessControlling
    let uninstallStream: any MoleStreaming
    let installer: any MoleProcessControlling
    let cleanCommand: any MoleProcessControlling
    let optimize: any MoleProcessControlling
    let purge: any MoleProcessControlling
    let estimate: any MoleProcessControlling
    /// Independent estimate lanes used to probe several paths in parallel
    /// (one command in flight per lane). The first entry is the primary lane.
    let estimatePool: [any MoleProcessControlling]
    let prewarm: (any MoleProcessControlling & MoleStreaming)?
    let statusStream: any MoleStreaming
    let cleanStream: (any MoleStreaming)?

    init(
        history: any MoleProcessControlling,
        uninstall: any MoleProcessControlling,
        uninstallStream: any MoleStreaming,
        installer: any MoleProcessControlling,
        cleanCommand: any MoleProcessControlling,
        optimize: any MoleProcessControlling,
        purge: any MoleProcessControlling,
        estimate: any MoleProcessControlling,
        estimatePool: [any MoleProcessControlling]? = nil,
        prewarm: (any MoleProcessControlling & MoleStreaming)?,
        statusStream: any MoleStreaming,
        cleanStream: (any MoleStreaming)?
    ) {
        self.history = history
        self.uninstall = uninstall
        self.uninstallStream = uninstallStream
        self.installer = installer
        self.cleanCommand = cleanCommand
        self.optimize = optimize
        self.purge = purge
        self.estimate = estimate
        self.estimatePool = estimatePool ?? [estimate]
        self.prewarm = prewarm
        self.statusStream = statusStream
        self.cleanStream = cleanStream
    }

    /// Every command lane, for shutdown cancellation.
    var allProcessLanes: [any MoleProcessControlling] {
        [history, uninstall, installer, cleanCommand, optimize, purge]
            + estimatePool
            + (prewarm.map { [$0] } ?? [])
    }

    var allStreams: [any MoleStreaming] {
        [uninstallStream, statusStream] + (cleanStream.map { [$0] } ?? [])
    }

    /// Named one-shot lanes. Named fields replace positional array mapping so
    /// adding or reordering lanes cannot silently cross-wire consumers.
    struct CommandBridges {
        let history: any MoleProcessControlling
        let uninstall: any MoleProcessControlling
        let installer: any MoleProcessControlling
        let cleanCommand: any MoleProcessControlling
        let optimize: any MoleProcessControlling
        let purge: any MoleProcessControlling
        let estimate: any MoleProcessControlling
        /// Extra estimate lanes for parallel overview probes.
        let estimateExtras: [any MoleProcessControlling]
    }

    static func makeCommandBridges() -> CommandBridges? {
        func makeBridge() -> (any MoleProcessControlling)? { try? MoleBridge() }
        guard let history = makeBridge(),
              let uninstall = makeBridge(),
              let installer = makeBridge(),
              let cleanCommand = makeBridge(),
              let optimize = makeBridge(),
              let purge = makeBridge(),
              let estimate = makeBridge(),
              let estimateExtra1 = makeBridge(),
              let estimateExtra2 = makeBridge() else { return nil }
        return CommandBridges(
            history: history,
            uninstall: uninstall,
            installer: installer,
            cleanCommand: cleanCommand,
            optimize: optimize,
            purge: purge,
            estimate: estimate,
            estimateExtras: [estimateExtra1, estimateExtra2]
        )
    }

    static func demo(
        process: any MoleProcessControlling,
        streaming: any MoleStreaming,
        uninstallStream: any MoleStreaming
    ) -> MoleCommandLanes {
        MoleCommandLanes(
            history: process, uninstall: process, uninstallStream: uninstallStream,
            installer: process, cleanCommand: process,
            optimize: process, purge: process, estimate: process,
            prewarm: nil,
            statusStream: streaming,
            cleanStream: nil
        )
    }

    static func unavailable() -> MoleCommandLanes {
        let process = UnavailableMoleProcess()
        return MoleCommandLanes(
            history: process, uninstall: process, uninstallStream: UnavailableMoleStreaming(),
            installer: process, cleanCommand: process,
            optimize: process, purge: process, estimate: process,
            prewarm: nil,
            statusStream: UnavailableMoleStreaming(),
            cleanStream: nil
        )
    }
}
