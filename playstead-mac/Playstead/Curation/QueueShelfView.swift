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
        performListReorder(from: source, to: destination, ids: viewModel.items.map(\.assetSetID)) { assetSetID, index in
            viewModel.beginReorder()
            viewModel.previewMove(assetSetID: assetSetID, to: index)
            viewModel.commitReorder(assetSetID: assetSetID)
            viewModel.refresh()
        }
    }
}
