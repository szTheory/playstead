import SwiftUI

/// Lists `CollectionsViewModel`'s collections and lets the user create a
/// new one. Selecting a collection navigates to `CollectionDetailView`.
struct CollectionsView: View {
    enum Automation {
        static func row(_ collectionID: String) -> String {
            "playstead.curation.collection.\(collectionID)"
        }
    }

    let viewModel: CollectionsViewModel
    /// Which collection the shell should show members for. A binding
    /// rather than local `@State` because the detail pane lives outside
    /// this view; it defaults to a constant so the existing
    /// `CollectionsView(viewModel:)` call shape (and its tests) keeps
    /// working as a plain, non-selectable list.
    @Binding var selectedCollectionID: String?
    var controllerFocusedCollectionID: String? = nil
    var collectionNameFocus: FocusState<Bool>.Binding?
    @State private var newCollectionName = ""
    @FocusState private var localCollectionNameFocus: Bool

    init(
        viewModel: CollectionsViewModel,
        selectedCollectionID: Binding<String?> = .constant(nil),
        controllerFocusedCollectionID: String? = nil,
        collectionNameFocus: FocusState<Bool>.Binding? = nil
    ) {
        self.viewModel = viewModel
        self._selectedCollectionID = selectedCollectionID
        self.controllerFocusedCollectionID = controllerFocusedCollectionID
        self.collectionNameFocus = collectionNameFocus
    }

    static let emptyExplanation = "Create a collection to group games your way."

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("Collection name", text: $newCollectionName)
                    .focused(collectionNameFocus ?? $localCollectionNameFocus)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("New collection name")
                Button("Create", systemImage: "plus") {
                    guard !newCollectionName.isEmpty else { return }
                    viewModel.createCollection(name: newCollectionName)
                    newCollectionName = ""
                }
                .fixedSize()
                .help("Create Collection")
                .accessibilityLabel("Create Collection")
            }

            if viewModel.isEmpty {
                ContentUnavailableView {
                    Label("No Collections", systemImage: "folder")
                } description: {
                    Text(Self.emptyExplanation)
                }
            } else {
                List(viewModel.collections, id: \.id, selection: $selectedCollectionID) { collection in
                    let isControllerFocused = controllerFocusedCollectionID == collection.id
                    Button {
                        selectedCollectionID = collection.id
                    } label: {
                        Text(collection.name)
                            .frame(maxWidth: .infinity, minHeight: DesignTokens.InteractiveTarget.minimum, alignment: .leading)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .background(isControllerFocused ? DesignTokens.focusRing.opacity(0.24) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.tight))
                    }
                    .buttonStyle(.plain)
                    .tag(collection.id)
                    .accessibilityAddTraits(selectedCollectionID == collection.id ? [.isSelected] : [])
                    .accessibilityValue(isControllerFocused ? "Focused" : "")
                    .accessibilityLabel(collection.name)
                    .accessibilityIdentifier(Automation.row(collection.id))
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collections")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.collections)
    }
}
