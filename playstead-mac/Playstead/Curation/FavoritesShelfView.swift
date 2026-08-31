import SwiftUI

/// Renders `FavoritesViewModel`'s favorites over `ShelfView` — the
/// shelf itself is generic (plan 03-06); this view is the mapping from
/// a favorite row plus the catalogue entry it references into a
/// `ShelfItem`, and the empty-state copy from 03-UI-SPEC.md's
/// Copywriting Contract.
struct FavoritesShelfView: View {
    let viewModel: FavoritesViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]
    /// Injected rather than derived here — status derivation (D-21) is
    /// wired by a later plan; this shelf renders whatever the caller
    /// currently knows.
    var statuses: (String) -> [LibraryStatus] = { _ in [] }

    static let emptyExplanation = "Favorite a game to see it here."

    var items: [ShelfItem] {
        Self.items(favorites: viewModel.favorites, catalogueByAssetSetID: catalogueByAssetSetID, statuses: statuses)
    }

    /// Pure so it can be asserted directly by tests without hosting a
    /// live view — matches the codebase's established pattern
    /// (`GameCardView.accessibleLabel`, `FilterChipRow.isSelected`, etc.)
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
        ShelfView(heading: "Favorites", items: items, layout: .horizontal, emptyExplanation: Self.emptyExplanation)
    }
}
