import SwiftUI

/// Continue over `ContinueViewModel`. Every copy string here is asserted
/// (source-level, by `OrderingTests`) to contain no promise about
/// restoring saved progress — Continue promises recency only; save
/// continuity does not exist until a later phase.
struct ContinueShelfView: View {
    let viewModel: ContinueViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]

    /// The only copy strings this view renders — collected in one place
    /// so a source grep can assert none of them promise restored
    /// progress (no "resume", "restore", "save" vocabulary).
    /// `emptyExplanation` is 03-UI-SPEC.md's own locked empty-state copy
    /// verbatim — it is about which games appear here (recency), not a
    /// promise that opening one restores in-game state.
    enum Copy {
        static let heading = "Continue"
        static let emptyExplanation = "Play something, and pick up where you left off here."
        static func subtitle(relativeTime: String) -> String { "Played \(relativeTime)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(Copy.heading).font(.psHeading).foregroundStyle(DesignTokens.textPrimary)

            if viewModel.isEmpty {
                Text(Copy.emptyExplanation)
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityLabel(Copy.emptyExplanation)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DesignTokens.Spacing.md) {
                        ForEach(viewModel.items, id: \.assetSetID) { row in
                            Text(catalogueByAssetSetID[row.assetSetID]?.displayTitle ?? row.assetSetID)
                        }
                    }
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }
}
