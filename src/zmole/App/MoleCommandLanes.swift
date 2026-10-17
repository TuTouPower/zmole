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
    /// Dedicated lanes for the background scanner; nil in demo/unavailable.
    let scan: BackgroundScanLanes?
    let statusStream: any MoleStreaming

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
        scan: BackgroundScanLanes?,
        statusStream: any MoleStreaming
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
        self.scan = scan
        self.statusStream = statusStream
    }

    /// Every command lane, for shutdown cancellation.
    var allProcessLanes: [any MoleProcessControlling] {
        var lanes: [any MoleProcessControlling] = [history, uninstall, installer, cleanCommand, optimize, purge]
        lanes += estimatePool
        if let scan {
            lanes += [scan.installerProcess, scan.clean, scan.optimize, scan.purge]
        }
        return lanes
    }

    var allStreams: [any MoleStreaming] {
        var streams: [any MoleStreaming] = [uninstallStream, statusStream]
        if let scan { streams.append(scan.uninstallStreaming) }
        return streams
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
        let scanUninstallStream: any MoleStreaming
        let scanInstaller: any MoleProcessControlling
        let scanClean: any MoleProcessControlling
        let scanOptimize: any MoleProcessControlling
        let scanPurge: any MoleProcessControlling
    }

    static func makeCommandBridges() -> CommandBridges? {
        func makeBridge() -> (any MoleProcessControlling)? { try? MoleBridge() }
        func makeStream() -> (any MoleStreaming)? { try? MoleBridge() }
        guard let history = makeBridge(),
              let uninstall = makeBridge(),
              let installer = makeBridge(),
              let cleanCommand = makeBridge(),
              let optimize = makeBridge(),
              let purge = makeBridge(),
              let estimate = makeBridge(),
              let estimateExtra1 = makeBridge(),
              let estimateExtra2 = makeBridge(),
              let scanUninstallStream = makeStream(),
              let scanInstaller = makeBridge(),
              let scanClean = makeBridge(),
              let scanOptimize = makeBridge(),
              let scanPurge = makeBridge() else { return nil }
        return CommandBridges(
            history: history,
            uninstall: uninstall,
            installer: installer,
            cleanCommand: cleanCommand,
            optimize: optimize,
            purge: purge,
            estimate: estimate,
            estimateExtras: [estimateExtra1, estimateExtra2],
            scanUninstallStream: scanUninstallStream,
            scanInstaller: scanInstaller,
            scanClean: scanClean,
            scanOptimize: scanOptimize,
            scanPurge: scanPurge
        )
    }

    static func demo(
        process: any MoleProcessControlling,
        streaming: any MoleStreaming,
        uninstallStream: any MoleStreaming
    ) -> MoleCommandLanes {
        let scan = BackgroundScanLanes(
            uninstallStreaming: uninstallStream,
            installer: InstallerInterface(process: process),
            installerProcess: process,
            clean: process,
            optimize: process,
            purge: process
        )
        return MoleCommandLanes(
            history: process, uninstall: process, uninstallStream: uninstallStream,
            installer: process, cleanCommand: process,
            optimize: process, purge: process, estimate: process,
            scan: scan,
            statusStream: streaming
        )
    }

    static func unavailable() -> MoleCommandLanes {
        let process = UnavailableMoleProcess()
        return MoleCommandLanes(
            history: process, uninstall: process, uninstallStream: UnavailableMoleStreaming(),
            installer: process, cleanCommand: process,
            optimize: process, purge: process, estimate: process,
            scan: nil,
            statusStream: UnavailableMoleStreaming()
        )
    }
}
