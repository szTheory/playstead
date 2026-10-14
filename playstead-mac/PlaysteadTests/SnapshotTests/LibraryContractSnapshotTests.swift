import Foundation
import SwiftUI
import XCTest
@testable import Playstead

@MainActor
final class LibraryContractSnapshotTests: XCTestCase {
    private let allStatuses: [LibraryStatus] = [
        .needsAttention,
        .missingDependency,
        .downloading(percent: 42),
        .queued,
        .pinned,
        .verified,
        .serverOnly
    ]

    func testCardAndStatusVisualContract() throws {
        let fixture = try LibrarySnapshotFixture()
        defer { fixture.cleanUp() }
        try PlaysteadSnapshot.assertContactSheet(
            CardAndStatusContractSheet(statuses: allStatuses, environment: fixture.environment),
            named: "card-and-status-contract",
            pointSize: CGSize(width: 1_360, height: 720)
        )
    }

    func testLibraryListRowWidthAdaptationVisualContract() throws {
        let fixture = try LibrarySnapshotFixture()
        defer { fixture.cleanUp() }
        try PlaysteadSnapshot.assertContactSheet(
            LibraryListRowWidthContractSheet(environment: fixture.environment),
            named: "library-list-row-width-adaptation",
            pointSize: CGSize(width: 1_160, height: 260)
        )
    }

    func testCollectionCreationControlsFitSidebarWidthVisualContract() throws {
        let fixture = try LibrarySnapshotFixture()
        defer { fixture.cleanUp() }
        try PlaysteadSnapshot.assertContactSheet(
            CollectionCreationControlsContractSheet(environment: fixture.environment),
            named: "collection-create-controls-sidebar",
            pointSize: CGSize(width: 320, height: 260)
        )
    }

    func testSemanticContractOracles() {
        let expected: [(status: LibraryStatus, rank: Int, glyph: String, label: String, sentence: String)] = [
            (.needsAttention, 1, "exclamationmark.triangle.fill", "Needs attention", "Contract title needs your attention."),
            (.missingDependency, 2, "wrench.and.screwdriver.fill", "Missing dependency", "Contract title is missing something it needs to play."),
            (.downloading(percent: 42), 3, "progress.ring", "Downloading — 42%", "Contract title is downloading, 42 percent complete."),
            (.queued, 4, "clock", "Queued", "Contract title is queued to download."),
            (.pinned, 5, "pin.fill", "Kept on this Mac", "Contract title is kept on this Mac and protected from automatic removal."),
            (.verified, 5, "checkmark.circle.fill", "Ready offline", "Contract title is downloaded and ready to play offline."),
            (.serverOnly, 6, "icloud", "Available to download", "Contract title is available to download.")
        ]

        XCTAssertEqual(allStatuses.count, 7)
        XCTAssertEqual(expected.count, 7)
        XCTAssertEqual(Set(expected.map(\.glyph)).count, 7)
        XCTAssertEqual(DesignTokens.CardGeometry.width, 280)
        XCTAssertEqual(DesignTokens.CardGeometry.height, 224)
        XCTAssertTrue(SystemAccent.allValues.isDisjoint(with: StatusToken.allValues))

        for row in expected {
            XCTAssertEqual(row.status.rank, row.rank)
            XCTAssertEqual(row.status.glyphIdentifier, row.glyph)
            XCTAssertEqual(row.status.listViewLabel, row.label)
            XCTAssertEqual(row.status.accessibleName(title: "Contract title"), row.sentence)
            XCTAssertEqual(StatusSlotView(statuses: [row.status], title: "Contract title").selectedStatus, row.status)
        }

        // All 127 non-empty combinations are checked against an oracle
        // written from the locked priority table, not production sorting.
        for mask in 1..<(1 << allStatuses.count) {
            let combination = allStatuses.enumerated().compactMap { index, status in
                mask & (1 << index) == 0 ? nil : status
            }
            let expectedWinner: LibraryStatus
            if combination.contains(.needsAttention) {
                expectedWinner = .needsAttention
            } else if combination.contains(.missingDependency) {
                expectedWinner = .missingDependency
            } else if combination.contains(.downloading(percent: 42)) {
                expectedWinner = .downloading(percent: 42)
            } else if combination.contains(.queued) {
                expectedWinner = .queued
            } else if combination.contains(.pinned) {
                expectedWinner = .pinned
            } else if combination.contains(.verified) {
                expectedWinner = .verified
            } else {
                expectedWinner = .serverOnly
            }
            XCTAssertEqual(LibraryStatus.highestPriority(among: combination), expectedWinner, "mask \(mask)")
            XCTAssertEqual(StatusSlotView(statuses: combination, title: "Contract title").selectedStatus, expectedWinner)
        }

        let cardEntry = CatalogueEntry(
            id: "contract-card",
            system: "gba",
            displayTitle: "Contract title",
            tags: [:],
            members: []
        )
        let card = GameRowView(entry: cardEntry, presentation: .card)
        XCTAssertEqual(card.entry, cardEntry)
        XCTAssertEqual(card.presentation, .card)
        XCTAssertEqual(GameRowView.downloadActionIdentifier(assetSetID: "contract-card"), "playstead.game.contract-card.download")
        XCTAssertEqual(GameRowView.playActionIdentifier(assetSetID: "contract-card"), "playstead.game.contract-card.play")
        XCTAssertEqual(GameRowView.retryActionIdentifier(assetSetID: "contract-card"), "playstead.game.contract-card.retry")
    }

    func testFiveCurationShelfVisualContract() throws {
        let fixture = try LibrarySnapshotFixture()
        defer { fixture.cleanUp() }
        try PlaysteadSnapshot.assertContactSheet(
            LibraryAndCurationContractSheet(environment: fixture.environment),
            named: "library-and-curation-states",
            pointSize: CGSize(width: 1_360, height: 1_560)
        )
    }

    func testLibrarySearchFocusAndEmptyStateSemanticContract() {
        let expectedSidebar = [
            "All Games", "Recently Played", "Favorites", "Collections", "Queue", "Recent",
            "Game Boy Advance", "Super Nintendo", "Unidentified", "Downloads", "Settings"
        ]
        XCTAssertEqual(
            SidebarView.entries(nonEmptySystemIDs: ["snes", "gba"], hasUnidentified: true).map(\.label),
            expectedSidebar
        )
        XCTAssertEqual(
            SidebarView.entries(nonEmptySystemIDs: ["gba"], hasUnidentified: false).map(\.label),
            ["All Games", "Recently Played", "Favorites", "Collections", "Queue", "Recent", "Game Boy Advance", "Downloads", "Settings"]
        )

        // Search is native `.searchable` owned by LibraryShellView; keep
        // asserting the stable production surface that contains it rather
        // than a retired standalone text-field component.
        XCTAssertEqual(AccessibilityIdentifiers.Surface.library, "playstead.surface.library")
        XCTAssertEqual(FilterChipRow.accessibilityIdentifier(for: "gba"), "library.filter.gba")
        XCTAssertEqual(ShowAllSystemsControl.accessibilityIdentifier, "library.systems.show-all")
        XCTAssertEqual(ShowAllSystemsControl.label(hiddenCount: 6, isExpanded: false), "Show all systems (6 hidden)")
        XCTAssertEqual(ShowAllSystemsControl.label(hiddenCount: 6, isExpanded: true), "Hide empty systems")

        XCTAssertEqual(ContinueShelfView.Copy.emptyExplanation, "Games you play will appear here.")
        XCTAssertEqual(FavoritesShelfView.emptyExplanation, "Favorite a game to see it here.")
        XCTAssertEqual(CollectionsView.emptyExplanation, "Create a collection to group games your way.")
        XCTAssertEqual(QueueShelfView.emptyExplanation, "Add a game to your queue to keep it in mind.")
        XCTAssertEqual(RecentShelfView.emptyExplanation, "Play a game to see it here.")
        let searchState = SearchResultState(query: "Nothing", entryCount: 0)
        XCTAssertEqual(searchState.heading, "No matches for “Nothing”")
        XCTAssertEqual(searchState.body, "Check the spelling, or clear your search to see everything.")
        XCTAssertEqual(searchState.clearControlLabel, "Clear search")
    }

}

private struct CardAndStatusContractSheet: View {
    let statuses: [LibraryStatus]
    let environment: AppEnvironment

    private let identifiedEntry = CatalogueEntry(
        id: "synthetic-a",
        system: "gba",
        displayTitle: "Pokémon Mystery Dungeon — Überlange 你好タイトル",
        tags: [:],
        members: []
    )
    private let unidentifiedEntry = CatalogueEntry(
        id: "synthetic-unknown",
        system: "unknown",
        displayTitle: "Unknown synthetic fixture with a deliberately long second line",
        tags: [:],
        members: []
    )

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Card and status contract").font(.psDisplay)
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                GameRowView(entry: identifiedEntry, presentation: .card, isControllerFocused: true)
                GameRowView(entry: unidentifiedEntry, presentation: .card)
                    .dynamicTypeSize(.large)
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Array(statuses.enumerated()), id: \.offset) { _, status in
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        StatusSlotView(statuses: [status], title: "Contract title")
                        Text(status.listViewLabel)
                            .font(.psLabel)
                            .lineLimit(2)
                            .frame(width: 112)
                    }
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.border.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .environment(environment)
    }
}

private struct LibraryListRowWidthContractSheet: View {
    let environment: AppEnvironment

    private let entry = CatalogueEntry(
        id: "synthetic-a",
        system: "gba",
        displayTitle: "The Legend of Zelda: The Minish Cap — Collector’s Edition",
        tags: [:],
        members: []
    )

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            rowPane(title: "Wide library pane · 620 pt", width: 620)
            rowPane(title: "Narrow library pane · 420 pt", width: 420)
        }
        .padding(DesignTokens.Spacing.lg)
        .environment(environment)
    }

    private func rowPane(title: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title).font(.psHeading)
            GameRowView(entry: entry, presentation: .list)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .background(DesignTokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.compact))
        }
        .frame(width: width, alignment: .topLeading)
    }
}

private struct CollectionCreationControlsContractSheet: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Collections sidebar").font(.psHeading)
            CollectionsView(viewModel: environment.collectionsViewModel)
                .frame(width: 280, height: 196, alignment: .topLeading)
                .background(DesignTokens.background)
        }
        .padding(DesignTokens.Spacing.md)
        .environment(environment)
    }
}

private struct LibraryAndCurationContractSheet: View {
    let environment: AppEnvironment
    @State private var search = "Pokémon"
    @State private var expanded = false

    private let populated = CatalogueEntry(
        id: "synthetic-a",
        system: "gba",
        displayTitle: "Synthetic Adventure",
        tags: [:],
        members: []
    )

    private let shelves: [(String, String)] = [
        ("Recently Played", "Games you play will appear here."),
        ("Favorites", "Favorite a game to see it here."),
        ("Collections", "Create a collection to group games your way."),
        ("Queue", "Add a game to your queue to keep it in mind."),
        ("Recent", "Play a game to see it here.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Library and five curation shelves").font(.psDisplay)
            HStack(spacing: DesignTokens.Spacing.md) {
                TextField("Search your library", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                FilterChipRow(
                    chips: [
                        FilterChip(id: "gba", label: "Game Boy Advance"),
                        FilterChip(id: "ready-offline", label: "Ready offline")
                    ],
                    selectedID: "gba",
                    onSelect: { _ in }
                )
                ShowAllSystemsControl(hiddenCount: 6, isExpanded: $expanded)
            }
            HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Populated").font(.psHeading)
                    ForEach(shelves, id: \.0) { heading, emptyCopy in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text(heading).font(.psHeading).foregroundStyle(DesignTokens.textPrimary)
                            GameRowView(entry: populated, presentation: .card)
                        }
                            .frame(width: 560, height: 238, alignment: .topLeading)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Honest empty").font(.psHeading)
                    ForEach(shelves, id: \.0) { heading, emptyCopy in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text(heading).font(.psHeading).foregroundStyle(DesignTokens.textPrimary)
                            Text(emptyCopy)
                                .font(.psBody)
                                .foregroundStyle(DesignTokens.textMuted)
                        }
                            .frame(width: 560, height: 238, alignment: .topLeading)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .environment(environment)
    }
}

@MainActor
private final class LibrarySnapshotFixture {
    private let root: URL
    private var storedEnvironment: AppEnvironment?

    var environment: AppEnvironment {
        guard let storedEnvironment else { fatalError("snapshot fixture was already cleaned up") }
        return storedEnvironment
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-library-snapshot-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let localStore = try LocalStore(paths: paths)
        let environment = AppEnvironment(
            uiTestingPaths: paths,
            localStore: localStore,
            reachability: Reachability(startOnline: false, monitorAutomatically: false),
            biosReferences: []
        )
        try environment.pinStore.pin(assetSetID: "synthetic-a")
        storedEnvironment = environment
    }

    func cleanUp() {
        storedEnvironment = nil
        try? FileManager.default.removeItem(at: root)
    }
}
