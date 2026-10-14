import SwiftUI

/// Navigation section identifiers, in the UI-SPEC's frozen order.
enum SidebarSection: Hashable {
    case home
    case recentlyPlayed
    case favorites
    case collections
    case queue
    case recent
    case downloads
    case system(String)
    case unidentified
    case settings
}

struct SidebarEntry: Identifiable, Hashable {
    let section: SidebarSection
    let label: String
    var id: SidebarSection { section }

    var accessibilityIdentifier: String {
        switch section {
        case .recentlyPlayed: "playstead.sidebar.continue"
        case .favorites: "playstead.sidebar.favorites"
        case .collections: "playstead.sidebar.collections"
        case .queue: "playstead.sidebar.queue"
        case .recent: "playstead.sidebar.recent"
        case .home: "playstead.sidebar.home"
        case .downloads: "playstead.sidebar.downloads"
        case .system(let id): "playstead.sidebar.system.\(id)"
        case .unidentified: "playstead.sidebar.unidentified"
        case .settings: "playstead.sidebar.settings"
        }
    }

    var symbolName: String {
        switch section {
        case .home: "square.grid.2x2"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .favorites: "star"
        case .collections: "square.stack"
        case .queue: "list.bullet"
        case .recent: "clock"
        case .downloads: "arrow.down.circle"
        case .system: "gamecontroller"
        case .unidentified: "questionmark.folder"
        case .settings: "gearshape"
        }
    }
}

/// The canonical source-list destinations from the shared UI contract.
/// Library contains browse and curation; Systems contains only system
/// filters; Manage groups downloads and app settings after the systems
/// users browse most often. Unidentified remains at the end of Systems.
struct SidebarView: View {
    let nonEmptySystemIDs: Set<String>
    let hasUnidentified: Bool
    @Binding var selection: SidebarSection?

    static func entries(nonEmptySystemIDs: Set<String>, hasUnidentified: Bool) -> [SidebarEntry] {
        var result: [SidebarEntry] = [
            SidebarEntry(section: .home, label: "All Games"),
            SidebarEntry(section: .recentlyPlayed, label: "Recently Played"),
            SidebarEntry(section: .favorites, label: "Favorites"),
            SidebarEntry(section: .collections, label: "Collections"),
            SidebarEntry(section: .queue, label: "Queue"),
            SidebarEntry(section: .recent, label: "Recent")
        ]
        for entry in SystemRegistry.all where nonEmptySystemIDs.contains(entry.id) {
            result.append(SidebarEntry(section: .system(entry.id), label: entry.displayName))
        }
        if hasUnidentified {
            result.append(SidebarEntry(section: .unidentified, label: "Unidentified"))
        }
        result.append(SidebarEntry(section: .downloads, label: "Downloads"))
        result.append(SidebarEntry(section: .settings, label: "Settings"))
        return result
    }

    var entries: [SidebarEntry] {
        Self.entries(nonEmptySystemIDs: nonEmptySystemIDs, hasUnidentified: hasUnidentified)
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(entries.filter { Self.isLibrary($0.section) }) { entry in
                    row(for: entry)
                }
            }

            if entries.contains(where: { if case .system = $0.section { true } else { false } })
                || entries.contains(where: { $0.section == .unidentified }) {
                Section("Systems") {
                    ForEach(entries.filter { Self.isSystem($0.section) }) { entry in
                        row(for: entry)
                    }
                }
            }

            Section("Manage") {
                ForEach(entries.filter { Self.isManage($0.section) }) { entry in
                    row(for: entry)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library sections")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.sidebar)
    }

    @ViewBuilder
    private func row(for entry: SidebarEntry) -> some View {
        Label(entry.label, systemImage: entry.symbolName)
            .tag(entry.section)
            .accessibilityLabel(entry.label)
            .accessibilityIdentifier(entry.accessibilityIdentifier)
    }

    private static func isLibrary(_ section: SidebarSection) -> Bool {
        switch section {
        case .home, .recentlyPlayed, .favorites, .collections, .queue, .recent: true
        case .downloads, .system, .unidentified, .settings: false
        }
    }

    private static func isManage(_ section: SidebarSection) -> Bool {
        switch section {
        case .downloads, .settings: true
        case .home, .recentlyPlayed, .favorites, .collections, .queue, .recent, .system, .unidentified: false
        }
    }

    private static func isSystem(_ section: SidebarSection) -> Bool {
        switch section {
        case .system, .unidentified: true
        case .home, .recentlyPlayed, .favorites, .collections, .queue, .recent, .downloads, .settings: false
        }
    }
}
