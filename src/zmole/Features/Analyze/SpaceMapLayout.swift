import Foundation

struct SpaceMapTile: Identifiable {
    let entry: DiskEntry
    let rect: CGRect
    var id: String { entry.id }
}

enum SpaceMapLayout {
    /// Partition one level only; entries with unknown sizes draw no area and
    /// descendant sizes must not be counted twice.
    static func tiles(entries: [DiskEntry], in bounds: CGRect) -> [SpaceMapTile] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let positive = entries
            .filter { ($0.knownSize ?? 0) > 0 }
            .sorted { lhs, rhs in
                let left = lhs.knownSize ?? 0
                let right = rhs.knownSize ?? 0
                return left == right ? lhs.path < rhs.path : left > right
            }
        var result: [SpaceMapTile] = []
        partition(positive[...], bounds: bounds, into: &result)
        return result
    }

    private static func partition(
        _ entries: ArraySlice<DiskEntry>, bounds: CGRect, into result: inout [SpaceMapTile]
    ) {
        guard let first = entries.first else { return }
        guard entries.count > 1 else {
            result.append(SpaceMapTile(entry: first, rect: bounds))
            return
        }
        // Double avoids Int64 overflow when adding very large entries.
        let total = entries.reduce(0.0) { $0 + Double($1.knownSize ?? 0) }
        var accumulated = 0.0
        var split = entries.startIndex + 1
        var splitWeight = Double(first.knownSize ?? 0)
        var distance = Double.greatestFiniteMagnitude
        for index in entries.indices.dropLast() {
            accumulated += Double(entries[index].knownSize ?? 0)
            let candidate = abs(total / 2 - accumulated)
            if candidate < distance {
                split = index + 1
                splitWeight = accumulated
                distance = candidate
            }
        }
        let ratio = splitWeight / total
        let a: CGRect
        let b: CGRect
        if bounds.width >= bounds.height {
            let width = bounds.width * ratio
            a = CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
            b = CGRect(x: bounds.minX + width, y: bounds.minY,
                       width: max(0, bounds.width - width), height: bounds.height)
        } else {
            let height = bounds.height * ratio
            a = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height)
            b = CGRect(x: bounds.minX, y: bounds.minY + height,
                       width: bounds.width, height: max(0, bounds.height - height))
        }
        partition(entries[..<split], bounds: a, into: &result)
        partition(entries[split...], bounds: b, into: &result)
    }
}
