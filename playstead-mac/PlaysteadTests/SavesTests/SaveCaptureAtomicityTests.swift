import XCTest
import CryptoKit
import Darwin
@testable import Playstead

/// WR-02 (04-REVIEW.md / 04-17-PLAN.md task 1): the rolling `staged`
/// file's write must replace an existing destination atomically. Before
/// this fix, `write()` did `removeItem(at: finalURL)` then
/// `moveItem(at:to:)` -- two separate filesystem operations with a
/// crash window between them in which `finalURL` was absent entirely.
/// These tests exercise the observable contract: an existing staged
/// file is never left empty/missing across a replace, a failed write
/// leaves the prior file exactly as it was, and a first write with no
/// prior file still succeeds.
final class SaveCaptureAtomicityTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            // A failure-injection test may leave `UF_IMMUTABLE` set on a
            // file; clear it everywhere under tempRoot first, or the
            // subsequent `removeItem` leaks the directory.
            clearImmutableFlags(under: tempRoot)
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func clearImmutableFlags(under url: URL) {
        _ = chflags(url.path, 0)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator {
            _ = chflags(fileURL.path, 0)
        }
    }

    // MARK: - Test doubles (mirrors SaveCaptureTierTests' conventions)

    private final class ScriptedArtifactSource: SaveArtifactSource, @unchecked Sendable {
        var next: Data?
        func readArtifact() -> Data? { next }
    }

    private struct FixedClock: SaveCaptureClock {
        func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }
    }

    private func makePoller(sessionID: String = UUID().uuidString) -> (SaveCapturePoller, URL) {
        let dir = tempRoot.appendingPathComponent("saves-\(UUID().uuidString)", isDirectory: true)
        let poller = SaveCapturePoller(
            source: ScriptedArtifactSource(),
            clock: FixedClock(),
            destinationDirectory: dir,
            pollInterval: 1.0,
            sessionID: sessionID,
            knownHeadDigest: nil
        )
        return (poller, dir)
    }

    /// Feeds three identical reads (D-03 quiescence) so a staged capture
    /// is produced deterministically.
    @discardableResult
    private func stageQuiescently(_ poller: SaveCapturePoller, bytes: Data) async throws -> CapturedSave? {
        _ = try await poller.observe(bytes)
        _ = try await poller.observe(bytes)
        return try await poller.observe(bytes)
    }

    private func stagedFileURL(in dir: URL, sessionID: String) -> URL {
        dir.appendingPathComponent("session-\(sessionID).staged.sav")
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 1. First write, no prior file, still succeeds.

    func test_firstStagedWrite_withNoPriorFile_succeeds() async throws {
        let sessionID = UUID().uuidString
        let (poller, dir) = makePoller(sessionID: sessionID)
        let bytes = Data(repeating: 0xAA, count: 32)

        guard let staged = try await stageQuiescently(poller, bytes: bytes) else {
            return XCTFail("expected a staged capture on first quiescent write")
        }

        let url = stagedFileURL(in: dir, sessionID: sessionID)
        XCTAssertEqual(staged.localPath, url.path)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    // MARK: - 2. A second write atomically replaces the first: exact new bytes, never a mixture.

    func test_secondStagedWrite_replacesFirst_finalFileIsExactlyTheNewBytes() async throws {
        let sessionID = UUID().uuidString
        let (poller, dir) = makePoller(sessionID: sessionID)
        let firstBytes = Data(repeating: 0x01, count: 64)
        let secondBytes = Data(repeating: 0x02, count: 40) // different length AND content

        try await stageQuiescently(poller, bytes: firstBytes)
        let url = stagedFileURL(in: dir, sessionID: sessionID)
        XCTAssertEqual(try Data(contentsOf: url), firstBytes)

        guard let secondStaged = try await stageQuiescently(poller, bytes: secondBytes) else {
            return XCTFail("expected a second staged capture for different bytes")
        }

        let finalBytes = try Data(contentsOf: url)
        XCTAssertEqual(finalBytes, secondBytes, "the replace must be all-or-nothing: never a mixture of old and new bytes")
        XCTAssertNotEqual(finalBytes, firstBytes)
        XCTAssertEqual(secondStaged.sha256, digest(secondBytes))
    }

    // MARK: - 3. A failed write leaves the prior staged file completely intact.

    func test_failedReplace_leavesPriorStagedFileIntact() async throws {
        let sessionID = UUID().uuidString
        let (poller, dir) = makePoller(sessionID: sessionID)
        let firstBytes = Data(repeating: 0x03, count: 48)
        try await stageQuiescently(poller, bytes: firstBytes)

        let url = stagedFileURL(in: dir, sessionID: sessionID)
        // Mark the existing staged file immutable so the write's
        // `rename(2)` call -- which must overwrite it -- fails with
        // EPERM, simulating a write failure at the replace step.
        XCTAssertEqual(chflags(url.path, UInt32(UF_IMMUTABLE)), 0, "precondition: could not mark staged file immutable")
        defer { _ = chflags(url.path, 0) }

        let secondBytes = Data(repeating: 0x04, count: 48)
        do {
            _ = try await stageQuiescently(poller, bytes: secondBytes)
            XCTFail("expected the replace to fail while the destination is immutable")
        } catch let error as SaveCaptureError {
            XCTAssertEqual(error, .writeFailed)
        }

        XCTAssertEqual(try Data(contentsOf: url), firstBytes, "a failed replace must never touch the previous staged file's bytes")
    }

    // MARK: - 4. A failed write removes its own temp artifact, leaving no orphan.

    func test_failedReplace_removesTempArtifact() async throws {
        let sessionID = UUID().uuidString
        let (poller, dir) = makePoller(sessionID: sessionID)
        let firstBytes = Data(repeating: 0x05, count: 16)
        try await stageQuiescently(poller, bytes: firstBytes)

        let url = stagedFileURL(in: dir, sessionID: sessionID)
        XCTAssertEqual(chflags(url.path, UInt32(UF_IMMUTABLE)), 0)
        defer { _ = chflags(url.path, 0) }

        _ = try? await stageQuiescently(poller, bytes: Data(repeating: 0x06, count: 16))

        let leftoverTempFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftoverTempFiles.isEmpty, "a failed write must remove its temp artifact: found \(leftoverTempFiles)")
    }

    // MARK: - 5. Many sequential replacements never leave an empty or truncated file.

    func test_multipleSequentialReplacements_neverLeaveAnEmptyOrTruncatedFile() async throws {
        let sessionID = UUID().uuidString
        let (poller, dir) = makePoller(sessionID: sessionID)
        let url = stagedFileURL(in: dir, sessionID: sessionID)

        for i in 0..<10 {
            let bytes = Data(repeating: UInt8(i), count: 20 + i)
            guard let staged = try await stageQuiescently(poller, bytes: bytes) else {
                return XCTFail("expected staged capture #\(i)")
            }
            let onDisk = try Data(contentsOf: url)
            XCTAssertEqual(onDisk, bytes, "iteration \(i): staged file must exactly match the newest bytes, never a hole or a mix")
            XCTAssertEqual(staged.sizeBytes, bytes.count)
        }
    }

    // MARK: - 6. The content-addressed (promoted) path also succeeds with no prior file.

    func test_contentAddressedWrite_succeeds_whenNoPriorFileExists() async throws {
        let (poller, dir) = makePoller()
        let bytes = Data(repeating: 0x07, count: 24)
        try await stageQuiescently(poller, bytes: bytes)

        guard let promoted = try await poller.promote() else {
            return XCTFail("expected a promoted revision")
        }

        let promotedURL = dir.appendingPathComponent("\(promoted.sha256).sav")
        XCTAssertEqual(try Data(contentsOf: promotedURL), bytes)
    }
}
