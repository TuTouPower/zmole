import SwiftUI

@MainActor
struct CommandPaletteView: View {
    @ObservedObject var navigation: NavigationModel
    @FocusState private var searchFocused: Bool
    @State private var selectedIndex = 0

    private var items: [CommandPaletteItem] { navigation.filteredPaletteItems }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { navigation.dismissCommandPalette() }

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(MoleTheme.subtle)
                    TextField("palette.placeholder", text: $navigation.commandQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                        .onSubmit { openFirstResult() }
                }
                .padding(.horizontal, 16)
                .frame(height: 50)

                Divider()

                if items.isEmpty {
                    VStack(spacing: 5) {
                        Text("palette.empty_title")
                            .font(.system(size: 13, weight: .semibold))
                        Text("palette.empty_message")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.subtle)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                resultRow(item, isSelected: index == clampedSelection)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }

                Divider()

                HStack(spacing: 15) {
                    Text("palette.hint.navigate")
                    Text("palette.hint.open")
                    Text("palette.hint.close")
                }
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.subtle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .frame(width: 520)
            .background(MoleTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(MoleTheme.line))
            .shadow(color: .black.opacity(0.2), radius: 40, y: 20)
            .padding(.top, 110)
        }
        .onAppear { searchFocused = true }
        .onChange(of: navigation.commandQuery) { _ in selectedIndex = 0 }
        .onMoveCommand { direction in
            switch direction {
            case .down: moveSelection(by: 1)
            case .up: moveSelection(by: -1)
            default: break
            }
        }
        .onExitCommand { navigation.dismissCommandPalette() }
    }

    private var clampedSelection: Int {
        guard !items.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), items.count - 1)
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(clampedSelection + delta, 0), items.count - 1)
    }

    private func resultRow(_ item: CommandPaletteItem, isSelected: Bool) -> some View {
        Button {
            navigation.perform(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13))
                    .frame(width: 26, height: 26)
                    .background(MoleTheme.surface3, in: RoundedRectangle(cornerRadius: 8))
                Text(item.titleKey)
                    .font(.system(size: 12))
                Spacer(minLength: 0)
                Text(item.subtitleKey)
                    .font(.system(size: 10))
                    .foregroundStyle(MoleTheme.subtle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? MoleTheme.surface3 : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openFirstResult() {
        let index = clampedSelection
        guard items.indices.contains(index) else { return }
        navigation.perform(items[index])
    }
}
