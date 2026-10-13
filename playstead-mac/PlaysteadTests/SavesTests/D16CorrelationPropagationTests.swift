import XCTest
import CryptoKit
@testable import Playstead

/// Regression proof for the Mac-owned half of D-16/D-17. The fixture is
/// shaped exactly like the server's RFC 9457 Problem response; the sentinel
/// must never become part of the locally eligible diagnostic evidence.
final class D16CorrelationPropagationTests: XCTestCase {
    private var tempRoot: URL!
    private var saveStore: SaveStore!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        saveStore = SaveStore(localStore: try LocalStore(paths: AppPaths(root: tempRoot)))
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testProblemCorrelationIsRetainedAsOpaqueLaunchHandoffEvidence() throws {
        let correlation = "16f5d6a4-41f4-4b7c-9594-8f99085285ec"
        let privateSaveSentinel = "PRIVATE_SAVE_BYTES_MUST_NOT_ESCAPE"
        let body = Data("""
        {"type":"about:blank","title":"Save rejected","status":422,"detail":"safe","code":"save_binding_incompatible","correlation_id":"\(correlation)","private_save":"\(privateSaveSentinel)"}
        """.utf8)

        let error = try JSONDecoder().decode(APIError.self, from: body)
        let evidence = LaunchSaveContextBuilder.handoffEvidence(
            from: SaveUploadLane.diagnosticEvidence(for: APIClientError.server(error))
        )

        XCTAssertEqual(evidence?.correlationID, correlation)
        XCTAssertEqual(evidence?.serialized(), "{\"correlation_id\":\"\(correlation)\"}")
        XCTAssertFalse(evidence?.serialized().contains(privateSaveSentinel) ?? true)
    }

    func testMissingOrReplacedCorrelationIsNotEligibleForLaunchHandoff() throws {
        let missing = Data("{\"code\":\"internal_error\"}".utf8)
        let replaced = Data("{\"code\":\"internal_error\",\"correlation_id\":\"derived-from-content-key\"}".utf8)

        XCTAssertNil(LaunchSaveContextBuilder.handoffEvidence(for: try JSONDecoder().decode(APIError.self, from: missing)))
        XCTAssertNil(LaunchSaveContextBuilder.handoffEvidence(for: try JSONDecoder().decode(APIError.self, from: replaced)))
    }

    func testRetryableSaveFailureRetainsTheExactCorrelationUntilLaunchHandoff() async throws {
        let correlation = "16f5d6a4-41f4-4b7c-9594-8f99085285ec"
        let revision = try makeLocalRevision()
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(
                statusCode: 503, headers: [:],
                body: Data("{\"code\":\"unavailable\",\"correlation_id\":\"\(correlation)\"}".utf8)
            )
        }
        let client = APIClient(
            keychain: KeychainStore(), session: StubURLProtocol.makeSession(),
            credential: PairingCredential(deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "token")
        )
        let lane = SaveUploadLane(apiClient: client, saveStore: saveStore)

        let result = await lane.drainOnce(at: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(result.stoppedForRetry)
        XCTAssertEqual(saveStore.fetchRevision(id: revision.id)?.durability, SaveDurability.queued.rawValue)
        XCTAssertEqual(
            LaunchSaveContextBuilder.handoffEvidence(from: lane.lastFailureDiagnosticEvidence)?.correlationID,
            correlation
        )
    }

    private func makeLocalRevision() throws -> SaveRevisionRow {
        let bytes = Data(repeating: 0x16, count: 128)
        let directory = tempRoot.appendingPathComponent("captured", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("save.sav")
        try bytes.write(to: fileURL)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let line = try saveStore.resolveLine(contentKey: digest, saveKind: "battery", slot: "0", placeholderID: UUID().uuidString)
        let revision = SaveRevisionRow(
            id: UUID().uuidString, saveLineID: line.id, parentRevisionID: nil, blobSHA256: digest,
            sizeBytes: bytes.count, originDeviceID: "device-1", deviceCapturedAt: nil, recordedAt: nil,
            captureMethod: "poll", adapterID: "mgba", adapterVersion: "1.0", saveFormat: "sram",
            formatConfidence: "exact", playSessionID: nil, durability: SaveDurability.localOnly.rawValue,
            localPath: fileURL.path
        )
        try saveStore.insertRevision(revision)
        return revision
    }
}
