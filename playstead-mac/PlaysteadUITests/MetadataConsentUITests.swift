import XCTest

@MainActor
final class MetadataConsentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        try super.tearDownWithError()
    }
    private let metadataFixtureKey = "PLAYSTEAD_UI_TEST_METADATA_FIXTURE"
    private let settingsFixtureIDs = [
        "provider-consent/disabled-unfilled", "provider-consent/loading", "provider-consent/rejection-error",
        "provider-consent/incomplete-credentials", "provider-consent/changed-terms-partial",
        "provider-consent/overflowing-disclosure", "provider-consent/long-exact-query",
        "match-candidates/zero", "match-candidates/loading", "match-candidates/error", "match-candidates/populated",
        "match-candidates/partial", "match-candidates/overflowing", "match-candidates/one-many", "match-candidates/long-title",
        "local-media-form/unfilled", "local-media-form/uploading", "local-media-form/rejected-error", "local-media-form/accepted",
        "local-media-form/partial-fields", "local-media-form/overlarge-image", "local-media-form/long-field-source",
        "delivery-preparation/unselected", "delivery-preparation/estimating", "delivery-preparation/failed", "delivery-preparation/ready",
        "delivery-preparation/partial-canceled", "delivery-preparation/overflowing", "delivery-preparation/zero-one-many", "delivery-preparation/long-title",
        "media-cache-controls/empty", "media-cache-controls/reclaiming", "media-cache-controls/failed", "media-cache-controls/under-budget",
        "media-cache-controls/pinned-expired-partial", "media-cache-controls/overflow", "media-cache-controls/zero-one-many", "media-cache-controls/long-label",
        "metadata-settings-navigation/provider-absent", "metadata-settings-navigation/loading", "metadata-settings-navigation/error",
        "metadata-settings-navigation/enabled-partial-credentials", "metadata-settings-navigation/overflowing",
        "metadata-settings-navigation/zero-one-many-groups", "metadata-settings-navigation/long-label"
    ]

    func testMetadataSettingsRemainInsideSettingsAndShowIndependentCacheBudget() throws {
        let harness = UITestHarness(profile: .emptyLibrary)
        let app = harness.app
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.sidebar.settings").clickWhenHittable()
        XCTAssertTrue(app.descendants(matching: .any)["playstead.settings"].awaitExistence(timeout: 5))
        harness.element("playstead.settings.open.metadata", type: .radioButton).clickWhenHittable()
        let metadata = app.descendants(matching: .any)["playstead.settings.metadata"]
        XCTAssertTrue(metadata.awaitExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Import a game before reviewing provider disclosure."].exists)
        XCTAssertTrue(app.descendants(matching: .any)["playstead.metadata.cache.budget"].exists)
        XCTAssertFalse(app.buttons["playstead.sidebar.metadata"].exists, "metadata is a Settings group, not a library sidebar destination")
        XCTAssertTrue(app.buttons["Reclaim unpinned artwork"].exists)
        XCTAssertFalse(app.buttons["Reclaim unpinned artwork"].isEnabled)
    }

    func testConsentPreviewRequiresASelectedGameAndUnpairedProfileNeverEnablesProvider() throws {
        let harness = UITestHarness(profile: .gbMBC1Qualified)
        let app = harness.app
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.sidebar.settings").clickWhenHittable()
        harness.element("playstead.settings.open.metadata").clickWhenHittable()
        let preview = app.buttons["playstead.metadata.consent.preview"]
        XCTAssertTrue(preview.awaitExistence(timeout: 5))
        preview.tap()
        XCTAssertTrue(app.staticTexts["playstead.metadata.status"].awaitExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playstead.metadata.consent.toggle"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["playstead.metadata.candidates.search"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["playstead.metadata.candidates.empty"].exists)
    }

    func testAllFortyFiveMetadataSettingsStatesExposeTheirOwnMeaningAndUsableAction() throws {
        let harness = UITestHarness(profile: .gbMBC1Qualified,
                                    extraEnvironment: [metadataFixtureKey: settingsFixtureIDs[0]])
        let app = harness.app
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.sidebar.settings").clickWhenHittable()
        harness.element("playstead.settings.open.metadata").clickWhenHittable()
        let metadata = app.descendants(matching: .any)["playstead.settings.metadata"]
        XCTAssertTrue(metadata.awaitExistence(timeout: 5))

        for (index, identity) in settingsFixtureIDs.enumerated() {
            XCTAssertEqual(metadataReadableText(app.staticTexts["playstead.metadata.fixture.identity"]), identity)
            assertRenderedContract(for: identity, app: app)
            guard index + 1 < settingsFixtureIDs.count else { continue }
            let next = app.buttons["playstead.metadata.fixture.next"]
            XCTAssertTrue(next.isEnabled, "fixture advancement must be an enabled action: \(identity)")
            next.tap()
            XCTAssertEqual(app.staticTexts["playstead.metadata.fixture.identity"].waitForValue(identity: settingsFixtureIDs[index + 1], timeout: 5), settingsFixtureIDs[index + 1])
        }
    }

    private func assertRenderedContract(for identity: String, app: XCUIApplication) {
        let parts = identity.split(separator: "/").map(String.init)
        guard parts.count == 2 else { XCTFail("invalid fixture identity: \(identity)"); return }
        let surface = parts[0], state = parts[1]
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)["playstead.metadata.\(id)"] }
        func exists(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
            let control = element(id)
            XCTAssertTrue(control.exists || control.waitForExistence(timeout: 4), "missing rendered semantic predicate \(id) for \(identity)", file: file, line: line)
        }
        func action(_ id: String, enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
            let control = element(id)
            XCTAssertTrue(control.exists || control.waitForExistence(timeout: 4), "missing action \(id) for \(identity)", file: file, line: line)
                XCTAssertEqual(control.isEnabled, enabled, "unexpected enabled state for \(id) in \(identity)", file: file, line: line)
        }

        switch surface {
        case "provider-consent", "metadata-settings-navigation":
            let awaitingPreview = state == "loading" || (surface == "metadata-settings-navigation" && ["provider-absent", "error"].contains(state))
            if awaitingPreview {
                action("consent.preview", enabled: state != "loading" && state != "provider-absent")
            } else {
                exists("consent.exact-query")
                exists("consent.hash-opt-in")
                XCTAssertFalse(element("consent.hash-opt-in").isEnabled, "hash lookup stays opt-in and disabled until a separate safe path exists")
                let hashValue = element("consent.hash-opt-in").value
                XCTAssertTrue((hashValue as? String).map { ["disabled", "0", "false"].contains($0.lowercased()) } ?? ((hashValue as? NSNumber)?.boolValue == false))
                action("consent.toggle", enabled: state != "incomplete-credentials")
                let hasLongQuery = ["long-exact-query", "overflowing-disclosure", "long-title", "long-label"].contains(state)
                if hasLongQuery { XCTAssertGreaterThan(metadataReadableText(element("consent.exact-query")).count, 100) }
                else { XCTAssertTrue(metadataReadableText(element("consent.exact-query")).contains("Fixture game")) }
            }
            if ["loading"].contains(state) { exists("progress") }
            if ["rejection-error", "error"].contains(state) { exists("status") }
            if ["incomplete-credentials", "enabled-partial-credentials"].contains(state) { exists("consent.credentials") }
            if state == "changed-terms-partial" { exists("consent.terms-changed") }
            if state == "changed-terms-partial" { action("candidates.search", enabled: false) }
            if ["overflowing-disclosure", "overflowing"].contains(state) { exists("consent.disclosure") }
            if ["long-exact-query", "long-label"].contains(state) { XCTAssertGreaterThan(metadataReadableText(element("consent.exact-query")).count, 100) }
            if surface == "metadata-settings-navigation" {
                XCTAssertTrue(app.descendants(matching: .any)["playstead.settings.metadata"].exists)
                XCTAssertFalse(app.buttons["playstead.sidebar.metadata"].exists)
                let count = state == "provider-absent" ? 0 : (state == "zero-one-many-groups" ? 2 : (state == "overflowing" ? 12 : 1))
                XCTAssertEqual(metadataReadableText(element("available-game-count")), "\(count) available games")
            }
        case "match-candidates":
            action("candidates.search", enabled: state != "loading")
            if state == "zero" { exists("candidates.empty") }
            else if state != "loading" && state != "error" {
                exists("candidates.count")
                let count = state == "partial" ? "2" : (state == "one-many" ? "3" : (state == "overflowing" ? "8" : "1"))
                XCTAssertTrue(metadataReadableText(element("candidates.count")).contains(count), "candidate count communicates the fixture-specific result")
                action("candidate.select.metadata-candidate-0", enabled: true)
            }
            if ["loading", "error"].contains(state) { exists(state == "loading" ? "progress" : "status") }
            if state == "zero" { XCTAssertTrue(metadataReadableText(element("candidates.empty")).contains("No provider suggestion")) }
            if state == "long-title" { XCTAssertTrue(staticTextContaining(app, "Long candidate title")); XCTAssertGreaterThan(app.staticTexts.allElementsBoundByIndex.map(metadataReadableText).first(where: { $0.contains("Long candidate title") })?.count ?? 0, 100) }
        case "local-media-form":
            exists("media.target")
            action("media.upload", enabled: state != "uploading")
            if state == "uploading" {
                exists("media.fixture-media")
                exists("media.progress"); action("media.cancel", enabled: true)
                element("media.cancel").tap()
                XCTAssertTrue(app.staticTexts["playstead.metadata.status"].waitForExistence(timeout: 4))
                exists("media.fixture-media")
            }
            if ["rejected-error", "overlarge-image"].contains(state) { exists("status"); action("media.retry", enabled: true) }
            if ["accepted", "partial-fields", "long-field-source"].contains(state) { exists("media.fixture-media") }
            if state == "overlarge-image" { exists("status") }
            if state == "long-field-source" {
                XCTAssertTrue(metadataReadableText(app.staticTexts["playstead.metadata.media.fixture-media"]).contains("Private original"))
                XCTAssertLessThanOrEqual(metadataReadableText(element("media.preview.text")).count, 320)
            }
        case "delivery-preparation":
            exists("preparation.mode")
            if state == "unselected" { action("preparation.estimate", enabled: false) }
            if state == "estimating" { exists("progress") }
            if state == "failed" { exists("status"); action("preparation.estimate", enabled: true) }
            if ["ready", "partial-canceled", "overflowing", "zero-one-many", "long-title"].contains(state) {
                if state != "zero-one-many" {
                    exists("preparation.review")
                    let count = state == "overflowing" ? 12 : 1
                    let review = metadataReadableText(element("preparation.review"))
                    XCTAssertEqual(review, "\(count) games · \(count * 2) requests · \(count * 64_000) bytes · \(count * 32_000) bytes storage")
                }
                if state == "partial-canceled" { exists("preparation.job.job-0") }
                if state == "overflowing" { exists("preparation.game.00000000-0000-7000-8000-000000000209") }
                if state == "zero-one-many" { exists("preparation.game.00000000-0000-7000-8000-000000000098") }
                if state == "long-title" { XCTAssertTrue(games(for: app).contains { metadataReadableText($0).contains("Exact private owner title") }) }
                if state == "zero-one-many" {
                    let count = element("preparation.selection-count")
                    XCTAssertEqual(metadataReadableText(count), "0 selected")
                    XCTAssertFalse(element("preparation.estimate").isEnabled)
                    let switches = games(for: app)
                    XCTAssertGreaterThanOrEqual(switches.count, 3)
                    switches[0].tap()
                    XCTAssertEqual(waitForAXValue(count, "1 selected", timeout: 3), "1 selected")
                    switches[1].tap(); switches[2].tap()
                    XCTAssertEqual(waitForAXValue(count, "3 selected", timeout: 3), "3 selected")
                    XCTAssertTrue(element("preparation.estimate").isEnabled)
                }
            }
        case "media-cache-controls":
            exists("cache.budget"); exists("cache.server-budget")
            exists("cache.pinned"); exists("cache.expiring"); exists("cache.reclaimable")
            action("cache.reclaim", enabled: ["pinned-expired-partial", "overflow", "zero-one-many"].contains(state))
            if state == "reclaiming" { exists("progress") }
            if state == "failed" { exists("status") }
            XCTAssertTrue(metadataReadableText(element("cache.budget")).contains("Device budget"))
            if state == "empty" { XCTAssertEqual(metadataReadableText(element("cache.pinned")), "0") }
            if state == "under-budget" { XCTAssertEqual(metadataReadableText(element("cache.used")), "1024 bytes"); XCTAssertEqual(metadataReadableText(element("cache.pinned")), "1") }
            if state == "zero-one-many" { XCTAssertEqual(metadataReadableText(element("cache.pinned")), "2"); XCTAssertEqual(metadataReadableText(element("cache.expiring")), "1") }
            if state == "pinned-expired-partial" { XCTAssertTrue(metadataReadableText(element("cache.pinned")).contains("2")); XCTAssertTrue(metadataReadableText(element("cache.expiring")).contains("1")) }
            if state == "overflow" { XCTAssertEqual(metadataReadableText(element("cache.used")), "536871424 bytes"); XCTAssertTrue(metadataReadableText(element("cache.pinned")).contains("12")); XCTAssertTrue(metadataReadableText(element("cache.expiring")).contains("8")) }
        default: XCTFail("unmapped metadata fixture surface: \(surface)")
        }
    }
}

private extension XCUIElement {
    func waitForValue(identity expected: String, timeout: TimeInterval) -> String? {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return exists ? metadataReadableText(self) : nil
    }
}

private func metadataReadableText(_ element: XCUIElement) -> String { (element.value as? String) ?? element.label }

private func staticTextContaining(_ app: XCUIApplication, _ text: String) -> Bool {
    app.staticTexts.allElementsBoundByIndex.contains { metadataReadableText($0).contains(text) }
}

private func games(for app: XCUIApplication) -> [XCUIElement] {
    (app.checkBoxes.allElementsBoundByIndex + app.switches.allElementsBoundByIndex).filter { $0.identifier.hasPrefix("playstead.metadata.preparation.game.") }
}

private func waitForAXValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval) -> String? {
    let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
    _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    return element.exists ? metadataReadableText(element) : nil
}
