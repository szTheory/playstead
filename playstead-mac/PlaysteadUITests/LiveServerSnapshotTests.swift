import XCTest
import Security

@MainActor
final class LiveServerSnapshotTests: XCTestCase {
    private var app: XCUIApplication?
    private var keychain: SecKeychain?
    private var root: URL?

    override func tearDownWithError() throws {
        app?.terminate()
        if let keychain { SecKeychainDelete(keychain) }
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch() throws {
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

        try runFixture("prepare", root: runRoot)
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
        try runFixture("second", root: runRoot)
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
        try runFixture("verify", root: runRoot)
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

    private func runFixture(_ action: String, root: URL) throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/ci/live-server.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, action, root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
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
