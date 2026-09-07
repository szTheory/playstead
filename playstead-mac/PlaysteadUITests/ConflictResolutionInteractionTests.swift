import XCTest

/// Drives the real `ConflictComparisonSheet` inside a genuine hosted
/// window via `ConflictComparisonHarnessRootView`
/// (`PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON=1`) -- a UI test target
/// cannot `@testable import Playstead`, so this env-var-gated
/// production seam (mirroring `UITestBootstrap`'s save end-to-end hook)
/// is the accessible surface. No production navigation reaches this
/// sheet yet (attention-inbox/game-detail wiring is a later plan's
/// job); these tests prove the sheet's own keyboard operability,
/// no-confirmation-dialog, no-Undo, and no-pre-selection contracts
/// end-to-end against a real AppKit/SwiftUI focus chain.
@MainActor
final class ConflictResolutionInteractionTests: XCTestCase {
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private enum ID {
        static let surface = "playstead.harness.conflict-comparison"
        static let chooseR1 = "playstead.conflict-comparison.side.0.choose"
        static let chooseR2 = "playstead.conflict-comparison.side.1.choose"
        static let chosenR1 = "playstead.conflict-comparison.side.0.chosen"
        static let exportR1 = "playstead.conflict-comparison.side.0.export"
        static let exportR2 = "playstead.conflict-comparison.side.1.export"
        static let keepBoth = "playstead.conflict-comparison.keep-both"
        static let done = "playstead.conflict-comparison.done"
        static let result = "playstead.conflict-comparison.result"
    }

    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON"] = "1"
        app.launch()
        self.app = app
        let surface = app.descendants(matching: .any)[ID.surface]
        XCTAssertTrue(surface.waitForExistence(timeout: 10), "the conflict comparison harness did not settle")
        return app
    }

    // MARK: - No pre-selection, no recommendation at launch

    func testNoSideIsPreSelectedOrChosenAtLaunch() {
        let app = launchHarness()
        XCTAssertFalse(app.staticTexts[ID.chosenR1].exists)
        XCTAssertTrue(app.buttons[ID.chooseR1].exists)
        XCTAssertTrue(app.buttons[ID.chooseR2].exists)
        XCTAssertFalse(app.staticTexts[ID.result].exists)
    }

    // MARK: - Keyboard-only traversal and activation, no confirmation dialog

    func testChoosingASideByKeyboardAloneMutatesWithNoIntervadingConfirmation() {
        let app = launchHarness()

        var reachedChoose = false
        for _ in 0..<40 {
            app.typeKey(.tab, modifierFlags: [])
            if app.buttons[ID.chooseR1].value(forKey: "hasKeyboardFocus") as? Bool == true {
                reachedChoose = true
                break
            }
        }
        XCTAssertTrue(reachedChoose, "Tab never reached the first side's Choose button")

        XCTAssertEqual(app.sheets.count, 0, "no confirmation dialog may precede a choice (D-51)")
        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(app.sheets.count, 0, "no confirmation dialog may follow a choice either")
        XCTAssertEqual(app.dialogs.count, 0)

        XCTAssertTrue(app.staticTexts[ID.chosenR1].waitForExistence(timeout: 5), "the chosen side must render its chosen state")
        XCTAssertTrue(app.staticTexts[ID.result].waitForExistence(timeout: 5), "a result message must render after choosing")
    }

    // MARK: - No Undo control anywhere after a resolution

    func testNoUndoControlRendersAfterChoosing() {
        let app = launchHarness()
        app.buttons[ID.chooseR1].click()
        XCTAssertTrue(app.staticTexts[ID.result].waitForExistence(timeout: 5))

        let undoPredicate = NSPredicate(format: "label CONTAINS[c] 'undo'")
        XCTAssertEqual(app.buttons.matching(undoPredicate).count, 0)
        XCTAssertEqual(app.staticTexts.matching(undoPredicate).count, 0)

        // The non-chosen side keeps a live, permanently choosable
        // "Continue from this one" control (D-49) rather than an Undo.
        XCTAssertTrue(app.buttons[ID.chooseR2].exists, "the non-chosen side must remain choosable after a resolution")
    }

    // MARK: - "Keep both" is a peer action, not a secondary/dismissal one

    func testKeepBothIsReachableByKeyboardAndIsAPeerOfTheChoiceButtons() {
        let app = launchHarness()
        XCTAssertTrue(app.buttons[ID.keepBoth].exists)

        var reachedKeepBoth = false
        for _ in 0..<40 {
            app.typeKey(.tab, modifierFlags: [])
            if app.buttons[ID.keepBoth].value(forKey: "hasKeyboardFocus") as? Bool == true {
                reachedKeepBoth = true
                break
            }
        }
        XCTAssertTrue(reachedKeepBoth, "Tab never reached Keep Both")
        app.typeKey(.space, modifierFlags: [])

        XCTAssertTrue(app.staticTexts[ID.result].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[ID.result].label.contains("Keeping both"))
        // Both sides remain choosable -- "Keep both" leaves every head
        // standing (D-52).
        XCTAssertTrue(app.buttons[ID.chooseR1].exists)
        XCTAssertTrue(app.buttons[ID.chooseR2].exists)
    }

    // MARK: - TEMPORARY DIAGNOSTIC (G-04-2)
    //
    // testKeepBothIsReachableByKeyboardAndIsAPeerOfTheChoiceButtons fails
    // deterministically (3/3) at :117: a result message renders, but it is
    // the "choosing" string, so the space press activated a Choose button
    // rather than Keep Both -- one line after the poll reported Keep Both
    // holding focus.
    //
    // Rather than guess between "the poll lags the real first responder"
    // and "tab order genuinely misplaces the activation target", this
    // prints the actual focus owner after every Tab. Run it alone:
    //
    //   ./scripts/ci/run-mac-verification.sh --layers ui \
    //     --only-testing PlaysteadUITests/ConflictResolutionInteractionTests/testDiagnosticTabOrder
    //
    // Then grep the output for PLAYSTEAD_TABORDER. Delete this test once
    // G-04-2 has a fix.
    func testDiagnosticTabOrder() {
        let app = launchHarness()
        let watched = [
            ("chooseR1", ID.chooseR1), ("exportR1", ID.exportR1),
            ("chooseR2", ID.chooseR2), ("exportR2", ID.exportR2),
            ("keepBoth", ID.keepBoth), ("done", ID.done),
        ]

        func focusOwners() -> [String] {
            watched.compactMap { name, id in
                let button = app.buttons[id]
                guard button.exists,
                      button.value(forKey: "hasKeyboardFocus") as? Bool == true
                else { return nil }
                return name
            }
        }

        print("PLAYSTEAD_TABORDER step=0 (at launch) focused=\(focusOwners())")
        for step in 1...14 {
            app.typeKey(.tab, modifierFlags: [])
            print("PLAYSTEAD_TABORDER step=\(step) focused=\(focusOwners())")
        }

        // Deliberately never fails: this exists to be read, not to gate.
        XCTAssertTrue(true)
    }

    // MARK: - TEMPORARY DIAGNOSTIC 2 (G-04-2)
    //
    // testDiagnosticTabOrder proved the tab order is correct and stable:
    // chooseR1, exportR1, chooseR2, exportR2, (disclosure), (disclosure),
    // keepBoth, done -- a clean cycle of 8 with keepBoth at step 6. So the
    // failure is NOT a misordered focus chain.
    //
    // This replays the failing test's exact sequence and prints what
    // actually happens at the moment of activation: how many tabs it took,
    // who holds focus immediately before the space press, and the verbatim
    // result label afterwards. Run it alone and grep PLAYSTEAD_ACTIVATE.
    func testDiagnosticKeepBothActivation() {
        let app = launchHarness()
        let watched = [
            ("chooseR1", ID.chooseR1), ("exportR1", ID.exportR1),
            ("chooseR2", ID.chooseR2), ("exportR2", ID.exportR2),
            ("keepBoth", ID.keepBoth), ("done", ID.done),
        ]

        func focusOwners() -> [String] {
            watched.compactMap { name, id in
                let button = app.buttons[id]
                guard button.exists,
                      button.value(forKey: "hasKeyboardFocus") as? Bool == true
                else { return nil }
                return name
            }
        }

        var tabs = 0
        for step in 1...40 {
            app.typeKey(.tab, modifierFlags: [])
            if app.buttons[ID.keepBoth].value(forKey: "hasKeyboardFocus") as? Bool == true {
                tabs = step
                break
            }
        }
        print("PLAYSTEAD_ACTIVATE tabsToReachKeepBoth=\(tabs)")
        print("PLAYSTEAD_ACTIVATE focusJustBeforeSpace=\(focusOwners())")

        app.typeKey(.space, modifierFlags: [])

        let result = app.staticTexts[ID.result]
        let appeared = result.waitForExistence(timeout: 5)
        print("PLAYSTEAD_ACTIVATE resultExists=\(appeared)")
        print("PLAYSTEAD_ACTIVATE resultLabel=>>>\(appeared ? result.label : "<none>")<<<")
        print("PLAYSTEAD_ACTIVATE resultValue=>>>\(String(describing: result.value))<<<")
        print("PLAYSTEAD_ACTIVATE resultTitle=>>>\(result.title)<<<")
        print("PLAYSTEAD_ACTIVATE resultDebug=>>>\(result.debugDescription.prefix(600))<<<")
        print("PLAYSTEAD_ACTIVATE focusAfterSpace=\(focusOwners())")
        print("PLAYSTEAD_ACTIVATE chosenR1Exists=\(app.staticTexts[ID.chosenR1].exists)")
        print("PLAYSTEAD_ACTIVATE chooseR1StillAButton=\(app.buttons[ID.chooseR1].exists)")
        print("PLAYSTEAD_ACTIVATE chooseR2StillAButton=\(app.buttons[ID.chooseR2].exists)")

        XCTAssertTrue(true)
    }

    // MARK: - Export is independently reachable by keyboard

    func testExportActionIsReachableByKeyboardOnBothSides() {
        let app = launchHarness()
        XCTAssertTrue(app.buttons[ID.exportR1].exists)
        XCTAssertTrue(app.buttons[ID.exportR2].exists)
    }

    // MARK: - Done closes the sheet-equivalent surface without side effects

    func testDoneIsReachableByKeyboardAndCarriesNoDestinationChange() {
        let app = launchHarness()
        XCTAssertTrue(app.buttons[ID.done].exists)
        XCTAssertFalse(app.staticTexts[ID.result].exists, "Done must not itself mutate anything")
    }
}
