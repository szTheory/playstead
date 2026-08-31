import SwiftUI

/// Recent over `RecentViewModel`. Plan 03-08 task 3 extends this view to
/// also list pending/delivered play sessions (individually deletable);
/// task 2 covers the recently-played-games shelf itself.
struct RecentShelfView: View {
    let viewModel: RecentViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]

    static let emptyExplanation = "Play a game to see it here."

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Recent").font(.psHeading).foregroundStyle(DesignTokens.textPrimary)

            if viewModel.isEmpty {
                Text(Self.emptyExplanation)
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityLabel(Self.emptyExplanation)
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
