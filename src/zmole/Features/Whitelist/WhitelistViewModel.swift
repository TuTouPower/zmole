import Combine
import Foundation

@MainActor
final class WhitelistViewModel: ObservableObject {
    @Published private(set) var document: WhitelistDocument?
    @Published private(set) var patterns: [WhitelistPattern] = []
    @Published var newPattern = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDirty = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didSave = false

    let filePath: String
    private let store: WhitelistStore
    private let moleProcess: (any MoleCommandRunning)?

    init(
        store: WhitelistStore = .live,
        moleProcess: (any MoleCommandRunning)? = nil
    ) {
        self.store = store
        self.moleProcess = moleProcess
        filePath = store.fileURL.path
    }

    func load() {
        isLoading = true
        errorMessage = nil
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
            errorMessage = error.localizedDescription
        }
    }

    func addPattern() {
        guard document != nil else { return }
        let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            errorMessage = "白名单模式不能为空"
            return
        }
        guard !pattern.hasPrefix("#") else {
            errorMessage = "注释不能作为白名单模式"
            return
        }
        guard !patterns.contains(where: { $0.value == pattern }) else {
            errorMessage = "白名单模式已存在"
            return
        }

        patterns.append(WhitelistPattern(value: pattern))
        newPattern = ""
        updateDocument()
    }

    func removePattern(id: WhitelistPattern.ID) {
        guard document != nil else { return }
        patterns.removeAll { $0.id == id }
        updateDocument()
    }

    func save() {
        guard let document else {
            errorMessage = "白名单尚未加载"
            return
        }

        isSaving = true
        errorMessage = nil
        didSave = false
        defer { isSaving = false }

        do {
            let updatedDocument = document.replacingPatterns(patterns.map(\.value))
            try store.save(updatedDocument)
            self.document = updatedDocument
            isDirty = false
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateDocument() {
        guard let document else { return }
        self.document = document.replacingPatterns(patterns.map(\.value))
        isDirty = true
        errorMessage = nil
        didSave = false
    }
}
