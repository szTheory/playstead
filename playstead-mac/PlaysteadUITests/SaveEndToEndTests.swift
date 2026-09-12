import XCTest
import Security
import CryptoKit

/// Plan 04-04 task 3: the tracer's real end-to-end check. Pairs against
/// the live test server (following `LiveServerSnapshotTests`' fixture and
/// preflight discipline -- including resolving the runner's runtime config
/// before the inherited environment, which this class originally omitted),
/// writes one 32,768-byte artifact into
/// a synthetic game's save directory, lets capture and the upload lane
/// run in-process inside the paired app (via `UITestBootstrap`'s save
/// e2e hook -- a UI test target cannot `@testable import Playstead`, so
/// this is the accessible surface, mirroring how `first-sentinel.json`/
/// `second-sentinel.json` are read rather than a bespoke UI surface
/// built only to be inspected by this test), then asserts the revision
/// comes back with the same `blob_sha256`/`size_bytes` the Mac computed
/// at capture -- one test proving the whole seam, not per-layer units.
///
/// The genuinely hardware-dependent half (a real mGBA process, a real
/// commercial game, "Continue the game" actually working) is
/// out of reach for automation and is carried by the named blocked
/// checkpoint **CP7-SAVE-C** (plan 04-12) instead — this test proves the
/// *file* half only, per D-68.
@MainActor
final class SaveEndToEndTests: XCTestCase {
    private var app: XCUIApplication?
    private var keychain: SecKeychain?
    private var root: URL?
    private var fixtureEnvironment: [String: String]?

    override func tearDownWithError() throws {
        app?.terminate()
        if let keychain { SecKeychainDelete(keychain) }
        if let root { try? FileManager.default.removeItem(at: root) }
        fixtureEnvironment = nil
    }

    func testOneSaveRoundTripsCaptureUploadAndJournalReturn() throws {
        guard fixtureEnvironmentIsReady() else {
            // Never a bare return: a preflight failure must be a visible failure,
            // not a silently green test (see fail-open-test-guard-test.sh).
            return XCTFail("live fixture preflight failed")
        }

        let runRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-save-e2e-\(UUID().uuidString.lowercased())", isDirectory: true)
        root = runRoot
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let keychainURL = runRoot.appendingPathComponent("scoped.keychain-db")
        let password = Data("synthetic-\(UUID().uuidString)".utf8)
        var created: SecKeychain?
        let status = keychainURL.path.withCString { path in
            password.withUnsafeBytes { bytes in
                SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created)
            }
        }
        XCTAssertEqual(status, errSecSuccess)
        keychain = created

        guard try runFixture("prepare", root: runRoot) else {
            return XCTFail("live fixture stage 'prepare' failed")
        }
        let handoff = runRoot.appendingPathComponent("credential-handoff.json")
        XCTAssertEqual(try permissions(of: handoff), 0o600)

        // The 32,768-byte artifact this test's capture pass will read —
        // written before launch so `UITestBootstrap`'s ownership-checked
        // `containedURL` finds it present.
        let artifactURL = runRoot.appendingPathComponent("synthetic.sav")
        let artifactBytes = Data((0..<32_768).map { UInt8(truncatingIfNeeded: $0) })
        try artifactBytes.write(to: artifactURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: artifactURL.path)
        let expectedSHA256 = sha256Hex(of: artifactBytes)

        let resultURL = runRoot.appendingPathComponent("save-e2e-result.json")
        let contentKey = String(repeating: "e", count: 64)

        let launched = XCUIApplication()
        app = launched
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_ROOT"] = runRoot.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF"] = handoff.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN"] = keychainURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"] = "dev.playstead.mac.live.\(UUID().uuidString.lowercased())"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_ARTIFACT_PATH"] = artifactURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_CONTENT_KEY"] = contentKey
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_RESULT_PATH"] = resultURL.path
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].waitForExistence(timeout: 20))

        // The harness writes exactly one of these two files. Polling for
        // both means a failure is reported by its cause on the run it
        // happens, instead of as an indistinguishable timeout -- hosted
        // run 34281587417 timed out here and said nothing about why.
        let errorURL = resultURL.deletingPathExtension().appendingPathExtension("error.txt")
        let deadline = Date().addingTimeInterval(120)
        while
            !FileManager.default.fileExists(atPath: resultURL.path),
            !FileManager.default.fileExists(atPath: errorURL.path),
            Date() < deadline
        {
            Thread.sleep(forTimeInterval: 0.5)
        }
        if FileManager.default.fileExists(atPath: errorURL.path) {
            let reason = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            return recordSaveHarnessFailure(reason.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path), "save-e2e result was never written within 120s")

        let resultData = try Data(contentsOf: resultURL)
        let result = try JSONDecoder().decode(SaveE2EResult.self, from: resultData)

        XCTAssertEqual(result.capturedSHA256, expectedSHA256, "the poller must hash the exact bytes written to the artifact")
        XCTAssertEqual(result.capturedSizeBytes, 32_768)
        XCTAssertEqual(result.blobSHA256, expectedSHA256, "the revision that came back through sync must carry the same digest the Mac computed at capture")
        XCTAssertEqual(result.sizeBytes, 32_768)
        XCTAssertEqual(result.durability, "uploaded")
        // Provenance survives the round trip (WINDOWS #57): the columns
        // were plumbed client -> wire -> server -> journal -> client and
        // nothing ever asserted the whole run of it.
        XCTAssertEqual(result.adapterID, "e2e-harness", "adapter_id must survive upload, journal and sync")
        XCTAssertEqual(result.adapterVersion, "1.0")

        // This test calls `verify` for the mirror-state half only: stored
        // cursor, both sentinels, empty objects/partials, and zero blob
        // routes. It makes NO claim about how many snapshots the layer
        // fetched, and saying so explicitly is what stops it inheriting
        // LiveServerSnapshotTests' count -- which is what failed it in run
        // 34636187313 once 04.5-01 added a third snapshotting test.
        guard try runFixture(
            "verify",
            root: runRoot,
            extraArguments: ["snapshots-not-asserted-here"]
        ) else {
            return XCTFail("live fixture stage 'verify' failed")
        }
    }

    private struct SaveE2EResult: Decodable {
        let revisionID: String
        let blobSHA256: String
        let sizeBytes: Int
        let durability: String
        let adapterID: String
        let adapterVersion: String
        let capturedSHA256: String
        let capturedSizeBytes: Int

        enum CodingKeys: String, CodingKey {
            case revisionID = "revision_id"
            case blobSHA256 = "blob_sha256"
            case sizeBytes = "size_bytes"
            case durability
            case adapterID = "adapter_id"
            case adapterVersion = "adapter_version"
            case capturedSHA256 = "captured_sha256"
            case capturedSizeBytes = "captured_size_bytes"
        }
    }

    /// One assertion site per cause, for the same reason
    /// `recordFixtureFailure` has one: CI's evidence pipeline keeps
    /// `file:line` and discards assertion messages, so a single shared
    /// `XCTFail(reason)` would report every distinct failure at the same
    /// line and diagnose nothing.
    private func recordSaveHarnessFailure(_ reason: String) {
        switch reason {
        case "save-e2e: capture did not quiesce":
            XCTAssertTrue(false, "save-e2e-harness=capture-did-not-quiesce")
        case "save-e2e: no paired APIClient":
            XCTAssertTrue(false, "save-e2e-harness=no-paired-api-client")
        // Three distinct sites, because these are three distinct verdicts
        // and CI keeps only file:line. `retryable` is the lane being asked
        // to succeed on a single un-retried pass -- a harness limitation,
        // not a product defect. The other two are real defects.
        case "save-e2e: upload stopped for retry, retryable":
            XCTAssertTrue(false, "save-e2e-harness=upload-stopped-retryable")
        case "save-e2e: upload still retryable-failing after all attempts":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-retries")
        case "save-e2e: upload stopped for retry, server refused":
            XCTAssertTrue(false, "save-e2e-harness=upload-server-refused")
        case "save-e2e: upload found nothing pending":
            XCTAssertTrue(false, "save-e2e-harness=upload-nothing-pending")
        case "save-e2e: revision not found after sync":
            XCTAssertTrue(false, "save-e2e-harness=revision-missing-after-sync")
        default:
            XCTAssertTrue(false, "save-e2e-harness=unexpected")
        }
    }

    private func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Fixture plumbing (shared shape with LiveServerSnapshotTests)

    private func fixtureEnvironmentIsReady() -> Bool {
        let manager = FileManager.default
        guard let environment = resolvedFixtureEnvironment() else {
            XCTAssertTrue(false, "save-e2e-preflight=runtime-config-invalid")
            return false
        }
        fixtureEnvironment = environment
        let script = fixtureScriptURL()
        guard manager.fileExists(atPath: script.path) else {
            XCTAssertTrue(false, "save-e2e-preflight=script-missing")
            return false
        }
        guard manager.isReadableFile(atPath: script.path) else {
            XCTAssertTrue(false, "save-e2e-preflight=script-unreadable")
            return false
        }
        guard let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"], !serverRoot.isEmpty else {
            XCTAssertNotNil(environment["PLAYSTEAD_MAC_CI_ROOT"], "save-e2e-preflight=server-root-missing")
            return false
        }
        guard manager.fileExists(atPath: serverRoot) else {
            XCTAssertTrue(false, "save-e2e-preflight=owned-root-missing")
            return false
        }
        return true
    }

    private func resolvedFixtureEnvironment() -> [String: String]? {
        let required = Set([
            "PLAYSTEAD_MAC_CI_ROOT", "PLAYSTEAD_LIVE_SERVER_STAGE_ROOT",
            "PLAYSTEAD_LIVE_SERVER_STAGE_FILE", "MAC_CI_DATABASE_URL", "MIX_ENV", "PORT"
        ])
        let inherited = ProcessInfo.processInfo.environment

        // Resolve through the runner's runtime config FIRST, exactly as
        // `LiveServerSnapshotTests` does. This class's own doc comment claimed
        // it reused that fixture discipline "verbatim"; it did not -- it read
        // the inherited environment only. The inherited PATH has no Elixir
        // toolchain, so `live-server.sh`'s `mix playstead.mac_ci_fixture`
        // died with "mix: command not found" at provision-domain on every
        // hosted run. That was invisible because this test was fail-open
        // until e6316d5: the fixture returned false, the test returned
        // without asserting, and XCTest recorded a pass. Hosted run
        // 34272794656 is the first one that could say so.
        let url = runtimeConfigurationURL()
        if
            (try? permissions(of: url)) == 0o600,
            let data = try? Data(contentsOf: url),
            data.count <= 32_768,
            let configured = try? JSONDecoder().decode([String: String].self, from: data),
            Set(configured.keys) == required.union(["PATH"]),
            required.allSatisfy({ !(configured[$0] ?? "").isEmpty }),
            configured["MIX_ENV"] == "mac_ci",
            configured["PORT"] == "4010"
        {
            return inherited.merging(configured) { _, configuredValue in configuredValue }
        }

        // Without a config, fall back to a fully inherited environment, and
        // only when it is self-consistent: the runner derives both roots from
        // one native server root, so disagreement means these values did not
        // come from this run's runner.
        let inheritedRootsAgree =
            resolved(inherited["PLAYSTEAD_MAC_CI_ROOT"] ?? "")
                == resolved(inherited["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"] ?? "")
        if required.allSatisfy({ !(inherited[$0] ?? "").isEmpty }), inheritedRootsAgree {
            return inherited
        }
        return nil
    }

    private func resolved(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    }

    private func fixtureScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/ci/live-server.sh")
    }

    private func runtimeConfigurationURL() -> URL {
        fixtureScriptURL()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/ci/four-layer/raw/live-server-runtime.json")
    }

    private func runFixture(_ action: String, root: URL, extraArguments: [String] = []) throws -> Bool {
        let script = fixtureScriptURL()
        guard let environment = fixtureEnvironment,
              let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"] else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, action, root.path, serverRoot] + extraArguments
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
