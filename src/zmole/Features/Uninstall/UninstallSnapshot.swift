import Foundation

struct UninstallApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let bundleID: String
    let uninstallName: String
    let path: String

    var id: String {
        [path, bundleID, uninstallName].joined(separator: "\u{1F}")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundle_id"
        case uninstallName = "uninstall_name"
        case path
    }
}

struct UninstallListSnapshot: Equatable, Sendable {
    let generation: UUID
    let apps: [UninstallApp]
}

struct UninstallPreviewSnapshot: Equatable, Sendable {
    let generation: UUID
    let target: UninstallApp
    let selectedIDs: Set<String>
    let output: String
}

enum UninstallViewModelError: Error, Equatable, Sendable {
    case noSelection
    case ambiguousName
    case changedTarget
    case invalidList
    case missingMole

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
