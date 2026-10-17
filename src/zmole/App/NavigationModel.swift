import Foundation
import SwiftUI

/// A command palette row. The palette only navigates; it never carries a
/// destructive or execution action (the type holds nothing but a destination).
struct CommandPaletteItem: Identifiable, Equatable, Sendable {
    let destination: AppDestination

    var id: String { destination.rawValue }
    var titleKey: LocalizedStringKey { destination.titleKey }
    var subtitleKey: LocalizedStringKey { destination.subtitleKey }
    var symbol: String { destination.symbol }

    static let all: [CommandPaletteItem] = AppDestination.allCases.map(CommandPaletteItem.init)
}

/// Navigation state shared by the window shell and the app menu, so the
/// system Settings command can select the sidebar settings page.
@MainActor
final class NavigationModel: ObservableObject {
    @Published var destination: AppDestination
    @Published var isCommandPalettePresented = false
    @Published var commandQuery = ""

    init(initial: AppDestination = .overview) {
        destination = initial
    }

    var paletteItems: [CommandPaletteItem] { CommandPaletteItem.all }

    var filteredPaletteItems: [CommandPaletteItem] {
        let query = commandQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return paletteItems }
        return paletteItems.filter { item in
            let names = displayNames(for: item.destination).map { $0.lowercased() }
            let raw = item.destination.rawValue.lowercased()
            return names.contains { $0.contains(query) } || raw.contains(query)
        }
    }

    func select(_ destination: AppDestination) {
        self.destination = destination
    }

    func presentCommandPalette() {
        commandQuery = ""
        isCommandPalettePresented = true
    }

    func dismissCommandPalette() {
        isCommandPalettePresented = false
    }

    func perform(_ item: CommandPaletteItem) {
        select(item.destination)
        dismissCommandPalette()
    }

    /// Resolves the localized name for every supported language so filtering
    /// works even when the in-app language override differs from the system
    /// locale. Falls back to the resource key when unavailable.
    func displayNames(for destination: AppDestination) -> [String] {
        let key = String.LocalizationValue(destination.titleKeyString)
        return AppLanguage.allCases
            .filter { $0 != .system }
            .map { String(localized: key, locale: $0.locale) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
    }
}
