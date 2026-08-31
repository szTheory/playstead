import SwiftUI

/// The play queue over `QueueViewModel` — `List` with `.onMove` so a
/// completed drag gesture settles into exactly one
/// `beginReorder`/`previewMove`/`commitReorder` sequence (SwiftUI's
/// `onMove(perform:)` itself fires once per drop, carrying the full
/// source/destination in one call).
struct QueueShelfView: View {
    let viewModel: QueueViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]

    static let emptyExplanation = "Add a game to your queue to keep it in mind."

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Queue").font(.psHeading).foregroundStyle(DesignTokens.textPrimary)

            if viewModel.isEmpty {
                Text(Self.emptyExplanation)
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityLabel(Self.emptyExplanation)
            } else {
                List {
                    ForEach(viewModel.items, id: \.assetSetID) { item in
                        Text(catalogueByAssetSetID[item.assetSetID]?.displayTitle ?? item.assetSetID)
                    }
                    .onMove(perform: move)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let assetSetID = viewModel.items[sourceIndex].assetSetID
        viewModel.beginReorder()
        viewModel.previewMove(assetSetID: assetSetID, to: destination > sourceIndex ? destination - 1 : destination)
        viewModel.commitReorder(assetSetID: assetSetID)
        viewModel.refresh()
    }
}
