import XCTest
@testable import Playstead

/// WINDOWS #79: `LibrarySortOption` and `GameListView.sorted(_:by:)`
/// existed, were tested, and could not be reached from the shipped app,
/// because the list layout renders `GameRowView` over `CatalogueEntry` and
/// nothing offered a sort control at all.
final class LibrarySortTests: XCTestCase {
    private func entry(_ id: String, title: String, system: String) -> CatalogueEntry {
        CatalogueEntry(id: id, system: system, displayTitle: title, tags: [:], members: [])
    }

    func testTitleSortIsAlphabeticalAndCaseInsensitive() {
        let entries = [
            entry("c", title: "zelda", system: "gba"),
            entry("a", title: "Advance Wars", system: "gba"),
            entry("b", title: "metroid", system: "gba"),
        ]
        XCTAssertEqual(
            LibrarySortOption.sortedEntries(entries, by: .title).map(\.displayTitle),
            ["Advance Wars", "metroid", "zelda"],
            "a lowercase title must not sort after every capitalised one"
        )
    }

    func testSystemSortGroupsBySystem() {
        let entries = [
            entry("1", title: "B", system: "snes"),
            entry("2", title: "A", system: "gba"),
            entry("3", title: "C", system: "nes"),
        ]
        XCTAssertEqual(LibrarySortOption.sortedEntries(entries, by: .system).map(\.system), ["gba", "nes", "snes"])
    }

    /// The order must be total. Without a tie-break, two games sharing a
    /// sort key can swap between two evaluations of the same view body,
    /// which reads as rows jittering under the cursor.
    func testEqualKeysKeepAStableTotalOrder() {
        let entries = [
            entry("z", title: "Same", system: "gba"),
            entry("a", title: "Same", system: "gba"),
            entry("m", title: "Same", system: "gba"),
        ]
        let once = LibrarySortOption.sortedEntries(entries, by: .title).map(\.id)
        let twice = LibrarySortOption.sortedEntries(entries.reversed(), by: .title).map(\.id)
        XCTAssertEqual(once, ["a", "m", "z"])
        XCTAssertEqual(once, twice, "the same set in a different input order must produce the same output order")
    }

    /// The control must not offer an ordering the data cannot answer:
    /// nothing local knows when a game was added.
    func testDateAddedIsNotOfferedAndOrdersNothing() {
        XCTAssertEqual(LibrarySortOption.selectable, [.title, .system])
        XCTAssertFalse(LibrarySortOption.selectable.contains(.dateAdded))

        let entries = [entry("b", title: "B", system: "gba"), entry("a", title: "A", system: "gba")]
        XCTAssertEqual(
            LibrarySortOption.sortedEntries(entries, by: .dateAdded).map(\.id), ["b", "a"],
            "with no dates available, the catalogue's own order is kept rather than a fabricated one"
        )
    }

    func testEverySelectableOptionHasADistinctLabelAndIdentifier() {
        let labels = LibrarySortOption.selectable.map(\.controlLabel)
        let identifiers = LibrarySortOption.selectable.map(\.controlIdentifier)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("playstead.control.sort-") })
    }
}
