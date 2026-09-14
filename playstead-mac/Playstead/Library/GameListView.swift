import SwiftUI

enum LibrarySortOption: String, CaseIterable {
    case title, system, dateAdded

    /// The options the shipped library actually offers.
    ///
    /// `dateAdded` is deliberately absent: nothing in the client knows when
    /// a game was added. `CatalogueEntry` carries id/system/displayTitle/
    /// tags/members and no date at all, and the server's catalogue payload
    /// has a FROZEN key set (`Playstead.Catalogue.Payload.frozen_keys`,
    /// with a test asserting no accidental additions) that exposes
    /// `updated_at` but no `inserted_at`. Offering the control anyway would
    /// mean either inventing an order or fabricating a date -- so the case
    /// stays in the enum, `sorted(_:by:)` still honours it for a caller
    /// that has real dates, and the picker does not offer what the data
    /// cannot answer. Making it real is a protocol change (one frozen key,
    /// one client field) and is recorded as such, not smuggled in here.
    static let selectable: [LibrarySortOption] = [.title, .system]

    var controlLabel: String {
        switch self {
        case .title: return "Title"
        case .system: return "System"
        case .dateAdded: return "Date added"
        }
    }

    var controlIdentifier: String { "playstead.control.sort-\(rawValue)" }

    /// Case- and diacritic-insensitive ordering with a total tie-break, so
    /// "metroid" and "Metroid" sort together and equal keys never reshuffle.
    private static func ordered(_ lhs: String, _ rhs: String, tieBreak: (String, String)) -> Bool {
        switch lhs.localizedStandardCompare(rhs) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return tieBreak.0 < tieBreak.1
        @unknown default: return tieBreak.0 < tieBreak.1
        }
    }

    /// Orders catalogue entries for the shipped list layout. Separate from
    /// `sorted(_:by:)` because that one works on `GameListRow`, which the
    /// shipped app never builds -- the row it renders is `GameRowView`,
    /// over `CatalogueEntry` (WINDOWS #74/#79).
    ///
    /// Ties break on `id` so the order is total: two games sharing a title,
    /// or every game in a single-system view, must not reshuffle between
    /// two evaluations of the same body.
    static func sortedEntries(_ entries: [CatalogueEntry], by sort: LibrarySortOption) -> [CatalogueEntry] {
        switch sort {
        case .title:
            return entries.sorted { ordered($0.displayTitle, $1.displayTitle, tieBreak: ($0.id, $1.id)) }
        case .system:
            return entries.sorted { ordered($0.system, $1.system, tieBreak: ($0.id, $1.id)) }
        case .dateAdded:
            // No date exists locally (see `selectable`); left in the
            // catalogue's own order rather than given a fabricated one.
            return entries
        }
    }
}

struct GameListRow: Identifiable, Equatable {
    let id: String
    let title: String
    let systemID: String
    let statuses: [LibraryStatus]
    let addedAt: Date
}

/// The sortable alternative to `ShelfView`'s shelf/grid layout —
/// sortable by title, system, and date added, rendering a text status
/// label in addition to the glyph (03-UI-SPEC.md's list-view text label
/// column, never color/glyph alone).
struct GameListView: View {
    let rows: [GameListRow]
    let sort: LibrarySortOption

    static func sorted(_ rows: [GameListRow], by sort: LibrarySortOption) -> [GameListRow] {
        switch sort {
        case .title: return rows.sorted { $0.title < $1.title }
        case .system: return rows.sorted { $0.systemID < $1.systemID }
        case .dateAdded: return rows.sorted { $0.addedAt > $1.addedAt }
        }
    }

    var body: some View {
        List(Self.sorted(rows, by: sort)) { row in
            HStack(spacing: DesignTokens.Spacing.sm) {
                SystemMonogramView(systemID: row.systemID)
                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(.psLabelEmphasized)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                if let status = LibraryStatus.highestPriority(among: row.statuses) {
                    Text(status.listViewLabel)
                        .font(.psLabel)
                        .foregroundStyle(DesignTokens.textMuted)
                    StatusSlotView(statuses: row.statuses, title: row.title.isEmpty ? "Untitled" : row.title)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibleLabel(for: row))
        }
    }

    /// One accessible name per row — title, system, and the status
    /// ladder's accessible-name sentence, matching `GameCardView`'s
    /// own composition rule so a screen-reader user hears the same
    /// three facts regardless of which layout is active.
    private func accessibleLabel(for row: GameListRow) -> String {
        let title = row.title.isEmpty ? "Untitled" : row.title
        let systemName = SystemRegistry.entry(for: row.systemID).displayName
        guard let statusSentence = LibraryStatus.highestPriority(among: row.statuses)?.accessibleName(title: title) else {
            return "\(title), \(systemName)"
        }
        return "\(title), \(systemName), \(statusSentence)"
    }
}

/// The "no matches" explanatory result — never a blank pane
/// (03-UI-SPEC.md Copywriting Contract). Rendered above `GameListView`/
/// `ShelfView(.grid)` whenever `LibraryViewModel.searchResultState` is
/// non-nil.
struct NoMatchesView: View {
    let state: SearchResultState
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(state.heading).font(.psHeading).foregroundStyle(DesignTokens.textPrimary)
            Text(state.body).font(.psBody).foregroundStyle(DesignTokens.textMuted)
            Button(state.clearControlLabel, action: onClear)
                .accessibilityLabel(state.clearControlLabel)
        }
        .padding(DesignTokens.Spacing.lg)
    }
}
