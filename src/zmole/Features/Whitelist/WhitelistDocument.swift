import Foundation

enum WhitelistLine: Equatable, Sendable {
    case blank
    case comment(String)
    case pattern(String)

    var text: String {
        switch self {
        case .blank:
            return ""
        case let .comment(value), let .pattern(value):
            return value
        }
    }
}

struct WhitelistDocument: Equatable, Sendable {
    static let defaultHeader: [WhitelistLine] = [
        .comment("# Mole Whitelist - Protected paths won't be deleted"),
        .comment("# Default protections: Playwright browsers, Ollama models, Surge Mac, R renv, Finder metadata"),
        .comment("# Add one pattern per line to keep items safe.")
    ]

    let lines: [WhitelistLine]

    init(lines: [WhitelistLine]) {
        self.lines = lines
    }

    init(contents: String) {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        lines = rawLines.map { rawLine in
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return .blank
            }
            if trimmed.hasPrefix("#") {
                return .comment(line)
            }
            return .pattern(trimmed)
        }
    }

    var patterns: [String] {
        lines.compactMap { line in
            guard case let .pattern(pattern) = line else { return nil }
            return pattern
        }
    }

    var comments: [String] {
        lines.compactMap { line in
            guard case let .comment(comment) = line else { return nil }
            return comment
        }
    }

    var serializedContents: String {
        guard !lines.isEmpty else { return "" }
        return lines.map(\.text).joined(separator: "\n") + "\n"
    }

    func replacingPatterns(_ patterns: [String]) -> WhitelistDocument {
        var replacementIndex = 0
        var replacedLines: [WhitelistLine] = []

        for line in lines {
            guard case .pattern = line else {
                replacedLines.append(line)
                continue
            }

            guard replacementIndex < patterns.count else { continue }
            replacedLines.append(.pattern(patterns[replacementIndex]))
            replacementIndex += 1
        }

        if replacementIndex < patterns.count {
            if !replacedLines.isEmpty, case .blank = replacedLines.last {
                // Keep the existing separator before appended patterns.
            } else if !replacedLines.isEmpty {
                replacedLines.append(.blank)
            }
            replacedLines.append(contentsOf: patterns[replacementIndex...].map(WhitelistLine.pattern))
        }

        return WhitelistDocument(lines: replacedLines)
    }
}

struct WhitelistPattern: Identifiable, Equatable, Sendable {
    let id: UUID
    let value: String

    init(value: String, id: UUID = UUID()) {
        self.id = id
        self.value = value
    }
}
