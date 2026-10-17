import Combine
import Foundation

enum WhitelistKind: Sendable {
    case clean
    case optimize

    var errorKey: String {
        switch self {
        case .clean: "whitelist.error.invalid_path"
        case .optimize: "whitelist.error.invalid_task_id"
        }
    }
}

@MainActor
final class WhitelistViewModel: ObservableObject {
    @Published private(set) var document: WhitelistDocument?
    @Published private(set) var patterns: [WhitelistPattern] = []
    @Published var newPattern = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDirty = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var didSave = false

    let filePath: String
    let kind: WhitelistKind
    private let store: WhitelistStore
    private let coordinator: OperationCoordinator

    init(
        store: WhitelistStore = .live,
        coordinator: OperationCoordinator,
        kind: WhitelistKind = .clean
    ) {
        self.store = store
        self.coordinator = coordinator
        self.kind = kind
        filePath = store.fileURL.path
    }

    func load() {
        isLoading = true
        errorMessage = nil
        errorMessageKey = nil
        didSave = false
        defer { isLoading = false }

        do {
            let loadedDocument = try store.load()
            document = loadedDocument
            patterns = loadedDocument.patterns.map { WhitelistPattern(value: $0) }
            isDirty = false
        } catch {
            document = nil
            patterns = []
            isDirty = false
            errorMessageKey = error.localizationKey
            errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
        }
    }

    @discardableResult
    func addPattern() -> Bool {
        guard document != nil else { return false }
        let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            errorMessage = "白名单模式不能为空"
            errorMessageKey = kind.errorKey
            return false
        }
        guard !pattern.hasPrefix("#") else {
            errorMessage = "注释不能作为白名单模式"
            errorMessageKey = "whitelist.error.comment"
            return false
        }
        if kind == .optimize {
            guard Self.isValidTaskID(pattern) else {
                errorMessage = "优化白名单只接受任务 id"
                errorMessageKey = kind.errorKey
                return false
            }
        }
        guard !patterns.contains(where: { $0.value == pattern }) else {
            errorMessage = "白名单模式已存在"
            errorMessageKey = "whitelist.error.duplicate"
            return false
        }

        patterns.append(WhitelistPattern(value: pattern))
        newPattern = ""
        updateDocument()
        return true
    }

    static func isValidTaskID(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    func removePattern(id: WhitelistPattern.ID) {
        guard document != nil else { return }
        patterns.removeAll { $0.id == id }
        updateDocument()
    }

    func save() {
        guard let document else {
            errorMessage = "白名单尚未加载"
            errorMessageKey = nil
            return
        }

        guard let lease = coordinator.acquire(kind == .optimize ? .optimizeWhitelist : .cleanWhitelist) else {
            errorMessage = nil
            errorMessageKey = "operation.error.busy"
            didSave = false
            return
        }
        isSaving = true
        errorMessage = nil
        errorMessageKey = nil
        didSave = false
        defer {
            lease.release()
            isSaving = false
            coordinator.invalidatePreviews()
        }

        do {
            let updatedDocument = document.replacingPatterns(patterns.map(\.value))
            try store.save(updatedDocument)
            lease.markDataModified()
            self.document = updatedDocument
            isDirty = false
            didSave = true
        } catch {
            errorMessageKey = error.localizationKey
            errorMessage = error.localizationKey == nil ? error.localizedDescription : nil
        }
    }

    private func updateDocument() {
        guard let document else { return }
        self.document = document.replacingPatterns(patterns.map(\.value))
        isDirty = true
        errorMessage = nil
        errorMessageKey = nil
        didSave = false
    }
}
