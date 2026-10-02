import CryptoKit
import Foundation
import XCTest

/// Proves the one finite UI_TESTING reference reaches the same packaged
/// readiness -> BIOS view -> BiosStore path as production composition.
/// The candidate is an inert nine-byte test sequence for a made-up system;
/// this suite makes no claim about any real BIOS.
@MainActor
final class BiosAcceptanceSeamTests: XCTestCase {
    private static let candidateBytes = Data([0x50, 0x4C, 0x41, 0x59, 0x53, 0x54, 0x45, 0x41, 0x44])
    private static let system = "playstead-test-bios-lab"
    private static let statusIdentifier = "playstead.readout.bios-status"
    private static let biosSurfaceIdentifier = "playstead.surface.bios"
    private static let readinessRemedyIdentifier = "playstead.readiness.row.bios.remedy"
    private static let chooseBiosIdentifier = "playstead.control.choose-bios"

    private var harness: UITestHarness!
    private var candidateRoot: URL!
    private var profileRoot: URL!
    private var candidateURL: URL!
    private var databaseURL: URL!
    private var managedBIOSDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
        if let candidateRoot { try? FileManager.default.removeItem(at: candidateRoot) }
        if let profileRoot { try? FileManager.default.removeItem(at: profileRoot) }
    }

    func testFixedSyntheticReferenceAcceptsThroughPackagedAppAndPersistsExactly() throws {
        try launchBIOSAcceptance(candidateBytes: Self.candidateBytes)
        acceptCandidate()

        let digest = Self.digest(Self.candidateBytes)
        XCTAssertEqual(
            harness.element(Self.statusIdentifier).readableText,
            "BIOS validated and stored."
        )
        XCTAssertEqual(try biosRows(), "1|\(Self.system)|\(Self.candidateBytes.count)|\(digest)|\(digest)")
        XCTAssertEqual(try managedFiles(), [digest])
        XCTAssertEqual(try Data(contentsOf: managedBIOSDirectory.appendingPathComponent(digest)), Self.candidateBytes)
        XCTAssertEqual(try Data(contentsOf: candidateURL), Self.candidateBytes, "acceptance must preserve the supplied original")

        // Accepting the same candidate again proves digest-derived storage
        // and the table's idempotent insert behavior through the same view.
        acceptCandidate()
        XCTAssertEqual(try biosRows(), "1|\(Self.system)|\(Self.candidateBytes.count)|\(digest)|\(digest)")
        XCTAssertEqual(try managedFiles(), [digest])
        XCTAssertEqual(try Data(contentsOf: candidateURL), Self.candidateBytes)
    }

    func testSameLengthWrongDigestIsRejectedWithoutManagedResidue() throws {
        let wrongBytes = Data(repeating: 0x58, count: Self.candidateBytes.count)
        try launchBIOSAcceptance(candidateBytes: wrongBytes)
        acceptCandidate()

        XCTAssertEqual(
            harness.element(Self.statusIdentifier).readableText,
            "This file could not be validated — this file's contents don't match a known reference."
        )
        XCTAssertEqual(try biosRows(), "0||0||")
        XCTAssertEqual(try managedFiles(), [])
        XCTAssertEqual(try Data(contentsOf: candidateURL), wrongBytes)
    }

    func testOneByteShortCandidateIsRejectedWithoutManagedResidue() throws {
        let wrongBytes = Data(Self.candidateBytes.dropLast())
        try launchBIOSAcceptance(candidateBytes: wrongBytes)
        acceptCandidate()

        XCTAssertEqual(
            harness.element(Self.statusIdentifier).readableText,
            "This file could not be validated — wrong size (expected \(Self.candidateBytes.count) bytes, got \(wrongBytes.count))."
        )
        XCTAssertEqual(try biosRows(), "0||0||")
        XCTAssertEqual(try managedFiles(), [])
        XCTAssertEqual(try Data(contentsOf: candidateURL), wrongBytes)
    }

    func testOneByteLongCandidateIsRejectedWithoutManagedResidue() throws {
        var wrongBytes = Self.candidateBytes
        wrongBytes.append(0x00)
        try launchBIOSAcceptance(candidateBytes: wrongBytes)
        acceptCandidate()

        XCTAssertEqual(
            harness.element(Self.statusIdentifier).readableText,
            "This file could not be validated — wrong size (expected \(Self.candidateBytes.count) bytes, got \(wrongBytes.count))."
        )
        XCTAssertEqual(try biosRows(), "0||0||")
        XCTAssertEqual(try managedFiles(), [])
        XCTAssertEqual(try Data(contentsOf: candidateURL), wrongBytes)
    }

    private func launchBIOSAcceptance(candidateBytes: Data) throws {
        let sessionID = UUID().uuidString.lowercased()
        let temporaryRoot = FileManager.default.temporaryDirectory
        candidateRoot = temporaryRoot.appendingPathComponent("playstead-bios-seam-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: candidateRoot, withIntermediateDirectories: true)
        candidateURL = candidateRoot.appendingPathComponent("candidate.bin")
        try candidateBytes.write(to: candidateURL, options: .atomic)

        profileRoot = temporaryRoot
            .appendingPathComponent("playstead-ui-profile-sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        // AppPaths belongs to the app target, not the XCUITest target. Mirror
        // only the two stable on-disk names needed for this test's private
        // fixture inspection; never construct the user's production paths.
        databaseURL = profileRoot.appendingPathComponent("playstead.sqlite3", isDirectory: false)
        managedBIOSDirectory = profileRoot.appendingPathComponent("bios", isDirectory: true)

        harness = UITestHarness(
            profile: .biosAcceptance,
            sessionID: sessionID,
            extraEnvironment: ["PLAYSTEAD_UI_TEST_BIOS_CANDIDATE": candidateURL.path]
        )
        harness.launch(settledAt: "playstead.surface.library")
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        harness.require(["playstead.surface.readiness"])
        harness.element(Self.readinessRemedyIdentifier, type: .button).clickWhenHittable()
        harness.require([Self.biosSurfaceIdentifier])
    }

    private func acceptCandidate() {
        harness.element(Self.chooseBiosIdentifier, type: .button).clickWhenHittable()
        XCTAssertTrue(harness.element(Self.statusIdentifier).awaitExistence(timeout: 5), "BIOS result was not rendered")
    }

    private func biosRows() throws -> String {
        try sqlite(
            "SELECT count(*) || '|' || COALESCE(max(system), '') || '|' || COALESCE(max(byte_length), 0) || '|' || COALESCE(max(sha256), '') || '|' || COALESCE(max(managed_filename), '') FROM bios_files WHERE system = '\(Self.system)';"
        )
    }

    private func managedFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: managedBIOSDirectory.path).sorted()
    }

    private func sqlite(_ query: String) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", databaseURL.path, query]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            XCTFail("Could not inspect the isolated BIOS acceptance database")
            throw CocoaError(.fileReadUnknown)
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
