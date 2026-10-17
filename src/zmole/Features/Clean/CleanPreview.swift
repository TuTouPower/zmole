import Foundation

enum CleanPreviewStoreError: Error, Equatable, LocalizedError, Sendable {
    case missingFile
    case emptyFile
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "clean 扫描没有写出列表文件"
        case .emptyFile:
            return "clean 扫描列表为空"
        case .invalidUTF8:
            return "clean 列表不是有效的 UTF-8 文本"
        }
    }
}

struct CleanPreviewGeneration: Equatable, Codable, Sendable {
    let id: UUID
    let fileURL: URL
}

struct CleanPreviewSnapshot: Equatable, Codable, Sendable {
    let generation: CleanPreviewGeneration
    let contents: String
    let entries: [String]
    let sections: [CleanPreviewSection]

    var reclaimBytes: Int64 {
        sections.reduce(0) { $0 + $1.reclaimBytes }
    }

    var reclaimText: String {
        ByteCountFormatter.string(fromByteCount: reclaimBytes, countStyle: .file)
    }
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

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CleanPreviewStoreError.missingFile
        }
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
        guard !entries.isEmpty else {
            throw CleanPreviewStoreError.emptyFile
        }

        return CleanPreviewSnapshot(
            generation: generation,
            contents: contents,
            entries: entries,
            sections: CleanPreviewParser.sections(from: contents)
        )
    }
}
