import Foundation

enum CleanPreviewStoreError: Error, Equatable, LocalizedError, Sendable {
    case missingFile
    case emptyFile
    case invalidUTF8
    case changedSincePreview

    var errorKey: String {
        switch self {
        case .missingFile:
            return "clean.error.missing_list"
        case .emptyFile:
            return "clean.error.empty_list"
        case .invalidUTF8:
            return "clean.error.invalid_list"
        case .changedSincePreview:
            return "clean.error.changed_list"
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "本次 clean 预览没有写出列表文件"
        case .emptyFile:
            return "本次 clean 预览列表为空"
        case .invalidUTF8:
            return "clean 预览文件不是有效的 UTF-8 文本"
        case .changedSincePreview:
            return "预览列表已变化，请重新预览"
        }
    }
}

struct CleanPreviewGeneration: Equatable, Sendable {
    let id: UUID
    let fileURL: URL
}

struct CleanPreviewSnapshot: Equatable, Sendable {
    let generation: CleanPreviewGeneration
    let contents: String
    let entries: [String]
}

struct CleanPreviewStore: Sendable {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static var live: CleanPreviewStore {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mole/clean-list.txt")
        return CleanPreviewStore(fileURL: fileURL)
    }

    func begin() throws -> CleanPreviewGeneration {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        return CleanPreviewGeneration(id: UUID(), fileURL: fileURL)
    }

    func read(_ generation: CleanPreviewGeneration) throws -> CleanPreviewSnapshot {
        guard generation.fileURL == fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CleanPreviewStoreError.missingFile
        }

        let data = try Data(contentsOf: fileURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            throw CleanPreviewStoreError.invalidUTF8
        }
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanPreviewStoreError.emptyFile
        }

        let entries = contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("===")
            }

        return CleanPreviewSnapshot(
            generation: generation,
            contents: contents,
            entries: entries
        )
    }

    func verifyUnchanged(_ snapshot: CleanPreviewSnapshot) throws {
        let data = try Data(contentsOf: fileURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            throw CleanPreviewStoreError.invalidUTF8
        }
        guard contents == snapshot.contents else {
            throw CleanPreviewStoreError.changedSincePreview
        }
    }
}
