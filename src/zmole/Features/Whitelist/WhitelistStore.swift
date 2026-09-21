import Foundation

enum WhitelistStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "白名单文件不是有效的 UTF-8 文本"
        }
    }
}

struct WhitelistStore: Sendable {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static var live: WhitelistStore {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mole/whitelist")
        return WhitelistStore(fileURL: fileURL)
    }

    func load() throws -> WhitelistDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return WhitelistDocument(lines: WhitelistDocument.defaultHeader)
        }

        let data = try Data(contentsOf: fileURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            throw WhitelistStoreError.invalidUTF8
        }
        return WhitelistDocument(contents: contents)
    }

    func save(_ document: WhitelistDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try document.serializedContents.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
    }
}
