import XCTest
import AppKit

@MainActor
final class ControllerNoHIDIntegrationTests: XCTestCase {
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

    func testSimulatedControllerMappingLifecyclePersistsAndResets() throws {
        harness = UITestHarness(profile: .controllerRecovery, persistentSession: true)
        harness.launch(settledAt: "playstead.surface.library")
        let readiness = harness.element("playstead.surface.readiness")
        let settings = harness.element("playstead.surface.controller-settings")
        let openReadiness = harness.element("playstead.control.open-readiness", type: .button)
        openReadiness.clickWhenHittable()
        openReadinessControllerSettings()
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "controller settings did not open")

        let controller = settings.buttons[UITestControllerName.value]
        XCTAssertTrue(controller.awaitExistence(timeout: 5), "fixed synthetic descriptor was not visible")
        controller.clickWhenHittable()
        let readinessContent = harness.element("playstead.readiness.content")

        let openTest = harness.element("playstead.controller.test.open", type: .button)
        for _ in 0..<8 where !openTest.isHittable { readinessContent.swipeUp() }
        openTest.clickWhenHittable()
        let input = harness.element("playstead.controller.input.buttonA")
        let press = harness.element("playstead.controller.test.press-a", type: .button)
        for _ in 0..<8 where !press.isHittable { readinessContent.swipeUp() }
        press.clickWhenHittable()
        XCTAssertEqual(input.readableText, "Lower face button, pressed", "named press did not reach the production live-input state")
        harness.element("playstead.controller.test.release-a", type: .button).clickWhenHittable()
        XCTAssertEqual(input.readableText, "Lower face button, not pressed", "named release did not clear the production live-input state")
        harness.element("playstead.controller.test.done", type: .button).clickWhenHittable()

        remapInput("A", to: "buttonB", in: settings)
        XCTAssertTrue(
            mappingControl("A", in: settings).readableText.contains("Right face button"),
            "the visible mapping did not reflect the committed remap"
        )

        harness.relaunch(settledAt: "playstead.surface.library")
        readinessAccess(openReadiness: "playstead.control.open-readiness")
        let relaunchedSettings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(relaunchedSettings.awaitExistence(timeout: 5), "settings did not reopen after remap relaunch")
        XCTAssertTrue(
            mappingControl("A", in: relaunchedSettings).readableText.contains("Right face button"),
            "the remapped value did not survive app relaunch for the fixed synthetic descriptor"
        )
        resetMapping(in: relaunchedSettings, content: harness.element("playstead.readiness.content"))
        XCTAssertTrue(
            mappingControl("A", in: relaunchedSettings).readableText.contains("Lower face button"),
            "reset did not publish the committed default mapping"
        )

        harness.relaunch(settledAt: "playstead.surface.library")
        readinessAccess(openReadiness: "playstead.control.open-readiness")
        let resetSettings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(resetSettings.awaitExistence(timeout: 5), "settings did not reopen after reset relaunch")
        XCTAssertTrue(
            mappingControl("A", in: resetSettings).readableText.contains("Lower face button"),
            "the committed default mapping did not survive app relaunch"
        )

        let testAfterRelaunch = harness.element("playstead.controller.test.open", type: .button)
        let resetContent = harness.element("playstead.readiness.content")
        for _ in 0..<8 where !testAfterRelaunch.isHittable { resetContent.swipeUp() }
        testAfterRelaunch.clickWhenHittable()
        let disconnect = harness.element("playstead.controller.test.disconnect", type: .button)
        for _ in 0..<8 where !disconnect.isHittable { resetContent.swipeUp() }
        disconnect.clickWhenHittable()
        XCTAssertTrue(harness.app.staticTexts["No active controller is connected."].awaitExistence(timeout: 5))
        harness.element("playstead.controller.test.done", type: .button).clickWhenHittable()
        let closeReadiness = readiness.buttons["playstead.control.done"]
        for _ in 0..<8 where !closeReadiness.isHittable { resetContent.swipeDown() }
        closeReadiness.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.controller.recovery-banner").awaitExistence(timeout: 5))

        moveToRecentlyPlayedWithKeyboard(failureStage: "mapping-lifecycle-keyboard-fallback")
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        openReadinessControllerSettings()
        XCTAssertTrue(readiness.awaitExistence(timeout: 5), "pointer activation failed while no controller was assigned")
        XCTAssertTrue(
            harness.app.staticTexts["No controller connected. Keyboard controls are available."].exists,
            "keyboard fallback copy was absent while the synthetic controller remained disconnected"
        )
    }

    func testRecoveryNoticeKeyboardDismissalPreservesFocusAndBrowsing() throws {
        harness.launch(settledAt: "playstead.surface.library")
        let sidebar = harness.element("playstead.surface.sidebar")
        harness.element("playstead.sidebar.home").clickWhenHittable()
        let focusBefore = sidebar.value(forKey: "hasKeyboardFocus") as? Bool
        XCTAssertEqual(focusBefore, true, "sidebar must own focus before disconnect")
        // The finite test shortcut emits a real disconnect while the sidebar
        // keeps focus; clicking the detach test button would steal it itself.
        sidebar.typeKey("d", modifierFlags: [.command, .shift])
        let banner = harness.element("playstead.controller.recovery-banner")
        XCTAssertTrue(banner.awaitExistence(timeout: 5))
        XCTAssertEqual(sidebar.value(forKey: "hasKeyboardFocus") as? Bool, true,
            "notice appearance stole keyboard focus")
        activateWithKeyboardFocus("playstead.controller.recovery-banner.dismiss",
            failureStage: "notice-keyboard-dismiss")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        XCTAssertTrue(harness.element("playstead.surface.library").exists)
        sidebar.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(harness.element("playstead.surface.shelf.continue").awaitExistence(timeout: 5),
            "keyboard browsing must work after notice dismissal")
    }

    func testRecoveryNoticeControllerNavigationDismissesAndReturnsToBrowsing() throws {
        prepareNoticeWithSpareController()
        let banner = harness.element("playstead.controller.recovery-banner")
        let dismiss = harness.element("playstead.controller.recovery-banner.dismiss", type: .button)
        harness.app.typeKey("u", modifierFlags: [.command, .shift])
        let focused = NSPredicate { _, _ in dismiss.value as? String == "Controller focused" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: nil)], timeout: 5), .completed,
            "assigned spare's D-pad must reach the production notice focus target")
        XCTAssertTrue(dismiss.isHittable)
        harness.app.typeKey("r", modifierFlags: [.command, .shift])
        harness.app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5), "controller Confirm must dismiss the notice")
        harness.app.typeKey("x", modifierFlags: [.command, .shift])
        harness.app.typeKey("a", modifierFlags: [.command, .shift])
        // Confirm from the restored sidebar enters the first game; it must
        // not re-dismiss a stale notice or accidentally launch that game.
        XCTAssertTrue(harness.element("playstead.surface.library").exists)
        XCTAssertFalse(harness.element("playstead.surface.readiness").exists)
        XCTAssertTrue(harness.element("playstead.surface.game-card").exists)
        XCTAssertFalse(banner.exists)
        harness.app.typeKey("x", modifierFlags: [.command, .shift])
        harness.app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(harness.element("playstead.surface.readiness").awaitExistence(timeout: 5),
            "a fresh controller Confirm must activate the focused game's readiness after dismissal")
    }

    func testRecoveryNoticeAccessibilityContractAndDismissalPreservesState() throws {
        prepareNoticeWithSpareController()
        let banner = harness.element("playstead.controller.recovery-banner")
        let dismiss = banner.descendants(matching: .button)["playstead.controller.recovery-banner.dismiss"]
        XCTAssertTrue(dismiss.awaitExistence(timeout: 5), "dismiss must remain a child button of the named notice")
        XCTAssertTrue(banner.label.contains("Playstead Test Controller disconnected"))
        XCTAssertTrue(banner.label.contains("Keyboard and pointer still work"))
        XCTAssertEqual(dismiss.label, "Dismiss controller disconnected notice")
        XCTAssertTrue(dismiss.isEnabled)
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThan(dismiss.frame.width, 0)
        try harness.audit(.sufficientElementDescription, rootIdentifier: "playstead.controller.recovery-banner")
        try harness.audit(.action, rootIdentifier: "playstead.controller.recovery-banner")
        if ProcessInfo.processInfo.environment["PLAYSTEAD_NOTICE_VOICEOVER_EXTERNAL_ACTION"] == "1" {
            // Agent-driven qualification: XCTest observes the real shell while
            // the trusted native driver invokes the default AX action. XCTest's
            // own event service times out for VO function-key chords on this Mac.
            XCTAssertFalse(voiceOverRunning, "external journey must begin with VoiceOver off")
            print("NOTICE_VOICEOVER_EXTERNAL_READY")
            let dismissed = NSPredicate { _, _ in !banner.exists }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: nil)], timeout: 180), .completed,
                "the native default accessibility action must dismiss the actual notice")
            XCTAssertTrue(voiceOverRunning, "VoiceOver must still be running when its action is observed")
            XCTAssertEqual(harness.element("playstead.harness.notice-accessibility-activation").readableText, "1",
                "the native default accessibility action must run; a pointer click is insufficient")
            print("NOTICE_VOICEOVER_ACTION_OBSERVED")
            let restored = NSPredicate { [weak self] _, _ in self?.voiceOverRunning == false }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: nil)], timeout: 120), .completed,
                "native driver must restore VoiceOver to off before the test continues")
            print("NOTICE_VOICEOVER_RESTORED")
            harness.app.activate()
        } else {
            dismiss.clickWhenHittable()
        }
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        harness.element("playstead.sidebar.settings").clickWhenHittable()
        harness.element("playstead.control.open-controller-settings", type: .radioButton).clickWhenHittable()
        let settings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(settings.buttons["Playstead Spare Controller, active"].awaitExistence(timeout: 5),
            "dismissal must preserve the spare controller assignment")
        XCTAssertFalse(settings.buttons[UITestControllerName.value].exists,
            "dismissal must not turn the disconnected primary into a connected controller")
    }

    private var voiceOverRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.VoiceOver" && !$0.isTerminated
        }
    }

    private func prepareNoticeWithSpareController() {
        harness.launch(settledAt: "playstead.surface.library")
        harness.app.typeKey("s", modifierFlags: [.command, .shift])
        harness.app.typeKey("d", modifierFlags: [.command, .shift])
        XCTAssertTrue(harness.element("playstead.controller.recovery-banner").awaitExistence(timeout: 5))
    }

    private func openReadinessControllerSettings() {
        let opener = harness.element("playstead.control.open-controller-settings", type: .button)
        let content = harness.element("playstead.readiness.content")
        for _ in 0..<6 where !opener.isHittable { content.swipeUp() }
        opener.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.controller-settings").awaitExistence(timeout: 5))
    }

    private func readinessAccess(openReadiness identifier: String) {
        harness.element(identifier, type: .button).clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.readiness").awaitExistence(timeout: 5))
        openReadinessControllerSettings()
    }

    private func remapInput(_ inputName: String, to controllerInput: String, in settings: XCUIElement) {
        // SwiftUI Menu exposes AXMenuButton on macOS, not AXButton.
        let mapping = mappingControl(inputName, in: settings)
        XCTAssertTrue(mapping.awaitExistence(timeout: 5), "mapping menu for \(inputName) is missing")
        mapping.clickWhenHittable()
        let choice = settings.descendants(matching: .menuItem)["playstead.controller.mapping.choice.\(controllerInput)"]
        XCTAssertTrue(choice.awaitExistence(timeout: 5), "mapping menu did not open for \(inputName)")
        choice.clickWhenHittable()
    }

    private func mappingControl(_ inputName: String, in settings: XCUIElement) -> XCUIElement {
        settings.descendants(matching: .menuButton)["playstead.controller.mapping.\(inputName)"]
    }

    private func resetMapping(in settings: XCUIElement, content: XCUIElement) {
        let reset = harness.element("playstead.controller.mapping.reset", type: .button)
        for _ in 0..<8 where !reset.isHittable { content.swipeUp() }
        reset.clickWhenHittable()
    }

    func testSimulatedControllerInputAndReconnectPreserveFallback() throws {
        harness.launch(settledAt: "playstead.surface.library")
        let openReadiness = harness.element("playstead.control.open-readiness", type: .button)
        XCTAssertTrue(openReadiness.awaitExistence(timeout: 5), "synthetic game readiness action was not visible")
        openReadiness.clickWhenHittable()
        openReadinessControllerSettings()

        let settings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "finite controller profile did not reach production settings")
        let controller = settings.buttons[UITestControllerName.value]
        XCTAssertTrue(controller.awaitExistence(timeout: 5), "synthetic controller row was not visible")

        let openControllerTest = settings.buttons["Test controller"]
        XCTAssertTrue(openControllerTest.awaitExistence(timeout: 5), "controller test action was not present")
        let readinessContent = harness.element("playstead.readiness.content")
        for _ in 0..<6 where !openControllerTest.isHittable {
            readinessContent.swipeUp()
        }
        openControllerTest.clickWhenHittable()
        let input = harness.element("playstead.controller.input.buttonA")
        for _ in 0..<6 where !input.exists { readinessContent.swipeUp() }
        XCTAssertTrue(input.awaitExistence(timeout: 5), "production input cell was not visible inside the controller test destination")
        XCTAssertEqual(input.readableText, "Lower face button, not pressed")

        let doneID = "playstead.controller.test.done"
        let pressID = "playstead.controller.test.press-a"
        let releaseID = "playstead.controller.test.release-a"
        let disconnectID = "playstead.controller.test.disconnect"
        let pressA = harness.element(pressID, type: .button)
        for _ in 0..<6 where !pressA.isHittable { readinessContent.swipeUp() }
        pressA.clickWhenHittable()
        XCTAssertEqual(input.readableText, "Lower face button, pressed", "named press did not reach ControllerHost's live state")
        harness.element(releaseID, type: .button).clickWhenHittable()
        XCTAssertEqual(input.readableText, "Lower face button, not pressed", "named release did not clear ControllerHost's live state")

        harness.element(disconnectID, type: .button).clickWhenHittable()
        XCTAssertTrue(
            harness.app.staticTexts["No active controller is connected."].awaitExistence(timeout: 5),
            "disconnect did not render the persistent disconnected state"
        )
        let reconnectID = "playstead.controller.test.reconnect"
        activateWithKeyboardFocus(
            reconnectID,
            failureStage: "simulated-controller-keyboard-reconnect"
        )

        XCTAssertTrue(input.awaitExistence(timeout: 5), "keyboard reconnect did not restore the controller input view")
        for _ in 0..<6 where !input.exists { readinessContent.swipeUp() }
        XCTAssertTrue(input.awaitExistence(timeout: 5), "reconnected input view was not visible inside the reconnected controller test destination")
        XCTAssertEqual(input.readableText, "Lower face button, not pressed", "reconnect retained a stale pressed input")
        let done = harness.element(doneID, type: .button)
        for _ in 0..<6 where !done.isHittable { readinessContent.swipeDown() }
        done.clickWhenHittable()
        XCTAssertTrue(settings.exists, "pointer dismissal should return to Controller Settings")
        XCTAssertTrue(controller.awaitExistence(timeout: 5), "reconnect did not restore the controller assignment")
    }

    func testSimulatedDetachShowsNonModalRecoveryAndPreservesFallback() throws {
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        openReadinessControllerSettings()

        let readiness = harness.element("playstead.surface.readiness")
        XCTAssertTrue(readiness.awaitExistence(timeout: 5), "synthetic game readiness sheet was not visible")
        let settings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "finite controller profile did not reach production settings")
        XCTAssertTrue(settings.buttons[UITestControllerName.value].awaitExistence(timeout: 5))

        let readinessContent = harness.element("playstead.readiness.content")
        let openControllerTest = settings.buttons["Test controller"]
        XCTAssertTrue(openControllerTest.awaitExistence(timeout: 5), "controller test action was not present")
        for _ in 0..<6 where !openControllerTest.isHittable { readinessContent.swipeUp() }
        openControllerTest.clickWhenHittable()

        let disconnect = harness.element("playstead.controller.test.disconnect", type: .button)
        for _ in 0..<6 where !disconnect.isHittable { readinessContent.swipeUp() }
        disconnect.clickWhenHittable()
        XCTAssertTrue(
            harness.app.staticTexts["No active controller is connected."].awaitExistence(timeout: 5),
            "simulated detach did not update the production controller test"
        )

        let closeControllerTest = harness.element("playstead.controller.test.done", type: .button)
        for _ in 0..<6 where !closeControllerTest.isHittable { readinessContent.swipeDown() }
        closeControllerTest.clickWhenHittable()
        XCTAssertFalse(
            harness.element("playstead.surface.controller-test").exists,
            "the inline controller test panel must close before the shell recovery notice is checked"
        )

        let closeReadiness = readiness.buttons["playstead.control.done"]
        for _ in 0..<6 where !closeReadiness.isHittable { readinessContent.swipeDown() }
        closeReadiness.clickWhenHittable()
        XCTAssertFalse(readiness.waitForExistence(timeout: 2), "readiness sheet should be dismissed while detached")

        let recoveryBanner = harness.element("playstead.controller.recovery-banner")
        XCTAssertTrue(
            recoveryBanner.awaitExistence(timeout: 5),
            "assigned simulated controller disconnect must show a non-modal shell recovery notice"
        )
        XCTAssertTrue(
            recoveryBanner.readableText.contains("Playstead Test Controller disconnected"),
            "recovery notice must identify the disconnected controller"
        )

        moveToRecentlyPlayedWithKeyboard(failureStage: "recovery-banner-keyboard-navigation")
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        openReadinessControllerSettings()
        XCTAssertTrue(readiness.awaitExistence(timeout: 5), "same synthetic game's readiness sheet did not reopen")
        XCTAssertTrue(recoveryBanner.exists, "pointer activation must succeed while the recovery notice remains visible")
        let reconnectSettings = harness.element("playstead.surface.controller-settings")
        let reopenControllerTest = reconnectSettings.buttons["Test controller"]
        for _ in 0..<6 where !reopenControllerTest.isHittable { readinessContent.swipeUp() }
        reopenControllerTest.clickWhenHittable()
        let reconnect = harness.element("playstead.controller.test.reconnect", type: .button)
        for _ in 0..<6 where !reconnect.isHittable { readinessContent.swipeUp() }
        reconnect.clickWhenHittable()
        let closeReconnectedTest = harness.element("playstead.controller.test.done", type: .button)
        // Return from live testing before checking the settings assignment.
        for _ in 0..<6 where !closeReconnectedTest.isHittable { readinessContent.swipeUp() }
        closeReconnectedTest.clickWhenHittable()
        XCTAssertTrue(
            reconnectSettings.buttons[UITestControllerName.value].awaitExistence(timeout: 5),
            "the finite reconnect control must restore the production controller assignment"
        )
        let closeReconnectedReadiness = readiness.buttons["playstead.control.done"]
        for _ in 0..<6 where !closeReconnectedReadiness.isHittable { readinessContent.swipeDown() }
        closeReconnectedReadiness.clickWhenHittable()
        XCTAssertFalse(recoveryBanner.waitForExistence(timeout: 2), "reconnect must clear the notice without relaunch")

        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        openReadinessControllerSettings()
        XCTAssertTrue(readiness.awaitExistence(timeout: 5), "readiness sheet did not reopen for the dismissal negative control")
        let secondSettings = harness.element("playstead.surface.controller-settings")
        let secondOpenControllerTest = secondSettings.buttons["Test controller"]
        for _ in 0..<6 where !secondOpenControllerTest.isHittable { readinessContent.swipeUp() }
        secondOpenControllerTest.clickWhenHittable()
        let secondDisconnect = harness.element("playstead.controller.test.disconnect", type: .button)
        for _ in 0..<6 where !secondDisconnect.isHittable { readinessContent.swipeUp() }
        secondDisconnect.clickWhenHittable()
        let closeSecondControllerTest = harness.element("playstead.controller.test.done", type: .button)
        for _ in 0..<6 where !closeSecondControllerTest.isHittable { readinessContent.swipeDown() }
        closeSecondControllerTest.clickWhenHittable()
        let closeSecondReadiness = readiness.buttons["playstead.control.done"]
        for _ in 0..<6 where !closeSecondReadiness.isHittable { readinessContent.swipeDown() }
        closeSecondReadiness.clickWhenHittable()
        XCTAssertTrue(recoveryBanner.awaitExistence(timeout: 5), "second simulated detach did not show the recovery notice")

        harness.element("playstead.controller.recovery-banner.dismiss", type: .button).clickWhenHittable()
        XCTAssertFalse(recoveryBanner.waitForExistence(timeout: 2), "dismissal should hide only the recovery notice")
        moveToRecentlyPlayedWithKeyboard(failureStage: "dismissed-recovery-keyboard-navigation")
        harness.element("playstead.sidebar.home", type: .staticText).clickWhenHittable()
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        openReadinessControllerSettings()
        XCTAssertTrue(readiness.awaitExistence(timeout: 5), "readiness sheet did not reopen after notice dismissal")
        let dismissedSettings = harness.element("playstead.surface.controller-settings")
        let dismissedOpenControllerTest = dismissedSettings.buttons["Test controller"]
        for _ in 0..<6 where !dismissedOpenControllerTest.isHittable { readinessContent.swipeUp() }
        dismissedOpenControllerTest.clickWhenHittable()
        XCTAssertTrue(
            harness.app.staticTexts["No active controller is connected."].awaitExistence(timeout: 5),
            "dismissing the notice must not reconnect or reassign the disconnected controller"
        )
        XCTAssertTrue(
            harness.element("playstead.controller.test.reconnect", type: .button).exists,
            "the persistent recovery action must remain available after notice dismissal"
        )
    }

    private func activateWithKeyboardFocus(
        _ identifier: String,
        failureStage: String,
        type: XCUIElement.ElementType = .button,
        activate: Bool = true
    ) {
        let button = harness.element(identifier, type: type)
        let marker = "PLAYSTEAD_FAILURE_STAGE[\(failureStage)]"
        XCTAssertTrue(button.awaitExistence(timeout: 5), "\(marker): keyboard target was absent")

        var foundFocus = false
        for _ in 0..<24 {
            if button.value(forKey: "hasKeyboardFocus") as? Bool == true {
                foundFocus = true
                break
            }
            harness.app.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(foundFocus, "\(marker): Tab could not focus \(identifier)")
        if activate { harness.app.typeKey(.space, modifierFlags: []) }
    }

    private func moveToRecentlyPlayedWithKeyboard(failureStage: String) {
        let marker = "PLAYSTEAD_FAILURE_STAGE[\(failureStage)]"
        // Focus the sidebar with a visible row below the recovery notice,
        // then send the arrow to the List itself. Sending the key to the app
        // alone after a sheet closes leaves focus on the old readiness
        // opener, so SwiftUI never delivers onMoveCommand to the shell.
        let favorites = harness.element("playstead.sidebar.favorites", type: .staticText)
        XCTAssertTrue(favorites.awaitExistence(timeout: 5), "\(marker): Favorites row was absent")
        favorites.clickWhenHittable()
        XCTAssertTrue(
            harness.element("playstead.surface.shelf.favorites").awaitExistence(timeout: 5),
            "\(marker): pointer could not select Favorites before keyboard navigation"
        )
        let sidebar = harness.element("playstead.surface.sidebar")
        sidebar.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(
            harness.element("playstead.surface.shelf.continue").awaitExistence(timeout: 5),
            "\(marker): Up Arrow did not move the focused sidebar selection to Recently Played"
        )
        sidebar.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(
            harness.element("playstead.control.open-readiness", type: .button).awaitExistence(timeout: 5),
            "\(marker): Up Arrow did not return the sidebar selection to All Games"
        )
    }
}

enum UITestControllerName {
    static let value = "Playstead Test Controller, active"
}
