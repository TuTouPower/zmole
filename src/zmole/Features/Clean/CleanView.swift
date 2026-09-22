import SwiftUI

enum CleanViewCopy {
    static let executionNoteKey = "clean.execution_note"
}

@MainActor
struct CleanView: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        Group {
            if viewModel.isConfirmationPresented {
                DestructiveConfirmationView(
                    title: "clean.confirm_title",
                    summary: "clean.confirm_summary",
                    onConfirm: { Task { await viewModel.confirmExecution() } },
                    onCancel: { viewModel.cancelConfirmation() }
                )
            } else {
                content
            }
        }
        .navigationTitle("mode.clean")
        .toolbar {
            ToolbarItem {
                if viewModel.isPreviewing {
                    Button("clean.cancel") { Task { await viewModel.cancelPreview() } }
                } else if viewModel.isExecuting {
                    Button("clean.cancel") { Task { await viewModel.cancelExecution() } }
                } else {
                    Button {
                        Task { await viewModel.previewClean() }
                    } label: {
                        Label("clean.preview", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(UtilityStyle.accent)
                    .disabled(viewModel.isConfirmationPresented)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(UtilityStyle.accent)
                Text(LocalizedStringKey(CleanViewCopy.executionNoteKey))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UtilityStyle.selection, in: RoundedRectangle(cornerRadius: 8))
            if viewModel.isPreviewing {
                UtilityPanel {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("clean.previewing").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            } else if viewModel.isExecuting {
                UtilityPanel {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("clean.executing").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            } else if let preview = viewModel.preview {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("clean.preview_title").font(.system(size: 16, weight: .semibold))
                            Text("clean.preview_scope").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        UtilityBadge(title: "clean.preview_ready", symbol: "checkmark")
                    }
                    HStack(spacing: 4) {
                        Text(verbatim: "\(preview.entries.count)")
                            .monospacedDigit()
                        Text("clean.preview_count")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    List {
                        ForEach(previewGroups) { group in
                            Section(group.category) {
                                ForEach(group.entries, id: \.self) { entry in
                                    Label {
                                        Text(entry).font(.system(size: 12, design: .monospaced))
                                            .textSelection(.enabled)
                                    } icon: {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(UtilityStyle.accent)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 260)
                    HStack {
                        Spacer()
                        Button("clean.execute", role: .destructive) { viewModel.requestConfirmation() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(!viewModel.canConfirm)
                    }
                }
                .padding(16)
                .background(UtilityStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(UtilityStyle.separator))
            } else {
                UtilityEmptyState(symbol: "sparkles", title: "clean.empty", message: "clean.preview_hint")
            }

            if let errorMessageKey = viewModel.errorMessageKey {
                UtilityNotice(
                    title: LocalizedStringKey(errorMessageKey),
                    detail: viewModel.executionSummary,
                    isError: true
                )
            } else if let errorMessage = viewModel.errorMessage {
                UtilityNotice(title: "clean.error_title", detail: errorMessage, isError: true)
            }
            if let executionSummary = viewModel.executionSummary, !executionSummary.isEmpty {
                UtilityNotice(title: "clean.result", detail: executionSummary, symbol: "checkmark.circle")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(UtilityStyle.background)
    }

    private var previewGroups: [CleanPreviewGroup] {
        let grouped = Dictionary(grouping: viewModel.preview?.entries ?? []) { entry in
            let components = entry.split(separator: "/").map(String.init)
            if components.contains(where: { $0.localizedCaseInsensitiveContains("cache") }) { return "Caches" }
            if components.contains(where: { $0.localizedCaseInsensitiveContains("log") }) { return "Logs" }
            return "Other paths"
        }
        return grouped.keys.sorted().map { CleanPreviewGroup(category: $0, entries: grouped[$0] ?? []) }
    }
}

private struct CleanPreviewGroup: Identifiable {
    let category: String
    let entries: [String]
    var id: String { category }
}
