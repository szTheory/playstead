import SwiftUI

/// Recent over `RecentViewModel`, plus (plan 03-08 task 3) the pending/
/// delivered play sessions `PlaySessionRecorder` owns — individually
/// deletable, per this task's `<action>`. The session list is read from
/// `viewModel.sessionListings` (cached, refresh()-driven), not queried
/// directly from `body`; `RecentViewModel` renders task 2's plain
/// recently-played-games shelf on its own wherever no `PlaySessionRecorder`
/// was wired into the view model.
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

            sessionsSection
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if !viewModel.sessionListings.isEmpty {
            List {
                ForEach(viewModel.sessionListings, id: \.session.id) { listing in
                    HStack {
                        Text(catalogueByAssetSetID[listing.session.assetSetID]?.displayTitle ?? listing.session.assetSetID)
                        Spacer()
                        Text(listing.delivered ? "Delivered" : "Pending")
                            .font(.psLabel)
                            .foregroundStyle(DesignTokens.textMuted)
                        Button(role: .destructive) {
                            viewModel.deleteSession(listing.session.id)
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
