import XCTest

@MainActor
final class ControllerHardwareIntegrationTests: XCTestCase {
    private var harness: UITestHarness!
    private var gamepad: VirtualGamepad!

    override func setUpWithError() throws {
        continueAfterFailure = false
        harness = UITestHarness(profile: .storage)
        gamepad = VirtualGamepad()
    }

    override func tearDownWithError() throws {
        gamepad?.disconnect()
        harness?.app.terminate()
        gamepad = nil
        harness = nil
        try super.tearDownWithError()
    }

    func testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch() throws {
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        harness.element("playstead.control.open-controller-settings", type: .button).clickWhenHittable()
        let settings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "PLAYSTEAD_FAILURE_STAGE[settings-route]")
        XCTAssertTrue(settings.staticTexts["No controller connected. Keyboard controls are available."].exists,
                      "PLAYSTEAD_FAILURE_STAGE[initial-non-vacuity]")

        XCTAssertThrowsError(try gamepad.connect(using: Data([0x00])), "invalid descriptors must never reach macOS")
        try gamepad.connect()
        let controller = settings.buttons[VirtualGamepad.controllerName]
        XCTAssertTrue(controller.awaitExistence(timeout: 10), "PLAYSTEAD_FAILURE_STAGE[gc-enumeration]")

        let openTest = harness.element("playstead.controller.test.open", type: .button)
        for _ in 0..<8 where !openTest.isHittable { settings.swipeUp() }
        openTest.clickWhenHittable()
        let buttonA = harness.element("playstead.controller.input.buttonA", type: .staticText)
        let dpadUp = harness.element("playstead.controller.input.dpadUp", type: .staticText)
        XCTAssertTrue(buttonA.awaitExistence(timeout: 5), "PLAYSTEAD_FAILURE_STAGE[controller-test-view]")
        XCTAssertEqual(buttonA.readableText, "Lower face button, not pressed")
        XCTAssertEqual(dpadUp.readableText, "D-pad Up, not pressed")

        try gamepad.press(0x01)
        assertLabel("Lower face button, pressed", on: buttonA, stage: "gamecontroller-press-callback")

        try gamepad.release()
        assertLabel("Lower face button, not pressed", on: buttonA, stage: "gamecontroller-release-callback")

        try gamepad.direction(0)
        assertLabel("D-pad Up, pressed", on: dpadUp, stage: "gamecontroller-dpad-up-callback")

        try gamepad.direction(8)
        assertLabel("D-pad Up, not pressed", on: dpadUp, stage: "gamecontroller-dpad-release-callback")
        harness.element("playstead.controller.test.done", type: .button).clickWhenHittable()

        gamepad.disconnect()
        XCTAssertTrue(settings.staticTexts["No controller connected. Keyboard controls are available."].awaitExistence(timeout: 10),
                      "PLAYSTEAD_FAILURE_STAGE[detach]")

        try gamepad.connect()
        XCTAssertTrue(controller.awaitExistence(timeout: 10), "PLAYSTEAD_FAILURE_STAGE[reconnect]")

        openTest.clickWhenHittable()
        XCTAssertTrue(buttonA.awaitExistence(timeout: 5), "PLAYSTEAD_FAILURE_STAGE[controller-test-view-after-reconnect]")
        XCTAssertEqual(buttonA.readableText, "Lower face button, not pressed")

        try gamepad.press(0x01)
        assertLabel("Lower face button, pressed", on: buttonA, stage: "gamecontroller-press-callback-after-reconnect")

        try gamepad.release()
        assertLabel("Lower face button, not pressed", on: buttonA, stage: "gamecontroller-release-callback-after-reconnect")
    }

    private func assertLabel(
        _ label: String,
        on element: XCUIElement,
        stage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "PLAYSTEAD_FAILURE_STAGE[\(stage)]", file: file, line: line)
    }
}
