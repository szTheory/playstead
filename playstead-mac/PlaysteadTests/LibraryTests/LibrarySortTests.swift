import XCTest
@testable import Playstead

/// WINDOWS #79: `LibrarySortOption` existed, was tested, and could not be
/// reached from the shipped app, because the list layout renders
/// `GameRowView` over `CatalogueEntry` and nothing offered a sort control at
/// all. The control is real now, and the unreachable `dateAdded` case that
/// sat beside it has been deleted rather than left documented.
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

    /// Every case the enum has must be one the picker offers.
    ///
    /// Strictly stronger than the assertion it replaces. That one pinned
    /// `selectable` against a hardcoded list while `dateAdded` sat in the enum
    /// unreachable and unordered -- it certified the gap instead of closing
    /// it. This fails if a case is ever added without being offered, which is
    /// the mistake that produced #79.
    func testEveryCaseIsOfferedByTheControl() {
        XCTAssertEqual(LibrarySortOption.selectable, LibrarySortOption.allCases)
        XCTAssertEqual(LibrarySortOption.selectable, [.title, .system])
    }

    func testEverySelectableOptionHasADistinctLabelAndIdentifier() {
        let labels = LibrarySortOption.selectable.map(\.controlLabel)
        let identifiers = LibrarySortOption.selectable.map(\.controlIdentifier)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("playstead.control.sort-") })
    }
}
