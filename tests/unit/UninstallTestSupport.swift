import AppKit
import Foundation
@testable import Zmole

/// Replays an old-style `uninstall --list` JSON fixture through the staging
/// protocol: identity rows first, then the resolved rows. This keeps the
/// existing fixtures meaningful while the production source streams.
enum UninstallFixture {
    static func stream(from json: String) -> UninstallListStream {
        stream(rows: rows(from: json))
    }

    static func rows(from json: String) -> [UninstallAppListing] {
        let apps = (try? JSONDecoder().decode([UninstallApp].self, from: Data(json.utf8))) ?? []
        return apps.map { app in
            UninstallAppListing(
                path: app.path,
                name: app.name,
                bundleID: app.bundleID,
                uninstallName: app.uninstallName,
                source: app.source,
                sizeText: app.size,
                version: app.version,
                lastUsed: app.lastUsed
            )
        }
    }

    static func stream(rows: [UninstallAppListing]) -> UninstallListStream {
        UninstallListStream(
            open: {
                AsyncThrowingStream { continuation in
                    for row in rows {
                        var identity = row
                        identity.bundleID = nil
                        identity.uninstallName = nil
                        identity.source = nil
                        identity.sizeText = nil
                        identity.version = nil
                        identity.lastUsed = nil
                        continuation.yield(identity)
                    }
                    for row in rows {
                        continuation.yield(row)
                    }
                    continuation.finish()
                }
            },
            cancel: {}
        )
    }
}

struct FixedTargetChecker: UninstallTargetChecking {
    let matches: Bool

    func stillMatches(_ app: UninstallApp) async -> Bool { matches }
}

struct NoopIconProvider: UninstallIconProviding {
    func icon(forAppAt path: String) async -> NSImage? { nil }
}

struct RecordingIconProvider: UninstallIconProviding {
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        func record(_ path: String) {
            lock.lock()
            defer { lock.unlock() }
            paths.append(path)
        }
        var recorded: [String] {
            lock.lock()
            defer { lock.unlock() }
            return paths
        }
    }

    let store = Store()
    let image: NSImage?

    func icon(forAppAt path: String) async -> NSImage? {
        store.record(path)
        return image
    }
}

/// Counts how many times a list scan was opened.
final class CountingListStream: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let open: @Sendable () async -> AsyncThrowingStream<UninstallAppListing, Error>

    init(rows: [UninstallAppListing]) {
        open = {
            AsyncThrowingStream { continuation in
                for row in rows {
                    continuation.yield(row)
                }
                continuation.finish()
            }
        }
    }

    var opens: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func makeStream() -> UninstallListStream {
        UninstallListStream(
            open: { [self] in
                lock.lock()
                count += 1
                lock.unlock()
                return await open()
            },
            cancel: {}
        )
    }
}

@MainActor
func makeUninstallViewModel(
    process: any MoleProcessControlling,
    listJSON: String,
    coordinator: OperationCoordinator? = nil,
    targetChecker: UninstallTargetChecking = FixedTargetChecker(matches: true),
    iconProvider: UninstallIconProviding = NoopIconProvider(),
    revealer: FileRevealing = NoopRevealer(),
    scan: (any BackgroundScanProviding)? = nil
) -> UninstallViewModel {
    UninstallViewModel(
        process: process,
        listStream: UninstallFixture.stream(from: listJSON),
        coordinator: coordinator ?? OperationCoordinator(),
        targetChecker: targetChecker,
        iconProvider: iconProvider,
        revealer: revealer,
        scan: scan
    )
}

struct NoopRevealer: FileRevealing {
    func reveal(path: String) async {}
}

struct StubProcess: MoleProcessControlling {
    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        MoleCommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}
