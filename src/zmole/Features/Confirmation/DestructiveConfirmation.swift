import SwiftUI

final class DestructiveConfirmationFlow {
    private let executeAction: () -> Void
    private(set) var isPending = true

    init(executeAction: @escaping () -> Void) {
        self.executeAction = executeAction
    }

    func cancel() {
        isPending = false
    }

    func confirm() {
        guard isPending else { return }
        isPending = false
        executeAction()
    }
}

struct DestructiveConfirmationView: View {
    let title: LocalizedStringKey
    let summary: LocalizedStringKey
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title)
            Text(summary)
                .foregroundStyle(.secondary)
            HStack {
                Button("action.cancel") {
                    onCancel()
                }
                Button("action.confirm", role: .destructive) {
                    onConfirm()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
    }
}
