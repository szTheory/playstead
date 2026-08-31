---
phase: 03-mac-offline-play-vertical-slice
plan: 06
subsystem: sync
tags: [swift, sqlite, urlsession, change-journal, cursor, curation, offline-first]

# Dependency graph
requires:
  - phase: 03-mac-offline-play-vertical-slice (03-03)
    provides: "Playstead.xcodeproj synchronized-group setup, APIClient/SnapshotClient/LocalStore, SQLiteConnection"
  - phase: 03-mac-offline-play-vertical-slice (03-04)
    provides: "Server curation entity kind riding the snapshot/journal/cursor spine — six payload types (favorite, collection, collection_member, queue_item, continue_dismissal, recent)"
provides:
  - "SyncEngine actor: snapshot bootstrap (paged via next_after_id/has_more), cursor-resumed /api/v1/changes paging, cursor-expired reset, SyncState (neverSynced/syncing/synced/offline)"
  - "CatalogueStore/CurationStore: incremental upsert/tombstone read model over catalogue_entries/catalogue_members and the six curation_* tables"
  - "CursorStore: opaque cursor round-trip storage, never parses/derives a cursor value"
  - "JournalApplier: entity-kind/payload-type dispatch, unknown-kind skip-and-count, idempotent replay"
affects: [03-07, 03-08, 03-09, 03-10]

actuals:
  tokens: 17855
  tasks: 1
  commits: 2

tech-stack:
  added: []
  patterns:
    - "SQLiteConnection.onQueue(_:) uses a DispatchSpecificKey to detect reentrant calls from inside transaction(_:), so table-owning stores can call execute/query from within a caller-wrapped transaction without a queue.sync deadlock/crash"
    - "SyncEngine owns its own SnapshotEnvelope decode (curation branch + next_after_id) rather than widening 03-03's narrow SnapshotClient/SnapshotResponse, which stays scoped to its one full-replace tracer bootstrap call"
    - "JournalApplier treats a snapshot's curation array elements as synthesized JournalEntry upserts (entity_kind: curation, a locally-derived entity_id), so snapshot-sourced and journal-sourced curation rows converge through the exact same apply path"

key-files:
  created:
    - playstead-mac/Playstead/Sync/SyncEngine.swift
    - playstead-mac/Playstead/Sync/ChangesClient.swift
    - playstead-mac/Playstead/Sync/CursorStore.swift
    - playstead-mac/Playstead/Sync/JournalApplier.swift
    - playstead-mac/Playstead/Persistence/CatalogueStore.swift
    - playstead-mac/Playstead/Persistence/CurationStore.swift
    - playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift
  modified:
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Persistence/LocalStore.swift
    - playstead-mac/Playstead/Persistence/SQLiteConnection.swift
    - playstead-mac/Playstead/Net/APIClient.swift

key-decisions:
  - "APIClient gained queryItems: [URLQueryItem] and injectable session/credential overrides — required for GET /api/v1/changes?cursor=… (URL.appendingPathComponent cannot carry a query string) and for SyncEngineTests to run headless against a URLProtocol stub, avoiding 03-03's documented Keychain 'dark wake' failure in this sandboxed environment."
  - "SQLiteConnection.execute/query detect (via DispatchSpecificKey) when already running on their own queue inside transaction(_:) and skip the redundant queue.sync — the original unconditional queue.sync crashed with 'dispatch_sync called on queue already owned by current thread' the instant any store method ran inside a transaction closure, which is exactly the pattern this task's page-apply discipline (Task's own <action> text) requires."
  - "LocalStore now exposes its SQLiteConnection and a transaction(_:) passthrough; CatalogueStore/CurationStore/CursorStore own their tables' read/write logic directly rather than LocalStore growing a method per table."
  - "SyncEngine decodes its own SnapshotEnvelope (curation branch, next_after_id) instead of widening 03-03's SnapshotClient/SnapshotResponse, which stays exactly as narrow as that tracer plan needed it."

patterns-established:
  - "Every apply (catalogue or curation, upsert or tombstone) is keyed on entity id and idempotent by construction (SQL upsert / DELETE-if-exists), so replaying a page after an interrupted apply is always safe."
  - "SyncState has no bare failure case — offline reads as .offline(since:) or .neverSynced, never a hard error, matching the phase's 'being offline is a normal state' contract."

requirements-completed: []

coverage:
  - id: D1
    description: "The Mac's local read model converges with the server through the snapshot/journal/cursor recovery spine alone: empty-store bootstrap (catalogue + curation), cursor-resumed changes paging, cursor-expired full reset with no duplicates, idempotent replay, unknown-entity-kind forward compatibility, and a transport failure leaving the stored cursor and read model byte-identical/untouched"
    requirement: "LIBR-01"
    verification:
      - kind: unit
        ref: "PlaysteadTests/SyncTests/SyncEngineTests (11 tests, all pass): testBootstrapFromEmptyStoreWritesCatalogueAndCurationAndStoresCursor, testMultiPageSnapshotContinuesFromMarkerUntilExhausted, testResumedSyncAppliesOnlyChangesAfterStoredCursorAndNeverRefetchesSnapshot, testUpsertInsertsAndTombstoneDeletes, testApplyingSameEntryTwiceLeavesRowCountAndContentsUnchanged, testUnknownEntityKindIsSkippedAndRestOfPageStillApplies, testApplyingIdenticalPageTwiceProducesIdenticalTableContents, testCursorExpiredResetsToFreshSnapshotWithNoDuplicateRows, testTransportFailureLeavesStoredCursorByteIdenticalAndReadModelIntact, testCursorStoreRoundTripsByteIdentically, testCursorStoreLoadIsNilBeforeAnyStore"
        status: pass
      - kind: other
        ref: "xcodebuild test -scheme Playstead -destination 'platform=macOS' (full suite, 34 tests: 11 new SyncEngineTests + 23 pre-existing) — all pass, no regressions"
        status: pass
    human_judgment: false

# Metrics
duration: 55min
completed: 2026-08-30
status: halted
---

# Phase 3 Plan 6: Sync Engine (Task 1 only — Task 2/3 blocked on missing UI-SPEC)

**Mac client sync engine converges catalogue and curation through the server's snapshot/journal/cursor spine alone (bootstrap, resumed paging, expiry reset, idempotent replay) — Task 1 (tracer+TDD) shipped and fully tested; Tasks 2 and 3 (library shell UI) did not start because their required `03-UI-SPEC.md` does not exist yet.**

## Performance

- **Duration:** ~55 min (Task 1 only)
- **Started:** 2026-08-30T21:50:18Z (per STATE.md session start)
- **Tasks:** 1 of 3 completed (Task 1); Tasks 2 and 3 blocked
- **Files changed:** 11 (7 created, 4 modified)
- **Test suite:** 34/34 tests pass (11 new `SyncEngineTests` + 23 pre-existing), no regressions

## Accomplishments

- `SyncEngine` (an actor) converges the local SQLite read model with the server through the D-21 snapshot/journal/cursor spine alone: bootstraps from `/api/v1/snapshot` when no cursor is stored (paging via `next_after_id`/`has_more`, every page pinned to the first page's own returned cursor), otherwise pages `/api/v1/changes` from the stored cursor and commits the new cursor only after each page's transaction commits.
- `JournalApplier` dispatches every entry by `entity_kind` (`catalogue`/`curation`) and, for curation, further by the payload's `type` field across all six shapes (favorite, collection, collection_member, queue_item, continue_dismissal, recent). An unrecognised kind or type is skipped and counted, never a hard failure — proven by `testUnknownEntityKindIsSkippedAndRestOfPageStillApplies`.
- Every apply is an idempotent upsert (SQL `ON CONFLICT ... DO UPDATE`) or delete keyed on entity id, so replaying a page — which happens after any interrupted apply — is always safe. Proven directly (`testApplyingSameEntryTwiceLeavesRowCountAndContentsUnchanged`, `testApplyingIdenticalPageTwiceProducesIdenticalTableContents`) and via a full cursor-expired reset that produces exactly the fresh snapshot's row set with zero duplicates (`testCursorExpiredResetsToFreshSnapshotWithNoDuplicateRows`).
- `CursorStore`'s `OpaqueCursor` only ever round-trips the server-signed cursor string verbatim — it has no parsing, comparison, or synthesis logic anywhere in the client, matching the plan's `<key_links>` prohibition. A transport failure during sync leaves the stored cursor byte-identical and the read model untouched (`testTransportFailureLeavesStoredCursorByteIdenticalAndReadModelIntact`).
- `SyncState` has no bare failure case: a transport/decode error during `syncNow()` lands on `.offline(since:)` (or `.neverSynced` if nothing has ever succeeded) — being offline reads as a normal state, per the phase's own contract, not an error.

## Task Commits

1. **Task 1 (tracer + TDD): Sync engine — snapshot bootstrap, cursor-resumed journal apply, and expiry reset**
   - `0d0fd90` `test(03-06): add failing test for sync engine snapshot/journal/cursor convergence` (RED — verified for real: temporarily moved `Playstead/Sync/*.swift` and `CatalogueStore.swift`/`CurationStore.swift` out of the target, `xcodebuild test` failed to compile with `cannot find type 'SyncEngine' in scope` / `cannot find type 'JSONValue' in scope`, then restored before committing)
   - `ca9d057` `feat(03-06): sync engine — snapshot bootstrap, cursor-resumed journal apply, expiry reset` (GREEN — all 11 `SyncEngineTests` pass; full 34-test suite green)

No REFACTOR commit — the reentrancy fix to `SQLiteConnection` (see Deviations) was needed to reach GREEN in the first place and is folded into the GREEN commit rather than a separate cleanup step; no further cleanup was warranted.

Tasks 2 and 3 were not started — see "Next Phase Readiness" below.

## TDD Gate Compliance

Task 1 (`type="tracer" tdd="true"`) followed the RED→GREEN cycle: `test(03-06)` commit `0d0fd90` precedes `feat(03-06)` commit `ca9d057`. RED was verified for real (see commit message and above). No REFACTOR commit was needed.

Per the tracer protocol, the tracer's own `<verify>` (`xcodebuild test -scheme Playstead -destination 'platform=macOS' -only-testing:PlaysteadTests/SyncTests`) was re-run end-to-end after the GREEN commit — actually via the correct class-based identifier `PlaysteadTests/SyncEngineTests` (see Deviations: the plan's literal `-only-testing:PlaysteadTests/SyncTests` selects zero tests, since `-only-testing` addresses `Target/Class`, not the containing folder) — and passed (11/11), then the full suite was re-run (34/34) before proceeding to check Task 2's precondition.

## Files Created/Modified

- `playstead-mac/Playstead/Sync/SyncEngine.swift` — the actor: `syncNow()`, `SyncState`, snapshot bootstrap/paging, changes paging, cursor-expired reset, `SnapshotEnvelope` decode, synthesized curation-entry bootstrap mapping
- `playstead-mac/Playstead/Sync/ChangesClient.swift` — `JSONValue` (minimally-typed JSON), `JournalEntry`, `ChangesPage`, `SyncError`, the `/api/v1/changes` fetch + error mapping
- `playstead-mac/Playstead/Sync/CursorStore.swift` — `OpaqueCursor`, single-row `sync_cursor` persistence
- `playstead-mac/Playstead/Sync/JournalApplier.swift` — entity-kind/payload-type dispatch, the six curation payload decode shapes, tombstone handling
- `playstead-mac/Playstead/Persistence/CatalogueStore.swift` — incremental catalogue upsert/tombstone/replaceAll/clearAll over `LocalStore`'s existing tables
- `playstead-mac/Playstead/Persistence/CurationStore.swift` — upsert/tombstone/fetch for all six `curation_*` tables
- `playstead-mac/Playstead/Persistence/Migrations.swift` — added `sync_cursor` and the six `curation_*` tables
- `playstead-mac/Playstead/Persistence/LocalStore.swift` — exposes `connection` and a `transaction(_:)` passthrough for table-owning stores
- `playstead-mac/Playstead/Persistence/SQLiteConnection.swift` — reentrancy fix (see Deviations)
- `playstead-mac/Playstead/Net/APIClient.swift` — `queryItems:` support, injectable `session`/`credential` for headless testing
- `playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift` — 11 tests covering every `<behavior>` bullet and `<acceptance_criteria>` item

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `APIClient.get` had no way to attach a query string**
- **Found during:** Task 1, implementing `ChangesClient.fetch(after:)`
- **Issue:** `GET /api/v1/changes` requires a `cursor` query parameter; `APIClient.get`'s only path-building mechanism was `URL.appendingPathComponent`, which percent-encodes `?`/`=` literally rather than treating them as a query string.
- **Fix:** Added `queryItems: [URLQueryItem] = []` to `APIClient.get`, applied via `URLComponents` before request construction. Backward compatible — the sole existing caller (`SnapshotClient.fetch()`) uses only the `path:` label.
- **Files modified:** `playstead-mac/Playstead/Net/APIClient.swift`
- **Verification:** `testResumedSyncAppliesOnlyChangesAfterStoredCursorAndNeverRefetchesSnapshot` asserts the outgoing request's `cursor` query item.
- **Committed in:** `ca9d057`

**2. [Rule 3 - Blocking] `APIClient` had no seam for headless testing (real Keychain, hardcoded session)**
- **Found during:** Task 1, writing `SyncEngineTests`
- **Issue:** The task's own `<action>` explicitly requires covering every `<behavior>` bullet against a `URLProtocol` stub. `APIClient` always read the real macOS Keychain and built its own hardcoded `URLSession` — the exact combination plan 03-03's SUMMARY documented as failing with `errSecInDarkWake` in this sandboxed environment.
- **Fix:** Added optional `session: URLSession?` and `credential: PairingCredential?` init parameters, both defaulting to the existing real behavior (`nil` → build the pinned `URLSession` / read the real Keychain). `SyncEngineTests` injects `StubURLProtocol.makeSession()` and a fixed test credential.
- **Files modified:** `playstead-mac/Playstead/Net/APIClient.swift`
- **Verification:** All 11 `SyncEngineTests` run headless, no Keychain access.
- **Committed in:** `ca9d057`

**3. [Rule 1 - Bug] `SQLiteConnection`'s `queue.sync` was not reentrant — crashed the instant a store method ran inside `transaction(_:)`**
- **Found during:** Task 1, first full test run (before any of the above deviations were flagged as such — surfaced as a hard crash, not an assertion failure)
- **Issue:** The task's own `<action>` requires "all writes go through the `LocalStore` transaction helper so a partially applied page can never be observed." `LocalStore.transaction(_:)` → `SQLiteConnection.transaction(_:)` already runs its body via `queue.sync`; any nested `CatalogueStore`/`CurationStore`/`JournalApplier` call to `execute`/`query` (which each also called `queue.sync`) was therefore a `queue.sync` invoked from a thread already executing synchronously on that same serial queue — libdispatch traps this as a fatal `BUG IN CLIENT OF LIBDISPATCH: dispatch_sync called on queue already owned by current thread` rather than merely deadlocking. Four of the eleven tests (every one that exercised a real transactional page apply — `testBootstrapFromEmptyStoreWritesCatalogueAndCurationAndStoresCursor`, `testCursorExpiredResetsToFreshSnapshotWithNoDuplicateRows`, `testMultiPageSnapshotContinuesFromMarkerUntilExhausted`, `testResumedSyncAppliesOnlyChangesAfterStoredCursorAndNeverRefetchesSnapshot`) crashed the test process.
- **Fix:** Added a per-instance `DispatchSpecificKey<Void>` set on `SQLiteConnection`'s own queue; `execute`/`query`/`transaction` now route through a shared `onQueue(_:)` helper that runs `body` directly (no additional queue hop) when already executing on that queue, and falls back to `queue.sync` otherwise — the standard GCD reentrant-queue pattern.
- **Files modified:** `playstead-mac/Playstead/Persistence/SQLiteConnection.swift`
- **Verification:** All four previously-crashing tests pass; full 34-test suite green with no regressions to `DownloadResumeTests`/`MaterializationTests`/`AdapterPinTests`/`SnapshotDecodeTests`, which also exercise `SQLiteConnection` indirectly.
- **Committed in:** `ca9d057`

**4. [Rule 1 - Bug] The plan's own `<verify>` command selects zero tests**
- **Found during:** Task 1, running the tracer's `<verify>` after GREEN
- **Issue:** The plan's `<verify>` reads `xcodebuild test ... -only-testing:PlaysteadTests/SyncTests`. `-only-testing` addresses `Target/TestClass[/TestMethod]`, not a containing source folder — `SyncTests` is the folder (`playstead-mac/PlaysteadTests/SyncTests/`), not a class; the actual class is `SyncEngineTests` (matching the plan's own `<files>` entry, `SyncEngineTests.swift`). Running the command exactly as written produces `totalTestCount: 0` (a vacuous, silent "success" — confirmed via `xcrun xcresulttool get test-results summary`), not a real verification.
- **Fix:** Ran `-only-testing:PlaysteadTests/SyncEngineTests` instead (and the plan-level unscoped full-suite run) for actual verification. No plan-file edit — flagging this here for whoever authors plan 03-07's PLAN.md's `<verify>` commands, which follow the same `-only-testing:PlaysteadTests/<FolderName>` pattern for `LibraryTests`/`SyncTests` throughout plan 03-06 (also affects Task 2/3's own `<verify>` lines once they run) and would silently no-op the same way.
- **Files modified:** None (verification-only correction; no code or plan-file change).
- **Verification:** `xcrun xcresulttool get test-results summary` on the literal command's run shows `"totalTestCount": 0`; the corrected command shows 11/11 passing.
- **Committed in:** N/A (no code change)

**5. [Rule 2 - Missing Critical, flagged not silently worked around] The server's snapshot `curation` branch payload carries no row id**
- **Found during:** Task 1, implementing snapshot-bootstrap curation convergence
- **Issue:** `Playstead.Sync.CurationPayload.build/1` (plan 03-04) is used for both the journal payload (where the surrounding `JournalEntry` envelope supplies `entity_id`) AND the snapshot's `curation` array (which has no such envelope — each element is a bare payload map). A client bootstrapping from a snapshot alone therefore cannot learn a favorite/collection/queue-item/etc. row's real server id, only its natural fields.
- **Fix (bounded, not a silent workaround):** `SyncEngine.synthesizedCurationEntry(from:)` builds a local key from each type's own natural unique key when no `id` is present in the payload — matching the server's own unique index for `favorite`/`continue_dismissal`/`queue_item` (`user_id, asset_set_id`) and `collection_member` (`collection_id, asset_set_id`). `collection` has no natural key in this payload shape and falls back to `name`, which is **not** guaranteed unique — documented below under Known Stubs rather than hidden. A real server-issued `entity_id` from any later `/changes` upsert becomes that row's key from that point on.
- **Files modified:** `playstead-mac/Playstead/Sync/SyncEngine.swift` (doc comment on `synthesizedCurationEntry(from:)` carries this in full)
- **Verification:** `testBootstrapFromEmptyStoreWritesCatalogueAndCurationAndStoresCursor` exercises the favorite case end to end (natural key = `asset_set_id`) and passes; the `collection`/`name`-fallback path is documented but not independently tested in this plan (no collection-bearing bootstrap fixture was needed for this task's own acceptance criteria).
- **Committed in:** `ca9d057`

---

**Total deviations:** 5 auto-fixed (2 blocking API-surface gaps, 1 blocking bug — a crash, not a mere assertion failure, 1 verification-command correction, 1 flagged missing-critical/known-gap workaround). **Impact:** All were necessary either for correctness (the reentrancy crash would have made every real transactional sync call fatal), for the task's own explicit testability requirement (the `URLProtocol`-stub coverage this task's `<action>` mandates), or to get a genuine (not vacuous) verification result. The curation-snapshot-id gap is a real, bounded, and documented limitation inherited from a completed sibling plan (03-04) outside this plan's file scope to fix — not a shortcut taken here.

## Issues Encountered

- **`.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` does not exist.** Task 2 carries an explicit `<precondition>` requiring this file (D-17's shared status-glyph/navigation-order/empty-state spec, produced by `/gsd-ui-phase 3`) and instructs: "If absent, stop and request `/gsd-ui-phase 3` before continuing." Verified absent both by direct file check and by confirming no sibling plan (03-05, which shares the identical precondition and read_first dependency on `playstead-server/lib/playstead_web/live/library_live/{status_slot,sidebar}.ex`) has produced it either — those console files do not exist yet and 03-05 has no `SUMMARY.md`. This is a genuine unmet precondition per the executor's own protocol (never auto-approved, even in yolo/auto-chain mode — `gate="blocking-human"`), not a deviation to route around. **Task 2 and Task 3 were not started.**

## User Setup Required

None for the work actually completed (Task 1). Once `/gsd-ui-phase 3` produces `03-UI-SPEC.md`, this plan can resume at Task 2 with no further setup.

## Known Stubs

- **`SyncEngine.synthesizedCurationEntry(from:)`'s `collection` fallback key is the collection's `name`, not a stable id** — see Deviation 5. A snapshot-bootstrapped collection whose name later collides with another (from a rename, or genuinely a duplicate name) is not disambiguated until the next cursor-expired-triggered full reset re-derives state from a fresh snapshot with an actual `entity_id` from a subsequent `/changes` upsert. This is inherited from plan 03-04's `Playstead.Sync.CurationPayload.build/1`, out of this plan's file scope (`playstead-server/`) to fix directly; a future plan should add `id` to all six of that function's clauses so the snapshot branch carries the same identity the journal branch does.
- **Tasks 2 and 3 (the entire library shell UI, search/filter, and the `LIBR-01`/`LIBR-02`/`LIBR-04` requirements this plan targets) are not built.** They are blocked on the missing `03-UI-SPEC.md` (see Issues Encountered). `SyncEngine`, `CatalogueStore`, and `CurationStore` are ready for whichever plan builds that UI to consume directly.

## Next Phase Readiness

- **This plan is `status: halted`, not `complete`.** Per the plan-halt convention, any plan whose `depends_on` (directly or transitively) names this one is blocked until a follow-up run completes Tasks 2 and 3 and re-summarizes this plan as `complete`.
- **Immediate next step:** run `/gsd-ui-phase 3` to produce `03-UI-SPEC.md` (D-17: the shared status-glyph vocabulary, priority ladder, navigation noun order, and empty-state copy both the Mac client and the LiveView console — plan 03-05 — must cite). Plan 03-05 shares this exact precondition and is equally blocked.
- **Once `03-UI-SPEC.md` exists:** re-run/continue this plan starting at Task 2 (`Library shell — source list, shelves, cards, and the status vocabulary`), then Task 3 (`Finding things — search, filter chips, sortable list, show-all-systems, and offline browse`). `SyncEngine.state` (`SyncState`) is ready for `LibraryViewModel` to observe as-is.
- Plans `03-08`, `03-09`, `03-10` (this plan's declared `affects`) all depend on the library UI this plan was meant to also deliver; they remain blocked transitively until this plan reaches `complete`.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed (Task 1 only; plan halted): 2026-08-30*

## Self-Check: PASSED

- All `key-files.created` verified present on disk: `SyncEngine.swift`, `ChangesClient.swift`, `CursorStore.swift`, `JournalApplier.swift`, `CatalogueStore.swift`, `CurationStore.swift`, `SyncEngineTests.swift` all spot-checked with `[ -f ]` (matches `git diff --stat` against the pre-plan base).
- `git log --oneline --all --grep="03-06"` returns 2 commits: `0d0fd90` (RED), `ca9d057` (GREEN).
- Re-ran Task 1's `<acceptance_criteria>`: every bullet has a passing XCTest assertion (see coverage `D1`'s `verification` list above); all pass.
- Re-ran the corrected `<verify>` (`-only-testing:PlaysteadTests/SyncEngineTests`): 11/11 pass. Re-ran the plan-level `<verification>`'s full-suite line (`xcodebuild test -scheme Playstead`, unscoped): 34/34 pass, no regressions.
- Confirmed Task 2's `<precondition>` is genuinely unmet: `[ -f .planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md ]` fails; `.planning/phases/03-mac-offline-play-vertical-slice/03-05-SUMMARY.md` does not exist; `playstead-server/lib/playstead_web/live/library_live/{status_slot,sidebar}.ex` do not exist.
