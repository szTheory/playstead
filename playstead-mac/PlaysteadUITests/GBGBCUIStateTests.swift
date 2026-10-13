import XCTest

/// Packaged assertions over the production library/readiness and save-history
/// composition. Fixtures seed only local catalogue/CAS/SaveStore state; every
/// route is entered through the normal app controls.
@MainActor
final class GBGBCUIStateTests: XCTestCase {
    private var harness: UITestHarness!
    private var persistentProfileRoot: URL?

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        if let app = harness?.app {
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), "deterministic app must close before fixture cleanup")
        }
        harness = nil
        if let root = persistentProfileRoot {
            let expectedParent = FileManager.default.temporaryDirectory
                .appendingPathComponent("playstead-ui-profile-sessions", isDirectory: true)
            XCTAssertEqual(root.deletingLastPathComponent().standardizedFileURL, expectedParent.standardizedFileURL)
            try FileManager.default.removeItem(at: root)
            persistentProfileRoot = nil
        }
    }

    func testLibraryReadinessDetailsStates() {
        launch(.emptyLibrary)
        let emptyPane = harness.element("playstead.library.empty")
        XCTAssertTrue(emptyPane.awaitExistence(timeout: 5), "zero entries must use the existing import invitation")
        XCTAssertTrue(emptyPane.staticTexts["No games yet"].exists)
        XCTAssertTrue(emptyPane.buttons["Pair with Server…"].isHittable)
        XCTAssertFalse(harness.app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "playstead.game.", ".summary"))
            .firstMatch.exists, "an empty library must not fabricate a game row")

        launch(.populatedCurationReorder)
        let layoutPicker = harness.element("playstead.library.view-mode")
        let listSegment = layoutPicker.descendants(matching: .any)["playstead.control.show-list"]
        XCTAssertTrue(listSegment.awaitExistence(timeout: 5))
        listSegment.clickWhenHittable()
        let expectedRows = (1...3).map { String(format: "00000000-0000-7000-8000-%012d", $0) }
        let listRows = harness.app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "playstead.game.", ".summary"))
            .allElementsBoundByIndex
        XCTAssertEqual(listRows.map(\.identifier), expectedRows.map { "playstead.game.\($0).summary" },
                       "list rows must preserve stable identity and deterministic title order")
        let cardsSegment = layoutPicker.descendants(matching: .any)["playstead.control.show-cards"]
        XCTAssertTrue(cardsSegment.awaitExistence(timeout: 5))
        cardsSegment.clickWhenHittable()
        let cardRows = harness.app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "playstead.game.", ".summary"))
            .allElementsBoundByIndex
        XCTAssertEqual(Set(cardRows.map(\.identifier)), Set(expectedRows.map { "playstead.game.\($0).summary" }),
                       "card and list layouts must retain the same three asset identities")

        launch(.gbcDownloadProgress)
        let downloadAssetID = "00000000-0000-7000-8000-000000000105"
        let downloads = harness.element("playstead.sidebar.downloads", type: .staticText)
        XCTAssertTrue(downloads.awaitExistence(timeout: 5))
        downloads.clickWhenHittable()
        let transferProgress = harness.element(DownloadsProgressIdentifier.progress(0))
        let transferEvidence = harness.element("playstead.test.download.evidence")
        let startEvidence = harness.element("playstead.test.download.start-evidence")
        XCTAssertTrue(startEvidence.awaitExistence(timeout: 5))
        XCTAssertTrue(transferProgress.awaitExistence(timeout: 10),
                      "the real queued transfer must publish received-byte progress; start=\(startEvidence.value as? String ?? "<missing>"), transport=\(transferEvidence.value as? String ?? "<missing>")")
        XCTAssertEqual((transferProgress.value as? NSNumber)?.doubleValue, 0.5,
                       "progress AX readback label=\(transferProgress.label), element=\(transferProgress.debugDescription)")
        XCTAssertTrue(transferEvidence.awaitExistence(timeout: 5))
        XCTAssertEqual(transferEvidence.value as? String,
                       "requests=1;rejected=0;receivedBytes=65536",
                       "the intermediate value must come from one accepted request and half the fixture bytes")
        let home = harness.element("playstead.sidebar.home", type: .staticText)
        home.clickWhenHittable()
        let gameRow = harness.element("playstead.game.\(downloadAssetID).summary")
        XCTAssertTrue(gameRow.awaitExistence(timeout: 5), "the prior library row must remain present during transfer")
        let progressStatus = harness.app.staticTexts.matching(identifier: "library.status-label").firstMatch
        XCTAssertTrue(progressStatus.awaitExistence(timeout: 5), "the prior library row must keep its ordinary status visible")
        XCTAssertEqual(progressStatus.readableText, "Queued",
                       "a first download with no cached member bytes remains queued in availability; transfer percentage is shown in Downloads")
        let rowActivity = harness.element("playstead.game.\(downloadAssetID).download-activity")
        XCTAssertTrue(rowActivity.awaitExistence(timeout: 5), "the active queue item must replace the duplicate Download action")
        XCTAssertEqual(rowActivity.label, "Downloading, 50 percent complete",
                       "the primary action must expose the actual active transfer percentage")
        XCTAssertFalse(harness.element("playstead.game.\(downloadAssetID).play", type: .button).exists,
                       "Play cannot submit during a game transfer")
        XCTAssertFalse(harness.element("playstead.game.\(downloadAssetID).download", type: .button).exists,
                       "Download cannot submit twice while the transfer is active")
        downloads.clickWhenHittable()
        harness.element("playstead.test.download.release", type: .button).clickWhenHittable()
        XCTAssertFalse(harness.element(DownloadsProgressIdentifier.row(0)).waitForExistence(timeout: 10),
                       "a completed, digest-verified transfer must leave the persistent queue")
        XCTAssertEqual(transferEvidence.value as? String,
                       "requests=1;rejected=0;receivedBytes=131072",
                       "release must deliver the remaining actual bytes before digest verification")
        home.clickWhenHittable()
        let downloadedPlay = harness.element("playstead.game.\(downloadAssetID).play", type: .button)
        let readinessDebug = harness.element("playstead.game.\(downloadAssetID).readiness-debug")
        let statusLabel = harness.app.staticTexts.matching(identifier: "library.status-label").firstMatch
        XCTAssertTrue(downloadedPlay.awaitExistence(timeout: 5),
                      "the downloaded bytes must be available from the production CAS; readiness=\(readinessDebug.value as? String ?? "<missing>"); status=\(statusLabel.readableText); download=\(harness.element("playstead.game.\(downloadAssetID).download", type: .button).exists); needed=\(harness.element("playstead.control.open-readiness", type: .button).exists)")

        launch(.gbMBC1Qualified, extraEnvironment: ["PLAYSTEAD_UI_TEST_READINESS_BARRIER": "hold"])
        let checking = harness.element("playstead.game.00000000-0000-7000-8000-000000000097.checking")
        XCTAssertTrue(checking.awaitExistence(timeout: 3), "readiness must remain explicit while a report is recomputed")
        XCTAssertFalse(harness.app.buttons["Play"].exists, "a previous or absent report must not enable Play during a refresh")
        harness.element("playstead.test.readiness.release.00000000-0000-7000-8000-000000000097", type: .button).clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.game.00000000-0000-7000-8000-000000000097.play", type: .button).awaitExistence(timeout: 5))

        launch(.gbcUnsupportedHeader)
        let whatsNeeded = harness.element("playstead.control.open-readiness", type: .button)
        XCTAssertTrue(whatsNeeded.awaitExistence(timeout: 5), "blocked GBC row must retain its actionable remedy")
        XCTAssertEqual(whatsNeeded.label, "What's needed")
        XCTAssertFalse(harness.app.buttons["Play"].exists, "unqualified cartridge must not offer Play")
        whatsNeeded.clickWhenHittable()

        let supportRow = harness.element("playstead.readiness.row.systemSupport")
        XCTAssertTrue(supportRow.awaitExistence(timeout: 5), "GBC cartridge qualification must be an explicit readiness check")
        XCTAssertTrue(supportRow.readableText.contains("Game Boy Color"))
        XCTAssertTrue(supportRow.readableText.contains("isn't supported for saved progress. No save was changed."))
        let remedy = harness.element("playstead.readiness.row.systemSupport.remedy", type: .button)
        XCTAssertTrue(remedy.exists)
        XCTAssertTrue(remedy.label.contains("keep this item in your library"))

        let details = harness.element("playstead.readiness.row.systemSupport.details", type: .button)
        XCTAssertTrue(details.exists, "diagnostic details must be explicit and initially collapsed")
        XCTAssertFalse(harness.element("playstead.readiness.row.systemSupport.detail.0").exists)
        details.clickWhenHittable()
        let firstDetail = harness.element("playstead.readiness.row.systemSupport.detail.0")
        XCTAssertTrue(firstDetail.awaitExistence(timeout: 5))
        XCTAssertLessThanOrEqual(firstDetail.readableText.count, 256)
        XCTAssertFalse(harness.element("playstead.surface.readiness").label.contains("unsupported or unqualified"),
                       "diagnostic data must not become a navigation label")
        XCTAssertFalse(harness.app.buttons["Play"].exists)
        XCTAssertLessThanOrEqual(harness.element("playstead.surface.readiness").frame.height, 520)
        details.clickWhenHittable()
        XCTAssertFalse(harness.element("playstead.readiness.row.systemSupport.detail.0").exists,
                       "collapsing Details must hide diagnostics")
        XCTAssertTrue(harness.element("playstead.readiness.row.systemSupport.remedy", type: .button).isHittable,
                      "collapsing Details must leave the safe remedy reachable")
        XCTAssertFalse(harness.app.buttons["Play"].exists,
                       "collapsing Details must preserve the blocker")

        launch(.gbcCorruptHeaderLongName)
        let corruptAction = harness.element("playstead.control.open-readiness", type: .button)
        let corruptDebug = harness.element("playstead.game.00000000-0000-7000-8000-000000000096.readiness-debug")
        XCTAssertTrue(
            corruptAction.awaitExistence(timeout: 5),
            "corrupt fixture readiness did not settle; production refresh trace: \(corruptDebug.value as? String ?? "<missing>"); tree: \(harness.app.debugDescription)"
        )
        XCTAssertEqual(corruptAction.label, "What's needed")
        XCTAssertFalse(harness.app.buttons["Play"].exists)
        corruptAction.clickWhenHittable()
        let corruptRow = harness.element("playstead.readiness.row.systemSupport")
        XCTAssertTrue(corruptRow.awaitExistence(timeout: 5))
        XCTAssertTrue(corruptRow.readableText.contains("valid Game Boy Color header"))
        XCTAssertEqual(
            harness.element("playstead.readiness.row.systemSupport.remedy", type: .button).label,
            "Redownload the game file"
        )
        let corruptDetails = harness.element("playstead.readiness.row.systemSupport.details", type: .button)
        corruptDetails.clickWhenHittable()
        let corruptDetail = harness.element("playstead.readiness.row.systemSupport.detail.0")
        XCTAssertTrue(corruptDetail.awaitExistence(timeout: 5))
        XCTAssertTrue(corruptDetail.readableText.contains("unavailable or invalid"))
        XCTAssertFalse(harness.element("playstead.surface.readiness").label.contains("uuuu"))

        launch(.unknownSystem, extraEnvironment: ["PLAYSTEAD_UI_TEST_READINESS_BARRIER": "after-initial"])
        let unknownAction = harness.element("playstead.control.open-readiness", type: .button)
        XCTAssertTrue(unknownAction.awaitExistence(timeout: 5))
        XCTAssertEqual(unknownAction.label, "What's needed")
        XCTAssertFalse(harness.app.buttons["Play"].exists, "unknown system must remain blocked")
        unknownAction.clickWhenHittable()
        let unknownSupport = harness.element("playstead.readiness.row.systemSupport")
        XCTAssertTrue(unknownSupport.awaitExistence(timeout: 5))
        XCTAssertTrue(unknownSupport.readableText.contains("limited to systems and cartridges validated"))
        XCTAssertEqual(
            harness.element("playstead.readiness.row.systemSupport.remedy", type: .button).label,
            "Review adapter support"
        )
        harness.element("playstead.readiness.row.systemSupport.remedy", type: .button).clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.readiness-adapter-setup").awaitExistence(timeout: 5))
        harness.element("playstead.readiness.adapter.back", type: .button).clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.readiness.checking").awaitExistence(timeout: 5))
        XCTAssertTrue(
            unknownSupport.readableText.contains("limited to systems and cartridges validated"),
            "a recompute must keep the prior blocked report visible until the new report completes"
        )
        XCTAssertFalse(harness.app.buttons["Play"].exists)
        harness.element("playstead.test.readiness.release-sheet", type: .button).clickWhenHittable()
        let readinessChecking = harness.element("playstead.readiness.checking")
        let checkingCleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: readinessChecking
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [checkingCleared], timeout: 8),
            .completed,
            "released readiness refresh did not settle; prior visible blocker: \(unknownSupport.readableText)"
        )
        XCTAssertTrue(unknownSupport.readableText.contains("limited to systems and cartridges validated"))

        launch(.gbcMissingReadinessEvidence)
        let missingAction = harness.element("playstead.control.open-readiness", type: .button)
        XCTAssertTrue(missingAction.awaitExistence(timeout: 5), "missing cartridge evidence must be a real blocker, not an indefinite spinner")
        XCTAssertEqual(missingAction.label, "What's needed")
        XCTAssertFalse(harness.app.buttons["Play"].exists)
        missingAction.clickWhenHittable()
        let missingSupport = harness.element("playstead.readiness.row.systemSupport")
        XCTAssertTrue(missingSupport.awaitExistence(timeout: 5))
        XCTAssertEqual(harness.element("playstead.surface.readiness").frame.width, 720, accuracy: 2)
        XCTAssertEqual(harness.element("playstead.surface.readiness").frame.height, 520, accuracy: 2)
        XCTAssertTrue(missingSupport.readableText.contains("Play requires a verified local .gbc file so Playstead can inspect its cartridge and save layout."))
        XCTAssertEqual(
            harness.element("playstead.readiness.row.systemSupport.remedy", type: .button).label,
            "Review adapter support"
        )
        let readinessSurface = harness.element("playstead.surface.readiness")
        XCTAssertLessThanOrEqual(readinessSurface.frame.height, 520)
        for _ in 0..<8 where !harness.element("playstead.control.done", type: .button).isHittable {
            harness.element("playstead.readiness.content").swipeUp()
        }
        XCTAssertTrue(harness.element("playstead.control.done", type: .button).isHittable,
                      "the readiness sheet must keep its return action reachable while content scrolls")
        XCTAssertTrue(harness.element("playstead.readiness.row.systemSupport.remedy", type: .button).isHittable,
                      "the blocking remedy must remain reachable after readiness scrolling")

        let qualified: [(UITestHarness.Profile, String, String, String)] = [
            (.gbMBC1Qualified, "00000000-0000-7000-8000-000000000097", "Game Boy", "MBC1"),
            (.gbcMBC5Qualified, "00000000-0000-7000-8000-000000000098", "Game Boy Color", "MBC5"),
            (.gbcMBC3RTCQualified, "00000000-0000-7000-8000-000000000099", "Game Boy Color", "MBC3-RTC")
        ]
        for (profile, assetID, system, cartridge) in qualified {
            launch(profile)
            let play = harness.element("playstead.game.\(assetID).play", type: .button)
            XCTAssertTrue(play.awaitExistence(timeout: 5), "qualified \(system) \(cartridge) must retain its primary Play action")
            XCTAssertTrue(play.isHittable)
            if assetID == "00000000-0000-7000-8000-000000000097" {
                let row = harness.element("playstead.game.\(assetID).summary")
                XCTAssertTrue(row.exists)
                let cardTitle = harness.element("playstead.game.\(assetID).title", type: .staticText)
                XCTAssertTrue(cardTitle.awaitExistence(timeout: 5))
                XCTAssertGreaterThan(cardTitle.frame.height, 0)
                XCTAssertLessThanOrEqual(cardTitle.frame.height, 56,
                                         "card title must remain within its two-line region at the supported app minimum")
                XCTAssertLessThanOrEqual(cardTitle.frame.width, row.frame.width)
                let listPicker = harness.element("playstead.library.view-mode")
                let list = listPicker.descendants(matching: .any)["playstead.control.show-list"]
                XCTAssertTrue(list.awaitExistence(timeout: 5))
                list.clickWhenHittable()
                let listTitle = row.staticTexts.firstMatch
                XCTAssertTrue(listTitle.awaitExistence(timeout: 5))
                XCTAssertEqual(harness.element("playstead.game.\(assetID).title", type: .staticText).frame.height,
                               listTitle.frame.height, accuracy: 1)
                XCTAssertLessThanOrEqual(listTitle.frame.height, 24,
                                         "the 4096-character list title must remain one line at the 960×560 supported minimum")
                let moreActions = harness.app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", "More actions for")).firstMatch
                XCTAssertTrue(moreActions.awaitExistence(timeout: 5))
                XCTAssertTrue(moreActions.isHittable, "long titles must not hide More Actions")
                XCTAssertTrue(focusWithTab(moreActions), "More Actions must remain keyboard reachable beside a 4096-character title")
                harness.app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(focusWithTab(play), "Play must remain keyboard reachable beside a 4096-character title")
            }
            openReadiness()
            let row = harness.element("playstead.readiness.row.systemSupport")
            XCTAssertTrue(row.awaitExistence(timeout: 5), "qualified system check must remain visible once")
            let details = harness.element("playstead.readiness.row.systemSupport.details", type: .button)
            XCTAssertTrue(details.exists)
            let content = harness.element("playstead.readiness.content")
            for _ in 0..<6 where !details.isHittable { content.swipeUp() }
            details.clickWhenHittable()
            XCTAssertTrue(harness.element("playstead.readiness.row.systemSupport.detail.0").readableText.contains(system))
            XCTAssertTrue(harness.element("playstead.readiness.row.systemSupport.detail.1").readableText.contains(cartridge))
        }


    }

    func testSaveHistoryAndStatusStates() throws {
        launch(.storage)
        openReadiness()
        openHistory()
        let noSavesCopy = harness.element("playstead.surface.save-history").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "No saves yet.", "No saves yet."))
            .firstMatch
        XCTAssertTrue(noSavesCopy.awaitExistence(timeout: 5), "zero revisions must use the approved no-save heading")
        XCTAssertTrue(noSavesCopy.readableText.contains("Play Synthetic Offline Fixture and your progress will show up here."))
        closeHistory()

        launch(.saveRestorable)
        openReadiness()
        openHistory()
        let uploaded = harness.element("playstead.save-history.session.0.row.0")
        XCTAssertTrue(uploaded.awaitExistence(timeout: 5), "uploaded revision identity must be retained")
        XCTAssertTrue(hasDescendantText("On your server", in: uploaded))
        closeHistory()

        launch(.saveDiverged)
        openReadiness()
        let reviewVersions = harness.element("playstead.readiness.row.saveState.remedy", type: .button)
        XCTAssertTrue(reviewVersions.awaitExistence(timeout: 5))
        XCTAssertEqual(reviewVersions.label, "Review versions…")
        reviewVersions.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.conflict-comparison").awaitExistence(timeout: 5))
        XCTAssertTrue(harness.element("playstead.conflict-comparison.side.0").exists)
        XCTAssertTrue(harness.element("playstead.conflict-comparison.side.1").exists)
        XCTAssertTrue(harness.element("playstead.conflict-comparison.done", type: .button).isHittable)
        XCTAssertLessThanOrEqual(harness.element("playstead.surface.conflict-comparison").frame.height, 520)

        launch(.gbcMBC3RTCQualified)
        openReadiness()
        openHistory()
        let rtcRow = harness.element("playstead.save-history.session.0.row.0")
        XCTAssertTrue(rtcRow.awaitExistence(timeout: 5))
        XCTAssertTrue(hasDescendantText("On your server", in: rtcRow))
        let rtcDetails = harness.element("playstead.save-history.session.0.row.0.details", type: .button)
        XCTAssertTrue(rtcDetails.awaitExistence(timeout: 5), "complete RTC artifact facts must be behind Details")
        XCTAssertFalse(harness.element("playstead.save-history.session.0.row.0.rtc-detail").exists)
        rtcDetails.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.save-history.session.0.row.0.rtc-detail").readableText
            .contains("This Game Boy Color save includes cartridge clock data. Playstead keeps the complete save artifact with this game's version."))
        let rtcRowIdentity = rtcRow.identifier
        let rtcRowLabel = rtcRow.label
        closeHistory()
        openHistory()
        let reopenedRTCRow = harness.element("playstead.save-history.session.0.row.0")
        XCTAssertTrue(reopenedRTCRow.awaitExistence(timeout: 5))
        XCTAssertEqual(reopenedRTCRow.identifier, rtcRowIdentity)
        XCTAssertEqual(reopenedRTCRow.label, rtcRowLabel,
                       "reopening unchanged local history must preserve revision identity and durability wording")

        launch(.gbcMBC3RTCQueuedOffline, extraEnvironment: ["PLAYSTEAD_UI_TEST_WINDOW_SIZE": "480x360"])
        let offlinePlay = harness.element("playstead.game.00000000-0000-7000-8000-000000000103.play", type: .button)
        XCTAssertTrue(offlinePlay.awaitExistence(timeout: 5), "pending save upload must not block verified local offline play")
        openReadiness()
        let saveState = harness.element("playstead.readiness.row.saveState")
        XCTAssertTrue(saveState.awaitExistence(timeout: 5))
        XCTAssertTrue(saveState.readableText.contains("It'll copy to your server when it's reachable."))
        openHistory()
        let pendingRow = harness.element("playstead.save-history.session.0.row.0")
        XCTAssertTrue(pendingRow.awaitExistence(timeout: 5))
        XCTAssertTrue(hasDescendantText("Waiting to copy", in: pendingRow))
        XCTAssertFalse(hasDescendantText("On your server", in: pendingRow))
        let longDevice = harness.element("playstead.save-history.session.0")
        XCTAssertTrue(longDevice.awaitExistence(timeout: 5))
        XCTAssertLessThanOrEqual(longDevice.readableText.count, 120)
        XCTAssertTrue(longDevice.readableText.hasSuffix("…"))
        let constrainedHistory = harness.element("playstead.surface.save-history")
        XCTAssertEqual(constrainedHistory.frame.width, 480, accuracy: 2)
        XCTAssertEqual(constrainedHistory.frame.height, 360, accuracy: 2)
        let historyScroll = constrainedHistory.scrollViews.firstMatch
        XCTAssertTrue(historyScroll.exists, "history content must remain in its real scroll view at 480×360")
        historyScroll.swipeUp()
        XCTAssertTrue(pendingRow.exists, "scrolling must retain the local pending revision")
        XCTAssertTrue(harness.element("playstead.save-history.done", type: .button).isHittable,
                      "the history return action must remain reachable at 480×360")

        let sessionID = UUID().uuidString.lowercased()
        let assetID = "00000000-0000-7000-8000-000000000104"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-ui-profile-sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        persistentProfileRoot = root
        harness = UITestHarness(
            profile: .gbcIncompatibleRestore, sessionID: sessionID,
            extraEnvironment: ["PLAYSTEAD_UI_TEST_CONTROLLER_SOURCE": "1"]
        )
        harness.launch(settledAt: "playstead.surface.library")
        let sentinelURL = root.appendingPathComponent("saves", isDirectory: true)
            .appendingPathComponent(assetID, isDirectory: true)
            .appendingPathComponent("qualified-mbc3-rtc.sav")
        let targetBefore = try Data(contentsOf: sentinelURL)
        XCTAssertEqual(targetBefore.count, 32_816)
        let incompatiblePlay = harness.element("playstead.game.\(assetID).play", type: .button)
        XCTAssertTrue(incompatiblePlay.awaitExistence(timeout: 5))
        incompatiblePlay.clickWhenHittable()
        let startIdentityCheck = harness.app.buttons["controller.identity.start"]
        XCTAssertTrue(startIdentityCheck.awaitExistence(timeout: 5), "the production launch path must request controller attestation before gameplay")
        startIdentityCheck.clickWhenHittable()
        let blocked = harness.element("playstead.readiness.row.saveState")
        XCTAssertTrue(blocked.awaitExistence(timeout: 5), "the real MBC5-to-MBC3 compatibility verdict must block at Play")
        XCTAssertTrue(blocked.readableText.contains("This save doesn't match this game's supported cartridge layout. Nothing was restored."))
        XCTAssertFalse(harness.app.buttons["Play"].exists)
        let processState = harness.app.descendants(matching: .any)["playstead.test.recovery-emulator-process-id.\(assetID)"]
        XCTAssertEqual(processState.value as? String, "idle", "an incompatible save must be rejected before child launch")
        let compatibleVersions = harness.element("playstead.readiness.row.saveState.remedy", type: .button)
        XCTAssertEqual(compatibleVersions.label, "Choose a compatible saved version or return to the game.")
        compatibleVersions.clickWhenHittable()
        let retainedRevision = harness.element("playstead.save-history.session.0.row.0")
        XCTAssertTrue(retainedRevision.awaitExistence(timeout: 5))
        XCTAssertTrue(hasDescendantText("On your server", in: retainedRevision))
        XCTAssertEqual(try Data(contentsOf: sentinelURL), targetBefore, "rejection must leave every target byte unchanged")
        closeHistory()
        harness.element("playstead.control.done", type: .button).clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.library").awaitExistence(timeout: 5))
        let stillBlocked = harness.element("playstead.control.open-readiness", type: .button)
        XCTAssertTrue(stillBlocked.awaitExistence(timeout: 5), "dismissing history and readiness must preserve the same game's actionable incompatibility")
        XCTAssertFalse(harness.app.buttons["Play"].exists, "dismissing the incompatible-restore report must not restore unsafe Play")
        XCTAssertEqual(stillBlocked.label, "What's needed")
        XCTAssertEqual(processState.value as? String, "idle", "dismissal must not launch the emulator")
        XCTAssertEqual(try Data(contentsOf: sentinelURL), targetBefore, "history/readiness dismissal must preserve every target byte")
    }

    private func launch(_ profile: UITestHarness.Profile, extraEnvironment: [String: String] = [:]) {
        if let previous = harness {
            previous.app.terminate()
            XCTAssertTrue(previous.app.wait(for: .notRunning, timeout: 5), "prior deterministic app profile must exit before the next fixture")
        }
        harness = UITestHarness(profile: profile, extraEnvironment: ["PLAYSTEAD_UI_TEST_WINDOW_SIZE": "960x560"].merging(extraEnvironment) { _, new in new })
        harness.launch(settledAt: "playstead.surface.library")
    }

    private func openReadiness() {
        let action = harness.element("playstead.control.open-readiness", type: .button)
        XCTAssertTrue(action.awaitExistence(timeout: 5))
        action.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.readiness").awaitExistence(timeout: 5))
    }

    private func openHistory() {
        let action = harness.element("playstead.readiness.open-save-history", type: .button)
        XCTAssertTrue(action.awaitExistence(timeout: 5), "save-history route must remain available from readiness")
        let content = harness.element("playstead.readiness.content")
        // `isHittable` can be true when a control extends just beyond the
        // ScrollView's clipped viewport. Require its full frame inside the
        // viewport before clicking; otherwise the click can land on the
        // underlying Done control at the supported 480×360 history size.
        for _ in 0..<8 where !content.frame.contains(action.frame) { content.swipeUp() }
        XCTAssertTrue(content.frame.contains(action.frame),
                      "save-history action must be fully inside the readiness viewport after scrolling")
        XCTAssertTrue(action.isHittable, "save-history navigation must be reachable by scrolling readiness content")
        action.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.save-history").awaitExistence(timeout: 5))
    }

    private func closeHistory() {
        let done = harness.element("playstead.save-history.done", type: .button)
        XCTAssertTrue(done.isHittable)
        done.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.readiness").awaitExistence(timeout: 5))
    }

    private func hasDescendantText(_ text: String, in element: XCUIElement) -> Bool {
        element.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text))
            .firstMatch.awaitExistence(timeout: 5)
    }

    private func focusWithTab(_ target: XCUIElement) -> Bool {
        for _ in 0..<32 {
            if target.value(forKey: "hasKeyboardFocus") as? Bool == true { return true }
            harness.app.typeKey(.tab, modifierFlags: [])
        }
        return target.value(forKey: "hasKeyboardFocus") as? Bool == true
    }
}

private enum DownloadsProgressIdentifier {
    static func row(_ slot: Int) -> String { "playstead.download.row.\(slot)" }
    static func progress(_ slot: Int) -> String { "\(row(slot)).progress" }
}
