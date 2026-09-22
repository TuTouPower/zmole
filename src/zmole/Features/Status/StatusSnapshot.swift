import Foundation

/// One sample emitted by `mole status --watch`.
///
/// Slow sections are emitted independently by mole. Basic sections therefore
/// have safe empty values while optional sections stay optional; an unavailable
/// sensor must not invalidate the whole sample.
struct StatusSnapshot: Codable, Equatable, Sendable {
    let collectedAt: Date?
    let healthScore: Int
    let healthScoreAvailable: Bool
    let cpu: CPU
    let memory: Memory
    let disks: [Disk]
    let disksAvailable: Bool
    let diskIO: DiskIO?
    let network: [NetworkInterface]?
    let topProcesses: [ProcessInfo]?
    let processCollectedAt: Date?
    let processStale: Bool

    struct CPU: Codable, Equatable, Sendable {
        let usage: Double
        let usageAvailable: Bool

        init(usage: Double = 0, usageAvailable: Bool = false) {
            self.usage = usage
            self.usageAvailable = usageAvailable
        }

        enum CodingKeys: String, CodingKey { case usage }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decode(Double.self, forKey: .usage) {
                usage = value
                usageAvailable = true
            } else {
                usage = 0
                usageAvailable = false
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(usage, forKey: .usage)
        }
    }

    struct Memory: Codable, Equatable, Sendable {
        let used: Int64?
        let total: Int64?
        let usedPercent: Double?

        init(used: Int64? = nil, total: Int64? = nil, usedPercent: Double? = nil) {
            self.used = used
            self.total = total
            self.usedPercent = usedPercent
        }

        enum CodingKeys: String, CodingKey {
            case used
            case total
            case usedPercent = "used_percent"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            used = try? container.decode(Int64.self, forKey: .used)
            total = try? container.decode(Int64.self, forKey: .total)
            usedPercent = try? container.decode(Double.self, forKey: .usedPercent)
        }

        var hasDisplayableValue: Bool {
            (used != nil && total != nil) || usedPercent != nil
        }
    }

    struct Disk: Codable, Equatable, Sendable {
        let mount: String
        let used: Int64?
        let total: Int64?
        let usedPercent: Double?

        init(mount: String, used: Int64? = nil, total: Int64? = nil, usedPercent: Double? = nil) {
            self.mount = mount
            self.used = used
            self.total = total
            self.usedPercent = usedPercent
        }

        enum CodingKeys: String, CodingKey {
            case mount
            case used
            case total
            case usedPercent = "used_percent"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mount = (try? container.decode(String.self, forKey: .mount)) ?? ""
            used = try? container.decode(Int64.self, forKey: .used)
            total = try? container.decode(Int64.self, forKey: .total)
            usedPercent = try? container.decode(Double.self, forKey: .usedPercent)
        }

        var hasDisplayableValue: Bool {
            (used != nil && total != nil) || usedPercent != nil
        }
    }

    struct DiskIO: Codable, Equatable, Sendable {
        let readRate: Double?
        let writeRate: Double?

        enum CodingKeys: String, CodingKey {
            case readRate = "read_rate"
            case writeRate = "write_rate"
        }

        init(readRate: Double? = nil, writeRate: Double? = nil) {
            self.readRate = readRate
            self.writeRate = writeRate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            readRate = try? container.decode(Double.self, forKey: .readRate)
            writeRate = try? container.decode(Double.self, forKey: .writeRate)
        }
    }

    struct NetworkInterface: Codable, Equatable, Sendable {
        let name: String
        let rxRateMBs: Double?
        let txRateMBs: Double?
        let ip: String?

        enum CodingKeys: String, CodingKey {
            case name
            case rxRateMBs = "rx_rate_mbs"
            case txRateMBs = "tx_rate_mbs"
            case ip
        }

        init(name: String, rxRateMBs: Double?, txRateMBs: Double?, ip: String? = nil) {
            self.name = name
            self.rxRateMBs = rxRateMBs
            self.txRateMBs = txRateMBs
            self.ip = ip
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? container.decode(String.self, forKey: .name)) ?? ""
            rxRateMBs = try? container.decode(Double.self, forKey: .rxRateMBs)
            txRateMBs = try? container.decode(Double.self, forKey: .txRateMBs)
            ip = try? container.decode(String.self, forKey: .ip)
        }

        /// Virtual/tunnel interfaces can mirror physical traffic.
        var isVirtual: Bool {
            let value = name.lowercased()
            return ["lo", "utun", "bridge", "awdl", "llw", "gif", "stf", "p2p", "tun", "tap", "veth", "docker", "vmnet", "tailscale"]
                .contains { value == $0 || value.hasPrefix($0) }
        }
    }

    struct ProcessInfo: Codable, Equatable, Sendable {
        let pid: Int
        let name: String
        let cpu: Double?
        let memoryPercent: Double?
        let memoryBytes: Int64?

        enum CodingKeys: String, CodingKey {
            case pid
            case name
            case cpu
            case memoryPercent = "memory"
            case memoryBytes = "memory_bytes"
        }

        init(pid: Int, name: String, cpu: Double? = nil, memoryPercent: Double? = nil, memoryBytes: Int64? = nil) {
            self.pid = pid
            self.name = name
            self.cpu = cpu
            self.memoryPercent = memoryPercent
            self.memoryBytes = memoryBytes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pid = (try? container.decode(Int.self, forKey: .pid)) ?? 0
            name = (try? container.decode(String.self, forKey: .name)) ?? ""
            cpu = try? container.decode(Double.self, forKey: .cpu)
            memoryPercent = try? container.decode(Double.self, forKey: .memoryPercent)
            memoryBytes = try? container.decode(Int64.self, forKey: .memoryBytes)
        }
    }

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case healthScore = "health_score"
        case cpu
        case memory
        case disks
        case diskIO = "disk_io"
        case network
        case topProcesses = "top_processes"
        case processCollectedAt = "process_collected_at"
        case processStale = "process_stale"
    }

    init(
        collectedAt: Date? = nil,
        healthScore: Int = 0,
        healthScoreAvailable: Bool = false,
        cpu: CPU = CPU(),
        memory: Memory = Memory(),
        disks: [Disk] = [],
        disksAvailable: Bool = false,
        diskIO: DiskIO? = nil,
        network: [NetworkInterface]? = nil,
        topProcesses: [ProcessInfo]? = nil,
        processCollectedAt: Date? = nil,
        processStale: Bool = true
    ) {
        self.collectedAt = collectedAt
        self.healthScore = healthScore
        self.healthScoreAvailable = healthScoreAvailable
        self.cpu = cpu
        self.memory = memory
        self.disks = disks
        self.disksAvailable = disksAvailable
        self.diskIO = diskIO
        self.network = network
        self.topProcesses = topProcesses
        self.processCollectedAt = processCollectedAt
        self.processStale = processStale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int.self, forKey: .healthScore) {
            healthScore = value
            healthScoreAvailable = true
        } else {
            healthScore = 0
            healthScoreAvailable = false
        }
        cpu = (try? container.decode(CPU.self, forKey: .cpu)) ?? CPU()
        memory = (try? container.decode(Memory.self, forKey: .memory)) ?? Memory()
        if let decoded = try? container.decode([Disk].self, forKey: .disks) {
            disks = decoded
            disksAvailable = decoded.contains(where: \.hasDisplayableValue)
        } else {
            disks = []
            disksAvailable = false
        }
        diskIO = try? container.decode(DiskIO.self, forKey: .diskIO)
        network = try? container.decode([NetworkInterface].self, forKey: .network)
        topProcesses = try? container.decode([ProcessInfo].self, forKey: .topProcesses)
        collectedAt = Self.decodeDate(container, key: .collectedAt)
        processCollectedAt = Self.decodeDate(container, key: .processCollectedAt)
        processStale = (try? container.decode(Bool.self, forKey: .processStale)) ?? (topProcesses == nil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let collectedAt { try container.encode(Self.dateString(collectedAt), forKey: .collectedAt) }
        try container.encode(healthScore, forKey: .healthScore)
        try container.encode(cpu, forKey: .cpu)
        try container.encode(memory, forKey: .memory)
        try container.encode(disks, forKey: .disks)
        try container.encodeIfPresent(diskIO, forKey: .diskIO)
        try container.encodeIfPresent(network, forKey: .network)
        try container.encodeIfPresent(topProcesses, forKey: .topProcesses)
        if let processCollectedAt { try container.encode(Self.dateString(processCollectedAt), forKey: .processCollectedAt) }
        try container.encode(processStale, forKey: .processStale)
    }

    var networkTotal: NetworkTotal? {
        guard let network, !network.isEmpty else { return nil }
        let physical = network.filter { !$0.isVirtual }
        guard !physical.isEmpty else {
            return NetworkTotal(
                rxRateMBs: nil,
                txRateMBs: nil,
                isVirtualOnly: true
            )
        }
        let interfaces = physical
        let rx = interfaces.compactMap(\.rxRateMBs).reduce(0, +)
        let tx = interfaces.compactMap(\.txRateMBs).reduce(0, +)
        let hasRx = interfaces.contains { $0.rxRateMBs != nil }
        let hasTx = interfaces.contains { $0.txRateMBs != nil }
        return NetworkTotal(
            rxRateMBs: hasRx ? rx : nil,
            txRateMBs: hasTx ? tx : nil,
            isVirtualOnly: false
        )
    }

    /// The helper reports zero while its first disk sample is only being
    /// initialized. Keep that zero distinguishable from a measured idle rate.
    var diskIOIsWarming: Bool {
        guard let diskIO else { return false }
        let hasNoDelta = diskIO.readRate == 0 && diskIO.writeRate == 0
        let isIncomplete = topProcesses == nil || network == nil || collectedAt == nil
        return hasNoDelta && isIncomplete
    }

    struct NetworkTotal: Equatable, Sendable {
        let rxRateMBs: Double?
        let txRateMBs: Double?
        let isVirtualOnly: Bool
    }

    private static func decodeDate<K: CodingKey>(_ container: KeyedDecodingContainer<K>, key: K) -> Date? {
        guard let value = try? container.decode(String.self, forKey: key) else { return nil }
        return parseDate(value)
    }

    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum StatusSnapshotError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON

    var errorDescription: String? { "status JSON 无法解析" }
}
