import XCTest
import Darwin
import AppKit
import CryptoKit

private struct RecoveryUITestFixture {
    let romSHA256: String
    let romSizeBytes: Int
    let saveSHA256: String
    let saveSizeBytes: Int

    static func read(from profileRoot: String) -> Self? {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: profileRoot, isDirectory: true)
        let file = root.appendingPathComponent("recovery-fixture.json", isDirectory: false)
        guard
            (try? manager.destinationOfSymbolicLink(atPath: root.path)) == nil,
            let rootAttributes = try? manager.attributesOfItem(atPath: root.path),
            (rootAttributes[.type] as? FileAttributeType) == .typeDirectory,
            (rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
            (rootAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
            (try? manager.destinationOfSymbolicLink(atPath: file.path)) == nil,
            let attributes = try? manager.attributesOfItem(atPath: file.path),
            (attributes[.type] as? FileAttributeType) == .typeRegular,
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            let length = (attributes[.size] as? NSNumber)?.intValue,
            length > 0, length <= 4096,
            let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == Set([
                "schema", "fixture_id", "system_id", "rom_sha256", "rom_size_bytes",
                "save_sha256", "save_size_bytes"
            ]),
            object["schema"] as? String == "playstead.recovery-ui-fixture.v1",
            object["fixture_id"] as? String == "aerevenadvance",
            object["system_id"] as? String == "gba",
            let romSHA256 = object["rom_sha256"] as? String,
            romSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
            let romSize = object["rom_size_bytes"] as? Int, romSize > 0,
            let saveSHA256 = object["save_sha256"] as? String,
            saveSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
            let saveSize = object["save_size_bytes"] as? Int, saveSize == 32_768
        else { return nil }
        return Self(romSHA256: romSHA256, romSizeBytes: romSize, saveSHA256: saveSHA256, saveSizeBytes: saveSize)
    }
}

/// D-07's automated receipt proves recovery data and lifecycle evidence, but
/// intentionally cannot turn that into a claim about real in-game continuation.
/// The restore handoff deliberately contains no owner credential, so the real
/// app can request pairing but cannot certify approval, sync, or play here.
final class RecoveryKnownPlayableTests: XCTestCase {
    func testRecoveryHarnessRefusesSyntheticFixtureWithoutAnIsolatedTarget() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/ci/prove-recovery-known-playable.sh", "--fixture", "--no-human-observation"]
        // XCTest launches its runner from DerivedData, not necessarily the
        // project root. The negative harness test must exercise the checked-in
        // driver rather than accidentally asking bash for a missing relative
        // file.
        process.currentDirectoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
        let output = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(output.contains("no real isolated restore target was supplied"))
        XCTAssertTrue(output.contains("docker compose -p <restore-identity>"))
    }

    func testPreparedRecoveryTargetLaunchesTheCleanMacAppAndRequestsPairing() throws {
        let environment = ProcessInfo.processInfo.environment
        let reportDestination = environment["PLAYSTEAD_RECOVERY_UI_REPORT"]
        let runID = UUID().uuidString.lowercased()
        var stages = [
            "clean_launch": "blocked",
            "local_ca_pairing_request": "not_run",
            "owner_approval": "not_run",
            "cursor_convergence": "not_run",
            "cache_preflight": "not_run",
            "persistent_save_transport_restore": "not_run",
            "controlled_exit": "not_run",
            "relaunch": "not_run"
        ]
        defer {
            if let reportDestination {
                let outcome = stages.values.allSatisfy { $0 == "passed" } ? "passed" : "blocked"
                let report: [String: Any] = [
                    "schema": "playstead.recovery-mac-ui.v2",
                    "run_id": runID,
                    "lane": "restored_target",
                    "stages": stages,
                    "outcome": outcome
                ]
                do {
                    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                    try data.write(to: URL(fileURLWithPath: reportDestination), options: [.atomic])
                } catch {
                    XCTFail("recovery-ui-report-write-failed")
                }
            }
        }

        let profileRootValue = environment["PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT"]
        let reportPathValue = reportDestination
        let trustAnchorPathValue = environment["PLAYSTEAD_RECOVERY_UI_TRUST_ANCHOR"]
        let appPathValue = environment["PLAYSTEAD_RECOVERY_UI_APP_PATH"]
        let targetURLValue: String? = {
            guard let profileRootValue else { return nil }
            let targetFile = URL(fileURLWithPath: profileRootValue)
                .appendingPathComponent("recovery-target.url", isDirectory: false)
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: targetFile.path)) == nil,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: targetFile.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
                  permissions & 0o777 == 0o600,
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  size > 0, size <= 4096,
                  let contents = try? String(contentsOf: targetFile, encoding: .utf8)
            else { return nil }
            let components = URLComponents(string: contents)
            guard components?.scheme?.lowercased() == "https",
                  components?.host?.lowercased() == "localhost",
                  let port = components?.port, (1...65535).contains(port),
                  components?.user == nil, components?.password == nil,
                  components?.query == nil, components?.fragment == nil,
                  components?.path.isEmpty == true || components?.path == "/"
            else { return nil }
            return contents
        }()
        var preflightFailures: [String] = []
        if targetURLValue == nil { preflightFailures.append("target_url_file_missing_invalid_or_non_private") }
        if profileRootValue == nil { preflightFailures.append("profile_root_missing") }
        if reportPathValue == nil { preflightFailures.append("report_path_missing") }
        if let trustAnchorPathValue {
            if !FileManager.default.fileExists(atPath: trustAnchorPathValue) {
                preflightFailures.append("trust_anchor_unavailable")
            }
        } else {
            preflightFailures.append("trust_anchor_missing")
        }
        if let appPathValue {
            let appURL = URL(fileURLWithPath: appPathValue)
            if !FileManager.default.fileExists(atPath: appURL.path)
                || Bundle(url: appURL)?.bundleIdentifier != "dev.playstead.mac" {
                preflightFailures.append("built_app_unavailable")
            }
        } else {
            preflightFailures.append("built_app_missing")
        }
        if let profileRootValue, !FileManager.default.fileExists(atPath: profileRootValue) {
            preflightFailures.append("profile_root_unavailable")
        }
        guard
            targetURLValue != nil,
            let profileRoot = profileRootValue,
            reportPathValue != nil,
            let trustAnchorPath = trustAnchorPathValue,
            let appPath = appPathValue,
            FileManager.default.fileExists(atPath: trustAnchorPath),
            Bundle(url: URL(fileURLWithPath: appPath))?.bundleIdentifier == "dev.playstead.mac",
            FileManager.default.fileExists(atPath: profileRoot)
        else {
            let checks = preflightFailures.isEmpty ? "unclassified" : preflightFailures.joined(separator: ",")
            return XCTFail("recovery-ui-preflight=missing-or-invalid-prepared-target checks=\(checks)")
        }

        let keychainURL = URL(fileURLWithPath: profileRoot)
            .appendingPathComponent("recovery-ui.keychain-db")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: keychainURL.path),
            "the app, not its launcher, must create the fresh scoped Keychain"
        )
        defer { try? FileManager.default.removeItem(at: keychainURL) }

        // Use Xcode's configured target application. The coordinator verifies
        // UITargetAppPath resolves to this run's exact signed build product;
        // selecting by bundle identifier can resolve another installed copy.
        let launched = XCUIApplication()
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_ROOT"] = profileRoot
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN"] = keychainURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"] = "dev.playstead.mac.live.\(UUID().uuidString.lowercased())"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_RECOVERY_CA_PATH"] = trustAnchorPath
        stages["clean_launch"] = "blocked"
        // Register cleanup before launch: XCTest can fail while acquiring the
        // launched app's process ID even though Launch Services started it.
        defer {
            if launched.state != .notRunning {
                launched.terminate()
            }
        }
        launched.launch()

        guard FileManager.default.fileExists(atPath: keychainURL.path) else {
            XCTFail("recovery-ui-keychain-not-materialized")
            return
        }
        guard launched.descendants(matching: .any)["playstead.surface.library"]
            .awaitExistence(timeout: 20) else {
            XCTFail("recovery-ui-library-surface-unavailable state=\(launched.state)")
            return
        }
        // Launch Services may finish the window handoff behind another app.
        // Establish foreground ownership before asking XCTest to hit toolbar
        // segments; mere accessibility existence does not establish that.
        launched.activate()
        guard launched.wait(for: .runningForeground, timeout: 10) else {
            return XCTFail("recovery-ui-library-not-foreground")
        }
        // SwiftUI's segmented Picker can expose a segment as a non-button
        // accessibility element on macOS. Resolve the stable identifier
        // independently of the framework-selected element type.
        let showList = launched.descendants(matching: .any)["playstead.control.show-list"]
        guard showList.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-list-control-unavailable state=\(launched.state)")
            return
        }
        stages["clean_launch"] = "passed"
        guard awaitHittable(showList) else {
            XCTFail("recovery-ui-list-control-not-hittable")
            return
        }
        showList.click()
        let pairing = launched.buttons["playstead.control.open-pairing"]
        stages["local_ca_pairing_request"] = "blocked"
        guard pairing.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-pairing-control-unavailable")
            return
        }
        guard awaitHittable(pairing) else {
            XCTFail("recovery-ui-pairing-control-not-hittable")
            return
        }
        pairing.click()

        // Drive the same explicit CA chooser and certificate-validation path
        // a person uses. The UI_TESTING build reads this mode-600 retained CA
        // candidate because headless XCTest cannot reliably drive NSOpenPanel.
        let chooseCA = launched.buttons["playstead.control.choose-recovery-ca"]
        guard chooseCA.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-ca-control-unavailable")
            return
        }
        guard awaitHittable(chooseCA) else {
            XCTFail("recovery-ui-ca-control-not-hittable")
            return
        }
        chooseCA.click()
        let caCandidateStatus = launched.descendants(matching: .any)["playstead.readout.recovery-ca-candidate-status"]
        guard caCandidateStatus.awaitExistence(timeout: 5) else {
            XCTFail("recovery-ui-ca-candidate-status-unavailable")
            return
        }
        let caSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "selected"),
            object: caCandidateStatus
        )
        guard XCTWaiter.wait(for: [caSelected], timeout: 5) == .completed else {
            let safeStatuses: Set<String> = [
                "idle", "candidate_supplied", "candidate_unavailable", "candidate_loaded",
                "candidate_invalid", "native_picker", "selected"
            ]
            let observed = [caCandidateStatus.value as? String, caCandidateStatus.readableText]
                .compactMap { $0 }
            let status = observed.first(where: { safeStatuses.contains($0) }) ?? "unknown"
            XCTFail("recovery-ui-ca-candidate-status-\(status)")
            return
        }
        let recoveryCARejected = launched.descendants(matching: .any)["playstead.readout.pairing-ca-error"]
        if recoveryCARejected.awaitExistence(timeout: 2) {
            XCTFail("recovery-ui-ca-test-candidate-rejected")
            return
        }
        guard launched.descendants(matching: .any)["playstead.readout.pairing-ca-selection"]
            .awaitExistence(timeout: 5) else {
            XCTFail("recovery-ui-ca-selection-not-confirmed")
            return
        }

        let serverURL = launched.textFields["playstead.control.pairing-server-url"]
        guard serverURL.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-pairing-url-control-unavailable")
            return
        }
        let targetPrefill = launched.descendants(matching: .any)["playstead.readout.recovery-target-prefill"]
        guard targetPrefill.awaitExistence(timeout: 5) else {
            XCTFail("recovery-ui-pairing-target-prefill-unavailable")
            return
        }
        let prefillStatus = (targetPrefill.value as? String ?? targetPrefill.readableText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowedPrefillStatuses: Set<String> = ["valid", "missing", "malformed", "scheme", "host", "port", "userinfo", "path", "query", "fragment"]
        let status = allowedPrefillStatuses.first(where: { prefillStatus.contains($0) }) ?? "other"
        guard status == "valid" else {
            XCTFail("recovery-ui-pairing-target-prefill-\(status)")
            return
        }
        let request = launched.buttons["playstead.control.request-pairing"]
        guard request.awaitExistence(timeout: 5) else {
            XCTFail("recovery-ui-pairing-request-control-unavailable")
            return
        }
        let requestEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: request
        )
        guard XCTWaiter.wait(for: [requestEnabled], timeout: 5) == .completed else {
            XCTFail("recovery-ui-pairing-target-prefill-not-applied")
            return
        }
        guard awaitHittable(request) else {
            XCTFail("recovery-ui-pairing-request-control-not-hittable")
            return
        }
        request.click()
        let pairingDisplayCode = launched.descendants(matching: .any)["playstead.control.pairing-display-code"]
        guard pairingDisplayCode.awaitExistence(timeout: 20) else {
            let pairingError = launched.descendants(matching: .any)["playstead.readout.pairing-error"]
            if pairingError.awaitExistence(timeout: 2) {
                let permittedCategories: Set<String> = [
                    "expired", "already_redeemed", "not_approved", "slow_down", "not_found",
                    "denied", "invalid_response", "keychain_write_failed", "transport",
                    "insecure_address", "certificate_pin", "certificate_trust"
                ]
                let value = pairingError.value as? String
                let category = value.flatMap { permittedCategories.contains($0) ? $0 : nil } ?? "other"
                XCTFail("recovery-ui-pairing-request-failed-\(category)")
            } else {
                XCTFail("recovery-ui-pairing-request-not-confirmed")
            }
            return
        }
        stages["local_ca_pairing_request"] = "passed"

        // Explicit disposable-owner automation receives only the code actually
        // displayed by this clean app. The helper authenticates the local test
        // owner and approves the exact fresh request through production logic.
        if environment["PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL"] == "1" {
            guard writePrivateApprovalRequest(from: pairingDisplayCode, profileRoot: profileRoot) else {
                stages["owner_approval"] = "blocked"
                XCTFail("recovery-ui-test-owner-request-write-failed")
                return
            }
        }

        // A display code proves only that the request was created. The real
        // PairingCoordinator reaches this success surface only after local
        // owner approval, polling, redemption, Keychain persistence, and CA
        // pinning have completed.
        stages["owner_approval"] = "blocked"
        let pairingSuccess = launched.descendants(matching: .any)["playstead.control.pairing-success"]
        let ownerApprovalCompleted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: pairingSuccess
        )
        guard XCTWaiter.wait(for: [ownerApprovalCompleted], timeout: 120) == .completed else {
            XCTFail("recovery-ui-owner-approval-timeout")
            return
        }
        stages["owner_approval"] = "passed"

        stages["cursor_convergence"] = "blocked"
        let cursorStatus = launched.descendants(matching: .any)["playstead.readout.recovery-cursor-status"]
        let cursorConverged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "synced"),
            object: cursorStatus
        )
        guard XCTWaiter.wait(for: [cursorConverged], timeout: 60) == .completed else {
            XCTFail("recovery-ui-cursor-convergence-timeout")
            return
        }
        stages["cursor_convergence"] = "passed"

        guard let fixture = RecoveryUITestFixture.read(from: profileRoot) else {
            XCTFail("recovery-ui-fixture-registry-invalid")
            return
        }
        let fixtureMatchStatus = launched.descendants(matching: .any)["playstead.readout.recovery-fixture-match-status"]
        let fixtureMatchExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR value == %@", "matched", "game_missing"),
            object: fixtureMatchStatus
        )
        guard XCTWaiter.wait(for: [fixtureMatchExpectation], timeout: 20) == .completed,
              (fixtureMatchStatus.value as? String) == "matched" else {
            let safeStatuses: Set<String> = [
                "sync_pending", "registry_missing", "registry_invalid", "game_missing", "game_ambiguous"
            ]
            let observed = fixtureMatchStatus.value as? String ?? "unreported"
            let category = safeStatuses.contains(observed) ? observed : "unreported"
            XCTFail("recovery-ui-fixture-match-\(category)")
            return
        }
        let fixtureAssetSetID = launched.descendants(matching: .any)[
            "playstead.readout.recovery-fixture-asset-set-id"
        ].value as? String
        guard let fixtureAssetSetID,
              fixtureAssetSetID.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil else {
            XCTFail("recovery-ui-fixture-asset-identity-unavailable")
            return
        }

        stages["cache_preflight"] = "blocked"
        // Install the pinned emulator through the same Settings UI and
        // AppEnvironment production installer a user uses. This keeps the
        // clean profile honest: readiness must observe a digest-verified
        // install, not a copied executable or injected adapter state.
        guard installPinnedAdapterThroughSettings(in: launched) else {
            return XCTFail("recovery-ui-adapter-install-failed")
        }
        guard downloadDesignatedFixture(in: launched, assetSetID: fixtureAssetSetID) else {
            return XCTFail("recovery-ui-fixture-download-failed")
        }

        let cachePreflightStatus = launched.descendants(matching: .any)["playstead.readout.recovery-cache-preflight-status"]
        let cachePreflightFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR value == %@", "ready", "blocked"),
            object: cachePreflightStatus
        )
        guard XCTWaiter.wait(for: [cachePreflightFinished], timeout: 30) == .completed else {
            XCTFail("recovery-ui-cache-preflight-timeout")
            return
        }
        guard (cachePreflightStatus.value as? String) == "ready" else {
            let blockerReadout = launched.descendants(matching: .any)["playstead.readout.recovery-cache-preflight-blockers"]
            let allowed = Set([
                "empty_catalogue", "game_assets", "cache_verification", "emulator",
                "bios", "controller_and_input", "save_directory", "save_state"
            ])
            let observed = (blockerReadout.value as? String ?? "").split(separator: ",").map(String.init)
            let blockers = observed.filter { allowed.contains($0) }
            let category = blockers.isEmpty ? "unreported" : blockers.joined(separator: ",")
            XCTFail("recovery-ui-cache-preflight-blocked blockers=\(category)")
            return
        }
        stages["cache_preflight"] = "passed"

        stages["persistent_save_transport_restore"] = "blocked"
        let saveStatus = launched.descendants(matching: .any)["playstead.readout.recovery-fixture-save-status"]
        guard (saveStatus.value as? String) == "prefetched" else {
            let allowedSaveStates: Set<String> = [
                "registry_unavailable", "game_unmatched", "line_missing", "revision_missing",
                "revision_not_uploaded", "prefetch_missing_or_mismatched"
            ]
            let observed = saveStatus.value as? String ?? "unreported"
            let category = allowedSaveStates.contains(observed) ? observed : "unreported"
            XCTFail("recovery-ui-fixture-save-\(category)")
            return
        }
        guard launchMaterializeAndQuitFixture(
            in: launched,
            profileRoot: profileRoot,
            assetSetID: fixtureAssetSetID,
            fixture: fixture
        ) else {
            return XCTFail("recovery-ui-fixture-launch-failed")
        }
        stages["persistent_save_transport_restore"] = "passed"

        stages["controlled_exit"] = "blocked"
        launched.terminate()
        guard launched.state == .notRunning else {
            XCTFail("recovery-ui-controlled-exit-not-confirmed")
            return
        }
        stages["controlled_exit"] = "passed"

        stages["relaunch"] = "blocked"
        launched.launch()
        guard launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20) else {
            XCTFail("recovery-ui-relaunch-failed")
            return
        }
        let relaunchedCursor = launched.descendants(matching: .any)["playstead.readout.recovery-cursor-status"]
        guard openPairingFromMenu(in: launched) else {
            return XCTFail("recovery-ui-pairing-control-unavailable")
        }
        let relaunchedSync = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "synced"),
            object: relaunchedCursor
        )
        guard XCTWaiter.wait(for: [relaunchedSync], timeout: 60) == .completed else {
            XCTFail("recovery-ui-relaunch-sync-timeout")
            return
        }
        let relaunchedFixtureMatch = launched.descendants(matching: .any)[
            "playstead.readout.recovery-fixture-match-status"
        ]
        let relaunchedFixtureReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "matched"),
            object: relaunchedFixtureMatch
        )
        guard XCTWaiter.wait(for: [relaunchedFixtureReady], timeout: 20) == .completed,
              (launched.descendants(matching: .any)["playstead.readout.recovery-fixture-asset-set-id"].value as? String)
                == fixtureAssetSetID,
              (launched.descendants(matching: .any)["playstead.readout.recovery-fixture-materialization-status"].value as? String)
                == "materialized" else {
            XCTFail("recovery-ui-relaunch-fixture-state-not-restored")
            return
        }
        stages["relaunch"] = "passed"
    }

    private func downloadDesignatedFixture(in app: XCUIApplication, assetSetID: String) -> Bool {
        let done = app.buttons["playstead.control.done"]
        guard done.awaitExistence(timeout: 10), awaitHittable(done) else {
            XCTFail("recovery-ui-fixture-pairing-dismiss-unavailable")
            return false
        }
        done.click()

        guard selectAllGames(in: app, assetSetID: assetSetID) else { return false }

        let download = app.buttons["playstead.game.\(assetSetID).download"]
        let play = app.buttons["playstead.game.\(assetSetID).play"]
        if download.awaitExistence(timeout: 10) {
            guard awaitHittable(download) else {
                XCTFail("recovery-ui-fixture-download-not-hittable")
                return false
            }
            download.click()
            switch waitForDesignatedFixturePlay(in: app, assetSetID: assetSetID, play: play, timeout: 240) {
            case .playReady:
                break
            case .retry:
                XCTFail("recovery-ui-fixture-download-retry")
                return false
            case .timeout:
                XCTFail("recovery-ui-fixture-download-timeout")
                return false
            }
        } else if !play.awaitExistence(timeout: 10) {
            XCTFail("recovery-ui-fixture-action-unavailable")
            return false
        }

        guard openPairingFromMenu(in: app) else { return false }
        let cacheStatus = app.descendants(matching: .any)["playstead.readout.recovery-cache-preflight-status"]
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR value == %@", "ready", "blocked"),
            object: cacheStatus
        )
        guard XCTWaiter.wait(for: [settled], timeout: 30) == .completed else {
            XCTFail("recovery-ui-fixture-cache-status-timeout")
            return false
        }
        return true
    }

    private func waitForDesignatedFixturePlay(
        in app: XCUIApplication,
        assetSetID: String,
        play: XCUIElement,
        timeout: TimeInterval
    ) -> FixtureDownloadWaitResult {
        let retry = app.buttons["playstead.game.\(assetSetID).retry"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if play.exists { return .playReady }
            if retry.exists { return .retry }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return .timeout
    }

    private func launchMaterializeAndQuitFixture(
        in app: XCUIApplication,
        profileRoot: String,
        assetSetID: String,
        fixture: RecoveryUITestFixture
    ) -> Bool {
        let done = app.buttons["playstead.control.done"]
        guard done.awaitExistence(timeout: 10), awaitHittable(done) else {
            XCTFail("recovery-ui-fixture-pairing-dismiss-unavailable")
            return false
        }
        done.click()

        guard selectAllGames(in: app, assetSetID: assetSetID) else { return false }

        let play = app.buttons["playstead.game.\(assetSetID).play"]
        guard play.awaitExistence(timeout: 10), awaitHittable(play) else {
            XCTFail("recovery-ui-fixture-play-unavailable")
            return false
        }
        play.click()

        let processReadout = app.descendants(matching: .any)[
            "playstead.test.recovery-emulator-process-id.\(assetSetID)"
        ]
        let processStarted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "idle"),
            object: processReadout
        )
        guard XCTWaiter.wait(for: [processStarted], timeout: 30) == .completed,
              let processIDValue = processReadout.value as? String,
              let processID = Int32(processIDValue), processID > 1 else {
            XCTFail("recovery-ui-fixture-emulator-start-unconfirmed")
            return false
        }

        // Revalidate the current process executable immediately before the
        // OS quit request. The PID came from AdapterHost's attestation of its
        // exact verified Process; here it must still resolve under this fresh
        // profile's emulator root and to the pinned executable name.
        var processPathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let processPathLength = processPathBuffer.withUnsafeMutableBufferPointer { buffer in
            proc_pidpath(pid_t(processID), buffer.baseAddress, UInt32(buffer.count))
        }
        guard processPathLength > 0 else {
            XCTFail("recovery-ui-fixture-emulator-process-unreadable")
            return false
        }
        let processPath = String(cString: processPathBuffer)
        let emulatorRoot = URL(fileURLWithPath: profileRoot, isDirectory: true)
            .appendingPathComponent("emulators", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let processURL = URL(fileURLWithPath: processPath)
            .resolvingSymlinksInPath().standardizedFileURL
        guard processURL.path.hasPrefix(emulatorRoot.hasSuffix("/") ? emulatorRoot : emulatorRoot + "/"),
              processURL.lastPathComponent == "mGBA" else {
            XCTFail("recovery-ui-fixture-emulator-process-identity-mismatch")
            return false
        }
        var observedNormalExit = false
        defer {
            if !observedNormalExit,
               currentProcessPath(pid: pid_t(processID)) == processPath,
               let ownedApplication = NSRunningApplication(processIdentifier: pid_t(processID)),
               !ownedApplication.isTerminated,
               ownedApplication.terminate() {
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline && !ownedApplication.isTerminated {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        var launchedEmulator: NSRunningApplication?
        let applicationReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard self.currentProcessPath(pid: pid_t(processID)) == processPath,
                      let application = NSRunningApplication(processIdentifier: pid_t(processID)),
                      application.isFinishedLaunching else { return false }
                launchedEmulator = application
                return true
            },
            object: nil
        )
        guard XCTWaiter.wait(for: [applicationReady], timeout: 20) == .completed,
              let emulatorApplication = launchedEmulator else {
            XCTFail("recovery-ui-fixture-emulator-application-unavailable")
            return false
        }

        guard waitForFixtureSaveMaterialization(
            profileRoot: profileRoot,
            assetSetID: assetSetID,
            fixture: fixture,
            timeout: 20
        ) else {
            XCTFail("recovery-ui-fixture-save-materialization-unconfirmed")
            return false
        }

        guard emulatorApplication.terminate() else {
            XCTFail("recovery-ui-fixture-normal-quit-rejected")
            return false
        }
        let exited = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isTerminated == true"),
            object: emulatorApplication
        )
        guard XCTWaiter.wait(for: [exited], timeout: 20) == .completed else {
            XCTFail("recovery-ui-fixture-normal-quit-timeout")
            return false
        }
        observedNormalExit = true

        let processExited = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "exited"),
            object: processReadout
        )
        guard XCTWaiter.wait(for: [processExited], timeout: 20) == .completed else {
            XCTFail("recovery-ui-fixture-host-exit-unconfirmed")
            return false
        }
        let exitCategory = app.descendants(matching: .any)[
            "playstead.test.recovery-emulator-exit-category.\(assetSetID)"
        ]
        guard (exitCategory.value as? String) == "clean",
              app.descendants(matching: .any)["playstead.game.\(assetSetID).last-exit"].exists else {
            XCTFail("recovery-ui-fixture-emulator-exit-not-clean")
            return false
        }

        guard openPairingFromMenu(in: app) else { return false }
        let materialization = app.descendants(matching: .any)[
            "playstead.readout.recovery-fixture-materialization-status"
        ]
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR value == %@", "materialized", "materialization_unconfirmed"),
            object: materialization
        )
        guard XCTWaiter.wait(for: [restored], timeout: 20) == .completed,
              (materialization.value as? String) == "materialized" else {
            let safeStates: Set<String> = [
                "not_materialized", "save_path_unavailable", "materialization_unconfirmed"
            ]
            let observed = materialization.value as? String ?? "unreported"
            let category = safeStates.contains(observed) ? observed : "unreported"
            XCTFail("recovery-ui-fixture-save-restore-\(category)")
            return false
        }
        return true
    }

    private func waitForFixtureSaveMaterialization(
        profileRoot: String,
        assetSetID: String,
        fixture: RecoveryUITestFixture,
        timeout: TimeInterval
    ) -> Bool {
        let manager = FileManager.default
        let saveDirectory = URL(fileURLWithPath: profileRoot, isDirectory: true)
            .appendingPathComponent("saves", isDirectory: true)
            .appendingPathComponent(assetSetID, isDirectory: true)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard
                (try? manager.destinationOfSymbolicLink(atPath: saveDirectory.path)) == nil,
                let directoryAttributes = try? manager.attributesOfItem(atPath: saveDirectory.path),
                (directoryAttributes[.type] as? FileAttributeType) == .typeDirectory,
                let children = try? manager.contentsOfDirectory(at: saveDirectory, includingPropertiesForKeys: nil)
            else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            for child in children where child.pathExtension.lowercased() == "sav" {
                guard
                    (try? manager.destinationOfSymbolicLink(atPath: child.path)) == nil,
                    let attributes = try? manager.attributesOfItem(atPath: child.path),
                    (attributes[.type] as? FileAttributeType) == .typeRegular,
                    (attributes[.size] as? NSNumber)?.intValue == fixture.saveSizeBytes,
                    let data = try? Data(contentsOf: child, options: [.mappedIfSafe]),
                    data.count == fixture.saveSizeBytes
                else { continue }
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if digest == fixture.saveSHA256 { return true }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private func selectAllGames(in app: XCUIApplication, assetSetID: String) -> Bool {
        let download = app.buttons["playstead.game.\(assetSetID).download"]
        let play = app.buttons["playstead.game.\(assetSetID).play"]
        // Returning from Pairing can leave the intended library row visible.
        // Avoid resolving a duplicate navigation-title label in that state.
        if download.exists || play.exists { return true }
        let sidebar = app.descendants(matching: .any)["playstead.surface.sidebar"]
        let allGames = sidebar.staticTexts["All Games"]
        guard allGames.awaitExistence(timeout: 10), awaitHittable(allGames) else {
            XCTFail("recovery-ui-fixture-library-navigation-unavailable")
            return false
        }
        allGames.click()
        let exactFixtureAction = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in download.exists || play.exists },
            object: nil
        )
        guard XCTWaiter.wait(for: [exactFixtureAction], timeout: 10) == .completed else {
            XCTFail("recovery-ui-fixture-library-surface-unavailable")
            return false
        }
        return true
    }

    private func currentProcessPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(pid, pointer.baseAddress, UInt32(pointer.count))
        }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private func openPairingFromMenu(in app: XCUIApplication) -> Bool {
        let pairingMenu = app.menuBars.menuBarItems["Pairing"]
        guard pairingMenu.awaitExistence(timeout: 10), awaitHittable(pairingMenu) else {
            XCTFail("recovery-ui-pairing-menu-unavailable")
            return false
        }
        pairingMenu.click()
        let pairCommand = app.menuItems["Pair with Server…"]
        guard pairCommand.awaitExistence(timeout: 5), awaitHittable(pairCommand) else {
            XCTFail("recovery-ui-pairing-command-unavailable")
            return false
        }
        pairCommand.click()
        let cacheReadout = app.descendants(matching: .any)["playstead.readout.recovery-cache-preflight-status"]
        guard cacheReadout.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-cache-readout-unavailable")
            return false
        }
        return true
    }

    private func installPinnedAdapterThroughSettings(in app: XCUIApplication) -> Bool {
        let done = app.buttons["playstead.control.done"]
        guard done.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-adapter-pairing-dismiss-unavailable")
            return false
        }
        guard awaitHittable(done) else {
            XCTFail("recovery-ui-adapter-pairing-dismiss-not-hittable")
            return false
        }
        done.click()

        let settingsDestination = app.staticTexts["Settings"]
        guard settingsDestination.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-adapter-settings-unavailable")
            return false
        }
        guard awaitHittable(settingsDestination) else {
            XCTFail("recovery-ui-adapter-settings-not-hittable")
            return false
        }
        settingsDestination.click()

        let settingsSurface = app.descendants(matching: .any)["playstead.settings"]
        guard settingsSurface.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-adapter-settings-surface-unavailable")
            return false
        }
        let emulatorPane = settingsSurface.descendants(matching: .any)["Emulator"]
        guard emulatorPane.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-adapter-pane-unavailable")
            return false
        }
        guard awaitHittable(emulatorPane) else {
            XCTFail("recovery-ui-adapter-pane-not-hittable")
            return false
        }
        emulatorPane.click()

        let install = app.buttons["playstead.control.install-adapter"]
        guard install.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-adapter-install-control-unavailable")
            return false
        }
        let installStatus = app.descendants(matching: .any)["playstead.readout.recovery-adapter-install-status"]
        guard installStatus.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-adapter-install-status-unavailable")
            return false
        }
        if (installStatus.value as? String) != "verified" {
            guard ["Install the pinned adapter", "Reinstall the pinned adapter"].contains(install.readableText),
                  awaitHittable(install) else {
                XCTFail("recovery-ui-adapter-install-control-not-ready")
                return false
            }
            install.click()

            let installed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@ OR value == %@", "verified", "failed"),
                object: installStatus
            )
            guard XCTWaiter.wait(for: [installed], timeout: 180) == .completed else {
                XCTFail("recovery-ui-adapter-install-timeout")
                return false
            }
            guard (installStatus.value as? String) == "verified" else {
                XCTFail("recovery-ui-adapter-install-failed")
                return false
            }
        }

        // The cache readout belongs to the existing Pairing surface. Reopen
        // that production route through the app's Pairing menu after
        // dismissing the sheet for Settings navigation.
        let pairingMenu = app.menuBars.menuBarItems["Pairing"]
        guard pairingMenu.awaitExistence(timeout: 10), awaitHittable(pairingMenu) else {
            XCTFail("recovery-ui-adapter-pairing-menu-unavailable")
            return false
        }
        pairingMenu.click()
        let pairCommand = app.menuItems["Pair with Server…"]
        guard pairCommand.awaitExistence(timeout: 5), awaitHittable(pairCommand) else {
            XCTFail("recovery-ui-adapter-pairing-command-unavailable")
            return false
        }
        pairCommand.click()
        let cacheReadout = app.descendants(matching: .any)["playstead.readout.recovery-cache-preflight-status"]
        guard cacheReadout.awaitExistence(timeout: 10) else {
            XCTFail("recovery-ui-adapter-cache-readout-unavailable")
            return false
        }
        return true
    }

    private func writePrivateApprovalRequest(from display: XCUIElement, profileRoot: String) -> Bool {
        let candidates = [display.value as? String, display.readableText].compactMap { $0 }
        guard let code = candidates.first(where: {
            $0.range(of: "^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$", options: .regularExpression) != nil
        }) else { return false }
        let root = URL(fileURLWithPath: profileRoot, isDirectory: true)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: root.path),
              (attributes[.type] as? FileAttributeType) == .typeDirectory,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: root.path)) == nil
        else { return false }
        let destination = root.appendingPathComponent("recovery-approval-request.json")
        let temporary = root.appendingPathComponent(".recovery-approval-\(UUID().uuidString).tmp")
        let record = [
            "schema": "playstead.recovery-test-approval.v1",
            "display_code": code,
            "requested_at": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
            return false
        }
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close(); try? FileManager.default.removeItem(at: temporary) }
        do {
            try file.write(contentsOf: data)
            try file.synchronize()
            try file.close()
            return Darwin.link(temporary.path, destination.path) == 0
        } catch {
            return false
        }
    }

    private func awaitHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [hittable], timeout: timeout) == .completed
    }
}

private enum FixtureDownloadWaitResult {
    case playReady
    case retry
    case timeout
}
