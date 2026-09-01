import SwiftUI

/// One collection's members, reorderable via drag. An empty collection
/// renders `emptyExplanation` — a selectable, non-error row, not a
/// blank pane — with a non-empty accessibility label, since an empty
/// collection is a perfectly normal, valid collection.
struct CollectionDetailView: View {
    let viewModel: CollectionsViewModel
    let collectionID: String
    let catalogueByAssetSetID: [String: CatalogueEntry]
    @State private var selectedMemberID: String?
    @FocusState private var memberListHasFocus: Bool
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
                keyboardReorderCommands

                List(selection: $selectedMemberID) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        memberRow(member, at: index)
                            .tag(member.id)
                    }
                    .onMove(perform: move)
                }
                .focused($memberListHasFocus)
                .accessibilityLabel("Collection member list")
                .accessibilityIdentifier("playstead.curation.collection-member-list")
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
        .onAppear { prepareKeyboardSelection() }
        .onChange(of: collectionID) { _, _ in prepareKeyboardSelection(reset: true) }
    }

    private var selectedMemberIndex: Int? {
        members.firstIndex { $0.id == selectedMemberID }
    }

    private var selectedMemberTitle: String? {
        guard let index = selectedMemberIndex else { return nil }
        let member = members[index]
        return catalogueByAssetSetID[member.assetSetID]?.displayTitle ?? member.assetSetID
    }

    private var keyboardReorderCommands: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(selectedMemberTitle.map { "Selected: \($0)" } ?? "No game selected")
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityValue(selectedMemberID ?? "none")
                .accessibilityIdentifier("playstead.curation.collection-selection")

            Button("Move selected up") { moveSelected(.up) }
                .disabled(selectedMemberIndex == nil || selectedMemberIndex == members.startIndex)
                .keyboardShortcut("u", modifiers: [.command, .option])
                .playsteadFocusable(identifier: "playstead.curation.collection-command.move-up")

            Button("Move selected down") { moveSelected(.down) }
                .disabled(
                    selectedMemberIndex == nil
                        || selectedMemberIndex == members.index(before: members.endIndex)
                )
                .keyboardShortcut("d", modifiers: [.command, .option])
                .playsteadFocusable(identifier: "playstead.curation.collection-command.move-down")
        }
    }

    private func memberRow(_ member: CurationCollectionMemberRow, at index: Int) -> some View {
        let title = catalogueByAssetSetID[member.assetSetID]?.displayTitle ?? member.assetSetID
        return HStack(spacing: DesignTokens.Spacing.sm) {
            Text(title)
            Spacer()
            reorderButton(member, title: title, index: index, direction: .up)
            reorderButton(member, title: title, index: index, direction: .down)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("playstead.curation.collection-member.\(member.id)")
    }

    private func reorderButton(
        _ member: CurationCollectionMemberRow,
        title: String,
        index: Int,
        direction: ReorderDirection
    ) -> some View {
        let isUp = direction == .up
        return Button {
            settleMove(assetSetID: member.assetSetID, to: isUp ? index - 1 : index + 1)
        } label: {
            Label(isUp ? "Move Up" : "Move Down", systemImage: isUp ? "arrow.up" : "arrow.down")
        }
        .disabled(isUp ? index == members.startIndex : index == members.index(before: members.endIndex))
        .accessibilityLabel("Move \(title) \(isUp ? "up" : "down")")
        .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
        .playsteadFocusable(identifier:
            "playstead.curation.collection-member.\(member.id).move-\(isUp ? "up" : "down")"
        )
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

    private func moveSelected(_ direction: ReorderDirection) {
        guard let index = selectedMemberIndex else { return }
        let destination = direction == .up ? index - 1 : index + 1
        guard members.indices.contains(destination) else { return }
        settleMove(assetSetID: members[index].assetSetID, to: destination)
        restoreMemberListFocus()
    }

    private func prepareKeyboardSelection(reset: Bool = false) {
        if reset || !members.contains(where: { $0.id == selectedMemberID }) {
            selectedMemberID = members.first?.id
        }
        restoreMemberListFocus()
    }

    private func restoreMemberListFocus() {
        Task { @MainActor in
            await Task.yield()
            memberListHasFocus = true
        }
    }
}

private enum ReorderDirection {
    case up
    case down
}
