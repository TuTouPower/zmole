import Foundation

struct VolumeCapacity: Equatable, Sendable {
    let mount: String
    let total: Int64
    let used: Int64
    let free: Int64

    var disk: StatusSnapshot.Disk {
        StatusSnapshot.Disk(
            mount: mount,
            used: used,
            total: total,
            usedPercent: total > 0 ? (Double(used) / Double(total)) * 100 : 0
        )
    }
}

protocol VolumeCapacityProviding: Sendable {
    func primaryVolumeCapacity() async -> VolumeCapacity?
}

final class LiveVolumeCapacityProvider: VolumeCapacityProviding, @unchecked Sendable {
    func primaryVolumeCapacity() async -> VolumeCapacity? {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            guard let totalInt = values.volumeTotalCapacity else { return nil }
            let total = Int64(totalInt)
            let free: Int64
            if let important = values.volumeAvailableCapacityForImportantUsage {
                free = important
            } else if let avail = values.volumeAvailableCapacity {
                free = Int64(avail)
            } else {
                free = 0
            }
            let used = max(0, total - free)
            return VolumeCapacity(mount: "/", total: total, used: used, free: free)
        } catch {
            return nil
        }
    }
}
