import XCTest
import Observation
@testable import Playstead

final class MetadataTracerTests: XCTestCase {
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var metadataStore: MetadataStore!

    override func setUpWithError() throws {
        paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        localStore = try LocalStore(paths: paths)
        metadataStore = MetadataStore(localStore: localStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.root)
    }

    @MainActor
    func testSQLiteTransactionNotificationDoesNotWaitForMainActor() async throws {
        let store = try XCTUnwrap(localStore)
        let environment = AppEnvironment(
            uiTestingPaths: paths, localStore: store,
            reachability: Reachability(startOnline: false, monitorAutomatically: false),
            biosReferences: [], controllerInputSource: FakeControllerInputSource()
        )
        environment.blockExternalIOForUITesting()
        let refreshed = expectation(description: "the production environment observes the committed store")
        withObservationTracking {
            _ = environment.metadataRefreshVersion
        } onChange: {
            refreshed.fulfill()
        }
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { completed.signal() }
            do {
                try store.transaction { try MetadataStore(localStore: store).clearAll() }
            } catch {
                XCTFail("metadata transaction failed: \(error)")
            }
        }
        // Deliberately hold the main actor for a bounded interval. Publishing
        // inside SQLite must finish without synchronously dispatching here.
        XCTAssertEqual(completed.wait(timeout: .now() + 0.5), .success,
                       "a SQLite transaction must not wait for the rendering main actor")
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertGreaterThan(environment.metadataRefreshVersion, 0)
    }

    func testDescriptionJournalAndCursorCommitTogetherAndReplayIsStable() throws {
        let catalogue = CatalogueStore(localStore: localStore)
        try catalogue.upsert(CatalogueEntry(id: "asset-1", system: "gba", displayTitle: "Sentinel", tags: [:], members: []))
        try localStore.connection.execute("INSERT INTO save_line (id, content_key, save_kind, slot) VALUES ('save-line-1', 'game-digest', 'battery', '0');")
        try localStore.connection.execute("INSERT INTO save_revision (id, save_line_id, blob_sha256, size_bytes) VALUES ('save-revision-1', 'save-line-1', 'save-digest', 3);")
        let applier = JournalApplier(
            catalogueStore: catalogue,
            curationStore: CurationStore(localStore: localStore),
            metadataStore: metadataStore
        )
        let entry = try JSONDecoder().decode(JournalEntry.self, from: Data(#"{"entity_kind":"metadata","entity_id":"asset-1","operation":"upsert","payload":{"version":1,"type":"description","asset_set_id":"asset-1","description":"Authored privately","revision":1,"deleted_at":null}}"#.utf8))
        let cursorStore = CursorStore(localStore: localStore)

        try localStore.transaction {
            XCTAssertEqual(applier.apply([entry]).appliedCount, 1)
            try cursorStore.store(OpaqueCursor(rawValue: "cursor-1"), syncedAt: Date(timeIntervalSince1970: 1))
        }

        XCTAssertEqual(metadataStore.description(for: "asset-1"), "Authored privately")
        XCTAssertEqual(cursorStore.load(), OpaqueCursor(rawValue: "cursor-1"))
        XCTAssertEqual(applier.apply([entry]).appliedCount, 1)
        XCTAssertEqual(metadataStore.description(for: "asset-1"), "Authored privately")
        XCTAssertEqual(catalogue.fetchAll().map(\.id), ["asset-1"])
        XCTAssertEqual(try localStore.connection.query("SELECT id FROM save_line;") { $0.string(0) }, ["save-line-1"])
        XCTAssertEqual(try localStore.connection.query("SELECT id FROM save_revision;") { $0.string(0) }, ["save-revision-1"])
    }

    func testMetadataAndCursorRollbackTogetherWhenPageApplyFails() throws {
        enum ExpectedFailure: Error { case rollback }
        let cursorStore = CursorStore(localStore: localStore)
        XCTAssertThrowsError(try localStore.transaction {
            try metadataStore.upsert(MetadataSelection(
                version: 1, type: "description", assetSetID: "asset-rollback",
                description: "Must not commit", revision: 1, deletedAt: nil
            ))
            try cursorStore.store(OpaqueCursor(rawValue: "cursor-rollback"), syncedAt: Date())
            throw ExpectedFailure.rollback
        })
        XCTAssertNil(metadataStore.description(for: "asset-rollback"))
        XCTAssertNil(cursorStore.load())
    }

    func testSnapshotResetRebuildsMetadataAndLegacySnapshotMayOmitBranch() throws {
        let data = Data(#"{"metadata":[{"version":1,"type":"description","asset_set_id":"asset-2","description":"Snapshot text","revision":2,"deleted_at":null}],"cursor":"c","has_more":false,"catalogue":[],"curation":[]}"#.utf8)
        let selections = try JSONDecoder().decode(MetadataSnapshotFixture.self, from: data)
        let applier = JournalApplier(
            catalogueStore: CatalogueStore(localStore: localStore),
            curationStore: CurationStore(localStore: localStore),
            metadataStore: metadataStore
        )

        try localStore.transaction {
            try metadataStore.clearAll()
            XCTAssertEqual(applier.apply(MetadataAPI.snapshotSelections(from: selections.metadata)).appliedCount, 1)
        }
        XCTAssertEqual(metadataStore.description(for: "asset-2"), "Snapshot text")
        XCTAssertNil(metadataStore.description(for: "asset-1"))
        let legacy = try JSONDecoder().decode(MetadataSnapshotFixture.self, from: Data(#"{"cursor":"old","has_more":false,"catalogue":[],"curation":[]}"#.utf8))
        XCTAssertTrue(legacy.metadata.isEmpty)

        let olderClient = JournalApplier(
            catalogueStore: CatalogueStore(localStore: localStore),
            curationStore: CurationStore(localStore: localStore)
        )
        let unknownEntry = try JSONDecoder().decode(JournalEntry.self, from: Data(#"{"entity_kind":"metadata","entity_id":"asset-2","operation":"upsert","payload":{"version":1,"type":"description","asset_set_id":"asset-2","description":"Snapshot text","revision":2,"deleted_at":null}}"#.utf8))
        XCTAssertEqual(olderClient.apply([unknownEntry]).skippedCount, 1)
    }
}

private struct MetadataSnapshotFixture: Decodable {
    let metadata: [JSONValue]
    private enum CodingKeys: String, CodingKey { case metadata }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decodeIfPresent([JSONValue].self, forKey: .metadata) ?? []
    }
}
