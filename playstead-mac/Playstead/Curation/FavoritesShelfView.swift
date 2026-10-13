import SwiftUI

/// Renders `FavoritesViewModel`'s favorites as actionable library rows;
/// this view maps a favorite row and its catalogue entry into a
/// `ShelfItem`, and owns the empty-state copy from 03-UI-SPEC.md's
/// Copywriting Contract.
struct FavoritesShelfView: View {
    let viewModel: FavoritesViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]
    var onBrowseLibrary: () -> Void = {}
    var controllerFocusedAssetSetID: String? = nil
    var controllerCommand: LibraryControllerCommand? = nil
    /// Injected rather than derived here, so the shelf stays free of the
    /// stores: `LibraryShellView` passes
    /// `AppEnvironment.libraryStatuses(for:)`, the same derivation the grid
    /// and the list row use. The empty default is a test convenience only —
    /// it was also, for a while, what the shipped app passed (WINDOWS #72).
    var statuses: (String) -> [LibraryStatus] = { _ in [] }

    static let emptyExplanation = "Favorite a game to see it here."

    var items: [ShelfItem] {
        Self.items(favorites: viewModel.favorites, catalogueByAssetSetID: catalogueByAssetSetID, statuses: statuses)
    }

    /// Pure so it can be asserted directly by tests without hosting a
    /// live view — matches the codebase's established pattern
    /// (`GameRowView` action-label helpers, `FilterChipRow.isSelected`, etc.)
    static func items(
        favorites: [CurationFavoriteRow],
        catalogueByAssetSetID: [String: CatalogueEntry],
        statuses: (String) -> [LibraryStatus]
    ) -> [ShelfItem] {
        favorites.compactMap { favorite in
            guard let entry = catalogueByAssetSetID[favorite.assetSetID] else { return nil }
            return ShelfItem(
                id: entry.id,
                title: entry.displayTitle,
                systemID: entry.system,
                isUnidentified: entry.system == "unknown" || entry.displayTitle.isEmpty,
                statuses: statuses(favorite.assetSetID)
            )
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Favorites", systemImage: "heart")
                } description: {
                    Text(Self.emptyExplanation)
                } actions: {
                    Button("Browse Library", action: onBrowseLibrary)
                }
            } else {
                List {
                    ForEach(items) { item in
                        if let entry = catalogueByAssetSetID[item.id] {
                            GameRowView(
                                entry: entry,
                                isControllerFocused: controllerFocusedAssetSetID == entry.id,
                                controllerCommand: controllerCommand
                            )
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Favorites")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.favoritesShelf)
    }
}
