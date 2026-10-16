import Foundation

/// Named execution lanes for the bundled mole CLI. One-shot read commands get
/// independent lanes so a slow scan (for example `analyze`) cannot reject other
/// pages as busy. Writes are still mutually exclusive through the shared
/// `OperationCoordinator` lease, and long-lived streams keep their own lanes.
@MainActor
final class MoleCommandLanes {
    let analyze: any MoleProcessControlling
    let history: any MoleProcessControlling
    let uninstall: any MoleProcessControlling
    let installer: any MoleProcessControlling
    let statusCommand: any MoleProcessControlling
    let cleanCommand: any MoleProcessControlling
    let optimize: any MoleProcessControlling
    let purge: any MoleProcessControlling
    let estimate: any MoleProcessControlling
    let statusStream: any MoleStreaming
    let cleanStream: (any MoleStreaming)?

    init(
        analyze: any MoleProcessControlling,
        history: any MoleProcessControlling,
        uninstall: any MoleProcessControlling,
        installer: any MoleProcessControlling,
        statusCommand: any MoleProcessControlling,
        cleanCommand: any MoleProcessControlling,
        optimize: any MoleProcessControlling,
        purge: any MoleProcessControlling,
        estimate: any MoleProcessControlling,
        statusStream: any MoleStreaming,
        cleanStream: (any MoleStreaming)?
    ) {
        self.analyze = analyze
        self.history = history
        self.uninstall = uninstall
        self.installer = installer
        self.statusCommand = statusCommand
        self.cleanCommand = cleanCommand
        self.optimize = optimize
        self.purge = purge
        self.estimate = estimate
        self.statusStream = statusStream
        self.cleanStream = cleanStream
    }

    /// One-shot lanes, in the order the `init` expects them.
    static let commandLaneCount = 9

    static func makeCommandBridges(count: Int = commandLaneCount) -> [any MoleProcessControlling]? {
        var bridges: [any MoleProcessControlling] = []
        for _ in 0..<count {
            guard let bridge = try? MoleBridge() else { return nil }
            bridges.append(bridge)
        }
        return bridges
    }

    static func demo(process: any MoleProcessControlling, streaming: any MoleStreaming) -> MoleCommandLanes {
        MoleCommandLanes(
            analyze: process, history: process, uninstall: process, installer: process,
            statusCommand: process, cleanCommand: process, optimize: process, purge: process,
            estimate: process,
            statusStream: streaming,
            cleanStream: nil
        )
    }

    static func unavailable() -> MoleCommandLanes {
        let process = UnavailableMoleProcess()
        return MoleCommandLanes(
            analyze: process, history: process, uninstall: process, installer: process,
            statusCommand: process, cleanCommand: process, optimize: process, purge: process,
            estimate: process,
            statusStream: UnavailableMoleStreaming(),
            cleanStream: nil
        )
    }
}
