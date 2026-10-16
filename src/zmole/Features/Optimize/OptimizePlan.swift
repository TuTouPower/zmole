import Foundation

enum OptimizeRowStatus: String, Equatable, Sendable {
    case willRun
    case skip
}

/// One read-only row on the optimize page. Rows are the `➤ Task` sections of
/// the current dry-run output; the UI never lets the user toggle a task.
struct OptimizePlanRow: Equatable, Sendable, Identifiable {
    let name: String
    let status: OptimizeRowStatus
    let reason: String?
    let deletesFiles: Bool

    var id: String { "\(name)\u{0}\(status.rawValue)\u{0}\(reason ?? "")" }
}

enum OptimizePlanParser {
    private static let deletionMarkers = ["launch agent", "launch daemon", "plist", "remove", "delete"]
    private static let noOpMarkers = [
        "skipped", "already", "not found", "unavailable", "not available",
        "all healthy", "is healthy", "all valid", "no legacy", "no changes",
        "nothing to", "close these apps before"
    ]

    /// Parses the `➤ Name` sections. Detail lines (indented `→`/`◎`/`-`) decide
    /// status: a detail that reports a no-op makes the task "skipped" and its
    /// text becomes the row's reason.
    static func rows(from output: String) -> [OptimizePlanRow] {
        var rows: [OptimizePlanRow] = []
        var name: String?
        var details: [String] = []

        func flush() {
            if let name {
                rows.append(makeRow(name: name, details: details))
            }
            name = nil
            details = []
        }

        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("➤ ") {
                flush()
                name = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if name != nil, rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") {
                if !trimmed.isEmpty { details.append(cleanDetail(trimmed)) }
            } else if !trimmed.isEmpty {
                // A non-indented line outside a task section (header/summary).
                flush()
            }
        }
        flush()
        return rows
    }

    private static func cleanDetail(_ line: String) -> String {
        var text = line
        for marker in ["→ ", "◎ ", "- ", "· "] where text.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count))
            break
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func makeRow(name: String, details: [String]) -> OptimizePlanRow {
        let joined = details.joined(separator: " ").lowercased()
        let isSkip = details.isEmpty || noOpMarkers.contains { joined.contains($0) }
        let deletes = deletionMarkers.contains { name.lowercased().contains($0) || joined.contains($0) }
        return OptimizePlanRow(
            name: name,
            status: isSkip ? .skip : .willRun,
            reason: isSkip && !details.isEmpty ? details.joined(separator: " · ") : nil,
            deletesFiles: deletes
        )
    }
}
