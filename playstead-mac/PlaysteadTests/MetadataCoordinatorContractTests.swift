import XCTest
@testable import Playstead

/// Exercises the production coordinator and authenticated API composition with
/// a deterministic transport. This is a state/contract oracle; it does not
/// claim packaged accessibility or painted UI action coverage.
final class MetadataCoordinatorContractTests: XCTestCase {
    private var root: URL!
    private var localStore: LocalStore!
    private var metadataStore: MetadataStore!
    private var outbox: Outbox!
    private var coordinator: MetadataCoordinator!
    private let assetID = "7C6C379B-8C15-4C17-BAF3-6D908620155B"
    private let credential = PairingCredential(deviceID: "metadata-coordinator-test", baseURL: URL(string: "https://metadata.test")!, token: "coordinator-token")

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: root)
        localStore = try LocalStore(paths: paths)
        metadataStore = MetadataStore(localStore: localStore)
        outbox = Outbox(localStore: localStore, curationStore: CurationStore(localStore: localStore), metadataStore: metadataStore)
        let api = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        let cache = MetadataMediaCache(root: paths.metadataMedia, localStore: localStore, byteLimit: 1024, lowWaterBytes: 0)
        coordinator = MetadataCoordinator(apiClient: api, metadataStore: metadataStore, outbox: outbox, mediaCache: cache)
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        localStore?.connection.close()
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testCoordinatorRequiresPreviewConsentAndDecodesZeroOneAndManySuggestions() async throws {
        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer coordinator-token")
            switch request.url?.path {
            case "/api/v1/metadata/\(self.assetID)/provider":
                return Self.json(200, #"{"provider":"igdb","enabled":false,"revision":3,"disclosure_revision":"terms-3","query_preview":"Owner title","system":"gbc","credentials_ready":true,"attribution":"IGDB","terms_url":"https://example.test/terms","image_fetch_allowed":false,"cache_age_days":14}"#)
            case "/api/v1/metadata/\(self.assetID)/provider/consent":
                return StubURLProtocol.Stub(statusCode: 204, headers: [:], body: Data())
            case "/api/v1/metadata/\(self.assetID)/provider/search":
                let rows: [String]
                switch StubURLProtocol.requestLog.filter({ $0.url?.path.hasSuffix("/provider/search") == true }).count {
                case 1: rows = []
                case 2: rows = [Self.evidence("one", 90)]
                default: rows = [Self.evidence("two-a", 90), Self.evidence("two-b", 67), Self.evidence("two-c", 42)]
                }
                return Self.json(200, "{\"results\":[\(rows.joined(separator: ","))]}")
            default:
                return StubURLProtocol.Stub(statusCode: 404, headers: [:], body: Data())
            }
        }

        let preview = try await coordinator.preview(assetSetID: assetID)
        XCTAssertFalse(preview.enabled)
        XCTAssertTrue(preview.credentialsReady)
        XCTAssertEqual(preview.queryPreview, "Owner title")
        XCTAssertEqual(preview.system, "gbc")
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1, "preview is read-only and does not trigger provider search")

        try await coordinator.consent(assetSetID: assetID, preview: preview, enabled: true)
        XCTAssertEqual(StubURLProtocol.requestLog.count, 2)
        let consentBody = try XCTUnwrap(Self.body(StubURLProtocol.requestLog[1]))
        let consentPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: consentBody) as? [String: String])
        XCTAssertEqual(consentPayload, ["title": "Owner title", "system": "gbc", "disclosure_revision": "terms-3"])
        let zero = try await coordinator.search(assetSetID: assetID)
        XCTAssertTrue(zero.isEmpty)
        let one = try await coordinator.search(assetSetID: assetID)
        XCTAssertEqual(one.count, 1)
        let many = try await coordinator.search(assetSetID: assetID)
        XCTAssertEqual(many.count, 3)
        XCTAssertEqual(many.map(\.confidence), ["high", "medium", "low"])
        try await coordinator.consent(assetSetID: assetID, preview: preview, enabled: false)
        let requests = StubURLProtocol.requestLog
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(requests.last?.httpMethod, "DELETE")
        XCTAssertNil(requests.last.flatMap(Self.body))
    }

    func testPreviewPublishesCredentialReadinessAndChangedDisclosureRevision() async throws {
        StubURLProtocol.responder = { _ in
            let revision = StubURLProtocol.requestLog.count == 1 ? "terms-4" : "terms-5"
            let ready = revision == "terms-5" ? "false" : "true"
            return Self.json(200, #"{"provider":"igdb","enabled":false,"revision":4,"disclosure_revision":"\#(revision)","query_preview":"Owner title","system":"gbc","credentials_ready":\#(ready),"attribution":"IGDB","terms_url":"https://example.test/terms","image_fetch_allowed":false,"cache_age_days":14}"#)
        }
        let first = try await coordinator.preview(assetSetID: assetID)
        XCTAssertTrue(first.credentialsReady)
        XCTAssertEqual(first.disclosureRevision, "terms-4")
        let refreshed = try await coordinator.preview(assetSetID: assetID)
        XCTAssertFalse(refreshed.credentialsReady)
        XCTAssertEqual(refreshed.disclosureRevision, "terms-5")
        XCTAssertEqual(StubURLProtocol.requestLog.count, 2, "refreshing changed terms is preview-only and sends no provider search")
    }

    func testCoordinatorPreservesServerConsentRejectionWithoutCreatingCandidates() async throws {
        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/metadata/\(self.assetID)/provider/search")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer coordinator-token")
            return StubURLProtocol.Stub(statusCode: 403, headers: ["Content-Type": "application/problem+json"],
                                        body: Data(#"{"code":"provider_consent_required"}"#.utf8))
        }
        do {
            _ = try await coordinator.search(assetSetID: assetID)
            XCTFail("the server consent gate must prevent search results")
        } catch let APIClientError.server(problem) {
            XCTAssertEqual(problem.status, 403)
            XCTAssertEqual(problem.code, "provider_consent_required")
        }
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1)
    }

    func testHeldPreviewPublishesNoCompletedStateUntilAuthenticatedResponseArrives() async throws {
        let response = Data(#"{"provider":"igdb","enabled":false,"revision":3,"disclosure_revision":"terms-3","query_preview":"Owner title","system":"gbc","credentials_ready":true,"attribution":"IGDB","terms_url":"https://example.test/terms","image_fetch_allowed":false,"cache_age_days":14}"#.utf8)
        StubURLProtocol.responder = { _ in
            let chunkSize = max(1, response.count / 16)
            let chunks = stride(from: 0, to: response.count, by: chunkSize).map { offset in
                Data(response[offset..<min(offset + chunkSize, response.count)])
            }
            return StubURLProtocol.Stub(statusCode: 200, headers: ["Content-Type": "application/json"], bodyChunks: chunks, failAfter: false)
        }
        let completion = MetadataCompletionFlag()
        let request = Task {
            let value = try await coordinator.preview(assetSetID: assetID)
            await completion.markComplete()
            return value
        }
        let deadline = Date().addingTimeInterval(2)
        while StubURLProtocol.requestLog.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1)
        try await Task.sleep(for: .milliseconds(50))
        let completedWhileHeld = await completion.isComplete()
        XCTAssertFalse(completedWhileHeld, "the production coordinator must remain pending while the response body is held")
        let preview = try await request.value
        XCTAssertEqual(preview.queryPreview, "Owner title")
        let completedAfterResponse = await completion.isComplete()
        XCTAssertTrue(completedAfterResponse)
    }

    func testCoordinatorPreparationEstimateJobsCacheAndReclaimUseServerState() async throws {
        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer coordinator-token")
            switch request.url?.path {
            case "/api/v1/metadata/provider/enrichment/estimate":
                let payload = Self.object(request)
                XCTAssertEqual(payload["mode"] as? String, "minimal")
                XCTAssertEqual(payload["selected_asset_set_ids"] as? [String], [self.assetID, "asset-2"])
                return Self.json(200, #"{"mode":"minimal","requests":2,"bytes":1024,"storage":2048}"#)
            case "/api/v1/metadata/\(self.assetID)/provider/enrichment":
                let payload = Self.object(request)
                XCTAssertEqual(payload["mode"] as? String, "prepare")
                XCTAssertEqual(payload["profile_mode"] as? String, "minimal")
                XCTAssertEqual(payload["selected_asset_set_ids"] as? [String], [self.assetID])
                return Self.json(202, #"{"jobs":[{"id":"job-1","asset_set_id":"7C6C379B-8C15-4C17-BAF3-6D908620155B","state":"queued","progress":{"completed":0,"total":1}}]}"#)
            case "/api/v1/metadata/provider/enrichment/job-1" where request.httpMethod == "DELETE":
                return Self.json(200, #"{"id":"job-1","asset_set_id":"7C6C379B-8C15-4C17-BAF3-6D908620155B","state":"cancelled","progress":{"completed":1,"total":3}}"#)
            case "/api/v1/metadata/provider/enrichment/job-1":
                return Self.json(200, #"{"id":"job-1","asset_set_id":"7C6C379B-8C15-4C17-BAF3-6D908620155B","state":"running","progress":{"completed":1,"total":3}}"#)
            case "/api/v1/metadata/provider/cache":
                return Self.json(200, #"{"used_bytes":314,"budget_bytes":1073741824,"reclaimable_bytes":200}"#)
            case "/api/v1/metadata/provider/cache/reclaim":
                return Self.json(200, #"{"used_bytes":114,"budget_bytes":1073741824,"reclaimable_bytes":0}"#)
            default:
                return StubURLProtocol.Stub(statusCode: 404, headers: [:], body: Data())
            }
        }

        let estimate = try await coordinator.estimate(assetSetIDs: [assetID, "asset-2"], mode: "minimal")
        XCTAssertEqual(estimate.requests, 2)
        XCTAssertEqual(estimate.bytes, 1024)
        let jobs = try await coordinator.prepare(assetSetID: assetID, selectedIDs: [assetID], estimate: estimate)
        XCTAssertEqual(jobs.map(\.state), ["queued"])
        let running = try await coordinator.status(jobID: "job-1")
        XCTAssertEqual(running.state, "running")
        let cancelled = try await coordinator.cancel(jobID: "job-1")
        XCTAssertEqual(cancelled.state, "cancelled")
        let usage = try await coordinator.cacheSnapshot()
        XCTAssertEqual(usage.serverBudgetBytes, 1_073_741_824)
        XCTAssertEqual(usage.serverUsedBytes, 314)
        XCTAssertEqual(usage.serverReclaimableBytes, 200)
        try await coordinator.reclaimCache()
        XCTAssertEqual(StubURLProtocol.requestLog.last?.url?.path, "/api/v1/metadata/provider/cache/reclaim")
    }

    func testCoordinatorFieldSelectionAndProviderResetUpdateTheLocalMirrorByRevision() async throws {
        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer coordinator-token")
            let payload = Self.object(request)
            if request.url?.path.hasSuffix("/reset-provider") == true {
                XCTAssertEqual(payload["evidence_id"] as? String, "provider-evidence-9")
                XCTAssertEqual(payload["base_revision"] as? Int, 4)
                return Self.json(200, #"{"version":1,"type":"description","asset_set_id":"7C6C379B-8C15-4C17-BAF3-6D908620155B","revision":5,"field_revisions":{"description":5},"selections":{"description":"provider value"}}"#)
            }
            XCTAssertEqual(payload["field"] as? String, "description")
            XCTAssertEqual(payload["base_revision"] as? Int, 0)
            return Self.json(200, #"{"version":1,"type":"description","asset_set_id":"7C6C379B-8C15-4C17-BAF3-6D908620155B","revision":4,"field_revisions":{"description":4},"selections":{"description":"private edit"}}"#)
        }

        let chosen = try await coordinator.select(assetSetID: assetID, field: "description", value: .string("private edit"))
        XCTAssertEqual(chosen.revision, 4)
        XCTAssertEqual(coordinator.selection(assetSetID: assetID)?.fieldRevisions["description"], 4)
        let restored = try await coordinator.selectProviderEvidence(assetSetID: assetID, field: "description", evidenceID: "provider-evidence-9")
        XCTAssertEqual(restored.revision, 5)
        XCTAssertEqual(coordinator.selection(assetSetID: assetID)?.revision, 5)

        // An unrelated title revision must not make a first cover or
        // description mutation appear concurrent on the server.
        let titleOnly = MetadataSelection(version: 1, type: "description", assetSetID: assetID,
                                          description: "", revision: 9, deletedAt: nil,
                                          selections: ["title": .string("Existing title")],
                                          fieldRevisions: ["title": 9])
        try metadataStore.upsert(titleOnly)
        StubURLProtocol.responder = { request in
            let payload = Self.object(request)
            XCTAssertEqual(payload["base_revision"] as? Int, 0,
                           "a never-selected field starts at zero independently of the document revision")
            return Self.json(200, #"{"version":1,"type":"description","asset_set_id":"7C6C379B-8C15-4C17-BAF3-6D908620155B","revision":10,"field_revisions":{"title":9,"cover":10},"selections":{"title":"Existing title"}}"#)
        }
        _ = try await coordinator.select(assetSetID: assetID, field: "cover", value: .object(["media_id": .string("private-media")]))
        _ = try await coordinator.selectProviderEvidence(assetSetID: assetID, field: "description", evidenceID: "new-description")
    }

    private static func evidence(_ id: String, _ confidence: Int) -> String {
        let level = confidence >= 85 ? "high" : confidence >= 60 ? "medium" : "low"
        return #"{"id":"\#(id)","external_id":17,"title":"Fixture","system":"gbc","confidence":"\#(level)","match_kind":"title","provider":"igdb","attribution":"IGDB","terms_url":"https://example.test/terms"}"#
    }

    private static func json(_ status: Int, _ text: String) -> StubURLProtocol.Stub {
        StubURLProtocol.Stub(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(text.utf8))
    }

    private static func body(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private static func object(_ request: URLRequest) -> [String: Any] {
        guard let body = body(request),
              let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return value
    }
}

private actor MetadataCompletionFlag {
    private var complete = false
    func markComplete() { complete = true }
    func isComplete() -> Bool { complete }
}
