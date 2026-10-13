import XCTest
@testable import Playstead

final class MetadataJournalTests: XCTestCase {
    func testJournalMirrorRetainsSelectionsEvidenceConflictsAndTombstones() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let localStore = try LocalStore(paths: AppPaths(root: root))
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MetadataStore(localStore: localStore)
        let payload = #"{"version":1,"type":"description","asset_set_id":"asset-1","description":"A corrected title","revision":8,"deleted_at":null,"selections":{"title":"A corrected title","cover":{"media_id":"cover-1"}},"field_revisions":{"title":8},"field_sources":{"title":{"kind":"user"}},"deleted_fields":{},"conflicts":[{"field":"title","current_alternative":"North","incoming_alternative":"South"}],"evidence":{"title":[{"provider":"fixture","confidence":0.92}]}}"#
        let entry = try JSONDecoder().decode(JournalEntry.self, from: Data("{\"entity_kind\":\"metadata\",\"entity_id\":\"asset-1\",\"operation\":\"upsert\",\"payload\":\(payload)}".utf8))
        let applier = JournalApplier(catalogueStore: CatalogueStore(localStore: localStore), curationStore: CurationStore(localStore: localStore), metadataStore: store)
        XCTAssertEqual(applier.apply([entry]).appliedCount, 1)
        let selection = try XCTUnwrap(store.selection(for: "asset-1"))
        XCTAssertEqual(selection.fieldRevisions["title"], 8)
        XCTAssertEqual(selection.conflicts.count, 1)
        XCTAssertEqual(selection.evidence["title"], .array([.object(["provider": .string("fixture"), "confidence": .number(0.92)])]))
        XCTAssertEqual(selection.selections["cover"], .object(["media_id": .string("cover-1")]))

        let tombstonePayload = payload.replacingOccurrences(of: "\"deleted_at\":null", with: "\"deleted_at\":\"2026-10-12T00:00:00Z\"")
        let tombstone = try JSONDecoder().decode(MetadataSelection.self, from: Data(tombstonePayload.utf8))
        try store.upsert(tombstone)
        XCTAssertNil(store.description(for: "asset-1"))
        XCTAssertNotNil(store.selection(for: "asset-1"))
    }
}
