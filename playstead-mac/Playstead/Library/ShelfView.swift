import SwiftUI

/// One item in a shelf or grid — the minimal projection `LibraryViewModel`
/// hands to `ShelfView`/`GameListView`, independent of `CatalogueEntry`
/// so those views never need to know about tags/members/decode shape.
struct ShelfItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemID: String
    let isUnidentified: Bool
    let statuses: [LibraryStatus]
}

/// Renders `items` as a horizontal lazy row (a curated shelf: Continue,
/// Favorites, etc.) or, via `.grid`, a lazy vertical grid for the
/// all-content browse — both fixed-height, no loading placeholder,
/// because the data is already local when this view appears (D-16). An
/// empty shelf shows `emptyExplanation` rather than disappearing, so the
/// sidebar entry it corresponds to always has somewhere to point.
struct ShelfView: View {
    enum Layout { case horizontal, grid }

    let heading: String
    let items: [ShelfItem]
    let layout: Layout
    let emptyExplanation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(heading).font(.psHeading).foregroundStyle(DesignTokens.textPrimary)

            if items.isEmpty {
                if let emptyExplanation {
                    Text(emptyExplanation)
                        .font(.psBody)
                        .foregroundStyle(DesignTokens.textMuted)
                }
            } else {
                content
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .horizontal:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DesignTokens.Spacing.md) {
                    ForEach(items) { card(for: $0) }
                }
            }
        case .grid:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: DesignTokens.CardGeometry.width), spacing: DesignTokens.Spacing.md)],
                spacing: DesignTokens.Spacing.md
            ) {
                ForEach(items) { card(for: $0) }
            }
        }
    }

    private func card(for item: ShelfItem) -> some View {
        GameCardView(title: item.title, systemID: item.systemID, isUnidentified: item.isUnidentified, statuses: item.statuses)
    }
}
