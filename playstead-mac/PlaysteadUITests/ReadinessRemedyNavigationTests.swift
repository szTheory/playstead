import XCTest

@MainActor
final class ReadinessRemedyNavigationTests: XCTestCase {
    private var harness: UITestHarness!

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
    }

    func testBIOSRemedyHasVisibleActionAndKeyboardReturnAtShortHeight() {
        for appearance in ["light", "dark"] {
            launch(.biosAcceptance, appearance: appearance)
            open("playstead.readiness.row.bios.remedy")
            let back = harness.element("playstead.readiness.destination.back", type: .button)
            assertVisible([back, harness.element("playstead.control.choose-bios", type: .button)])
            capture("bios-\(appearance)")
            assertFocus(harness.element("playstead.control.done", type: .button))
            back.typeKey(.escape, modifierFlags: [])
            assertOverviewAndFocus()
            XCTAssertFalse(harness.element("playstead.surface.bios").exists)
            harness.app.terminate()
        }
    }

    func testControllerSettingsAndTestHaveVisibleReturnAndLiveInputAtShortHeight() {
        for appearance in ["light", "dark"] {
            launch(.controllerRecovery, appearance: appearance)
            open("playstead.control.open-controller-settings")
            let back = harness.element("playstead.readiness.destination.back", type: .button)
            let test = harness.element("playstead.controller.test.open", type: .button)
            assertVisible([back, test])
            capture("controller-settings-\(appearance)")
            assertFocus(harness.element("playstead.control.done", type: .button))
            test.clickWhenHittable()
            let returnToSettings = harness.element("playstead.controller.test.done", type: .button)
            let press = harness.element("playstead.controller.test.press-a", type: .button)
            assertVisible([returnToSettings, press])
            assertFocus(harness.element("playstead.control.done", type: .button))
            press.clickWhenHittable()
            XCTAssertEqual(harness.element("playstead.controller.input.buttonA").readableText, "Lower face button, pressed")
            harness.element("playstead.controller.test.release-a", type: .button).clickWhenHittable()
            XCTAssertEqual(harness.element("playstead.controller.input.buttonA").readableText, "Lower face button, not pressed")
            capture("controller-test-\(appearance)")
            returnToSettings.clickWhenHittable()
            XCTAssertFalse(harness.element("playstead.surface.controller-test").exists)
            XCTAssertTrue(harness.element("playstead.surface.controller-settings").exists)
            assertFocus(harness.element("playstead.control.done", type: .button))
            back.typeKey(.escape, modifierFlags: [])
            assertOverviewAndFocus()
            harness.app.terminate()
        }
    }

    func testSaveHistoryOpensFromHealthyReadinessAndReturnsAtShortHeight() {
        for appearance in ["light", "dark"] {
            launch(.saveRestorable, appearance: appearance)
            open("playstead.readiness.open-save-history")
            XCTAssertTrue(harness.element("playstead.surface.save-history").awaitExistence(timeout: 5))
            XCTAssertTrue(harness.element("playstead.save-history.session.0.row.0").exists, "the actual committed save was omitted")
            let done = harness.element("playstead.save-history.done", type: .button)
            assertVisible([done])
            assertFocus(done)
            capture("save-history-\(appearance)")
            done.typeKey(.escape, modifierFlags: [])
            assertOverviewAndFocus()
            XCTAssertFalse(harness.element("playstead.surface.save-history").exists)
            harness.app.terminate()
        }
    }

    func testConflictComparisonHasVisibleChoicesAndReturnAtShortHeight() {
        for appearance in ["light", "dark"] {
            launch(.saveDiverged, appearance: appearance)
            open("playstead.readiness.row.saveState.remedy")
            XCTAssertTrue(harness.element("playstead.surface.conflict-comparison").awaitExistence(timeout: 5))
            let done = harness.element("playstead.conflict-comparison.done", type: .button)
            assertVisible([
                done,
                harness.element("playstead.conflict-comparison.keep-both", type: .button),
                harness.element("playstead.conflict-comparison.side.0.choose", type: .button),
                harness.element("playstead.conflict-comparison.side.1.choose", type: .button)
            ])
            assertFocus(done)
            capture("conflict-\(appearance)")
            done.typeKey(.escape, modifierFlags: [])
            assertOverviewAndFocus()
            XCTAssertTrue(harness.element("playstead.readiness.row.saveState.remedy").exists, "dismissal must retain the unresolved versions")
            open("playstead.readiness.row.saveState.remedy")
            let resolution = appearance == "light"
                ? "playstead.conflict-comparison.side.0.choose"
                : "playstead.conflict-comparison.keep-both"
            harness.focusContainedAction(resolution, rootIdentifier: "playstead.surface.conflict-comparison")
            harness.element(resolution, type: .button).typeKey(.space, modifierFlags: [])
            XCTAssertFalse(harness.element("playstead.surface.conflict-comparison").waitForExistence(timeout: 2), "a successful choice must return to readiness")
            assertOverviewAndFocus()
            harness.app.terminate()
        }
    }

    private func launch(_ profile: UITestHarness.Profile, appearance: String) {
        harness = UITestHarness(profile: profile, extraEnvironment: [
            "PLAYSTEAD_UI_TEST_WINDOW_SIZE": "960x560",
            "PLAYSTEAD_UI_TEST_APPEARANCE": appearance
        ])
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.readiness").awaitExistence(timeout: 5))
    }

    private func open(_ identifier: String) {
        let action = harness.element(identifier, type: .button)
        XCTAssertTrue(action.awaitExistence(timeout: 5))
        let content = harness.element("playstead.readiness.content")
        for _ in 0..<6 where !action.isHittable { content.swipeUp() }
        harness.focusContainedAction(identifier, rootIdentifier: "playstead.surface.readiness")
        action.typeKey(.space, modifierFlags: [])
    }

    private func assertVisible(_ actions: [XCUIElement]) {
        let readiness = activeSurface
        XCTAssertLessThanOrEqual(readiness.frame.height, 520)
        for action in actions {
            XCTAssertTrue(action.awaitExistence(timeout: 5))
            XCTAssertTrue(action.isHittable, "action is hidden below the initial viewport: \(action.identifier)")
            XCTAssertGreaterThan(action.frame.width, 0)
            XCTAssertGreaterThan(action.frame.height, 0)
            XCTAssertTrue(readiness.frame.insetBy(dx: -1, dy: -1).contains(action.frame), "action overflows readiness: \(action.identifier)")
        }
    }

    private func assertFocus(_ action: XCUIElement) {
        let focus = NSPredicate { _, _ in action.value(forKey: "hasKeyboardFocus") as? Bool == true }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focus, object: nil)], timeout: 5), .completed,
            "Expected focus on \(action.identifier); focused controls: \(harness.app.buttons.allElementsBoundByIndex.filter { $0.value(forKey: "hasKeyboardFocus") as? Bool == true }.map(\.identifier))"
        )
    }

    private func assertOverviewAndFocus() {
        let done = harness.element("playstead.control.done", type: .button)
        XCTAssertTrue(done.awaitExistence(timeout: 5), "return dismissed the readiness sheet")
        assertFocus(done)
    }

    private var activeSurface: XCUIElement {
        for identifier in ["playstead.surface.conflict-comparison", "playstead.surface.save-history", "playstead.surface.readiness"] {
            let surface = harness.element(identifier)
            if surface.exists { return surface }
        }
        return harness.element("playstead.surface.readiness")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: activeSurface.screenshot())
        attachment.name = "readiness-\(name)-960x560"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
