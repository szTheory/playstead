import XCTest

/// WINDOWS #83. `LibraryViewModel.searchResultState` was computed correctly,
/// unit-tested in `FilterTests` and snapshot-tested in
/// `LibraryContractSnapshotTests` -- and read by no view at all. Three layers
/// of green evidence, and what a user searching for a non-matching title
/// actually saw on the list layout was "No games yet / Pair with your
/// Playstead server to see your library", over a paired, fully populated
/// library.
///
/// That is why this suite is a front-door UI test and not another view-model
/// test: the coverage that missed it was view-model coverage. Every assertion
/// here goes through the real search field and the real rendered tree.
@MainActor
final class LibraryEmptyStateTests: XCTestCase {
    private var harness: UITestHarness?

    /// A query no `Synthetic Game N` fixture title can contain.
    private let missQuery = "zzznotathing"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
    }

    func testListLayoutSearchWithNoMatchesShowsTheContractCopyNotThePairingPrompt() throws {
        let harness = launchLibrary()
        showLayout("playstead.control.show-list", in: harness)
        search(missQuery, in: harness)

        let pane = harness.element("playstead.surface.no-matches")
        XCTAssertTrue(pane.awaitExistence(timeout: 5), "the no-matches pane never rendered")

        // 03-UI-SPEC Copywriting Contract, asserted verbatim including the
        // typographic quotes, so a paraphrase cannot pass.
        XCTAssertTrue(
            harness.app.staticTexts["No matches for \u{201C}\(missQuery)\u{201D}"].awaitExistence(timeout: 5),
            "the heading did not echo the query"
        )
        XCTAssertTrue(
            harness.app.staticTexts["Check the spelling, or clear your search to see everything."].exists,
            "the contract body copy is missing"
        )

        // The defect this suite exists for: the pairing prompt is the wrong
        // answer to a search that matched nothing, and it is what shipped.
        XCTAssertFalse(
            harness.app.staticTexts["No games yet"].exists,
            "a search miss still offers the empty-library pairing prompt"
        )
    }

    func testCardsLayoutSearchWithNoMatchesShowsTheSameContractCopy() throws {
        let harness = launchLibrary()
        showLayout("playstead.control.show-cards", in: harness)
        search(missQuery, in: harness)

        XCTAssertTrue(
            harness.element("playstead.surface.no-matches").awaitExistence(timeout: 5),
            "the cards layout never rendered the no-matches pane"
        )
        XCTAssertTrue(
            harness.app.staticTexts["No matches for \u{201C}\(missQuery)\u{201D}"].awaitExistence(timeout: 5),
            "the cards layout did not echo the query"
        )
    }

    func testClearSearchControlIsReachableAndRestoresTheLibrary() throws {
        let harness = launchLibrary()
        showLayout("playstead.control.show-list", in: harness)
        search(missQuery, in: harness)

        // `LibraryViewModel.clearSearch()` existed with no UI path to it in
        // the one state it was written for.
        let clear = harness.element("playstead.control.clear-search", type: .button)
        XCTAssertTrue(clear.awaitExistence(timeout: 5), "the clear-search control is unreachable")
        clear.clickWhenHittable()

        XCTAssertTrue(
            harness.app.staticTexts["Synthetic Game 1"].awaitExistence(timeout: 5),
            "clearing the search did not restore the library"
        )
        XCTAssertFalse(
            harness.element("playstead.surface.no-matches").exists,
            "the no-matches pane outlived the search that caused it"
        )
    }

    // MARK: - Harness

    private func launchLibrary() -> UITestHarness {
        let harness = UITestHarness(profile: .populatedCurationReorder, persistentSession: true)
        self.harness = harness
        harness.launch(settledAt: "playstead.surface.library")
        return harness
    }

    private func showLayout(_ identifier: String, in harness: UITestHarness) {
        let control = harness.element(identifier, type: .button)
        XCTAssertTrue(control.awaitExistence(timeout: 5), "layout control missing: \(identifier)")
        control.clickWhenHittable()
    }

    private func search(_ query: String, in harness: UITestHarness) {
        let field = harness.element("library.search.field", type: .textField)
        XCTAssertTrue(field.awaitExistence(timeout: 5), "the library search field is missing")
        field.clickWhenHittable()
        field.typeText(query)
    }
}
