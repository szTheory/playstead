import SwiftUI

/// One collection's members, reorderable via drag. An empty collection
/// renders `emptyExplanation` — a selectable, non-error row, not a
/// blank pane — with a non-empty accessibility label, since an empty
/// collection is a perfectly normal, valid collection.
struct CollectionDetailView: View {
    let viewModel: CollectionsViewModel
    let collectionID: String
    let catalogueByAssetSetID: [String: CatalogueEntry]
#if UI_TESTING
    @Environment(AppEnvironment.self) private var environment
#endif

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
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        memberRow(member, at: index)
                    }
                    .onMove(perform: move)
                }
            }

#if UI_TESTING
            Text(environment.curationReorderEvidenceValue(collectionID: collectionID))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityLabel("Curation verification evidence")
                .accessibilityValue(environment.curationReorderEvidenceValue(collectionID: collectionID))
                .accessibilityIdentifier("playstead.test.curation.evidence")
#endif
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collection detail")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.collectionDetail)
    }

    private func memberRow(_ member: CurationCollectionMemberRow, at index: Int) -> some View {
        let title = catalogueByAssetSetID[member.assetSetID]?.displayTitle ?? member.assetSetID
        return Text(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("playstead.curation.collection-member.\(member.id)")
    }

    private func move(from source: IndexSet, to destination: Int) {
        performListReorder(from: source, to: destination, ids: members.map(\.assetSetID)) { assetSetID, index in
            settleMove(assetSetID: assetSetID, to: index)
        }
    }

    private func settleMove(assetSetID: String, to index: Int) {
        guard members.indices.contains(index) else { return }
        viewModel.beginReorderMembers(collectionID)
        viewModel.previewMoveMember(collectionID, assetSetID: assetSetID, to: index)
        viewModel.commitReorderMembers(collectionID, assetSetID: assetSetID)
        viewModel.refresh()
    }
}
