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

    func testGenuineEmptyLibraryGuidanceMatchesPairingAcrossLayoutsAndAppearances() throws {
        for (profile, paired) in [(UITestHarness.Profile.emptyLibrary, false), (.pairedEmptyLibrary, true)] {
            for (appearance, windowSize) in [("light", "960x560"), ("dark", "1280x800")] {
                let harness = UITestHarness(profile: profile, extraEnvironment: [
                    "PLAYSTEAD_UI_TEST_APPEARANCE": appearance,
                    "PLAYSTEAD_UI_TEST_WINDOW_SIZE": windowSize
                ])
                self.harness = harness
                harness.launch(settledAt: "playstead.surface.library")
                for layout in ["cards", "list"] {
                    let picker = harness.element("playstead.library.view-mode")
                    let segment = picker.descendants(matching: .any)["playstead.control.show-\(layout)"]
                    XCTAssertTrue(segment.awaitExistence(timeout: 5))
                    segment.clickWhenHittable()
                    let pane = harness.element("playstead.library.empty")
                    XCTAssertTrue(pane.awaitExistence(timeout: 5))
                    XCTAssertTrue(pane.staticTexts["No games yet"].exists)
                    let action = paired ? "Refresh Library" : "Pair with Server…"
                    let otherAction = paired ? "Pair with Server…" : "Refresh Library"
                    XCTAssertTrue(pane.buttons[action].awaitExistence(timeout: 5))
                    XCTAssertTrue(pane.buttons[action].isHittable)
                    XCTAssertFalse(pane.buttons[otherAction].exists)
                    let guidance = paired
                        ? "Import a game in your server's web console, then refresh your library."
                        : "Pair with your Playstead server to see your library."
                    XCTAssertTrue(pane.staticTexts[guidance].exists)
                    let image = XCTAttachment(screenshot: harness.app.screenshot())
                    image.name = "Empty library — \(profile.rawValue), \(layout), \(appearance), \(windowSize)"
                    image.lifetime = .keepAlways
                    add(image)
                }
                harness.app.terminate()
            }
        }
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

    func testListFilterEmptyStateClearFiltersRestoresResults() throws {
        let harness = launchLibrary()
        showLayout("playstead.control.show-list", in: harness)

        selectReadyOffline(in: harness)

        XCTAssertTrue(
            harness.app.staticTexts["No games match the current filters"].awaitExistence(timeout: 5),
            "the selected filter did not produce its empty state"
        )
        let clear = harness.element("playstead.control.clear-filters", type: .button)
        XCTAssertTrue(clear.awaitExistence(timeout: 5), "the filter recovery action is missing")
        clear.clickWhenHittable()

        XCTAssertTrue(
            harness.app.staticTexts["Synthetic Game 1"].awaitExistence(timeout: 5),
            "clearing filters did not restore the populated library"
        )
        XCTAssertTrue(
            harness.app.buttons["Availability: Any"].exists,
            "the availability filter did not return to Any"
        )
    }

    func testCardsFilterEmptyStateClearFiltersRestoresResults() throws {
        let harness = launchLibrary()
        showLayout("playstead.control.show-cards", in: harness)

        selectReadyOffline(in: harness)

        XCTAssertTrue(
            harness.app.staticTexts["No games match the current filters"].awaitExistence(timeout: 5),
            "the selected filter did not produce its empty state"
        )
        let clear = harness.element("playstead.control.clear-filters", type: .button)
        XCTAssertTrue(clear.awaitExistence(timeout: 5), "the filter recovery action is missing")
        clear.clickWhenHittable()

        XCTAssertTrue(
            harness.app.staticTexts["Synthetic Game 1"].awaitExistence(timeout: 5),
            "clearing filters did not restore the populated library"
        )
    }

    func testSearchMissWithFilterKeepsClearSearchRecovery() throws {
        let harness = launchLibrary()
        selectReadyOffline(in: harness)
        search(missQuery, in: harness)

        XCTAssertTrue(
            harness.app.staticTexts["No matches for \u{201C}\(missQuery)\u{201D}"].awaitExistence(timeout: 5),
            "a filtered search miss did not preserve the query-specific heading"
        )
        XCTAssertTrue(
            harness.element("playstead.control.clear-search", type: .button).exists,
            "the query-specific Clear search action is missing"
        )
        XCTAssertFalse(
            harness.element("playstead.control.clear-filters", type: .button).exists,
            "a typed search miss should not offer the filter-only recovery action"
        )

        harness.element("playstead.control.clear-search", type: .button).clickWhenHittable()
        XCTAssertTrue(
            harness.element("playstead.control.clear-filters", type: .button).awaitExistence(timeout: 5),
            "clearing the query should reveal the still-active filter recovery state"
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
        // The toolbar's segmented Picker is exposed as a compound AX
        // container on macOS. Resolve its production root, then activate the
        // visible, exact child segment instead of assuming an XCUI element
        // type for the wrapper.
        let picker = harness.element("playstead.library.view-mode")
        XCTAssertTrue(picker.awaitExistence(timeout: 5), "library view picker is missing")
        let segmentLabel: String
        switch identifier {
        case "playstead.control.show-list": segmentLabel = "List"
        case "playstead.control.show-cards": segmentLabel = "Cards"
        default: return XCTFail("unknown library view segment: \(identifier)")
        }
        let control = picker.descendants(matching: .any)[identifier]
        XCTAssertTrue(control.awaitExistence(timeout: 5), "layout segment missing: \(segmentLabel)")
        XCTAssertEqual(control.readableText, segmentLabel)
        control.clickWhenHittable()
        let resultingSurface = segmentLabel == "List"
            ? "playstead.library.sort"
            : "playstead.surface.game-card"
        XCTAssertTrue(
            harness.element(resultingSurface).awaitExistence(timeout: 5),
            "selecting \(segmentLabel) did not render its production layout"
        )
    }

    private func selectReadyOffline(in harness: UITestHarness) {
        let filterRow = harness.element("playstead.surface.filter")
        let readyOffline = harness.element("library.filter.availability:ready_offline", type: .button)
        XCTAssertTrue(readyOffline.awaitExistence(timeout: 5), "the Ready offline filter is missing")
        for _ in 0..<8 where !readyOffline.isHittable {
            filterRow.swipeLeft()
        }
        readyOffline.clickWhenHittable()
    }

    private func search(_ query: String, in harness: UITestHarness) {
        let field = harness.app.searchFields["Search your library"]
        XCTAssertTrue(field.awaitExistence(timeout: 5), "the library search field is missing")
        field.clickWhenHittable()
        field.typeText(query)
    }
}
