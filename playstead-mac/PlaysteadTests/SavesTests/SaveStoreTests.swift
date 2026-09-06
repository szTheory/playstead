import XCTest
@testable import Playstead

/// Covers `SaveStore.markRestoredHere` (plan 04-22 task 1): D-35's
/// restored-here provenance column is immutable once set, and an
/// existing install whose `save_revision` table predates the column
/// still opens and reads every existing row as `restoredHereAt == nil`.
final class SaveStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func freshStore() throws -> SaveStore {
        let localStore = try LocalStore(paths: paths)
        return SaveStore(localStore: localStore)
    }

    private func insertRevision(_ store: SaveStore, id: String, lineID: String) throws {
        try store.insertRevision(SaveRevisionRow(
            id: id, saveLineID: lineID, parentRevisionID: nil, blobSHA256: String(repeating: "a", count: 64),
            sizeBytes: 32_768, originDeviceID: nil, deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.localOnly.rawValue, localPath: nil
        ))
    }

    // MARK: - Immutability

    func testARevisionNeverRestoredReadsNilRestoredHereAt() throws {
        let store = try freshStore()
        try store.resolveLine(contentKey: "content-1", saveKind: "battery", slot: "0", placeholderID: "line-1")
        try insertRevision(store, id: "r1", lineID: "line-1")

        let revision = try XCTUnwrap(store.fetchRevision(id: "r1"))
        XCTAssertNil(revision.restoredHereAt)
    }

    func testMarkingRestoredTwiceKeepsTheFirstTimestamp() throws {
        let store = try freshStore()
        try store.resolveLine(contentKey: "content-1", saveKind: "battery", slot: "0", placeholderID: "line-1")
        try insertRevision(store, id: "r1", lineID: "line-1")

        try store.markRestoredHere(revisionID: "r1", at: "2026-01-01T00:00:00Z")
        try store.markRestoredHere(revisionID: "r1", at: "2027-06-01T00:00:00Z")

        let revision = try XCTUnwrap(store.fetchRevision(id: "r1"))
        XCTAssertEqual(revision.restoredHereAt, "2026-01-01T00:00:00Z", "provenance must be immutable once set (D-35)")
    }

    // MARK: - Pre-04-22 install upgrades in place

    /// Simulates a database created before this plan's `restored_here_at`
    /// column existed: hand-writes `save_line`/`save_revision` with the
    /// pre-04-22 shape, then opens it through `LocalStore(paths:)` --
    /// which runs the full migration set, including the additive ALTER
    /// this plan added -- and asserts the store still opens and every
    /// pre-existing row reads `restoredHereAt == nil`.
    func testAnExistingInstallWhoseTablePredatesTheColumnStillOpensWithNilProvenance() throws {
        let connection = try SQLiteConnection(path: paths.databaseURL.path)
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS save_line (
                id TEXT PRIMARY KEY,
                content_key TEXT NOT NULL,
                save_kind TEXT NOT NULL DEFAULT 'battery',
                slot TEXT NOT NULL DEFAULT '0',
                UNIQUE(content_key, save_kind, slot)
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS save_revision (
                id TEXT PRIMARY KEY,
                save_line_id TEXT NOT NULL,
                parent_revision_id TEXT,
                blob_sha256 TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                origin_device_id TEXT,
                device_captured_at TEXT,
                recorded_at TEXT,
                capture_method TEXT,
                adapter_id TEXT,
                adapter_version TEXT,
                save_format TEXT,
                format_confidence TEXT,
                play_session_id TEXT,
                durability TEXT NOT NULL DEFAULT 'localOnly',
                local_path TEXT,
                FOREIGN KEY (save_line_id) REFERENCES save_line(id) ON DELETE CASCADE
            );
            """
        )
        try connection.execute(
            "INSERT INTO save_line (id, content_key, save_kind, slot) VALUES (?, ?, ?, ?);",
            params: ["line-old", "content-old", "battery", "0"]
        )
        try connection.execute(
            """
            INSERT INTO save_revision (id, save_line_id, blob_sha256, size_bytes, durability)
            VALUES (?, ?, ?, ?, ?);
            """,
            params: ["r-old", "line-old", String(repeating: "b", count: 64), 32_768, "localOnly"]
        )

        // Re-open through the real production path -- runs every
        // migration, including this plan's additive ALTER.
        let store = try freshStore()

        let revision = try XCTUnwrap(store.fetchRevision(id: "r-old"))
        XCTAssertNil(revision.restoredHereAt, "a pre-existing row must read nil, never crash or lose the row")

        // The upgraded schema must accept a new mark on this pre-existing row.
        try store.markRestoredHere(revisionID: "r-old", at: "2026-02-01T00:00:00Z")
        XCTAssertEqual(store.fetchRevision(id: "r-old")?.restoredHereAt, "2026-02-01T00:00:00Z")
    }
}
