import XCTest
@testable import Playstead

/// WR-01 (04-REVIEW.md / 04-17-PLAN.md task 2): `JournalApplier.applySave`
/// builds its upsert row from `SavePayload` alone, which carries none of
/// `tier`/`origin`/`manifestDigest`/`sessionID`/`artifactSetJSON` -- the
/// server never learns these, they are local capture facts. Before this
/// fix, `SaveStore.insertRevision`'s `ON CONFLICT DO UPDATE` wrote every
/// column unconditionally, so echoing back a revision this Mac already
/// authored (a normal poll/sync occurrence, not an edge case) silently
/// reset those five columns to their defaults -- desyncing
/// `SaveSessionRecovery`'s staged/promoted pairing. These tests exercise
/// the fixed contract: an echo of a self-authored revision preserves the
/// existing local-only columns, a genuinely new revision still gets
/// whatever the entry carries (nothing to preserve), server-owned
/// columns still update from the journal, and `SaveSessionRecovery`'s
/// pairing survives a full round-trip of its own revisions.
final class JournalRevisionMergeTests: XCTestCase {
    private var tempRoot: URL!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!
    private var applier: JournalApplier!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        saveStore = SaveStore(localStore: localStore)
        applier = JournalApplier(
            catalogueStore: CatalogueStore(localStore: localStore),
            curationStore: CurationStore(localStore: localStore),
            saveStore: saveStore
        )
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makePayload(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    /// Matches `Playstead.Sync.SavePayload.build/2`'s frozen key set --
    /// deliberately never includes tier/origin/manifestDigest/sessionID/
    /// artifactSetJSON, since the server never carries them.
    private func savePayloadJSON(
        revisionID: String, lineID: String, contentKey: String, saveKind: String = "battery", slot: String = "0",
        blobSHA256: String
    ) -> String {
        """
        {
            "revision_id": "\(revisionID)",
            "save_line_id": "\(lineID)",
            "content_key": "\(contentKey)",
            "save_kind": "\(saveKind)",
            "slot": "\(slot)",
            "parent_revision_id": null,
            "blob_sha256": "\(blobSHA256)",
            "size_bytes": 64,
            "origin_device_id": null,
            "device_captured_at": null,
            "recorded_at": "2026-01-01T00:00:00Z",
            "capture_method": "poll",
            "adapter_id": "mgba",
            "adapter_version": "1.0",
            "save_format": "sram",
            "format_confidence": "exact",
            "play_session_id": null
        }
        """
    }

    private func saveEntry(revisionID: String, lineID: String, contentKey: String, blobSHA256: String) throws -> JournalEntry {
        JournalEntry(
            entityKind: "save", entityID: revisionID, operation: "upsert",
            payload: try makePayload(
                savePayloadJSON(revisionID: revisionID, lineID: lineID, contentKey: contentKey, blobSHA256: blobSHA256)
            )
        )
    }

    private func localRevisionRow(
        id: String, lineID: String, blobSHA256: String, tier: SaveCaptureTier, origin: SaveCaptureOrigin,
        manifestDigest: String?, sessionID: String?, artifactSetJSON: String?
    ) -> SaveRevisionRow {
        SaveRevisionRow(
            id: id, saveLineID: lineID, parentRevisionID: nil, blobSHA256: blobSHA256, sizeBytes: 64,
            originDeviceID: "device-1", deviceCapturedAt: nil, recordedAt: nil, captureMethod: "poll",
            adapterID: "mgba", adapterVersion: "1.0", saveFormat: "sram", formatConfidence: "exact",
            playSessionID: sessionID, durability: SaveDurability.localOnly.rawValue, localPath: "/tmp/\(id).sav",
            tier: tier.rawValue, origin: origin.rawValue, manifestDigest: manifestDigest, sessionID: sessionID,
            artifactSetJSON: artifactSetJSON
        )
    }

    @discardableResult
    private func makeLine(contentKey: String, saveKind: String = "battery", slot: String = "0") throws -> String {
        let lineID = UUID().uuidString
        return try saveStore.resolveLine(contentKey: contentKey, saveKind: saveKind, slot: slot, placeholderID: lineID).id
    }

    // MARK: - 1. All five local-only columns survive an echo carrying nulls (the baseline/external case).

    func test_journalEcho_ofSelfAuthoredBaselineRevision_preservesAllFiveLocalOnlyColumns() throws {
        let contentKey = "content-key-1"
        let lineID = try makeLine(contentKey: contentKey)
        let revisionID = UUID().uuidString

        try saveStore.insertRevision(localRevisionRow(
            id: revisionID, lineID: lineID, blobSHA256: "abc123", tier: .baseline, origin: .external,
            manifestDigest: "manifest-digest-1", sessionID: "session-1", artifactSetJSON: "{\"entries\":[]}"
        ))

        let entry = try saveEntry(revisionID: revisionID, lineID: lineID, contentKey: contentKey, blobSHA256: "abc123")
        let result = applier.apply([entry])
        XCTAssertEqual(result.appliedCount, 1)

        let echoed = try XCTUnwrap(saveStore.fetchRevision(id: revisionID))
        XCTAssertEqual(echoed.tier, SaveCaptureTier.baseline.rawValue, "tier must survive the echo, not reset to the applier's promoted default")
        XCTAssertEqual(echoed.origin, SaveCaptureOrigin.external.rawValue, "origin must survive the echo, not flip to the applier's session default")
        XCTAssertEqual(echoed.manifestDigest, "manifest-digest-1")
        XCTAssertEqual(echoed.sessionID, "session-1")
        XCTAssertEqual(echoed.artifactSetJSON, "{\"entries\":[]}")
    }

    // MARK: - 2. Tier/origin also survive for the ordinary promoted/session case.

    func test_journalEcho_ofSelfAuthoredPromotedRevision_preservesTierAndOrigin() throws {
        let contentKey = "content-key-2"
        let lineID = try makeLine(contentKey: contentKey)
        let revisionID = UUID().uuidString

        try saveStore.insertRevision(localRevisionRow(
            id: revisionID, lineID: lineID, blobSHA256: "def456", tier: .promoted, origin: .session,
            manifestDigest: "manifest-digest-2", sessionID: "session-2", artifactSetJSON: "{}"
        ))

        let entry = try saveEntry(revisionID: revisionID, lineID: lineID, contentKey: contentKey, blobSHA256: "def456")
        _ = applier.apply([entry])

        let echoed = try XCTUnwrap(saveStore.fetchRevision(id: revisionID))
        XCTAssertEqual(echoed.tier, SaveCaptureTier.promoted.rawValue)
        XCTAssertEqual(echoed.origin, SaveCaptureOrigin.session.rawValue)
        XCTAssertEqual(echoed.sessionID, "session-2")
    }

    // MARK: - 3. A revision this device has never seen inserts with whatever the entry carries -- nothing local to preserve.

    func test_journalEcho_ofNeverSeenRevision_insertsWithDefaultsForLocalOnlyColumns() throws {
        let contentKey = "content-key-3"
        let lineID = try makeLine(contentKey: contentKey)
        let revisionID = UUID().uuidString

        let entry = try saveEntry(revisionID: revisionID, lineID: lineID, contentKey: contentKey, blobSHA256: "ghi789")
        let result = applier.apply([entry])
        XCTAssertEqual(result.appliedCount, 1)

        let inserted = try XCTUnwrap(saveStore.fetchRevision(id: revisionID))
        XCTAssertEqual(inserted.tier, SaveCaptureTier.promoted.rawValue)
        XCTAssertEqual(inserted.origin, SaveCaptureOrigin.session.rawValue)
        XCTAssertNil(inserted.manifestDigest)
        XCTAssertNil(inserted.sessionID)
        XCTAssertNil(inserted.artifactSetJSON)
    }

    // MARK: - 4. Server-owned columns still update from the journal while local-only columns are preserved.

    func test_journalEcho_stillUpdatesServerOwnedColumns_whilePreservingLocalOnlyColumns() throws {
        let contentKey = "content-key-4"
        let lineID = try makeLine(contentKey: contentKey)
        let revisionID = UUID().uuidString

        try saveStore.insertRevision(localRevisionRow(
            id: revisionID, lineID: lineID, blobSHA256: "jkl012", tier: .promoted, origin: .session,
            manifestDigest: "manifest-digest-4", sessionID: "session-4", artifactSetJSON: "{}"
        ))
        XCTAssertEqual(saveStore.fetchRevision(id: revisionID)?.durability, SaveDurability.localOnly.rawValue)

        let entry = try saveEntry(revisionID: revisionID, lineID: lineID, contentKey: contentKey, blobSHA256: "jkl012")
        _ = applier.apply([entry])

        let echoed = try XCTUnwrap(saveStore.fetchRevision(id: revisionID))
        XCTAssertEqual(echoed.durability, SaveDurability.uploaded.rawValue, "durability is server-derived and must still update to uploaded on echo")
        XCTAssertEqual(echoed.sessionID, "session-4", "the local-only column must survive alongside the server-owned update")
    }

    // MARK: - 5. SaveSessionRecovery's staged/promoted pairing survives a full journal round-trip.

    func test_sessionRecoveryPairing_survivesJournalEchoRoundTrip() async throws {
        let contentKey = "content-key-5"
        let lineID = try makeLine(contentKey: contentKey)
        let sessionID = "session-5"

        let stagedID = UUID().uuidString
        try saveStore.insertRevision(localRevisionRow(
            id: stagedID, lineID: lineID, blobSHA256: "staged-digest", tier: .staged, origin: .session,
            manifestDigest: nil, sessionID: sessionID, artifactSetJSON: nil
        ))

        let promotedID = UUID().uuidString
        try saveStore.insertRevision(localRevisionRow(
            id: promotedID, lineID: lineID, blobSHA256: "promoted-digest", tier: .promoted, origin: .session,
            manifestDigest: nil, sessionID: sessionID, artifactSetJSON: nil
        ))

        let recovery = SaveSessionRecovery(saveStore: saveStore)
        let before = await recovery.abandonedSessionIDs(saveLineID: lineID)
        XCTAssertFalse(before.contains(sessionID), "precondition: the session is already paired before any journal echo")

        // Echo the promoted revision back through the journal, exactly as
        // a poll/sync loop does once this device uploads it.
        let entry = try saveEntry(revisionID: promotedID, lineID: lineID, contentKey: contentKey, blobSHA256: "promoted-digest")
        _ = applier.apply([entry])

        let after = await recovery.abandonedSessionIDs(saveLineID: lineID)
        XCTAssertFalse(
            after.contains(sessionID),
            "the promoted row's sessionID must survive the echo, or recovery wrongly re-treats this session as abandoned"
        )
        XCTAssertEqual(saveStore.fetchRevision(id: promotedID)?.sessionID, sessionID)
    }

    // MARK: - 6. Repeated echoes are idempotent and never progressively degrade local-only columns.

    func test_repeatedJournalEchoes_areIdempotent_andDoNotDegradeLocalOnlyColumns() throws {
        let contentKey = "content-key-6"
        let lineID = try makeLine(contentKey: contentKey)
        let revisionID = UUID().uuidString

        try saveStore.insertRevision(localRevisionRow(
            id: revisionID, lineID: lineID, blobSHA256: "mno345", tier: .baseline, origin: .external,
            manifestDigest: "manifest-digest-6", sessionID: "session-6", artifactSetJSON: "{\"n\":1}"
        ))

        let entry = try saveEntry(revisionID: revisionID, lineID: lineID, contentKey: contentKey, blobSHA256: "mno345")
        _ = applier.apply([entry])
        _ = applier.apply([entry])
        _ = applier.apply([entry])

        let echoed = try XCTUnwrap(saveStore.fetchRevision(id: revisionID))
        XCTAssertEqual(echoed.tier, SaveCaptureTier.baseline.rawValue)
        XCTAssertEqual(echoed.origin, SaveCaptureOrigin.external.rawValue)
        XCTAssertEqual(echoed.manifestDigest, "manifest-digest-6")
        XCTAssertEqual(echoed.sessionID, "session-6")
        XCTAssertEqual(echoed.artifactSetJSON, "{\"n\":1}")
    }
}
