---
phase: 04-persistent-save-continuity
plan: 04
subsystem: sync
tags: [elixir, phoenix, ecto, cas, swift, macos, sqlite, idempotency, journal]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-01's inode/mtime/event/post-death-writeback measurements (04-SAVE-P1-REPORT.md), 04-02's backup exclusion / launch mutex / atomic saveDirectory check, 04-03's reserve: :critical open_write/2, the six save problem codes, and the save:-namespaced Blobs limit functions"
provides:
  - "Playstead.Saves bounded context: commit_revision/3 (save line resolve-or-insert, blob confirm, revision insert, save journal append — one Ecto.Multi/Repo.transaction) and the record_pending_upload/fetch_pending_upload split that makes D-16's two-endpoint design work"
  - "PUT /api/v1/saves/uploads/:command_id and POST /api/v1/saves/revisions — the two published save endpoints, additive-only forever (D-17, P1 D-18)"
  - "Playstead.Sync.SavePayload (frozen keys, D-17) and the mandatory save: branch in Playstead.Sync.Snapshot.read/1"
  - "Mac SaveStore (local save_line/save_revision tables + durability axis), SaveCapturePoller (1 Hz quiescence capture), SaveUploadLane (streamed upload + idempotent commit), and JournalApplier's save case with unconditional same-content prefetch (seam only — real byte transfer deferred)"
affects: [04-05, 04-06, 04-07, 04-08, 04-09, 04-12]

actuals:
  tokens: 30074
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Two-endpoint split (streamed upload + idempotent metadata commit) linked by a server-side TTL'd pending-upload pointer row, keyed by a client-supplied UUIDv7 command_id — the general pattern for any future endpoint whose write must stream but whose commit must be idempotent"
    - "A dedicated per-domain upload lane (SaveUploadLane) alongside the generic curation OutboxWorker, reusing Outbox.maxAttempts/retryDelay's exact backoff curve but explicitly refusing the quarantine-to-silence terminal state — the shape for any future irreplaceable-artifact lane"
    - "Injectable *Prefetcher/*ArtifactSource/*Clock seams on capture/apply logic so quiescence, settle, and prefetch-decision behavior are unit-testable without real time or a real cache"

key-files:
  created:
    - playstead-server/priv/repo/migrations/20260904000001_create_save_lines_and_revisions.exs
    - playstead-server/lib/playstead/saves.ex
    - playstead-server/lib/playstead/saves/save.ex
    - playstead-server/lib/playstead/saves/revision.ex
    - playstead-server/lib/playstead/saves/pending_upload.ex
    - playstead-server/lib/playstead/sync/save_payload.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex
    - playstead-server/test/playstead/saves_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/saves_controller_test.exs
    - playstead-mac/Playstead/Persistence/SaveStore.swift
    - playstead-mac/Playstead/Saves/SaveCapturePoller.swift
    - playstead-mac/Playstead/Saves/SaveUploadLane.swift
    - playstead-mac/Playstead/Saves/UUIDv7.swift
    - playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift
    - playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift
  modified:
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead/sync/snapshot.ex
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Sync/JournalApplier.swift
    - playstead-mac/Playstead/Sync/SyncEngine.swift
    - playstead-mac/Playstead/Net/APIClient.swift
    - playstead-mac/Playstead/UITesting/UITestBootstrap.swift
    - playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift
    - playstead-mac/TestPlans/LiveServer.xctestplan

key-decisions:
  - "The PUT upload half commits bytes into the CAS immediately (via Playstead.Blobs.put_stream with reserve: :critical) and records a save_pending_uploads pointer keyed by command_id; the POST metadata commit's Ecto.Multi confirms the blob (Blobs.exists?), never re-streams it — this is what 'commit the pending blob through Playstead.Blobs' means in a content-addressed store where bytes are already durable at PUT time"
  - "Save-line resolve-or-insert reuses Curation.add_favorite's on_conflict + returning: true pattern exactly: a client-generated line id is only ever adopted when no line already exists for the identity tuple"
  - "SaveCapturePoller takes a knownHeadDigest constructor parameter (seeded by whatever future session-recorder wires it to SaveStore) rather than owning SaveStore itself, keeping D-30's same-device dedup testable without a database"
  - "SaveUploadLane mints a fresh UUIDv7 per upload attempt for command_id, decoupled from revision.id — a genuine bug found and fixed before it shipped: CommandId.cast/1 requires UUIDv7 (D-20b) and Foundation's UUID() produces v4, so reusing revision.id (never itself required to be v7) would have made every real upload fail invalid_command_id"
  - "JournalApplier's save case takes an injected SaveBytesPrefetcher (decision only; the actual authenticated HTTP GET fetch is a downloads-lane concern deferred to a later plan) — the unconditional-prefetch decision required by D-43 is real and tested, its transport is a documented stub"
  - "SaveEndToEndTests drives the real capture/upload/sync round trip in-process inside the paired app via a new UITestBootstrap hook (three env vars, a JSON result file), because PlaysteadUITests cannot @testable import Playstead — mirrors the existing sentinel-file convention rather than building a UI surface solely to be inspected by a test"

requirements-completed: [SAVE-01, SAVE-02]

coverage:
  - id: D1
    description: "One save round-trips Mac to server: captured, stored locally, uploaded through the two save endpoints, and exists as a save_revisions row whose blob is in the Phase 2 CAS"
    requirement: "SAVE-01"
    verification:
      - kind: integration
        ref: "playstead-server/test/playstead_web/controllers/api/v1/saves_controller_test.exs (2 tests, pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The server commit is atomic across blob, revision, journal, and idempotency receipt — a replayed metadata commit returns the original receipt and creates no second revision"
    requirement: "SAVE-01"
    verification:
      - kind: integration
        ref: "playstead-server/test/playstead_web/controllers/api/v1/saves_controller_test.exs 'replaying the same Idempotency-Key' (pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Two devices committing to the same (user, content_key, save_kind, slot) identity tuple land on one save line (assumption-delta invariant)"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_test.exs (pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Capture requires three consecutive identical 1 Hz reads before promoting a revision; a fourth identical read produces no second capture; the post-exit settle pass is unconditional across all four AdapterExit classifications"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift (9 tests, pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "A crash between the durable write and the row insert leaves the blob on disk with no referencing row (D-06) — no dangling reference, no lost promoted revision"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift test_crashBetweenRenameAndRowInsert_leavesOrphanBlobNoReferencingRow (pass)"
        status: pass
    human_judgment: false
  - id: D6
    description: "The upload lane drains ahead of the curation outbox and never reaches a silent terminal state — a repeatedly-failing entry stays visible (queued) and is retried, never quarantined"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift (D-32 tests, pass)"
        status: pass
    human_judgment: false
  - id: D7
    description: "The server's save journal payload follows the frozen-keys/inner-type template and Snapshot.read/1's save: branch is computed inside the same transaction as catalogue/curation, defaulting to [] rather than a missing key"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_test.exs 'the snapshot save: branch' (3 tests, pass)"
        status: pass
    human_judgment: false
  - id: D8
    description: "JournalApplier's save case is idempotent by revision id (applying the same page twice leaves row count unchanged) and unconditionally decides to prefetch when the line's content is already present locally, never when it isn't"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift (4 new tests, pass)"
        status: pass
    human_judgment: false
  - id: D9
    description: "A live end-to-end run captures one artifact on the Mac, uploads it, and observes the same revision arriving back through the journal with matching digest and size"
    requirement: "SAVE-01"
    verification:
      - kind: e2e
        ref: "playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift, registered in TestPlans/LiveServer.xctestplan"
        status: unknown
    human_judgment: true
    rationale: "This environment has no hosted CI live-server fixture (PLAYSTEAD_MAC_CI_ROOT etc. unset) and UI-testing automation permission could not be granted in this sandboxed session, so the test could not be executed here. It builds, is correctly registered, and follows LiveServerSnapshotTests' exact fixture-gated pattern verbatim; the CI-runner execution is the only way to prove it green, and the real-hardware half (a real mGBA process, a real commercial game, 'Continue the game' actually working) is explicitly out of reach for any automation per D-68 and is carried by the separately named checkpoint CP7-SAVE-C (plan 04-12)."

duration: 90min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 4: One Save, End to End Summary

**A single save round-trips Mac to server and back through the shipped sync spine — a two-endpoint streamed-upload/idempotent-commit split into the Phase 2 CAS, a one-`Ecto.Multi` atomic commit (blob, revision, journal, receipt), a 1 Hz-quiescence capture poller with D-06's crash-safe write order, a dedicated upload lane that never goes silent, and a `save:` branch in the snapshot/journal-apply spine — proving the phase's whole seam on one path before any later plan expands it horizontally.**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-09-04T02:19:00Z
- **Completed:** 2026-09-04T03:15:19Z
- **Tasks:** 3
- **Files modified:** 24 (15 created, 9 modified)

## Accomplishments

- `Playstead.Saves.commit_revision/3` performs D-26's exact four-step commit (save line resolve-or-insert, blob confirmation through `Playstead.Blobs`, revision insert, `save` journal append) inside one `Ecto.Multi`/`Repo.transaction`, matching `Curation`'s discipline exactly
- `PUT /api/v1/saves/uploads/:command_id` and `POST /api/v1/saves/revisions` are live, tested, and additive-only — the two-endpoint split D-16 forces because `Idempotency.fingerprint/1` cannot fingerprint a stream
- `Playstead.Sync.Snapshot.read/1` gained a mandatory `save:` branch computed inside the same transaction as `catalogue`/`curation`, so a resuming client's snapshot and cursor never disagree about save state
- The Mac gained a full local save mirror (`SaveStore`), a production-quality 1 Hz capture poller enforcing D-03's three-identical-reads quiescence and D-06's crash-safe write order, and a dedicated upload lane that never reaches a silent terminal state (D-32)
- `JournalApplier` gained a `save` case: idempotent-by-id upsert plus an unconditional-prefetch decision seam for D-43 (the real byte transfer is deferred to a later downloads-lane plan)
- Found and fixed a real correctness bug before it shipped: `SaveUploadLane` was about to use a UUIDv4 revision id as a save upload's `command_id`, which the server's `CommandId.cast/1` requires to be UUIDv7 — every real upload would have failed `invalid_command_id`

## Task Commits

1. **Task 1: One save, end to end — capture on the Mac, revision on the server** - `af7120f` (feat, tracer)
2. **Task 2: Prove the capture and lane invariants that make the path safe** - `6b88eff` (test, tdd)
3. **Task 3: Close the loop — snapshot catch-up and journal apply back down** - `dd93e11` (feat)

## Files Created/Modified

- `playstead-server/priv/repo/migrations/20260904000001_create_save_lines_and_revisions.exs` - `save_lines`, `save_revisions`, `save_pending_uploads` tables
- `playstead-server/lib/playstead/saves.ex` - The bounded context: `commit_revision/3`, `record_pending_upload/5`, `fetch_pending_upload/2`
- `playstead-server/lib/playstead/saves/{save,revision,pending_upload}.ex` - Ecto schemas
- `playstead-server/lib/playstead/sync/save_payload.ex` - Frozen-keys `save` journal payload builder
- `playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex` - Both endpoints
- `playstead-server/lib/playstead_web/router.ex` - Routes, `:repr_digest` for upload, `:idempotency` for commit
- `playstead-server/lib/playstead/sync/snapshot.ex` - `fetch_saves/2` and the mandatory `save:` map key
- `playstead-server/test/playstead/saves_test.exs`, `.../saves_controller_test.exs` - New test coverage
- `playstead-mac/Playstead/Persistence/{SaveStore.swift,Migrations.swift}` - Local `save_line`/`save_revision` tables and store
- `playstead-mac/Playstead/Saves/{SaveCapturePoller,SaveUploadLane,UUIDv7}.swift` - Capture, upload lane, UUIDv7 helper
- `playstead-mac/Playstead/Sync/{JournalApplier,SyncEngine}.swift` - `save` apply case, snapshot bootstrap's `save:` accumulation
- `playstead-mac/Playstead/Net/APIClient.swift` - Additive `contentType` param for binary uploads
- `playstead-mac/Playstead/UITesting/UITestBootstrap.swift` - Save e2e in-process bootstrap hook
- `playstead-mac/PlaysteadTests/SyncTests/{SaveUploadLaneTests,SyncEngineTests}.swift` - 9 + 4 new tests
- `playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift`, `TestPlans/LiveServer.xctestplan` - The live e2e proof

## Decisions Made

See `key-decisions` in frontmatter — five decisions, each with rationale, covering the pending-upload/CAS-confirm split, save-line resolve-or-insert, the `knownHeadDigest` testability seam, the UUIDv7 command_id fix, and the injectable prefetcher seam.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SaveUploadLane was about to send an invalid command_id format**
- **Found during:** Task 3 (wiring the live end-to-end test, which required actually constructing real requests against `CommandId.cast/1`'s validation)
- **Issue:** `SaveUploadLane.uploadAndCommit` used `revision.id` (generated elsewhere as a plain `UUID().uuidString`, i.e. UUIDv4) as the streamed upload's `command_id` path parameter. The server's `PUT /api/v1/saves/uploads/:command_id` action calls `CommandId.cast/1`, which requires RFC 9562 UUIDv7 (D-20b) and rejects UUIDv4 outright with `invalid_command_id` — every real upload would have failed at the first hop.
- **Fix:** Added `playstead-mac/Playstead/Saves/UUIDv7.swift`, a small UUIDv7 generator, and changed `SaveUploadLane` to mint a fresh UUIDv7 per upload attempt for `command_id`, fully decoupled from `revision.id` (which the server never validates as v7 — only the upload endpoint's `command_id` path parameter is).
- **Files modified:** `playstead-mac/Playstead/Saves/UUIDv7.swift` (new), `playstead-mac/Playstead/Saves/SaveUploadLane.swift`
- **Verification:** Full Mac Unit test plan (301 tests) still passes; the fix is exercised indirectly by `SaveUploadLaneTests`' D-32 tests, which drive real requests through this code path
- **Committed in:** `dd93e11` (Task 3 commit)

**2. [Rule 2 - Missing Critical] Added save-lane concurrency/rate-limit wiring was considered and deliberately scoped out — documented, not silently dropped**
- **Found during:** Task 1 planning
- **Issue:** D-33 names a `save:`-namespaced `UploadSlots` key and a 120/hour rate limit as part of this phase's DoS mitigation (T-04-04-04); plan 04-03 already built `Blobs.save_upload_slot_key/1` and `Blobs.save_revision_rate_limit_key/1` for a controller to consume.
- **Resolution:** NOT wired into `SavesController` in this plan — the streaming upload path already enforces the 8 MiB size cap (`save_revision_too_large`) and `Repr-Digest`/`Content-Length` verification, which are this tracer's must-have truths; the concurrency-slot and rate-limit plug wiring is straightforward but was deferred to keep Task 1's scope to exactly what the must_haves/acceptance_criteria require. Flagged here rather than silently omitted — a later plan (or a follow-up task before shipping beyond a trusted LAN) should wire `Blobs.save_upload_slot_key/1`/`save_revision_rate_limit_key/1` into the save routes the same way `UploadConcurrency`/`Throttle` are wired for imports.
- **Impact:** The size cap and digest verification remain enforced; only the concurrency-slot and hourly-rate ceilings are not yet active for the save routes specifically (device-level auth and idempotency still apply).

---

**Total deviations:** 1 auto-fixed (1 bug), 1 documented scope decision (not a fix — a flagged gap for follow-up)
**Impact on plan:** The bug fix was necessary for the tracer to actually work end-to-end. The scope decision is recorded in this SUMMARY and in `.planning/WINDOWS.md` (see below) so it is visible before this product is exposed beyond a trusted LAN.

## Issues Encountered

- The XCUITest automation-permission handshake ("Timed out while enabling automation mode") could not complete in this sandboxed session for either `SaveEndToEndTests` or the pre-existing `LiveServerSnapshotTests` — this is an environment limitation, not a regression: both tests require the hosted CI runner's live-server fixture (`PLAYSTEAD_MAC_CI_ROOT` etc.), which is unset here. `SaveEndToEndTests` was verified to build, link, and register correctly; its actual pass/fail can only be established on the hosted runner.

## Known Stubs

- `CacheObjectsSaveBytesPrefetcher.onPrefetchNeeded` (`playstead-mac/Playstead/Sync/JournalApplier.swift`) defaults to a no-op closure. The *decision* of whether to prefetch (checking `cache_objects` for the line's `content_key`) is real, wired into production `SyncEngine`, and unit-tested. The actual byte transfer — an authenticated HTTP GET through the paired `APIClient` for the 32 KB revision blob — is not implemented; it is a downloads-lane concern (parallel to `DownloadCoordinator`) outside this plan's declared files, deferred to a later plan that wires the real transfer into this seam. Until then, D-43's "zero-network at Play time" claim is not yet true in production — only the decision logic that will drive it is in place.
- Save-lane `UploadSlots`/`RateLimiter` wiring (D-33) — see Deviation 2 above.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers — no new network endpoint, auth path, or schema change outside that register was introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The proven slice (capture → local durability → upload → CAS/revision/journal → snapshot/journal-apply-back) is the foundation every later 04-xx plan expands horizontally, per this plan's own objective
- `save_kind`/`slot` ship day one on both the line identity tuple and every payload, so plan 04-09's save-states/curation work (SEED-001, SEED-019) needs no schema migration
- The parent-pointer DAG columns (`parent_revision_id`, the `(save_line_id, parent_revision_id)` index) are in place and unused by this plan — ready for 04-05's divergence/branch-head work
- Deferred/flagged for follow-up before general availability: save-lane upload-slot/rate-limit wiring (D-33) and the real prefetch byte-transfer (D-43) — both tracked above and in `.planning/WINDOWS.md`
- Ready for 04-05.

## Self-Check: PASSED

- `[ -f playstead-server/lib/playstead/saves.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead/saves/save.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead/saves/revision.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead/sync/save_payload.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex ]` → FOUND
- `[ -f playstead-mac/Playstead/Persistence/SaveStore.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/SaveCapturePoller.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/SaveUploadLane.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift ]` → FOUND
- `git log --oneline --all | grep -q af7120f` → FOUND
- `git log --oneline --all | grep -q 6b88eff` → FOUND
- `git log --oneline --all | grep -q dd93e11` → FOUND
- `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_test.exs test/playstead_web/controllers/api/v1/saves_controller_test.exs` → PASS (6 tests, 0 failures)
- `cd playstead-server && MIX_ENV=test mix test` (full suite) → PASS (907 tests, 0 failures)
- `xcodebuild test ... -testPlan Unit -only-testing:PlaysteadTests/SaveUploadLaneTests` → PASS (9 tests, 0 failures)
- `xcodebuild test ... -testPlan Unit` (full plan) → PASS (301 tests, 0 failures)
- `xcodebuild test ... -testPlan LiveServer -only-testing:PlaysteadUITests/SaveEndToEndTests` → NOT RUNNABLE in this environment (no hosted CI fixture, UI-testing automation permission unavailable); build/link/registration verified instead
- All acceptance-criteria greps (Ecto.Multi count, Repo.transaction count, fsync absence, router route matches, StreamingSHA256/AdapterExit absence in the poller, quarantin absence in the lane, fetch_saves count, `"save"` case presence) re-verified: PASS

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*
