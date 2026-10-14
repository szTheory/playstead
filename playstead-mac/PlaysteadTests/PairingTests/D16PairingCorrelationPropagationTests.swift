import XCTest
@testable import Playstead

@MainActor
final class D16PairingCorrelationPropagationTests: XCTestCase {
    override func setUp() {
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
    }

    func testFailedPairingRetainsOnlyExactProblemCorrelationAsLocalEvidence() async {
        let correlation = "1ee5c0e4-20a4-4548-b3fa-c3c0e2518744"
        let credentialSentinel = "PAIRING_CREDENTIAL_MUST_NOT_APPEAR"
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(
                statusCode: 409, headers: [:],
                body: Data("{\"code\":\"pairing_request_not_approved\",\"correlation_id\":\"\(correlation)\",\"credential\":\"\(credentialSentinel)\"}".utf8)
            )
        }
        let coordinator = PairingCoordinator(
            client: PairingClient(session: StubURLProtocol.makeSession()), keychain: KeychainStore(),
            deviceName: "Test Mac", platform: "macOS", appVersion: "1.0", deviceCodeGenerator: { "device-code" }
        )

        await coordinator.start(baseURLString: "https://sync.test")

        XCTAssertEqual(coordinator.state, .failed(.notApproved))
        XCTAssertEqual(coordinator.lastFailureDiagnosticEvidence?.correlationID, correlation)
        XCTAssertEqual(coordinator.lastFailureDiagnosticEvidence?.serialized(), "{\"correlation_id\":\"\(correlation)\"}")
        XCTAssertFalse(coordinator.lastFailureDiagnosticEvidence?.serialized().contains(credentialSentinel) ?? true)
    }

    func testPairingDoesNotAcceptMissingOrContentDerivedCorrelation() async {
        for body in [
            "{\"code\":\"pairing_request_not_approved\"}",
            "{\"code\":\"pairing_request_not_approved\",\"correlation_id\":\"derived-from-device-code\"}"
        ] {
            StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 409, headers: [:], body: Data(body.utf8)) }
            let coordinator = PairingCoordinator(client: PairingClient(session: StubURLProtocol.makeSession()), keychain: KeychainStore())
            await coordinator.start(baseURLString: "https://sync.test")
            XCTAssertNil(coordinator.lastFailureDiagnosticEvidence)
        }
    }
}
