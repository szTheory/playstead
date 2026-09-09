import XCTest
import Security
@testable import Playstead

/// Covers plan 04.5-01 task 2: the pairing ceremony's own state machine,
/// exercised against `StubURLProtocol` exactly as `SaveSessionCoordinatorTests`
/// exercises `SaveSessionCoordinator` — a plain type constructed directly,
/// with no SwiftUI and no real network or Keychain surprises.
///
/// The Keychain half uses a real, scoped file Keychain (`SecKeychainCreate`),
/// the same pattern `LiveServerSnapshotTests` uses at the UI-test layer —
/// proven safe there, and here it proves `storeCredential` actually lands a
/// credential `APIClient` could read back, not merely that the coordinator
/// calls a mock.
@MainActor
final class PairingCoordinatorTests: XCTestCase {
    private var tempRoot: URL!
    private var keychain: SecKeychain?
    private var store: KeychainStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let keychainPath = tempRoot.appendingPathComponent("scoped.keychain-db")
        let password = Data("pairing-coordinator-test-\(UUID().uuidString)".utf8)
        var created: SecKeychain?
        let status = keychainPath.path.withCString { path in
            password.withUnsafeBytes { bytes in
                SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created)
            }
        }
        XCTAssertEqual(status, errSecSuccess)
        keychain = created
        store = try KeychainStore.uiTestingStore(
            service: "dev.playstead.mac.test.\(UUID().uuidString.lowercased())", fileURL: keychainPath
        )
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let keychain { SecKeychainDelete(keychain) }
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    // MARK: - Fixture construction

    /// The pin URL most recently resolved by `makeCoordinator(pinsCertificate: true)`,
    /// so tests can stat it without recomputing the path.
    private var pinnedCertificateURL: URL?

    private func makeCoordinator(
        deviceCode: String = "fixed-device-code",
        now: @escaping () -> Date = Date.init,
        recordedSleeps: SleepRecorder? = nil,
        capturedCertificateData: Data? = nil,
        pinsCertificate: Bool = false
    ) -> PairingCoordinator {
        let client = PairingClient(session: StubURLProtocol.makeSession())
        var certificateCapture: PinnedCertificateCapture?
        var pinURL: URL?
        if pinsCertificate {
            certificateCapture = PinnedCertificateCapture(capturedCertificateData: capturedCertificateData)
            pinURL = AppPaths(root: tempRoot).root.appendingPathComponent("pinned-ca.der")
            pinnedCertificateURL = pinURL
        }
        return PairingCoordinator(
            client: client,
            keychain: store,
            certificateCapture: certificateCapture,
            pinnedCertificateURL: pinURL,
            deviceName: "Test Mac",
            platform: "macOS",
            appVersion: "1.0",
            deviceCodeGenerator: { deviceCode },
            now: now,
            sleep: { interval in recordedSleeps?.record(interval) }
        )
    }

    /// Thread-confined to the MainActor test class, so a plain array is safe.
    final class SleepRecorder {
        private(set) var intervals: [TimeInterval] = []
        func record(_ interval: TimeInterval) { intervals.append(interval) }
    }

    private func waitForTerminal(_ coordinator: PairingCoordinator, timeout: TimeInterval = 3) async -> PairingState {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch coordinator.state {
            case .paired, .failed:
                return coordinator.state
            default:
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        return coordinator.state
    }

    // MARK: - Response builders

    private static func createBody(id: String, displayCode: String, pollInterval: Double, expiresAt: Date) -> Data {
        let iso = ISO8601DateFormatter().string(from: expiresAt)
        return Data("""
        {"id":"\(id)","display_code":"\(displayCode)","poll_interval":\(pollInterval),"expires_at":"\(iso)"}
        """.utf8)
    }

    private static func statusBody(_ status: String) -> Data {
        Data("{\"status\":\"\(status)\"}".utf8)
    }

    private static func redeemBody(deviceID: String, credential: String, fingerprintPrefix: String) -> Data {
        Data("""
        {"device_id":"\(deviceID)","credential":"\(credential)","fingerprint_prefix":"\(fingerprintPrefix)"}
        """.utf8)
    }

    private static func problemBody(code: String) -> Data {
        Data("{\"code\":\"\(code)\",\"title\":\"t\",\"detail\":\"d\"}".utf8)
    }

    private static func isCreate(_ request: URLRequest) -> Bool {
        request.httpMethod == "POST" && request.url?.path.hasSuffix("/device-pairing/requests") == true
    }
    private static func isPoll(_ request: URLRequest) -> Bool {
        request.httpMethod == "GET" && (request.url?.path.contains("/device-pairing/requests/") ?? false)
    }
    private static func isRedeem(_ request: URLRequest) -> Bool {
        request.httpMethod == "POST" && (request.url?.path.hasSuffix("/redeem") ?? false)
    }

    // MARK: - Happy path

    func testCreateRequestTransitionsToAwaitingApprovalWithTheServersDisplayCodeAndCadence() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        StubURLProtocol.responder = { request in
            guard Self.isCreate(request) else { return StubURLProtocol.Stub(statusCode: 404, headers: [:], body: Data()) }
            return StubURLProtocol.Stub(
                statusCode: 201, headers: ["Content-Type": "application/json"],
                body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
            )
        }
        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")

        guard case .awaitingApproval(let displayCode, let expiresAt) = coordinator.state else {
            return XCTFail("expected .awaitingApproval, got \(coordinator.state)")
        }
        XCTAssertEqual(displayCode, "ABC-123")
        XCTAssertEqual(expiresAt.timeIntervalSince1970, expires.timeIntervalSince1970, accuracy: 1)

        // Stop the poll loop before it can run against a responder this test
        // never scripted a poll/redeem branch for.
        coordinator.cancel()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testFullCeremonySucceedsAndWritesTheCredentialExactlyOnce() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        var pollCount = 0
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                pollCount += 1
                let status = pollCount < 2 ? "pending" : "approved"
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody(status))
            }
            if Self.isRedeem(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.redeemBody(deviceID: "device-9", credential: "cred-abc", fingerprintPrefix: "ab:cd")
                )
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        let final = await waitForTerminal(coordinator)

        guard case .paired(let deviceID) = final else {
            return XCTFail("expected .paired, got \(final)")
        }
        XCTAssertEqual(deviceID, "device-9")

        let credential = store.loadCredential()
        XCTAssertEqual(credential?.deviceID, "device-9")
        XCTAssertEqual(credential?.token, "cred-abc")
        XCTAssertEqual(credential?.baseURL, URL(string: "https://127.0.0.1:4010"))

        let redeemCalls = StubURLProtocol.requestLog.filter { $0.url?.path.hasSuffix("/redeem") == true }
        XCTAssertEqual(redeemCalls.count, 1, "redeem must happen exactly once per approved ceremony")
    }

    // MARK: - PROT-01/ceremony-failure: four distinct, non-collapsed refusals

    func testRedeemExpiredReachesFailedExpired() async throws {
        try await assertRedeemFailure(problemCode: "pairing_request_expired", status: 410, expected: .expired)
    }

    func testRedeemAlreadyRedeemedReachesFailedAlreadyRedeemed() async throws {
        try await assertRedeemFailure(problemCode: "pairing_request_already_redeemed", status: 409, expected: .alreadyRedeemed)
    }

    func testRedeemNotApprovedReachesFailedNotApproved() async throws {
        try await assertRedeemFailure(problemCode: "pairing_request_not_approved", status: 409, expected: .notApproved)
    }

    private func assertRedeemFailure(problemCode: String, status: Int, expected: PairingError) async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody("approved"))
            }
            if Self.isRedeem(request) {
                return StubURLProtocol.Stub(statusCode: status, headers: [:], body: Self.problemBody(code: problemCode))
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        let final = await waitForTerminal(coordinator)
        XCTAssertEqual(final, .failed(expected))
        XCTAssertNil(store.loadCredential(), "a failed redeem must never leave a credential behind")
    }

    /// The server's poll-time `"denied"` status is a distinct terminal
    /// outcome from every redeem-time refusal above.
    func testPollDeniedReachesFailedDenied() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody("denied"))
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }
        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        let final = await waitForTerminal(coordinator)
        XCTAssertEqual(final, .failed(.denied))
    }

    // MARK: - PROT-01/poll-cadence

    /// The poll loop must honor the server-advertised interval and back off
    /// further — never faster — on a 429, so it cannot trip
    /// `Pairing.check_poll_rate/1` and lock itself out mid-ceremony.
    func testPollBacksOffOnSlowDownAndDoublesTheNextInterval() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        var pollCount = 0
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                pollCount += 1
                if pollCount == 1 {
                    return StubURLProtocol.Stub(statusCode: 429, headers: [:], body: Self.problemBody(code: "slow_down"))
                }
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody("approved"))
            }
            if Self.isRedeem(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.redeemBody(deviceID: "device-1", credential: "cred-1", fingerprintPrefix: "aa:bb")
                )
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let recorder = SleepRecorder()
        let coordinator = makeCoordinator(recordedSleeps: recorder)
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        let final = await waitForTerminal(coordinator)

        guard case .paired = final else { return XCTFail("expected .paired after backing off, got \(final)") }
        // First sleep is the server's advertised interval (5s); the second
        // (after the 429) must be strictly larger, never the same or smaller.
        XCTAssertGreaterThanOrEqual(recorder.intervals.count, 2)
        XCTAssertEqual(recorder.intervals[0], 5)
        XCTAssertGreaterThan(recorder.intervals[1], recorder.intervals[0])
    }

    // MARK: - Expiry

    func testPollingStopsAtExpiryRatherThanPollingADeadRequest() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        var pollAttempted = false
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                pollAttempted = true
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody("pending"))
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        // `now` always reports past the request's expiry, so the very first
        // loop iteration must stop rather than poll.
        let coordinator = makeCoordinator(now: { Date.distantFuture })
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        let final = await waitForTerminal(coordinator)

        XCTAssertEqual(final, .failed(.expired))
        XCTAssertFalse(pollAttempted, "an expired request must never be polled")
    }

    // MARK: - Cancellation

    func testCancellingStopsThePollLoop() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        var pollCount = 0
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                pollCount += 1
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody("pending"))
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        coordinator.cancel()
        XCTAssertEqual(coordinator.state, .idle)

        // Give any (incorrectly) still-running loop a chance to poll.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(pollCount, 0, "cancel() must stop polling, not merely reset the displayed state")
    }

    // MARK: - Input validation

    func testAnUnparsableServerAddressFailsWithoutMakingARequest() async throws {
        StubURLProtocol.responder = { _ in
            XCTFail("no request should be made for an invalid server address")
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }
        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "not a url")
        XCTAssertEqual(coordinator.state, .failed(.invalidResponse))
    }

    func testAnEmptyServerAddressFailsWithoutMakingARequest() async throws {
        StubURLProtocol.responder = { _ in
            XCTFail("no request should be made for an empty server address")
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }
        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "   ")
        XCTAssertEqual(coordinator.state, .failed(.invalidResponse))
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty)
    }

    // MARK: - Fail-closed pinning (VERIFICATION gap 1 / CR-02)

    /// planner-discipline-allow: http://127.0.0.1:4010
    func testAPlaintextServerAddressIsRefusedBeforeAnyRequest() async throws {
        StubURLProtocol.responder = { _ in
            XCTFail("no request should be made for a plaintext server address")
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }
        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "http://127.0.0.1:4010")
        XCTAssertEqual(coordinator.state, .failed(.insecureServerAddress))
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty)
    }

    func testPairingFailsClosedAndRollsBackTheCredentialWhenTheAnchorCannotBePinned() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        var pollCount = 0
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                pollCount += 1
                let status = pollCount < 2 ? "pending" : "approved"
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody(status))
            }
            if Self.isRedeem(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.redeemBody(deviceID: "device-9", credential: "cred-abc", fingerprintPrefix: "ab:cd")
                )
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let coordinator = makeCoordinator(capturedCertificateData: nil, pinsCertificate: true)
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        let final = await waitForTerminal(coordinator)

        XCTAssertEqual(final, .failed(.certificatePinFailed))
        XCTAssertNil(store.loadCredential(), "a failed pin must roll back the just-stored credential")
        guard let pinURL = pinnedCertificateURL else {
            return XCTFail("expected makeCoordinator(pinsCertificate: true) to resolve a pin URL")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: pinURL.path))
    }

    func testStartingASecondCeremonyWhileOneIsAwaitingApprovalIsANoOp() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        var createCount = 0
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                createCount += 1
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 300, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody("pending"))
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let coordinator = makeCoordinator()
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        guard case .awaitingApproval(let firstCode, _) = coordinator.state else {
            return XCTFail("expected .awaitingApproval, got \(coordinator.state)")
        }
        XCTAssertEqual(createCount, 1)

        await coordinator.start(baseURLString: "https://127.0.0.1:4010")

        XCTAssertEqual(createCount, 1, "a second start() while awaiting approval must not issue another create request")
        guard case .awaitingApproval(let secondCode, _) = coordinator.state else {
            return XCTFail("expected .awaitingApproval to persist, got \(coordinator.state)")
        }
        XCTAssertEqual(firstCode, secondCode)

        coordinator.cancel()
    }

    /// The tracer proof: a successful https ceremony with seeded capture
    /// bytes writes the server's trust anchor to `pinned-ca.der`, and
    /// `.paired` is reached only after both the credential and the pin
    /// are durable.
    func testASuccessfulPairingWritesTheServersTrustAnchorToPinnedCADer() async throws {
        let expires = Date(timeIntervalSinceNow: 300)
        var pollCount = 0
        StubURLProtocol.responder = { request in
            if Self.isCreate(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.createBody(id: "req-1", displayCode: "ABC-123", pollInterval: 5, expiresAt: expires)
                )
            }
            if Self.isPoll(request) {
                pollCount += 1
                let status = pollCount < 2 ? "pending" : "approved"
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Self.statusBody(status))
            }
            if Self.isRedeem(request) {
                return StubURLProtocol.Stub(
                    statusCode: 201, headers: [:],
                    body: Self.redeemBody(deviceID: "device-9", credential: "cred-abc", fingerprintPrefix: "ab:cd")
                )
            }
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let seededBytes = Data("der-anchor-bytes".utf8)
        let coordinator = makeCoordinator(capturedCertificateData: seededBytes, pinsCertificate: true)
        await coordinator.start(baseURLString: "https://127.0.0.1:4010")
        let final = await waitForTerminal(coordinator)

        guard case .paired = final else {
            return XCTFail("expected .paired, got \(final)")
        }
        guard let pinURL = pinnedCertificateURL else {
            return XCTFail("expected makeCoordinator(pinsCertificate: true) to resolve a pin URL")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: pinURL.path))
        let written = try Data(contentsOf: pinURL)
        XCTAssertFalse(written.isEmpty)
        XCTAssertEqual(written, seededBytes)
        XCTAssertEqual(store.loadCredential()?.deviceID, "device-9")
    }
}
