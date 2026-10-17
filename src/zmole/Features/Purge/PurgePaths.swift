import Combine
import Foundation

enum PurgePathsError: Error, Equatable, LocalizedError, Sendable, ErrorKeyProviding {
    case invalidPath(String)
    case invalidUTF8

    var errorKey: String {
        switch self {
        case .invalidPath: "purge.paths.error.invalid"
        case .invalidUTF8: "purge.paths.error.encoding"
        }
    }

    var errorDescription: String? {
        switch self {
        case let .invalidPath(path): "扫描目录必须是绝对路径或 ~/ 开头：\(path)"
        case .invalidUTF8: "purge_paths 文件不是有效的 UTF-8 文本"
        }
    }
}

struct PurgePathsStore: Sendable {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static var live: PurgePathsStore {
        PurgePathsStore(
            fileURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mole/purge_paths")
        )
    }

    func load() throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            throw PurgePathsError.invalidUTF8
        }
        return contents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func save(_ paths: [String]) throws {
        for path in paths {
            guard path.hasPrefix("/") || path.hasPrefix("~/") else {
                throw PurgePathsError.invalidPath(path)
            }
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = (["# mole project cleanup scan directories"] + paths).joined(separator: "\n") + "\n"
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

@MainActor
final class PurgePathsViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var errorKey: String?
    @Published private(set) var didSave = false
    /// False until a load succeeds; `save` is refused so a failed load can
    /// never overwrite the file with the (possibly empty) editor contents.
    @Published private(set) var isLoaded = false

    private let store: PurgePathsStore
    private let coordinator: OperationCoordinator

    init(store: PurgePathsStore, coordinator: OperationCoordinator) {
        self.store = store
        self.coordinator = coordinator
    }

    var filePath: String { store.fileURL.path }

    func load() {
        didSave = false
        do {
            text = try store.load().joined(separator: "\n")
            errorKey = nil
            isLoaded = true
        } catch {
            errorKey = (error as? PurgePathsError)?.errorKey ?? "purge.paths.error.load"
            isLoaded = false
        }
    }

    /// Validates and writes the edited text under the shared write lease, so it
    /// cannot overlap another write and any existing purge preview is expired.
    /// On failure the edited text stays in the view model.
    @discardableResult
    func save() -> Bool {
        guard isLoaded else { return false }
        let paths = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard let lease = coordinator.acquire(.purge) else {
            errorKey = "operation.error.busy"
            didSave = false
            return false
        }
        defer {
            lease.release()
            coordinator.invalidatePreviews()
        }
        do {
            try store.save(paths)
            errorKey = nil
            didSave = true
            return true
        } catch {
            errorKey = (error as? PurgePathsError)?.errorKey ?? "purge.paths.error.invalid"
            didSave = false
            return false
        }
    }
}
