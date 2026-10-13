import SwiftUI

/// Recently Played over `ContinueViewModel`. Every copy string here is
/// asserted (source-level, by `OrderingTests`) to contain no promise about
/// restoring saved progress — Continue promises recency only; save
/// continuity does not exist until a later phase.
struct ContinueShelfView: View {
    let viewModel: ContinueViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]
    var onBrowseLibrary: () -> Void = {}
    var controllerFocusedAssetSetID: String? = nil
    var controllerCommand: LibraryControllerCommand? = nil

    /// The only copy strings this view renders — collected in one place
    /// so a source grep can assert none of them promise restored
    /// progress (no "resume", "restore", "save" vocabulary).
    /// `emptyExplanation` is 03-UI-SPEC.md's own locked empty-state copy
    /// verbatim — it is about which games appear here (recency), not a
    /// promise that opening one restores in-game state.
    enum Copy {
        static let heading = "Recently Played"
        static let emptyExplanation = "Games you play will appear here."
        static func subtitle(relativeTime: String) -> String { "Played \(relativeTime)" }
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                ContentUnavailableView {
                    Label(Copy.heading, systemImage: "clock")
                } description: {
                    Text(Copy.emptyExplanation)
                } actions: {
                    Button("Browse Library", action: onBrowseLibrary)
                }
            } else {
                List {
                    ForEach(viewModel.items, id: \.assetSetID) { row in
                        if let entry = catalogueByAssetSetID[row.assetSetID] {
                            GameRowView(
                                entry: entry,
                                isControllerFocused: controllerFocusedAssetSetID == entry.id,
                                controllerCommand: controllerCommand
                            )
                        } else {
                            Label("Game unavailable", systemImage: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.heading)
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.continueShelf)
    }
}
