import XCTest

@MainActor
final class ControllerRecoveryBannerGeometryTests: XCTestCase {
    private var harness: UITestHarness!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
        try super.tearDownWithError()
    }

    func testRecoveryBannerGeometryAcrossWindowSizesAndAppearances() throws {
        let windowCases: [(String, CGSize)] = [
            ("960x560", CGSize(width: 960, height: 560)),
            ("1280x800", CGSize(width: 1280, height: 800))
        ]

        for (windowSize, expectedContentSize) in windowCases {
            for appearance in ["light", "dark"] {
                harness = UITestHarness(
                    profile: .controllerRecovery,
                    extraEnvironment: [
                        "PLAYSTEAD_UI_TEST_WINDOW_SIZE": windowSize,
                        "PLAYSTEAD_UI_TEST_APPEARANCE": appearance
                    ]
                )
                harness.launch(settledAt: "playstead.surface.library")
                showRecoveryBanner()

                let window = harness.app.windows.firstMatch
                XCTAssertTrue(window.awaitExistence(timeout: 5), "application window was absent")
                let observedWindowFrame = window.frame
                XCTAssertEqual(observedWindowFrame.width, expectedContentSize.width, accuracy: 2, "requested window content width was not applied")
                XCTAssertGreaterThanOrEqual(
                    observedWindowFrame.height + 2,
                    expectedContentSize.height,
                    "outer window frame must contain the requested content height"
                )

                let banner = harness.element("playstead.controller.recovery-banner")
                XCTAssertTrue(banner.awaitExistence(timeout: 5), "recovery notice was absent at \(windowSize), \(appearance)")
                assertNoticeDoesNotCover(
                    banner,
                    target: harness.element("playstead.control.open-readiness", type: .button),
                    description: "All Games readiness action at \(windowSize), \(appearance)",
                    requiresHittable: true
                )

                // Use the same stable production row identity as the
                // curation journeys; this check measures shelf geometry.
                let recentlyPlayed = harness.element("playstead.sidebar.continue")
                XCTAssertTrue(recentlyPlayed.awaitExistence(timeout: 5), "Recently Played row was absent")
                XCTAssertEqual(recentlyPlayed.readableText, "Recently Played")
                recentlyPlayed.clickWhenHittable()
                let recentShelf = harness.element("playstead.surface.shelf.continue")
                XCTAssertTrue(recentShelf.awaitExistence(timeout: 5), "Recently Played did not open")
                XCTAssertTrue(banner.exists, "notice should remain visible while browsing Recently Played")
                let recentTitle = recentShelf.descendants(matching: .staticText).matching(
                    NSPredicate(format: "label == %@ OR value == %@", "Synthetic Controller Test", "Synthetic Controller Test")
                ).firstMatch
                let recentSystem = recentShelf.descendants(matching: .staticText).matching(
                    NSPredicate(format: "label == %@ OR value == %@", "Unidentified", "Unidentified")
                ).firstMatch
                XCTAssertTrue(recentTitle.awaitExistence(timeout: 5), "fixture title was absent")
                XCTAssertTrue(recentSystem.awaitExistence(timeout: 5), "fixture system subtitle was absent")
                XCTAssertEqual(recentTitle.readableText, "Synthetic Controller Test")
                XCTAssertEqual(recentSystem.readableText, "Unidentified")
                assertNoticeDoesNotCover(
                    banner,
                    target: recentTitle,
                    description: "Recently Played game title at \(windowSize), \(appearance)",
                    requiresHittable: false
                )
                assertNoticeDoesNotCover(
                    banner,
                    target: recentSystem,
                    description: "Recently Played system subtitle at \(windowSize), \(appearance)",
                    requiresHittable: false
                )
                let rowAction = recentShelf.descendants(matching: .button)
                    .matching(identifier: "playstead.control.open-readiness")
                    .firstMatch
                assertNoticeDoesNotCover(
                    banner,
                    target: rowAction,
                    description: "Recently Played row readiness action at \(windowSize), \(appearance)",
                    requiresHittable: true
                )
                let screenshot = XCTAttachment(screenshot: harness.app.screenshot())
                screenshot.name = "Recently Played recovery notice — \(windowSize), \(appearance)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                harness.app.terminate()
            }
        }
    }

    private func showRecoveryBanner() {
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        let readiness = harness.element("playstead.surface.readiness")
        XCTAssertTrue(readiness.awaitExistence(timeout: 5), "readiness sheet did not open")
        harness.element("playstead.control.open-controller-settings", type: .button).clickWhenHittable()
        let settings = harness.element("playstead.surface.controller-settings")
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "controller settings were absent")
        let content = harness.element("playstead.readiness.content")
        let openControllerTest = settings.buttons["Test controller"]
        for _ in 0..<6 where !openControllerTest.isHittable { content.swipeUp() }
        openControllerTest.clickWhenHittable()
        let disconnect = harness.element("playstead.controller.test.disconnect", type: .button)
        for _ in 0..<6 where !disconnect.isHittable { content.swipeUp() }
        disconnect.clickWhenHittable()
        XCTAssertTrue(harness.app.staticTexts["No active controller is connected."].awaitExistence(timeout: 5))
        let closeControllerTest = harness.element("playstead.controller.test.done", type: .button)
        for _ in 0..<6 where !closeControllerTest.isHittable { content.swipeDown() }
        closeControllerTest.clickWhenHittable()
        XCTAssertTrue(settings.awaitExistence(timeout: 5), "controller test did not return to settings")
        // The destination replaces the readiness content; query its current
        // pinned dismissal action rather than a previously resolved container.
        let closeReadiness = harness.element("playstead.control.done", type: .button)
        let returnDiagnostics = XCTAttachment(string: """
            window=\(harness.app.windows.firstMatch.frame)
            readiness=\(harness.element("playstead.surface.readiness").frame)
            done=\(closeReadiness.frame), hittable=\(closeReadiness.isHittable)
            \(harness.element("playstead.surface.readiness").debugDescription)
            """)
        returnDiagnostics.name = "Readiness dismissal after controller disconnect"
        returnDiagnostics.lifetime = .keepAlways
        add(returnDiagnostics)
        closeReadiness.clickWhenHittable()
        XCTAssertTrue(
            harness.element("playstead.controller.recovery-banner").awaitExistence(timeout: 5),
            "disconnect must show the production recovery notice"
        )
    }

    private func assertNoticeDoesNotCover(
        _ notice: XCUIElement,
        target: XCUIElement,
        description: String,
        requiresHittable: Bool
    ) {
        XCTAssertTrue(target.awaitExistence(timeout: 5), "\(description) was absent")
        let noticeFrame = notice.frame
        let targetFrame = target.frame
        let windowFrame = harness.app.windows.firstMatch.frame
        let targetIsHittable = target.isHittable
        let diagnostics = XCTAttachment(string: """
            \(description)
            notice=\(noticeFrame)
            target=\(targetFrame)
            window=\(windowFrame)
            targetHittable=\(targetIsHittable)
            """)
        diagnostics.name = description
        diagnostics.lifetime = .keepAlways
        add(diagnostics)
        for (name, frame) in [("notice", noticeFrame), ("target", targetFrame), ("window", windowFrame)] {
            XCTAssertTrue(frame.origin.x.isFinite && frame.origin.y.isFinite, "\(name) frame origin was not finite: \(frame)")
            XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0, "\(name) frame was empty or non-finite: \(frame)")
        }
        let visibleBounds = windowFrame.insetBy(dx: -2, dy: -2)
        XCTAssertTrue(visibleBounds.contains(noticeFrame), "notice was outside the visible window: notice=\(noticeFrame), window=\(windowFrame)")
        XCTAssertTrue(visibleBounds.contains(targetFrame), "\(description) was outside the visible window: target=\(targetFrame), window=\(windowFrame)")
        let overlap = noticeFrame.intersection(targetFrame)
        XCTAssertTrue(
            overlap.isNull || overlap.width <= 2 || overlap.height <= 2,
            "recovery notice overlaps \(description): notice=\(noticeFrame), target=\(targetFrame)"
        )
        if requiresHittable {
            XCTAssertTrue(targetIsHittable, "\(description) was not hittable while the notice was visible")
        }
    }
}
