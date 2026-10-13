import XCTest

@MainActor
final class MetadataCorrectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        try super.tearDownWithError()
    }
    private let assetSetID = "00000000-0000-7000-8000-000000000097"
    private let fixtureKey = "PLAYSTEAD_UI_TEST_METADATA_FIXTURE"
    private let fixtures = [
        "metadata-corrections/unchanged", "metadata-corrections/loading", "metadata-corrections/failed-submit",
        "metadata-corrections/corrected", "metadata-corrections/partial-conflict", "metadata-corrections/overflow",
        "metadata-corrections/zero-one-many", "metadata-corrections/long-text"
    ]

    func testCorrectionFormShowsPerFieldSourceAndOnlyExplicitSaveAction() throws {
        let harness = UITestHarness(profile: .gbMBC1Qualified)
        let app = harness.app
        harness.launch(settledAt: "playstead.surface.library")
        openCorrection(in: harness)
        let form = app.descendants(matching: .any)["playstead.metadata.correction.form"]
        XCTAssertTrue(form.awaitExistence(timeout: 5))
        XCTAssertTrue(app.textFields["playstead.metadata.correction.title"].exists)
        XCTAssertTrue(app.textViews["playstead.metadata.correction.description"].exists || app.descendants(matching: .any)["playstead.metadata.correction.description"].exists)
        XCTAssertTrue(app.staticTexts["playstead.metadata.correction.source.title"].exists)
        XCTAssertTrue(app.staticTexts["playstead.metadata.correction.source.description"].exists)
        XCTAssertFalse(app.buttons["playstead.metadata.correction.save"].isEnabled, "unchanged fields are not enqueued")
        XCTAssertFalse(app.buttons["playstead.metadata.correction.conflict.notice"].exists)
    }

    func testSavingCorrectionUpdatesTheLocalMirrorBeforeServerDelivery() throws {
        let harness = UITestHarness(profile: .gbMBC1Qualified)
        let app = harness.app
        harness.launch(settledAt: "playstead.surface.library")
        openCorrection(in: harness)

        let title = app.textFields["playstead.metadata.correction.title"]
        XCTAssertTrue(title.awaitExistence(timeout: 5))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Privately corrected title")

        let save = app.buttons["playstead.metadata.correction.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let correctedTitle = app.staticTexts["playstead.game.\(assetSetID).detail-title"]
        XCTAssertTrue(correctedTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(readableText(correctedTitle), "Privately corrected title")
        let correctedSource = app.staticTexts["playstead.game.\(assetSetID).title.source"]
        XCTAssertTrue(correctedSource.waitForExistence(timeout: 5))
        XCTAssertTrue(readableText(correctedSource).contains("your private library"),
                       "MetadataStore optimistic writes notify the production environment so open detail provenance refreshes")
    }

    func testAllEightCorrectionStatesRenderProvenanceConflictsAndEnabledActions() throws {
        let harness = UITestHarness(profile: .gbMBC1Qualified, extraEnvironment: [fixtureKey: fixtures[0]])
        let app = harness.app
        harness.launch(settledAt: "playstead.surface.library")
        openCorrection(in: harness)
        XCTAssertTrue(app.descendants(matching: .any)["playstead.metadata.correction.form"].awaitExistence(timeout: 5))

        for (index, identity) in fixtures.enumerated() {
            let current = app.staticTexts["playstead.metadata.fixture.identity"]
            XCTAssertEqual(readableText(current), identity)
            let titleSource = app.staticTexts["playstead.metadata.correction.source.title"]
            let descriptionSource = app.staticTexts["playstead.metadata.correction.source.description"]
            XCTAssertTrue(titleSource.exists, "title provenance remains visible in \(identity)")
            XCTAssertTrue(descriptionSource.exists, "description provenance remains visible in \(identity)")
            let save = app.buttons["playstead.metadata.correction.save"]
            XCTAssertTrue(save.exists)
            XCTAssertEqual(save.isEnabled, identity == "metadata-corrections/failed-submit")

            switch identity {
            case "metadata-corrections/unchanged":
                XCTAssertTrue(readableText(titleSource).contains("imported"))
                XCTAssertTrue(readableText(descriptionSource).contains("imported"))
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "playstead.metadata.correction.reset-provider.title.")).firstMatch.isEnabled)
            case "metadata-corrections/loading":
                XCTAssertFalse(save.isEnabled, "submitting state disables duplicate writes")
                XCTAssertTrue(app.buttons["Cancel"].isEnabled)
            case "metadata-corrections/failed-submit":
                XCTAssertTrue(readableText(app.staticTexts["playstead.metadata.correction.status"]).contains("could not be saved"))
                XCTAssertTrue(save.isEnabled, "retry is available after a failed submit")
            case "metadata-corrections/corrected":
                XCTAssertTrue(readableText(titleSource).contains("your private library"))
                XCTAssertTrue(readableText(descriptionSource).contains("your private library"))
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "playstead.metadata.correction.reset-provider.title.")).firstMatch.exists,
                               "user corrections retain explicit provider reset choices from sanitized evidence")
            case "metadata-corrections/partial-conflict":
                XCTAssertTrue(app.staticTexts["playstead.metadata.correction.conflict.notice"].exists)
                XCTAssertTrue(staticTextContaining(app, "Your offline title"))
                XCTAssertTrue(staticTextContaining(app, "Current server title"))
                XCTAssertTrue(app.buttons["Keep current"].isEnabled)
                XCTAssertTrue(app.buttons["Keep my edit"].isEnabled)
            case "metadata-corrections/overflow":
                XCTAssertGreaterThan((app.textFields["playstead.metadata.correction.title"].value as? String ?? "").count, 120)
            case "metadata-corrections/zero-one-many":
                XCTAssertTrue(readableText(titleSource).contains("imported"))
                XCTAssertTrue(readableText(descriptionSource).contains("imported"))
                let title = app.textFields["playstead.metadata.correction.title"]
                title.click(); title.typeKey("a", modifierFlags: .command); title.typeText("One and many correction fixture")
                XCTAssertTrue(save.isEnabled)
                XCTAssertTrue(descriptionSource.exists, "the second supported field remains independently surfaced")
                save.tap()
                XCTAssertTrue(app.staticTexts["playstead.game.\(assetSetID).detail-title"].waitForExistence(timeout: 5))
                let detailTitleSource = app.staticTexts["playstead.game.\(assetSetID).title.source"]
                let detailDescriptionSource = app.staticTexts["playstead.game.\(assetSetID).description.source"]
                XCTAssertTrue(readableText(detailTitleSource).contains("your private library"))
                XCTAssertFalse(readableText(detailDescriptionSource).contains("Description written for this private library"), "one changed field produces exactly one correction")
                app.activate()
                app.buttons["playstead.game.\(assetSetID).metadata-correction.open"].clickWhenHittable()
                XCTAssertTrue(app.staticTexts["playstead.metadata.correction.source.title"].waitForExistence(timeout: 5))
                XCTAssertTrue(readableText(app.staticTexts["playstead.metadata.correction.source.title"]).contains("your private library"))
                XCTAssertFalse(readableText(app.staticTexts["playstead.metadata.correction.source.description"]).contains("your private library"))
                let description = app.descendants(matching: .any)["playstead.metadata.correction.description"]
                description.click(); description.typeKey("a", modifierFlags: .command); description.typeText("Second correction")
                XCTAssertTrue(app.buttons["playstead.metadata.correction.save"].isEnabled)
                app.buttons["playstead.metadata.correction.save"].tap()
                let savedDescription = app.staticTexts["playstead.game.\(assetSetID).description"]
                let descriptionSaved = NSPredicate { _, _ in
                    savedDescription.exists && readableText(savedDescription) == "Second correction" &&
                        detailDescriptionSource.exists && readableText(detailDescriptionSource) == "Description written for this private library"
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: descriptionSaved, object: nil)], timeout: 5), .completed,
                               "the second real save updates both description text and provenance")
                XCTAssertTrue(readableText(detailTitleSource).contains("your private library"))
                XCTAssertEqual(readableText(detailDescriptionSource), "Description written for this private library", "many supported fields converge after the second real save")
                app.activate()
                app.buttons["playstead.game.\(assetSetID).metadata-correction.open"].clickWhenHittable()
            case "metadata-corrections/long-text":
                XCTAssertGreaterThan(readableText(app.textFields["playstead.metadata.correction.title"]).count, 100)
                XCTAssertTrue(app.textViews["playstead.metadata.correction.description"].exists || app.descendants(matching: .any)["playstead.metadata.correction.description"].exists)
            default: XCTFail("unmapped correction fixture: \(identity)")
            }

            guard index + 1 < fixtures.count else { continue }
            let next = app.buttons["playstead.metadata.fixture.next"]
            XCTAssertTrue(next.isEnabled)
            next.tap()
            let expected = fixtures[index + 1]
            let predicate = NSPredicate(format: "value == %@", expected)
            expectation(for: predicate, evaluatedWith: app.staticTexts["playstead.metadata.fixture.identity"])
            waitForExpectations(timeout: 5)
        }
    }
    private func openCorrection(in harness: UITestHarness) {
        let app = harness.app
        let actions = app.descendants(matching: .menuButton)["playstead.game.\(assetSetID).actions"]
        XCTAssertTrue(actions.awaitExistence(timeout: 5), "the imported game's actions menu must exist")
        actions.clickWhenHittable()
        let details = app.menuItems["playstead.game.\(assetSetID).details.trigger"]
        XCTAssertTrue(details.awaitExistence(timeout: 5), "the actions menu must expose Game Details")
        details.clickWhenHittable()
        let correction = app.buttons["playstead.game.\(assetSetID).metadata-correction.open"]
        XCTAssertTrue(correction.awaitExistence(timeout: 5))
        let detailScroll = app.descendants(matching: .any)["playstead.game.\(assetSetID).details"]
        for _ in 0..<6 where !correction.isHittable { detailScroll.swipeUp() }
        correction.clickWhenHittable()
        XCTAssertTrue(app.descendants(matching: .any)["playstead.metadata.correction.form"].awaitExistence(timeout: 5))
    }
}

private func readableText(_ element: XCUIElement) -> String { (element.value as? String) ?? element.label }

private func staticTextContaining(_ app: XCUIApplication, _ text: String) -> Bool {
    app.staticTexts.allElementsBoundByIndex.contains { readableText($0).contains(text) }
}
