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
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        queueRow(item, at: index)
                    }
                    .onMove(perform: move)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Play queue")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.playQueue)
    }

    private func queueRow(_ item: CurationQueueItemRow, at index: Int) -> some View {
        let title = catalogueByAssetSetID[item.assetSetID]?.displayTitle ?? item.assetSetID
        return HStack(spacing: DesignTokens.Spacing.sm) {
            Text(title)
            Spacer()
            reorderButton(item, title: title, index: index, direction: .up)
            reorderButton(item, title: title, index: index, direction: .down)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("playstead.curation.queue-item.\(item.id)")
    }

    private func reorderButton(
        _ item: CurationQueueItemRow,
        title: String,
        index: Int,
        direction: QueueReorderDirection
    ) -> some View {
        let isUp = direction == .up
        return Button {
            settleMove(assetSetID: item.assetSetID, to: isUp ? index - 1 : index + 1)
        } label: {
            Label(isUp ? "Move Up" : "Move Down", systemImage: isUp ? "arrow.up" : "arrow.down")
        }
        .disabled(
            isUp ? index == viewModel.items.startIndex : index == viewModel.items.index(before: viewModel.items.endIndex)
        )
        .accessibilityLabel("Move \(title) \(isUp ? "up" : "down")")
        .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
        .playsteadFocusable(identifier:
            "playstead.curation.queue-item.\(item.id).move-\(isUp ? "up" : "down")"
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        performListReorder(from: source, to: destination, ids: viewModel.items.map(\.assetSetID)) { assetSetID, index in
            settleMove(assetSetID: assetSetID, to: index)
        }
    }

    private func settleMove(assetSetID: String, to index: Int) {
        guard viewModel.items.indices.contains(index) else { return }
        viewModel.beginReorder()
        viewModel.previewMove(assetSetID: assetSetID, to: index)
        viewModel.commitReorder(assetSetID: assetSetID)
        viewModel.refresh()
    }
}

private enum QueueReorderDirection {
    case up
    case down
}
