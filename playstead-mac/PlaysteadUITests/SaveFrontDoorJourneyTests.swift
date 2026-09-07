import XCTest

/// Front-door reachability journeys for the four save surfaces this phase
/// shipped (04-16-SUMMARY.md's MC-01..MC-06 wiring). Every save-related UI
/// test that existed before this file sets a `PLAYSTEAD_UI_TEST_*` flag
/// that has `UITestBootstrap` construct the surface under test directly --
/// proving each surface's own behavior, never that anything a person does
/// actually reaches it. `StorageInteractionTests`/`CurationInteractionTests`
/// are the flagless precedent this file follows: `UITestHarness` launches
/// the app in its NORMAL state (`PLAYSTEAD_UI_TESTING`/
/// `PLAYSTEAD_UI_TEST_PROFILE` only -- see `UITestHarness.init`), and every
/// journey below reaches its surface only through the controls a person
/// would actually click.
///
/// Seeding state is fine and required -- a diverged save line, an
/// only-on-this-Mac revision, and a restorable revision all have to exist
/// for a journey to mean anything (see the `.saveRestorable`/
/// `.saveOnlyCopy`/`.saveDiverged` deterministic profiles). ROUTING to a
/// surface is not: no test below ever sets a flag that presents, opens, or
/// short-circuits navigation to the surface it is proving reachable.
///
/// Each journey is deliberately THIN: it asserts arrival at its surface,
/// with a failure message naming the navigation step that dead-ended, and
/// stops. The one documented exception is Journey 2's default-button
/// check, because a silently no-op default button was the actual shipped
/// defect (MC-02), and a working escape hatch is part of what "reached the
/// interruptive modal" has to mean. Every other behavioral assertion
/// belongs to the direct-entry suites this file does not duplicate.
@MainActor
final class SaveFrontDoorJourneyTests: XCTestCase {
    private var harness: UITestHarness!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
    }

    // MARK: - Journey 1 (SAVE-03): pressing Play restores the save

    /// From a normal launch with a game whose local save directory is
    /// empty and one `uploaded`, restorable revision committed for its
    /// content key, pressing the real List row's Play button must reach
    /// the launch-path save machinery (`LaunchSavePlanner`/
    /// `SavePlanExecutor`) rather than stopping at an earlier readiness
    /// blocker or a raw launch failure.
    func testPressingPlayReachesTheLaunchPathRestoreBranch() {
        launch(.saveRestorable)
        showList()

        let play = uniqueButton(labeled: "Play")
        XCTAssertTrue(
            play.waitForExistence(timeout: 5),
            "the seeded restorable-revision game never reached a ready Play action -- readiness must be blocking somewhere upstream of SAVE-03"
        )
        play.click()

        let lastExit = harness.app.staticTexts
            // GameRowView renders this as a bare Text inside a
            // `.accessibilityElement(children: .contain)` container, so macOS
            // carries the string in AXValue and `label` is empty (G-04-2).
            // Match either attribute so the query cannot silently never fire.
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                                  "Last exit:", "Last exit:"))
            .firstMatch
        XCTAssertTrue(
            lastExit.waitForExistence(timeout: 15),
            "Play never completed a launch -- the front door to SAVE-03's restore branch is unreachable"
        )

        let summary = harness.element(GameRowSummaryIdentifier.saveRestorable)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(
            (summary.readableText).contains("Launch failed"),
            "the launch path reported an error instead of completing the restore: \(summary.readableText)"
        )
    }

    // MARK: - Journey 2 (D-40): reclaiming an only-copy game interrupts, and the escape hatch is real

    /// From a normal launch, navigating to Storage and reclaiming a game
    /// that holds an only-on-this-Mac revision must present the D-40
    /// interruptive modal. The one documented behavior assertion this
    /// file makes beyond arrival: the default "Export saves…" button is
    /// not a silent dismissal (the exact shape of the shipped MC-02
    /// defect) -- it performs a real, observable export.
    func testReclaimingAnOnlyCopyGameInStoragePresentsTheInterruptiveModalAndExportIsReal() {
        launch(.saveOnlyCopy)
        openSurface(control: "playstead.control.open-storage", root: "playstead.surface.storage")

        harness.require(["playstead.storage.candidate.0", "playstead.storage.candidate.0.toggle"])
        harness.focusContainedAction(
            "playstead.storage.candidate.0.toggle",
            rootIdentifier: "playstead.surface.storage"
        )
        harness.element("playstead.storage.candidate.0.toggle", type: .button)
            .typeKey(.space, modifierFlags: [])

        let reclaim = harness.element("playstead.storage.reclaim", type: .button)
        XCTAssertTrue(reclaim.waitForExistence(timeout: 5))
        XCTAssertTrue(reclaim.isEnabled, "reclaim never became available for the selected only-copy candidate")
        reclaim.click()

        let interruption = harness.element("playstead.save.only-copy-interruptive")
        XCTAssertTrue(
            interruption.waitForExistence(timeout: 5),
            "reclaiming an only-on-this-Mac game must present the D-40 interruptive modal, but it never appeared"
        )

        let export = harness.element("playstead.save.only-copy-interruptive.export", type: .button)
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        // One assertion per hypothesis, on its own line: the CI evidence
        // sanitizer keeps file:line and discards the message, so the line number
        // has to carry the diagnosis by itself.
        func owns(_ element: XCUIElement) -> Bool {
            element.value(forKey: "hasKeyboardFocus") as? Bool == true
        }
        let cancel = harness.element("playstead.save.only-copy-interruptive.cancel", type: .button)
        let removeAnyway = harness.element("playstead.save.only-copy-interruptive.remove-anyway", type: .button)

        // Fails here => focus was never placed in the presented sheet at all.
        XCTAssertTrue(
            harness.app.buttons.allElementsBoundByIndex.contains(where: owns),
            "no button owns focus in the presented modal"
        )
        // Fails here => cancel took the focus that belongs to the escape hatch.
        XCTAssertFalse(owns(cancel), "cancel owns focus in the presented modal")
        // Fails here => the destructive button is default-focused: a D-40 violation.
        XCTAssertFalse(owns(removeAnyway), "the destructive button owns focus")
        // Fails here => focus landed on some other element entirely.
        XCTAssertTrue(
            owns(export),
            "the safe escape hatch ('Export saves…') must be the default-focused button, never the destructive one"
        )
        export.typeKey(.space, modifierFlags: [])

        XCTAssertFalse(
            interruption.waitForExistence(timeout: 2),
            "the interruptive modal did not dismiss after choosing the default action"
        )

        // The documented exception: proving the default button is not a
        // no-op (MC-02's shipped defect). NSWorkspace.shared.open is
        // unconditionally skipped under UI_TESTING; this reads the
        // recorded attempt AppEnvironment.openConsoleSavesExport leaves
        // in its place.
        let exportAttempt = harness.element("playstead.harness.console-export-attempt")
        XCTAssertTrue(exportAttempt.waitForExistence(timeout: 5))
        XCTAssertFalse(
            (exportAttempt.value as? String ?? "").isEmpty,
            "the default 'Export saves…' button must perform a real export, but no export attempt was recorded -- MC-02's silent no-op"
        )
    }

    // MARK: - Journey 3 (D-38): the divergence badge is reachable and opens the comparison sheet

    /// From a normal launch with a diverged save line, the divergence
    /// badge must be visible on the card, and following it through the
    /// readiness surface's "Review versions…" remedy (the comparison
    /// sheet's one real production entry point, per 04-16-SUMMARY.md)
    /// must open `ConflictComparisonSheet`.
    func testDivergedLineShowsTheCardBadgeAndReviewVersionsOpensComparison() {
        launch(.saveDiverged)

        let card = harness.element("library.card")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded diverged game's card never rendered")
        // GameCardView deliberately collapses to a single accessibility element
        // (`children: .ignore`) and composes the status ladder's sentence into
        // its own label, so `library.status-slot` cannot be addressed inside the
        // card -- by design, and better for a screen reader than three separate
        // stops. D-38's rank-1 union is therefore proven by the card's composed
        // accessible name, which ends in the divergence rung's sentence.
        XCTAssertTrue(
            card.readableText.hasSuffix("needs your attention."),
            "the card does not carry the D-38 divergence rung: \(card.readableText)"
        )

        openSurface(control: "playstead.control.open-readiness", root: "playstead.surface.readiness")

        let remedy = harness.element("playstead.readiness.row.saveState.remedy", type: .button)
        XCTAssertTrue(
            remedy.waitForExistence(timeout: 5),
            "the readiness Save row never surfaced a 'Review versions…' remedy for the diverged line"
        )
        remedy.click()

        let comparison = harness.element("playstead.surface.conflict-comparison")
        XCTAssertTrue(
            comparison.waitForExistence(timeout: 5),
            "'Review versions…' must open the comparison sheet for a diverged line, but it never appeared"
        )
        assertDismissalOwnsFocus(
            "playstead.conflict-comparison.done",
            "when the comparison sheet opens from 'Review versions…'"
        )
    }

    // MARK: - Journey 4 (D-37): the readiness Save row reports real state

    /// From a normal launch with saved progress (a restorable, uploaded
    /// revision -- the same `.saveRestorable` world Journey 1 seeds),
    /// the readiness sheet's Save row must report the game's actual
    /// state rather than the always-empty "No saved progress yet."
    /// placeholder MC-04 fixed.
    func testReadinessSaveRowReportsRealStateForAGameWithSavedProgress() {
        launch(.saveRestorable)
        openSurface(control: "playstead.control.open-readiness", root: "playstead.surface.readiness")

        assertDismissalOwnsFocus("playstead.control.done", "when the readiness sheet opens")

        let saveRow = harness.element("playstead.readiness.row.saveState")
        XCTAssertTrue(
            saveRow.waitForExistence(timeout: 5),
            "the readiness surface never rendered a Save row at all"
        )
        XCTAssertFalse(
            saveRow.readableText.contains("No saved progress yet."),
            "a game with a committed, uploaded save revision must never report the empty Save row state"
        )
    }

    // MARK: - Sheet focus placement (G-04-8's sweep, proven on the real paths)

    private func focusReport() -> String {
        let focused = harness.app.buttons.allElementsBoundByIndex
            .filter { $0.value(forKey: "hasKeyboardFocus") as? Bool == true }
            .map(\.identifier)
        return focused.isEmpty ? "nothing owns keyboard focus" : "focus is on \(focused)"
    }

    /// A `.sheet`-presented surface must open with its dismissal control
    /// focused: keyboard users need a defined starting point and a visible
    /// ring. `.defaultFocus` alone does not achieve this (G-04-8), so these
    /// journeys assert it on the real presentation path rather than trusting
    /// the modifier.
    ///
    /// Each cause gets its own line, because the CI evidence sanitizer strips
    /// assertion messages and keeps only file:line.
    private func assertDismissalOwnsFocus(_ identifier: String, _ moment: String) {
        let app = harness.app
        let anyFocused = app.buttons.allElementsBoundByIndex
            .contains { $0.value(forKey: "hasKeyboardFocus") as? Bool == true }
        // Fails here => focus was never placed at all in this sheet.
        XCTAssertTrue(anyFocused, "no button owns focus \(moment) -- \(focusReport())")
        // Fails here => the dismissal control is not even present.
        XCTAssertTrue(app.buttons[identifier].exists, "no dismissal control \(moment)")
        // Fails here => focus landed on some other control instead.
        XCTAssertEqual(
            app.buttons[identifier].value(forKey: "hasKeyboardFocus") as? Bool, true,
            "the dismissal control must own focus \(moment) -- \(focusReport())"
        )
    }

    // MARK: - Shared navigation (mirrors StorageInteractionTests -- the flagless precedent)

    private func launch(_ profile: UITestHarness.Profile) {
        harness?.app.terminate()
        harness = UITestHarness(profile: profile)
        harness.launch(settledAt: "playstead.surface.library")
    }

    private func showList() {
        harness.element("playstead.control.show-list", type: .button).click()
        XCTAssertTrue(harness.element("playstead.surface.game-list").waitForExistence(timeout: 5))
    }

    private func openSurface(control: String, root: String) {
        harness.element(control, type: .button).click()
        XCTAssertTrue(harness.element(root).waitForExistence(timeout: 5), "navigation dead-ended before reaching \(root)")
    }

    private func uniqueButton(labeled label: String) -> XCUIElement {
        harness.app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}

/// The fixed synthetic asset id `.saveRestorable` seeds
/// (`DeterministicProfile.saveRestorableAssetID`), mirrored here because
/// the UI test target cannot import the app target's private constant.
private enum GameRowSummaryIdentifier {
    static let saveRestorable = "playstead.game.00000000-0000-7000-8000-000000000091.summary"
}
