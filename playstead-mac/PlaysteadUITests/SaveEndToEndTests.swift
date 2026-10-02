import XCTest
import Security
import CryptoKit
import Darwin

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
    private var probeProcess: Process?
    private var probeLog: FileHandle?
    private var probeRoot: URL?
    private var probeOutcome: ProbeReport?
    private var probeStopSucceeded: Bool?
    private var reliabilityControlDirectories: [URL] = []

    override func tearDownWithError() throws {
        app?.terminate()
        _ = stopReliabilityProbes()
        for directory in reliabilityControlDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        if let keychain { SecKeychainDelete(keychain) }
        if let root { try? FileManager.default.removeItem(at: root) }
        fixtureEnvironment = nil
        reliabilityControlDirectories = []
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
        // This verifier owns the same two-sentinel mirror invariant as the
        // snapshot flow, but runs independently of XCTest ordering. Seed the
        // second sentinel here instead of inheriting it from an earlier test.
        guard try runFixture("second", root: runRoot) else {
            return XCTFail("live fixture stage 'second' failed")
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
        guard let fixtureEnvironment,
              let caPath = fixtureEnvironment["PLAYSTEAD_TEST_LIVE_SERVER_CA_DER"],
              let caDigest = fixtureEnvironment["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"] else {
            return XCTFail("live fixture CA configuration is missing")
        }
        let trustAnchor = try LiveServerTestTrustAnchor(
            sourcePath: caPath, expectedSHA256: caDigest, runRoot: runRoot
        )

        let reliabilityEvidencePath = ProcessInfo.processInfo.environment["PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH"]
            .flatMap { $0.isEmpty ? nil : $0 }
        let reliabilityEnabled = reliabilityEvidencePath != nil
        let transientToken = UUID().uuidString.lowercased()
        let conflictToken = UUID().uuidString.lowercased()
        let transientRevisionID = UUID().uuidString.lowercased()
        if reliabilityEnabled {
            guard let serverRoot = fixtureEnvironment["PLAYSTEAD_MAC_CI_ROOT"] else {
                return XCTFail("save-e2e-reliability=server-root-missing")
            }
            try prepareReliabilityControl(token: transientToken, serverRoot: serverRoot)
            try prepareReliabilityControl(token: conflictToken, serverRoot: serverRoot)
            try startReliabilityProbes(root: runRoot, caFile: trustAnchor.fileURL)
        }
        defer {
            if reliabilityEnabled {
                XCTAssertTrue(stopReliabilityProbes(), "save-e2e-reliability=probes-failed")
            }
        }

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
        trustAnchor.install(on: launched)
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_ARTIFACT_PATH"] = artifactURL.path
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_CONTENT_KEY"] = contentKey
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_RESULT_PATH"] = resultURL.path
        if reliabilityEnabled, let serverRoot = fixtureEnvironment["PLAYSTEAD_MAC_CI_ROOT"] {
            launched.launchEnvironment["PLAYSTEAD_MAC_CI_ROOT"] = serverRoot
            launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_RELIABILITY"] = "1"
            launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_TRANSIENT_TOKEN"] = transientToken
            launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_TRANSIENT_REVISION_ID"] = transientRevisionID
            launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_CONFLICT_TOKEN"] = conflictToken
            launched.launchEnvironment["PLAYSTEAD_UI_TEST_SAVE_CONTROL_ROOT"] =
                URL(fileURLWithPath: serverRoot, isDirectory: true)
                    .appendingPathComponent("mac-client-control", isDirectory: true).path
        }
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))

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

        if reliabilityEnabled {
            guard let reliability = result.reliability,
                  isValidReliabilityResult(reliability),
                  let report = probeReportAfterStop() else {
                return XCTFail("save-e2e-reliability=classification-or-probe-evidence-missing")
            }
            try writeSanitizedReliabilityEvidence(
                reliability, probes: report, destination: reliabilityEvidencePath!
            )
        }

        // This test calls `verify` for the mirror-state half only: stored
        // cursor, both sentinels, empty objects/partials, and zero blob
        // routes. It makes NO claim about how many snapshots the layer
        // fetched, and saying so explicitly is what stops it inheriting
        // LiveServerSnapshotTests' count -- which is what failed it in run
        // 34636187313 once 04.5-01 added a third snapshotting test.
        let mirrorVerificationPassed = try runFixture(
            "verify",
            root: runRoot,
            extraArguments: ["snapshots-not-asserted-here"]
        )
        if !mirrorVerificationPassed {
            recordMirrorVerificationFailure(in: runRoot)
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
        let reliability: SaveReliabilityResult?

        enum CodingKeys: String, CodingKey {
            case revisionID = "revision_id"
            case blobSHA256 = "blob_sha256"
            case sizeBytes = "size_bytes"
            case durability
            case adapterID = "adapter_id"
            case adapterVersion = "adapter_version"
            case capturedSHA256 = "captured_sha256"
            case capturedSizeBytes = "captured_size_bytes"
            case reliability
        }
    }

    private struct SaveReliabilityResult: Decodable {
        let transient: TransientResult
        let conflict: ConflictResult
    }

    private struct TransientResult: Decodable {
        let httpStatus: Int
        let problemCode: String
        let failureClassification: String
        let failureCause: String
        let escalates: Bool
        let correlationID: String

        enum CodingKeys: String, CodingKey {
            case httpStatus = "http_status"
            case problemCode = "problem_code"
            case failureClassification = "failure_classification"
            case failureCause = "failure_cause"
            case escalates
            case correlationID = "correlation_id"
        }
    }

    private struct ConflictResult: Decodable {
        let originalHTTPStatus: Int
        let duplicateHTTPStatus: Int
        let problemCode: String
        let failureClassification: String
        let failureCause: String
        let escalates: Bool
        let correlationID: String

        enum CodingKeys: String, CodingKey {
            case originalHTTPStatus = "original_http_status"
            case duplicateHTTPStatus = "duplicate_http_status"
            case problemCode = "problem_code"
            case failureClassification = "failure_classification"
            case failureCause = "failure_cause"
            case escalates
            case correlationID = "correlation_id"
        }
    }

    private struct ProbeReport: Decodable {
        let schema: String
        let probeCount: Int
        let maxRequestsPerSecondPerProbe: Int
        let successfulRequests: [Int]
        let lastStatus: [Int]
        let failedRequests: [Int]

        enum CodingKeys: String, CodingKey {
            case schema
            case probeCount = "probe_count"
            case maxRequestsPerSecondPerProbe = "max_requests_per_second_per_probe"
            case successfulRequests = "successful_requests"
            case lastStatus = "last_status"
            case failedRequests = "failed_requests"
        }
    }

    private func prepareReliabilityControl(token: String, serverRoot: String) throws {
        guard UUID(uuidString: token) != nil else { throw SaveReliabilityTestError.invalidIdentity }
        let rootURL = URL(fileURLWithPath: serverRoot, isDirectory: true).standardizedFileURL
        let controlRoot = rootURL.appendingPathComponent("mac-client-control", isDirectory: true)
        let rootAttributes = try FileManager.default.attributesOfItem(atPath: controlRoot.path)
        guard (rootAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((rootAttributes[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o077 == 0,
              (rootAttributes[.type] as? FileAttributeType) == .typeDirectory else {
            throw SaveReliabilityTestError.invalidControlRoot
        }

        let directory = controlRoot.appendingPathComponent("save-e2e-\(token)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let owner = directory.appendingPathComponent("owner")
        try Data(token.utf8).write(to: owner, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: owner.path)
        reliabilityControlDirectories.append(directory)
    }

    private func startReliabilityProbes(root: URL, caFile: URL) throws {
        let owner = UUID().uuidString.lowercased()
        let ownerURL = root.appendingPathComponent(".owner")
        try Data(owner.utf8).write(to: ownerURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ownerURL.path)

        let helper = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/ci/reliability-load.py")
        guard FileManager.default.isReadableFile(atPath: helper.path) else {
            throw SaveReliabilityTestError.probeHelperMissing
        }
        let logURL = root.appendingPathComponent("reliability-probes.log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]),
              let log = FileHandle(forWritingAtPath: logURL.path) else {
            throw SaveReliabilityTestError.probeLogUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", helper.path, "probes",
            "--root", root.path,
            "--owner", owner,
            "--url", "https://127.0.0.1:4010/healthz",
            "--probes", "4",
            "--max-rps", "2",
            "--ready-timeout", "20",
            "--ca-file", caFile.path
        ]
        process.standardOutput = log
        process.standardError = log
        try process.run()
        probeProcess = process
        probeLog = log
        probeRoot = root

        let ready = root.appendingPathComponent("probes-ready")
        let deadline = Date().addingTimeInterval(22)
        while Date() < deadline {
            if let value = try? String(contentsOf: ready, encoding: .utf8), value == owner { return }
            guard process.isRunning else { throw SaveReliabilityTestError.probesDidNotStart }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw SaveReliabilityTestError.probesDidNotStart
    }

    @discardableResult
    private func stopReliabilityProbes() -> Bool {
        if let probeStopSucceeded { return probeStopSucceeded }
        guard let process = probeProcess else {
            probeStopSucceeded = false
            return false
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        try? probeLog?.close()
        probeLog = nil
        let report = probeRoot?.appendingPathComponent("probe-report.json")
        if let report,
           let data = try? Data(contentsOf: report),
           let decoded = try? JSONDecoder().decode(ProbeReport.self, from: data),
           decoded.schema == "playstead.reliability-probes.v1",
           decoded.probeCount == 4,
           decoded.maxRequestsPerSecondPerProbe == 2,
           decoded.successfulRequests.count == 4,
           decoded.successfulRequests.allSatisfy({ $0 > 0 }),
           decoded.lastStatus == [200, 200, 200, 200],
           decoded.failedRequests == [0, 0, 0, 0] {
            probeOutcome = decoded
            probeStopSucceeded = process.terminationStatus == 0
            return probeStopSucceeded!
        }
        probeStopSucceeded = false
        return false
    }

    private func probeReportAfterStop() -> ProbeReport? {
        guard stopReliabilityProbes() else { return nil }
        return probeOutcome
    }

    private func isValidReliabilityResult(_ result: SaveReliabilityResult) -> Bool {
        UUID(uuidString: result.transient.correlationID) != nil &&
        result.transient.httpStatus == 503 &&
        result.transient.problemCode == "service_unavailable" &&
        result.transient.failureClassification == "none" &&
        result.transient.failureCause == "http5xx" &&
        !result.transient.escalates &&
        UUID(uuidString: result.conflict.correlationID) != nil &&
        result.conflict.originalHTTPStatus == 201 &&
        result.conflict.duplicateHTTPStatus == 409 &&
        result.conflict.problemCode == "idempotency_key_conflict" &&
        result.conflict.failureClassification == "serverRefusal" &&
        result.conflict.failureCause == "idempotencyConflict" &&
        result.conflict.escalates
    }

    private func writeSanitizedReliabilityEvidence(
        _ result: SaveReliabilityResult, probes: ProbeReport, destination rawPath: String
    ) throws {
        let destination = URL(fileURLWithPath: rawPath).standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let attributes = try FileManager.default.attributesOfItem(atPath: parent.path)
        guard destination.lastPathComponent == "save-reliability.json",
              parent.lastPathComponent == "evidence",
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o077 == 0,
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw SaveReliabilityTestError.invalidEvidenceDestination
        }

        let evidence: [String: Any] = [
            "schema": "playstead.save-reliability.v1",
            "round_trip": "passed",
            "transient": [
                "http_status": result.transient.httpStatus,
                "problem_code": result.transient.problemCode,
                "failure_classification": result.transient.failureClassification,
                "failure_cause": result.transient.failureCause,
                "escalates": result.transient.escalates,
                "correlation_id": result.transient.correlationID.lowercased()
            ],
            "conflict": [
                "original_http_status": result.conflict.originalHTTPStatus,
                "duplicate_http_status": result.conflict.duplicateHTTPStatus,
                "problem_code": result.conflict.problemCode,
                "failure_classification": result.conflict.failureClassification,
                "failure_cause": result.conflict.failureCause,
                "escalates": result.conflict.escalates,
                "correlation_id": result.conflict.correlationID.lowercased()
            ],
            "probes": [
                "probe_count": probes.probeCount,
                "max_requests_per_second_per_probe": probes.maxRequestsPerSecondPerProbe,
                "successful_requests": probes.successfulRequests,
                "last_status": probes.lastStatus,
                "failed_requests": probes.failedRequests
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
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
        case "save-e2e: upload exhausted local retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-local-retries")
        case "save-e2e: upload exhausted retries without pairing":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-not-paired")
        case "save-e2e: upload exhausted connectivity retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-connectivity")
        case "save-e2e: upload exhausted timeout retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-timeout")
        case "save-e2e: upload exhausted TLS retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-tls")
        case "save-e2e: upload exhausted other transport retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-other-transport")
        case "save-e2e: upload exhausted invalid-response retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-invalid-response")
        case "save-e2e: upload exhausted HTTP 408 retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-http-408")
        case "save-e2e: upload exhausted HTTP 429 retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-http-429")
        case "save-e2e: upload exhausted HTTP 5xx retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-http-5xx")
        case "save-e2e: upload exhausted other HTTP retries":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-http-other")
        case "save-e2e: upload exhausted nonretryable HTTP status":
            XCTAssertTrue(false, "save-e2e-harness=upload-exhausted-nonretryable-http-status")
        // Four sites, not one, because D-40's four unfixable reasons are
        // four different verdicts and CI keeps only file:line. WINDOWS #87
        // cost a whole hosted run to "server refused" without being able to
        // say which refusal it was -- or whether the classification even
        // belonged to this pass.
        case "save-e2e: upload refused, revoked auth":
            XCTAssertTrue(false, "save-e2e-harness=refused-revoked-auth")
        case "save-e2e: upload refused, capability skew":
            XCTAssertTrue(false, "save-e2e-harness=refused-capability-skew")
        case "save-e2e: upload refused, server refusal":
            XCTAssertTrue(false, "save-e2e-harness=refused-server-refusal")
        case "save-e2e: upload refused with HTTP 400":
            XCTAssertTrue(false, "save-e2e-harness=refused-http-400")
        case "save-e2e: upload refused with HTTP 401":
            XCTAssertTrue(false, "save-e2e-harness=refused-http-401")
        case "save-e2e: upload refused with HTTP 403":
            XCTAssertTrue(false, "save-e2e-harness=refused-http-403")
        case "save-e2e: upload refused with HTTP 404":
            XCTAssertTrue(false, "save-e2e-harness=refused-http-404")
        case "save-e2e: upload refused with HTTP 409":
            XCTAssertTrue(false, "save-e2e-harness=refused-http-409")
        case "save-e2e: upload refused with HTTP 413":
            XCTAssertTrue(false, "save-e2e-harness=refused-http-413")
        case "save-e2e: upload refused with HTTP 422":
            XCTAssertTrue(false, "save-e2e-harness=refused-http-422")
        case "save-e2e: upload refused idempotency conflict":
            XCTAssertTrue(false, "save-e2e-harness=refused-idempotency-conflict")
        case "save-e2e: upload refused not found":
            XCTAssertTrue(false, "save-e2e-harness=refused-not-found")
        case "save-e2e: upload refused, compatibility rejection":
            XCTAssertTrue(false, "save-e2e-harness=refused-compatibility-rejection")
        case "save-e2e: upload found nothing pending":
            XCTAssertTrue(false, "save-e2e-harness=upload-nothing-pending")
        case "save-e2e: revision not found after sync":
            XCTAssertTrue(false, "save-e2e-harness=revision-missing-after-sync")
        case "save-e2e: transient server hook was not observed":
            XCTAssertTrue(false, "save-e2e-harness=transient-hook-not-observed")
        case "save-e2e: transient lane evidence missing":
            XCTAssertTrue(false, "save-e2e-harness=transient-lane-evidence-missing")
        case "save-e2e: transient classification was not none":
            XCTAssertTrue(false, "save-e2e-harness=transient-escalation-classification")
        case "save-e2e: transient cause was not http5xx":
            XCTAssertTrue(false, "save-e2e-harness=transient-cause-mismatch")
        case "save-e2e: transient status was not 503":
            XCTAssertTrue(false, "save-e2e-harness=transient-status-mismatch")
        case "save-e2e: transient problem code was not service unavailable":
            XCTAssertTrue(false, "save-e2e-harness=transient-code-mismatch")
        case "save-e2e: transient response escalated":
            XCTAssertTrue(false, "save-e2e-harness=transient-escalated")
        case "save-e2e: transient correlation identity missing":
            XCTAssertTrue(false, "save-e2e-harness=transient-correlation-missing")
        case "save-e2e: transient response evidence missing":
            XCTAssertTrue(false, "save-e2e-harness=transient-evidence-missing")
        case "save-e2e: reliability control invalid":
            XCTAssertTrue(false, "save-e2e-harness=reliability-control-invalid")
        case "save-e2e: execution claim unavailable":
            XCTAssertTrue(false, "save-e2e-harness=execution-claim-unavailable")
        case "save-e2e: conflict control identity invalid":
            XCTAssertTrue(false, "save-e2e-harness=conflict-control-invalid")
        case "save-e2e: conflict command missing":
            XCTAssertTrue(false, "save-e2e-harness=conflict-command-missing")
        case "save-e2e: conflict hold was not reached":
            XCTAssertTrue(false, "save-e2e-harness=conflict-hold-not-reached")
        case "save-e2e: duplicate did not reach idempotency preflight":
            XCTAssertTrue(false, "save-e2e-harness=duplicate-preflight-not-reached")
        case "save-e2e: duplicate conflict was not preserved":
            XCTAssertTrue(false, "save-e2e-harness=duplicate-conflict-not-preserved")
        case "save-e2e: reliability marker timeout":
            XCTAssertTrue(false, "save-e2e-harness=reliability-marker-timeout")
        default:
            XCTAssertTrue(false, "save-e2e-harness=unexpected")
        }
    }

    private func recordMirrorVerificationFailure(in runRoot: URL) {
        let marker = runRoot.appendingPathComponent("live-server-verify-result")
        let category = (try? String(contentsOf: marker, encoding: .ascii)) ?? "missing"
        switch category {
        case "mirror-database-unreadable":
            XCTAssertTrue(false, "save-e2e-verify=mirror-database-unreadable")
        case "snapshot-count-mismatch":
            XCTAssertTrue(false, "save-e2e-verify=snapshot-count-mismatch")
        case "blob-request-observed":
            XCTAssertTrue(false, "save-e2e-verify=blob-request-observed")
        case "snapshot-cursor-empty":
            XCTAssertTrue(false, "save-e2e-verify=snapshot-cursor-empty")
        case "sentinel-set-mismatch":
            XCTAssertTrue(false, "save-e2e-verify=sentinel-set-mismatch")
        case "local-byte-residue":
            XCTAssertTrue(false, "save-e2e-verify=local-byte-residue")
        case "verification-input-missing":
            XCTAssertTrue(false, "save-e2e-verify=verification-input-missing")
        case "passed":
            XCTAssertTrue(false, "save-e2e-verify=unexpected-runner-status")
        default:
            XCTAssertTrue(false, "save-e2e-verify=unclassified")
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
        let explicitRuntimeConfig = inherited["PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG"] ?? ""

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
            configured["PORT"] == "4010",
            runtimeConfigurationMatchesRun(url, configured: configured)
        {
            return inherited.merging(configured) { _, configuredValue in configuredValue }
        }

        if !explicitRuntimeConfig.isEmpty { return nil }

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
        return canonicalURL == expectedURL
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

private enum SaveReliabilityTestError: Error {
    case invalidIdentity
    case invalidControlRoot
    case probeHelperMissing
    case probeLogUnavailable
    case probesDidNotStart
    case invalidEvidenceDestination
}
