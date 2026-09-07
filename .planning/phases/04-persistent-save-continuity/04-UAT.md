---
status: testing
phase: 04-persistent-save-continuity
source: [04-01-SUMMARY.md,04-02-SUMMARY.md 04-03-SUMMARY.md,04-04-SUMMARY.md 04-05-SUMMARY.md,04-06-SUMMARY.md 04-07-SUMMARY.md,04-08-SUMMARY.md 04-09-SUMMARY.md,04-10-SUMMARY.md 04-11-SUMMARY.md,04-12-SUMMARY.md 04-13-SUMMARY.md,04-14-SUMMARY.md 04-15-SUMMARY.md,04-16-SUMMARY.md 04-17-SUMMARY.md,04-18-SUMMARY.md 04-19-SUMMARY.md,04-20-SUMMARY.md 04-21-SUMMARY.md,04-22-SUMMARY.md 04-23-SUMMARY.md,04-24-SUMMARY.md 04-25-SUMMARY.md]
started: 2026-09-04T00:00:00Z
updated: 2026-09-07T00:00:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 113
name: Only-copy escalation default action feels non-destructive
expected: |
  See test 113 below. Test 108 reported an issue (G-04-1) — /saves lists only diverged
  lines, so its stated inspect/export purpose is unreachable on a healthy library.
  113 is the last open judgment checkpoint and is observable during Session B.
awaiting: user response

## Purpose

SAVE-03 ("the client captures a proven persistent save type, appends immutable
revisions, restores history...") has exactly **two** verification items, and
this document exists to keep them permanently, explicitly separate. A green
automated suite is not, and must never be read as, a passed continuation
proof. See D-68 in `04-CONTEXT.md`.

This file was regenerated on 2026-09-06T14:11:50Z to cover **all 25 plans** of the phase
(the previous revision covered plan 04-13 only). The two 04-13 rows and the
Explicit Separation Statement below are preserved verbatim from that revision;
CP7-SAVE-C's blocked status is untouched and may still only ever be set by a
developer performing the five steps in 04-13-PLAN.md's `<how-to-verify>`.

## Tests

### 1. Cold Start Smoke Test
expected: |
  Kill any running Playstead server and Mac app. Clear ephemeral state (dev DB, temp
  CAS/partials dirs, lock files). Start the application from scratch: the five Phase 4
  migrations apply cleanly with no manual step, the server boots without errors, and a
  primary query against a save surface returns live data.
result: pass
source: automated
evidence: |
  Executed this session via the project's own cold-start path,
  `playstead-server/scripts/compose-smoke.sh --fresh` — the script whose header names
  this exact UAT test. Run under an ISOLATED compose project
  (`COMPOSE_PROJECT_NAME=playstead-coldstart`, ports 18081/18444) so that
  `docker compose down -v` destroyed only throwaway volumes; the operator's real
  `playstead-server_playstead_db` / `_playstead_blobs` volumes and the live stack
  (up 2 days, healthy) were confirmed untouched before and after. Exit code 0.

  Observed:
    - named volumes destroyed, stack brought up from empty → all three services healthy
    - https://localhost:18444/healthz -> 200
    - https://localhost:18444/api/v1/capabilities -> 200
    - single-use setup token banner present (49 chars); /setup -> 200
    - server process (PID 1) runs as nobody (uid 65534) — setpriv drop intact
    - /app/blobs writable, /app/inbox listable-not-writable (D-01 :ro), /app/exports writable
    - marker row survived `down` + `up -d`; /healthz and /api/v1/capabilities 200 again
    - SUCCESS

  Migration half verified directly against the cold-start database:
    schema_migrations >= 20260904000001 → 20260904000001, ...02, ...03, ...04, ...05
    (all five Phase 4 migrations applied from an empty volume, no manual step)
    public save tables present → save_attention_items, save_lines, save_pending_uploads,
    save_revision_parents, save_revisions

  Evidence boundary: this proves server-tier cold start — migrations apply from zero,
  the app boots, and public endpoints answer. It says nothing about the Mac client,
  and nothing about a real emulator (see test 120).

### 2. Probe harness measures inode stability, mtime fidelity, FSEvents/vnode event delivery, and post-death writeback for a MAP_SHARED writer on APFS, emitting one schema-valid JSON report
expected: Probe harness measures inode stability, mtime fidelity, FSEvents/vnode event delivery, and post-death writeback for a MAP_SHARED writer on APFS, emitting one schema-valid JSON report
result: pass
source: automated
coverage_id: 04-01/D1
requirement: SAVE-01
verification: |
    - [pass] cd playstead-mac && swift scripts/probes/save-p1-probe.swift | python3 -c \"...\" (plan Task 1 <verify>)

### 3. Pinned 04-SAVE-P1-REPORT.json is schema-guarded by a stdlib unittest validator with a negative case per required key
expected: Pinned 04-SAVE-P1-REPORT.json is schema-guarded by a stdlib unittest validator with a negative case per required key
result: pass
source: automated
coverage_id: 04-01/D2
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/scripts/ci/tests/test_save_p1_probe.py (30 tests, all pass)

### 4. mgba_observed defaults to false and both the JSON and the human-readable .md name CP7-SAVE-C (plan 04-12) as the carrier of the real-emulator confirmation
expected: mgba_observed defaults to false and both the JSON and the human-readable .md name CP7-SAVE-C (plan 04-12) as the carrier of the real-emulator confirmation
result: pass
source: automated
coverage_id: 04-01/D3
requirement: SAVE-01
verification: |
    - [pass] grep -c mgba_observed 04-SAVE-P1-REPORT.md; python3 assertion on JSON field

### 5. Backup exclusion applies only to objects/, partials/, launch/, emulators/, bios/; root, saves/, and playstead.sqlite3 are never excluded; a stale pre-fix root flag is cleared idempotently at every launch
expected: Backup exclusion applies only to objects/, partials/, launch/, emulators/, bios/; root, saves/, and playstead.sqlite3 are never excluded; a stale pre-fix root flag is cleared idempotently at every launch
result: pass
source: automated
coverage_id: 04-02/D1
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/CacheTests/AppPathsBackupExclusionTests.swift (5 tests, all pass)

### 6. AdapterLaunchMutex refuses a second concurrent launch of the same assetSetID with .launchInProgress while a different assetSetID proceeds unaffected; an interrupted launch releases its key; process exit releases the key regardless of AdapterExit classification
expected: AdapterLaunchMutex refuses a second concurrent launch of the same assetSetID with .launchInProgress while a different assetSetID proceeds unaffected; an interrupted launch releases its key; process exit releases the key regardless of AdapterExit classification
result: pass
source: automated
coverage_id: 04-02/D2
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/AdapterTests/LaunchMutexTests.swift (7 tests, all pass)

### 7. saveDirectory readiness check blocks when a directory-writable-but-atomic-replace-fails case exists (an immutable file at the replace target), and carries the four locked copy strings verbatim; every outcome leaves the directory's contents unchanged
expected: saveDirectory readiness check blocks when a directory-writable-but-atomic-replace-fails case exists (an immutable file at the replace target), and carries the four locked copy strings verbatim; every outcome leaves the directory's contents unchanged
result: pass
source: automated
coverage_id: 04-02/D3
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/ReadinessTests/SaveDirectoryAtomicPlacementTests.swift (5 tests, all pass)

### 8. open_write/2 with reserve: :critical bypasses only the general free-space margin, never the 64 MiB physical floor; required_bytes/2 and fits_free_space?/3 are pinned unchanged for three input pairs
expected: open_write/2 with reserve: :critical bypasses only the general free-space margin, never the 64 MiB physical floor; required_bytes/2 and fits_free_space?/3 are pinned unchanged for three input pairs
result: pass
source: automated
coverage_id: 04-03/D1
requirement: SAVE-01
verification: |
    - [pass] playstead-server/test/playstead/readiness_critical_reserve_test.exs (13 tests, all pass)

### 9. The six save-domain problem codes (save_binding_incompatible, save_revision_digest_mismatch, save_revision_too_large, save_parent_unknown, save_branch_limit_exceeded, save_revision_immutable) resolve to their decided statuses and are present in the registry
expected: The six save-domain problem codes (save_binding_incompatible, save_revision_digest_mismatch, save_revision_too_large, save_parent_unknown, save_branch_limit_exceeded, save_revision_immutable) resolve to their decided statuses and are present in the registry
result: pass
source: automated
coverage_id: 04-03/D2
requirement: SAVE-01
verification: |
    - [pass] playstead-server/test/playstead_web/error_codes_test.exs (7 tests, all pass)

### 10. Save upload concurrency is accounted under a save:-prefixed UploadSlots key, distinct from the same device's import-slot counter; no parallel limiter or slots module was created
expected: Save upload concurrency is accounted under a save:-prefixed UploadSlots key, distinct from the same device's import-slot counter; no parallel limiter or slots module was created
result: pass
source: automated
coverage_id: 04-03/D3
requirement: SAVE-01
verification: |
    - [pass] playstead-server/test/playstead/readiness_critical_reserve_test.exs 'save-lane limits (D-33)' describe block (5 tests, all pass)

### 11. One save round-trips Mac to server: captured, stored locally, uploaded through the two save endpoints, and exists as a save_revisions row whose blob is in the Phase 2 CAS
expected: One save round-trips Mac to server: captured, stored locally, uploaded through the two save endpoints, and exists as a save_revisions row whose blob is in the Phase 2 CAS
result: pass
source: automated
coverage_id: 04-04/D1
requirement: SAVE-01
verification: |
    - [pass] playstead-server/test/playstead_web/controllers/api/v1/saves_controller_test.exs (2 tests, pass)

### 12. The server commit is atomic across blob, revision, journal, and idempotency receipt — a replayed metadata commit returns the original receipt and creates no second revision
expected: The server commit is atomic across blob, revision, journal, and idempotency receipt — a replayed metadata commit returns the original receipt and creates no second revision
result: pass
source: automated
coverage_id: 04-04/D2
requirement: SAVE-01
verification: |
    - [pass] playstead-server/test/playstead_web/controllers/api/v1/saves_controller_test.exs 'replaying the same Idempotency-Key' (pass)

### 13. Two devices committing to the same (user, content_key, save_kind, slot) identity tuple land on one save line (assumption-delta invariant)
expected: Two devices committing to the same (user, content_key, save_kind, slot) identity tuple land on one save line (assumption-delta invariant)
result: pass
source: automated
coverage_id: 04-04/D3
requirement: SAVE-01
verification: |
    - [pass] playstead-server/test/playstead/saves_test.exs (pass)

### 14. Capture requires three consecutive identical 1 Hz reads before promoting a revision; a fourth identical read produces no second capture; the post-exit settle pass is unconditional across all four AdapterExit classifications
expected: Capture requires three consecutive identical 1 Hz reads before promoting a revision; a fourth identical read produces no second capture; the post-exit settle pass is unconditional across all four AdapterExit classifications
result: pass
source: automated
coverage_id: 04-04/D4
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift (9 tests, pass)

### 15. A crash between the durable write and the row insert leaves the blob on disk with no referencing row (D-06) — no dangling reference, no lost promoted revision
expected: A crash between the durable write and the row insert leaves the blob on disk with no referencing row (D-06) — no dangling reference, no lost promoted revision
result: pass
source: automated
coverage_id: 04-04/D5
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift test_crashBetweenRenameAndRowInsert_leavesOrphanBlobNoReferencingRow (pass)

### 16. The upload lane drains ahead of the curation outbox and never reaches a silent terminal state — a repeatedly-failing entry stays visible (queued) and is retried, never quarantined
expected: The upload lane drains ahead of the curation outbox and never reaches a silent terminal state — a repeatedly-failing entry stays visible (queued) and is retried, never quarantined
result: pass
source: automated
coverage_id: 04-04/D6
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift (D-32 tests, pass)

### 17. The server's save journal payload follows the frozen-keys/inner-type template and Snapshot.read/1's save: branch is computed inside the same transaction as catalogue/curation, defaulting to [] rather than a missing key
expected: The server's save journal payload follows the frozen-keys/inner-type template and Snapshot.read/1's save: branch is computed inside the same transaction as catalogue/curation, defaulting to [] rather than a missing key
result: pass
source: automated
coverage_id: 04-04/D7
requirement: SAVE-02
verification: |
    - [pass] playstead-server/test/playstead/saves_test.exs 'the snapshot save: branch' (3 tests, pass)

### 18. JournalApplier's save case is idempotent by revision id (applying the same page twice leaves row count unchanged) and unconditionally decides to prefetch when the line's content is already present locally, never when it isn't
expected: JournalApplier's save case is idempotent by revision id (applying the same page twice leaves row count unchanged) and unconditionally decides to prefetch when the line's content is already present locally, never when it isn't
result: pass
source: automated
coverage_id: 04-04/D8
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift (4 new tests, pass)

### 19. The server accepts and branches a non-fast-forward commit -- two commits naming the same parent, or a second root, both succeed and both land as heads; there is no fast-forward requirement anywhere in the commit path (D-13)
expected: The server accepts and branches a non-fast-forward commit -- two commits naming the same parent, or a second root, both succeed and both land as heads; there is no fast-forward requirement anywhere in the commit path (D-13)
result: pass
source: automated
coverage_id: 04-05/D1
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_branches_test.exs (7 tests, pass)

### 20. Every revision records base_sha256 and a derived base_matched boolean; a mismatch is recorded and the commit still succeeds (D-12), and every ordering is by server recorded_at, never a device-claimed time (D-15)
expected: Every revision records base_sha256 and a derived base_matched boolean; a mismatch is recorded and the commit still succeeds (D-12), and every ordering is by server recorded_at, never a device-claimed time (D-15)
result: pass
source: automated
coverage_id: 04-05/D2
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_branches_test.exs (base evidence + ordering describe blocks, pass)

### 21. The three loud commit caps: save_parent_unknown (409 + Retry-After, retried transparently), save_branch_limit_exceeded at 32 heads, save_revision_immutable on any attempt to modify a committed revision
expected: The three loud commit caps: save_parent_unknown (409 + Retry-After, retried transparently), save_branch_limit_exceeded at 32 heads, save_revision_immutable on any attempt to modify a committed revision
result: pass
source: automated
coverage_id: 04-05/D3
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs (pass)

### 22. D-30's dedup invariant: a same-device byte-identical capture bumps confirm_count/last_confirmed_at with no new revision; a different-device byte-identical capture inserts a new revision sharing the blob
expected: D-30's dedup invariant: a same-device byte-identical capture bumps confirm_count/last_confirmed_at with no new revision; a different-device byte-identical capture inserts a new revision sharing the blob
result: pass
source: automated
coverage_id: 04-05/D4
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs (2 tests, pass)

### 23. GET .../history returns a line's revisions and derived heads, scoped by user_id; a cross-user line read is 404, never 403
expected: GET .../history returns a line's revisions and derived heads, scoped by user_id; a cross-user line read is 404, never 403
result: pass
source: automated
coverage_id: 04-05/D5
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs (2 tests, pass)

### 24. Choosing a side appends one resolution revision naming every divergent head as a parent (one chosen, the rest acknowledged), moves no head pointer, and deletes nothing; the resolution's blob is the chosen side's bytes and adds zero new CAS bytes
expected: Choosing a side appends one resolution revision naming every divergent head as a parent (one chosen, the rest acknowledged), moves no head pointer, and deletes nothing; the resolution's blob is the chosen side's bytes and adds zero new CAS bytes
result: pass
source: automated
coverage_id: 04-05/D6
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_test.exs (3 tests, pass)

### 25. N-way divergence resolves in a single act; two independent resolutions of the same fork (in either arrival order) converge to equal retained-revision sets with no compare-and-swap race; replaying the same idempotency key appends no second resolution revision
expected: N-way divergence resolves in a single act; two independent resolutions of the same fork (in either arrival order) converge to equal retained-revision sets with no compare-and-swap race; replaying the same idempotency key appends no second resolution revision
result: pass
source: automated
coverage_id: 04-05/D7
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_test.exs (3 tests, pass)

### 26. 'Keep both' leaves every head standing and marks the fork acknowledged so it is never re-raised as needing a decision, while its heads remain heads
expected: 'Keep both' leaves every head standing and marks the fork acknowledged so it is never re-raised as needing a decision, while its heads remain heads
result: pass
source: automated
coverage_id: 04-05/D8
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_test.exs (2 tests, pass)

### 27. A session with five quiescent changes produces five successive staged captures, each superseding the last, and exactly one promoted revision at session end; a zero-byte artifact never produces a revision
expected: A session with five quiescent changes produces five successive staged captures, each superseding the last, and exactly one promoted revision at session end; a zero-byte artifact never produces a revision
result: pass
source: automated
coverage_id: 04-06/D1
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift test_fiveQuiescentChanges_produceFiveStagedCaptures_andExactlyOnePromotedRevision, test_zeroByteArtifact_producesNoCapture (pass)

### 28. Opening a session with on-disk bytes differing from the last recorded revision creates a session-start baseline revision marked origin: external before any staged capture; matching bytes create no baseline; the promoted revision's parent is the baseline when one exists, else the line's prior head
expected: Opening a session with on-disk bytes differing from the last recorded revision creates a session-start baseline revision marked origin: external before any staged capture; matching bytes create no baseline; the promoted revision's parent is the baseline when one exists, else the line's prior head
result: pass
source: automated
coverage_id: 04-06/D2
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift (4 tests: sessionStart_bytesDiffer/Match/noKnownHead, promotedRevisionParent_isSessionBaseline/isLinePriorHead) (pass)

### 29. SaveArtifactSet is a sorted, timestamp-free manifest reproducible byte-for-byte across runs; the stored blob digest is the raw artifact sha256 and, for the single-entry mGBA case, differs from the manifest digest
expected: SaveArtifactSet is a sorted, timestamp-free manifest reproducible byte-for-byte across runs; the stored blob digest is the raw artifact sha256 and, for the single-entry mGBA case, differs from the manifest digest
result: pass
source: automated
coverage_id: 04-06/D3
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift test_artifactSet_isSortedAndTimestampFree..., test_storedBlobDigestEqualsRawSha256_andDiffersFromManifestDigest... (pass)

### 30. SaveSessionRecovery replays a crashed session's identical settle-then-promote pass at launch and produces the revision the crash prevented; a replay with nothing new produces no revision and no output; recovery never branches on how the session's process exited
expected: SaveSessionRecovery replays a crashed session's identical settle-then-promote pass at launch and produces the revision the crash prevented; a replay with nothing new produces no revision and no output; recovery never branches on how the session's process exited
result: pass
source: automated
coverage_id: 04-06/D4
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift test_replay_promotesTheRevisionTheCrashedSessionDidNot, test_replay_whenNothingChangedSinceLastRecordedRevision_producesNoRevision, test_recovery_runsIdenticallyForAllFourAdapterExitClassifications_andNoRecordedExit (pass)

### 31. Running recovery twice, or recovery racing a live poller's own promotion for the same session, produces exactly one promoted revision (idempotent-by-digest single-winner guard)
expected: Running recovery twice, or recovery racing a live poller's own promotion for the same session, produces exactly one promoted revision (idempotent-by-digest single-winner guard)
result: pass
source: automated
coverage_id: 04-06/D5
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift test_runningRecoveryTwice_..., test_runningRecoveryConcurrentlyWithLivePoller_... (pass)

### 32. A disk-full capture failure writes a durable blocked row, raises exactly one alert per distinct blockage, leaves a persistent attention state until cleared, is retried every subsequent poll cycle without stopping the running game, and deletes nothing
expected: A disk-full capture failure writes a durable blocked row, raises exactly one alert per distinct blockage, leaves a persistent attention state until cleared, is retried every subsequent poll cycle without stopping the running game, and deletes nothing
result: pass
source: automated
coverage_id: 04-06/D6
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift (4 tests: diskFullFailure_writesDurableBlockedRow, blockedCapture_isRetriedOnNextPollCycle, secondDiskFullFailure_..., diskFullFailure_deletesNothing_...) (pass)

### 33. The quota sum over cache objects and save revisions equals the cache-objects-only sum; the permitted download budget is reduced by exactly 268,435,456 bytes (256 MiB) relative to the same computation without the save reserve
expected: The quota sum over cache objects and save revisions equals the cache-objects-only sum; the permitted download budget is reduced by exactly 268,435,456 bytes (256 MiB) relative to the same computation without the save reserve
result: pass
source: automated
coverage_id: 04-06/D7
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift test_quotaSum_..., test_permittedDownloadBudget_isReducedByExactlyTheSaveReserve (pass)

### 34. No save revision ever appears in the eviction candidate list under maximum quota pressure; evicting a game removes its cached bytes and leaves its save revision count unchanged; unpinning a game does not expose its saves; no 'never evictable' status rung exists anywhere
expected: No save revision ever appears in the eviction candidate list under maximum quota pressure; evicting a game removes its cached bytes and leaves its save revision count unchanged; unpinning a game does not expose its saves; no 'never evictable' status rung exists anywhere
result: pass
source: automated
coverage_id: 04-06/D8
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift (4 tests: evictionCandidates_..., evictingAGame_..., unpinningAGame_..., noNeverEvictableStatusRung_...) (pass)

### 35. AdapterSaveContract's eight additive D-24 fields decode as nil against an older five-key pin, and the shipped pin decodes them populated with sram_32k as the only proven medium
expected: AdapterSaveContract's eight additive D-24 fields decode as nil against an older five-key pin, and the shipped pin decodes them populated with sram_32k as the only proven medium
result: pass
source: automated
coverage_id: 04-07/D1
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveCompatibilityGateTests.swift testOlderPinLackingEveryNewSaveContractKeyDecodesWithNilFields, testShippedPinDecodesTheNewOptionalFieldsPopulated (pass)

### 36. SaveCompatibilityGate returns exact/same_title/incompatible per D-18/D-19/D-20/D-22: identical tuples are exact; a certain same-title match on both sides widens; medium_id/artifact_bytes mismatches hard-block with no override affordance regardless of every other field; emulator/core/version differences never gate
expected: SaveCompatibilityGate returns exact/same_title/incompatible per D-18/D-19/D-20/D-22: identical tuples are exact; a certain same-title match on both sides widens; medium_id/artifact_bytes mismatches hard-block with no override affordance regardless of every other field; emulator/core/version differences never gate
result: pass
source: automated
coverage_id: 04-07/D2
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveCompatibilityGateTests.swift (14 tests, all pass)

### 37. LaunchSavePlanner.plan states and enforces D-44's governing invariant: restoring/fast-forwarding only ever happens into emptiness or over a proven ancestor of a single uncontested head; a diverged slot always yields .keep regardless of on-disk state; an incompatible or same_title verdict never silently restores
expected: LaunchSavePlanner.plan states and enforces D-44's governing invariant: restoring/fast-forwarding only ever happens into emptiness or over a proven ancestor of a single uncontested head; a diverged slot always yields .keep regardless of on-disk state; an incompatible or same_title verdict never silently restores
result: pass
source: automated
coverage_id: 04-07/D3
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/LaunchSavePlannerTests.swift (15 tests, all pass)

### 38. SavePlanExecutor writes only via stage/fsync/rename/fsync-directory, never in place; captures the current on-disk artifact before any restore/fast-forward write and aborts on capture failure; always fully re-hashes revision bytes and quarantines (never deletes) on mismatch; .fresh/.keep write nothing; the whole exercised path issues zero HTTP requests
expected: SavePlanExecutor writes only via stage/fsync/rename/fsync-directory, never in place; captures the current on-disk artifact before any restore/fast-forward write and aborts on capture failure; always fully re-hashes revision bytes and quarantines (never deletes) on mismatch; .fresh/.keep write nothing; the whole exercised path issues zero HTTP requests
result: pass
source: automated
coverage_id: 04-07/D4
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SavePlanExecutorTests.swift (11 tests, all pass)

### 39. The save plan executes inside the same per-assetSetID launch mutex as the process spawn -- a second concurrent launch for the same assetSetID is refused while executeSavePlan is still running
expected: The save plan executes inside the same per-assetSetID launch mutex as the process spawn -- a second concurrent launch for the same assetSetID is refused while executeSavePlan is still running
result: pass
source: automated
coverage_id: 04-07/D5
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SavePlanExecutorTests.swift testExecuteSavePlanRunsInsideThePerAssetSetIDLaunchMutex (pass)

### 40. Save revisions are exported into the reserved saves/ slot with sequence numbers in recorded_at order and device-independent branch letters
expected: Save revisions are exported into the reserved saves/ slot with sequence numbers in recorded_at order and device-independent branch letters
result: pass
source: automated
coverage_id: 04-08/D1
requirement: PORT-01
verification: |
    - [pass] playstead-server/test/playstead/export/saves_plan_test.exs (12 tests, pass)

### 41. A linear slot gets a drop-in saves/{stem}.sav copy named from the primary member's original basename; a diverged slot or a non-system_save revision gets none
expected: A linear slot gets a drop-in saves/{stem}.sav copy named from the primary member's original basename; a diverged slot or a non-system_save revision gets none
result: pass
source: automated
coverage_id: 04-08/D2
requirement: PORT-01
verification: |
    - [pass] playstead-server/test/playstead/export/saves_plan_test.exs (drop-in tests, pass)

### 42. The sidecar's saves key carries branches always present (even linear = single element), a companion saves.txt readable manifest, and a missing-bytes revision is named as missing while absent from manifest-sha256.txt/fetch.txt so sha256sum -c still succeeds
expected: The sidecar's saves key carries branches always present (even linear = single element), a companion saves.txt readable manifest, and a missing-bytes revision is named as missing while absent from manifest-sha256.txt/fetch.txt so sha256sum -c still succeeds
result: pass
source: automated
coverage_id: 04-08/D3
requirement: PORT-01
verification: |
    - [pass] playstead-server/test/playstead/export/sidecar_test.exs (9 tests, pass)

### 43. saves_scope is persisted on ExportRecord (migration + changeset) and Layout.plan/2's opts[:saves] reproduces the same plan from a persisted record; determinism is asserted as plan purity, write reproducibility (byte-identical except two Phase-2-inherited exceptions), and append-only stability
expected: saves_scope is persisted on ExportRecord (migration + changeset) and Layout.plan/2's opts[:saves] reproduces the same plan from a persisted record; determinism is asserted as plan purity, write reproducibility (byte-identical except two Phase-2-inherited exceptions), and append-only stability
result: pass
source: automated
coverage_id: 04-08/D4
requirement: PORT-01
verification: |
    - [pass] playstead-server/test/playstead/export/layout_test.exs (7 new tests, 17 total in file, pass)

### 44. The full pre-existing export suite and the full server test suite remain green after the sidecar/layout changes
expected: The full pre-existing export suite and the full server test suite remain green after the sidecar/layout changes
result: pass
source: automated
coverage_id: 04-08/D5
requirement: PORT-01
verification: |
    - [pass] mix test test/playstead/export/ (85 tests, pass); mix test full suite (961 tests, 0 failures, up from 933 baseline)

### 45. One shared save vocabulary (shared/save-vocabulary.json) is the single source every SAVE-02 string derives from, with both runtimes' copy-contract tests proving exhaustive bidirectional equality and zero banned-word hits
expected: One shared save vocabulary (shared/save-vocabulary.json) is the single source every SAVE-02 string derives from, with both runtimes' copy-contract tests proving exhaustive bidirectional equality and zero banned-word hits
result: pass
source: automated
coverage_id: 04-09/D1
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveCopyContractTests.swift (9 tests, pass)
    - [pass] playstead-server/test/playstead/save_copy_contract_test.exs (8 tests, pass)

### 46. Durability/current/restored are three independent axes (never one SaveStatus(for:) enum), durability is monotone, current is scoped to a (revision, device) pair, and conflicted is derived purely from a line's head set
expected: Durability/current/restored are three independent axes (never one SaveStatus(for:) enum), durability is monotone, current is scoped to a (revision, device) pair, and conflicted is derived purely from a line's head set
result: pass
source: automated
coverage_id: 04-09/D2
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift (16 tests, pass)

### 47. The game-level rollup implements D-36's first-match-wins header table (divergence beats every durability state, newest-revision durability only, never min()), the muted earlier-local-only line, and the empty 'No saves yet.' state
expected: The game-level rollup implements D-36's first-match-wins header table (divergence beats every durability state, newest-revision durability only, never min()), the muted earlier-local-only line, and the empty 'No saves yet.' state
result: pass
source: automated
coverage_id: 04-09/D3
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift (rollup tests within the same 16, pass)

### 48. The readiness Save row is purely navigational: it can never produce .blocked for any input including two divergent heads, never inflates the blocker count, and its two-versions case carries the 'Review versions…' action
expected: The readiness Save row is purely navigational: it can never produce .blocked for any input including two divergent heads, never inflates the blocker count, and its two-versions case carries the 'Review versions…' action
result: pass
source: automated
coverage_id: 04-09/D4
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift (readiness Save row tests within the same 16, pass); playstead-mac/PlaysteadTests/ReadinessTests/ReadinessEngineTests.swift (unaffected, still pass)

### 49. The per-game save history sheet renders a session-grouped timeline with a glyph set proven disjoint from the card's status ladder, zero new colour literal, no green, and the 'No saves yet.' empty state for zero revisions; only conflicted reaches the card via the existing rank-1 needsAttention rung with no snapshot rebaseline
expected: The per-game save history sheet renders a session-grouped timeline with a glyph set proven disjoint from the card's status ladder, zero new colour literal, no green, and the 'No saves yet.' empty state for zero revisions; only conflicted reaches the card via the existing rank-1 needsAttention rung with no snapshot rebaseline
result: pass
source: automated
coverage_id: 04-09/D5
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift (9 tests, pass, including glyph-disjointness and colour-literal scans)
    - [pass] playstead-mac/PlaysteadTests/SnapshotTests/LibraryContractSnapshotTests.swift (unaffected; zero reference-image diffs confirmed via git status)

### 50. Playstead.Attention.Reason's nine-member list is byte-identical before and after this plan, pinned by test and by an empty git diff
expected: Playstead.Attention.Reason's nine-member list is byte-identical before and after this plan, pinned by test and by an empty git diff
result: pass
source: automated
coverage_id: 04-10/D1
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_attention_source_test.exs (frozen vocabulary test, pass)
    - [pass] git diff playstead-server/lib/playstead/attention/reason.ex

### 51. Divergence, blocked capture, and per-user backstops raise/clear saves-owned attention items with their own reason vocabulary, upserting by grouping key rather than duplicating, unioned into the shared inbox at read time
expected: Divergence, blocked capture, and per-user backstops raise/clear saves-owned attention items with their own reason vocabulary, upserting by grouping key rather than duplicating, unioned into the shared inbox at read time
result: pass
source: automated
coverage_id: 04-10/D2
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_attention_source_test.exs (10 tests, pass)

### 52. Resolving or acknowledging a fork clears its divergence attention item; a backstop crossing raises an item and refuses no commit
expected: Resolving or acknowledging a fork clears its divergence attention item; a backstop crossing raises an item and refuses no commit
result: pass
source: automated
coverage_id: 04-10/D3
requirement: SAVE-04
verification: |
    - [pass] playstead-server/test/playstead/saves_attention_source_test.exs (resolve/acknowledge/backstop describe blocks, pass)

### 53. The exports console exposes exactly one saves-scope control (all/none), persisted and reproduced on re-enqueue; 'Export this version…' deep-links into the same Export.create_export/3 -> Export.Worker machinery
expected: The exports console exposes exactly one saves-scope control (all/none), persisted and reproduced on re-enqueue; 'Export this version…' deep-links into the same Export.create_export/3 -> Export.Worker machinery
result: pass
source: automated
coverage_id: 04-10/D5
requirement: PORT-01
verification: |
    - [pass] playstead-server/test/playstead_web/live/exports_live_test.exs (saves-scope describe block, pass)
    - [pass] playstead-server/test/playstead_web/live/saves_live_test.exs (export-this-version test, pass)

### 54. The full pre-existing server suite (995 tests) and the browser-coherence/palette/typography/keyboard-reachability contract suites remain green after adding the two new console screens
expected: The full pre-existing server suite (995 tests) and the browser-coherence/palette/typography/keyboard-reachability contract suites remain green after adding the two new console screens
result: pass
source: automated
coverage_id: 04-10/D6
requirement: SAVE-02
verification: |
    - [pass] mix test (995 tests, 0 failures); coherence/palette/typography/keyboard_reachability browser suites (all green)

### 55. A Mac saves attention source unions divergence (unacknowledged, exact-head-set-scoped) and blocked-capture items into the card's existing rank-1 needsAttention rung, with zero new case/glyph/colour/copy and no snapshot rebaseline
expected: A Mac saves attention source unions divergence (unacknowledged, exact-head-set-scoped) and blocked-capture items into the card's existing rank-1 needsAttention rung, with zero new case/glyph/colour/copy and no snapshot rebaseline
result: pass
source: automated
coverage_id: 04-11/D1
requirement: SAVE-04
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift#SaveAttentionSourceTests (15 tests, pass)
    - [pass] playstead-mac/PlaysteadTests/SnapshotTests/LibraryContractSnapshotTests.swift (unaffected; zero reference-image diffs confirmed via git status)

### 56. The comparison sheet renders exactly D-50's four facts per side, no file size/byte-diff/similarity/ordinal/parent, no highlight/pre-selection/colour/confirmation dialog/Undo, Keep Both as a peer action, N-way and not-downloaded variants, all keyboard-native
expected: The comparison sheet renders exactly D-50's four facts per side, no file size/byte-diff/similarity/ordinal/parent, no highlight/pre-selection/colour/confirmation dialog/Undo, Keep Both as a peer action, N-way and not-downloaded variants, all keyboard-native
result: pass
source: automated
coverage_id: 04-11/D2
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SnapshotTests/ConflictComparisonContractSnapshotTests.swift (10 tests, pass)

### 57. Choosing a side writes a local fork disposition and enqueues exactly one SaveOutbox entry in one transaction; the whole flow completes with the server unreachable and the entry drains later once reachable
expected: Choosing a side writes a local fork disposition and enqueues exactly one SaveOutbox entry in one transaction; the whole flow completes with the server unreachable and the entry drains later once reachable
result: pass
source: automated
coverage_id: 04-11/D4
requirement: SAVE-04
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift#SaveConflictResolverTests (13 tests, pass, including a real transport-failure-then-recovery round trip via StubURLProtocol)

### 58. Resolution never deletes a revision or moves a head pointer; both original heads remain present after every resolution; resolving the same fork twice is idempotent (no second entry); switching to the other side later is a legitimate new resolution
expected: Resolution never deletes a revision or moves a head pointer; both original heads remain present after every resolution; resolving the same fork twice is idempotent (no second entry); switching to the other side later is a legitimate new resolution
result: pass
source: automated
coverage_id: 04-11/D5
requirement: SAVE-04
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift#SaveConflictResolverTests (within the same 13 tests, pass)

### 59. The full pre-existing Mac Unit and Rendering suites remain green after adding the two new attention/comparison-sheet surfaces
expected: The full pre-existing Mac Unit and Rendering suites remain green after adding the two new attention/comparison-sheet surfaces
result: pass
source: automated
coverage_id: 04-11/D6
requirement: SAVE-02
verification: |
    - [pass] Unit test plan: 437 tests / 0 failures (was 399); Rendering test plan run against ConflictComparisonContractSnapshotTests: 10/10 pass

### 60. The escalated tier fires only on revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection; an offline queue, a slow upload, and a 30-day-old local-only version with a reachable server all produce no escalation, and this is structural (no date/elapsed-time field exists in the classifier's input) rather than merely tested
expected: The escalated tier fires only on revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection; an offline queue, a slow upload, and a 30-day-old local-only version with a reachable server all produce no escalation, and this is structural (no date/elapsed-time field exists in the classifier's input) rather than merely tested
result: pass
source: automated
coverage_id: 04-12/D1
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/OnlyCopyEscalationTests.swift (13 tests, pass)
    - [pass] playstead-mac/PlaysteadTests/SnapshotTests/OnlyCopyContractSnapshotTests.swift (7 tests, pass, including source-level no-colour and no-duration-logic scans)

### 61. The escalated panel renders the locked title/body with count/title/reason substituted and the three locked controls, persistent and inline, zero colour literal
expected: The escalated panel renders the locked title/body with count/title/reason substituted and the three locked controls, persistent and inline, zero colour literal
result: pass
source: automated
coverage_id: 04-12/D2
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/OnlyCopyEscalationTests.swift#testEscalationRendersTitleBodyWithCountTitleAndReasonSubstituted, testPanelCarriesTheThreeRequiredControls (pass)
    - [pass] playstead-mac/PlaysteadTests/SnapshotTests/OnlyCopyContractSnapshotTests.swift#testEscalatedPanelVisualContract, testReducedMotionSubstitutionVisualContract (pass, 2 new reference images)

### 62. StorageView and ReclaimPromptView's existing 'Reclaim selected' flows both route through the interruptive gate before evicting/removing, using a new per-candidate onlyOnThisMacCount input; a selection with zero affected candidates proceeds directly with no modal
expected: StorageView and ReclaimPromptView's existing 'Reclaim selected' flows both route through the interruptive gate before evicting/removing, using a new per-candidate onlyOnThisMacCount input; a selection with zero affected candidates proceeds directly with no modal
result: pass
source: automated
coverage_id: 04-12/D5
requirement: SAVE-01
verification: |
    - [pass] Full Mac Unit suite (457 tests, was 437) and Rendering suite (46 tests, StorageContractSnapshotTests unaffected) both green after the StorageView/ReclaimPromptView changes

### 63. The full pre-existing Mac Unit and Rendering suites remain green after adding the escalated and interruptive surfaces
expected: The full pre-existing Mac Unit and Rendering suites remain green after adding the escalated and interruptive surfaces
result: pass
source: automated
coverage_id: 04-12/D6
requirement: SAVE-02
verification: |
    - [pass] Unit test plan: 457 tests / 0 failures (was 437); Rendering test plan: 46 tests / 0 failures (2 skipped, pre-existing StorageContractSnapshotTests skip, unrelated to this plan)

### 64. The production Play path builds a LaunchSaveContext, asks LaunchSavePlanner.plan(context:) for a plan, and passes a non-nil executeSavePlan closure to AdapterHost.launch -- the default nil is never taken on the real Play path
expected: The production Play path builds a LaunchSaveContext, asks LaunchSavePlanner.plan(context:) for a plan, and passes a non-nil executeSavePlan closure to AdapterHost.launch -- the default nil is never taken on the real Play path
result: pass
source: automated
coverage_id: 04-14/D1
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift testProductionLaunchCallSitePassesANonNilExecuteSavePlan (pass)

### 65. A production SavePlanExecutorEnvironment exists, backed by the real CASManager; revisionBytes never fetches over the network for a digest absent from the CAS
expected: A production SavePlanExecutorEnvironment exists, backed by the real CASManager; revisionBytes never fetches over the network for a digest absent from the CAS
result: pass
source: automated
coverage_id: 04-14/D2
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/LaunchSaveEnvironmentTests.swift (8 tests, pass)

### 66. LaunchSaveContextBuilder assembles a context from already-local facts only: a head absent from the CAS is reported bytesLocal:false rather than omitted; onDiskDigest is nil for both a missing and a zero-byte target; a missing save line yields a context whose plan is a no-op
expected: LaunchSaveContextBuilder assembles a context from already-local facts only: a head absent from the CAS is reported bytesLocal:false rather than omitted; onDiskDigest is nil for both a missing and a zero-byte target; a missing save line yields a context whose plan is a no-op
result: pass
source: automated
coverage_id: 04-14/D3
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/LaunchSaveContextBuilderTests.swift (13 tests, pass)

### 67. A plan that requires a write reaches SavePlanExecutor with the resolved saves/<assetSetID>/<romBaseName>.sav target path; a throwing plan aborts the launch before AdapterHost ever spawns the emulator and releases the per-assetSetID mutex; no second mutex is introduced
expected: A plan that requires a write reaches SavePlanExecutor with the resolved saves/<assetSetID>/<romBaseName>.sav target path; a throwing plan aborts the launch before AdapterHost ever spawns the emulator and releases the per-assetSetID mutex; no second mutex is introduced
result: pass
source: automated
coverage_id: 04-14/D4
requirement: SAVE-03
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift testAWriteRequiringPlanRestoresTheExactBytesAtTheResolvedTargetPath, testAThrowingExecuteSavePlanAbortsBeforeTheEmulatorSpawns, testGameRowViewSourceNeverReferencesASecondLaunchMutex (pass)

### 68. A submitted parent_revision_id is accepted only when it belongs to the same save line as the revision being committed, backstopped by a database constraint
expected: A submitted parent_revision_id is accepted only when it belongs to the same save line as the revision being committed, backstopped by a database constraint
result: pass
source: automated
coverage_id: 04-15/D1
requirement: SAVE-01
verification: |
    - [pass] test/playstead/saves_lineage_scoping_test.exs#commit_revision/3 refuses a cross-save-line parent (CR-01)
    - [pass] test/playstead/saves_lineage_scoping_test.exs#a direct Repo.insert bypassing the context is rejected by the DATABASE constraint

### 69. D-33's save-revision hourly rate limit is invoked on the commit path and refuses an over-budget device
expected: D-33's save-revision hourly rate limit is invoked on the commit path and refuses an over-budget device
result: pass
source: automated
coverage_id: 04-15/D2
requirement: SAVE-04
verification: |
    - [pass] test/playstead_web/controllers/api/v1/saves_limits_test.exs#the save-revision rate limit is enforced on the commit path (D-33/CR-02)

### 70. D-33's namespaced save-upload concurrency slot is applied to the save-upload route, replay-safe against a retried command_id
expected: D-33's namespaced save-upload concurrency slot is applied to the save-upload route, replay-safe against a retried command_id
result: pass
source: automated
coverage_id: 04-15/D3
requirement: SAVE-04
verification: |
    - [pass] test/playstead_web/controllers/api/v1/saves_limits_test.exs#the save-upload concurrency slot is namespaced and applied (D-33/CR-02)

### 71. MC-01: OnlyCopyInterruptionGate fires from both reclaim surfaces with a real, committed-state-derived only-copy count
expected: MC-01: OnlyCopyInterruptionGate fires from both reclaim surfaces with a real, committed-state-derived only-copy count
result: pass
source: automated
coverage_id: 04-16/D1
requirement: SAVE-01
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/OnlyCopyWiringTests.swift#testReclaimCandidateRowsCarryRealOnlyOnThisMacCount, #testReclaimCandidateRowsReportZeroWhenEverythingIsUploaded, #testInFlightUploadStillCountsAsOnlyOnThisMac, #testStorageSnapshotCarriesRealOnlyOnThisMacCounts, #testStorageSnapshotOmitsCandidatesWithNoOnlyCopyRevisions

### 72. MC-03: the card's divergence badge unions into the existing rank-1 status rung without bypassing higher-ranked statuses
expected: MC-03: the card's divergence badge unions into the existing rank-1 status rung without bypassing higher-ranked statuses
result: pass
source: automated
coverage_id: 04-16/D3
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift#testDivergedLineYieldsTheBadgeThroughTheRealStatusPath, #testNonDivergedLineYieldsNoBadge, #testDisposedForkStopsRaisingTheBadge

### 73. MC-04: the D-37 Save row reports real SaveReadinessCase state instead of always the empty state
expected: MC-04: the D-37 Save row reports real SaveReadinessCase state instead of always the empty state
result: pass
source: automated
coverage_id: 04-16/D4
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift#testReadinessSaveRowReportsRealStateForAGameWithSavedProgress, #testReadinessSaveRowReportsEmptyStateOnlyWhenGenuinelyEmpty, #testReadinessSaveRowReportsTwoVersionsForADivergedLine

### 74. MC-06: ConflictComparisonSheet is reachable from ReadinessSheetView for a genuine fork and its choose/keep-both actions perform real, append-only SaveConflictResolver mutations
expected: MC-06: ConflictComparisonSheet is reachable from ReadinessSheetView for a genuine fork and its choose/keep-both actions perform real, append-only SaveConflictResolver mutations
result: pass
source: automated
coverage_id: 04-16/D6
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift#testConflictSidesReflectTheRealCommittedHeads, #testResolvingChoosesASideAndDisposesTheFork

### 75. No regression: full Unit test plan and Rendering test plan remain green, and reachability-sweep.sh reports no zero-caller user-facing symbol under Playstead/Saves/
expected: No regression: full Unit test plan and Rendering test plan remain green, and reachability-sweep.sh reports no zero-caller user-facing symbol under Playstead/Saves/
result: pass
source: automated
coverage_id: 04-16/D7
verification: |
    - [pass] xcodebuild test-without-building -testPlan Unit (499/499, 0 failures); -testPlan Rendering (46/46, 0 failures, no snapshot drift); scripts/ci/reachability-sweep.sh (no user-facing Saves/ symbol)

### 76. Staged-save write replaces its target atomically via rename(2) -- no crash window where the file is observably absent (WR-02)
expected: Staged-save write replaces its target atomically via rename(2) -- no crash window where the file is observably absent (WR-02)
result: pass
source: automated
coverage_id: 04-17/D1
requirement: SAVE-01
verification: |
    - [pass] PlaysteadTests/SavesTests/SaveCaptureAtomicityTests.swift (6 tests)
    - [pass] grep -n 'removeItem(at: finalURL)' playstead-mac/Playstead/Saves/SaveCapturePoller.swift (no match)

### 77. Journal echo of a self-authored revision preserves tier/origin/manifestDigest/sessionID/artifactSetJSON instead of blanking them, and SaveSessionRecovery's staged/promoted pairing survives the round-trip (WR-01)
expected: Journal echo of a self-authored revision preserves tier/origin/manifestDigest/sessionID/artifactSetJSON instead of blanking them, and SaveSessionRecovery's staged/promoted pairing survives the round-trip (WR-01)
result: pass
source: automated
coverage_id: 04-17/D2
requirement: SAVE-02
verification: |
    - [pass] PlaysteadTests/SyncTests/JournalRevisionMergeTests.swift (6 tests)

### 78. Compaction exempts fork-acknowledgment entries from deletion, so a resolved fork is not re-raised past the retention horizon, while ordinary entries are still deleted on schedule (WS-01)
expected: Compaction exempts fork-acknowledgment entries from deletion, so a resolved fork is not re-raised past the retention horizon, while ordinary entries are still deleted on schedule (WS-01)
result: pass
source: automated
coverage_id: 04-17/D3
requirement: SAVE-02
verification: |
    - [pass] playstead-server/test/playstead/sync/compaction_retention_test.exs (5 tests)

### 79. reachability-sweep.sh --strict exits 0 on the current tree with a small (23-entry), fully-reasoned allowlist, and is registered as a gate in run-mac-verification.sh
expected: reachability-sweep.sh --strict exits 0 on the current tree with a small (23-entry), fully-reasoned allowlist, and is registered as a gate in run-mac-verification.sh
result: pass
source: automated
coverage_id: 04-18/D2
requirement: SAVE-02
verification: |
    - [pass] playstead-mac/scripts/ci/reachability-sweep.sh --strict (exit 0); awk allowlist-reason check (exit 0); grep -c reachability run-mac-verification.sh == 11

### 80. Mac Unit and Rendering test plans remain at their post-04-17 baselines with no regressions
expected: Mac Unit and Rendering test plans remain at their post-04-17 baselines with no regressions
result: pass
source: automated
coverage_id: 04-18/D4
verification: |
    - [pass] xcodebuild test-without-building -testPlan Unit: 511/511, 0 failures; -testPlan Rendering: 44/44 passed + 2 expected local skips (hosted-only canary), 0 failures

### 81. Playing a game and quitting the emulator produces a promoted save revision in SaveStore, created by the shipped app's own code path, with no test flag set
expected: Playing a game and quitting the emulator produces a promoted save revision in SaveStore, created by the shipped app's own code path, with no test flag set
result: pass
source: automated
coverage_id: 04-19/D1
requirement: SAVE-01
verification: |
    - [pass] PlaysteadTests.PlayPathSaveWiringTests/testAFullSessionThroughTheProductionSeamPromotesARevisionIntoTheAppsSaveStore -- drives GameRowView.buildSaveCaptureCoordinator (the exact object play() builds), writes save bytes, ends, asserts exactly one promoted localOnly revision with the written bytes' digest
    - [pass] PlaysteadTests.SaveSessionCoordinatorTests (12 tests: baseline on out-of-band change, promotion, parenting, no-change-no-promotion, end-without-begin, double-end, double-begin, blocked capture, blockage clearing, no-reimplementation source guard)
    - [pass] PlaysteadTests.PlayPathSaveWiringTests/testProductionPlayPathBeginsAndEndsACaptureSession -- asserts play()'s source begins the session before adapterHost.launch and ends it inside onExit before playSessionRecorder.ended. FALSIFIED: deleting the begin() call turned this test red with 'play() must open a capture session'.

### 82. An app launch that follows a crash mid-session replays the abandoned session through SaveSessionRecovery
expected: An app launch that follows a crash mid-session replays the abandoned session through SaveSessionRecovery
result: pass
source: automated
coverage_id: 04-19/D3
requirement: SAVE-01
verification: |
    - [pass] PlaysteadTests.PlayPathSaveWiringTests/testAppLaunchReplaysAnAbandonedSessionAndPromotesIt -- seeds exactly the staged-row-with-no-promoted-row a crashed session leaves, calls environment.recoverAbandonedSaveSessionsAtLaunch(), asserts one promoted revision with captureMethod 'recovery' and the crashed session's id
    - [pass] PlaysteadTests.PlayPathSaveWiringTests/testASecondRecoveryPassPromotesNothingNew -- D-07 idempotence
    - [pass] PlaysteadTests.PlayPathSaveWiringTests/testProductionAppLaunchRunsSaveSessionRecovery -- asserts ProductionRootView's .task actually calls it

### 83. The capture lifecycle lives in ONE named production type that both the Play path and the tests construct -- not duplicated inline in a SwiftUI view body
expected: The capture lifecycle lives in ONE named production type that both the Play path and the tests construct -- not duplicated inline in a SwiftUI view body
result: pass
source: automated
coverage_id: 04-19/D4
verification: |
    - [pass] SaveSessionCoordinator.swift is the only capture lifecycle; play() calls buildSaveCaptureCoordinator and nothing else. SaveSessionCoordinatorTests/testTheCoordinatorReimplementsNoCaptureLogic asserts the coordinator calls poller.startSession/settle/promote and declares no settle/promote/digest/quiescence of its own.

### 84. SaveUploadLane's real failure classification reaches AppEnvironment.saveUploadFailureClassification(), replacing the online/offline-only stub, closing WINDOWS #40
expected: SaveUploadLane's real failure classification reaches AppEnvironment.saveUploadFailureClassification(), replacing the online/offline-only stub, closing WINDOWS #40
result: pass
source: automated
coverage_id: 04-19/D5
requirement: SAVE-04
verification: |
    - [pass] PlaysteadTests.SaveSurfaceWiringTests: device_revoked -> .revokedAuth (and OnlyCopyEscalation.evaluate now returns a non-nil escalation); save_binding_incompatible -> .compatibilityRejection; capability_incompatible -> .capabilitySkew; 500 -> .none; offline outranks a recorded .revokedAuth -> .offlineQueue
    - [pass] testTheAssembledEnvironmentOwnsALiveUploadLane -- asserts the constant 'reachability.isOnline ? .none : .offlineQueue' no longer appears in PlaysteadApp.swift

### 85. The reachability allowlist SHRINKS by exactly the symbols this plan wires; the sweep stays at zero findings under --strict
expected: The reachability allowlist SHRINKS by exactly the symbols this plan wires; the sweep stays at zero findings under --strict
result: pass
source: automated
coverage_id: 04-19/D6
verification: |
    - [pass] git diff --stat reachability-allowlist.txt -> 5 deletions, 0 insertions on the entry lines (the header comment was separately updated to record why); scripts/ci/reachability-sweep.sh --strict exits 0

### 86. No regression in the Mac test suites
expected: No regression in the Mac test suites
result: pass
source: automated
coverage_id: 04-19/D7
verification: |
    - [pass] xcodebuild test-without-building -testPlan Unit: 536 tests, 0 failures (baseline 511, +25 new); -testPlan Rendering: 46 executed, 2 skipped, 0 failures (baseline 44 passed + 2 expected local skips)

### 87. An export of a game with a committed save revision writes that revision's real bytes into the bag; the saves/ slot for a game with revisions is non-empty on disk and the bag verifies (ROADMAP criterion 4).
expected: An export of a game with a committed save revision writes that revision's real bytes into the bag; the saves/ slot for a game with revisions is non-empty on disk and the bag verifies (ROADMAP criterion 4).
result: pass
source: automated
coverage_id: 04-21/D1
requirement: PORT-01
verification: |
    - [pass] test/playstead/export/saves_loading_test.exs#an export of a game with one committed save revision writes that revision's real bytes into the bag
    - [pass] test/playstead/export/saves_loading_test.exs#an asset set with zero save lines still produces an empty saves/ slot and a bag that verifies
    - [pass] test/playstead/export/saves_loading_test.exs#deleting the :saves key from to_layout_input/2 makes this test go red (falsification check)

### 88. Both sides of a real save divergence export under stable, distinct branch letters, and re-planning the same fork reproduces the same letters (ROADMAP criterion 5's export deep link is real, not an empty slot).
expected: Both sides of a real save divergence export under stable, distinct branch letters, and re-planning the same fork reproduces the same letters (ROADMAP criterion 5's export deep link is real, not an empty slot).
result: pass
source: automated
coverage_id: 04-21/D2
requirement: SAVE-04
verification: |
    - [pass] test/playstead/export/saves_lineage_test.exs#a two-way fork yields two distinct non-nil keys, inherited by every descendant of each side
    - [pass] test/playstead/export/saves_lineage_test.exs#two sides of a real fork export under stable, distinct branch letters, and re-planning is stable

### 89. A revision whose bytes are not on this server is named in the sidecar/manifest as missing, its file is absent from the payload, and the bag still verifies (D-61).
expected: A revision whose bytes are not on this server is named in the sidecar/manifest as missing, its file is absent from the payload, and the bag still verifies (D-61).
result: pass
source: automated
coverage_id: 04-21/D3
verification: |
    - [pass] test/playstead/export/saves_lineage_test.exs#a revision whose blob is absent from the store produces no payload file, no manifest line, and a bag that still verifies

### 90. A battery (system) save line with a single linear head earns a saves/<stem>.sav drop-in copy; a diverged line does not.
expected: A battery (system) save line with a single linear head earns a saves/<stem>.sav drop-in copy; a diverged line does not.
result: pass
source: automated
coverage_id: 04-21/D4
verification: |
    - [pass] test/playstead/export/saves_lineage_test.exs#a battery line with a single linear head gets a saves/<stem>.sav drop-in copy
    - [pass] test/playstead/export/saves_lineage_test.exs#a diverged line (multiple heads) gets no drop-in copy

### 91. Append-only stability (D-59): a later commit never renumbers or renames an earlier revision's exported filename. Re-exporting is idempotent. Two users sharing a content_key never see each other's save bytes (T-04-21-01).
expected: Append-only stability (D-59): a later commit never renumbers or renames an earlier revision's exported filename. Re-exporting is idempotent. Two users sharing a content_key never see each other's save bytes (T-04-21-01).
result: pass
source: automated
coverage_id: 04-21/D5
verification: |
    - [pass] test/playstead/export/round_trip_test.exs#an appended revision never renumbers or renames a pre-existing revision's exported file (D-59)
    - [pass] test/playstead/export/round_trip_test.exs#re-running the export worker twice against one target leaves every payload byte-identical and still verifies
    - [pass] test/playstead/export/round_trip_test.exs#a second user sharing the same content_key never sees the first user's save bytes (T-04-21-01)

### 92. A restore or fast-forward through the real launch path leaves a durable, immutable restored-here timestamp on the matching revision; an existing install upgrades in place.
expected: A restore or fast-forward through the real launch path leaves a durable, immutable restored-here timestamp on the matching revision; an existing install upgrades in place.
result: pass
source: automated
coverage_id: 04-22/D1
requirement: SAVE-02
verification: |
    - [pass] PlaysteadTests/SavesTests/SaveStoreTests.swift#testMarkingRestoredTwiceKeepsTheFirstTimestamp
    - [pass] PlaysteadTests/SavesTests/SaveStoreTests.swift#testAnExistingInstallWhoseTablePredatesTheColumnStillOpensWithNilProvenance
    - [pass] PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift#testARestorePlanMarksTheMatchingRevisionRestoredHereAfterExecuting
    - [pass] PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift#testAKeepPlanMarksNoRevisionRestoredHere

### 93. Opening 'Review versions…' for a game with real save history renders that history, with each row reporting durability, position, provenance and lineage from committed SaveStore data -- not the empty state (WINDOWS #43).
expected: Opening 'Review versions…' for a game with real save history renders that history, with each row reporting durability, position, provenance and lineage from committed SaveStore data -- not the empty state (WINDOWS #43).
result: pass
source: automated
coverage_id: 04-22/D2
requirement: SAVE-02
verification: |
    - [pass] PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift (16 tests, one per <behavior> bullet plus an AppEnvironment integration case)
    - [pass] PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift#testBothReadinessSheetViewCallSitesPassARealSaveHistorySessionsClosure

### 94. SaveRollup.rollup(for:) has a real production caller and the reachability allowlist is one line shorter, closing WINDOWS #47.
expected: SaveRollup.rollup(for:) has a real production caller and the reachability allowlist is one line shorter, closing WINDOWS #47.
result: pass
source: automated
coverage_id: 04-22/D3
verification: |
    - [pass] scripts/ci/reachability-sweep.sh --strict (exit 0, allowlist shrunk by exactly the SaveRollup line)
    - [pass] PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift#testPopulatedHistoryWithSummaryVisualContract
    - [pass] PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift#testSaveRollupSummaryReturnsTheTwoVersionsHeaderForADivergedLineAndOnServerForAnUploadedNewest

### 95. A divergence resolved on this Mac reaches the server: SaveOutbox.drainOnce(apiClient:) has a production call site fired on the same trigger classes Outbox/SaveUploadLane use (ROADMAP criterion 5's resolve verb).
expected: A divergence resolved on this Mac reaches the server: SaveOutbox.drainOnce(apiClient:) has a production call site fired on the same trigger classes Outbox/SaveUploadLane use (ROADMAP criterion 5's resolve verb).
result: pass
source: automated
coverage_id: 04-23/D1
requirement: SAVE-04
verification: |
    - [pass] PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift (9 tests covering every <behavior> bullet)
    - [pass] PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testResolvingThroughTheProductionEntryPointReachesTheWireWithTheRightPathAndKey

### 96. A save revision recovered from a crashed session has its bytes in the CAS, so LaunchSaveContextBuilder reports bytesLocal: true for it and zero-network restore of a crash-recovered revision works (ROADMAP criterion 3).
expected: A save revision recovered from a crashed session has its bytes in the CAS, so LaunchSaveContextBuilder reports bytesLocal: true for it and zero-network restore of a crash-recovered revision works (ROADMAP criterion 3).
result: pass
source: automated
coverage_id: 04-23/D2
requirement: SAVE-01
verification: |
    - [pass] PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_replay_commitsThePromotedRevisionsBytesToTheCAS
    - [pass] PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_launchSaveContextBuilder_reportsBytesLocalTrue_forACrashRecoveredRevision
    - [pass] PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_falsification_bytesLocalIsFalseWhenTheCASWasNeverCommittedTo

### 97. Running crash recovery twice commits the same digest to the CAS at most once and inserts no second revision row; a CAS commit that throws still inserts the row and records a blockage without propagating.
expected: Running crash recovery twice commits the same digest to the CAS at most once and inserts no second revision row; a CAS commit that throws still inserts the row and records a blockage without propagating.
result: pass
source: automated
coverage_id: 04-23/D3
requirement: SAVE-03
verification: |
    - [pass] PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_replayAllRunTwice_insertsNoSecondRow_commitsNoSecondCopy
    - [pass] PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_aThrowingCASCommit_stillInsertsTheRow_recordsABlockage_andReplayReturnsNormally

### 98. Draining the save outbox twice sends each entry under the same Idempotency-Key and a delivered entry is deleted; a rejected send leaves local resolution intact and increments attempt_count.
expected: Draining the save outbox twice sends each entry under the same Idempotency-Key and a delivered entry is deleted; a rejected send leaves local resolution intact and increments attempt_count.
result: pass
source: automated
coverage_id: 04-23/D4
verification: |
    - [pass] PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testEverySendCarriesTheEntrysIdempotencyKeyAndARetryReplaysTheSameKey
    - [pass] PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testARejectedSendLeavesTheEntryQueuedAndDispositionUntouched
    - [pass] PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testASuccessfulDrainDeletesTheEntryAndASecondDrainSendsNothing

### 99. The WINDOWS ledger reports the same thing the source does: #30, #42, #43, #47, #52 fixed with resolving commits; stale #32 closed with the commit that actually resolved it; CP7-SAVE-C left untouched.
expected: The WINDOWS ledger reports the same thing the source does: #30, #42, #43, #47, #52 fixed with resolving commits; stale #32 closed with the commit that actually resolved it; CP7-SAVE-C left untouched.
result: pass
source: automated
coverage_id: 04-23/D5
verification: |
    - [pass] gsd-tools windows status (ok: true); WINDOWS.md counters open_count 41->35, fixed_count 11->17, total_count unchanged at 53
    - [pass] 6 confirming greps from 04-VERIFICATION's spot-check table, each returning the opposite of what verification recorded

### 100. Playstead.Saves.get_history/2 and Playstead.Saves.Branches.heads/2 return revisions in a total order (recorded_at asc, id asc), eliminating unspecified Postgres tie behavior
expected: Playstead.Saves.get_history/2 and Playstead.Saves.Branches.heads/2 return revisions in a total order (recorded_at asc, id asc), eliminating unspecified Postgres tie behavior
result: pass
source: automated
coverage_id: 04-24/D1
requirement: PORT-01
verification: |
    - [pass] test/playstead/saves_test.exs#get_history/2 returns a recorded_at tie in a stable id-ascending order
    - [pass] test/playstead/saves_branches_test.exs#heads/2 returns a recorded_at tie in a stable id-ascending order

### 101. Two revisions committed at the same microsecond (the concurrent-device divergence shape) receive identical seq and filenames across two independent, real export runs -- demonstrated red against the unfixed order_by clauses before landing
expected: Two revisions committed at the same microsecond (the concurrent-device divergence shape) receive identical seq and filenames across two independent, real export runs -- demonstrated red against the unfixed order_by clauses before landing
result: pass
source: automated
coverage_id: 04-24/D2
requirement: PORT-01
verification: |
    - [pass] test/playstead/export/round_trip_test.exs#two revisions sharing one recorded_at keep identical seq and filenames across two independent exports (D-59)

### 102. SavesPlan.plan/2 produces the identical plan (entries, seq, relative) for the same revision set regardless of caller input order, so pure-planner determinism no longer depends on the caller's query having sorted correctly
expected: SavesPlan.plan/2 produces the identical plan (entries, seq, relative) for the same revision set regardless of caller input order, so pure-planner determinism no longer depends on the caller's query having sorted correctly
result: pass
source: automated
coverage_id: 04-24/D3
requirement: SAVE-04
verification: |
    - [pass] test/playstead/export/saves_plan_test.exs#plan/2 breaks a recorded_at tie by revision id regardless of input list order

### 103. No user_id scoping, filename grammar, seq allocation mechanics, branch-letter assignment, or drop-in naming rule was altered; the change is confined to order_by clauses and the planner's sort comparator
expected: No user_id scoping, filename grammar, seq allocation mechanics, branch-letter assignment, or drop-in naming rule was altered; the change is confined to order_by clauses and the planner's sort comparator
result: pass
source: automated
coverage_id: 04-24/D4
verification: |
    - [pass] grep -c 'user_id == ^user_id' branches.ex unchanged; git diff shows no change to filename_for/4, pad/1, assign_branch_letters/1, plan_drop_in/4; git diff --stat priv/repo/migrations is empty

### 104. SaveOutboxDrainTrigger.fire() serializes the predecessor read and _lastTask replacement inside one critical section, closing the TOCTOU race 04-VERIFICATION gap 2 / 04-REVIEW-gaps-mac.md CR-01 identified
expected: SaveOutboxDrainTrigger.fire() serializes the predecessor read and _lastTask replacement inside one critical section, closing the TOCTOU race 04-VERIFICATION gap 2 / 04-REVIEW-gaps-mac.md CR-01 identified
result: pass
source: automated
coverage_id: 04-25/D1
requirement: SAVE-04
verification: |
    - [pass] SaveOutboxDrainTriggerTests.swift#testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass
    - [pass] SaveOutboxDrainTriggerTests.swift#testTwoOverlappingDrainPassesProduceAtMostOneSuccessfulSend
    - [pass] awk-extracted fire() body source gate: exactly one lock.lock()/lock.unlock() pair

### 105. No second copy of the read-then-separately-write defect exists elsewhere in Sync/ or Saves/; the full Mac and server test gates remain green
expected: No second copy of the read-then-separately-write defect exists elsewhere in Sync/ or Saves/; the full Mac and server test gates remain green
result: pass
source: automated
coverage_id: 04-25/D2
requirement: SAVE-04
verification: |
    - [pass] Unit test plan: 583 tests, 582 passed, 1 pre-existing unrelated flake (isolated re-run passed)
    - [pass] playstead-mac/scripts/ci/reachability-sweep.sh --strict
    - [pass] playstead-server MIX_ENV=test mix test — 1034 tests, 0 failures
### 106. A live end-to-end run captures one artifact on the Mac, uploads it, and observes the same revision arriving back through the journal with ma…
expected: |
  A live end-to-end run captures one artifact on the Mac, uploads it, and observes the same revision arriving back through the journal with matching digest and size
result: blocked
blocked_by: server
source: human
reason: |
  Needs the hosted CI live-server fixture (PLAYSTEAD_MAC_CI_ROOT et al. unset here) AND a real app launch. playstead-mac/scripts/ci/run-mac-verification.sh:1026 refuses local UI/LiveServer verification outright: "local UI/LiveServer verification is disabled because launching Playstead may request login-Keychain authorization; a human may explicitly set PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1, but automated GSD runs must not set it". This session honored that prohibition rather than working around it. Resolvable by the hosted runner, or by a human setting that variable themselves.
coverage_id: 04-04/D9
reason_human: human_judgment
rationale: |
  This environment has no hosted CI live-server fixture (PLAYSTEAD_MAC_CI_ROOT etc. unset) and UI-testing automation permission could not be granted in this sandboxed session, so the test could not be executed here. It builds, is correctly registered, and follows LiveServerSnapshotTests' exact fixture-gated pattern verbatim; the CI-runner execution is the only way to prove it green, and the real-hardware half (a real mGBA process, a real commercial game, 'Continue the game' actually working) is explicitly out of reach for any automation per D-68 and is carried by the separately named checkpoint CP7-SAVE-C (plan 04-12).

### 107. A real emulator accepts a restored .sav and shows the player's actual in-game progress (the 'Continue the game' human half of SAVE-03) -- no…
expected: |
  A real emulator accepts a restored .sav and shows the player's actual in-game progress (the 'Continue the game' human half of SAVE-03) -- not automatable; the file-identity half is proven above
result: blocked
blocked_by: physical-device
source: human
reason: |
  Requires a real emulator process and real commercial game bytes. Same constraint as CP7-SAVE-C (test 120); not automatable by any means available here. The file-identity half is proven by test 118.
coverage_id: 04-07/D6
reason_human: human_judgment
rationale: |
  Blocked on checkpoint 7 (real emulator + real game bytes), consistent with the phase's named blocked checkpoint CP7-SAVE-C. This plan proves every byte-level and mutex/atomicity property automatable today; a human must observe the emulator's own Continue/Load screen on real hardware.

### 108. The console can inspect, choose, keep both, and export a diverged save line at /saves and /saves/:id — exactly four facts per side, digest b…
expected: |
  The console can inspect, choose, keep both, and export a diverged save line at /saves and /saves/:id — exactly four facts per side, digest behind Details only, no confirmation dialog, no Undo, no recommended/pre-selected side, no bulk always-use-this-Mac control, all asserted absent by test
result: pass
gap_id: G-04-1
closed: |
  Fixed in 33a3fc5 and proven by three reachability tests that were verified to fail
  against the old diverged-only filter (mix precommit 1037/0). The running dev
  container was rebuilt on 2026-09-07 — it had been built at 14:27Z, before the 02:47Z
  fix, so the deployed page still served the old copy. Same stale-image trap that
  produced this phase's original /saves 404: a green test tree says nothing about what
  the running container is serving.
source: human
coverage_id: 04-10/D4
reason_human: human_judgment
rationale: |
  Automated tests assert the DOM-level absences and the correct context calls; the actual visual read (does the sheet feel calm, does keyboard order feel natural) is a genuine UX judgment call no test proves.
reported: |
  The user opened /saves on a healthy library and saw only the header "Saves — Inspect,
  choose, and export save versions." above the empty state "Nothing needs a decision
  right now." Their words: "that's ur saves right, 'needs a decision right now' doesn't
  really fit into the psychology of our user who is a gamer trying to look at their
  saves."

  This is not a copy nit. saves_live.ex:51-59 filters every save line through
  Saves.needs_divergence_decision?/2, so /saves lists ONLY unresolved conflicts. For a
  user whose saves are healthy — the overwhelmingly common case, since divergence is by
  design the exception — two of the header's three promised verbs are unreachable:
  "inspect" has nothing to list, and "export" lives on /saves/:id which is only
  navigable from that list. Only "choose" works, and only during a conflict.

  Compounding it: /attention already owns the needs-a-decision queue and owns it better.
  attention_live.ex:66 unions SavesAttention.list_items/1 into the inbox and :351 links
  each card to /saves/#{grouping_key}. So /saves currently duplicates /attention's job
  while failing its own.

  Scope note: the capability is not missing. load_line (saves_live.ex:62) calls
  Saves.get_history, which returns the line and its heads for ANY line; with a single
  head, sides has one entry and /saves/:id renders inspect + export correctly today.
  What is missing is the index — a way to reach it.

### 109. The comparison sheet's real keyboard operability, no-confirmation-dialog, no-Undo, and no-pre-selection behavior against a genuine hosted Ap…
expected: |
  The comparison sheet's real keyboard operability, no-confirmation-dialog, no-Undo, and no-pre-selection behavior against a genuine hosted AppKit/SwiftUI window
result: pass
gap_id: G-04-2
source: human
closed: |
  Confirmed green 2026-09-06: ConflictResolutionInteractionTests 5/5 after the
  readableText fix, restored to its full 6 tests in 9613a79.
unblocked_by: |
  The user set PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 themselves and ran the suite
  on 2026-09-06, which is the only legitimate way this row could move off blocked.
reported: |
  5 of 6 tests pass. One fails:
  ConflictResolutionInteractionTests.testKeepBothIsReachableByKeyboardAndIsAPeerOfTheChoiceButtons()
  at ConflictResolutionInteractionTests.swift:117 — XCTAssertTrue failed.

  Line 113 passed, so Tab DID reach Keep Both. Line 116 passed, so a result message DID
  render. Only line 117's text check failed. Per the harness at
  ConflictComparisonSheet.swift:299-306, resultMessage returns the "Keeping both…" string
  when keptBoth is true and the "…choosing" string when chosenID is set. A message that
  exists but does not contain "Keeping both" therefore means keptBoth == false and
  chosenID != nil: the space key at line 114 activated a Choose button, not Keep Both,
  despite the loop at 106-112 having just observed Keep Both holding keyboard focus.

  Leading hypothesis (NOT yet confirmed): a test-harness race. Line 108 polls
  value(forKey: "hasKeyboardFocus") immediately after typeKey, and typeKey does not wait
  for SwiftUI's focus update to propagate, so the accessibility snapshot can lag the real
  first responder. If so the keyboard contract is sound and the defect is in the test.
  The alternative — tab order genuinely places a Choose button under the space key — is a
  real accessibility defect. A 3x repeat run of the single test distinguishes them and is
  the next action.
diagnosis: |
  RESOLVED 2026-09-06. Both hypotheses above were wrong, and so were two subsequent
  fix attempts. The instrumented run settled it:

    resultLabel=>>><<<
    resultValue=>>>Optional(Keeping both. This Mac plays the This Mac version.
                  Neither version will be removed.)<<<
    resultTitle=>>><<<
    focusJustBeforeSpace=["keepBoth"]  focusAfterSpace=["keepBoth"]
    chosenR1Exists=false

  Keep Both DID activate. There was no focus race and no tab-order defect. The keyboard
  contract was sound the whole time. On macOS an AXStaticText carries its content in
  AXValue — what XCUITest exposes as `value` and what VoiceOver speaks — while `label`
  maps to AXTitle/AXDescription, which a SwiftUI Text leaves empty. The assertion at
  :117 read `.label` and had been comparing against "" since the day it was written.

  Two intermediate diagnoses were asserted with more confidence than the evidence
  carried: (1) accessibility-modifier ordering, and (2) a missing explicit
  .accessibilityLabel. Both were rebuilt and re-run; neither changed the empty label.
  `.accessibilityLabel` is a no-op on a macOS Text for this purpose. Both are reverted
  and ConflictComparisonSheet.swift is back to its original shape — the production view
  never contained the defect.

  Also corrected: this was NOT a screen-reader defect. An earlier note in this session
  claimed the reassurance message was silent to VoiceOver users. It was not; the string
  is exposed on the attribute macOS actually reads.

  Blast radius beyond this row: OnlyCopyInterruptionTests reads `.label` on macOS static
  texts in eight further places (:102, :103, :119, :128, :129, :138, :142, :173) and has
  never been run, so it would have failed identically on its first execution — another
  instance of the G-04-3 pattern, where a never-executed test hides a defect in itself.
  All nine reads now route through XCUIElement.readableText (PlaysteadUITests/Support/
  UITestHarness.swift), which prefers `label` and falls back to `value`.

  Fixed in 13eb3bb. Both temporary diagnostics deleted; the real assertion now reports
  the observed text on failure. UI target builds and all static contract guards pass.
  Re-run of the UI layer by a human is still required to move this row to pass.
first_execution: |
  CRITICAL CONTEXT: this test had never executed anywhere before 2026-09-06. It was
  introduced in 91cdb43 on 2026-09-04 16:14; the most recent CI run is 33770958764 at
  2026-09-03 15:08 on sha a14d171, and the working tree carries 154 unpushed commits.
  04-11-SUMMARY.md:92 recorded the deferral honestly ("their pass/fail has not been
  observed outside the hosted runner"), but the deferral was never redeemed. This was the
  test's first-ever run, and it failed. See G-04-3.
coverage_id: 04-11/D3
reason_human: human_judgment
rationale: |
  Local UI-layer execution is disabled in this sandbox by the project's own login-Keychain launch guard (scripts/ci/run-mac-verification.sh); these tests build and are registered in TestPlans/UI.xctestplan but their pass/fail has not been observed outside the hosted runner (WINDOWS #34, mirrors #9/#10 precedent).

### 110. The interruptive modal appears only when onlyOnThisMacCount > 0 (proven for all five named destructive-intent contexts plus a zero-count cas…
expected: |
  The interruptive modal appears only when onlyOnThisMacCount > 0 (proven for all five named destructive-intent contexts plus a zero-count case), renders the locked title/body/three buttons with Export saves… as the default, Remove anyway destructive-styled and never default, is fully keyboard-operable with visible focus, and never appears during browse/launch/sync
result: issue
gap_id: G-04-8
source: human
unblocked_by: |
  The user set PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 and ran the suite on
  2026-09-06 — the first execution this suite has ever had, anywhere.
reported: |
  7 of 12 failed. The five destructive-intent contexts all reach the modal (those five
  passed), so the gate itself is correct. Two production defects account for the rest:
  harness Texts unaddressable because a container combined its children, and the export
  escape hatch neither holding focus nor carrying the focus ring. See G-04-8.
coverage_id: 04-12/D3
reason_human: human_judgment
rationale: |
  Local UI-layer execution is disabled in this sandbox by the project's own login-Keychain launch guard (scripts/ci/run-mac-verification.sh); these tests build cleanly and are registered in TestPlans/UI.xctestplan but their pass/fail has not been observed outside the hosted runner (WINDOWS #36, mirrors #9/#10/#34 precedent).

### 111. Choosing Remove anyway removes cached game bytes and leaves every save revision present (the never-evictable rule); choosing Cancel or Expor…
expected: |
  Choosing Remove anyway removes cached game bytes and leaves every save revision present (the never-evictable rule); choosing Cancel or Export leaves everything untouched
result: issue
gap_id: G-04-8
source: human
reason: |
  Hosted macOS runner only — same run-mac-verification.sh:1026 launch guard as test 109. WINDOWS #36.
unblocked_by: |
  Ran for the first time on 2026-09-06 under the user's explicit launch approval.
reported: |
  testChoosingCancelLeavesEveryRevisionAndCachedByteInPlace and
  testChoosingRemoveAnywayLeavesEverySaveRevisionPresent both failed, but on the
  harness's result Text being unaddressable (G-04-8 half A), not on the never-evictable
  rule itself — the revision count assertion is downstream of the failed one and never
  executed. The rule's unit-level proof (OnlyCopyWiringTests) is unaffected and green.
coverage_id: 04-12/D4
reason_human: human_judgment
rationale: |
  Same login-Keychain local-execution guard as D3 (WINDOWS #36).

### 112. CP7-SAVE-C's step 3 (clear the save directory, relaunch through Playstead, expect automatic restore with no prompt) is now performable on th…
expected: |
  CP7-SAVE-C's step 3 (clear the save directory, relaunch through Playstead, expect automatic restore with no prompt) is now performable on the production path -- the file-identity half is proven above; a real emulator resuming gameplay from the restored bytes is CP7-SAVE-C's own named blocked checkpoint (04-07/04-13), not re-litigated here
result: blocked
blocked_by: physical-device
source: human
reason: |
  Requires a real installed emulator and real game bytes. This plan made the production call site reachable; it did not change CP7-SAVE-C's automatability. Carried by test 120.
coverage_id: 04-14/D5
reason_human: human_judgment
rationale: |
  Requires a real installed emulator and real game bytes, consistent with CP7-SAVE-C's existing named-blocked status from 04-07/04-13. This plan makes the production call site reachable; it does not change CP7-SAVE-C's automatability.

### 113. MC-02: the interruptive sheet's default 'Export saves...' button deep-links to the console's export surface and clears the deferred destruct…
expected: |
  MC-02: the interruptive sheet's default 'Export saves...' button deep-links to the console's export surface and clears the deferred destructive selection, never performing the destructive action
result: [pending]
source: human
coverage_id: 04-16/D2
reason_human: human_judgment
rationale: |
  Automated tests prove the destination URL and that the destructive path never fires; whether the actual browser-opening UX feels calm and unambiguous to a user is a judgment call no unit test proves.

### 114. MC-05: OnlyCopyEscalationPanel has a real, correctly-gated call site (never escalates offline/no-failure-signal states)
expected: |
  MC-05: OnlyCopyEscalationPanel has a real, correctly-gated call site (never escalates offline/no-failure-signal states)
result: pass
source: artifact-record
evidence: |
  This checkpoint asked a human to confirm that MC-05's ungated escalation was an
  acceptable, disclosed scope boundary. The premise is no longer true: 04-16 recorded
  WR-04 ("SaveUploadLane has no wired failure-classification output anywhere in
  production"), and 04-19 — two plans later — wired it. Verified in the code this
  session:

    - playstead-mac/Playstead/Saves/SaveUploadLane.swift:91
      `static func classify(_ error: Error) -> SaveUploadFailureClassification` maps the
      server's D-22 machine codes onto D-40's escalation vocabulary: device_revoked /
      unauthorized -> .revokedAuth, capability_incompatible -> .capabilitySkew,
      save_binding_incompatible / save_revision_digest_mismatch / save_parent_unknown /
      save_revision_immutable / save_branch_limit_exceeded -> .compatibilityRejection.
      Retryable conditions (transport, 5xx, slow_down, rate_limited, unpaired) stay
      `.none` — the conservative rule D-40 requires.
    - SaveUploadLane.swift:80 `lastFailureClassification` exposes it, backed by
      `SaveUploadClassificationCell`, and returns to `.none` on a successful upload.
    - playstead-mac/Playstead/App/PlaysteadApp.swift:1043
      `saveUploadFailureClassification()` returns `.offlineQueue` when offline and
      otherwise the live lane's own most recent outcome. Its own doc comment states:
      "Until 04-19 this returned a constant `.none` for the online case, because
      SaveUploadLane had no classification output and no production construction site
      at all: the four unfixable reasons were unreachable code in the shipped app
      (WINDOWS #40, #44)."
    - playstead-mac/Playstead/Readiness/ReadinessSheetView.swift:57 passes that
      classification, and line 71 constructs `OnlyCopyEscalationPanel` with it — a real,
      reachable call site.

  The offline gate is the structural guarantee this checkpoint asked about: the panel
  cannot escalate an offline or no-failure-signal state, because
  `saveUploadFailureClassification()` returns `.offlineQueue` before ever consulting the
  lane, and the lane returns `.none` until a genuinely unfixable server code arrives.

  Evidence boundary: this proves the call site exists and is correctly gated by reading
  the shipped code. Observing the panel actually render for a real revoked-auth response
  against a live server is the same hosted/live-server constraint as test 117.

  Note: WR-04's other half (SaveOutbox had no drain trigger) was closed separately by
  04-25 — see test 105 (04-25/D2).
source: human
coverage_id: 04-16/D5
reason_human: human_judgment
rationale: |
  The panel cannot yet be proven to fire for a genuine unfixable failure in production, because SaveUploadLane has no wired failure classifier (WR-04, recorded in WINDOWS.md) -- a human must confirm this is an acceptable, disclosed scope boundary rather than a hidden gap.

### 115. Four front-door journeys exist, one per save surface (SAVE-03 launch-restore, D-40 interruptive modal + MC-02 export escape hatch, D-38 dive…
expected: |
  Four front-door journeys exist, one per save surface (SAVE-03 launch-restore, D-40 interruptive modal + MC-02 export escape hatch, D-38 divergence badge + comparison sheet, D-37 readiness Save row), launched with no PLAYSTEAD_UI_TEST_* routing flag
result: blocked
blocked_by: other
source: human
reason: |
  Hosted macOS runner only. XCUITest execution needs a real app process, a real accessibility tree, and a spawned adapter process for Journey 1; run-mac-verification.sh:1026 forbids automated GSD runs from launching the app locally.
coverage_id: 04-18/D1
reason_human: human_judgment
rationale: |
  The four journeys compile, are registered, and were designed against verified real navigation paths and real seeded SaveStore/CAS/adapter-install state (traced through AppEnvironment/GameRowView/ReadinessSheetView/StorageView source), but XCUITest execution (a real app process, real accessibility tree, a spawned adapter process for Journey 1) genuinely requires the hosted macOS runner per this plan's own testing note and could not be executed in this session. A human/CI run on the hosted runner is the remaining proof, exactly as plans 04-11 and 04-12 disclosed for their own hosted-only suites.

### 116. Baselining the sweep surfaced a genuine, previously-undisclosed defect (the save-capture-and-upload pipeline has no production trigger) and …
expected: |
  Baselining the sweep surfaced a genuine, previously-undisclosed defect (the save-capture-and-upload pipeline has no production trigger) and it was reported, not quietly allowlisted
result: pass
source: artifact-record
evidence: |
  This checkpoint asked a human to read the disclosed defect (the save-capture-and-upload
  pipeline had no production trigger) and decide how urgently a dedicated wiring plan was
  needed. The phase record itself answers it — the wiring plans were written and executed,
  in this order, after the disclosure:
    - 04-19 wired capture end-to-end into the shipped Play path: SaveSessionCoordinator
      driven by the real Play path, GameRowView.buildSaveCaptureCoordinator, and a live
      SaveUploadLane on AppEnvironment with three drain triggers (session promotion,
      reachability-online, launch recovery).
    - 04-20 committed capture bytes into the CAS at promotion and made save blobs
      structurally un-evictable (bytesLocal: true for a save this Mac made).
    - 04-23 closed WINDOWS #52 — the identical hole on the crash-recovery path
      (SaveSessionRecovery now commits a promoted capture's bytes like the live path).
    - 04-25 closed the SaveOutbox drain-trigger race (WR-04's other half), serializing
      SaveOutboxDrainTrigger.fire() into one critical section.
  So the disclosure was acted on, not left standing. The urgency question is moot; what
  remains open is not this gap but the end-to-end observation of the wired lane against a
  real server, which is tracked separately as test 117 (blocked: server).
source: human
coverage_id: 04-18/D3
reason_human: human_judgment
rationale: |
  This is a significant, previously-unknown gap in a shipped save-safety phase. A human should read the 'Genuinely Unreachable Symbols Found' section below and decide how urgently a dedicated wiring plan is needed -- this plan's job was disclosure, not the fix.

### 117. The promoted revision is subsequently drained to the server by SaveUploadLane running in the shipped app
expected: |
  The promoted revision is subsequently drained to the server by SaveUploadLane running in the shipped app
result: blocked
blocked_by: server
source: human
reason: |
  Requires a live paired Playstead server and a paired device, neither available in this session (WINDOWS #3/#6). The lane's own success path is covered by SaveUploadLaneTests (9 tests, unchanged and passing); what is unobserved is the end-to-end drain against a real server.
coverage_id: 04-19/D2
reason_human: human_judgment
rationale: |
  A successful end-to-end upload against a live paired Playstead server was not executed in this session (no live server / paired device available locally, the same constraint WINDOWS #3/#6 record). The lane's own success path is covered by the pre-existing SaveUploadLaneTests (9 tests, unchanged and passing); what this plan adds and proves is that the shipped app constructs and triggers it. A hosted or manual run against a real server remains the final proof.
### 118. Captured revision restores to byte-identical bytes on disk (the automated proxy)
expected: A captured revision, when restored onto a clean save directory through the real `SavePlanExecutor` the launch path uses, produces bytes on disk that are byte-identical to what was captured, and whose sha256 matches the revision's recorded digest.
result: pass
source: automated
evidence: |
  `SaveRestoreProofTests.testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`
  (plan 04-13), executed locally this session via:
  `xcodebuild test -project Playstead.xcodeproj -scheme Playstead -testPlan LiveServer
  -destination 'platform=macOS' -only-testing:PlaysteadUITests/SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`
  Result: 1 test, 0 failures. Writes a 32,768-byte artifact, captures it through
  `SaveCapturePoller`, clears the restore target to simulate a clean Mac, restores
  it through the real `SavePlanExecutor` (`.fastForward`, the launch path's silent
  restore), and asserts the restored bytes and sha256 match the captured original
  both from the in-process result and by re-reading the file directly.
  Registered in `TestPlans/LiveServer.xctestplan` and in
  `scripts/ci/run-mac-verification.sh`'s live-server required-tests manifest;
  a negative check (removing the identifier from the manifest's expected set)
  was run locally against the same result bundle and confirmed the gate exits
  non-zero (`required test execution count must equal 1 ... (got 0)`).
  **Evidence boundary — read this narrowly.** This proves only that captured
  bytes round-trip byte-identically through the file-write mechanism a real
  launch would use. It does NOT prove: that a real emulator accepts those bytes
  as valid save data, that in-game progress is correct after restore, that a
  real commercial title flushes on any particular cadence, or anything about
  post-exit writeback timing on real hardware. Those are exactly what test 2
  (CP7-SAVE-C) below is for, and this test's passing status must never be
  cited as evidence toward it.
coverage_id: 04-13/D1
### 119. Save blobs are never offered as reclaimable storage, and a locally-captured save reports bytesLocal: true
expected: |
  In StorageView's reclaim/free-up-space surface, a save blob is never listed as
  removable junk — even though save blobs live in the CAS and have no catalogue member
  record. And after this Mac captures a save, the launch path reports the save's bytes
  as locally present (restorable from history with no server round-trip), not as a
  remote-only revision.
result: pass
source: automated
evidence: |
  Executed locally this session:
  `xcodebuild test -project Playstead.xcodeproj -scheme Playstead -testPlan Unit
   -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
   PROVISIONING_PROFILE_SPECIFIER=
   -only-testing:PlaysteadTests/LaunchSaveContextBuilderTests
   -only-testing:PlaysteadTests/EvictionTests
   -only-testing:PlaysteadTests/SaveSessionCoordinatorTests`
  Result: ** TEST SUCCEEDED ** — Executed 44 tests, with 0 failures (0 unexpected).
  All three suites passed: EvictionTests, LaunchSaveContextBuilderTests,
  SaveSessionCoordinatorTests.

  (The CI signing overrides are the same ones run-mac-verification.sh uses at lines
  1071/1172/1341/1530/1779; without them the project's placeholder DEVELOPMENT_TEAM
  "REPLACE_WITH_YOUR_TEAM_ID" fails codesign before any test runs. This is the Unit
  layer only — it does NOT touch the UI/LiveServer layers that line 1026's launch
  guard forbids automated runs from executing.)

  04-20-SUMMARY.md additionally records a falsification run: with `commitCaptureBytes`
  deleted from both call sites AND the test bundle rebuilt, the new test failed at
  exactly `LaunchSaveContextBuilderTests.swift:131` —
  "a save captured on this Mac must be restorable from history without a server round-trip".

  Evidence boundary: this proves the structural guarantee —
  `EvictionPlanner.unreferencedObjects()` cannot return a sha that appears as a revision
  `blobSHA256`, and `LaunchSaveContextBuilder` derives `bytesLocal: true` for a save this
  Mac captured. It does not prove the StorageView *rendering* of that list, which is a
  UI-layer observation blocked by the same launch guard as tests 109/110/111/115.
source: human
coverage_id: 04-20 (legacy summary — no coverage block; derived from prose)
rationale: |
  04-20-SUMMARY.md has no structured `coverage:` block, so per the coverage-classification
  rule nothing from it is auto-passed. Its own automated evidence is real and was
  falsified (`LaunchSaveContextBuilderTests.swift:131` failed at exactly the `bytesLocal`
  assertion with `commitCaptureBytes` removed), but that evidence is not machine-readable
  from this SUMMARY, so the deliverable is presented rather than silently dropped.
  Note WINDOWS #52: the identical hole on the crash-recovery path (`SaveSessionRecovery`)
  was disclosed, not fixed, in this plan.
### 120. CP7-SAVE-C — the human continuation proof
expected: Against a real commercial GBA title through the pinned mGBA adapter: (a) the on-disk `.sav` changes on a bounded cadence after an in-game save, not never; (b) a normal quit captures a revision, and a force-quit also captures a revision; (c) restoring onto a cleared save directory happens automatically with no prompt; (d) continuing the game shows the exact progress that was saved — not fresh, not stale, and with no in-game "save corrupt, erase?" prompt.
result: blocked
blocked_by: human-action
reason: "Requires a real emulator (pinned mGBA adapter), a real commercial GBA title, and a human judging in-game continuity — none of which exist or can be synthesized in this automated execution environment. This is a designed checkpoint (04-13-PLAN.md Task 3, type=\"checkpoint:human-verify\", gate=\"blocking-human\"), never auto-approved even in auto-mode, and its status may only ever be set by the developer performing the five steps in the plan's <how-to-verify> and recording the observations here. A green result on test 1 above is not, and must never be substituted as, evidence for this test."
coverage_id: 04-13/D2
## Explicit Separation Statement

Tests 118 and 120 above are deliberately recorded as two distinct rows rather than
one. The automated proxy (test 118) proves the file half of SAVE-03 and nothing
more. CP7-SAVE-C (test 120) carries the human continuation proof and is the only
thing that can close SAVE-03's "restores history" claim end to end on real
hardware. **A passing test 118 does not imply, contribute to, or partially
satisfy test 120.** Anyone reading this document who sees test 118 green must not
conclude the continuation proof has happened — it has not, until a developer
records observations under test 120 and sets its own status by hand.

## Summary

total: 120
passed: 111
issues: 2
pending: 1
skipped: 0
blocked: 6

## Gaps

<!-- YAML format for plan-phase --gaps consumption -->
- gap_id: G-04-1
  test: 108
  title: /saves lists only diverged lines, so its stated purpose is unreachable
  severity: medium
  status: FIXED 2026-09-06 in 33a3fc5 — index lists every line; decision framing is a
    per-row flag in muted text, not a filter and not an accent pill. Three reachability
    tests added and verified to fail against the old filter. mix precommit 1037/0.
  kind: reachability
  evidence:
    - lib/playstead_web/live/saves_live.ex:51-59  # filters all lines through needs_divergence_decision?/2
    - lib/playstead_web/live/saves_live.ex:296    # header promises "Inspect, choose, and export"
    - lib/playstead_web/live/saves_live.ex:306    # empty state "Nothing needs a decision right now."
    - lib/playstead_web/live/saves_live.ex:62     # load_line already handles single-head lines
    - lib/playstead_web/live/attention_live.ex:66 # /attention already owns the conflict queue
    - lib/playstead_web/live/attention_live.ex:351
  summary: |
    /saves renders a conflict-resolution queue under a browse-your-saves header. On a
    healthy library it is permanently empty, making "inspect" and "export" unreachable,
    while /attention already surfaces the conflicts it does list. The detail view at
    /saves/:id already supports non-diverged lines; only the index filter is wrong.
  suggested_fix: |
    Have load_diverged_lines list every save line for the user, carrying
    needs_divergence_decision? as a per-row flag rather than as a filter. Reserve the
    decision framing for the rows that have one, and rewrite the header and empty state
    for someone browsing their saves rather than servicing a queue.
    Reachability assertion required (see seams-between-plans-go-unowned): a test that a
    user with exactly one healthy save line can reach /saves/:id and its export control
    starting from /saves.

- gap_id: G-04-2
  test: 109
  title: testKeepBothIsReachableByKeyboardAndIsAPeerOfTheChoiceButtons fails on first-ever execution
  severity: high
  kind: keyboard-activation
  triage_result: |
    RESOLVED 2026-09-06 — and BOTH earlier hypotheses were wrong, including the
    inference recorded in this gap's original `reported` block.

    Two diagnostics settled it. Tab order is clean and stable: chooseR1, exportR1,
    chooseR2, exportR2, two disclosure groups, keepBoth, done — a cycle of 8 with
    keepBoth at step 6. The activation replay then showed tabsToReachKeepBoth=6,
    focusJustBeforeSpace=[keepBoth], chosenR1Exists=FALSE, and
    resultLabel=>>><<< — the empty string.

    So Keep Both activated correctly and no Choose button was ever touched. The
    assertion at :117 fails because the result element's accessibility label is EMPTY,
    not because it carries the wrong message.

    Root cause is the TEST, not the production view. On macOS an AXStaticText carries
    its content in AXValue — what XCUITest exposes as `value`, and what VoiceOver
    speaks — while `label` maps to AXTitle/AXDescription, which a SwiftUI Text leaves
    empty. The instrumented run showed resultValue carrying the exact expected string
    while resultLabel and resultTitle were both empty. The assertion at :117 was
    written to iOS semantics and had been comparing against "" since it was written.
  correction: |
    THREE wrong diagnoses were recorded in this gap before the right one, each stated
    more confidently than its evidence supported.

    (1) "The space key at line 114 activated a Choose button, not Keep Both." An
    inference from `label.contains(...) == false` plus the harness's resultMessage
    branches. chosenR1Exists=false disproved it. The evidence was consistent with an
    empty label the whole time; that branch was never considered.

    (2) "The identifier landed on the decorated container instead of the Text."
    Moving `.accessibilityIdentifier` above the decorative modifiers was rebuilt and
    re-run; the label stayed empty. Modifier ordering was never the cause.

    (3) "The Text needs an explicit .accessibilityLabel." Also rebuilt and re-run;
    also no change. `.accessibilityLabel` is a no-op on a macOS Text for this purpose.

    Both (2) and (3) are reverted. ConflictComparisonSheet.swift is back to its
    original shape: the production view never contained this defect.

    Also corrected: an earlier note in this session claimed the "Keeping both" message
    was silent to VoiceOver users. It was not. The string is exposed on the attribute
    macOS actually reads.
  evidence:
    - playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift:117
    - playstead-mac/PlaysteadUITests/Support/UITestHarness.swift (readableText)
    - "PLAYSTEAD_ACTIVATE resultValue carried the full string; resultLabel/resultTitle empty"
  summary: |
    The assertion read `.label` on a macOS static text, where SwiftUI puts the string in
    `.value`. It compared against the empty string and failed. Keep Both had activated
    correctly; tab order, focus propagation and the keyboard contract were all sound.
  blast_radius: |
    Not a one-line bug. OnlyCopyInterruptionTests reads `.label` on macOS static texts in
    eight further places (:102, :103, :119, :128, :129, :138, :142, :173) and has never
    been run, so it would have failed identically on first execution. Same G-04-3 shape:
    a never-executed test hiding a defect in itself. All nine reads now go through
    XCUIElement.readableText, which prefers `label` and falls back to `value`.
  status: CLOSED — confirmed green by a human UI-layer run on 2026-09-06.
    ConflictResolutionInteractionTests passed 5/5 immediately after the readableText
    fix, and the previously-failing label reads in OnlyCopyInterruptionTests (:102,
    :103) passed as well, which is independent confirmation the diagnosis was right.
    The suite is 6 tests again as of 9613a79 (see cleanup_correction).
  cleanup_correction: |
    Deleting the two diagnostics in 13eb3bb also deleted a real test,
    testExportActionIsReachableByKeyboardOnBothSides — the sed range ran to a closing
    brace I read as the last diagnostic's when it belonged to that test. Caught only
    because the run reported 5 tests where 6 were expected. Restored in 9613a79. A
    deletion whose range is chosen by line number needs its result counted, not
    eyeballed.
  cleanup_done: |
    testDiagnosticTabOrder and testDiagnosticKeepBothActivation are deleted as of
    13eb3bb; the real assertion now reports the observed text on failure, which is what
    the diagnostics existed to provide.

- gap_id: G-04-3
  test: 109
  title: Phase 4's entire UI layer has never run in CI; 154 commits unpushed
  resolved: |
    RESOLVED 2026-09-07. CI run 34082159625 executed 111 UI tests on the hosted runner —
    the deferral 04-11/04-12/04-18 each recorded honestly is finally redeemed. It found
    5 real failures on that first execution, in three separate suites, none of which any
    of 583 unit tests or any rendering test could see. The deferral was hiding defects,
    not paperwork.

    The standing lesson (honest-deferrals-expire-silently) holds: every one of these was
    correctly recorded as deferred, and correct recording did nothing to stop the rot.
    What stopped it was executing the tests.
  severity: high
  kind: verification-integrity
  evidence:
    - "gh run list: most recent CI run 33770958764 at 2026-09-03T15:08Z on sha a14d171"
    - "git log origin/main..HEAD: 154 commits"
    - .planning/phases/04-persistent-save-continuity/04-11-SUMMARY.md:92
    - .planning/phases/04-persistent-save-continuity/04-12-SUMMARY.md
    - .planning/phases/04-persistent-save-continuity/04-18-SUMMARY.md
  summary: |
    The last green CI run predates every Phase 4 commit. Three plans (04-11, 04-12,
    04-18) explicitly deferred UI-layer pass/fail to the hosted runner under WINDOWS #34.
    Each deferral was recorded honestly, but none was ever redeemed, because the work was
    never pushed. G-04-2 is the first evidence of what that deferral was hiding: the very
    first execution of a deferred test failed.

    This is the fail-open shape from playstead-ci-gates-rot-unnoticed — the gate did not
    fail, it simply never ran. It is also why UAT Session C is not a formality: it is the
    first real verification of 154 commits.
  scope_note: |
    Bounded, not phase-wide. Only one UAT row cites PlaysteadUITests, and the three
    UI-deferring summaries map to checkpoints already recorded as blocked. The 104
    coverage auto-passed rows rest on the Unit and Rendering layers, which run locally
    without the launch guard and did execute (04-11-SUMMARY.md:140 — 437 unit tests,
    0 failures; rendering 10/10).
  suggested_fix: |
    Push and get a green hosted run before any further UAT rows are treated as closed.
    Then add a gate that fails when the phase's UI/LiveServer layers have no hosted
    evidence newer than the phase's commits, so a deferral cannot silently expire again.

- gap_id: G-04-4
  test: 117
  title: mix precommit failed on --check-formatted
  severity: low
  kind: hygiene
  status: FIXED — verified green in hosted run 34077469940, where the `mix precommit`
    job passed for the first time on any Phase 4 commit. Commits 3328f6e and 33a3fc5.
  evidence:
    - "CI run 34066095728, job 'mix precommit', step 'Run mix precommit'"
    - playstead-server/test/playstead/export/round_trip_test.exs
  summary: |
    One unformatted test file failed the Linux gate. Fixed by running mix format; no
    behavior change.

- gap_id: G-04-5
  test: 117
  title: LiveServer.xctestplan selects 4 tests; the topology contract demands exactly 2
  severity: medium
  status: APPLIED 2026-09-06 by the user (82f1c84) via
    .planning/phases/04-persistent-save-continuity/apply-G-04-5.py. Applying it unmasked
    G-04-7, a second failing assertion in the same guard that the LiveServer failure had
    been hiding. Previously: the sole visible CI failure. Hosted run 34077469940 reduced the
    macOS job to exactly this one guard; every other contract passes, including the
    keychain-prompt-safety guard G-04-6 fixed. Patch prepared, human application required. A sandbox guard blocked the
    assistant from editing a CI contract file, which is the correct protection: a model
    widening a gate so CI turns green is the failure mode worth preventing. The diff is at
    .planning/phases/04-persistent-save-continuity/G-04-5-liveserver-contract.patch and
    the recommendation is to apply it — the two save tests need a real server and cannot
    be proven in a cheaper layer.
  kind: contract-drift
  evidence:
    - playstead-mac/scripts/ci/tests/four-layer-topology-test.sh:106
    - playstead-mac/TestPlans/LiveServer.xctestplan
  summary: |
    four-layer-topology-test.sh asserts LiveServer selects exactly
    HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner() and
    LiveServerSnapshotTests/testPairedFreshMirrorRenders...(). Phase 4 added
    SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn() and
    SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir()
    to the plan without updating the contract, so the guard fails closed.
  decision_required: |
    This is a genuine either/or, not a bug with one right answer. Either the two Phase 4
    live-server tests belong in the LiveServer plan and the contract's expected set must
    grow to four, or they belong elsewhere. The contract exists to keep the live-server
    layer minimal and serial; growing it is a deliberate choice about that budget, so a
    human should make it rather than an executor picking the path that turns CI green.

- gap_id: G-04-6
  test: 117
  title: UI test profile can now construct a real KeychainStore, weakening the fail-closed guard
  severity: high
  status: FIXED 2026-09-06 in a457028 — added APIClient.pairedForUITesting(_:) using the
    existing .fixed credential source, and branched the convenience init explicitly so the
    unpaired default stays the literal shape the contract greps for. Paired world state
    preserved, Keychain path gone. Guard passes; Mac unit layer 583/0.
  kind: safety-invariant
  evidence:
    - playstead-mac/scripts/ci/tests/keychain-prompt-safety-test.sh:38
    - playstead-mac/Playstead/App/PlaysteadApp.swift:398-419
  summary: |
    The guard requires the uiTestingPaths convenience init to read literally
    `apiClient: APIClient.unpairedForUITesting()` — fail closed, never touch the login
    Keychain. Phase 4 added an optional `credential:` parameter, so it now reads
    `apiClient: credential.map { APIClient(keychain: KeychainStore(), credential: $0) }
    ?? APIClient.unpairedForUITesting()`. The nil default preserves the safe path, but a
    caller passing a credential constructs a real KeychainStore in the UI test profile.

    This is the exact hazard the PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH guard exists
    to prevent, and it is the property that makes it safe to ask a human to run the UI
    layer locally. The doc comment defending the change argues only that the path opens
    no network connection — true, and not what this guard asserts. It answers a different
    question than the one it appears to answer.
  correction: |
    An earlier revision of this gap called the parameter unused and the hazard latent.
    That was wrong, and the error was mine: I grepped Playstead/App/UITestBootstrap.swift,
    but the file is at Playstead/UITesting/UITestBootstrap.swift. The empty result read as
    "no callers."

    There is a caller. UITestBootstrap.swift:64 passes profile.uiTestingCredential, and
    DeterministicProfile.swift:48 returns a real credential for .saveOnlyCopy — the
    profile behind OnlyCopyInterruptionTests. The KeychainStore branch was live, in
    exactly the suite a human would be asked to run locally.
  suggested_fix: |
    Remove the unused `credential:` parameter and restore the literal fail-closed form.
    If a future save-safety journey genuinely needs a seeded pairing credential, give it
    a synthetic credential source that cannot reach KeychainStore, and widen the contract
    deliberately rather than by parameter default.

- gap_id: G-04-7
  test: 117
  title: The reclaim-ordering guard truncates the button body at the first brace
  severity: medium
  kind: guard-parsing
  status: OPEN — apply script prepared, human application required (same sandbox block as
    G-04-5). .planning/phases/04-persistent-save-continuity/apply-G-04-7.py
  evidence:
    - playstead-mac/scripts/ci/tests/four-layer-topology-test.sh:431
    - playstead-mac/Playstead/Library/ReclaimPromptView.swift:136-149
    - playstead-mac/Playstead/Library/StorageView.swift:181-
  summary: |
    The guard extracts the "Reclaim selected" body with
    `source.split('}', 1)[0]`, which stops at the first closing brace. Phase 4 added the
    only-copy interruption gate to that body, and its `candidates.filter { ... }` closure
    now closes a brace before any marker the guard looks for. The body is truncated to two
    lines, so the guard reports a violation that does not exist.
  not_a_product_defect: |
    Verified by reading the full body: ReclaimPromptView.swift:137, :147, :148 still do
    `let selection = selected`, `selected.removeAll()`, `onReclaim(selection)` in that
    order — exactly what the guard asserts. The interruption branch deliberately defers
    the clear to the sheet's resolution, which is the intended interruptive behaviour.
  suggested_fix: |
    Replace the split with real brace matching so the guard reads the whole body. This
    restores the original assertion rather than relaxing it; the apply script prints a
    negative control (swap removeAll and onReclaim, confirm the guard fails) so the check
    is proven to still bite before being trusted.
  note: |
    Third guard in this phase to fail on well-formed code (with G-04-5, and the
    ripgrep-exit-127 case in playstead-ci-gates-rot-unnoticed). The common shape is a
    guard parsing source with naive string operations. Worth a sweep of the remaining
    contracts for `.split(` on Swift source before the phase closes.
  negative_control: |
    PERFORMED 2026-09-07. Swapped `selected.removeAll()` and `onReclaim(...)` in
    ReclaimPromptView.swift and re-ran the guards: they failed with "ReclaimPromptView
    .swift: reclaim must snapshot, clear stale selection, then invoke its effect", then
    passed again once the file was restored (git diff clean). The guard bites on the
    defect it claims to catch — it is not fail-open, which is the specific rot mode
    recorded in playstead-ci-gates-rot-unnoticed.

- gap_id: G-04-8
  test: 110
  title: OnlyCopyInterruptionTests failed 7 of 12 on its first-ever execution
  severity: high
  kind: accessibility-containment, visible-focus
  first_execution: |
    Same shape as G-04-3 and G-04-2: this suite had never run anywhere. Its first
    execution, on 2026-09-06, failed 7 of 12. Five tests passed (the five
    destructive-intent contexts all reach the modal), so the harness launches and the
    gate is correct.
  triage_result: |
    Two independent defects, both in production code, neither in the tests.

    (A) CONTAINMENT — four elements could not be addressed at all: the interruption
    harness's no-modal (:95), result (:127, :137) and revisions-remaining Texts, and
    the neutral harness's browse/launch/sync Texts (:180). Every one is a direct child
    of a VStack carrying `.accessibilityIdentifier` with no
    `.accessibilityElement(children: .contain)`. An accessibility modifier on a
    container makes SwiftUI combine its children into a single element, so the
    children stop being addressable. What DID resolve — title, body — lives inside
    OnlyCopyInterruptiveSheet, which declares `.contain` itself.
    ConflictComparisonHarnessRootView applies its identifier directly onto its sheet
    rather than onto a wrapping VStack, which is why the comparison harness never hit
    this and why it was invisible until this suite first ran.

    (B) VISIBLE FOCUS — the export button never held focus (:109, :116, :149). It was
    also the only button in that row without the focus ring: cancel and remove-anyway
    use `playsteadFocusable`, while export hand-rolled `.focused` + identifier and so
    silently lost the ring. That is the "visible focus" contract failing on the
    control it matters most for — the destructive modal's escape hatch, the button
    D-40 requires to be the easiest one to reach.
  fix: |
    (A) Both harness roots now declare `.accessibilityElement(children: .contain)`.
    (B) A new `playsteadFocusable(identifier:focus:)` overload takes a parent-owned
    `@FocusState` binding, so a `.defaultFocus` target keeps the shared ring; export
    now uses it. The sheet also declares `.focusSection()`, which
    ConflictComparisonSheet — whose keyboard contract is proven green — has and this
    sheet lacked.
  evidence:
    - playstead-mac/Playstead/Saves/OnlyCopyInterruptiveSheet.swift
    - playstead-mac/Playstead/Design/FocusRing.swift
    - playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift
  ci_first_run: |
    2026-09-07, CI run 34082159625 — the hosted runner executed 111 UI tests. This is
    the first time this phase's UI layer has ever run in CI, and it closes the deferral
    that G-04-3 recorded. 5 failures.

    (A) CONFIRMED FIXED. The harness's result, no-modal and revisions-remaining Texts
    are addressable and their tests pass.

    (B) NOT FIXED by `.focusSection()`. Export still does not hold focus — and it failed
    in SaveFrontDoorJourneyTests:115 as well, which drives the real modal presented from
    Storage, so the defect is in the sheet and not in the harness. Nothing in this app
    proves `.defaultFocus` ever lands anywhere. The sheet now sets focus directly with
    .onAppear in addition, because D-40's contract should not rest on a modifier not
    observed to fire. Pushed in 2bead02; unverified until the next CI run.

    Instrumentation failure of my own: the previous round's `focus is on [...]` message
    never reached the artifact, because the evidence sanitizer strips assertion messages
    and keeps only file:line. The check is now four assertions on four separate lines
    (nothing focused / cancel took it / the destructive button took it / something else
    did), so the line number alone carries the diagnosis through sanitization. A
    diagnostic has to survive the evidence pipeline, not just run.

    Third failure, SaveFrontDoorJourneyTests:152, was a wrong assumption in the test
    rather than a missing badge: GameCardView deliberately collapses to a single element
    (`children: .ignore`) and composes the status sentence into its own label — better
    for a screen reader than three separate stops. The test now proves D-38's rung
    through the card's composed accessible name.
  status: (A) CONFIRMED FIXED by CI run 34082159625. (B) FIXED AGAIN but NOT VERIFIED —
    the focus half is reasoned from the comparison sheet's precedent, not observed. The
    three focus assertions now report which element actually owns focus when they fail,
    so the next UI-layer run resolves it either way rather than costing another
    round trip. Verified so far: UI target builds, Unit plan 583/583, all static
    contract guards pass.
  pattern: |
    Both halves were invisible to 583 passing unit tests and to every rendering test.
    They are only observable in a hosted window. This is the third time in this phase
    that first-ever execution of a deferred UI test found a real defect — see G-04-3.
  sweep: |
    Swept the whole tree for both shapes rather than fixing only what failed.

    Containment: a detector for "accessibility modifier applied to a container with no
    `.accessibilityElement(children:)` nearby" was validated against the known-bad
    original (it flags exactly the two OnlyCopy harness roots and nothing else) and
    then run over the fixed tree, which is clean. No third instance exists.

    Label-vs-value: no `.label` reads on static texts remain anywhere in the UI test
    target. The reads that survive (LiveServerSnapshot, StorageInteraction, Curation,
    SaveFrontDoorJourney's summary/badge/saveRow) are all on containers that set an
    explicit `.accessibilityLabel`, where `label` is the correct attribute.

    One further instance was found and fixed by the sweep, in a suite that has also
    never run: SaveFrontDoorJourneyTests matched `label BEGINSWITH "Last exit:"` on
    static texts, but GameRowView:109 renders that as a bare Text inside a `.contain`
    container, so the string lives in AXValue and the predicate could never fire. It
    now matches either attribute. CurationInteractionTests:300 uses the same predicate
    shape but matches GameCardView, which sets an explicit label under
    `children: .ignore`, so it is correct as written and was left alone.

- gap_id: G-04-9
  test: 110
  title: The evidence sanitizer rejects the reachability sweep's summary, truncating failure evidence
  severity: medium
  kind: verification-integrity
  found_by: |
    Debugging G-04-8 from CI evidence. The failure artifact contained only three files;
    the per-layer test evidence I needed was missing.
  triage_result: |
    sanitize-evidence.sh validates every `*-tests.json` in the evidence directory
    against the xctest-layer schema. 04-18 promoted the reachability sweep to a real
    layer, and it writes a static-sweep summary — layer/kind/outcome/exit_status — into
    that same directory under that same filename pattern. The validator matched it by
    filename, found a shape it did not recognise, and raised. Sanitization aborts on
    first rejection, so every failing run silently uploaded truncated evidence.

    Blast radius is bounded: the sanitizer runs only when the aggregate has already
    failed (run-mac-verification.sh:1322), so this never turned a green run red. What it
    did was degrade the evidence for exactly the runs where evidence matters most.

    Another unowned seam between plans, in the shape recorded in
    seams-between-plans-go-unowned: 04-18 added a new artifact to a directory owned by
    an earlier plan's contract, and nothing asserted the two still agreed.
  fix: |
    The sanitizer recognises the sweep's own shape and validates it on its own terms.
    Four new checks in sanitizer-test.sh: one positive (the sweep's real shape is
    accepted and reaches the output) and three negative — the static-sweep marker must
    not become a bypass for an arbitrary extra key, an uninterpretable outcome, or real
    xctest evidence. Guard count 29 -> 34.
  negative_control: |
    PERFORMED. With the sanitizer fix reverted, reachability_sweep_accepted fails and
    the guards go red; restored, all 34 pass. The new checks bite.
  status: FIXED in 2bead02, with a negative control. Verified by the guard suite.

## Standing Non-Gap Notes

- Three load-sensitive Mac unit flakes are on record for this phase: the two named by
  04-23, plus `PlaySessionTests.test_launchSucceedsIndependentlyOfPlaySessionRecording`
  (recorded by 04-25, which found it failing on a 5s "process exits" timeout under
  full-suite load and passing in isolation; it passed 583/583 in the 2026-09-06 UAT run).
  CI runs the full suite under load, so a macOS red on one of these three is a known
  flake, not a new defect — confirm by re-running the named test alone before treating it
  as a finding. Not a gap: no user-facing behaviour is implicated.

- CP7-SAVE-C (test 120) requires a human session with the pinned mGBA adapter installed,
  a real commercial GBA title, a running paired server, and roughly 15-30 minutes to
  perform the five recorded steps. Until that session happens, SAVE-03's continuation
  claim remains open — the phase's automated evidence covers the file half only. This is
  a prerequisite gate, not a code defect, and therefore is not a gap.
