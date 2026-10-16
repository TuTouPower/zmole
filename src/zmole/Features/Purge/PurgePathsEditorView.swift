import SwiftUI

struct PurgePathsEditorView: View {
    @ObservedObject var viewModel: PurgePathsViewModel
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("purge.paths.title").font(.system(size: 15, weight: .semibold))
            Text(verbatim: viewModel.filePath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("purge.paths.hint").font(.system(size: 11)).foregroundStyle(.secondary)
            TextEditor(text: $viewModel.text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 420, minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            if let errorKey = viewModel.errorKey {
                UtilityNotice(title: LocalizedStringKey(errorKey), isError: true)
            }
            HStack {
                if viewModel.didSave {
                    Text("purge.paths.saved").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("purge.paths.cancel") { onClose() }
                Button("purge.paths.save") { viewModel.save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear { viewModel.load() }
    }
}
