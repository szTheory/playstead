import XCTest

@MainActor
final class MetadataGalleryUITests: XCTestCase {
    private let assetSetID = "00000000-0000-7000-8000-000000000097"

    func testGameDetailsKeepPlayAndReturnToSelectedGame() throws {
        let app = try openSelectedGameDetails()
        let detail = app.descendants(matching: .any)["playstead.game.\(assetSetID).details"]
        XCTAssertTrue(detail.awaitExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Play"].exists || app.buttons["Continue"].exists)
        XCTAssertTrue(app.staticTexts["Game Boy Advance"].exists || app.staticTexts["Game Boy"].exists)
        let cover = app.descendants(matching: .any)["playstead.game.\(assetSetID).details.cover"]
        XCTAssertEqual(cover.frame.width, 240, accuracy: 1)
        XCTAssertEqual(cover.frame.height, 320, accuracy: 1)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let moreActions = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "More actions for ")
        ).firstMatch
        XCTAssertTrue(moreActions.exists, "closing details must return to the selected game's row")
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["playstead.game.\(assetSetID).details.trigger"].awaitExistence(timeout: 3),
                      "Space after dismissal must open the restored details menu trigger")
    }

    func testEmptyGalleryReturnsToSelectedGameDetails() throws {
        let app = try openSelectedGameDetails()
        let detail = app.descendants(matching: .any)["playstead.game.\(assetSetID).details"]
        app.buttons["View screenshots"].tap()
        XCTAssertTrue(app.staticTexts["No screenshots yet"].awaitExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close screenshots"].exists)
        XCTAssertFalse(app.buttons["Previous screenshot"].exists)
        XCTAssertFalse(app.buttons["Next screenshot"].exists)
        app.buttons["Close screenshots"].tap()
        XCTAssertTrue(detail.exists, "closing the gallery must return to the same selected game's details")
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["No screenshots yet"].awaitExistence(timeout: 3),
                      "gallery Close must restore focus to View screenshots")
        app.buttons["Close screenshots"].tap()
    }

    func testControllerBReleaseClosesGalleryAndRestoresSelectedGame() throws {
        let app = try openSelectedGameDetails()
        let galleryButton = app.buttons["View screenshots"]
        XCTAssertTrue(galleryButton.awaitExistence(timeout: 5))
        galleryButton.tap()
        XCTAssertTrue(app.staticTexts["No screenshots yet"].awaitExistence(timeout: 5))
        let press = app.buttons["playstead.harness.controller.back"]
        XCTAssertTrue(press.awaitExistence(timeout: 5), "the active production controller host must expose its semantic test input")
        press.tap()
        let release = app.buttons["playstead.harness.controller.back-release"]
        XCTAssertTrue(release.awaitExistence(timeout: 5))
        release.tap()
        XCTAssertTrue(app.buttons["Close screenshots"].waitForNonExistence(timeout: 5),
                      "B release from ControllerHost must close the active gallery")
        XCTAssertTrue(app.descendants(matching: .any)["playstead.game.\(assetSetID).details"].exists,
                      "B dismissal must return to the same selected game's details")
    }

    private func openSelectedGameDetails() throws -> XCUIApplication {
        let harness = UITestHarness(profile: .gbMBC1Qualified)
        let app = harness.app
        harness.launch(settledAt: "playstead.surface.library")

        let moreActions = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "More actions for ")
        ).firstMatch
        XCTAssertTrue(moreActions.awaitExistence(timeout: 10))
        let cardArtwork = app.descendants(matching: .any)["playstead.game.\(assetSetID).artwork"]
        XCTAssertTrue(cardArtwork.awaitExistence(timeout: 5))
        XCTAssertEqual(cardArtwork.frame.width, 44, accuracy: 1)
        XCTAssertEqual(cardArtwork.frame.height, 44, accuracy: 1)
        XCTAssertTrue(cardArtwork.label.contains("No selected artwork; showing the system monogram"),
                       "the artwork accessibility label must disclose the truthful empty state")
        moreActions.tap()

        let details = app.descendants(matching: .any)["playstead.game.\(assetSetID).details.trigger"]
        XCTAssertTrue(details.awaitExistence(timeout: 5), "the real game row must offer its details destination")
        details.tap()
        return app
    }
}
