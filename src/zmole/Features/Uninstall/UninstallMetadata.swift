import AppKit
import CoreServices
import Foundation

struct UninstallAppMetadata: Equatable, Sendable {
    let version: String?
    let lastUsed: Date?
}

protocol UninstallMetadataProviding: Sendable {
    func metadata(forAppAt path: String) async -> UninstallAppMetadata
}

protocol FileRevealing: Sendable {
    func reveal(path: String) async
}

/// Reads version and last-used from on-device metadata only. Missing fields stay
/// nil so the UI can show "unknown" instead of invented values.
struct LiveUninstallMetadataProvider: UninstallMetadataProviding {
    func metadata(forAppAt path: String) async -> UninstallAppMetadata {
        await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            let bundle = Bundle(url: url)
            let shortVersion = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
            let bundleVersion = bundle?.infoDictionary?["CFBundleVersion"] as? String
            let version = [shortVersion, bundleVersion]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return UninstallAppMetadata(version: version, lastUsed: Self.lastUsedDate(at: url))
        }.value
    }

    static func lastUsedDate(at url: URL) -> Date? {
        guard let item = NSMetadataItem(url: url) else { return nil }
        return item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
    }
}

struct LiveFileRevealer: FileRevealing {
    func reveal(path: String) async {
        await MainActor.run {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
