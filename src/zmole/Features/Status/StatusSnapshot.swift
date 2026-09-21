import Foundation

struct StatusSnapshot: Codable, Equatable, Sendable {
    let healthScore: Int
    let cpu: CPU
    let memory: Memory
    let disks: [Disk]

    struct CPU: Codable, Equatable, Sendable {
        let usage: Double
    }

    struct Memory: Codable, Equatable, Sendable {
        let used: Int64?
        let total: Int64?
        let usedPercent: Double?

        enum CodingKeys: String, CodingKey {
            case used
            case total
            case usedPercent = "used_percent"
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

        enum CodingKeys: String, CodingKey {
            case mount
            case used
            case total
            case usedPercent = "used_percent"
        }

        var hasDisplayableValue: Bool {
            (used != nil && total != nil) || usedPercent != nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case healthScore = "health_score"
        case cpu
        case memory
        case disks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        healthScore = try container.decode(Int.self, forKey: .healthScore)
        cpu = try container.decode(CPU.self, forKey: .cpu)
        memory = try container.decode(Memory.self, forKey: .memory)
        disks = try container.decode([Disk].self, forKey: .disks)

        guard memory.hasDisplayableValue else {
            throw StatusSnapshotError.missingMemoryMetrics
        }
        guard disks.contains(where: \.hasDisplayableValue) else {
            throw StatusSnapshotError.missingDiskMetrics
        }
    }
}

enum StatusSnapshotError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON
    case missingMemoryMetrics
    case missingDiskMetrics

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "status JSON 无法解析"
        case .missingMemoryMetrics:
            return "status JSON 缺少内存指标"
        case .missingDiskMetrics:
            return "status JSON 缺少磁盘指标"
        }
    }
}
