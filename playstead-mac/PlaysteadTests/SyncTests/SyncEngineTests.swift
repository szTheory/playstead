import XCTest
@testable import Playstead

/// Covers every bullet of plan 03-06 task 1's `<behavior>` block against
/// `CacheTests/StubURLProtocol` (reused across the `PlaysteadTests`
/// target rather than duplicated) — no live server, no real Keychain
/// (`APIClient`'s injected `credential`/`session` overrides added in this
/// plan exist specifically so this suite can run headless).
final class SyncEngineTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var apiClient: APIClient!

    private let credential = PairingCredential(
        deviceID: "device-1",
        baseURL: URL(string: "https://sync.test")!,
        token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func makeEngine() -> SyncEngine {
        SyncEngine(apiClient: apiClient, localStore: localStore)
    }

    // MARK: - Fixture builders

    private func catalogueEntryJSON(id: String, title: String) -> String {
        """
        {"id":"\(id)","system":"gba","display_title":"\(title)","tags":{},"members":[]}
        """
    }

    private func snapshotResponseJSON(
        catalogue: [String],
        curation: [String],
        cursor: String,
        hasMore: Bool,
        nextAfterID: String?
    ) -> Data {
        let catalogueJSON = "[" + catalogue.joined(separator: ",") + "]"
        let curationJSON = "[" + curation.joined(separator: ",") + "]"
        let nextAfterField = nextAfterID.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "entries": [],
          "cursor": "\(cursor)",
          "has_more": \(hasMore),
          "next_after_id": \(nextAfterField),
          "catalogue": \(catalogueJSON),
          "job": [],
          "curation": \(curationJSON)
        }
        """
        return Data(json.utf8)
    }

    private func changesPageJSON(entries: [String], cursor: String, hasMore: Bool) -> Data {
        let entriesJSON = "[" + entries.joined(separator: ",") + "]"
        return Data("""
        {"entries": \(entriesJSON), "cursor": "\(cursor)", "has_more": \(hasMore)}
        """.utf8)
    }

    private func journalEntryJSON(kind: String, id: String, op: String, payload: String) -> String {
        """
        {"entity_kind":"\(kind)","entity_id":"\(id)","operation":"\(op)","payload":\(payload)}
        """
    }

    private func problemJSON(code: String) -> Data {
        Data("""
        {"type":"about:blank","title":"error","status":410,"detail":"expired","code":"\(code)"}
        """.utf8)
    }

    private func makePayload(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    // MARK: - Bootstrap from an empty store

    func testBootstrapFromEmptyStoreWritesCatalogueAndCurationAndStoresCursor() async throws {
        let catalogueRow = catalogueEntryJSON(id: "game-1", title: "Game One")
        let favoriteRow = """
        {"type":"favorite","asset_set_id":"game-1","created_at":"2026-01-01T00:00:00Z"}
        """

        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/snapshot")
            return StubURLProtocol.Stub(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.snapshotResponseJSON(
                    catalogue: [catalogueRow], curation: [favoriteRow], cursor: "CUR1", hasMore: false, nextAfterID: nil
                )
            )
        }

        let engine = makeEngine()
        await engine.syncNow()

        guard case .synced = await engine.state else {
            return XCTFail("expected .synced after a successful bootstrap")
        }

        let catalogueStore = CatalogueStore(localStore: localStore)
        XCTAssertEqual(catalogueStore.count(), 1)
        XCTAssertEqual(catalogueStore.fetchAll().first?.id, "game-1")

        let curationStore = CurationStore(localStore: localStore)
        XCTAssertEqual(curationStore.fetchFavorites().count, 1)
        XCTAssertEqual(curationStore.fetchFavorites().first?.assetSetID, "game-1")

        XCTAssertEqual(CursorStore(localStore: localStore).load()?.rawValue, "CUR1")
    }

    func testMultiPageSnapshotContinuesFromMarkerUntilExhausted() async throws {
        var callCount = 0

        StubURLProtocol.responder = { request in
            callCount += 1
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let afterID = items.first(where: { $0.name == "after_id" })?.value

            if afterID == nil {
                return StubURLProtocol.Stub(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: self.snapshotResponseJSON(
                        catalogue: [self.catalogueEntryJSON(id: "game-1", title: "Game One")],
                        curation: [],
                        cursor: "PINNED",
                        hasMore: true,
                        nextAfterID: "device-marker"
                    )
                )
            }

            XCTAssertEqual(afterID, "device-marker")
            XCTAssertEqual(items.first(where: { $0.name == "cursor" })?.value, "PINNED")
            return StubURLProtocol.Stub(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.snapshotResponseJSON(
                    catalogue: [self.catalogueEntryJSON(id: "game-2", title: "Game Two")],
                    curation: [],
                    cursor: "PINNED",
                    hasMore: false,
                    nextAfterID: nil
                )
            )
        }

        let engine = makeEngine()
        await engine.syncNow()

        XCTAssertEqual(callCount, 2)
        let catalogueStore = CatalogueStore(localStore: localStore)
        XCTAssertEqual(catalogueStore.count(), 2)
        XCTAssertEqual(Set(catalogueStore.fetchAll().map(\.id)), Set(["game-1", "game-2"]))
    }

    // MARK: - Resumed sync

    func testResumedSyncAppliesOnlyChangesAfterStoredCursorAndNeverRefetchesSnapshot() async throws {
        let cursorStore = CursorStore(localStore: localStore)
        try cursorStore.store(OpaqueCursor(rawValue: "CUR1"), syncedAt: Date())

        var snapshotWasCalled = false
        StubURLProtocol.responder = { request in
            if request.url?.path == "/api/v1/snapshot" {
                snapshotWasCalled = true
                return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/v1/changes")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(items.first(where: { $0.name == "cursor" })?.value, "CUR1")

            let entry = self.journalEntryJSON(
                kind: "catalogue", id: "game-2", op: "upsert",
                payload: self.catalogueEntryJSON(id: "game-2", title: "Game Two")
            )
            return StubURLProtocol.Stub(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.changesPageJSON(entries: [entry], cursor: "CUR2", hasMore: false)
            )
        }

        let engine = makeEngine()
        await engine.syncNow()

        XCTAssertFalse(snapshotWasCalled)
        XCTAssertEqual(CatalogueStore(localStore: localStore).count(), 1)
        XCTAssertEqual(cursorStore.load()?.rawValue, "CUR2")
    }

    // MARK: - Upsert / tombstone mechanics (direct JournalApplier)

    func testUpsertInsertsAndTombstoneDeletes() throws {
        let catalogueStore = CatalogueStore(localStore: localStore)
        let curationStore = CurationStore(localStore: localStore)
        let applier = JournalApplier(catalogueStore: catalogueStore, curationStore: curationStore)

        let upsert = JournalEntry(
            entityKind: "catalogue", entityID: "game-1", operation: "upsert",
            payload: try makePayload(catalogueEntryJSON(id: "game-1", title: "Game One"))
        )
        applier.apply([upsert])
        XCTAssertEqual(catalogueStore.count(), 1)

        let tombstone = JournalEntry(entityKind: "catalogue", entityID: "game-1", operation: "tombstone", payload: .object([:]))
        applier.apply([tombstone])
        XCTAssertEqual(catalogueStore.count(), 0)
    }

    func testApplyingSameEntryTwiceLeavesRowCountAndContentsUnchanged() throws {
        let catalogueStore = CatalogueStore(localStore: localStore)
        let curationStore = CurationStore(localStore: localStore)
        let applier = JournalApplier(catalogueStore: catalogueStore, curationStore: curationStore)

        let entry = JournalEntry(
            entityKind: "catalogue", entityID: "game-1", operation: "upsert",
            payload: try makePayload(catalogueEntryJSON(id: "game-1", title: "Game One"))
        )

        applier.apply([entry])
        let firstFetch = catalogueStore.fetchAll()
        applier.apply([entry])
        let secondFetch = catalogueStore.fetchAll()

        XCTAssertEqual(catalogueStore.count(), 1)
        XCTAssertEqual(firstFetch, secondFetch)
    }

    func testUnknownEntityKindIsSkippedAndRestOfPageStillApplies() throws {
        let catalogueStore = CatalogueStore(localStore: localStore)
        let curationStore = CurationStore(localStore: localStore)
        let applier = JournalApplier(catalogueStore: catalogueStore, curationStore: curationStore)

        let unknown = JournalEntry(entityKind: "transfer", entityID: "x", operation: "upsert", payload: .object([:]))
        let known = JournalEntry(
            entityKind: "catalogue", entityID: "game-1", operation: "upsert",
            payload: try makePayload(catalogueEntryJSON(id: "game-1", title: "Game One"))
        )

        let result = applier.apply([unknown, known])
        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(catalogueStore.count(), 1)
    }

    func testApplyingIdenticalPageTwiceProducesIdenticalTableContents() throws {
        let catalogueStore = CatalogueStore(localStore: localStore)
        let curationStore = CurationStore(localStore: localStore)
        let applier = JournalApplier(catalogueStore: catalogueStore, curationStore: curationStore)

        let page = [
            JournalEntry(
                entityKind: "catalogue", entityID: "game-1", operation: "upsert",
                payload: try makePayload(catalogueEntryJSON(id: "game-1", title: "Game One"))
            ),
            JournalEntry(
                entityKind: "curation", entityID: "fav-1", operation: "upsert",
                payload: try makePayload(#"{"type":"favorite","asset_set_id":"game-1","created_at":null}"#)
            )
        ]

        applier.apply(page)
        let firstCatalogue = catalogueStore.fetchAll()
        let firstFavorites = curationStore.fetchFavorites()

        applier.apply(page)
        XCTAssertEqual(catalogueStore.fetchAll(), firstCatalogue)
        XCTAssertEqual(curationStore.fetchFavorites(), firstFavorites)
    }

    // MARK: - Cursor-expired reset

    func testCursorExpiredResetsToFreshSnapshotWithNoDuplicateRows() async throws {
        let cursorStore = CursorStore(localStore: localStore)
        try cursorStore.store(OpaqueCursor(rawValue: "STALE"), syncedAt: Date())

        // Pre-seed a row the fresh snapshot does NOT include, to prove
        // the reset clears the read model rather than merging into it.
        let catalogueStore = CatalogueStore(localStore: localStore)
        try catalogueStore.upsert(try makePayload(catalogueEntryJSON(id: "stale-game", title: "Stale")).decoded(as: CatalogueEntry.self))

        var changesCallCount = 0
        StubURLProtocol.responder = { request in
            if request.url?.path == "/api/v1/changes" {
                changesCallCount += 1
                return StubURLProtocol.Stub(
                    statusCode: 410,
                    headers: ["Content-Type": "application/json"],
                    body: self.problemJSON(code: "cursor_expired")
                )
            }
            XCTAssertEqual(request.url?.path, "/api/v1/snapshot")
            return StubURLProtocol.Stub(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.snapshotResponseJSON(
                    catalogue: [self.catalogueEntryJSON(id: "game-1", title: "Game One")],
                    curation: [], cursor: "FRESH", hasMore: false, nextAfterID: nil
                )
            )
        }

        let engine = makeEngine()
        await engine.syncNow()

        XCTAssertEqual(changesCallCount, 1)
        let rows = catalogueStore.fetchAll()
        XCTAssertEqual(rows.count, 1, "expected exactly the snapshot's row set with no duplicates")
        XCTAssertEqual(rows.first?.id, "game-1")
        XCTAssertEqual(cursorStore.load()?.rawValue, "FRESH")

        guard case .synced = await engine.state else {
            return XCTFail("expected .synced after a successful reset")
        }
    }

    // MARK: - Transport failure leaves cursor and read model intact

    func testTransportFailureLeavesStoredCursorByteIdenticalAndReadModelIntact() async throws {
        let cursorStore = CursorStore(localStore: localStore)
        try cursorStore.store(OpaqueCursor(rawValue: "CUR1"), syncedAt: Date())

        let catalogueStore = CatalogueStore(localStore: localStore)
        try catalogueStore.upsert(try makePayload(catalogueEntryJSON(id: "game-1", title: "Game One")).decoded(as: CatalogueEntry.self))

        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: [:], bodyChunks: [], failAfter: true)
        }

        let engine = makeEngine()
        await engine.syncNow()

        XCTAssertEqual(cursorStore.load()?.rawValue, "CUR1")
        XCTAssertEqual(catalogueStore.fetchAll().map(\.id), ["game-1"])

        guard case .offline = await engine.state else {
            return XCTFail("being offline must read as a normal state, not a bare failure")
        }
    }

    // MARK: - CursorStore opacity and round-trip

    func testCursorStoreRoundTripsByteIdentically() throws {
        let cursorStore = CursorStore(localStore: localStore)
        let original = OpaqueCursor(rawValue: "AAAAAAAAAAA.some-signed-opaque-tag==")

        try cursorStore.store(original, syncedAt: Date())
        let loaded = cursorStore.load()

        XCTAssertEqual(loaded, original)
    }

    func testCursorStoreLoadIsNilBeforeAnyStore() {
        XCTAssertNil(CursorStore(localStore: localStore).load())
    }
}
