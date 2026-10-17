import Foundation

/// One candidate row from a clean dry-run preview.
struct CleanPreviewEntry: Equatable, Codable, Sendable, Identifiable {
    let path: String
    let sizeBytes: Int64?
    let itemNote: String?
    let rawLine: String

    var id: String { "\(path)\u{0}\(rawLine)" }

    var sizeText: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Candidate rows grouped under the dry-run section header (`=== Name ===`).
struct CleanPreviewSection: Equatable, Codable, Sendable, Identifiable {
    let name: String
    let entries: [CleanPreviewEntry]

    var id: String { name }

    var reclaimBytes: Int64 {
        entries.compactMap(\.sizeBytes).reduce(0, +)
    }

    var reclaimText: String {
        ByteCountFormatter.string(fromByteCount: reclaimBytes, countStyle: .file)
    }
}

enum CleanPreviewParser {
    static func sections(from contents: String) -> [CleanPreviewSection] {
        var order: [String] = []
        var grouped: [String: [CleanPreviewEntry]] = [:]
        var current = "Other"

        for rawLine in contents.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let name = sectionHeaderName(line) {
                current = name
                if grouped[current] == nil { order.append(current); grouped[current] = [] }
                continue
            }
            let entry = parseEntry(line)
            if grouped[current] == nil { order.append(current); grouped[current] = [] }
            grouped[current, default: []].append(entry)
        }

        return order.compactMap { name in
            guard let entries = grouped[name], !entries.isEmpty else { return nil }
            return CleanPreviewSection(name: name, entries: entries)
        }
    }

    static func reclaimBytes(from contents: String) -> Int64 {
        sections(from: contents).reduce(0) { $0 + $1.reclaimBytes }
    }

    private static func sectionHeaderName(_ line: String) -> String? {
        guard line.hasPrefix("==="), line.hasSuffix("==="), line.count > 6 else { return nil }
        let name = line.dropFirst(3).dropLast(3).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func parseEntry(_ line: String) -> CleanPreviewEntry {
        let (pathPart, sizePart) = splitSizeComment(line)
        return CleanPreviewEntry(
            path: pathPart,
            sizeBytes: sizePart.flatMap(Self.parseHumanSize),
            itemNote: sizePart.flatMap(Self.itemsNote),
            rawLine: line
        )
    }

    private static func splitSizeComment(_ line: String) -> (String, String?) {
        guard let range = line.range(of: "  # ") ?? line.range(of: " # ") else {
            return (line.trimmingCharacters(in: .whitespaces), nil)
        }
        let path = String(line[line.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let comment = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (path, comment)
    }

    private static func itemsNote(_ comment: String) -> String? {
        if let range = comment.range(of: ", ") {
            let tail = String(comment[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return tail.isEmpty ? nil : tail
        }
        return nil
    }

    static func parseHumanSize(_ text: String) -> Int64? {
        let head = text.split(separator: ",").first.map(String.init) ?? text
        return HumanSizeParser.bytes(from: head)
    }
}
