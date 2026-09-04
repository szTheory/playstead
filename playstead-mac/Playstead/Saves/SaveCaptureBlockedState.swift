import Foundation

/// One durable blocked-capture row (D-31): a disk-full or other write-
/// refusal error observed while writing a capture. Nothing is ever
/// deleted because of a blockage, and the row itself is never deleted --
/// `resolvedAt` marks a cleared blockage without erasing its history.
struct SaveCaptureBlockedRow: Equatable {
    let id: String
    let saveLineID: String
    let sessionID: String?
    let digest: String?
    let reason: String
    let firstFailedAt: String
    let lastFailedAt: String
    let failureCount: Int
    let alerted: Bool
    let resolvedAt: String?
}

/// The user-facing signal a newly raised (never-before-alerted) blockage
/// produces. Deliberately its own type, never the frozen, nine-member,
/// import-recognition-scoped attention vocabulary that a different
/// bounded context owns (plan 04-10's D-66 arbitration) -- saves raise
/// their own attention through a saves-owned source instead of widening
/// that vocabulary. `SaveCaptureAlert` is this plan's local signal; plan
/// 04-10 wires a durable saves attention item to it without this type
/// changing.
struct SaveCaptureAlert: Equatable {
    let saveLineID: String
    let sessionID: String?
    let reason: String
}

/// A one-shot notifier for a newly raised blockage. Injected so a test
/// can assert "exactly one alert per distinct blockage" without a real
/// UI, and so a later attention-source wiring can plug in without this
/// type changing.
protocol SaveCaptureAlertSink: Sendable {
    func alert(_ alert: SaveCaptureAlert)
}

/// D-31's escape hatch: streams a captured artifact's bytes directly to
/// the server without first landing a local blob -- for a device whose
/// disk cannot even hold the small SRAM artifact. The real authenticated
/// HTTP transport is a later plan's concern (mirrors plan 04-04's
/// `SaveBytesPrefetcher` documented-stub seam); this type only declares
/// the contract, matching that precedent rather than inventing a new
/// stubbing convention.
protocol SaveDirectUploadTransport: Sendable {
    func uploadDirectly(data: Data, saveLineID: String, sessionID: String?) async throws
}

/// Owns D-31's named, loud-once, never-silent disk-full failure path: a
/// durable blocked row, exactly one alert per distinct blockage, a
/// persistent attention state until it clears, a retry on every
/// subsequent poll cycle, and a direct-upload escape hatch. Nothing is
/// ever deleted, and this type never touches the running game -- the
/// emulator keeps running and keeps writing; only the durable local
/// capture path is affected while a blockage is open.
actor SaveCaptureBlockedState {
    private let localStore: LocalStore
    private let alertSink: SaveCaptureAlertSink?
    private let directUpload: SaveDirectUploadTransport?
    private let clock: () -> Date

    init(
        localStore: LocalStore,
        alertSink: SaveCaptureAlertSink? = nil,
        directUpload: SaveDirectUploadTransport? = nil,
        clock: @escaping () -> Date = Date.init
    ) {
        self.localStore = localStore
        self.alertSink = alertSink
        self.directUpload = directUpload
        self.clock = clock
    }

    /// Records one capture failure for `saveLineID`. When a blockage is
    /// already open for this line, upserts onto it (bumping
    /// `failureCount`/`lastFailedAt`) and never alerts again -- a second,
    /// third, ... failure for the same still-open blockage raises no
    /// second alert. Otherwise inserts a new durable row and alerts
    /// exactly once.
    @discardableResult
    func recordFailure(saveLineID: String, sessionID: String?, digest: String?, reason: String) throws -> SaveCaptureBlockedRow {
        let now = Self.iso8601.string(from: clock())

        if let existing = openBlockage(saveLineID: saveLineID) {
            try localStore.connection.execute(
                "UPDATE save_capture_blocked SET last_failed_at = ?, failure_count = failure_count + 1 WHERE id = ?;",
                params: [now, existing.id]
            )
            return openBlockage(saveLineID: saveLineID) ?? existing
        }

        let id = UUID().uuidString
        try localStore.connection.execute(
            """
            INSERT INTO save_capture_blocked (
                id, save_line_id, session_id, digest, reason, first_failed_at, last_failed_at, failure_count, alerted, resolved_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, NULL);
            """,
            params: [id, saveLineID, sessionID, digest, reason, now, now]
        )
        alertSink?.alert(SaveCaptureAlert(saveLineID: saveLineID, sessionID: sessionID, reason: reason))
        return openBlockage(saveLineID: saveLineID) ?? SaveCaptureBlockedRow(
            id: id, saveLineID: saveLineID, sessionID: sessionID, digest: digest, reason: reason,
            firstFailedAt: now, lastFailedAt: now, failureCount: 1, alerted: true, resolvedAt: nil
        )
    }

    /// The still-open (`resolvedAt == nil`) blockage for `saveLineID`, if
    /// any -- what a poll cycle checks before deciding whether a retry is
    /// even relevant, and what "persistent attention state" means here:
    /// the row simply exists, unresolved, until cleared.
    func openBlockage(saveLineID: String) -> SaveCaptureBlockedRow? {
        (try? localStore.connection.query(
            """
            SELECT id, save_line_id, session_id, digest, reason, first_failed_at, last_failed_at,
                   failure_count, alerted, resolved_at
            FROM save_capture_blocked WHERE save_line_id = ? AND resolved_at IS NULL
            ORDER BY rowid DESC LIMIT 1;
            """,
            params: [saveLineID]
        ) { row in Self.row(from: row) })?.first
    }

    /// Clears the open blockage for `saveLineID`, called once a retried
    /// capture (or the direct-upload escape hatch) actually succeeds.
    /// Marks `resolvedAt`; the row itself is never deleted.
    func clearBlockage(saveLineID: String) throws {
        guard let existing = openBlockage(saveLineID: saveLineID) else { return }
        let now = Self.iso8601.string(from: clock())
        try localStore.connection.execute(
            "UPDATE save_capture_blocked SET resolved_at = ? WHERE id = ?;", params: [now, existing.id]
        )
    }

    /// D-31's escape hatch: streams `data` directly to the server without
    /// landing a local blob first. Does not, by itself, clear the
    /// blockage -- the caller clears it once the upload (or a subsequent
    /// successful local retry) actually succeeds.
    func attemptDirectUpload(data: Data, saveLineID: String, sessionID: String?) async throws {
        guard let directUpload else { return }
        try await directUpload.uploadDirectly(data: data, saveLineID: saveLineID, sessionID: sessionID)
    }

    private static let iso8601 = ISO8601DateFormatter()

    private static func row(from row: SQLiteRow) -> SaveCaptureBlockedRow {
        SaveCaptureBlockedRow(
            id: row.string(0) ?? "",
            saveLineID: row.string(1) ?? "",
            sessionID: row.string(2),
            digest: row.string(3),
            reason: row.string(4) ?? "",
            firstFailedAt: row.string(5) ?? "",
            lastFailedAt: row.string(6) ?? "",
            failureCount: row.int(7) ?? 0,
            alerted: (row.int(8) ?? 0) != 0,
            resolvedAt: row.string(9)
        )
    }
}
