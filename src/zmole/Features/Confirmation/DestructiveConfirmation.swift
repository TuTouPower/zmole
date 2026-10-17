import SwiftUI

struct DestructiveConfirmationView: View {
    let title: LocalizedStringKey
    let summary: LocalizedStringKey
    var detail: String? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title)
            Text(summary)
                .foregroundStyle(.secondary)
            if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.system(size: 13, weight: .medium))
            }
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
