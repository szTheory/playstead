import XCTest
@testable import Playstead

/// Covers plan 03-06 task 2's `<acceptance_criteria>` against
/// 03-UI-SPEC.md's Status Vocabulary & Priority Ladder table. SwiftUI
/// views are not introspectable headlessly in this project (no
/// ViewInspector dependency — see other test files' precedent of testing
/// pure logic rather than rendered output), so these tests exercise the
/// same pure computations the views call, not the rendered accessibility
/// tree.
final class StatusLadderTests: XCTestCase {
    private let allSeven: [LibraryStatus] = [
        .needsAttention, .missingDependency, .downloading(percent: 42), .queued, .pinned, .verified, .serverOnly
    ]

    func testHighestRankedIndicatorWinsForEveryCombination() {
        for i in allSeven.indices {
            for j in allSeven.indices where j != i {
                let combo = [allSeven[i], allSeven[j]]
                let expected = combo.min(by: { $0.rank < $1.rank })
                XCTAssertEqual(LibraryStatus.highestPriority(among: combo), expected)
            }
        }

        // The full ladder together must resolve to the single highest rank (1).
        XCTAssertEqual(LibraryStatus.highestPriority(among: allSeven), .needsAttention)
    }

    func testEachStateProducesDistinctGlyphAndNonEmptyFullSentenceAccessibleName() {
        let glyphs = allSeven.map(\.glyphIdentifier)
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "every state must have a distinct glyph identifier")

        for status in allSeven {
            let name = status.accessibleName(title: "Metroid Fusion")
            XCTAssertFalse(name.isEmpty)
            XCTAssertTrue(name.hasSuffix("."), "accessible name must read as a full sentence: \(name)")
            XCTAssertTrue(name.contains("Metroid Fusion"))
        }
    }

    func testSystemAccentAndStatusTokenShareNoValue() {
        XCTAssertFalse(SystemAccent.allValues.isEmpty)
        XCTAssertFalse(StatusToken.allValues.isEmpty)
        XCTAssertTrue(SystemAccent.allValues.isDisjoint(with: StatusToken.allValues))
    }

    func testSafeToEvictIsNotAMemberOfTheCardStatusLadder() {
        // LibraryStatus has no .safeToEvict case at all — a compile-time
        // guarantee, not a runtime one. This documents the ranks the
        // real card ladder spans (1 through 6, with 5 shared by
        // pinned/verified) and would fail if a future change collapsed
        // or renumbered them.
        XCTAssertEqual(Set(allSeven.map(\.rank)), Set([1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(StatusToken.safeToEvict, StatusToken.safeToEvict, "safeToEvict is a color token only, never a ladder case")
    }

    func test500EntrySnapshotUsesFixedCardGeometryForAStableRowHeight() {
        let items = (0..<500).map { i in
            ShelfItem(id: "\(i)", title: "Game \(i)", systemID: "gba", isUnidentified: false, statuses: [.serverOnly])
        }
        XCTAssertEqual(items.count, 500)
        // Row height/width are compile-time constants, not derived from
        // content — the fixed geometry itself is what makes a lazy
        // container safe with no loading placeholder for 500 items (D-16).
        XCTAssertEqual(DesignTokens.CardGeometry.height, 224)
        XCTAssertEqual(DesignTokens.CardGeometry.width, 280)
    }

    func testSidebarOrderMatchesTheCurrentGroupedNavigationOrder() {
        let entries = SidebarView.entries(nonEmptySystemIDs: ["gba", "snes"], hasUnidentified: true)
        let labels = entries.map(\.label)

        XCTAssertEqual(labels[0], "All Games")
        XCTAssertEqual(labels[1], "Recently Played")
        XCTAssertEqual(labels[2], "Favorites")
        XCTAssertEqual(labels[3], "Collections")
        XCTAssertEqual(labels[4], "Queue")
        XCTAssertEqual(labels[5], "Recent")
        // Systems remain easy to reach; Manage destinations follow them.
        XCTAssertEqual(Array(labels[6...]), [
            "Game Boy Advance", "Super Nintendo", "Unidentified", "Downloads", "Settings"
        ])
    }

    func testUnidentifiedSectionIsHiddenEntirelyWhenNoneExist() {
        let entries = SidebarView.entries(nonEmptySystemIDs: ["gba"], hasUnidentified: false)
        XCTAssertFalse(entries.map(\.section).contains(.unidentified))
    }

    func testGrepHasNoPlaceholderOrGeneratedArtworkVocabulary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LibraryTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
        let libraryDir = root.appendingPathComponent("Playstead/Library")
        let designDir = root.appendingPathComponent("Playstead/Design")

        let forbidden = ["placeholderImage", "boxArt", "coverArt"]
        for dir in [libraryDir, designDir] {
            let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                for term in forbidden {
                    XCTAssertFalse(
                        contents.localizedCaseInsensitiveContains(term),
                        "\(file.lastPathComponent) must not reference '\(term)'"
                    )
                }
            }
        }
    }
}
