import SwiftUI

/// Navigation section identifiers, in the UI-SPEC's frozen order.
enum SidebarSection: Hashable {
    case home
    case continuePlaying
    case favorites
    case collections
    case queue
    case recent
    case system(String)
    case unidentified
}

struct SidebarEntry: Identifiable, Hashable {
    let section: SidebarSection
    let label: String
    var id: SidebarSection { section }
}

/// The one canonical source-list order (03-UI-SPEC.md Navigation & IA,
/// D-14), identical on both clients: Home, Continue, Favorites,
/// Collections, Queue, Recent, then non-empty systems in the frozen
/// registry order, then Unidentified last (only when at least one
/// unidentified asset set exists — hidden entirely otherwise, since
/// "unidentified" is itself a status, not a curated noun the user chose).
/// Home and Continue are two separate entries, never merged.
struct SidebarView: View {
    let nonEmptySystemIDs: Set<String>
    let hasUnidentified: Bool
    @Binding var selection: SidebarSection?

    static func entries(nonEmptySystemIDs: Set<String>, hasUnidentified: Bool) -> [SidebarEntry] {
        var result: [SidebarEntry] = [
            SidebarEntry(section: .home, label: "Home"),
            SidebarEntry(section: .continuePlaying, label: "Continue"),
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
        return result
    }

    var entries: [SidebarEntry] {
        Self.entries(nonEmptySystemIDs: nonEmptySystemIDs, hasUnidentified: hasUnidentified)
    }

    var body: some View {
        List(entries, selection: $selection) { entry in
            Text(entry.label)
                .font(.psLabelEmphasized)
                .tag(entry.section)
                .accessibilityLabel(entry.label)
        }
        .listStyle(.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library sections")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.sidebar)
    }
}
