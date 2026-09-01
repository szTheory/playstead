import SwiftUI

/// Lists `CollectionsViewModel`'s collections and lets the user create a
/// new one. Selecting a collection navigates to `CollectionDetailView`.
struct CollectionsView: View {
    let viewModel: CollectionsViewModel
    /// Which collection the shell should show members for. A binding
    /// rather than local `@State` because the detail pane lives outside
    /// this view; it defaults to a constant so the existing
    /// `CollectionsView(viewModel:)` call shape (and its tests) keeps
    /// working as a plain, non-selectable list.
    @Binding var selectedCollectionID: String?
    @State private var newCollectionName = ""

    init(viewModel: CollectionsViewModel, selectedCollectionID: Binding<String?> = .constant(nil)) {
        self.viewModel = viewModel
        self._selectedCollectionID = selectedCollectionID
    }

    static let emptyExplanation = "Create a collection to group games your way."

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("Collections").font(.psHeading).foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                TextField("New collection name", text: $newCollectionName)
                    .frame(maxWidth: 200)
                Button("Create Collection") {
                    guard !newCollectionName.isEmpty else { return }
                    viewModel.createCollection(name: newCollectionName)
                    newCollectionName = ""
                }
                .accessibilityLabel("Create Collection")
            }

            if viewModel.isEmpty {
                Text(Self.emptyExplanation)
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityLabel(Self.emptyExplanation)
            } else {
                List(viewModel.collections, id: \.id, selection: $selectedCollectionID) { collection in
                    Text(collection.name).tag(collection.id)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collections")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.collections)
    }
}
