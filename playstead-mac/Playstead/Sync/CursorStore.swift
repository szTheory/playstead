import Foundation

/// An opaque wrapper over the server-signed sync cursor string
/// (`Playstead.Sync.Cursor`). The client must never parse, compare, or
/// synthesize a cursor value — doing so would let it fabricate an as-of
/// position the server never issued and skip entries permanently (see
/// this task's `<action>`). `rawValue` is module-internal only so it can
/// round-trip through `CursorStore`'s storage and `ChangesClient`'s
/// request — nothing outside this module can read, derive, or construct
/// one, and nothing inside it inspects the string's structure.
struct OpaqueCursor: Equatable {
    let rawValue: String
}

/// Persists the single opaque sync cursor plus the last successful sync
/// timestamp in the `sync_cursor` table (always at most one row, `id = 1`).
/// Absence of a row means the client has never completed a snapshot
/// bootstrap.
final class CursorStore {
    private let localStore: LocalStore
    private let dateFormatter = ISO8601DateFormatter()

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    /// The stored cursor, or `nil` if never synced.
    func load() -> OpaqueCursor? {
        let rows = (try? localStore.connection.query(
            "SELECT cursor FROM sync_cursor WHERE id = 1;"
        ) { row -> String in row.string(0) ?? "" }) ?? []
        guard let raw = rows.first, !raw.isEmpty else { return nil }
        return OpaqueCursor(rawValue: raw)
    }

    /// The last successful sync timestamp, or `nil` if never synced.
    func lastSyncedAt() -> Date? {
        let rows = (try? localStore.connection.query(
            "SELECT last_synced_at FROM sync_cursor WHERE id = 1;"
        ) { row -> String? in row.string(0) }) ?? []
        guard let raw = rows.first, let iso = raw else { return nil }
        return dateFormatter.date(from: iso)
    }

    /// Stores `cursor` verbatim, replacing whatever was there before, and
    /// records `syncedAt` as the last successful sync time. A failed
    /// transport attempt must never call this — the whole point of the
    /// single-row upsert is that the previous cursor stays byte-identical
    /// until a full page has actually been applied.
    func store(_ cursor: OpaqueCursor, syncedAt: Date) throws {
        try localStore.connection.execute(
            """
            INSERT INTO sync_cursor (id, cursor, last_synced_at)
            VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                cursor = excluded.cursor,
                last_synced_at = excluded.last_synced_at;
            """,
            params: [cursor.rawValue, dateFormatter.string(from: syncedAt)]
        )
    }

    /// Deletes the stored cursor — the first step of a cursor-expired
    /// reset, always inside the same transaction as clearing the
    /// catalogue/curation tables so the client can never observe a
    /// cleared read model paired with a stale cursor.
    func clear() throws {
        try localStore.connection.execute("DELETE FROM sync_cursor;")
    }
}
