import CoreGraphics
import Foundation

/// Pure geometry for the status load chart. The view never fabricates a trend:
/// a series needs at least two samples inside the trailing window to draw.
enum StatusChart {
    static let window: TimeInterval = 60

    /// Samples inside the trailing window, oldest first.
    static func windowed(
        _ series: [StatusSeriesPoint],
        seconds: TimeInterval = window,
        now: Date
    ) -> [StatusSeriesPoint] {
        guard let newest = series.last?.collectedAt else { return [] }
        let reference = max(newest, now)
        let cutoff = reference.addingTimeInterval(-seconds)
        return series.filter { $0.collectedAt >= cutoff }
    }

    /// Unit-space points (x 0...1 left to right, y 0...1 bottom to top).
    /// Empty when fewer than two samples in the window carry a value.
    static func points(
        _ series: [StatusSeriesPoint],
        seconds: TimeInterval = window,
        now: Date = Date(),
        value: (StatusSeriesPoint) -> Double?,
        range: ClosedRange<Double>
    ) -> [CGPoint] {
        let samples = windowed(series, seconds: seconds, now: now)
            .compactMap { point -> (Date, Double)? in
                guard let raw = value(point), raw.isFinite else { return nil }
                return (point.collectedAt, raw)
            }
        guard samples.count >= 2,
              let first = samples.first?.0,
              let last = samples.last?.0,
              last > first else { return [] }

        let span = last.timeIntervalSince(first)
        let low = range.lowerBound
        let high = max(range.upperBound, low + 0.0001)
        return samples.map { date, raw in
            let x = date.timeIntervalSince(first) / span
            let y = min(1, max(0, (raw - low) / (high - low)))
            return CGPoint(x: x, y: y)
        }
    }

    static func isDrawable(_ points: [CGPoint]) -> Bool {
        points.count >= 2
    }

    /// Maps unit-space points into a view of `size`, y flipped so 0 is bottom.
    static func path(_ points: [CGPoint], in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
            if index == 0 {
                path.move(to: position)
            } else {
                path.addLine(to: position)
            }
        }
        return path
    }
}

/// Values shown by the four-tile status strip. Missing fields render the
/// localized unknown placeholder, never a made-up zero.
struct StatusStatValues: Equatable {
    let cpu: String
    let memory: String
    let diskWrite: String
    let temperature: String

    static func make(from snapshot: StatusSnapshot) -> StatusStatValues {
        let memory: String
        if let used = snapshot.memory.used, let total = snapshot.memory.total {
            memory = "\(bytes(used)) / \(bytes(total))"
        } else if let percent = snapshot.memory.usedPercent {
            memory = String(format: "%.1f%%", percent)
        } else {
            memory = StatusReadout.unknown
        }

        let diskWrite = snapshot.diskIOIsWarming
            ? String(localized: "status.sampling")
            : StatusReadout.rate(snapshot.diskIO?.writeRate)

        return StatusStatValues(
            cpu: snapshot.cpu.usageAvailable
                ? String(format: "%.1f%%", snapshot.cpu.usage)
                : StatusReadout.unknown,
            memory: memory,
            diskWrite: diskWrite,
            temperature: StatusReadout.temperature(snapshot.cpuTemperature)
        )
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
