import XCTest
import AppKit
import CryptoKit
import Darwin
import Foundation
import Vision

/// Production continuity tracer for the pinned GB/GBC cartridge contracts. It uses
/// the same live isolated Phoenix stack as the pairing proof, imports only
/// the locally registered authored fixture, and asks the real Play action
/// to launch the pinned Qt process before examining its scripting console.
@MainActor
final class GBGBCSaveContinuityTests: XCTestCase {
    private var app: XCUIApplication?
    private var oracleFiles: [URL] = []
    private var ownedProfiles: [URL] = []
    private let oracleToolsRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    override func tearDownWithError() throws {
        app?.terminate()
        // A failed console/oracle assertion must not leave this selector's
        // child running while the next selector attaches to the same bundle.
        for profile in ownedProfiles {
            _ = try runPython(arguments: [
                oracleToolsRoot.appendingPathComponent("playstead-mac/scripts/ci/cleanup-gb-gbc-save-children.py").path,
                "--executable", managedPinnedExecutableURL.path,
                "--profile-root", profile.path
            ])
        }
        ownedProfiles.removeAll()
        for file in oracleFiles { try? FileManager.default.removeItem(at: file) }
        try super.tearDownWithError()
    }

    func testGBMBC1FreshProfileGameReadback() throws {
        try runFreshProfileGameReadback(fixtureName: "gb-mbc1-8k")
    }

    func testGBCMBC5FreshProfileGameReadback() throws {
        try runFreshProfileGameReadback(fixtureName: "gbc-mbc5-32k")
    }

    func testGBCMBC3RTCFreshProfileGameReadback() throws {
        try runFreshProfileGameReadback(fixtureName: "gbc-mbc3-rtc")
    }

    func testAerevenAdvanceGBARestoreMenuRegression() throws {
        try runAerevenAdvanceGBARestoreMenuRegression()
    }

    private func runAerevenAdvanceGBARestoreMenuRegression() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let registryPath = environment["PLAYSTEAD_AEREVEN_FIXTURE_REGISTRY"],
              let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"],
              let caPath = environment["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"],
              let caDigest = environment["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"] else {
            return XCTFail("aereven-e2e=required-runner-input-missing")
        }
        let registryURL = URL(fileURLWithPath: registryPath)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: registryPath),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              let registryData = try? Data(contentsOf: registryURL),
              let registry = try? JSONSerialization.jsonObject(with: registryData) as? [String: Any],
              registry["schema"] as? String == "playstead.local-test-fixture.v1",
              registry["fixture_id"] as? String == "aerevenadvance",
              registry["system_id"] as? String == "gba",
              let game = registry["game"] as? [String: Any],
              let romPath = game["path"] as? String,
              let romSHA = game["sha256"] as? String,
              game["size_bytes"] as? Int == 5_564_940,
              romSHA == "de968dca9f86f1648bb2bb992d6ce4aa4007d3bf7a064b4bbfd82a96e29409ab",
              sha256Hex(at: URL(fileURLWithPath: romPath)) == romSHA,
              let save = registry["persistent_save"] as? [String: Any],
              let savePath = save["path"] as? String,
              let saveSHA = save["sha256"] as? String,
              save["size_bytes"] as? Int == 32_768,
              saveSHA == "8efc60d327e3c485e0d5bdcd93503059d1ea9f92dcd8f14813b39f689e5aa9cf",
              sha256Hex(at: URL(fileURLWithPath: savePath)) == saveSHA else {
            return XCTFail("aereven-e2e=registry-or-original-lineage-mismatch")
        }
        let runRoot = URL(fileURLWithPath: environment["PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT"] ?? "")
            .appendingPathComponent("aerevenadvance", isDirectory: true)
        guard runRoot.path.hasPrefix(FileManager.default.temporaryDirectory.path) else {
            return XCTFail("aereven-e2e=private-profile-root-invalid")
        }
        let runnerRoot = runRoot.deletingLastPathComponent()
        let runID = String(runnerRoot.lastPathComponent.dropFirst("playstead-gb-save-e2e.".count))
        guard runID.utf8.count == 6 else { return XCTFail("aereven-e2e=run-identity-invalid") }
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard try runFixture("pair-provision", root: runRoot, serverRoot: serverRoot) else {
            return XCTFail("aereven-e2e=disposable-owner-provision-failed")
        }

        let sourceRoot = runRoot.appendingPathComponent("source-profile", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        ownedProfiles.append(sourceRoot)
        let sourceKeychain = sourceRoot.appendingPathComponent("source.keychain-db")
        let sourceCA = sourceRoot.appendingPathComponent("server-ca.der")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: caPath), to: sourceCA)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceCA.path)
        let source = XCUIApplication()
        app = source
        configureApp(source, profileRoot: sourceRoot, keychainURL: sourceKeychain, caURL: sourceCA, caDigest: caDigest)
        source.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED"] = "1"
        source.launch()
        guard source.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20) else {
            return XCTFail("aereven-e2e=source-library-unavailable")
        }
        guard requestPairing(in: source, runRoot: runRoot, serverRoot: serverRoot) else {
            return XCTFail("aereven-e2e=source-pairing-failed")
        }
        guard try runFixture("aerevenadvance-import", root: runRoot, serverRoot: serverRoot) else {
            return XCTFail("aereven-e2e=production-import-failed")
        }
        let importPath = URL(fileURLWithPath: serverRoot).appendingPathComponent("mac-client-control/aerevenadvance-import.json")
        let importReceipt = try JSONDecoder().decode(GBImportReceipt.self, from: Data(contentsOf: importPath))
        XCTAssertEqual(importReceipt.system, "gba")
        XCTAssertEqual(importReceipt.sizeBytes, 5_564_940)
        XCTAssertEqual(importReceipt.sha256, romSHA)

        // Seed only the existing registered battery bytes through Plan02's
        // assembled SaveStore → authenticated upload → fresh CAS download →
        // SavePlanExecutor hook. The original itself remains read-only.
        let registeredSaveCopy = sourceRoot.appendingPathComponent("registered-aereven-source.sav")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: savePath), to: registeredSaveCopy)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registeredSaveCopy.path)
        XCTAssertEqual(sha256Hex(at: registeredSaveCopy), saveSHA)
        source.terminate()
        source.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED")
        let seedResult = sourceRoot.appendingPathComponent("aereven-save-custody-result.json")
        source.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_ARTIFACT_PATH"] = registeredSaveCopy.path
        source.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_CONTENT_KEY"] = romSHA
        source.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_RESULT_PATH"] = seedResult.path
        source.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_QUALIFIED_ARTIFACTS"] = "1"
        source.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_AEREVEN_FIXTURE_ARTIFACT"] = "1"
        source.launch()
        guard source.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20) else {
            return XCTFail("aereven-e2e=paired-source-relaunch-failed")
        }
        let seedError = seedResult.deletingPathExtension().appendingPathExtension("error.txt")
        let seedDeadline = Date().addingTimeInterval(180)
        while !FileManager.default.fileExists(atPath: seedResult.path),
              !FileManager.default.fileExists(atPath: seedError.path), Date() < seedDeadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard !FileManager.default.fileExists(atPath: seedError.path) else {
            let reason = (try? String(contentsOf: seedError, encoding: .utf8)) ?? "unknown"
            return XCTFail("aereven-e2e=save-custody-hook-failed; reason=\(reason)")
        }
        guard FileManager.default.fileExists(atPath: seedResult.path) else {
            return XCTFail("aereven-e2e=save-custody-hook-timeout; result=missing after bounded 180s wait")
        }
        let custody = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: seedResult)) as? [String: Any])
        let custodyArtifacts = try XCTUnwrap(custody["artifacts"] as? [[String: Any]])
        XCTAssertEqual(custodyArtifacts.count, 1)
        XCTAssertEqual(custodyArtifacts[0]["captured_sha256"] as? String, saveSHA)
        XCTAssertEqual(custodyArtifacts[0]["downloaded_sha256"] as? String, saveSHA)
        XCTAssertEqual(custodyArtifacts[0]["restored_sha256"] as? String, saveSHA)
        source.terminate()

        let targetRoot = runRoot.appendingPathComponent("target-profile", isDirectory: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        ownedProfiles.append(targetRoot)
        let targetKeychain = targetRoot.appendingPathComponent("target.keychain-db")
        let targetCA = targetRoot.appendingPathComponent("server-ca.der")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: caPath), to: targetCA)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetCA.path)
        let target = XCUIApplication()
        app = target
        configureApp(target, profileRoot: targetRoot, keychainURL: targetKeychain, caURL: targetCA, caDigest: caDigest)
        target.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED"] = "1"
        target.launch()
        guard target.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20) else {
            return XCTFail("aereven-e2e=target-library-unavailable")
        }
        guard requestPairing(in: target, runRoot: runRoot, serverRoot: serverRoot) else {
            return XCTFail("aereven-e2e=target-pairing-failed")
        }
        target.terminate()
        target.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED")
        target.launch()
        guard target.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20) else {
            return XCTFail("aereven-e2e=target-paired-library-relaunch-failed")
        }
        guard installPinnedAdapter(in: target) else { return XCTFail("aereven-e2e=pinned-adapter-install-failed") }
        target.terminate()
        target.launch()
        guard target.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20) else {
            return XCTFail("aereven-e2e=target-library-reconstruction-failed")
        }

        let menuEvidence = runRoot.appendingPathComponent("aereven-continue-menu-evidence.json")
        var menuObservations: [(launch: Int, text: String)] = []
        for launchIndex in 1...2 {
            target.activate()
            XCTAssertTrue(target.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(target.descendants(matching: .any)["playstead.control.show-list"].awaitExistence(timeout: 10))
            target.descendants(matching: .any)["playstead.control.show-list"].click()
            guard selectAllGames(in: target, assetSetID: importReceipt.assetSetID) else {
                return XCTFail("aereven-e2e=restored-game-row-unavailable")
            }
            if launchIndex == 1 {
                let download = target.buttons["playstead.game.\(importReceipt.assetSetID).download"]
                guard download.awaitExistence(timeout: 10) else {
                    return XCTFail("aereven-e2e=target-production-download-unavailable")
                }
                download.click()
                let retry = target.buttons["playstead.game.\(importReceipt.assetSetID).retry"]
                let downloadDeadline = Date().addingTimeInterval(60)
                while Date() < downloadDeadline && !target.buttons["playstead.game.\(importReceipt.assetSetID).play"].exists && !retry.exists {
                    Thread.sleep(forTimeInterval: 0.25)
                }
                guard !retry.exists, target.buttons["playstead.game.\(importReceipt.assetSetID).play"].exists else {
                    let status = target.staticTexts.matching(identifier: "library.status-label")
                        .allElementsBoundByIndex.map(\.readableText).joined(separator: "; ")
                    return XCTFail("aereven-e2e=target-production-download-failed; status=\(status)")
                }
            }
            let play = target.buttons["playstead.game.\(importReceipt.assetSetID).play"]
            XCTAssertTrue(play.awaitExistence(timeout: 10), "aereven-e2e=restored-play-action-unavailable")
            play.click()
            let identityCheck = target.buttons["controller.identity.start"]
            if identityCheck.awaitExistence(timeout: 5) { identityCheck.click() }
            let processReadout = target.descendants(matching: .any)[
                "playstead.test.recovery-emulator-process-id.\(importReceipt.assetSetID)"
            ]
            let started = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                pinnedApplicationPID(from: processReadout) != nil
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 30), .completed,
                           "aereven-e2e=restored-child-not-observed")
            guard let pidText = processReadout.value as? String, let pid = Int32(pidText), pid > 1,
                  let path = currentProcessPath(pid: pid_t(pid)) else {
                return XCTFail("aereven-e2e=restored-child-identity-unreadable")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).standardizedFileURL.path, managedPinnedExecutableURL.path)
            XCTAssertEqual(sha256Hex(at: URL(fileURLWithPath: path)),
                           "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640")
            guard NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier == "com.endrift.mgba-qt" else {
                return XCTFail("aereven-e2e=child-bundle-mismatch")
            }
            let menuObservation = try captureContinueMenu(by: pid_t(pid), launchIndex: launchIndex)
            guard menuObservation.visible else {
                XCTFail("aereven-e2e=continue-menu-not-visible; recognized=\(menuObservation.text)")
                return
            }
            menuObservations.append((launch: launchIndex, text: menuObservation.text))
            if launchIndex == 1 {
                let child = try XCTUnwrap(NSRunningApplication(processIdentifier: pid_t(pid)))
                XCTAssertTrue(child.terminate())
                let childExited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isTerminated == true"), object: child)
                XCTAssertEqual(XCTWaiter.wait(for: [childExited], timeout: 20), .completed)
                target.terminate()
                target.launch()
                XCTAssertTrue(target.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20),
                              "aereven-e2e=target-app-relaunch-failed")
            } else {
                let child = try XCTUnwrap(NSRunningApplication(processIdentifier: pid_t(pid)))
                XCTAssertTrue(child.terminate())
                let childExited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isTerminated == true"), object: child)
                XCTAssertEqual(XCTWaiter.wait(for: [childExited], timeout: 20), .completed)
            }
        }
        let evidence: [String: Any] = [
            "schema": "playstead.aereven-restore-menu.v1", "run_id": runID,
            "fixture": "aerevenadvance", "system": "gba", "rom_sha256": romSHA,
            "save_sha256": saveSHA, "save_bytes": 32_768, "source_custody": "uploaded-and-authenticated-restored",
            "target_continue_menu_first_launch": menuObservations.contains { $0.launch == 1 },
            "target_continue_menu_relaunch": menuObservations.contains { $0.launch == 2 },
            "menu_oracle": "vision-ocr-of-unique-xctest-mgba-child-window-after-pid-path-sha-bundle-verification",
            "recognized_viewport_text": menuObservations.map { ["launch": $0.launch, "text": $0.text] }
        ]
        guard menuObservations.count == 2,
              menuObservations.contains(where: { $0.launch == 1 }),
              menuObservations.contains(where: { $0.launch == 2 }) else {
            return XCTFail("aereven-e2e=menu-evidence-incomplete")
        }
        try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]).write(to: menuEvidence, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: menuEvidence.path)
    }

    private func runFreshProfileGameReadback(fixtureName: String) throws {
        guard FileManager.default.isReadableFile(atPath: oracleToolsRoot.appendingPathComponent(
            ".planning/spikes/002-persistent-battery-saves/oracle_command.py").path) else {
            return XCTFail("gb-save-e2e=oracle-generator-missing")
        }
        guard FileManager.default.isReadableFile(atPath: oracleToolsRoot.appendingPathComponent(
            ".planning/spikes/001-bios-free-gameplay/verify_pixels.py").path) else {
            return XCTFail("gb-save-e2e=pixel-verifier-missing")
        }
        guard let fixtureSpec = GBFixtureSpec.named(fixtureName) else {
            return XCTFail("gb-save-e2e=unsupported-fixture")
        }
        let environment = ProcessInfo.processInfo.environment
        guard let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"],
              let caPath = environment["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"],
              let caDigest = environment["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"],
              let registry = environment["PLAYSTEAD_GB_GBC_FIXTURE_REGISTRY"] else {
            return XCTFail("gb-save-e2e=required-runner-input-missing")
        }
        guard let rootPath = environment["PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT"] else {
            return XCTFail("gb-save-e2e=private-profile-root-missing")
        }
        let runnerRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let profileName = runnerRoot.lastPathComponent
        let runID = String(profileName.dropFirst("playstead-gb-save-e2e.".count))
        guard profileName.hasPrefix("playstead-gb-save-e2e."),
              runID.utf8.count == 6,
              runID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            return XCTFail("gb-save-e2e=private-run-id-invalid")
        }
        // Every serialized selector receives its own source and target
        // profiles while sharing only the disposable server and run identity.
        let runRoot = runnerRoot.appendingPathComponent(fixtureName, isDirectory: true)
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try runFixture("pair-provision", root: runRoot, serverRoot: serverRoot) else {
            return XCTFail("gb-save-e2e=disposable-owner-provision-failed")
        }

        let sourceRoot = runRoot.appendingPathComponent("source-profile", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        ownedProfiles.append(sourceRoot)
        let keychainURL = sourceRoot.appendingPathComponent("source.keychain-db")
        let caURL = sourceRoot.appendingPathComponent("server-ca.der")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: caPath), to: caURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: caURL.path)

        let launched = XCUIApplication()
        app = launched
        configureApp(launched, profileRoot: sourceRoot, keychainURL: keychainURL, caURL: caURL, caDigest: caDigest)
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED"] = "1"
        launched.launch()
        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20), "gb-save-e2e=source-library-unavailable")
        guard requestPairing(in: launched, runRoot: runRoot, serverRoot: serverRoot) else {
            return XCTFail("gb-save-e2e=source-pairing-failed")
        }
        guard installPinnedAdapter(in: launched) else {
            return XCTFail("gb-save-e2e=pinned-adapter-install-failed")
        }

        // The helper validates the registry alias, exact ROM digest, file
        // type, and size before streaming bytes through Blobs + Import.
        XCTAssertTrue(try runFixture("gb-import", root: runRoot, serverRoot: serverRoot, extraArgument: fixtureName), "gb-save-e2e=production-import-failed")
        let importReceiptURL = URL(fileURLWithPath: serverRoot, isDirectory: true)
            .appendingPathComponent("mac-client-control/\(fixtureName)-import.json")
        let importReceipt = try JSONDecoder().decode(GBImportReceipt.self, from: Data(contentsOf: importReceiptURL))
        XCTAssertEqual(importReceipt.system, fixtureSpec.system)
        XCTAssertEqual(importReceipt.sizeBytes, fixtureSpec.romSize)
        XCTAssertTrue(["new_asset", "unrecognized"].contains(importReceipt.outcome), "gb-save-e2e=production-import-outcome-invalid")
        let registryData = try Data(contentsOf: URL(fileURLWithPath: registry))
        let registryRows = try XCTUnwrap(JSONSerialization.jsonObject(with: registryData) as? [[String: Any]])
        let registeredFixture = try XCTUnwrap(registryRows.first(where: { $0["name"] as? String == fixtureName }))
        XCTAssertEqual(registeredFixture["sha256"] as? String, fixtureSpec.romSHA,
                       "gb-save-e2e=authored-fixture-pin-mismatch")
        XCTAssertEqual(importReceipt.sha256, registeredFixture["sha256"] as? String)

        // A fresh process reconstructs the paired library through the normal
        // API cursor/snapshot path after import has completed on the server.
        launched.terminate()
        launched.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED")
        launched.launch()
        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20), "gb-save-e2e=paired-library-relaunch-failed")
        launched.activate()
        XCTAssertTrue(launched.wait(for: .runningForeground, timeout: 10), "gb-save-e2e=paired-library-not-foreground")
        let showList = launched.descendants(matching: .any)["playstead.control.show-list"]
        XCTAssertTrue(showList.awaitExistence(timeout: 10), "gb-save-e2e=list-layout-unavailable")
        showList.click()
        guard selectAllGames(in: launched, assetSetID: importReceipt.assetSetID) else {
            return XCTFail("gb-save-e2e=imported-game-row-unavailable")
        }
        let download = launched.buttons["playstead.game.\(importReceipt.assetSetID).download"]
        XCTAssertTrue(download.awaitExistence(timeout: 10), "gb-save-e2e=production-download-unavailable")
        download.click()
        let play = launched.buttons["playstead.game.\(importReceipt.assetSetID).play"]
        let retry = launched.buttons["playstead.game.\(importReceipt.assetSetID).retry"]
        let cacheDeadline = Date().addingTimeInterval(60)
        while Date() < cacheDeadline && !play.exists && !retry.exists {
            Thread.sleep(forTimeInterval: 0.25)
        }
        if retry.exists {
            let status = launched.staticTexts.matching(identifier: "library.status-label")
                .allElementsBoundByIndex.map(\.readableText).joined(separator: "; ")
            return XCTFail("gb-save-e2e=production-download-failed; status=\(status)")
        }
        guard play.exists else {
            let status = launched.staticTexts.matching(identifier: "library.status-label")
                .allElementsBoundByIndex.map(\.readableText).joined(separator: "; ")
            return XCTFail("gb-save-e2e=verified-cache-not-playable; status=\(status)")
        }

        play.click()
        let startIdentityCheck = launched.buttons["controller.identity.start"]
        if startIdentityCheck.awaitExistence(timeout: 5) {
            startIdentityCheck.click()
        }
        let processReadout = launched.descendants(matching: .any)["playstead.test.recovery-emulator-process-id.\(importReceipt.assetSetID)"]
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            pinnedApplicationPID(from: processReadout) != nil
        }, object: nil)
        let processWait = XCTWaiter.wait(for: [started], timeout: 30)
        if processWait != .completed {
            let status = launched.staticTexts.matching(identifier: "library.status-label")
                .allElementsBoundByIndex.map(\.readableText).joined(separator: "; ")
            let alerts = launched.alerts.allElementsBoundByIndex.map(\.readableText).joined(separator: "; ")
            let hierarchy = launched.debugDescription.components(separatedBy: "\n")
                .filter { $0.localizedCaseInsensitiveContains("controller") || $0.localizedCaseInsensitiveContains("launch") || $0.localizedCaseInsensitiveContains("playstead.game.") || $0.localizedCaseInsensitiveContains("playstead.test.recovery") }
                .joined(separator: " | ")
            XCTFail("gb-save-e2e=app-launched-child-not-observed; status=\(status); alerts=\(alerts); hierarchy=\(hierarchy)")
            return
        }
        guard let pidText = processReadout.value as? String, let pidNumber = Int32(pidText), pidNumber > 1 else {
            return XCTFail("gb-save-e2e=app-launched-child-identity-unreadable; readout=\(String(describing: processReadout.value))")
        }
        guard let childPath = currentProcessPath(pid: pid_t(pidNumber)) else {
            return XCTFail("gb-save-e2e=app-launched-child-path-unreadable; pid=\(pidNumber); readout=\(pidText)")
        }
        let expectedChild = managedPinnedExecutableURL.standardizedFileURL.path
        XCTAssertEqual(URL(fileURLWithPath: childPath).standardizedFileURL.path, expectedChild, "gb-save-e2e=child-path-mismatch")
        let childDigest = sha256Hex(at: URL(fileURLWithPath: childPath)) ?? "<unreadable>"
        XCTAssertEqual(childDigest, "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640", "gb-save-e2e=child-digest-mismatch")

        let qtApp = XCUIApplication(bundleIdentifier: "com.endrift.mgba-qt")
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.endrift.mgba-qt")
            .contains(where: { $0.processIdentifier == pid_t(pidNumber) }) else {
            return XCTFail("gb-save-e2e=qt-xctest-attachment-identity-mismatch; child_pid=\(pidNumber); child_path=\(childPath); child_sha256=\(childDigest)")
        }
        qtApp.activate()
        try openScriptingConsole(in: qtApp)
        let console = qtApp.windows.matching(NSPredicate(format: "title CONTAINS[c] %@", "script")).firstMatch
        guard console.waitForExistence(timeout: 5) else {
            return XCTFail("gb-save-e2e=qt-console-window-unavailable; child_pid=\(pidNumber); child_path=\(childPath); child_sha256=\(childDigest)")
        }
        let prompts = console.textFields.allElementsBoundByIndex
        guard let prompt = prompts.first(where: { $0.isHittable }) else {
            return XCTFail("gb-save-e2e=qt-console-repl-prompt-unavailable; child_pid=\(pidNumber); child_path=\(childPath); child_sha256=\(childDigest); text_fields=\(prompts.count); console=\(console.debugDescription)")
        }

        var runEvidence: [String: Any] = [
            "schema": "playstead.gb-gbc-save-continuity.v1",
            "run_id": runID,
            "fixture": fixtureName,
            "system": fixtureSpec.system,
            "save_bytes": fixtureSpec.saveBytes,
            "rtc_bytes": fixtureSpec.rtcBytes,
            "runner_bundle": "dev.playstead.mac.PlaysteadUITests.xctrunner",
            "emulator_sha256": childDigest,
            "source": [
                "pid": pidNumber,
                "executable": childPath,
                "oracle": "pending",
                "pixels": "pending",
                "upload": "pending"
            ],
            "target": ["oracle": "pending", "pixels": "pending"]
        ]
        try writeRunEvidence(runEvidence)
        let sourceLabel = "playstead-gb-source-\(runID)"
        let sourceOracle = try runOracle(fixture: fixtureName, system: fixtureSpec.system, label: sourceLabel, observeOnly: false, in: prompt, console: console)
        XCTAssertEqual(sourceOracle.before, 0, "gb-save-e2e=source-counter-was-not-fresh")
        XCTAssertEqual(sourceOracle.after, 1, "gb-save-e2e=source-did-not-advance-exactly-once")
        XCTAssertEqual(sourceOracle.inputEdges, 1, "gb-save-e2e=source-input-edge-count-invalid")
        XCTAssertEqual(sourceOracle.platform, fixtureSpec.platform, "gb-save-e2e=source-platform-mismatch")
        let sourcePixels = try verifyOraclePixels(fixture: fixtureName, system: fixtureSpec.system, label: sourceLabel, before: 0, after: 1)
        let sourceRTC = fixtureSpec.rtcBytes == 48
            ? try assertRTCRunningClock(label: sourceLabel, prompt: prompt, console: console)
            : nil
        runEvidence["source"] = [
            "pid": pidNumber,
            "executable": childPath,
            "sha256": childDigest,
            "oracle": ["before": sourceOracle.before, "after": sourceOracle.after,
                       "input_edges": sourceOracle.inputEdges, "platform": sourceOracle.platform],
            "pixels": sourcePixels,
            "rtc_clock": sourceRTC as Any? ?? NSNull(),
            "upload": "pending"
        ]
        try writeRunEvidence(runEvidence)

        // The command is scheduled by the original bounded spike generator;
        // allow its callback frames to finish before asking the real Qt app
        // to quit so the production capture coordinator sees the settled RAM.
        let emulator = try XCTUnwrap(NSRunningApplication(processIdentifier: pid_t(pidNumber)))
        XCTAssertTrue(emulator.terminate(), "gb-save-e2e=normal-quit-request-rejected")
        let childExited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isTerminated == true"), object: emulator)
        XCTAssertEqual(XCTWaiter.wait(for: [childExited], timeout: 20), .completed, "gb-save-e2e=normal-quit-not-observed")
        let appExited = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "exited"), object: processReadout
        )
        XCTAssertEqual(XCTWaiter.wait(for: [appExited], timeout: 20), .completed, "gb-save-e2e=playstead-host-exit-not-observed")
        guard waitForUploadedRevision(in: launched) else {
            runEvidence["sourceUpload"] = "not verified"
            try writeRunEvidence(runEvidence)
            return XCTFail("gb-save-e2e=source-revision-not-uploaded")
        }
        if var sourceEvidence = runEvidence["source"] as? [String: Any] {
            sourceEvidence["upload"] = "Latest save is on your server."
            runEvidence["source"] = sourceEvidence
        }
        runEvidence["sourceUpload"] = "save-history-confirmed"
        try writeRunEvidence(runEvidence)
        launched.terminate()

        // Pair an independent clean profile after the source revision is
        // visibly on the server. Its first Play must derive the target from
        // this profile's verified ROM and restore through the production
        // save planner before the observe-only game readback.
        let targetRoot = runRoot.appendingPathComponent("target-profile", isDirectory: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        ownedProfiles.append(targetRoot)
        let targetKeychain = targetRoot.appendingPathComponent("target.keychain-db")
        let targetCA = targetRoot.appendingPathComponent("server-ca.der")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: caPath), to: targetCA)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetCA.path)

        let target = XCUIApplication()
        app = target
        configureApp(target, profileRoot: targetRoot, keychainURL: targetKeychain, caURL: targetCA, caDigest: caDigest)
        target.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED"] = "1"
        target.launch()
        XCTAssertTrue(target.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20), "gb-save-e2e=target-library-unavailable")
        guard requestPairing(in: target, runRoot: runRoot, serverRoot: serverRoot) else {
            return XCTFail("gb-save-e2e=target-pairing-failed")
        }
        target.terminate()
        target.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED")
        target.launch()
        XCTAssertTrue(target.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20), "gb-save-e2e=target-paired-library-relaunch-failed")
        target.activate()
        XCTAssertTrue(target.wait(for: .runningForeground, timeout: 10), "gb-save-e2e=target-not-foreground")
        guard installPinnedAdapter(in: target) else {
            return XCTFail("gb-save-e2e=target-pinned-adapter-install-failed")
        }
        // Settings remains the active surface after adapter verification.
        // Reconstruct the paired library from the target profile before its
        // first Play, matching the normal production relaunch path.
        target.terminate()
        target.launch()
        XCTAssertTrue(target.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20), "gb-save-e2e=target-library-relaunch-failed")
        target.activate()
        XCTAssertTrue(target.wait(for: .runningForeground, timeout: 10), "gb-save-e2e=target-library-not-foreground")
        let targetShowList = target.descendants(matching: .any)["playstead.control.show-list"]
        XCTAssertTrue(targetShowList.awaitExistence(timeout: 10), "gb-save-e2e=target-list-layout-unavailable")
        targetShowList.click()
        guard selectAllGames(in: target, assetSetID: importReceipt.assetSetID) else {
            return XCTFail("gb-save-e2e=target-imported-game-row-unavailable")
        }
        let targetDownload = target.buttons["playstead.game.\(importReceipt.assetSetID).download"]
        XCTAssertTrue(targetDownload.awaitExistence(timeout: 10), "gb-save-e2e=target-download-unavailable")
        targetDownload.click()
        let targetPlay = target.buttons["playstead.game.\(importReceipt.assetSetID).play"]
        let targetRetry = target.buttons["playstead.game.\(importReceipt.assetSetID).retry"]
        let targetCacheDeadline = Date().addingTimeInterval(60)
        while Date() < targetCacheDeadline && !targetPlay.exists && !targetRetry.exists {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertFalse(targetRetry.exists, "gb-save-e2e=target-production-download-failed")
        XCTAssertTrue(targetPlay.exists, "gb-save-e2e=target-cache-not-playable")
        targetPlay.click()
        let targetIdentityCheck = target.buttons["controller.identity.start"]
        if targetIdentityCheck.awaitExistence(timeout: 5) { targetIdentityCheck.click() }
        let targetProcessReadout = target.descendants(matching: .any)["playstead.test.recovery-emulator-process-id.\(importReceipt.assetSetID)"]
        let targetStarted = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            pinnedApplicationPID(from: targetProcessReadout) != nil
        }, object: nil)
        let targetStartResult = XCTWaiter.wait(for: [targetStarted], timeout: 30)
        guard targetStartResult == .completed else {
            let status = target.staticTexts.matching(identifier: "library.status-label")
                .allElementsBoundByIndex.map(\.readableText).joined(separator: "; ")
            let alerts = target.alerts.allElementsBoundByIndex.map(\.readableText).joined(separator: "; ")
            let hierarchy = target.debugDescription.components(separatedBy: "\n")
                .filter { line in
                    ["playstead.game.", "playstead.surface.", "controller.identity", "playstead.test.recovery", "readiness", "launch"]
                        .contains(where: { line.localizedCaseInsensitiveContains($0) })
                }
                .joined(separator: " | ")
            return XCTFail("gb-save-e2e=target-child-not-observed; process_state=\(String(describing: targetProcessReadout.value)); status=\(status); alerts=\(alerts); hierarchy=\(hierarchy)")
        }
        guard let targetPIDText = targetProcessReadout.value as? String, let targetPID = Int32(targetPIDText), targetPID > 1,
              let targetPath = currentProcessPath(pid: pid_t(targetPID)),
              URL(fileURLWithPath: targetPath).standardizedFileURL.path == managedPinnedExecutableURL.standardizedFileURL.path,
              sha256Hex(at: URL(fileURLWithPath: targetPath)) == "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640",
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.endrift.mgba-qt").contains(where: { $0.processIdentifier == pid_t(targetPID) }) else {
            return XCTFail("gb-save-e2e=target-child-identity-mismatch")
        }
        let targetQt = XCUIApplication(bundleIdentifier: "com.endrift.mgba-qt")
        targetQt.activate()
        try openScriptingConsole(in: targetQt)
        let targetConsole = targetQt.windows.matching(NSPredicate(format: "title CONTAINS[c] %@", "script")).firstMatch
        guard targetConsole.waitForExistence(timeout: 5) else { return XCTFail("gb-save-e2e=target-console-unavailable") }
        let targetPrompts = targetConsole.textFields.allElementsBoundByIndex
        guard let targetPrompt = targetPrompts.first(where: { $0.isHittable }) else {
            return XCTFail("gb-save-e2e=target-console-repl-prompt-unavailable; text_fields=\(targetPrompts.count); console=\(targetConsole.debugDescription)")
        }
        let targetLabel = "playstead-gb-target-\(runID)"
        let targetOracle = try runOracle(fixture: fixtureName, system: fixtureSpec.system, label: targetLabel, observeOnly: true, in: targetPrompt, console: targetConsole)
        XCTAssertEqual(targetOracle.before, 1, "gb-save-e2e=target-restored-progress-missing")
        XCTAssertEqual(targetOracle.after, 1, "gb-save-e2e=target-observation-mutated-progress")
        XCTAssertEqual(targetOracle.inputEdges, 0, "gb-save-e2e=target-observe-only-edge-count-invalid")
        XCTAssertEqual(targetOracle.platform, fixtureSpec.platform, "gb-save-e2e=target-platform-mismatch")
        let targetPixels = try verifyOraclePixels(fixture: fixtureName, system: fixtureSpec.system, label: targetLabel, before: 1, after: 1)
        let targetRTC = fixtureSpec.rtcBytes == 48
            ? try assertRTCRunningClock(label: targetLabel, prompt: targetPrompt, console: targetConsole)
            : nil
        runEvidence["target"] = [
            "pid": targetPID,
            "executable": targetPath,
            "sha256": sha256Hex(at: URL(fileURLWithPath: targetPath)) ?? "unreadable",
            "oracle": ["before": targetOracle.before, "after": targetOracle.after,
                       "input_edges": targetOracle.inputEdges, "platform": targetOracle.platform],
            "pixels": targetPixels,
            "rtc_clock": targetRTC as Any? ?? NSNull()
        ]
        try writeRunEvidence(runEvidence)
        let targetEmulator = try XCTUnwrap(NSRunningApplication(processIdentifier: pid_t(targetPID)))
        XCTAssertTrue(targetEmulator.terminate(), "gb-save-e2e=target-normal-quit-request-rejected")
        let targetExited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isTerminated == true"), object: targetEmulator)
        XCTAssertEqual(XCTWaiter.wait(for: [targetExited], timeout: 20), .completed, "gb-save-e2e=target-normal-quit-not-observed")
        let targetHostExited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "exited"), object: targetProcessReadout)
        XCTAssertEqual(XCTWaiter.wait(for: [targetHostExited], timeout: 20), .completed, "gb-save-e2e=target-host-exit-not-observed")
    }

    private func openScriptingConsole(in app: XCUIApplication) throws {
        // XCTest uses the system's UI testing service; direct AX calls from
        // this runner have a separate trust requirement. Preserve the real
        // child identity and game/save oracles without changing permissions
        // or competing with the adapter's private controller configuration.
        let tools = app.menuBars.menuBarItems.matching(
            NSPredicate(format: "title IN %@", ["Tools", "Outils"])
        ).firstMatch
        XCTAssertTrue(tools.awaitExistence(timeout: 5), "gb-save-e2e=tools-menu-missing")
        tools.click()
        let scripting = app.menuItems.matching(
            NSPredicate(format: "title IN %@", ["Scripting...", "Scripting…"])
        ).firstMatch
        XCTAssertTrue(scripting.awaitExistence(timeout: 5), "gb-save-e2e=scripting-menu-missing")
        scripting.click()
    }

    private struct GBImportReceipt: Decodable {
        let assetSetID: String
        let outcome: String
        let sha256: String
        let sizeBytes: Int
        let system: String

        enum CodingKeys: String, CodingKey {
            case assetSetID = "asset_set_id", outcome, sha256, system
            case sizeBytes = "size_bytes"
        }
    }

    private struct GBFixtureSpec {
        let system: String
        let romSize: Int
        let romSHA: String
        let saveBytes: Int
        let rtcBytes: Int
        let platform: Int

        static func named(_ name: String) -> Self? {
            switch name {
            case "gb-mbc1-8k": Self(system: "gb", romSize: 32_768, romSHA: "4d62166b5cd35185ac0977eb73fe5bc22b406141861832863f133d754f635aa4", saveBytes: 8_192, rtcBytes: 0, platform: 1)
            case "gbc-mbc5-32k": Self(system: "gbc", romSize: 32_768, romSHA: "f9d914ba107bfd9676c730d315956a2d264c6e0e74e042afd729f493dcb40a3b", saveBytes: 32_768, rtcBytes: 0, platform: 1)
            case "gbc-mbc3-rtc": Self(system: "gbc", romSize: 32_768, romSHA: "0edb186314a8fee38e00fec0c52e678ba24abf5b00198e3cfcb80c0d3e60cbc7", saveBytes: 32_768, rtcBytes: 48, platform: 1)
            default: nil
            }
        }
    }

    private func configureApp(_ app: XCUIApplication, profileRoot: URL, keychainURL: URL, caURL: URL, caDigest: String) {
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER"] = "1"
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_ROOT"] = profileRoot.path
        app.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN"] = keychainURL.path
        app.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"] = "dev.playstead.mac.live.gb-\(UUID().uuidString.lowercased())"
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_DER"] = caURL.path
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256"] = caDigest
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_PAIRING_TARGET"] = "https://127.0.0.1:4010"
        app.launchEnvironment["PLAYSTEAD_UI_TEST_PAIRING_DEVICE_NAME"] = "Playstead Hosted Mac"
        app.launchEnvironment["PLAYSTEAD_UI_TEST_MANAGED_ADAPTER_SELECTION"] = managedPinnedAppURL.path
        app.launchEnvironment["PLAYSTEAD_UI_TEST_CONTROLLER_SOURCE"] = "1"
    }

    private func requestPairing(in app: XCUIApplication, runRoot: URL, serverRoot: String) -> Bool {
        let menu = app.menuBars.menuBarItems["Pairing"]
        guard menu.awaitExistence(timeout: 10) else { return false }
        menu.click()
        let command = app.menuItems["Pair with Server…"]
        guard command.awaitExistence(timeout: 5) else { return false }
        command.click()
        let server = app.textFields["playstead.control.pairing-server-url"]
        guard server.awaitExistence(timeout: 10) else { return false }
        server.click()
        server.typeText("https://127.0.0.1:4010")
        let request = app.buttons["playstead.control.request-pairing"]
        guard request.awaitExistence(timeout: 5) else { return false }
        request.click()
        let code = app.descendants(matching: .any)["playstead.control.pairing-display-code"]
        guard code.awaitExistence(timeout: 15), let value = code.value as? String, !value.isEmpty else { return false }
        guard (try? runFixture("pair-approve", root: runRoot, serverRoot: serverRoot, extraArgument: value)) == true else { return false }
        let success = app.descendants(matching: .any)["playstead.control.pairing-success"]
        guard success.awaitExistence(timeout: 20) else { return false }
        let done = app.buttons["playstead.control.done"]
        guard done.awaitExistence(timeout: 10) else { return false }
        done.click()
        return true
    }

    private func installPinnedAdapter(in app: XCUIApplication) -> Bool {
        let settings = app.staticTexts["Settings"]
        guard settings.awaitExistence(timeout: 10) else { return false }
        settings.click()
        let pane = app.descendants(matching: .any)["Emulator"]
        guard pane.awaitExistence(timeout: 10) else { return false }
        pane.click()
        let status = app.descendants(matching: .any)["playstead.readout.recovery-adapter-install-status"]
        guard status.awaitExistence(timeout: 10) else { return false }
        // Use the existing managed mGBA 0.10.5 bundle after verifying its
        // exact executable digest. This avoids a redundant release download
        // for each disposable profile while keeping selection and launch on
        // Playstead's production AdapterInstaller/AdapterHost path.
        guard sha256Hex(at: managedPinnedExecutableURL) == "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640" else { return false }
        let choose = app.buttons["playstead.control.choose-adapter"]
        guard choose.awaitExistence(timeout: 10) else { return false }
        choose.click()
        let installed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "verified"), object: status)
        return XCTWaiter.wait(for: [installed], timeout: 20) == .completed
    }

    private var managedPinnedAppURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Playstead/emulators/mgba/0.10.5/mGBA.app", isDirectory: true)
    }

    private var managedPinnedExecutableURL: URL {
        managedPinnedAppURL.appendingPathComponent("Contents/MacOS/mGBA")
    }

    private func selectAllGames(in app: XCUIApplication, assetSetID: String) -> Bool {
        let download = app.buttons["playstead.game.\(assetSetID).download"]
        let play = app.buttons["playstead.game.\(assetSetID).play"]
        if download.exists || play.exists { return true }
        let allGames = app.descendants(matching: .any)["playstead.surface.sidebar"].staticTexts["All Games"]
        guard allGames.awaitExistence(timeout: 10) else { return false }
        allGames.click()
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if download.exists || play.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func runFixture(_ action: String, root: URL, serverRoot: String, extraArgument: String? = nil) throws -> Bool {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/ci/live-server.sh")
        var arguments = [script.path, action, root.path, serverRoot]
        if let extraArgument { arguments.append(extraArgument) }
        guard var environment = fixtureEnvironment() else { return false }
        environment["PLAYSTEAD_GB_GBC_FIXTURE_REGISTRY"] =
            ProcessInfo.processInfo.environment["PLAYSTEAD_GB_GBC_FIXTURE_REGISTRY"]
        environment["PLAYSTEAD_AEREVEN_FIXTURE_REGISTRY"] =
            ProcessInfo.processInfo.environment["PLAYSTEAD_AEREVEN_FIXTURE_REGISTRY"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.environment = environment
        let diagnostics = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = diagnostics
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { _ = diagnostics.fileHandleForReading.readDataToEndOfFile() }
        return process.terminationStatus == 0
    }

    private func fixtureEnvironment() -> [String: String]? {
        let inherited = ProcessInfo.processInfo.environment
        guard let configurationPath = inherited["PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG"],
              (configurationPath as NSString).isAbsolutePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: configurationPath),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              let data = try? Data(contentsOf: URL(fileURLWithPath: configurationPath)),
              data.count <= 32_768,
              let configured = try? JSONDecoder().decode([String: String].self, from: data),
              runtimeConfigurationMatchesRun(URL(fileURLWithPath: configurationPath), configured: configured),
              let path = configured["PATH"], !path.isEmpty,
              configured["MIX_ENV"] == "mac_ci", configured["PORT"] == "4010",
              configured["PLAYSTEAD_MAC_CI_ROOT"] == inherited["PLAYSTEAD_MAC_CI_ROOT"],
              configured["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"] == inherited["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"] else {
            return nil
        }
        return inherited.merging(configured) { _, runtimeValue in runtimeValue }
    }

    private func runtimeConfigurationMatchesRun(_ url: URL, configured: [String: String]) -> Bool {
        let inherited = ProcessInfo.processInfo.environment
        return url.lastPathComponent == "live-server-runtime.json"
            && configured["PLAYSTEAD_MAC_CI_ROOT"] == inherited["PLAYSTEAD_MAC_CI_ROOT"]
            && configured["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"] == inherited["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"]
            && configured["PLAYSTEAD_LIVE_SERVER_STAGE_FILE"] == inherited["PLAYSTEAD_LIVE_SERVER_STAGE_FILE"]
    }

    private func pinnedApplicationPID(from readout: XCUIElement) -> pid_t? {
        // A missing readout has nil value, which also satisfies `value != "idle"`.
        // A spawned PID can also precede AppKit's application registration.
        // Wait for the complete original identity, within the existing deadline.
        guard readout.exists,
              let text = readout.value as? String, let pid = Int32(text), pid > 1,
              let path = currentProcessPath(pid: pid_t(pid)),
              URL(fileURLWithPath: path).standardizedFileURL.path == managedPinnedExecutableURL.standardizedFileURL.path,
              sha256Hex(at: URL(fileURLWithPath: path)) == "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640",
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.endrift.mgba-qt")
                .contains(where: { $0.processIdentifier == pid_t(pid) }) else { return nil }
        return pid_t(pid)
    }

    private func currentProcessPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBufferPointer { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        return length > 0 ? String(cString: buffer) : nil
    }

    private func captureContinueMenu(by pid: pid_t, launchIndex: Int) throws -> (visible: Bool, text: String) {
        guard let processPath = currentProcessPath(pid: pid),
              URL(fileURLWithPath: processPath).standardizedFileURL.path == managedPinnedExecutableURL.path,
              sha256Hex(at: URL(fileURLWithPath: processPath)) == "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640",
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.endrift.mgba-qt" else {
            return (false, "child identity changed before window capture")
        }

        let childApplication = XCUIApplication(url: managedPinnedAppURL)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.endrift.mgba-qt")
            .contains(where: { $0.processIdentifier == pid }) else {
            return (false, "verified mGBA PID is not registered before XCTest window attachment")
        }
        childApplication.activate()
        guard currentProcessPath(pid: pid).map({ URL(fileURLWithPath: $0).standardizedFileURL.path })
                == managedPinnedExecutableURL.path,
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.endrift.mgba-qt")
                .contains(where: { $0.processIdentifier == pid }) else {
            return (false, "mGBA process identity changed during XCTest attachment")
        }
        let windows = childApplication.windows.matching(NSPredicate(format: "title CONTAINS[c] %@", "Aereven2 Adv"))
        guard windows.count == 1 else {
            return (false, "expected one Aereven game window, found \(windows.count)")
        }
        let gameWindow = windows.element(boundBy: 0)
        guard gameWindow.exists, gameWindow.frame.width > 0, gameWindow.frame.height > 0 else {
            return (false, "unique Aereven game window has no visible frame")
        }

        let deadline = Date().addingTimeInterval(15)
        var lastScreenshot: XCUIScreenshot?
        var lastText = ""
        var visible = false
        while Date() < deadline {
            guard currentProcessPath(pid: pid).map({ URL(fileURLWithPath: $0).standardizedFileURL.path })
                    == managedPinnedExecutableURL.path,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.endrift.mgba-qt" else {
                lastText = "verified child identity changed during menu polling"
                break
            }
            let screenshot = gameWindow.screenshot()
            lastScreenshot = screenshot
            var proposedRect = CGRect(origin: .zero, size: screenshot.image.size)
            guard let windowImage = screenshot.image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
                return (false, "XCTest child-window screenshot did not decode")
            }
            // XCUIWindow.screenshot() is scoped to the unique mGBA game window.
            // CGImage crop coordinates start at the top-left: begin below its 8% title bar.
            let titleBarPixels = CGFloat(windowImage.height) * 0.08
            guard let viewport = windowImage.cropping(to: CGRect(
                x: 0, y: titleBarPixels,
                width: CGFloat(windowImage.width), height: CGFloat(windowImage.height) - titleBarPixels
            )) else {
                return (false, "game viewport crop failed")
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: viewport).perform([request])
            let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            lastText = recognized.joined(separator: " | ")
            let normalized = recognized.joined(separator: " ").uppercased()
            if normalized.contains("CONTINUE") && normalized.contains("NEW GAME") {
                visible = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        if let lastScreenshot {
            let rawAttachment = XCTAttachment(screenshot: lastScreenshot)
            rawAttachment.name = "Aereven mGBA child window launch \(launchIndex) PID \(pid)"
            rawAttachment.lifetime = .keepAlways
            add(rawAttachment)
        }
        let textAttachment = XCTAttachment(string: "PID=\(pid) launch=\(launchIndex) viewportOCR=\(lastText)")
        textAttachment.name = "Aereven viewport OCR launch \(launchIndex) PID \(pid)"
        textAttachment.lifetime = .keepAlways
        add(textAttachment)
        return (visible, lastText)
    }

    private func sha256Hex(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct OracleResult: Decodable {
        let before: Int
        let after: Int
        let inputEdges: Int
        let platform: Int

        enum CodingKeys: String, CodingKey {
            case before, after, platform
            case inputEdges = "input_edges"
        }
    }

    private func runOracle(fixture: String, system: String, label: String, observeOnly: Bool, in prompt: XCUIElement, console: XCUIElement) throws -> OracleResult {
        let fixtureRoot = oracleToolsRoot.appendingPathComponent("playstead-mac/.local/gb-gbc-spike/\(fixture)")
        let oracle = fixtureRoot.appendingPathComponent("\(label)-oracle.json")
        let before = fixtureRoot.appendingPathComponent("screenshots/\(label)-before.png")
        let after = fixtureRoot.appendingPathComponent("screenshots/\(label)-after.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oracle.path), "gb-save-e2e=oracle-label-collision")
        oracleFiles.append(contentsOf: [oracle, before, after])

        let generator = oracleToolsRoot.appendingPathComponent(".planning/spikes/002-persistent-battery-saves/oracle_command.py")
        var arguments = [generator.path, fixture, label]
        if observeOnly { arguments.append("--observe-only") }
        let command = try runPython(arguments: arguments).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, command.utf8.count <= 16_384 else {
            throw NSError(domain: "GBGBCSaveContinuityTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "gb-save-e2e=oracle-command-invalid"])
        }

        prompt.click()
        prompt.typeText(command + "\n")
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let data = try? Data(contentsOf: oracle), data.count <= 4096,
               let result = try? JSONDecoder().decode(OracleResult.self, from: data) {
                return result
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let logText = console.descendants(matching: .textView).allElementsBoundByIndex
            .map(\.readableText).filter { !$0.isEmpty }.joined(separator: " | ")
        let boundedLog = String(logText.suffix(1200))
        throw NSError(domain: "GBGBCSaveContinuityTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "gb-save-e2e=oracle-result-timeout; console_log=\(boundedLog)"])
    }

    private func verifyOraclePixels(fixture: String, system: String, label: String, before: Int, after: Int) throws -> [String: String] {
        let verifier = oracleToolsRoot.appendingPathComponent(".planning/spikes/001-bios-free-gameplay/verify_pixels.py")
        let screenshotRoot = oracleToolsRoot.appendingPathComponent("playstead-mac/.local/gb-gbc-spike/\(fixture)/screenshots")
        let beforeResult = try runPython(arguments: [verifier.path, screenshotRoot.appendingPathComponent("\(label)-before.png").path, system, String(before)])
        let afterResult = try runPython(arguments: [verifier.path, screenshotRoot.appendingPathComponent("\(label)-after.png").path, system, String(after)])
        return ["before": beforeResult.trimmingCharacters(in: .whitespacesAndNewlines),
                "after": afterResult.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private func assertRTCRunningClock(label: String, prompt: XCUIElement, console: XCUIElement) throws -> [String: Int] {
        func sample(_ suffix: String) throws -> (seconds: Int, uptime: TimeInterval) {
            let fixtureRoot = oracleToolsRoot.appendingPathComponent("playstead-mac/.local/gb-gbc-spike/gbc-mbc3-rtc")
            let resultURL = fixtureRoot.appendingPathComponent("\(label)-rtc-\(suffix).json")
            XCTAssertFalse(FileManager.default.fileExists(atPath: resultURL.path), "gb-save-e2e=rtc-label-collision")
            oracleFiles.append(resultURL)
            let command = "emu:write8(0x0000,0x0A); emu:write8(0x4000,0x08); emu:write8(0x6000,0); emu:write8(0x6000,1); local s=emu:read8(0xA000); emu:write8(0x4000,0); local f=assert(io.open(\(String(reflecting: resultURL.path)),\"w\")); f:write(string.format('{\\\"seconds\\\":%d}\\n',s)); f:close(); console:log(\"RTC seconds=\"..s)"
            prompt.click()
            prompt.typeText(command + "\n")
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let data = try? Data(contentsOf: resultURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int],
                   let seconds = json["seconds"], (0...59).contains(seconds) {
                    return (seconds, ProcessInfo.processInfo.systemUptime)
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw NSError(domain: "GBGBCSaveContinuityTests", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "gb-save-e2e=rtc-register-observation-timeout"])
        }
        let start = try sample("start")
        Thread.sleep(forTimeInterval: 2.1)
        let end = try sample("end")
        let elapsed = (end.seconds - start.seconds + 60) % 60
        let wallElapsed = end.uptime - start.uptime
        let wallSeconds = Int(wallElapsed.rounded())
        XCTAssertTrue((1...15).contains(wallSeconds), "gb-save-e2e=rtc-sample-interval-invalid")
        XCTAssertGreaterThanOrEqual(elapsed, 1, "gb-save-e2e=rtc-clock-not-running")
        XCTAssertLessThanOrEqual(abs(elapsed - wallSeconds), 2, "gb-save-e2e=rtc-clock-rate-invalid")
        return ["start_seconds": start.seconds, "end_seconds": end.seconds, "elapsed_seconds_mod_60": elapsed,
                "wall_elapsed_seconds": wallSeconds]
    }

    private func writeRunEvidence(_ evidence: [String: Any]) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["PLAYSTEAD_GB_GBC_SAVE_EVIDENCE_DIRECTORY"],
              (outputPath as NSString).isAbsolutePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: outputPath),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw NSError(domain: "GBGBCSaveContinuityTests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "gb-save-e2e=evidence-directory-unavailable"])
        }
        let fixture = evidence["fixture"] as? String ?? "unknown"
        let evidenceURL = URL(fileURLWithPath: outputPath, isDirectory: true)
            .appendingPathComponent("gb-gbc-save-continuity-\(fixture).json")
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
        try data.write(to: evidenceURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: evidenceURL.path)
    }

    private func waitForUploadedRevision(in app: XCUIApplication) -> Bool {
        guard app.state != .notRunning else { return false }
        app.activate()
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let review = app.buttons["playstead.control.open-readiness"]
            guard review.awaitExistence(timeout: 5) else { return false }
            review.clickWhenHittable()
            let historyAction = app.buttons["playstead.readiness.open-save-history"]
            guard historyAction.awaitExistence(timeout: 5) else { return false }
            historyAction.click()
            let history = app.descendants(matching: .any)["playstead.surface.save-history"]
            guard history.awaitExistence(timeout: 5) else { return false }
            guard app.descendants(matching: .any)["playstead.save-history.session.0.row.0"].exists else {
                return false
            }
            if app.staticTexts["Latest save is on your server."].exists {
                app.buttons["playstead.save-history.done"].click()
                app.buttons["playstead.control.done"].click()
                return true
            }
            let closeHistory = app.buttons["playstead.save-history.done"]
            if closeHistory.exists { closeHistory.click() }
            let closeReadiness = app.buttons["playstead.control.done"]
            if closeReadiness.exists { closeReadiness.click() }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private func runPython(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "GBGBCSaveContinuityTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "gb-save-e2e=oracle-tool-failed"])
        }
        return value
    }
}
