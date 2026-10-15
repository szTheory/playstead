import XCTest
import Security
import AppKit
import CryptoKit

@MainActor
final class MetadataPrivateMediaJourneyTests: XCTestCase {
    private var app: XCUIApplication?
    private var keychain: SecKeychain?
    private var root: URL?

    override func tearDownWithError() throws {
        app?.terminate()
        if let app { XCTAssertEqual(app.state, .notRunning, "metadata media app must be closed") }
        if let keychain { SecKeychainDelete(keychain) }
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testPrivateMediaExportAndProviderDisclosureUsePairedProductionRoutes() throws {
        let env = ProcessInfo.processInfo.environment
        guard let configPath = env["PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG"],
              let config = try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: configPath))),
              runtimeConfigurationMatchesRun(configPath, configured: config),
              let serverRoot = config["PLAYSTEAD_MAC_CI_ROOT"],
              let caPath = env["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"],
              let caDigest = env["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"] else {
            return XCTFail("metadata media live fixture configuration is missing")
        }
        let runRoot = FileManager.default.temporaryDirectory.appendingPathComponent("playstead-metadata-media-\(UUID().uuidString.lowercased())", isDirectory: true)
        root = runRoot
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/ci/live-server.sh")
        let fixture = Process()
        let fixtureEnvironment = env.merging(config) { _, configured in configured }
        fixture.executableURL = URL(fileURLWithPath: "/bin/bash")
        fixture.arguments = [script.path, "prepare", runRoot.path, serverRoot]
        fixture.environment = fixtureEnvironment
        fixture.standardOutput = FileHandle.nullDevice
        fixture.standardError = FileHandle.nullDevice
        try fixture.run()
        fixture.waitUntilExit()
        guard fixture.terminationStatus == 0 else { return XCTFail("metadata media paired fixture setup failed") }

        let importFixture = Process()
        importFixture.executableURL = URL(fileURLWithPath: "/bin/bash")
        importFixture.arguments = [script.path, "gb-import", runRoot.path, serverRoot, "gbc-mbc5-32k"]
        importFixture.environment = fixtureEnvironment
        importFixture.standardOutput = FileHandle.nullDevice
        importFixture.standardError = FileHandle.nullDevice
        try importFixture.run()
        importFixture.waitUntilExit()
        guard importFixture.terminationStatus == 0 else { return XCTFail("metadata media private fixture import failed") }
        let importReceiptURL = URL(fileURLWithPath: serverRoot)
            .appendingPathComponent("mac-client-control/gbc-mbc5-32k-import.json")
        let importReceipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: importReceiptURL)) as? [String: Any]
        )
        let selectedAssetID = try XCTUnwrap(importReceipt["asset_set_id"] as? String)
        XCTAssertEqual(importReceipt["system"] as? String, "gbc")

        let handoff = runRoot.appendingPathComponent("credential-handoff.json")
        // Bootstrap consumes the handoff after Keychain installation. Keep
        // the existing fixture's private test copy for read-only assertions
        // and the explicit second-device edit, then remove it in teardown.
        let credentialCopy = runRoot.appendingPathComponent("test-credential.json")
        try FileManager.default.copyItem(at: handoff, to: credentialCopy)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialCopy.path)
        let keychainURL = runRoot.appendingPathComponent("metadata.keychain-db")
        let password = Data("metadata-\(UUID().uuidString)".utf8)
        var created: SecKeychain?
        let status = keychainURL.path.withCString { path in
            password.withUnsafeBytes { bytes in SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created) }
        }
        XCTAssertEqual(status, errSecSuccess)
        keychain = created
        let trust = try LiveServerTestTrustAnchor(sourcePath: caPath, expectedSHA256: caDigest, runRoot: runRoot)

        // Author the exact private pixels here. The previous embedded PNG had
        // a bad IDAT CRC that ImageIO tolerated but libvips rejects.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 4, bitsPerPixel: 32)!
        bitmap.setColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1), atX: 0, y: 0)
        let png = bitmap.representation(using: .png, properties: [:])!
        let pngURL = runRoot.appendingPathComponent("private-cover.png")
        try png.write(to: pngURL, options: .atomic)
        let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
        let jpegURL = runRoot.appendingPathComponent("private-cover.jpg")
        try jpeg.write(to: jpegURL, options: .atomic)
        let text = Data("Private description authored for this library.".utf8)
        let textURL = runRoot.appendingPathComponent("private-description.txt")
        try text.write(to: textURL, options: .atomic)
        let launched = XCUIApplication()
        app = launched
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_ROOT"] = runRoot.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF"] = handoff.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN"] = keychainURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"] = "dev.playstead.mac.live.\(UUID().uuidString.lowercased())"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_METADATA_PNG_FILE"] = pngURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_METADATA_JPEG_FILE"] = jpegURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_METADATA_TEXT_FILE"] = textURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_METADATA_ASSET_ID"] = selectedAssetID
        trust.install(on: launched)
        launched.launch()
        launched.activate()
        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))
        XCTAssertTrue(launched.descendants(matching: .any)["playstead.sidebar.settings"].awaitExistence(timeout: 10))
        launched.descendants(matching: .any)["playstead.sidebar.settings"].clickWhenHittable()
        launched.descendants(matching: .any)["playstead.settings.open.metadata"].clickWhenHittable()
        let gamePicker = launched.descendants(matching: .any)["playstead.metadata.game-picker"]
        XCTAssertTrue(gamePicker.awaitExistence(timeout: 10))
        let selectedGameValue = try XCTUnwrap(gamePicker.value as? String)
        XCTAssertTrue(["gbc-mbc5-32k", "gbc-mbc5-32k · gbc"].contains(selectedGameValue),
                      "the native picker must identify the imported GBC asset title")

        let disclosure = launched.buttons["playstead.metadata.consent.preview"]
        XCTAssertTrue(disclosure.awaitExistence(timeout: 10))
        launched.activate()
        disclosure.clickWhenHittable()
        XCTAssertTrue(launched.staticTexts["playstead.metadata.consent.disclosure"].awaitExistence(timeout: 10))
        XCTAssertTrue(launched.staticTexts["gbc-mbc5-32k"].exists, "the exact preview title must match the selected fixture")
        XCTAssertTrue(launched.staticTexts["gbc"].exists, "the exact preview system must match the selected GBC fixture")
        XCTAssertFalse(launched.buttons["playstead.metadata.candidates.search"].isEnabled)
        let consent = launched.buttons["playstead.metadata.consent.toggle"]
        XCTAssertTrue(consent.isEnabled)
        launched.activate()
        consent.clickWhenHittable()
        let search = launched.buttons["playstead.metadata.candidates.search"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        launched.activate()
        search.clickWhenHittable()
        let suggestion = launched.buttons.matching(NSPredicate(format: "label == 'Select this title'" )).firstMatch
        XCTAssertTrue(suggestion.awaitExistence(timeout: 15))
        launched.activate()
        // XCTest scrolls an offscreen element into the enclosing Settings
        // ScrollView when click() is synthesized. A pre-click isHittable check
        // rejects that valid path before XCTest can perform its scroll.
        suggestion.click()
        let selectedStatus = launched.staticTexts["playstead.metadata.status"]
        let selectedTitle = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Selected title saved with provider evidence"),
            object: selectedStatus
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selectedTitle], timeout: 10), .completed,
                       "the offscreen candidate click must persist the explicit selection")

        let preparationID = "playstead.metadata.preparation.game."
        let selection = launched.checkBoxes.matching(NSPredicate(format: "identifier == %@", preparationID + selectedAssetID)).firstMatch
        XCTAssertTrue(selection.awaitExistence(timeout: 10))
        XCTAssertEqual(selection.label, "gbc-mbc5-32k", "stable checkbox identity must retain its truthful fixture title")
        launched.activate()
        selection.click()
        let estimate = launched.buttons["playstead.metadata.preparation.estimate"]
        launched.activate()
        estimate.click()
        let preparationReview = launched.staticTexts["playstead.metadata.preparation.review"]
        XCTAssertTrue(preparationReview.awaitExistence(timeout: 15))
        XCTAssertTrue(preparationReview.readableText.contains("1 games"),
                      "the server-backed estimate must include the selected game")
        launched.activate()
        launched.buttons["playstead.metadata.preparation.enqueue"].clickWhenHittable()
        let job = launched.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'playstead.metadata.preparation.job.'")).firstMatch
        XCTAssertTrue(job.awaitExistence(timeout: 15))
        let cancel = job.buttons["Cancel"]
        if cancel.exists && cancel.isEnabled { cancel.clickWhenHittable() }

        let upload = launched.buttons["playstead.metadata.media.test-upload.png"]
        XCTAssertTrue(upload.awaitExistence(timeout: 10))
        launched.activate()
        upload.click()
        let pngDigest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let receipt = launched.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Private original")).firstMatch
        XCTAssertTrue(receipt.awaitExistence(timeout: 20))
        XCTAssertTrue(receipt.readableText.contains(String(pngDigest.prefix(12))))
        let cover = launched.buttons["Select as cover"]
        XCTAssertTrue(cover.awaitExistence(timeout: 10))
        cover.click()
        let coverSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Private artwork selected"),
            object: launched.staticTexts["playstead.metadata.status"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [coverSelected], timeout: 10), .completed)
        let export = launched.buttons.matching(NSPredicate(format: "label == 'Export and verify original'")).firstMatch
        XCTAssertTrue(export.awaitExistence(timeout: 10))
        export.click()
        XCTAssertTrue(launched.staticTexts["playstead.metadata.media.verified-original"].awaitExistence(timeout: 20))
        XCTAssertTrue(launched.staticTexts["playstead.metadata.media.verified-original"].readableText.contains(pngDigest))

        let jpegUpload = launched.buttons["playstead.metadata.media.test-upload.jpeg"]
        XCTAssertTrue(jpegUpload.awaitExistence(timeout: 10))
        jpegUpload.click()
        let jpegDigest = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
        let jpegReceipt = launched.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", String(jpegDigest.prefix(12)))).firstMatch
        XCTAssertTrue(jpegReceipt.awaitExistence(timeout: 20))
        let jpegExports = launched.buttons.matching(NSPredicate(format: "label == 'Export and verify original'"))
        jpegExports.element(boundBy: 1).click()
        let jpegVerified = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", jpegDigest),
            object: launched.staticTexts["playstead.metadata.media.verified-original"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [jpegVerified], timeout: 20), .completed)

        let textUpload = launched.buttons["playstead.metadata.media.test-upload.text"]
        XCTAssertTrue(textUpload.awaitExistence(timeout: 10))
        textUpload.click()
        let textDigest = SHA256.hash(data: text).map { String(format: "%02x", $0) }.joined()
        let textReceipt = launched.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", String(textDigest.prefix(12)))).firstMatch
        XCTAssertTrue(textReceipt.awaitExistence(timeout: 20))
        launched.buttons.matching(NSPredicate(format: "label == 'Export and verify original'")).element(boundBy: 2).click()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", textDigest),
            object: launched.staticTexts["playstead.metadata.media.verified-original"]
        )], timeout: 20), .completed)

        let provider = try serverMetadata(root: runRoot, serverRoot: serverRoot, assetID: selectedAssetID, provider: true)
        XCTAssertEqual(provider["enabled"] as? Bool, true)
        XCTAssertEqual(provider["query_preview"] as? String, "gbc-mbc5-32k")
        XCTAssertEqual(provider["system"] as? String, "gbc")
        XCTAssertNotNil(provider["disclosure_revision"] as? String)
        XCTAssertFalse(provider["image_fetch_allowed"] as? Bool ?? true)
        let initialState = try localState(root: runRoot, assetID: selectedAssetID)

        // Relaunch the same paired SQLite profile with an explicit transport
        // failure. No synthetic success response replaces the live server.
        launched.terminate()
        XCTAssertEqual(launched.state, .notRunning)
        launched.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF")
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_START_OFFLINE"] = "1"
        launched.launch()
        openCorrection(launched, assetID: selectedAssetID)
        let offlineTitle = "Offline privately corrected title"
        let offlineDescription = "Offline privately corrected description"
        replace(launched.textFields["playstead.metadata.correction.title"], with: offlineTitle)
        replace(launched.descendants(matching: .any)["playstead.metadata.correction.description"], with: offlineDescription)
        launched.buttons["playstead.metadata.correction.save"].click()
        XCTAssertEqual(launched.staticTexts["playstead.game.\(selectedAssetID).detail-title"].readableText, offlineTitle)
        let offlineState = try localState(root: runRoot, assetID: selectedAssetID)
        XCTAssertEqual((offlineState["pending_fields"] as? [String])?.sorted(), ["description", "title"])

        // A second real server edit races the offline title. Neither value
        // may disappear during reconnect; resolve from the actual form.
        _ = try serverMetadata(root: runRoot, serverRoot: serverRoot, assetID: selectedAssetID,
                               newTitle: "Concurrent server title")
        launched.terminate()
        XCTAssertEqual(launched.state, .notRunning)
        launched.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_LIVE_START_OFFLINE")
        launched.launch()
        openCorrection(launched, assetID: selectedAssetID)
        let conflict = launched.descendants(matching: .any)["playstead.metadata.correction.conflict.title"]
        XCTAssertTrue(conflict.awaitExistence(timeout: 20))
        XCTAssertTrue(launched.staticTexts["Your edit: \(offlineTitle)"].exists)
        XCTAssertTrue(launched.staticTexts["Current server value: Concurrent server title"].exists)
        let keepMyEdit = launched.buttons.matching(NSPredicate(format: "label == %@", "Keep my edit"))
        XCTAssertEqual(keepMyEdit.count, 1, "the one title conflict must expose one explicit resolution action")
        keepMyEdit.element(boundBy: 0).click()
        let resolved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let state = try? self.serverMetadata(root: runRoot, serverRoot: serverRoot, assetID: selectedAssetID),
                  let fields = state["selections"] as? [String: Any],
                  let conflicts = state["conflicts"] as? [[String: Any]] else { return false }
            return fields["title"] as? String == offlineTitle && fields["description"] as? String == offlineDescription && conflicts.isEmpty
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resolved], timeout: 20), .completed)
        let finalMetadata = try serverMetadata(root: runRoot, serverRoot: serverRoot, assetID: selectedAssetID)
        let sources = finalMetadata["field_sources"] as? [String: [String: Any]]
        XCTAssertEqual(sources?["title"]?["source"] as? String, "user")
        XCTAssertEqual(sources?["description"]?["source"] as? String, "user")

        launched.terminate()
        XCTAssertEqual(launched.state, .notRunning)
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/bin/bash")
        reset.arguments = [script.path, "reset-cursor", runRoot.path, serverRoot]
        reset.environment = fixtureEnvironment
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        try reset.run(); reset.waitUntilExit()
        XCTAssertEqual(reset.terminationStatus, 0)
        launched.launch()
        openDetails(launched, assetID: selectedAssetID)
        XCTAssertEqual(launched.staticTexts["playstead.game.\(selectedAssetID).detail-title"].readableText, offlineTitle)
        let coverView = launched.descendants(matching: .any)["playstead.game.\(selectedAssetID).details.cover"]
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR label == %@", "Artwork loaded",
                                   "Game cover for \(offlineTitle). Artwork loaded"),
            object: coverView
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed,
                       "the real digest-bound derivative must decode in the packaged app")
        let finalState = try localState(root: runRoot, assetID: selectedAssetID)
        for key in ["catalogue_ids", "save_line_ids", "save_revision_ids"] {
            XCTAssertEqual(finalState[key] as? [String], initialState[key] as? [String])
        }
    }

    private func openDetails(_ app: XCUIApplication, assetID: String) {
        XCTAssertTrue(app.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "More actions for gbc-mbc5-32k")).firstMatch.click()
        let details = app.descendants(matching: .any)["playstead.game.\(assetID).details.trigger"]
        XCTAssertTrue(details.awaitExistence(timeout: 10))
        details.click()
        XCTAssertTrue(app.descendants(matching: .any)["playstead.game.\(assetID).details"].awaitExistence(timeout: 10))
    }

    private func openCorrection(_ app: XCUIApplication, assetID: String) {
        openDetails(app, assetID: assetID)
        app.buttons["playstead.game.\(assetID).metadata-correction.open"].click()
        XCTAssertTrue(app.descendants(matching: .any)["playstead.metadata.correction.form"].awaitExistence(timeout: 10))
    }

    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.awaitExistence(timeout: 10))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func localState(root: URL, assetID: String) throws -> [String: Any] {
        try pythonJSON("""
import json,sqlite3,sys
c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)
result={k:[r[0] for r in c.execute('SELECT id FROM '+t+' ORDER BY id')] for k,t in
        [('catalogue_ids','catalogue_entries'),('save_line_ids','save_line'),('save_revision_ids','save_revision')]}
result['pending_fields']=[json.loads(r[0])['metadata_field'] for r in c.execute(
    "SELECT payload_json FROM outbox_entries WHERE kind='metadata_correction' AND state IN ('pending','in_flight') AND json_extract(payload_json,'$.asset_set_id')=?",(sys.argv[2],))]
print(json.dumps(result))
""", arguments: [root.appendingPathComponent("playstead.sqlite3").path, assetID])
    }

    private func serverMetadata(root: URL, serverRoot: String, assetID: String,
                                provider: Bool = false, newTitle: String = "") throws -> [String: Any] {
        try pythonJSON("""
import json,pathlib,ssl,sys,urllib.parse,urllib.request,uuid
h=json.loads(pathlib.Path(sys.argv[1]).read_text());p=urllib.parse.urlparse(h['base_url'])
assert p.scheme=='https' and p.hostname=='127.0.0.1' and p.port==4010
ctx=ssl.create_default_context(cafile=sys.argv[2]);url=h['base_url']+'/api/v1/metadata/'+sys.argv[3]
headers={'Authorization':'Bearer '+h['credential']}
if sys.argv[4]=='provider': url+='/provider'
with urllib.request.urlopen(urllib.request.Request(url,headers=headers),context=ctx,timeout=10) as response: result=json.load(response)
if sys.argv[5]:
 body=json.dumps({'field':'title','value':sys.argv[5],'base_revision':result.get('field_revisions',{}).get('title',0)}).encode()
 headers.update({'Content-Type':'application/json','Idempotency-Key':'metadata-concurrent-'+str(uuid.uuid4())})
 with urllib.request.urlopen(urllib.request.Request(url,data=body,headers=headers,method='POST'),context=ctx,timeout=10) as response: result=json.load(response)
print(json.dumps(result))
""", arguments: [root.appendingPathComponent("test-credential.json").path,
                    URL(fileURLWithPath: serverRoot).appendingPathComponent("tls/ca.pem").path,
                    assetID, provider ? "provider" : "selection", newTitle])
    }

    private func pythonJSON(_ script: String, arguments: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        // Emit only the exception category and HTTP status. Never include
        // response bodies, credentials, request headers or local paths.
        let guardedScript = "import sys\ntry:\n" + script.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    " + $0 }.joined(separator: "\n") + "\nexcept Exception as error:\n    print(type(error).__name__ + ':' + str(getattr(error, 'code', '')), file=sys.stderr)\n    sys.exit(1)\n"
        process.arguments = ["-c", guardedScript] + arguments
        let output = Pipe()
        let diagnostics = Pipe()
        process.standardOutput = output
        process.standardError = diagnostics
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            let category = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile().prefix(128), as: UTF8.self)
            throw NSError(domain: "MetadataLiveJourney", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Fixture inspection failed: \(category)"])
        }
        return result
    }
    private func runtimeConfigurationMatchesRun(_ configPath: String, configured: [String: String]) -> Bool {
        guard let server = configured["PLAYSTEAD_MAC_CI_ROOT"],
              let stage = configured["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"] else { return false }
        let serverURL = URL(fileURLWithPath: server).resolvingSymlinksInPath().standardizedFileURL
        let stageURL = URL(fileURLWithPath: stage).resolvingSymlinksInPath().standardizedFileURL
        let expected = serverURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("live-server-runtime.json")
        return serverURL == stageURL && URL(fileURLWithPath: configPath)
            .resolvingSymlinksInPath().standardizedFileURL == expected
    }

}
