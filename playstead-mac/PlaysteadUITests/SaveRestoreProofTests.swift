import XCTest
import CryptoKit

/// Plan 04-13 task 1: the named restore proof. Proves the *file* half of
/// SAVE-03 -- that a captured revision restores to byte-identical bytes
/// on disk through the same `SavePlanExecutor` type the launch path
/// calls -- and nothing more. This is deliberately not a claim that a
/// real game continues from the restored save; that continuation proof
/// is human-only and carried separately by checkpoint **CP7-SAVE-C**
/// (plan 04-13 task 3), which must never be marked passed by this or
/// any other automated result (D-68).
///
/// A UI test target cannot `@testable import Playstead`, so this test
/// drives the accessible surface `UITestBootstrap.maybeRunSaveRestoreProof`
/// exposes -- three env vars naming an artifact path, a restore target
/// path, and a result path -- mirroring the existing
/// `SaveEndToEndTests`/`first-sentinel.json` convention rather than
/// inventing a UI surface purely to be inspected by a test.
@MainActor
final class SaveRestoreProofTests: XCTestCase {
    private var app: XCUIApplication?
    private var root: URL?

    override func tearDownWithError() throws {
        app?.terminate()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir() throws {
        let runRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-save-restore-proof-\(UUID().uuidString.lowercased())", isDirectory: true)
        root = runRoot
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        // The artifact this test's capture pass reads -- written before
        // launch, exactly 32,768 bytes, matching the fixed size every
        // other Phase 4 save proof in this repo uses.
        let artifactURL = runRoot.appendingPathComponent("synthetic.sav")
        let artifactBytes = Data((0..<32_768).map { UInt8(truncatingIfNeeded: $0) })
        try artifactBytes.write(to: artifactURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: artifactURL.path)
        let expectedSHA256 = sha256Hex(of: artifactBytes)

        // The restore target: deliberately does not exist yet, simulating
        // a clean Mac's save directory the way `LaunchSavePlanner`'s
        // `.exact` verdict finds one before an automatic silent restore.
        let targetURL = runRoot.appendingPathComponent("launch-dir").appendingPathComponent("game.sav")
        let resultURL = runRoot.appendingPathComponent("save-restore-proof-result.json")

        let launched = XCUIApplication()
        app = launched
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_PROFILE"] = "empty-library"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_RESTORE_ARTIFACT_PATH"] = artifactURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_RESTORE_TARGET_PATH"] = targetURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_RESTORE_RESULT_PATH"] = resultURL.path
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))

        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: resultURL.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path), "save-restore-proof result was never written within 30s")

        let resultData = try Data(contentsOf: resultURL)
        let result = try JSONDecoder().decode(SaveRestoreProofResult.self, from: resultData)

        XCTAssertEqual(result.capturedSHA256, expectedSHA256, "the poller must hash the exact bytes written to the artifact")
        XCTAssertEqual(result.capturedSizeBytes, 32_768)
        XCTAssertEqual(result.restoredSHA256, expectedSHA256, "the restored bytes on disk must hash to the captured revision's digest")
        XCTAssertEqual(result.restoredSizeBytes, 32_768)
        XCTAssertTrue(result.bytesEqual, "the restored file's bytes must be byte-identical to what was captured")

        // Belt-and-suspenders: re-read the actual restored file directly,
        // independent of the in-process result JSON, and compare bytes.
        let restoredOnDisk = try Data(contentsOf: targetURL)
        XCTAssertEqual(restoredOnDisk, artifactBytes)
        XCTAssertEqual(sha256Hex(of: restoredOnDisk), expectedSHA256)
    }

    private struct SaveRestoreProofResult: Decodable {
        let capturedSHA256: String
        let capturedSizeBytes: Int
        let restoredSHA256: String
        let restoredSizeBytes: Int
        let bytesEqual: Bool

        enum CodingKeys: String, CodingKey {
            case capturedSHA256 = "captured_sha256"
            case capturedSizeBytes = "captured_size_bytes"
            case restoredSHA256 = "restored_sha256"
            case restoredSizeBytes = "restored_size_bytes"
            case bytesEqual = "bytes_equal"
        }
    }

    private func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
