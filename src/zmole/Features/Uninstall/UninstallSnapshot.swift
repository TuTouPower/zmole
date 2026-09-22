import Foundation

struct UninstallApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let bundleID: String
    let uninstallName: String
    let path: String
    let source: String?
    let size: String?

    var id: String {
        [path, bundleID, uninstallName].joined(separator: "\u{1F}")
    }

    var identity: UninstallIdentity {
        UninstallIdentity(path: path, bundleID: bundleID, uninstallName: uninstallName)
    }

    var sizeBytes: Int64? {
        UninstallSizeParser.bytes(from: size)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundle_id"
        case uninstallName = "uninstall_name"
        case path
        case source
        case size
    }

    init(
        name: String,
        bundleID: String,
        uninstallName: String,
        path: String,
        source: String? = nil,
        size: String? = nil
    ) {
        self.name = name
        self.bundleID = bundleID
        self.uninstallName = uninstallName
        self.path = path
        self.source = source
        self.size = size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        uninstallName = try container.decode(String.self, forKey: .uninstallName)
        path = try container.decode(String.self, forKey: .path)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        if let value = try? container.decode(String.self, forKey: .size) {
            size = value
        } else if let value = try? container.decode(Int64.self, forKey: .size) {
            size = String(value)
        } else if let value = try? container.decode(Double.self, forKey: .size) {
            size = String(value)
        } else {
            size = nil
        }
    }
}

struct UninstallIdentity: Codable, Equatable, Hashable, Sendable {
    let path: String
    let bundleID: String
    let uninstallName: String
}

struct UninstallListSnapshot: Equatable, Sendable {
    let generation: UUID
    let apps: [UninstallApp]
}

struct UninstallPreviewSnapshot: Equatable, Sendable {
    let generation: UUID
    let apps: [UninstallApp]
    let selectedIDs: Set<String>
    let output: String

    var identities: Set<UninstallIdentity> { Set(apps.map(\.identity)) }

    init(
        generation: UUID,
        apps: [UninstallApp],
        selectedIDs: Set<String>,
        output: String
    ) {
        precondition(!apps.isEmpty)
        self.generation = generation
        self.apps = apps
        self.selectedIDs = selectedIDs
        self.output = output
    }

}

enum UninstallViewModelError: Error, Equatable, Sendable {
    case noSelection
    case ambiguousName
    case changedTarget
    case invalidList
    case missingMole
    case invalidName

    var errorKey: String {
        switch self {
        case .noSelection:
            return "uninstall.error.no_selection"
        case .ambiguousName:
            return "uninstall.error.ambiguous"
        case .changedTarget:
            return "uninstall.error.changed_target"
        case .invalidList:
            return "uninstall.error.invalid_list"
        case .missingMole:
            return "uninstall.error.missing_mole"
        case .invalidName:
            return "uninstall.error.invalid_name"
        }
    }
}

enum UninstallListDecoder {
    static func decode(_ output: String) throws -> [UninstallApp] {
        guard let data = output.data(using: .utf8) else {
            throw UninstallViewModelError.invalidList
        }

        do {
            return try JSONDecoder().decode([UninstallApp].self, from: data)
        } catch {
            throw UninstallViewModelError.invalidList
        }
    }
}

enum UninstallSelectionValidator {
    static func batch(
        selectedIDs: Set<String>,
        apps: [UninstallApp]
    ) throws -> [UninstallApp] {
        guard !selectedIDs.isEmpty else { throw UninstallViewModelError.noSelection }
        let selected = apps.filter { selectedIDs.contains($0.id) }
        guard selected.count == selectedIDs.count else {
            throw UninstallViewModelError.changedTarget
        }

        let names = selected.map { normalize($0.uninstallName) }
        guard Set(names).count == names.count else {
            throw UninstallViewModelError.ambiguousName
        }

        for app in selected {
            let normalizedName = normalize(app.uninstallName)
            guard !normalizedName.isEmpty, !normalizedName.hasPrefix("-") else {
                throw UninstallViewModelError.invalidName
            }
            let exactMatches = apps.filter {
                aliases(for: $0).contains(normalizedName)
            }
            let matches = exactMatches.isEmpty
                ? apps.filter { substringAliases(for: $0).contains(where: { $0.contains(normalizedName) }) }
                : exactMatches
            guard matches.count == 1, matches[0].id == app.id else {
                throw UninstallViewModelError.ambiguousName
            }
        }
        return selected
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func aliases(for app: UninstallApp) -> Set<String> {
        [app.name, app.uninstallName, directoryName(app.path)]
            .map(normalize)
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    private static func substringAliases(for app: UninstallApp) -> Set<String> {
        [app.name, directoryName(app.path)].map(normalize).filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    private static func directoryName(_ path: String) -> String {
        let base = URL(fileURLWithPath: path).lastPathComponent
        if base.lowercased().hasSuffix(".app") {
            return String(base.dropLast(4))
        }
        return base
    }
}

enum UninstallBatchResultParser {
    static func result(
        _ commandResult: MoleCommandResult,
        expectedCount: Int
    ) -> OperationResult {
        let summary = [commandResult.stdout, commandResult.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let lines = summary.split(whereSeparator: \.isNewline).map(String.init)
        let lowerLines = lines.map { $0.lowercased() }
        let failureCount = lowerLines.filter {
            $0.contains("failed") || $0.contains("error") || $0.contains("skip")
                || $0.contains("could not be removed") || $0.contains("permission denied")
        }.count
        let aggregateSuccess = lowerLines.contains {
            $0.contains("removed \(expectedCount) app")
                || $0.contains("would remove \(expectedCount) app")
        }
        let successCount = lowerLines.filter {
            $0.contains("successfully uninstalled")
                || $0.contains("removed ")
                || $0.contains("would remove ")
                || $0.contains("trashed ")
        }.count

        if commandResult.exitCode != 0 {
            return OperationResult(
                status: successCount > 0 ? .partial : .failed,
                summary: summary.isEmpty ? nil : summary,
                errorKey: "uninstall.error.failed"
            )
        }
        if failureCount > 0 {
            return OperationResult(
                status: successCount > 0 ? .partial : .failed,
                summary: summary.isEmpty ? nil : summary,
                errorKey: "uninstall.error.failed"
            )
        }
        guard expectedCount > 0, aggregateSuccess || successCount >= expectedCount else {
            return OperationResult(
                status: .unknown,
                summary: summary.isEmpty ? nil : summary,
                errorKey: "uninstall.error.unknown_result"
            )
        }
        return OperationResult(status: .succeeded, summary: summary.isEmpty ? nil : summary)
    }
}

enum UninstallSizeParser {
    static func bytes(from rawValue: String?) -> Int64? {
        guard let rawValue else { return nil }
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !value.isEmpty else { return nil }
        switch value.lowercased() {
        case "0", "unknown", "n/a", "na", "--", "n/a (steam-managed)":
            return nil
        default:
            break
        }

        let characters = Array(value)
        var split = 0
        while split < characters.count,
              characters[split].isNumber || characters[split] == "." {
            split += 1
        }
        let numberText = String(characters[..<split])
        guard split > 0,
              numberText.filter({ $0 == "." }).count <= 1,
              numberText != ".",
              let number = Decimal(string: numberText, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        let unit = String(characters[split...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let multiplier: Decimal
        switch unit {
        case "", "B", "BYTES": multiplier = 1
        case "K", "KB": multiplier = 1_000
        case "M", "MB": multiplier = 1_000_000
        case "G", "GB": multiplier = 1_000_000_000
        case "T", "TB": multiplier = 1_000_000_000_000
        case "KIB": multiplier = 1_024
        case "MIB": multiplier = 1_048_576
        case "GIB": multiplier = 1_073_741_824
        case "TIB": multiplier = 1_099_511_627_776
        default: return nil
        }

        let bytes = NSDecimalNumber(decimal: number * multiplier)
        let maximum = NSDecimalNumber(value: Int64.max)
        guard bytes.compare(maximum) != .orderedDescending,
              bytes.compare(NSDecimalNumber(value: 0)) == .orderedDescending else { return nil }
        return bytes.int64Value
    }
}
