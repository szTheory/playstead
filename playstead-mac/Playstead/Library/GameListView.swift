import SwiftUI

enum LibrarySortOption: String, CaseIterable {
    case title, system, dateAdded
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
        }
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
