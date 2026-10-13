import XCTest
import Security

@MainActor
final class MetadataDescriptionJourneyTests: XCTestCase {
    private var app: XCUIApplication?
    private var keychain: SecKeychain?
    private var root: URL?
    private var environment: [String: String] = [:]

    override func tearDownWithError() throws {
        app?.terminate()
        if let app { XCTAssertEqual(app.state, .notRunning, "metadata journey app must be closed") }
        if let keychain { SecKeychainDelete(keychain) }
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testPrivateDescriptionSurvivesChangeAndReset() throws {
        guard fixtureEnvironmentIsReady() else { return XCTFail("metadata live-server preflight failed") }
        let runRoot = FileManager.default.temporaryDirectory.appendingPathComponent("playstead-metadata-\(UUID().uuidString.lowercased())", isDirectory: true)
        root = runRoot
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let handoff = runRoot.appendingPathComponent("credential-handoff.json")
        guard try runFixture("prepare", root: runRoot), FileManager.default.fileExists(atPath: handoff.path) else {
            return XCTFail("metadata fixture pairing setup failed")
        }
        let credentialCopy = runRoot.appendingPathComponent("test-credential.json")
        try FileManager.default.copyItem(at: handoff, to: credentialCopy)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialCopy.path)

        let keychainURL = runRoot.appendingPathComponent("scoped.keychain-db")
        let password = Data("metadata-\(UUID().uuidString)".utf8)
        var created: SecKeychain?
        let status = keychainURL.path.withCString { path in
            password.withUnsafeBytes { bytes in SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created) }
        }
        XCTAssertEqual(status, errSecSuccess)
        keychain = created
        let trust = try LiveServerTestTrustAnchor(
            sourcePath: try XCTUnwrap(environment["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"]),
            expectedSHA256: try XCTUnwrap(environment["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"]),
            runRoot: runRoot
        )

        let launched = XCUIApplication()
        app = launched
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_ROOT"] = runRoot.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF"] = handoff.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN"] = keychainURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"] = "dev.playstead.mac.live.\(UUID().uuidString.lowercased())"
        trust.install(on: launched)
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))
        let sentinel = try JSONDecoder().decode(SentinelEnvelope.self, from: Data(contentsOf: runRoot.appendingPathComponent("control/first-sentinel.json"))).sentinel
        let rowID = "playstead.game.\(sentinel.assetSetID).summary"
        XCTAssertTrue(launched.descendants(matching: .any)[rowID].awaitExistence(timeout: 15))
        let initialGameIDs = try databaseIDs(root: runRoot, table: "catalogue_entries", column: "id")
        let initialSaveLines = try databaseIDs(root: runRoot, table: "save_line", column: "id")
        let initialSaveRevisions = try databaseIDs(root: runRoot, table: "save_revision", column: "id")

        guard try runFixture("metadata-select", root: runRoot) else { return XCTFail("authenticated metadata selection failed") }
        launched.terminate()
        XCTAssertEqual(launched.state, .notRunning)
        launched.launchEnvironment.removeValue(forKey: "PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF")
        launched.launch()
        XCTAssertTrue(launched.staticTexts["playstead.game.description"].waitForExistence(timeout: 20))
        XCTAssertEqual(launched.staticTexts["playstead.game.description"].readableText, "Synthetic private description survives journal and snapshot reset.")

        guard try runFixture("reset-cursor", root: runRoot) else { return XCTFail("isolated profile cursor reset failed") }
        launched.terminate()
        XCTAssertEqual(launched.state, .notRunning)
        launched.launch()
        XCTAssertTrue(launched.staticTexts["playstead.game.description"].waitForExistence(timeout: 20))
        XCTAssertEqual(launched.staticTexts["playstead.game.description"].readableText, "Synthetic private description survives journal and snapshot reset.")
        XCTAssertTrue(launched.descendants(matching: .any)[rowID].exists)
        XCTAssertEqual(try databaseIDs(root: runRoot, table: "catalogue_entries", column: "id"), initialGameIDs)
        XCTAssertEqual(try databaseIDs(root: runRoot, table: "save_line", column: "id"), initialSaveLines)
        XCTAssertEqual(try databaseIDs(root: runRoot, table: "save_revision", column: "id"), initialSaveRevisions)
    }

    private struct SentinelEnvelope: Decodable {
        struct Sentinel: Decodable { let title: String; let assetSetID: String; enum CodingKeys: String, CodingKey { case title; case assetSetID = "asset_set_id" } }
        let sentinel: Sentinel
    }

    private func fixtureEnvironmentIsReady() -> Bool {
        let values = ProcessInfo.processInfo.environment
        let required = Set(["PLAYSTEAD_MAC_CI_ROOT", "PLAYSTEAD_LIVE_SERVER_STAGE_ROOT", "PLAYSTEAD_LIVE_SERVER_STAGE_FILE", "MAC_CI_DATABASE_URL", "MIX_ENV", "PORT"])
        guard let configPath = values["PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG"],
              let config = try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: configPath))),
              runtimeConfigurationMatchesRun(configPath, configured: config),
              Set(config.keys) == required.union(["PATH"]), required.allSatisfy({ !(config[$0] ?? "").isEmpty }),
              config["MIX_ENV"] == "mac_ci", config["PORT"] == "4010",
              URL(fileURLWithPath: config["PLAYSTEAD_MAC_CI_ROOT"]!).standardizedFileURL == URL(fileURLWithPath: config["PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"]!).standardizedFileURL,
              values["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"]?.isEmpty == false,
              values["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"]?.isEmpty == false else { return false }
        environment = values.merging(config) { _, configuredValue in configuredValue }
        return true
    }

    private func runFixture(_ action: String, root: URL) throws -> Bool {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/ci/live-server.sh")
        guard let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"] else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, action, root.path, serverRoot]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        let diagnostics = Pipe()
        process.standardError = diagnostics
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stages = ["validate-input", "resolve-server-root", "create-control-root", "create-server-control", "secure-roots", "provision-domain", "request-pairing", "approve-pairing", "redeem-pairing", "metadata-selection", "snapshot-reset"]
            let stage = stages.first { output.contains("live-server fixture failed at \($0)") } ?? "unknown"
            XCTFail("metadata fixture stage failed: \(stage)")
            return false
        }
        return true
    }

    private func databaseIDs(root: URL, table: String, column: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print('\\n'.join(r[0] for r in c.execute('SELECT ' + sys.argv[3] + ' FROM ' + sys.argv[2] + ' ORDER BY ' + sys.argv[3])))", root.appendingPathComponent("playstead.sqlite3").path, table, column]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "MetadataJourney", code: 1) }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.split(separator: "\n").map(String.init)
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
