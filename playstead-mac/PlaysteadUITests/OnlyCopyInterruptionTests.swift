import XCTest

/// Drives the real `OnlyCopyInterruptiveSheet` inside a genuine hosted
/// window via `OnlyCopyInterruptionHarnessRootView`
/// (`PLAYSTEAD_UI_TEST_ONLY_COPY_INTERRUPTION=<context>`) and its
/// sibling neutral harness (`PLAYSTEAD_UI_TEST_ONLY_COPY_NEUTRAL=1`) --
/// a UI test target cannot `@testable import Playstead`, so these
/// env-var-gated production seams (mirroring
/// `ConflictComparisonHarnessRootView`'s precedent) are the accessible
/// surface. No production destructive-intent call site (remove local
/// copy, eviction, unpair, sign out, delete game) is wired to present
/// this sheet yet -- these tests prove the sheet and its gate are
/// already correct, keyboard-operable, and never self-triggering,
/// for whichever future call site wires each of the five.
@MainActor
final class OnlyCopyInterruptionTests: XCTestCase {
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private enum ID {
        static let surface = "playstead.save.only-copy-interruptive"
        static let title = "playstead.save.only-copy-interruptive.title"
        static let body = "playstead.save.only-copy-interruptive.body"
        static let export = "playstead.save.only-copy-interruptive.export"
        static let cancel = "playstead.save.only-copy-interruptive.cancel"
        static let removeAnyway = "playstead.save.only-copy-interruptive.remove-anyway"
        static let noModal = "playstead.harness.only-copy-interruption.no-modal"
        static let result = "playstead.harness.only-copy-interruption.result"
        static let revisionsRemaining = "playstead.harness.only-copy-interruption.revisions-remaining"
        static let neutralRoot = "playstead.harness.only-copy-neutral"
    }

    private func launchHarness(context: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PLAYSTEAD_UI_TEST_ONLY_COPY_INTERRUPTION"] = context
        app.launch()
        self.app = app
        let root = app.descendants(matching: .any)["playstead.harness.only-copy-interruption"]
        XCTAssertTrue(root.waitForExistence(timeout: 10), "the only-copy interruption harness did not settle")
        return app
    }

    private func launchNeutralHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PLAYSTEAD_UI_TEST_ONLY_COPY_NEUTRAL"] = "1"
        app.launch()
        self.app = app
        let root = app.descendants(matching: .any)[ID.neutralRoot]
        XCTAssertTrue(root.waitForExistence(timeout: 10), "the neutral harness did not settle")
        return app
    }

    // MARK: - The five destructive-intent points all reach the same modal

    func testRemovingLocalCopyWithOnlyOnThisMacVersionsRaisesTheModal() {
        let app = launchHarness(context: "remove_local_copy")
        XCTAssertTrue(app.staticTexts[ID.title].exists)
    }

    func testEvictingAGameWithOnlyOnThisMacVersionsRaisesTheModal() {
        let app = launchHarness(context: "eviction")
        XCTAssertTrue(app.staticTexts[ID.title].exists)
    }

    func testUnpairingRaisesTheModalWhenAnyGameHasOnlyOnThisMacVersions() {
        let app = launchHarness(context: "unpair")
        XCTAssertTrue(app.staticTexts[ID.title].exists)
    }

    func testSigningOutRaisesTheModalUnderTheSameCondition() {
        let app = launchHarness(context: "sign_out")
        XCTAssertTrue(app.staticTexts[ID.title].exists)
    }

    func testDeletingAGameRaisesTheModalUnderTheSameCondition() {
        let app = launchHarness(context: "delete_game")
        XCTAssertTrue(app.staticTexts[ID.title].exists)
    }

    // MARK: - Zero only-on-this-Mac versions raises no modal at all

    func testSameActionsWithZeroOnlyOnThisMacVersionsRaiseNoModal() {
        let app = launchHarness(context: "zero_count")
        XCTAssertFalse(app.staticTexts[ID.title].exists)
        XCTAssertTrue(app.staticTexts[ID.noModal].waitForExistence(timeout: 5))
    }

    // MARK: - Locked copy, three buttons, default is the escape hatch

    func testModalRendersLockedTitleBodyAndThreeButtonsWithExportAsDefault() {
        let app = launchHarness(context: "remove_local_copy")
        XCTAssertEqual(app.staticTexts[ID.title].readableText, "This is the only copy of your progress.")
        XCTAssertTrue(app.staticTexts[ID.body].readableText.contains("3 versions of Metroid Fusion are only on this Mac and nowhere else."))
        XCTAssertTrue(app.buttons[ID.export].exists)
        XCTAssertTrue(app.buttons[ID.cancel].exists)
        XCTAssertTrue(app.buttons[ID.removeAnyway].exists)
        // The default is focused at presentation (D-40's easiest button
        // is the one that saves the user's progress).
        XCTAssertTrue(app.buttons[ID.export].value(forKey: "hasKeyboardFocus") as? Bool == true)
    }

    // MARK: - Activating the default does not perform the destructive action

    func testActivatingTheDefaultActionExportsRatherThanRemoving() {
        let app = launchHarness(context: "remove_local_copy")
        XCTAssertTrue(app.buttons[ID.export].value(forKey: "hasKeyboardFocus") as? Bool == true)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts[ID.result].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[ID.result].readableText, "exported")
    }

    // MARK: - Cancel leaves everything in place

    func testChoosingCancelLeavesEveryRevisionAndCachedByteInPlace() {
        let app = launchHarness(context: "remove_local_copy")
        app.buttons[ID.cancel].click()
        XCTAssertTrue(app.staticTexts[ID.result].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[ID.result].readableText, "cancelled")
        XCTAssertEqual(app.staticTexts[ID.revisionsRemaining].readableText, "3")
    }

    // MARK: - Remove anyway removes cached bytes but never a save revision

    func testChoosingRemoveAnywayLeavesEverySaveRevisionPresent() {
        let app = launchHarness(context: "remove_local_copy")
        app.buttons[ID.removeAnyway].click()
        XCTAssertTrue(app.staticTexts[ID.result].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[ID.result].readableText, "removed")
        // Choosing "Remove anyway" removes cached game bytes and still
        // keeps every save revision (the never-evictable rule, D-40) --
        // the harness's fixed revision count never changes.
        XCTAssertEqual(app.staticTexts[ID.revisionsRemaining].readableText, "3")
    }

    // MARK: - Full keyboard operability with visible focus

    func testModalIsOperableEntirelyByKeyboardWithVisibleFocus() {
        let app = launchHarness(context: "remove_local_copy")
        XCTAssertTrue(app.buttons[ID.export].value(forKey: "hasKeyboardFocus") as? Bool == true)

        var reachedRemoveAnyway = false
        for _ in 0..<10 {
            app.typeKey(.tab, modifierFlags: [])
            if app.buttons[ID.removeAnyway].value(forKey: "hasKeyboardFocus") as? Bool == true {
                reachedRemoveAnyway = true
                break
            }
        }
        XCTAssertTrue(reachedRemoveAnyway, "Tab never reached Remove anyway")

        var reachedCancel = false
        for _ in 0..<10 {
            app.typeKey(.tab, modifierFlags: [])
            if app.buttons[ID.cancel].value(forKey: "hasKeyboardFocus") as? Bool == true {
                reachedCancel = true
                break
            }
        }
        XCTAssertTrue(reachedCancel, "Tab never reached Cancel")

        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.staticTexts[ID.result].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[ID.result].readableText, "cancelled")
    }

    // MARK: - The modal appears at no other time

    func testModalNeverAppearsDuringBrowseLaunchOrSyncWithOnlyOnThisMacVersionsPresent() {
        let app = launchNeutralHarness()
        XCTAssertTrue(app.staticTexts["playstead.harness.only-copy-neutral.browse"].exists)
        XCTAssertTrue(app.staticTexts["playstead.harness.only-copy-neutral.launch"].exists)
        XCTAssertTrue(app.staticTexts["playstead.harness.only-copy-neutral.sync"].exists)
        XCTAssertFalse(app.staticTexts[ID.title].exists)
        XCTAssertFalse(app.otherElements[ID.surface].exists)
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertEqual(app.dialogs.count, 0)
    }
}
