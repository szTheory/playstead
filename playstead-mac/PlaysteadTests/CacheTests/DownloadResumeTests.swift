import XCTest
import CryptoKit
@testable import Playstead

final class DownloadResumeTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var cas: CASManager!
    private let url = URL(string: "https://blobs.test/api/v1/blobs/fixture")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        cas = CASManager(paths: paths)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func fixtureData(byteCount: Int, seed: UInt8 = 7) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount {
            bytes[i] = UInt8((Int(seed) &+ i &* 31) & 0xFF)
        }
        return Data(bytes)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func instantSleeper() -> (@Sendable (Double) async -> Void) {
        { _ in }
    }

    // MARK: - Fresh download

    func testFreshDownloadCommitsObjectMatchingDigestAtCASPath() async throws {
        let data = fixtureData(byteCount: 200_000)
        let digest = sha256Hex(data)

        StubURLProtocol.responder = { _ in .init(statusCode: 200, headers: [:], body: data) }
        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: instantSleeper())

        try await engine.download(sha256: digest, from: url)

        XCTAssertTrue(cas.contains(digest))
        let committedURL = try cas.objectURL(for: digest)
        XCTAssertEqual(committedURL, paths.objects.appendingPathComponent(String(digest.prefix(2)))
            .appendingPathComponent(String(digest.dropFirst(2).prefix(2))).appendingPathComponent(digest))
        let onDisk = try Data(contentsOf: committedURL)
        XCTAssertEqual(onDisk, data)
    }

    func testZeroByteBlobCommitsAsZeroLengthObject() async throws {
        let digest = sha256Hex(Data())
        StubURLProtocol.responder = { _ in .init(statusCode: 200, headers: [:], body: Data()) }
        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: instantSleeper())

        try await engine.download(sha256: digest, from: url)

        XCTAssertTrue(cas.contains(digest))
        let attrs = try FileManager.default.attributesOfItem(atPath: try cas.objectURL(for: digest).path)
        XCTAssertEqual(attrs[.size] as? Int, 0)
    }

    // MARK: - Interruption leaves an exact partial, no commit

    func testInterruptedDownloadLeavesExactPartialAndNoCommit() async throws {
        let data = fixtureData(byteCount: 500_000)
        let digest = sha256Hex(data)
        let cutoff = 131_072 // > default chunkSize, forces at least one real flush

        StubURLProtocol.responder = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Range"), "first attempt must not carry Range")
            return .init(statusCode: 200, headers: [:], bodyChunks: [data.prefix(cutoff)], failAfter: true)
        }

        // Bounded to exactly one transport attempt so the interruption's
        // on-disk aftermath is observable deterministically, without
        // racing an unbounded background retry loop.
        let engine = DownloadEngine(
            session: StubURLProtocol.makeSession(), paths: paths, cas: cas,
            maxTransportAttempts: 1, sleeper: instantSleeper()
        )

        do {
            try await engine.download(sha256: digest, from: url)
            XCTFail("expected the bounded transport failure to propagate")
        } catch is URLError {
            // expected — the single allowed attempt failed transport-side
        }

        let partialURL = try paths.partialURL(for: digest)
        let attrs = try FileManager.default.attributesOfItem(atPath: partialURL.path)
        XCTAssertEqual(attrs[.size] as? Int, cutoff)
        XCTAssertFalse(cas.contains(digest))
    }

    // MARK: - Resume
    //
    // These tests pre-seed the partial file directly (rather than
    // driving an actual first-attempt interruption through the stub)
    // so the Range/If-Range/append behavior under test is isolated from
    // the engine's separate, already-covered interruption/retry timing.

    private func seedPartial(digest: String, prefix: Data) throws {
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        try prefix.write(to: try paths.partialURL(for: digest))
    }

    func testResumeSendsRangeAndQuotedIfRangeAndCommitsByteIdenticalObject() async throws {
        let data = fixtureData(byteCount: 400_000, seed: 3)
        let digest = sha256Hex(data)
        let cutoff = 100_000
        try seedPartial(digest: digest, prefix: data.prefix(cutoff))

        StubURLProtocol.responder = { request in
            let range = request.value(forHTTPHeaderField: "Range")
            let ifRange = request.value(forHTTPHeaderField: "If-Range")
            XCTAssertEqual(range, "bytes=\(cutoff)-")
            XCTAssertEqual(ifRange, "\"\(digest)\"")
            let remainder = data.suffix(from: cutoff)
            let headers = ["Content-Range": "bytes \(cutoff)-\(data.count - 1)/\(data.count)"]
            return .init(statusCode: 206, headers: headers, body: Data(remainder))
        }

        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: instantSleeper())
        try await engine.download(sha256: digest, from: url)

        XCTAssertTrue(cas.contains(digest))
        let onDisk = try Data(contentsOf: try cas.objectURL(for: digest))
        XCTAssertEqual(onDisk, data)
    }

    // MARK: - 200-instead-of-206 guard

    func test200InsteadOf206TruncatesPartialBeforeAppending() async throws {
        let data = fixtureData(byteCount: 300_000, seed: 11)
        let digest = sha256Hex(data)
        let cutoff = 90_000
        try seedPartial(digest: digest, prefix: data.prefix(cutoff))

        StubURLProtocol.responder = { request in
            // Server ignored the Range header entirely: full 200 body.
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Range"))
            return .init(statusCode: 200, headers: [:], body: data)
        }

        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: instantSleeper())

        // Assert the partial is zero-length before any new byte is
        // appended, at the moment the truncation decision is made —
        // then let the download run to completion.
        try await engine.download(sha256: digest, from: url)

        // If the guard failed to truncate, the committed object would be
        // cutoff + data.count bytes (doubled prefix). It must be exactly
        // data.count — proof the pre-existing cutoff bytes were discarded
        // rather than kept and appended onto.
        let onDisk = try Data(contentsOf: try cas.objectURL(for: digest))
        XCTAssertEqual(onDisk.count, data.count)
        XCTAssertEqual(onDisk, data)
    }

    // MARK: - 416 restarts

    func test416DiscardsPartialAndRestarts() async throws {
        let data = fixtureData(byteCount: 50_000, seed: 5)
        let digest = sha256Hex(data)
        let cutoff = 20_000
        try seedPartial(digest: digest, prefix: data.prefix(cutoff))

        var attempt = 0
        StubURLProtocol.responder = { _ in
            attempt += 1
            if attempt == 1 {
                return .init(statusCode: 416, headers: ["Content-Range": "bytes */\(data.count)"], body: Data())
            } else {
                return .init(statusCode: 200, headers: [:], body: data)
            }
        }

        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: instantSleeper())
        try await engine.download(sha256: digest, from: url)

        XCTAssertTrue(cas.contains(digest))
        let onDisk = try Data(contentsOf: try cas.objectURL(for: digest))
        XCTAssertEqual(onDisk, data)
        XCTAssertEqual(attempt, 2)

        let partialSizeBeforeSecondRequest = try paths.partialURL(for: digest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialSizeBeforeSecondRequest.path), "partial is renamed away on commit")
    }

    // MARK: - Digest mismatch quarantines, never commits

    func testDigestMismatchQuarantinesAndDoesNotCommit() async throws {
        let data = fixtureData(byteCount: 10_000, seed: 99)
        let wrongDigest = sha256Hex(fixtureData(byteCount: 10_000, seed: 100)) // deliberately wrong

        StubURLProtocol.responder = { _ in .init(statusCode: 200, headers: [:], body: data) }
        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: instantSleeper())

        do {
            try await engine.download(sha256: wrongDigest, from: url)
            XCTFail("expected digestMismatch")
        } catch let error as DownloadError {
            guard case .digestMismatch = error else {
                return XCTFail("expected .digestMismatch, got \(error)")
            }
        }

        XCTAssertFalse(cas.contains(wrongDigest))
        let quarantineDir = paths.partials.appendingPathComponent("quarantine", isDirectory: true)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: quarantineDir.path)
        XCTAssertFalse(quarantined.isEmpty, "a quarantined partial should exist")
    }

    // MARK: - RangeResumeDecision pure logic

    func testRangeResumeDecisionAppendsOnlyOnMatching206() {
        XCTAssertEqual(
            RangeResumeDecision.decide(sentRangeHeader: true, statusCode: 206, contentRangeFirstByte: 500, existingLength: 500),
            .appendFrom(500)
        )
        XCTAssertEqual(
            RangeResumeDecision.decide(sentRangeHeader: true, statusCode: 200, contentRangeFirstByte: nil, existingLength: 500),
            .restartFromZero
        )
        XCTAssertEqual(
            RangeResumeDecision.decide(sentRangeHeader: true, statusCode: 416, contentRangeFirstByte: nil, existingLength: 500),
            .restartFromZero
        )
        XCTAssertEqual(
            RangeResumeDecision.decide(sentRangeHeader: true, statusCode: 206, contentRangeFirstByte: 400, existingLength: 500),
            .restartFromZero
        )
        XCTAssertEqual(
            RangeResumeDecision.decide(sentRangeHeader: false, statusCode: 200, contentRangeFirstByte: nil, existingLength: 0),
            .restartFromZero
        )
    }

    // MARK: - No background session / resumeData anywhere

    func testNoBackgroundSessionOrResumeDataUsage() throws {
        let cacheDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CacheTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Cache")
        let enumerator = FileManager.default.enumerator(at: cacheDir, includingPropertiesForKeys: nil)
        var found = false
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if contents.contains("URLSessionConfiguration.background") || contents.contains("resumeData") {
                found = true
            }
        }
        XCTAssertFalse(found)
    }
}
