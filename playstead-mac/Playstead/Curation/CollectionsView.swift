import SwiftUI

/// Lists `CollectionsViewModel`'s collections and lets the user create a
/// new one. Selecting a collection navigates to `CollectionDetailView`.
struct CollectionsView: View {
    let viewModel: CollectionsViewModel
    @State private var newCollectionName = ""

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
                List(viewModel.collections, id: \.id) { collection in
                    Text(collection.name)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }
}
