import XCTest
@testable import Playstead

final class MetadataOutboxTests: XCTestCase {
    private var root: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var metadataStore: MetadataStore!
    private var curationStore: CurationStore!
    private var outbox: Outbox!
    private var apiClient: APIClient!

    private let assetSetID = "7C6C379B-8C15-4C17-BAF3-6D908620155B"
    private let credential = PairingCredential(deviceID: "device-test", baseURL: URL(string: "https://sync.test")!, token: "test-token")

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: root)
        localStore = try LocalStore(paths: paths)
        metadataStore = MetadataStore(localStore: localStore)
        curationStore = CurationStore(localStore: localStore)
        outbox = Outbox(localStore: localStore, curationStore: curationStore, metadataStore: metadataStore)
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        localStore?.connection.close()
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testMetadataCorrectionIsOptimisticDurableAndReplaysWithStableIdempotencyKey() async throws {
        let entry = try outbox.setMetadata(assetSetID: assetSetID, field: "description", value: .string("Edited offline"))
        XCTAssertEqual(metadataStore.description(for: assetSetID), "Edited offline")
        XCTAssertEqual(entry.idempotencyKey, "metadata_correction:\(entry.id)")

        // A fresh store/outbox is the next process; it reconstructs the
        // complete request from SQLite before the network is available.
        let reopened = try LocalStore(paths: paths)
        let reopenedMetadata = MetadataStore(localStore: reopened)
        let reopenedOutbox = Outbox(
            localStore: reopened, curationStore: CurationStore(localStore: reopened), metadataStore: reopenedMetadata
        )
        XCTAssertEqual(reopenedOutbox.listPending().first?.idempotencyKey, entry.idempotencyKey)
        XCTAssertEqual(reopenedOutbox.listPending().first?.intent, entry.intent)

        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/metadata/\(self.assetSetID)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), entry.idempotencyKey)
            let body = try? JSONSerialization.jsonObject(with: self.bodyData(from: request)) as? [String: Any]
            XCTAssertEqual(body?["field"] as? String, "description")
            XCTAssertEqual(body?["value"] as? String, "Edited offline")
            XCTAssertEqual(body?["base_revision"] as? Int, 0)
            return StubURLProtocol.Stub(statusCode: 201, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }
        let result = await OutboxWorker(apiClient: apiClient, outbox: reopenedOutbox, metadataStore: reopenedMetadata).drainOnce()
        XCTAssertEqual(result.sent, 1)
        XCTAssertTrue(reopenedOutbox.listAll().isEmpty)
        XCTAssertEqual(reopenedMetadata.description(for: assetSetID), "Edited offline")
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1)

        try metadataStore.upsert(MetadataSelection(
            version: 1, type: "description", assetSetID: assetSetID, description: "",
            revision: 9, deletedAt: nil, selections: ["title": .string("Existing title")],
            fieldRevisions: ["title": 9]
        ))
        let newDescription = try outbox.setMetadata(assetSetID: assetSetID, field: "description", value: .string("First description"))
        XCTAssertEqual(newDescription.intent, .metadataCorrection(
            assetSetID: assetSetID, field: "description", value: .string("First description"), baseRevision: 0
        ), "an unrelated field must not supply a new field's base revision")

        let legacyAssetID = "7C6C379B-8C15-4C17-BAF3-6D908620155C"
        try metadataStore.upsert(MetadataSelection(version: 1, type: "description", assetSetID: legacyAssetID,
                                                 description: "Legacy description", revision: 6, deletedAt: nil))
        let legacyEdit = try outbox.setMetadata(assetSetID: legacyAssetID, field: "description", value: .string("Updated legacy description"))
        XCTAssertEqual(legacyEdit.intent, .metadataCorrection(
            assetSetID: legacyAssetID, field: "description", value: .string("Updated legacy description"), baseRevision: 6
        ), "the original description-only representation retains its revision")
        reopened.connection.close()
    }

    func testServerConflictKeepsBothAlternativesAndExplicitResolutionUsesCurrentRevision() async throws {
        try metadataStore.upsert(MetadataSelection(
            version: 1, type: "description", assetSetID: assetSetID, description: "base", revision: 1,
            deletedAt: nil, selections: ["description": .string("base")], fieldRevisions: ["description": 1]
        ))
        let edit = try outbox.setMetadata(assetSetID: assetSetID, field: "description", value: .string("mine"))
        try outbox.enqueue(.favoriteAdd(id: "later-favorite", assetSetID: assetSetID))
        StubURLProtocol.responder = { request in
            guard request.url?.path == "/api/v1/metadata/\(self.assetSetID)" else {
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8))
            }
            return StubURLProtocol.Stub(statusCode: 409, headers: ["Content-Type": "application/json"], body: Data("""
            {"type":"metadata_conflict","field":"description","base_revision":1,"current_revision":2,
             "current_alternative":{"value":"theirs","revision":2},
             "incoming_alternative":{"value":"mine","source":{"kind":"user"}}}
            """.utf8))
        }

        let worker = OutboxWorker(apiClient: apiClient, outbox: outbox, metadataStore: metadataStore)
        let conflictResult = await worker.drainOnce()
        XCTAssertEqual(conflictResult.conflicted, 1)
        XCTAssertEqual(outbox.listAll().first(where: { $0.id == edit.id })?.state, .conflicted)
        XCTAssertEqual(metadataStore.description(for: assetSetID), "theirs")
        let conflict = try XCTUnwrap(metadataStore.selection(for: assetSetID)?.conflicts.first)
        guard case .object(let fields) = conflict else { return XCTFail("expected typed conflict") }
        let currentAlternative = try XCTUnwrap(fields["current_alternative"]).decoded(as: [String: JSONValue].self)
        let incomingAlternative = try XCTUnwrap(fields["incoming_alternative"]).decoded(as: [String: JSONValue].self)
        XCTAssertEqual(currentAlternative["value"], .string("theirs"))
        XCTAssertEqual(incomingAlternative["value"], .string("mine"))

        let unrelated = await worker.drainOnce()
        XCTAssertEqual(unrelated.sent, 1, "an unresolved metadata conflict must not stop unrelated curation delivery")
        XCTAssertEqual(StubURLProtocol.requestLog.count, 2)

        _ = try outbox.setMetadata(assetSetID: assetSetID, field: "description", value: .string("resolved by owner"))
        XCTAssertTrue(metadataStore.selection(for: assetSetID)?.conflicts.isEmpty ?? false)
        XCTAssertEqual(outbox.listAll().first(where: { $0.id == edit.id })?.state, .rejected)
        StubURLProtocol.responder = { request in
            if request.url?.path == "/api/v1/metadata/\(self.assetSetID)" {
                let body = try? JSONSerialization.jsonObject(with: self.bodyData(from: request)) as? [String: Any]
                XCTAssertEqual(body?["base_revision"] as? Int, 2)
                XCTAssertEqual(body?["value"] as? String, "resolved by owner")
                return StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8))
            }
            return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8))
        }
        let resolved = await worker.drainOnce()
        XCTAssertEqual(resolved.sent, 1)
        XCTAssertEqual(outbox.listUnresolved().count, 0)
    }

    func testJournalPageRollbackAndResetPreserveLocalCacheState() throws {
        enum ExpectedFailure: Error { case rollback }
        let cursor = CursorStore(localStore: localStore)
        try localStore.connection.execute("INSERT INTO cache_objects (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms) VALUES ('local-cache', 3, '2026-10-12T00:00:00Z', '2026-10-12T00:00:00Z', 3, 1, 1);")

        XCTAssertThrowsError(try localStore.transaction {
            try metadataStore.upsert(try JSONDecoder().decode(MetadataSelection.self, from: Data(#"{"version":1,"type":"description","asset_set_id":"asset-1","description":"Page value","revision":5,"selections":{"description":"Page value"},"field_revisions":{"description":5},"deleted_at":null}"#.utf8)))
            try cursor.store(OpaqueCursor(rawValue: "must-roll-back"), syncedAt: Date())
            throw ExpectedFailure.rollback
        })
        XCTAssertNil(metadataStore.selection(for: "asset-1"))
        XCTAssertNil(cursor.load())
        XCTAssertEqual(try localStore.connection.query("SELECT sha256 FROM cache_objects;") { $0.string(0) }, ["local-cache"])

        try metadataStore.upsert(try JSONDecoder().decode(MetadataSelection.self, from: Data(#"{"version":1,"type":"description","asset_set_id":"asset-1","description":"Server value","revision":6,"deleted_at":null}"#.utf8)))
        try localStore.transaction {
            try metadataStore.clearAll()
            try metadataStore.upsert(try JSONDecoder().decode(MetadataSelection.self, from: Data(#"{"version":1,"type":"description","asset_set_id":"asset-2","description":"Reset value","revision":7,"deleted_at":null}"#.utf8)))
            try cursor.store(OpaqueCursor(rawValue: "reset-cursor"), syncedAt: Date())
        }
        XCTAssertNil(metadataStore.selection(for: "asset-1"))
        XCTAssertEqual(metadataStore.description(for: "asset-2"), "Reset value")
        XCTAssertEqual(cursor.load(), OpaqueCursor(rawValue: "reset-cursor"))
        XCTAssertEqual(try localStore.connection.query("SELECT sha256 FROM cache_objects;") { $0.string(0) }, ["local-cache"])
    }

    private func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
