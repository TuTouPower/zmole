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
    let statusCommand: any MoleProcessControlling
    let cleanCommand: any MoleProcessControlling
    let optimize: any MoleProcessControlling
    let purge: any MoleProcessControlling
    let estimate: any MoleProcessControlling
    let prewarm: (any MoleProcessControlling & MoleStreaming)?
    let statusStream: any MoleStreaming
    let cleanStream: (any MoleStreaming)?

    init(
        history: any MoleProcessControlling,
        uninstall: any MoleProcessControlling,
        uninstallStream: any MoleStreaming,
        installer: any MoleProcessControlling,
        statusCommand: any MoleProcessControlling,
        cleanCommand: any MoleProcessControlling,
        optimize: any MoleProcessControlling,
        purge: any MoleProcessControlling,
        estimate: any MoleProcessControlling,
        prewarm: (any MoleProcessControlling & MoleStreaming)?,
        statusStream: any MoleStreaming,
        cleanStream: (any MoleStreaming)?
    ) {
        self.history = history
        self.uninstall = uninstall
        self.uninstallStream = uninstallStream
        self.installer = installer
        self.statusCommand = statusCommand
        self.cleanCommand = cleanCommand
        self.optimize = optimize
        self.purge = purge
        self.estimate = estimate
        self.prewarm = prewarm
        self.statusStream = statusStream
        self.cleanStream = cleanStream
    }

    /// One-shot lanes, in the order the `init` expects them.
    nonisolated static let commandLaneCount = 8

    static func makeCommandBridges(count: Int = commandLaneCount) -> [any MoleProcessControlling]? {
        var bridges: [any MoleProcessControlling] = []
        for _ in 0..<count {
            guard let bridge = try? MoleBridge() else { return nil }
            bridges.append(bridge)
        }
        return bridges
    }

    static func demo(
        process: any MoleProcessControlling,
        streaming: any MoleStreaming,
        uninstallStream: any MoleStreaming
    ) -> MoleCommandLanes {
        MoleCommandLanes(
            history: process, uninstall: process, uninstallStream: uninstallStream,
            installer: process, statusCommand: process, cleanCommand: process,
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
            installer: process, statusCommand: process, cleanCommand: process,
            optimize: process, purge: process, estimate: process,
            prewarm: nil,
            statusStream: UnavailableMoleStreaming(),
            cleanStream: nil
        )
    }
}
