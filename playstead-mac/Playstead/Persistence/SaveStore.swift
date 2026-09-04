import Foundation

/// One local `save_line` row -- the client's mirror of the server's
/// `(content_key, save_kind, slot)` identity tuple (D-10). `id`
/// mirrors the server's `save_lines.id` once a revision on this line
/// has round-tripped through a commit; a fresh line created entirely
/// offline before any commit is keyed by a client-generated
/// placeholder id, which the identity tuple's unique local index makes
/// safe to converge later without a rename (SaveCapturePoller never
/// needs to rewrite existing revision rows' `save_line_id` because the
/// commit path adopts the id `SavesController`'s multi-hand-back
/// establishes as canonical the very first time the pair is seen).
struct SaveLineRow: Equatable {
    let id: String
    let contentKey: String
    let saveKind: String
    let slot: String
}

/// One local `save_revision` row. `durability` is one of `localOnly`,
/// `queued`, `uploaded` -- a distinct axis from `current`/`restored`/
/// `conflicted` (D-35), never modeled as one shared enum with them.
enum SaveDurability: String {
    case localOnly
    case queued
    case uploaded
}

struct SaveRevisionRow: Equatable {
    let id: String
    let saveLineID: String
    let parentRevisionID: String?
    let blobSHA256: String
    let sizeBytes: Int
    let originDeviceID: String?
    let deviceCapturedAt: String?
    let recordedAt: String?
    let captureMethod: String?
    let adapterID: String?
    let adapterVersion: String?
    let saveFormat: String?
    let formatConfidence: String?
    let playSessionID: String?
    let durability: String
    /// The temp-file-turned-durable local copy of the artifact's bytes
    /// at capture time (D-06's write-order result), so the upload lane
    /// can stream from disk without re-reading the live save directory.
    let localPath: String?
    /// D-04's tier discriminator (`staged`/`promoted`/`baseline`) and
    /// D-04's origin (`session`/`external`, the baseline case). Rows
    /// created before plan 04-06 read as `promoted`/`session` (the
    /// schema default), matching 04-04's pre-tier semantics exactly.
    let tier: String
    let origin: String
    /// D-08: recorded alongside `blobSHA256` (the raw artifact digest,
    /// always the stored blob identity) -- never used for dedupe, export
    /// filenames, or the compatibility gate.
    let manifestDigest: String?
    /// Groups every staged/promoted/baseline row that belongs to one
    /// open-to-close play session (D-04, D-07).
    let sessionID: String?
    /// The JSON-encoded `SaveArtifactSet` this revision was captured
    /// from (D-08).
    let artifactSetJSON: String?

    /// Explicit memberwise init (defining any initializer suppresses
    /// Swift's synthesized one) with defaults for the five fields plan
    /// 04-06 added, so every pre-04-06 call site that only names the
    /// original fields keeps compiling unchanged.
    init(
        id: String,
        saveLineID: String,
        parentRevisionID: String?,
        blobSHA256: String,
        sizeBytes: Int,
        originDeviceID: String?,
        deviceCapturedAt: String?,
        recordedAt: String?,
        captureMethod: String?,
        adapterID: String?,
        adapterVersion: String?,
        saveFormat: String?,
        formatConfidence: String?,
        playSessionID: String?,
        durability: String,
        localPath: String?,
        tier: String = SaveCaptureTier.promoted.rawValue,
        origin: String = SaveCaptureOrigin.session.rawValue,
        manifestDigest: String? = nil,
        sessionID: String? = nil,
        artifactSetJSON: String? = nil
    ) {
        self.id = id
        self.saveLineID = saveLineID
        self.parentRevisionID = parentRevisionID
        self.blobSHA256 = blobSHA256
        self.sizeBytes = sizeBytes
        self.originDeviceID = originDeviceID
        self.deviceCapturedAt = deviceCapturedAt
        self.recordedAt = recordedAt
        self.captureMethod = captureMethod
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.saveFormat = saveFormat
        self.formatConfidence = formatConfidence
        self.playSessionID = playSessionID
        self.durability = durability
        self.localPath = localPath
        self.tier = tier
        self.origin = origin
        self.manifestDigest = manifestDigest
        self.sessionID = sessionID
        self.artifactSetJSON = artifactSetJSON
    }
}

/// Reads and writes the two local `save_*` tables. Mirrors
/// `CurationStore`'s shape: one upsert per row kind, a durability
/// transition helper, and read helpers the capture poller, the upload
/// lane, and `JournalApplier`'s `save` case all share.
final class SaveStore {
    private let localStore: LocalStore

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    // MARK: - Save line

    /// Resolves the local line row for `(contentKey, saveKind, slot)`,
    /// creating one with `placeholderID` if none exists yet. Returns
    /// the row that actually exists after this call -- if a line was
    /// already present (created locally or by a prior journal apply),
    /// its existing `id` is returned, never `placeholderID`.
    @discardableResult
    func resolveLine(contentKey: String, saveKind: String, slot: String, placeholderID: String) throws -> SaveLineRow {
        if let existing = fetchLine(contentKey: contentKey, saveKind: saveKind, slot: slot) {
            return existing
        }

        try localStore.connection.execute(
            """
            INSERT INTO save_line (id, content_key, save_kind, slot)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(content_key, save_kind, slot) DO NOTHING;
            """,
            params: [placeholderID, contentKey, saveKind, slot]
        )

        return fetchLine(contentKey: contentKey, saveKind: saveKind, slot: slot)
            ?? SaveLineRow(id: placeholderID, contentKey: contentKey, saveKind: saveKind, slot: slot)
    }

    /// Re-keys a local line's id to the server-canonical id once a
    /// commit response confirms it -- a no-op when they already match.
    func adoptCanonicalLineID(_ canonicalID: String, forLocalID localID: String) throws {
        guard canonicalID != localID else { return }
        try localStore.connection.execute("UPDATE save_line SET id = ? WHERE id = ?;", params: [canonicalID, localID])
        try localStore.connection.execute(
            "UPDATE save_revision SET save_line_id = ? WHERE save_line_id = ?;", params: [canonicalID, localID]
        )
    }

    func fetchLine(id: String) -> SaveLineRow? {
        (try? localStore.connection.query(
            "SELECT id, content_key, save_kind, slot FROM save_line WHERE id = ?;",
            params: [id]
        ) { row in
            SaveLineRow(
                id: row.string(0) ?? "",
                contentKey: row.string(1) ?? "",
                saveKind: row.string(2) ?? "",
                slot: row.string(3) ?? ""
            )
        })?.first
    }

    func fetchLine(contentKey: String, saveKind: String, slot: String) -> SaveLineRow? {
        (try? localStore.connection.query(
            "SELECT id, content_key, save_kind, slot FROM save_line WHERE content_key = ? AND save_kind = ? AND slot = ?;",
            params: [contentKey, saveKind, slot]
        ) { row in
            SaveLineRow(
                id: row.string(0) ?? "",
                contentKey: row.string(1) ?? "",
                saveKind: row.string(2) ?? "",
                slot: row.string(3) ?? ""
            )
        })?.first
    }

    // MARK: - Save revision

    func insertRevision(_ row: SaveRevisionRow) throws {
        try localStore.connection.execute(
            """
            INSERT INTO save_revision (
                id, save_line_id, parent_revision_id, blob_sha256, size_bytes,
                origin_device_id, device_captured_at, recorded_at, capture_method,
                adapter_id, adapter_version, save_format, format_confidence,
                play_session_id, durability, local_path, tier, origin, manifest_digest,
                session_id, artifact_set_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                save_line_id = excluded.save_line_id,
                parent_revision_id = excluded.parent_revision_id,
                blob_sha256 = excluded.blob_sha256,
                size_bytes = excluded.size_bytes,
                origin_device_id = excluded.origin_device_id,
                device_captured_at = excluded.device_captured_at,
                recorded_at = excluded.recorded_at,
                capture_method = excluded.capture_method,
                adapter_id = excluded.adapter_id,
                adapter_version = excluded.adapter_version,
                save_format = excluded.save_format,
                format_confidence = excluded.format_confidence,
                play_session_id = excluded.play_session_id,
                durability = excluded.durability,
                local_path = excluded.local_path,
                tier = excluded.tier,
                origin = excluded.origin,
                manifest_digest = excluded.manifest_digest,
                session_id = excluded.session_id,
                artifact_set_json = excluded.artifact_set_json;
            """,
            params: [
                row.id, row.saveLineID, row.parentRevisionID, row.blobSHA256, row.sizeBytes,
                row.originDeviceID, row.deviceCapturedAt, row.recordedAt, row.captureMethod,
                row.adapterID, row.adapterVersion, row.saveFormat, row.formatConfidence,
                row.playSessionID, row.durability, row.localPath, row.tier, row.origin, row.manifestDigest,
                row.sessionID, row.artifactSetJSON
            ]
        )
    }

    func updateDurability(id: String, durability: SaveDurability) throws {
        try localStore.connection.execute(
            "UPDATE save_revision SET durability = ? WHERE id = ?;", params: [durability.rawValue, id]
        )
    }

    func setRecordedAt(id: String, recordedAt: String) throws {
        try localStore.connection.execute(
            "UPDATE save_revision SET recorded_at = ? WHERE id = ?;", params: [recordedAt, id]
        )
    }

    func fetchRevision(id: String) -> SaveRevisionRow? {
        fetchRevisions(matching: "id = ?", params: [id]).first
    }

    /// The current head (a revision with no children) for a line, or
    /// `nil` if the line has no revisions yet. Used by the capture
    /// poller to decide same-device byte-identical de-dup (D-30) and
    /// to derive the next capture's `parent_revision_id`.
    /// A `staged` row is a rolling, session-scoped working copy, never a
    /// DAG node (D-04) -- excluded here so it can never be mistaken for
    /// the line's real head, which only a `promoted` or `baseline` row
    /// may be.
    func fetchHead(saveLineID: String) -> SaveRevisionRow? {
        (try? localStore.connection.query(
            """
            SELECT r.id, r.save_line_id, r.parent_revision_id, r.blob_sha256, r.size_bytes,
                   r.origin_device_id, r.device_captured_at, r.recorded_at, r.capture_method,
                   r.adapter_id, r.adapter_version, r.save_format, r.format_confidence,
                   r.play_session_id, r.durability, r.local_path, r.tier, r.origin, r.manifest_digest,
                   r.session_id, r.artifact_set_json
            FROM save_revision r
            WHERE r.save_line_id = ?
              AND r.tier != 'staged'
              AND NOT EXISTS (SELECT 1 FROM save_revision c WHERE c.parent_revision_id = r.id)
            ORDER BY r.rowid DESC
            LIMIT 1;
            """,
            params: [saveLineID]
        ) { row in Self.row(from: row) })?.first
    }

    func fetchPending(durability: SaveDurability) -> [SaveRevisionRow] {
        fetchRevisions(matching: "durability = ?", params: [durability.rawValue])
    }

    func fetchAllRevisions() -> [SaveRevisionRow] {
        fetchRevisions(matching: "1 = 1", params: [])
    }

    /// Every row captured under one open-to-close play session (D-04) --
    /// used to assert "exactly one promoted revision per session" and to
    /// distinguish a session's staged/promoted/baseline rows.
    func fetchRevisions(sessionID: String) -> [SaveRevisionRow] {
        fetchRevisions(matching: "session_id = ?", params: [sessionID])
    }

    private func fetchRevisions(matching whereClause: String, params: [SQLiteBindable]) -> [SaveRevisionRow] {
        (try? localStore.connection.query(
            """
            SELECT id, save_line_id, parent_revision_id, blob_sha256, size_bytes,
                   origin_device_id, device_captured_at, recorded_at, capture_method,
                   adapter_id, adapter_version, save_format, format_confidence,
                   play_session_id, durability, local_path, tier, origin, manifest_digest,
                   session_id, artifact_set_json
            FROM save_revision WHERE \(whereClause) ORDER BY rowid ASC;
            """,
            params: params
        ) { row in Self.row(from: row) }) ?? []
    }

    private static func row(from row: SQLiteRow) -> SaveRevisionRow {
        SaveRevisionRow(
            id: row.string(0) ?? "",
            saveLineID: row.string(1) ?? "",
            parentRevisionID: row.string(2),
            blobSHA256: row.string(3) ?? "",
            sizeBytes: row.int(4) ?? 0,
            originDeviceID: row.string(5),
            deviceCapturedAt: row.string(6),
            recordedAt: row.string(7),
            captureMethod: row.string(8),
            adapterID: row.string(9),
            adapterVersion: row.string(10),
            saveFormat: row.string(11),
            formatConfidence: row.string(12),
            playSessionID: row.string(13),
            durability: row.string(14) ?? SaveDurability.localOnly.rawValue,
            localPath: row.string(15),
            tier: row.string(16) ?? SaveCaptureTier.promoted.rawValue,
            origin: row.string(17) ?? SaveCaptureOrigin.session.rawValue,
            manifestDigest: row.string(18),
            sessionID: row.string(19),
            artifactSetJSON: row.string(20)
        )
    }

    /// Deletes every row across both save tables -- used by tests only.
    func clearAll() throws {
        try localStore.connection.execute("DELETE FROM save_revision;")
        try localStore.connection.execute("DELETE FROM save_line;")
    }
}
