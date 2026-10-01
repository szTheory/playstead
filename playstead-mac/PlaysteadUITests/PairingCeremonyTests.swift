import XCTest
import Security
import CryptoKit

/// Covers plan 04.5-01 task 5's live-server proof: the real pairing
/// ceremony, driven entirely through the app's own `PairingView`, against
/// the real Phoenix server -- not `live-server.sh` performing the HTTP
/// calls itself (that shape already exists in `live-server.sh prepare` and
/// stays the fixture for tests that need a *pre-paired* app).
///
/// The fixture side only provisions the owner and approves whatever
/// request the app creates (`pair-provision`/`pair-approve`) -- it never
/// creates the request or redeems it. That is exactly the boundary D-07/
/// D-08 draw: `create`/`redeem` are unauthenticated because the client (not
/// the fixture) is the only party holding `device_code`.
///
/// This is the one live-server test WINDOWS #54 required: a human's path
/// (enter a server URL, see a display code, have it approved, end up with
/// a working credential) exercised end-to-end with no shell script and no
/// hand-written Keychain item standing in for the app.
///
/// Precondition for whoever finally executes this against a hosted
/// Phoenix: the fixture server MUST terminate TLS on port 4010. Since
/// plan 04.5-02, `PairingCoordinator.start()` refuses any non-`https`
/// scheme before a single network call, so the trust anchor this test
/// asserts below can only ever be captured from a real TLS challenge.
/// Until the hosted harness serves TLS on 4010, this test cannot pass —
/// that gap is the remaining blocker on ROADMAP criterion 6, already
/// tracked as deferred in 04.5-VERIFICATION.md.
@MainActor
final class PairingCeremonyTests: XCTestCase {
    private var app: XCUIApplication?
    private var keychain: SecKeychain?
    private var root: URL?
    private var fixtureEnvironment: [String: String]?
    private var runtimeConfigurationFailure = RuntimeConfigurationFailure.invalid

    /// Closed, path-free preflight diagnostics for sanitized CI evidence.
    private enum RuntimeConfigurationFailure: String {
        case invalid = "runtime-config-invalid"
        case fileInvalid = "runtime-config-file-invalid"
        case contentInvalid = "runtime-config-content-invalid"
        case identityInvalid = "runtime-config-identity-invalid"
        case runMismatch = "runtime-config-run-mismatch"
        case caPathInvalid = "runtime-config-ca-path-invalid"
        case caDigestInvalid = "runtime-config-ca-digest-invalid"
        case inheritedInvalid = "runtime-config-environment-invalid"
    }

    /// Must match `Mix.Tasks.Playstead.MacCiFixture`'s `@device_label` --
    /// `approve-sole` requires the pending request's `claimed_device_name`
    /// to equal this exact literal.
    private static let deviceLabel = "Playstead Hosted Mac"

    override func tearDownWithError() throws {
        app?.terminate()
        if let keychain { SecKeychainDelete(keychain) }
        if let root { try? FileManager.default.removeItem(at: root) }
        fixtureEnvironment = nil
    }

    func testAHumanCanPairAFreshMacEntirelyFromInsideTheAppAgainstTheRealServer() throws {
        guard fixtureEnvironmentIsReady() else {
            // Never a bare return: a preflight failure must be a visible
            // failure, not a silently green test (fail-open-test-guard-test.sh).
            return XCTFail("live fixture preflight failed")
        }
        let runRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-pair-\(UUID().uuidString.lowercased())", isDirectory: true)
        root = runRoot
        try FileManager.default.createDirectory(
            at: runRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )

        let keychainURL = runRoot.appendingPathComponent("scoped.keychain-db")
        guard let caPath = fixtureEnvironment?["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"] else {
            return XCTFail("live fixture CA path is missing")
        }
        let sourceCA = URL(fileURLWithPath: caPath)
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: sourceCA.path)
        XCTAssertEqual(sourceAttributes[.type] as? FileAttributeType, .typeRegular)
        let caBytes = try Data(contentsOf: sourceCA, options: [.mappedIfSafe])
        XCTAssertGreaterThan(caBytes.count, 0)
        XCTAssertLessThanOrEqual(caBytes.count, 16_384)
        let caDigest = SHA256.hash(data: caBytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(caDigest, fixtureEnvironment?["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"])
        let ownedCA = runRoot.appendingPathComponent("pairing-ca.der")
        try caBytes.write(to: ownedCA, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ownedCA.path)

        let password = Data("synthetic-\(UUID().uuidString)".utf8)
        var created: SecKeychain?
        let status = keychainURL.path.withCString { path in
            password.withUnsafeBytes { bytes in
                SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created)
            }
        }
        XCTAssertEqual(status, errSecSuccess)
        keychain = created

        guard try runFixture("pair-provision", root: runRoot) else {
            return XCTFail("live fixture stage 'pair-provision' failed")
        }

        let launched = XCUIApplication()
        app = launched
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_ROOT"] = runRoot.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN"] = keychainURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"] = "dev.playstead.mac.live.\(UUID().uuidString.lowercased())"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_DER"] = ownedCA.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256"] = caDigest
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_PAIRING_TARGET"] = "https://127.0.0.1:4010"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_PAIRING_DEVICE_NAME"] = Self.deviceLabel
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))
        openPairingFromMenu(in: launched)

        let serverURLField = launched.textFields["playstead.control.pairing-server-url"]
        XCTAssertTrue(serverURLField.awaitExistence(timeout: 10))
        serverURLField.clickWhenHittable()
        serverURLField.typeText("https://127.0.0.1:4010")

        let requestButton = launched.buttons["playstead.control.request-pairing"]
        XCTAssertTrue(requestButton.awaitExistence(timeout: 5))
        requestButton.clickWhenHittable()

        let displayCodeElement = launched.descendants(matching: .any)["playstead.control.pairing-display-code"]
        XCTAssertTrue(displayCodeElement.awaitExistence(timeout: 15), "expected the server-issued display code to render")
        let displayCode = displayCodeElement.readableText
        XCTAssertFalse(displayCode.isEmpty)

        // The fixture's one and only privileged action: approving the
        // request the app itself created, exactly as a human clicking in
        // the devices console would.
        guard try runFixture("pair-approve", root: runRoot, extraArgument: displayCode) else {
            return XCTFail("live fixture stage 'pair-approve' failed")
        }

        let success = launched.descendants(matching: .any)["playstead.control.pairing-success"]
        XCTAssertTrue(success.awaitExistence(timeout: 20), "expected the ceremony to complete and report success")

        // The trust anchor, not merely the confirmation: criterion 5
        // (VERIFICATION gap 1) requires the server's certificate to have
        // actually landed on disk at the exact path `APIClient` watches.
        // `UITestBootstrap.makeLiveServerSession` builds `AppPaths(root:)`
        // from `PLAYSTEAD_UI_TEST_LIVE_ROOT`, set to `runRoot` above, so
        // that is the exact path the app writes.
        let pinnedCertificateURL = runRoot.appendingPathComponent("pinned-ca.der")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: pinnedCertificateURL.path),
            "criterion 5: pinned-ca.der must exist after a successful pairing"
        )
        let pinnedCertificateData = try? Data(contentsOf: pinnedCertificateURL)
        XCTAssertFalse(
            (pinnedCertificateData ?? Data()).isEmpty,
            "criterion 5: pinned-ca.der must be non-empty after a successful pairing"
        )

        launched.buttons["playstead.control.done"].clickWhenHittable()

        // The evidence, not the confirmation: a working credential landed
        // in the exact scoped Keychain `APIClient` reads from -- proven by
        // a real subsequent snapshot fetch succeeding on relaunch.
        launched.terminate()
        for key in [
            "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED",
            "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_DER",
            "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256",
            "PLAYSTEAD_UI_TEST_LIVE_SERVER_PAIRING_TARGET",
        ] {
            launched.launchEnvironment.removeValue(forKey: key)
        }
        launched.launch()
        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))
        // UITestBootstrap fails closed before constructing the library if the
        // scoped credential cannot be reopened from the same run-owned store.
    }

    // MARK: - Fixture plumbing (mirrors LiveServerSnapshotTests exactly)

    private func fixtureEnvironmentIsReady() -> Bool {
        let manager = FileManager.default
        guard let environment = resolvedFixtureEnvironment() else {
            XCTAssertTrue(
                false,
                "pairing-ceremony-preflight=\(runtimeConfigurationFailure.rawValue)"
            )
            return false
        }
        fixtureEnvironment = environment
        let script = fixtureScriptURL()
        guard manager.fileExists(atPath: script.path) else {
            XCTAssertTrue(false, "pairing-ceremony-preflight=script-missing")
            return false
        }
        guard manager.isReadableFile(atPath: script.path) else {
            XCTAssertTrue(false, "pairing-ceremony-preflight=script-unreadable")
            return false
        }
        guard let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"], !serverRoot.isEmpty else {
            XCTAssertNotNil(environment["PLAYSTEAD_MAC_CI_ROOT"], "pairing-ceremony-preflight=server-root-missing")
            return false
        }
        guard manager.fileExists(atPath: serverRoot) else {
            XCTAssertTrue(false, "pairing-ceremony-preflight=owned-root-missing")
            return false
        }
        if let owner = ownerUID(of: serverRoot), owner != getuid() {
            XCTAssertTrue(false, "pairing-ceremony-preflight=server-root-foreign-owner")
            return false
        }
        let denial = probeWriteErrno(in: serverRoot)
        if denial == 0 { return true }
        XCTAssertTrue(false, "pairing-ceremony-preflight=server-root-write-denied")
        return false
    }

    private func probeWriteErrno(in root: String) -> Int32 {
        let path = (root as NSString)
            .appendingPathComponent(".pairing-ceremony-probe.\(UUID().uuidString.lowercased())")
        let descriptor = path.withCString { open($0, O_CREAT | O_EXCL | O_WRONLY, 0o600) }
        guard descriptor >= 0 else { return errno }
        close(descriptor)
        _ = path.withCString { unlink($0) }
        return 0
    }

    private func ownerUID(of path: String) -> uid_t? {
        var info = stat()
        guard path.withCString({ stat($0, &info) }) == 0 else { return nil }
        return info.st_uid
    }

    private func resolved(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    }

    private func fixtureScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/ci/live-server.sh")
    }

    private func openPairingFromMenu(in app: XCUIApplication) {
        let pairingMenu = app.menuBars.menuBarItems["Pairing"]
        XCTAssertTrue(pairingMenu.awaitExistence(timeout: 10), "the production Pairing menu is missing")
        pairingMenu.clickWhenHittable()
        let pairCommand = app.menuItems["Pair with Server…"]
        XCTAssertTrue(pairCommand.awaitExistence(timeout: 5), "the production Pair with Server command is missing")
        pairCommand.clickWhenHittable()
    }

    private func runtimeConfigurationURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG"],
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return fixtureScriptURL()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/ci/four-layer/raw/live-server-runtime.json")
    }

    private func runtimeConfigurationMatchesRun(_ url: URL, configured: [String: String]) -> Bool {
        guard let serverRoot = configured["PLAYSTEAD_MAC_CI_ROOT"],
              let stageRoot = configured["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"],
              resolved(serverRoot) == resolved(stageRoot) else { return false }
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        let expectedURL = resolved(serverRoot)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("live-server-runtime.json")
        // The runner may spell the same temporary directory through `/tmp`
        // or `/private/tmp`; compare canonical locations against this run's
        // expected file rather than rejecting a safe symlink spelling.
        return canonicalURL == expectedURL
    }

    private func resolvedFixtureEnvironment() -> [String: String]? {
        let required = Set([
            "PLAYSTEAD_MAC_CI_ROOT", "PLAYSTEAD_LIVE_SERVER_STAGE_ROOT",
            "PLAYSTEAD_LIVE_SERVER_STAGE_FILE", "MAC_CI_DATABASE_URL", "MIX_ENV", "PORT"
        ])
        let inherited = ProcessInfo.processInfo.environment
        let explicitRuntimeConfig = inherited["PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG"] ?? ""

        let url = runtimeConfigurationURL()
        if !explicitRuntimeConfig.isEmpty {
            guard (try? permissions(of: url)) == 0o600 else {
                runtimeConfigurationFailure = .fileInvalid
                return nil
            }
            guard let data = try? Data(contentsOf: url), data.count <= 32_768,
                  let configured = try? JSONDecoder().decode([String: String].self, from: data),
                  Set(configured.keys) == required.union(["PATH"]),
                  required.allSatisfy({ !(configured[$0] ?? "").isEmpty }) else {
                runtimeConfigurationFailure = .contentInvalid
                return nil
            }
            guard configured["MIX_ENV"] == "mac_ci", configured["PORT"] == "4010" else {
                runtimeConfigurationFailure = .identityInvalid
                return nil
            }
            guard runtimeConfigurationMatchesRun(url, configured: configured) else {
                runtimeConfigurationFailure = .runMismatch
                return nil
            }
            let merged = inherited.merging(configured) { _, configuredValue in configuredValue }
            guard let caPath = merged["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"],
                  let serverRoot = merged["PLAYSTEAD_MAC_CI_ROOT"],
                  caPathMatchesRun(caPath, serverRoot: serverRoot) else {
                runtimeConfigurationFailure = .caPathInvalid
                return nil
            }
            guard let digest = merged["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"],
                  isCanonicalSHA256(digest) else {
                runtimeConfigurationFailure = .caDigestInvalid
                return nil
            }
            return merged
        }

        let inheritedRootsAgree =
            resolved(inherited["PLAYSTEAD_MAC_CI_ROOT"] ?? "")
                == resolved(inherited["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"] ?? "")
        if required.allSatisfy({ !(inherited[$0] ?? "").isEmpty }), inheritedRootsAgree {
            return inherited
        }
        runtimeConfigurationFailure = .inheritedInvalid
        return nil
    }

    /// Compare the CA's canonical parent directory to this run's owned
    /// `tls` directory, while allowing the same temporary root through
    /// `/tmp` or `/private/tmp` spellings. Requiring the fixed leaf name
    /// keeps a caller-supplied path from escaping the service root.
    private func caPathMatchesRun(_ path: String, serverRoot: String) -> Bool {
        let caURL = URL(fileURLWithPath: path).standardizedFileURL
        guard caURL.lastPathComponent == "ca.der" else { return false }
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: caURL.path)) == nil else {
            return false
        }
        let actualParent = resolved(caURL.deletingLastPathComponent().path)
        let expectedParent = resolved(
            resolved(serverRoot).appendingPathComponent("tls", isDirectory: true).path
        )
        return actualParent == expectedParent
    }

    private func isCanonicalSHA256(_ digest: String) -> Bool {
        let bytes = Array(digest.utf8)
        return bytes.count == 64 && bytes.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private func runFixture(_ action: String, root: URL, extraArgument: String? = nil) throws -> Bool {
        let script = fixtureScriptURL()
        guard let environment = fixtureEnvironment,
              let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"] else {
            recordFixtureFailure(action: action, status: -1)
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        var arguments = [script.path, action, root.path, serverRoot]
        if let extraArgument { arguments.append(extraArgument) }
        process.arguments = arguments
        process.environment = environment
        let diagnostics = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = diagnostics
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            _ = diagnostics.fileHandleForReading.readDataToEndOfFile()
            recordFixtureFailure(action: action, status: process.terminationStatus)
            return false
        }
        return true
    }

    private func recordFixtureFailure(action: String, status: Int32) {
        XCTAssertEqual(status, 0, "pairing-ceremony-fixture-failed action=\(action)")
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
