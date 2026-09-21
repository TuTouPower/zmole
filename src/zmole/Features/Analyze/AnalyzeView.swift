import Foundation
import SwiftUI

@MainActor
struct AnalyzeView: View {
    @StateObject private var viewModel: AnalyzeViewModel

    init(viewModel: AnalyzeViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AnalyzeViewModel())
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.snapshot == nil {
                ProgressView("analyze.loading")
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("analyze.error_title")
                        .font(.title)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = viewModel.snapshot {
                AnalyzeSnapshotContent(displayState: snapshot.displayState) { entry in
                    Task { await viewModel.openDirectory(entry) }
                }
            } else {
                ProgressView("analyze.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("sidebar.analyze")
        .toolbar {
            ToolbarItem {
                if viewModel.canGoBack {
                    Button("analyze.back") {
                        Task { await viewModel.goBack() }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            ToolbarItem {
                Button("analyze.refresh") {
                    Task { await viewModel.loadOverview() }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            guard viewModel.snapshot == nil, !viewModel.isLoading else { return }
            await viewModel.loadOverview()
        }
    }
}

private struct AnalyzeSnapshotContent: View {
    let displayState: AnalyzeDisplayState
    let onOpenDirectory: (AnalyzeEntry) -> Void

    var body: some View {
        List {
            Section {
                Text(displayState.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text(displayState.overview ? "analyze.overview" : "analyze.path")
            }

            Section("analyze.entries") {
                ForEach(displayState.entries) { entry in
                    if entry.isDirectory {
                        Button {
                            onOpenDirectory(entry)
                        } label: {
                            AnalyzeEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    } else {
                        AnalyzeEntryRow(entry: entry)
                    }
                }
            }
        }
    }
}

private struct AnalyzeEntryRow: View {
    let entry: AnalyzeEntry

    var body: some View {
        HStack {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
            Text(entry.name)
                .lineLimit(1)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
