import SwiftUI

@MainActor
struct WhitelistView: View {
    @StateObject private var viewModel: WhitelistViewModel

    init(viewModel: WhitelistViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? WhitelistViewModel())
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("whitelist.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.document == nil {
                VStack(spacing: 12) {
                    Text("whitelist.error_title")
                        .font(.title)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = viewModel.document {
                List {
                    Section {
                        Text("whitelist.clean_summary")
                            .foregroundStyle(.secondary)
                        Text(viewModel.filePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text("whitelist.clean_title")
                    }

                    if !document.comments.isEmpty {
                        Section("whitelist.comments") {
                            ForEach(Array(document.comments.enumerated()), id: \.offset) { _, comment in
                                Text(comment)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    Section("whitelist.patterns") {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                        if viewModel.patterns.isEmpty {
                            Text("whitelist.empty")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.patterns) { pattern in
                                HStack {
                                    Text(pattern.value)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button(role: .destructive) {
                                        viewModel.removePattern(id: pattern.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("whitelist.remove")
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView("whitelist.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("sidebar.whitelist")
        .toolbar {
            ToolbarItem {
                Button("whitelist.save") {
                    viewModel.save()
                }
                .disabled(viewModel.document == nil || !viewModel.isDirty || viewModel.isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.document != nil {
                HStack {
                    TextField("whitelist.add_placeholder", text: $viewModel.newPattern)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.addPattern() }
                    Button("whitelist.add") {
                        viewModel.addPattern()
                    }
                    .disabled(viewModel.newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.bar)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.didSave {
                Text("whitelist.saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing)
                    .padding(.bottom, 66)
            }
        }
        .task {
            guard viewModel.document == nil, !viewModel.isLoading else { return }
            viewModel.load()
        }
    }
}
