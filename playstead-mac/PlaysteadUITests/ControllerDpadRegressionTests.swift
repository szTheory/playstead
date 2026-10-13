import XCTest

@MainActor
final class ControllerDpadRegressionTests: XCTestCase {
    private var harness: UITestHarness!

    override func setUpWithError() throws {
        continueAfterFailure = false
        harness = UITestHarness(profile: .controllerRecovery)
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
        try super.tearDownWithError()
    }

    func testControllerTestDpadUpStaysInSettingsAndSettingsReopensAtStorage() throws {
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.sidebar.settings").clickWhenHittable()
        let settings = harness.element("playstead.settings")
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "Settings did not open from the sidebar")

        let storagePage = harness.element("playstead.surface.storage")
        XCTAssertTrue(storagePage.awaitExistence(timeout: 5), "Settings should open at its Storage landing pane")
        harness.element("playstead.control.open-controller-settings", type: .radioButton).clickWhenHittable()
        let controllerSettings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(controllerSettings.awaitExistence(timeout: 5), "Controller settings did not open")
        XCTAssertTrue(
            controllerSettings.buttons[UITestControllerName.value].awaitExistence(timeout: 5),
            "the deterministic controller should already be connected and assigned in Settings"
        )

        controllerSettings.buttons["Test controller"].clickWhenHittable()
        let testSurface = harness.element("playstead.surface.controller-test")
        XCTAssertTrue(testSurface.awaitExistence(timeout: 5), "Controller test sheet did not open")
        XCTAssertTrue(
            harness.app.staticTexts["Testing Playstead Test Controller"].exists,
            "the assigned controller's input grid was not rendered"
        )
        let upInput = harness.element("playstead.controller.input.dpadUp")
        let pressUp = harness.element("playstead.controller.test.press-up", type: .button)
        XCTAssertTrue(pressUp.awaitExistence(timeout: 5), "test-only D-pad Up control was not visible")

        pressUp.clickWhenHittable()
        XCTAssertEqual(upInput.readableText, "D-pad Up, pressed", "D-pad Up press did not reach the live input tile")
        XCTAssertTrue(testSurface.exists, "D-pad Up must not dismiss the controller test")
        XCTAssertTrue(settings.exists, "D-pad Up must not navigate away from Settings")
        XCTAssertTrue(controllerSettings.exists, "D-pad Up must not remove the controller settings page")

        harness.element("playstead.controller.test.release-up", type: .button).clickWhenHittable()
        XCTAssertEqual(upInput.readableText, "D-pad Up, not pressed", "D-pad Up release did not clear the live input tile")
        XCTAssertTrue(testSurface.exists, "releasing D-pad Up must leave the controller test open")
        harness.element("playstead.controller.test.done", type: .button).clickWhenHittable()

        harness.element("playstead.sidebar.home").clickWhenHittable()
        harness.element("playstead.sidebar.settings").clickWhenHittable()
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "Settings did not reopen from the sidebar")
        let storageLanding = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            storagePage.exists && !controllerSettings.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [storageLanding], timeout: 5), .completed,
                       "re-entering Settings should settle on Storage with Controller closed")
    }
}
