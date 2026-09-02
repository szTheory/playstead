import XCTest
import Security

@MainActor
final class LiveServerSnapshotTests: XCTestCase {
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

    func testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch() throws {
        guard fixtureEnvironmentIsReady() else { return }
        let runRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-live-\(UUID().uuidString.lowercased())", isDirectory: true)
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

        guard try runFixture("prepare", root: runRoot) else { return }
        let first = try sentinel(at: runRoot.appendingPathComponent("control/first-sentinel.json"))
        let handoff = runRoot.appendingPathComponent("credential-handoff.json")
        XCTAssertEqual(try permissions(of: handoff), 0o600)

        let launched = XCUIApplication()
        app = launched
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_ROOT"] = runRoot.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF"] = handoff.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN"] = keychainURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"] = "dev.playstead.mac.live.\(UUID().uuidString.lowercased())"
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.path))
        XCTAssertTrue(launched.buttons["playstead.control.show-list"].waitForExistence(timeout: 10))
        launched.buttons["playstead.control.show-list"].click()
        let row = launched.descendants(matching: .any)["playstead.game.\(first.assetSetID).summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains(first.title))
        XCTAssertFalse(try storedCursor(root: runRoot).isEmpty)
        try assertNoGameBytes(root: runRoot)

        launched.terminate()
        guard try runFixture("second", root: runRoot) else { return }
        let second = try sentinel(at: runRoot.appendingPathComponent("control/second-sentinel.json"))
        XCTAssertNotEqual(second.assetSetID, first.assetSetID)

        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: runRoot.appendingPathComponent("playstead.sqlite3").path + suffix)
            )
        }
        launched.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF")
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].waitForExistence(timeout: 20))
        XCTAssertTrue(launched.buttons["playstead.control.show-list"].waitForExistence(timeout: 10))
        launched.buttons["playstead.control.show-list"].click()
        for sentinel in [first, second] {
            let refreshedRow = launched.descendants(matching: .any)["playstead.game.\(sentinel.assetSetID).summary"]
            XCTAssertTrue(refreshedRow.waitForExistence(timeout: 10))
            XCTAssertTrue(refreshedRow.label.contains(sentinel.title))
        }
        XCTAssertFalse(try storedCursor(root: runRoot).isEmpty)
        try assertNoGameBytes(root: runRoot)
        guard try runFixture("verify", root: runRoot) else { return }
    }

    private struct Control: Decodable {
        struct Sentinel: Decodable {
            let title: String
            let assetSetID: String
            enum CodingKeys: String, CodingKey { case title; case assetSetID = "asset_set_id" }
        }
        let sentinel: Sentinel
    }

    private func sentinel(at url: URL) throws -> Control.Sentinel {
        try JSONDecoder().decode(Control.self, from: Data(contentsOf: url)).sentinel
    }

    private func fixtureEnvironmentIsReady() -> Bool {
        let manager = FileManager.default
        guard let environment = resolvedFixtureEnvironment() else {
            XCTAssertTrue(false, "live-server-preflight=runtime-config-invalid")
            return false
        }
        fixtureEnvironment = environment
        let script = fixtureScriptURL()
        guard manager.fileExists(atPath: script.path) else {
            XCTAssertTrue(false, "live-server-preflight=script-missing")
            return false
        }
        guard manager.isReadableFile(atPath: script.path) else {
            XCTAssertTrue(false, "live-server-preflight=script-unreadable")
            return false
        }
        guard let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"], !serverRoot.isEmpty else {
            XCTAssertNotNil(environment["PLAYSTEAD_MAC_CI_ROOT"], "live-server-preflight=server-root-missing")
            return false
        }
        guard let stageRoot = environment["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"], !stageRoot.isEmpty else {
            XCTAssertNotNil(environment["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"], "live-server-preflight=stage-root-missing")
            return false
        }
        guard let stageFile = environment["PLAYSTEAD_LIVE_SERVER_STAGE_FILE"], !stageFile.isEmpty else {
            XCTAssertNotNil(environment["PLAYSTEAD_LIVE_SERVER_STAGE_FILE"], "live-server-preflight=stage-file-missing")
            return false
        }
        guard manager.fileExists(atPath: serverRoot), manager.fileExists(atPath: stageRoot) else {
            XCTAssertTrue(false, "live-server-preflight=owned-root-missing")
            return false
        }
        let stageURL = URL(fileURLWithPath: stageFile).standardizedFileURL
        guard stageURL.lastPathComponent == "live-server-failure-stage" else {
            XCTAssertEqual(stageURL.lastPathComponent, "live-server-failure-stage", "live-server-preflight=stage-basename")
            return false
        }
        let rootURL = URL(fileURLWithPath: stageRoot, isDirectory: true).standardizedFileURL
        guard stageURL.deletingLastPathComponent() == rootURL else {
            XCTAssertEqual(stageURL.deletingLastPathComponent(), rootURL, "live-server-preflight=stage-parent")
            return false
        }
        // The runner exports both roots from the same native server root, so a
        // divergence here means the resolved environment is not the one that
        // provisioned the server. Left unchecked it splits the fixture in two:
        // stage writes land in one directory while the pairing control
        // directory is created in another, which is how a writable stage file
        // coexisted with a failing mkdir at create-server-control.
        guard resolved(serverRoot) == resolved(stageRoot) else {
            XCTAssertEqual(resolved(serverRoot), resolved(stageRoot), "live-server-preflight=root-mismatch")
            return false
        }
        // Probe with a real create/remove rather than isWritableFile, which
        // answers access(2) and can disagree with what the filesystem actually
        // permits. The fixture only writes files into this root -- the runner
        // that owns the root creates its directories -- so file creation is the
        // capability to require here.
        guard probeCreate(in: serverRoot, directory: false) else {
            XCTAssertTrue(false, "live-server-preflight=server-root-file-write-denied")
            return false
        }
        return true
    }

    private func resolved(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    }

    /// Create a uniquely named entry in `root` and remove it again, reporting
    /// whether the operation actually succeeded.
    private func probeCreate(in root: String, directory: Bool) -> Bool {
        let manager = FileManager.default
        let probe = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(".live-server-probe.\(UUID().uuidString.lowercased())")
        do {
            if directory {
                try manager.createDirectory(at: probe, withIntermediateDirectories: false)
            } else {
                try Data("probe\n".utf8).write(to: probe, options: .atomic)
            }
        } catch {
            return false
        }
        try? manager.removeItem(at: probe)
        return true
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

    private func resolvedFixtureEnvironment() -> [String: String]? {
        let required = Set([
            "PLAYSTEAD_MAC_CI_ROOT", "PLAYSTEAD_LIVE_SERVER_STAGE_ROOT",
            "PLAYSTEAD_LIVE_SERVER_STAGE_FILE", "MAC_CI_DATABASE_URL", "MIX_ENV", "PORT"
        ])
        let inherited = ProcessInfo.processInfo.environment
        // Only trust a fully inherited environment when it is self-consistent.
        // The runner derives both roots from one native server root, so if they
        // disagree the inherited values did not come from this run's runner and
        // the materialized runtime config below is the authoritative source.
        let inheritedRootsAgree =
            resolved(inherited["PLAYSTEAD_MAC_CI_ROOT"] ?? "")
                == resolved(inherited["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"] ?? "")
        if required.allSatisfy({ !(inherited[$0] ?? "").isEmpty }), inheritedRootsAgree {
            return inherited
        }

        let url = runtimeConfigurationURL()
        guard
            (try? permissions(of: url)) == 0o600,
            let data = try? Data(contentsOf: url),
            data.count <= 32_768,
            let configured = try? JSONDecoder().decode([String: String].self, from: data),
            Set(configured.keys) == required,
            required.allSatisfy({ !(configured[$0] ?? "").isEmpty }),
            configured["MIX_ENV"] == "mac_ci",
            configured["PORT"] == "4010"
        else { return nil }
        return inherited.merging(configured) { _, configuredValue in configuredValue }
    }

    private func runFixture(_ action: String, root: URL) throws -> Bool {
        seedFixtureStageBestEffort(for: action)
        let script = fixtureScriptURL()
        guard let environment = fixtureEnvironment,
              let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"] else {
            recordFixtureFailure(stage: "validate-input", action: action, status: -1)
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, action, root.path, serverRoot]
        process.environment = environment
        let diagnostics = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = diagnostics
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let raw = String(
                decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            let allowedStages = [
                "validate-input", "resolve-server-root", "create-control-root",
                "create-server-control", "secure-roots", "provision-domain",
                "request-pairing", "approve-pairing", "redeem-pairing",
                "add-second-sentinel", "verify-evidence"
            ]
            let sanitized = raw.replacingOccurrences(
                of: "[^A-Za-z0-9 _:-]",
                with: " ",
                options: .regularExpression
            )
            let bounded = String(sanitized.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
            let stage = allowedStages.first { raw.contains("live-server fixture failed at \($0)") }
                ?? allowedStages.first { bounded.contains("live-server fixture failed at \($0)") }
            recordFixtureFailure(
                stage: stage,
                action: action,
                status: process.terminationStatus
            )
            return false
        }
        return true
    }

    private func fixtureEntryStage(for action: String) -> String? {
        switch action {
        case "prepare": "validate-input"
        case "second": "add-second-sentinel"
        case "verify": "verify-evidence"
        default: nil
        }
    }

    private func seedFixtureStageBestEffort(for action: String) {
        guard let stage = fixtureEntryStage(for: action) else { return }
        guard let environment = fixtureEnvironment else { return }
        guard
            let stageRoot = environment["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"],
            let stageFile = environment["PLAYSTEAD_LIVE_SERVER_STAGE_FILE"]
        else { return }
        let rootURL = URL(fileURLWithPath: stageRoot, isDirectory: true).standardizedFileURL
        let stageURL = URL(fileURLWithPath: stageFile).standardizedFileURL
        guard stageURL.deletingLastPathComponent() == rootURL else { return }

        let temporary = rootURL.appendingPathComponent(".live-server-failure-stage.\(UUID().uuidString.lowercased())")
        let manager = FileManager.default
        do {
            try Data("\(stage)\n".utf8).write(to: temporary, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if manager.fileExists(atPath: stageURL.path) {
                try manager.removeItem(at: stageURL)
            }
            try manager.moveItem(at: temporary, to: stageURL)
        } catch {
            try? manager.removeItem(at: temporary)
        }
    }

    private func recordFixtureFailure(stage: String?, action: String, status: Int32) {
        // Distinct XCTAssertEqual sites make the allowlisted stage visible to
        // the existing bounded xcresult parser without emitting raw IO. The
        // caller immediately returns from the test after this records failure.
        switch stage {
        case "validate-input":
            XCTAssertEqual(status, 0, "live-server-stage=validate-input action=\(action)")
        case "resolve-server-root":
            XCTAssertEqual(status, 0, "live-server-stage=resolve-server-root action=\(action)")
        case "create-control-root":
            XCTAssertEqual(status, 0, "live-server-stage=create-control-root action=\(action)")
        case "create-server-control":
            XCTAssertEqual(status, 0, "live-server-stage=create-server-control action=\(action)")
        case "secure-roots":
            XCTAssertEqual(status, 0, "live-server-stage=secure-roots action=\(action)")
        case "provision-domain":
            XCTAssertEqual(status, 0, "live-server-stage=provision-domain action=\(action)")
        case "request-pairing":
            XCTAssertEqual(status, 0, "live-server-stage=request-pairing action=\(action)")
        case "approve-pairing":
            XCTAssertEqual(status, 0, "live-server-stage=approve-pairing action=\(action)")
        case "redeem-pairing":
            XCTAssertEqual(status, 0, "live-server-stage=redeem-pairing action=\(action)")
        case "add-second-sentinel":
            XCTAssertEqual(status, 0, "live-server-stage=add-second-sentinel action=\(action)")
        case "verify-evidence":
            XCTAssertEqual(status, 0, "live-server-stage=verify-evidence action=\(action)")
        default:
            XCTAssertEqual(status, 0, "live-server-stage=bounded-diagnostic-unavailable action=\(action)")
        }
    }

    private func storedCursor(root: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [root.appendingPathComponent("playstead.sqlite3").path, "SELECT cursor FROM sync_cursor WHERE id = 1;"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func assertNoGameBytes(root: URL) throws {
        for name in ["objects", "partials"] {
            let contents = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(name).path)
            XCTAssertTrue(contents.isEmpty, "\(name) must remain empty before an explicit download")
        }
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
