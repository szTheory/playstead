import SwiftUI

/// One collection's members, reorderable via drag. An empty collection
/// renders `emptyExplanation` — a selectable, non-error row, not a
/// blank pane — with a non-empty accessibility label, since an empty
/// collection is a perfectly normal, valid collection.
struct CollectionDetailView: View {
    let viewModel: CollectionsViewModel
    let collectionID: String
    let catalogueByAssetSetID: [String: CatalogueEntry]

    static let emptyExplanation = "This collection has no games yet."

    private var members: [CurationCollectionMemberRow] {
        viewModel.members(of: collectionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if members.isEmpty {
                Text(Self.emptyExplanation)
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityLabel(Self.emptyExplanation)
            } else {
                List {
                    ForEach(members, id: \.assetSetID) { member in
                        Text(catalogueByAssetSetID[member.assetSetID]?.displayTitle ?? member.assetSetID)
                    }
                    .onMove(perform: move)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let assetSetID = members[sourceIndex].assetSetID
        viewModel.beginReorderMembers(collectionID)
        viewModel.previewMoveMember(collectionID, assetSetID: assetSetID, to: destination > sourceIndex ? destination - 1 : destination)
        viewModel.commitReorderMembers(collectionID, assetSetID: assetSetID)
        viewModel.refresh()
    }
}
