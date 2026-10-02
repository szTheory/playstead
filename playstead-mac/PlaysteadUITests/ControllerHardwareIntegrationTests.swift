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
        XCTAssertTrue(settings.staticTexts["No controller connected. Keyboard and pointer remain fully available."].exists,
                      "PLAYSTEAD_FAILURE_STAGE[initial-non-vacuity]")

        XCTAssertThrowsError(try gamepad.connect(using: Data([0x00])), "invalid descriptors must never reach macOS")
        try gamepad.connect()
        let controller = settings.buttons[VirtualGamepad.controllerName]
        XCTAssertTrue(controller.awaitExistence(timeout: 10), "PLAYSTEAD_FAILURE_STAGE[gc-enumeration]")

        gamepad.disconnect()
        XCTAssertTrue(settings.staticTexts["No controller connected. Keyboard and pointer remain fully available."].awaitExistence(timeout: 10),
                      "PLAYSTEAD_FAILURE_STAGE[detach]")

        try gamepad.connect()
        XCTAssertTrue(controller.awaitExistence(timeout: 10), "PLAYSTEAD_FAILURE_STAGE[reconnect]")
    }
}
