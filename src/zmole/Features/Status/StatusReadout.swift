import Foundation

/// Formatting helpers shared by the status page. Missing values render as a
/// localized "unknown" instead of a bare dash so AC-006 is applied uniformly to
/// temperature, network and disk I/O.
enum StatusReadout {
    static func temperature(_ value: Double?) -> String {
        value.map { String(format: "%.0f°C", $0) } ?? unknown
    }

    static func count(_ value: Int?) -> String {
        value.map(String.init) ?? unknown
    }

    static func rate(_ value: Double?) -> String {
        value.map { String(format: "%.2f MB/s", $0) } ?? unknown
    }

    static var unknown: String {
        String(localized: "status.unknown")
    }
}
