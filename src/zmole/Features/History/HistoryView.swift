import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel

    init(viewModel: HistoryViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? HistoryViewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MolePageHead(
                title: "history.title",
                subtitle: "history.subtitle"
            ) {
                Button {
                    exportJSON()
                } label: {
                    Label("history.export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.rawJSON == nil)
                Button("history.refresh") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MoleTheme.accent)
                .disabled(viewModel.isLoading)
            }
            .padding(.bottom, 10)

            if viewModel.isLoading && viewModel.snapshot == nil {
                ProgressView("history.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = viewModel.snapshot {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorKey = viewModel.errorMessageKey {
                        UtilityNotice(title: LocalizedStringKey(errorKey), isError: true)
                    } else if let errorMessage = viewModel.errorMessage {
                        UtilityNotice(title: "history.error_title", detail: errorMessage, isError: true)
                    }
                    HistorySnapshotContent(snapshot: snapshot)
                    UtilityNotice(title: "history.info_note", symbol: "shield", isInfo: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorKey = viewModel.errorMessageKey {
                VStack(spacing: 12) {
                    UtilityNotice(title: LocalizedStringKey(errorKey), isError: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                Spacer()
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    UtilityNotice(title: "history.error_title", detail: errorMessage, isError: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                Spacer()
            } else {
                ProgressView("history.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 1180, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MoleTheme.background)
        .overlay(alignment: .top) {
            if viewModel.showBusyNotice {
                RecoverableBusyNotice().padding(16)
            }
        }
        .navigationTitle("sidebar.history")
        .task {
            guard viewModel.snapshot == nil, !viewModel.isLoading else { return }
            await viewModel.refresh()
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mole-history.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.export(to: url)
        }
    }
}

private struct HistorySnapshotContent: View {
    let snapshot: HistorySnapshot

    var body: some View {
        let rows = HistoryTable.rows(from: snapshot.displayState)
        if rows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("history.empty")
                    .font(.title2)
                Text("history.empty_summary")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            UtilityPanel {
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                tableRow(row)
                                Divider().padding(.leading, 18)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("history.column_date").frame(width: 200, alignment: .leading)
            Text("history.column_action").frame(maxWidth: .infinity, alignment: .leading)
            Text("history.column_result").frame(width: 110, alignment: .trailing)
            Text("history.column_status").frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 10))
        .foregroundStyle(MoleTheme.subtle)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func tableRow(_ row: HistoryTableRow) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: row.date)
                .frame(width: 200, alignment: .leading)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(MoleTheme.muted)
            actionCell(row)
            Text(verbatim: row.result)
                .frame(width: 110, alignment: .trailing)
                .monospacedDigit()
            statusCell(row)
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(MoleTheme.accentStrong)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func statusCell(_ row: HistoryTableRow) -> some View {
        switch row.status {
        case .done:
            Text("history.status_done")
        case let .verbatim(status):
            Text(verbatim: status)
        }
    }

    @ViewBuilder
    private func actionCell(_ row: HistoryTableRow) -> some View {
        switch row.kind {
        case .session:
            Text(verbatim: row.action)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .deletion:
            Text(verbatim: row.action)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(row.fullPath ?? row.action)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
