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
        let view = CardAndStatusContractSheet(statuses: allStatuses)
        try PlaysteadSnapshot.assertContactSheet(
            view,
            named: "card-and-status-contract",
            pointSize: CGSize(width: 1_360, height: 720)
        )
    }

    func testSemanticContractOracles() {
        let expected: [(status: LibraryStatus, rank: Int, glyph: String, label: String, sentence: String)] = [
            (.needsAttention, 1, "exclamationmark.triangle.fill", "Needs attention", "Contract title needs your attention."),
            (.missingDependency, 2, "wrench.and.screwdriver.fill", "Missing dependency", "Contract title is missing something it needs to play."),
            (.downloading(percent: 42), 3, "progress.ring", "Downloading — 42%", "Contract title is downloading, 42 percent complete."),
            (.queued, 4, "clock", "Queued", "Contract title is queued to download."),
            (.pinned, 5, "mappin.circle.fill", "Pinned", "Contract title is pinned and ready to play offline."),
            (.verified, 5, "checkmark.circle.fill", "Ready offline", "Contract title is downloaded and ready to play offline."),
            (.serverOnly, 6, "icloud", "On server", "Contract title is on your server. Choose Download to play it offline.")
        ]

        XCTAssertEqual(allStatuses.count, 7)
        XCTAssertEqual(expected.count, 7)
        XCTAssertEqual(Set(expected.map(\.glyph)).count, 7)
        XCTAssertEqual(DesignTokens.CardGeometry.width, 280)
        XCTAssertEqual(DesignTokens.CardGeometry.height, 158)
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

        let source = try? String(contentsOf: productionFile("Library/GameCardView.swift"), encoding: .utf8)
        XCTAssertNotNil(source)
        XCTAssertFalse(source?.localizedCaseInsensitiveContains("cover") ?? true)
        XCTAssertFalse(source?.localizedCaseInsensitiveContains("artwork") ?? true)
    }

    func testFiveCurationShelfVisualContract() throws {
        try PlaysteadSnapshot.assertContactSheet(
            LibraryAndCurationContractSheet(),
            named: "library-and-curation-states",
            pointSize: CGSize(width: 1_360, height: 1_560)
        )
    }

    func testLibrarySearchFocusAndEmptyStateSemanticContract() {
        let expectedSidebar = [
            "Home", "Continue", "Favorites", "Collections", "Queue", "Recent",
            "Game Boy Advance", "Super Nintendo", "Unidentified"
        ]
        XCTAssertEqual(
            SidebarView.entries(nonEmptySystemIDs: ["snes", "gba"], hasUnidentified: true).map(\.label),
            expectedSidebar
        )
        XCTAssertEqual(
            SidebarView.entries(nonEmptySystemIDs: ["gba"], hasUnidentified: false).map(\.label),
            ["Home", "Continue", "Favorites", "Collections", "Queue", "Recent", "Game Boy Advance"]
        )

        XCTAssertEqual(SearchField.accessibilityIdentifier, "library.search.field")
        XCTAssertEqual(FilterChipRow.accessibilityIdentifier(for: "gba"), "library.filter.gba")
        XCTAssertEqual(ShowAllSystemsControl.accessibilityIdentifier, "library.systems.show-all")
        XCTAssertEqual(ShowAllSystemsControl.label(hiddenCount: 6, isExpanded: false), "Show all systems (6 hidden)")
        XCTAssertEqual(ShowAllSystemsControl.label(hiddenCount: 6, isExpanded: true), "Hide empty systems")

        XCTAssertEqual(ContinueShelfView.Copy.emptyExplanation, "Play something, and pick up where you left off here.")
        XCTAssertEqual(FavoritesShelfView.emptyExplanation, "Favorite a game to see it here.")
        XCTAssertEqual(CollectionsView.emptyExplanation, "Create a collection to group games your way.")
        XCTAssertEqual(QueueShelfView.emptyExplanation, "Add a game to your queue to keep it in mind.")
        XCTAssertEqual(RecentShelfView.emptyExplanation, "Play a game to see it here.")
        XCTAssertEqual(LibraryContractCopy.noMatchesBody, "Check the spelling, or clear your search to see everything.")
        XCTAssertEqual(LibraryContractCopy.clearSearch, "Clear search")
    }

    private func productionFile(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Playstead")
            .appendingPathComponent(relativePath)
    }
}

private struct CardAndStatusContractSheet: View {
    let statuses: [LibraryStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Card and status contract").font(.psDisplay)
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                GameCardView(
                    title: "Pokémon Mystery Dungeon — Überlange 你好タイトル",
                    systemID: "gba",
                    isUnidentified: false,
                    statuses: [.verified]
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                        .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                }
                GameCardView(
                    title: "Unknown synthetic fixture with a deliberately long second line",
                    systemID: "unknown",
                    isUnidentified: true,
                    statuses: [.serverOnly]
                )
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
    }
}

private struct LibraryAndCurationContractSheet: View {
    @State private var search = "Pokémon"
    @State private var expanded = false

    private let populated = [
        ShelfItem(id: "synthetic-a", title: "Synthetic Adventure", systemID: "gba", isUnidentified: false, statuses: [.pinned])
    ]

    private let shelves: [(String, String)] = [
        ("Continue", "Play something, and pick up where you left off here."),
        ("Favorites", "Favorite a game to see it here."),
        ("Collections", "Create a collection to group games your way."),
        ("Queue", "Add a game to your queue to keep it in mind."),
        ("Recent", "Play a game to see it here.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Library and five curation shelves").font(.psDisplay)
            HStack(spacing: DesignTokens.Spacing.md) {
                SearchField(text: $search).frame(width: 300)
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
                        ShelfView(heading: heading, items: populated, layout: .horizontal, emptyExplanation: emptyCopy)
                            .frame(width: 560, height: 238, alignment: .topLeading)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Honest empty").font(.psHeading)
                    ForEach(shelves, id: \.0) { heading, emptyCopy in
                        ShelfView(heading: heading, items: [], layout: .horizontal, emptyExplanation: emptyCopy)
                            .frame(width: 560, height: 238, alignment: .topLeading)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
    }
}
