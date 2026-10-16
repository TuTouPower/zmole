import AppKit
import Foundation

protocol FileRevealing: Sendable {
    func reveal(path: String) async
}

struct LiveFileRevealer: FileRevealing {
    func reveal(path: String) async {
        await MainActor.run {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// App icons load after the list is already interactive; list rendering never
/// waits on a synchronous icon read.
protocol UninstallIconProviding: Sendable {
    func icon(forAppAt path: String) async -> NSImage?
}

struct LiveUninstallIconProvider: UninstallIconProviding {
    func icon(forAppAt path: String) async -> NSImage? {
        await Task.detached(priority: .utility) {
            NSWorkspace.shared.icon(forFile: path)
        }.value
    }
}

/// Cheap confirm-time identity check: the listed path still exists and its
/// bundle identity is unchanged. It never runs a full list scan; a change
/// refuses the execution and the caller re-lists.
protocol UninstallTargetChecking: Sendable {
    func stillMatches(_ app: UninstallApp) async -> Bool
}

struct LiveUninstallTargetChecker: UninstallTargetChecking {
    func stillMatches(_ app: UninstallApp) async -> Bool {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: app.path) else { return false }
            guard !app.bundleID.isEmpty else { return true }
            guard let bundle = Bundle(url: URL(fileURLWithPath: app.path)) else { return false }
            return bundle.bundleIdentifier == app.bundleID
        }.value
    }
}
