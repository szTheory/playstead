import Foundation
import os

/// The durable ledger of committed cache objects (`cache_objects`).
///
/// Every capacity and reclaim decision in the app is measured against
/// this table and nothing else: `QuotaManager.usedBytes()` sums its
/// `size` column, `EvictionPlanner` enumerates it to build the reclaim
/// candidate list, `AvailabilityState` treats a row as the definition of
/// "cached", and `JournalApplier` consults it. `objects/` on disk and
/// `verify-index.json` are the physical truth; this table is the
/// queryable mirror of it, and the two drifting apart is not a cosmetic
/// problem — it is a capacity gate that cannot fire and bytes that
/// cannot be reclaimed (WINDOWS #75).
///
/// Which is why this type exists rather than an `INSERT` at a call site:
/// the row was previously written by exactly one caller,
/// `DownloadCoordinator.handleSuccess`, so the queue path recorded its
/// objects and the Download button's own path — `attemptDownload`, which
/// calls `DownloadEngine` directly — recorded nothing at all. `CASManager`
/// owns this now, because committing an object and recording it are the
/// same event.
struct CacheObjectStore {
    private static let logger = Logger(subsystem: "dev.playstead.mac", category: "cache-objects")

    let localStore: LocalStore

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    /// Records (or refreshes) the row for a just-committed object. The
    /// verify columns are carried across so a later integrity check can
    /// use them without re-reading `verify-index.json`.
    ///
    /// A failure here cannot be allowed to fail a commit whose bytes are
    /// already verified and in place — but it must not be silent either,
    /// because the consequence is an under-counted cache.
    func record(_ record: VerifyRecord, at date: Date = Date()) {
        let timestamp = ISO8601DateFormatter().string(from: date)
        do {
            try localStore.connection.execute(
                """
                INSERT INTO cache_objects
                    (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(sha256) DO UPDATE SET
                    last_used_at = excluded.last_used_at,
                    verify_size = excluded.verify_size,
                    verify_inode = excluded.verify_inode,
                    verify_mtime_ms = excluded.verify_mtime_ms;
                """,
                params: [
                    record.sha256, record.size, timestamp, timestamp,
                    record.size, Int(record.inode), Int(record.mtime * 1000),
                ]
            )
        } catch {
            Self.logger.error("could not record cache object: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the row for an object that is no longer on disk. Idempotent,
    /// and deliberately tolerant of already being gone —
    /// `EvictionPlanner` deletes the row itself before removing the file
    /// (so a crash between the two leaves an unreferenced file rather
    /// than a row promising bytes that are not there), and this is the
    /// backstop for every other removal path.
    func forget(sha256: String) {
        do {
            try localStore.connection.execute("DELETE FROM cache_objects WHERE sha256 = ?;", params: [sha256])
        } catch {
            Self.logger.error("could not forget cache object: \(error.localizedDescription, privacy: .public)")
        }
    }
}
