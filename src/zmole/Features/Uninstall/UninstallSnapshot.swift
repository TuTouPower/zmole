import Foundation

struct UninstallApp: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let bundleID: String
    let uninstallName: String
    let path: String
    let source: String?
    let size: String?
    let version: String?
    let lastUsed: Date?

    /// Stable identity for selection and confirmation binding. The full
    /// path/bundle-id/uninstall-name triplet is still validated separately
    /// before any destructive step.
    var id: String { path }

    var sizeBytes: Int64? {
        HumanSizeParser.bytes(from: size)
    }

    /// Normalized size text, or nil when the size cannot be parsed (shown as
    /// "unknown" instead of a raw or zero value).
    var sizeText: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundle_id"
        case uninstallName = "uninstall_name"
        case path
        case source
        case size
        case version
        case lastUsedEpoch = "last_used_epoch"
    }

    init(
        name: String,
        bundleID: String,
        uninstallName: String,
        path: String,
        source: String? = nil,
        size: String? = nil,
        version: String? = nil,
        lastUsed: Date? = nil
    ) {
        self.name = name
        self.bundleID = bundleID
        self.uninstallName = uninstallName
        self.path = path
        self.source = source
        self.size = size
        self.version = version
        self.lastUsed = lastUsed
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
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        if let epoch = try? container.decodeIfPresent(Double.self, forKey: .lastUsedEpoch), epoch > 0 {
            lastUsed = Date(timeIntervalSince1970: epoch)
        } else {
            lastUsed = nil
        }
    }
}

struct UninstallPreviewSnapshot: Equatable, Sendable {
    let generation: UUID
    let apps: [UninstallApp]
    let selectedIDs: Set<String>
    let output: String

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

enum UninstallViewModelError: Error, Equatable, Sendable, ErrorKeyProviding {
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

enum UninstallListFilter {
    /// Progressive listing rows use the same search/source semantics.
    static func visibleListings(
        _ listings: [UninstallAppListing],
        search: String,
        source: String
    ) -> [UninstallAppListing] {
        listings
            .filter { source == "all" || $0.source == source }
            .filter {
                search.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(search)
                    || ($0.bundleID?.localizedCaseInsensitiveContains(search) ?? false)
                    || $0.path.localizedCaseInsensitiveContains(search)
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
        let summary = MaintenanceOutput.summary(
            stdout: commandResult.stdout,
            stderr: commandResult.stderr
        )
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


