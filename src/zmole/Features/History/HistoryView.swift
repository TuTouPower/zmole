import Foundation
import SwiftUI

@MainActor
struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel

    init(viewModel: HistoryViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? HistoryViewModel())
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.snapshot == nil {
                ProgressView("history.loading")
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("history.error_title")
                        .font(.title)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = viewModel.snapshot {
                HistorySnapshotContent(snapshot: snapshot)
            } else {
                ProgressView("history.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("sidebar.history")
        .toolbar {
            ToolbarItem {
                Button("history.refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            guard viewModel.snapshot == nil, !viewModel.isLoading else { return }
            await viewModel.refresh()
        }
    }
}

private struct HistorySnapshotContent: View {
    let snapshot: HistorySnapshot

    var body: some View {
        switch snapshot.displayState {
        case .empty:
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("history.empty")
                    .font(.title2)
                Text("history.empty_summary")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .content(sessions, deletions):
            List {
                if !sessions.isEmpty {
                    Section("history.sessions") {
                        ForEach(Array(sessions.enumerated()), id: \.offset) {
                            _, session in
                            HistorySessionRow(session: session)
                        }
                    }
                }

                if !deletions.isEmpty {
                    Section("history.deletions") {
                        ForEach(Array(deletions.enumerated()), id: \.offset) {
                            _, deletion in
                            HistoryDeletionRow(deletion: deletion)
                        }
                    }
                }
            }
        }
    }
}

private struct HistorySessionRow: View {
    let session: HistorySessionDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.command)
                .font(.headline)
            Text(session.dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if let items = session.items {
                    LabeledContent("history.items") {
                        Text("\(items)")
                    }
                }
                if let size = session.size {
                    LabeledContent("history.size") {
                        Text(size)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDeletionRow: View {
    let deletion: HistoryDeletionDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(deletion.path)
                .font(.headline)
                .textSelection(.enabled)
            Text("\(deletion.timestamp) · \(deletion.mode) · \(deletion.status)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let sizeKB = deletion.sizeKB {
                Text(ByteCountFormatter.string(fromByteCount: sizeKB * 1024, countStyle: .file))
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
