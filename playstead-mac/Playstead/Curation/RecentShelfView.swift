import SwiftUI

/// Recent over `RecentViewModel`, plus (plan 03-08 task 3) the pending/
/// delivered play sessions `PlaySessionRecorder` owns — individually
/// deletable, per this task's `<action>`. The session list is read from
/// `viewModel.sessionListings` (cached, refresh()-driven), not queried
/// directly from `body`; `RecentViewModel` renders task 2's plain
/// recently-played-games shelf on its own wherever no `PlaySessionRecorder`
/// was wired into the view model.
struct RecentShelfView: View {
    let viewModel: RecentViewModel
    let catalogueByAssetSetID: [String: CatalogueEntry]
    var onBrowseLibrary: () -> Void = {}
    var controllerFocusedAssetSetID: String? = nil
    var controllerCommand: LibraryControllerCommand? = nil

    static let emptyExplanation = "Play a game to see it here."

    var body: some View {
        Group {
            if viewModel.isEmpty && viewModel.sessionListings.isEmpty {
                ContentUnavailableView {
                    Label("Recent", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(Self.emptyExplanation)
                } actions: {
                    Button("Browse Library", action: onBrowseLibrary)
                }
            } else {
                List {
                    if !viewModel.items.isEmpty {
                        Section("Games") {
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
                    }
                    sessionsSection
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.recent)
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if !viewModel.sessionListings.isEmpty {
            Section("Play sessions") {
                ForEach(viewModel.sessionListings, id: \.session.id) { listing in
                    HStack {
                        Text(catalogueByAssetSetID[listing.session.assetSetID]?.displayTitle ?? "Game unavailable")
                        Spacer()
                        Text(listing.delivered ? "Synced" : "Waiting to sync")
                            .font(.psLabel)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            viewModel.deleteSession(listing.session.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete session")
                    }
                }
            }
        }
    }
}
