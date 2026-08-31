import SwiftUI

/// Recent over `RecentViewModel`, plus (plan 03-08 task 3) the pending/
/// delivered play sessions `PlaySessionRecorder` owns — individually
/// deletable, per this task's `<action>`. `sessionRecorder` is optional
/// so this view still renders task 2's plain recently-played-games shelf
/// wherever a `PlaySessionRecorder` isn't wired in yet.
struct RecentShelfView: View {
    let viewModel: RecentViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]
    var sessionRecorder: PlaySessionRecorder?

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

            if let sessionRecorder {
                sessionsSection(sessionRecorder)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    @ViewBuilder
    private func sessionsSection(_ sessionRecorder: PlaySessionRecorder) -> some View {
        let listings = sessionRecorder.listings()
        if !listings.isEmpty {
            List {
                ForEach(listings, id: \.session.id) { listing in
                    HStack {
                        Text(catalogueByAssetSetID[listing.session.assetSetID]?.displayTitle ?? listing.session.assetSetID)
                        Spacer()
                        Text(listing.delivered ? "Delivered" : "Pending")
                            .font(.psLabel)
                            .foregroundStyle(DesignTokens.textMuted)
                        Button(role: .destructive) {
                            _ = sessionRecorder.delete(listing.session.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete session")
                    }
                }
            }
        }
    }
}
