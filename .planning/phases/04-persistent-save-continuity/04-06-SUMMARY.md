---
phase: 04-persistent-save-continuity
plan: 06
subsystem: saves
tags: [swift, macos, sqlite, save-capture, quota, crash-recovery]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-04's tracer: SaveCapturePoller (1 Hz quiescence capture), SaveStore (local save_line/save_revision tables), SaveUploadLane, and the save: journal spine this plan expands horizontally"
provides:
  - "SaveArtifactSet: sorted, timestamp-free (path, size, sha256) capture-unit manifest (D-08), with manifestDigest recorded alongside -- never used for -- dedupe, export filenames, or the compatibility gate"
  - "SaveCapturePoller's D-04 two-tier model: startSession() (session-start baseline, origin: external), observe()/settle() writing a rolling staged capture, and promote() turning the session's newest staged bytes into the one permanent promoted revision"
  - "save_revision's tier/origin/manifest_digest/session_id/artifact_set_json columns and the save_capture_blocked table (Migrations)"
  - "SaveSessionRecovery: D-07 crash recovery, replaying the identical settle-then-promote pass a live session runs at its own end, idempotent by digest, derived purely from tier/session_id -- no separate open-session table"
  - "SaveCaptureBlockedState: D-31's durable blocked row, one-alert-per-blockage, retry-forever, and direct-upload escape-hatch seam"
  - "QuotaManager.saveReserveBytes (268_435_456, D-29): the local mirror of the server-side 256 MiB save reserve, folded into the free-space floor"
affects: [04-07, 04-08, 04-09, 04-10, 04-11, 04-12]

actuals:
  tokens: 21858
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Tier discriminator (staged/promoted/baseline) plus origin (session/external) on the same save_revision table, rather than a separate table per tier -- keeps one query surface for the whole DAG while letting fetchHead exclude the ephemeral staged tier"
    - "Crash recovery derives 'sessions left open' purely from existing tier/session_id columns (no dedicated open-session table) and replays through the exact same SaveCapturePoller.settle()/promote() code path a live session uses -- idempotent-by-digest is the single-winner guard against double promotion, whether from a second replay or a live poller racing recovery"
    - "A rolling staged capture is written to one fixed, session-scoped filename (atomically overwritten each write); promoted/baseline captures are written to a permanent, content-addressed <digest>.sav path -- the same write() primitive, discriminated only by the destination filename"

key-files:
  created:
    - playstead-mac/Playstead/Saves/SaveArtifactSet.swift
    - playstead-mac/Playstead/Saves/SaveSessionRecovery.swift
    - playstead-mac/Playstead/Saves/SaveCaptureBlockedState.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift
  modified:
    - playstead-mac/Playstead/Saves/SaveCapturePoller.swift
    - playstead-mac/Playstead/Persistence/SaveStore.swift
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Cache/QuotaManager.swift

key-decisions:
  - "observe()/settle() keep returning a non-nil CapturedSave on the exact same reads 04-04's SaveUploadLaneTests already exercise (now tagged tier: .staged instead of an implicit promotion), and promote() is a new, distinct step -- this is what let the two-tier model land with zero changes to 04-04's shipped test file"
  - "A staged capture is written to a fixed, session-scoped filename that is atomically overwritten on every supersession; promoted/baseline captures keep the pre-existing permanent, content-addressed <digest>.sav naming -- one write() primitive, two destination-naming policies"
  - "SaveSessionRecovery.abandonedSessionIDs derives 'left open' purely from save_revision's tier/session_id columns (staged with no matching promoted row) rather than adding a dedicated open-session table -- stays within this plan's declared file list and needs no new migration"
  - "The 256 MiB save reserve is folded into QuotaManager's free-space floor check (not the logical quota), since it is specifically about physical disk headroom for a future save capture, matching D-29's own framing of 'downloads permitted to consume'"
  - "SaveCaptureAlert is a save-domain-local type, never Playstead.Attention.Reason -- that vocabulary is frozen and owned by a different bounded context (plan 04-10); SaveCaptureBlockedState raises its own signal today and plan 04-10 wires a durable attention item to it later"

requirements-completed: [SAVE-01]

coverage:
  - id: D1
    description: "A session with five quiescent changes produces five successive staged captures, each superseding the last, and exactly one promoted revision at session end; a zero-byte artifact never produces a revision"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift test_fiveQuiescentChanges_produceFiveStagedCaptures_andExactlyOnePromotedRevision, test_zeroByteArtifact_producesNoCapture (pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Opening a session with on-disk bytes differing from the last recorded revision creates a session-start baseline revision marked origin: external before any staged capture; matching bytes create no baseline; the promoted revision's parent is the baseline when one exists, else the line's prior head"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift (4 tests: sessionStart_bytesDiffer/Match/noKnownHead, promotedRevisionParent_isSessionBaseline/isLinePriorHead) (pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "SaveArtifactSet is a sorted, timestamp-free manifest reproducible byte-for-byte across runs; the stored blob digest is the raw artifact sha256 and, for the single-entry mGBA case, differs from the manifest digest"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift test_artifactSet_isSortedAndTimestampFree..., test_storedBlobDigestEqualsRawSha256_andDiffersFromManifestDigest... (pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "SaveSessionRecovery replays a crashed session's identical settle-then-promote pass at launch and produces the revision the crash prevented; a replay with nothing new produces no revision and no output; recovery never branches on how the session's process exited"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift test_replay_promotesTheRevisionTheCrashedSessionDidNot, test_replay_whenNothingChangedSinceLastRecordedRevision_producesNoRevision, test_recovery_runsIdenticallyForAllFourAdapterExitClassifications_andNoRecordedExit (pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Running recovery twice, or recovery racing a live poller's own promotion for the same session, produces exactly one promoted revision (idempotent-by-digest single-winner guard)"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift test_runningRecoveryTwice_..., test_runningRecoveryConcurrentlyWithLivePoller_... (pass)"
        status: pass
    human_judgment: false
  - id: D6
    description: "A disk-full capture failure writes a durable blocked row, raises exactly one alert per distinct blockage, leaves a persistent attention state until cleared, is retried every subsequent poll cycle without stopping the running game, and deletes nothing"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift (4 tests: diskFullFailure_writesDurableBlockedRow, blockedCapture_isRetriedOnNextPollCycle, secondDiskFullFailure_..., diskFullFailure_deletesNothing_...) (pass)"
        status: pass
    human_judgment: false
  - id: D7
    description: "The quota sum over cache objects and save revisions equals the cache-objects-only sum; the permitted download budget is reduced by exactly 268,435,456 bytes (256 MiB) relative to the same computation without the save reserve"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift test_quotaSum_..., test_permittedDownloadBudget_isReducedByExactlyTheSaveReserve (pass)"
        status: pass
    human_judgment: false
  - id: D8
    description: "No save revision ever appears in the eviction candidate list under maximum quota pressure; evicting a game removes its cached bytes and leaves its save revision count unchanged; unpinning a game does not expose its saves; no 'never evictable' status rung exists anywhere"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift (4 tests: evictionCandidates_..., evictingAGame_..., unpinningAGame_..., noNeverEvictableStatusRung_...) (pass)"
        status: pass
    human_judgment: false

duration: 65min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 6: Two-Tier Save Capture, Crash Recovery, and the Never-Evictable Quota Reserve Summary

**D-04's staged/promoted/baseline capture tiers with D-08's timestamp-free artifact-set identity, D-07's idempotent-by-digest crash recovery replaying the exact settle-then-promote code path a live session uses, D-31's durable one-alert-ever disk-full blocked-capture state, and D-29's 256 MiB free-space save reserve with saves proven structurally unreachable by eviction.**

## Performance

- **Duration:** ~65 min
- **Started:** 2026-09-04T00:58:00Z
- **Completed:** 2026-09-04T01:24:00Z
- **Tasks:** 3
- **Files modified:** 10 (6 created, 4 modified)

## Accomplishments

- `SaveArtifactSet` (D-08): a sorted, timestamp-free `(path, size, sha256)` manifest, with `manifestDigest` computed and recorded alongside the raw artifact digest but never substituted for it in dedupe, export filenames, or the compatibility gate
- `SaveCapturePoller` expanded from 04-04's implicit "every quiescent capture is promoted" tracer behavior into D-04's real two-tier model: `startSession()` (session-start baseline, `origin: external`, when on-disk bytes diverge from the known head), `observe()`/`settle()` now write a rolling, session-scoped **staged** capture (atomically superseded on every write), and a new `promote()` turns the session's newest staged bytes into the one permanent **promoted** revision -- backward-compatible with every existing 04-04 test
- `Migrations`: `tier`/`origin`/`manifest_digest`/`session_id`/`artifact_set_json` columns on `save_revision` (defensive `ALTER`s plus updated `CREATE TABLE`), and the new `save_capture_blocked` table
- `SaveSessionRecovery` (D-07): derives "sessions left open" purely from existing `tier`/`session_id` columns (a `staged` row with no matching `promoted` row), then replays the *identical* `SaveCapturePoller.settle()`/`promote()` pair a live session runs at its own end -- idempotent by digest, safe against a second replay or a live poller racing it, and never branches on how the session's process exited
- `SaveCaptureBlockedState` (D-31): a durable blocked row per distinct blockage, exactly one alert ever per still-open blockage, a persistent attention state until cleared, retry-every-cycle semantics, a direct-upload escape-hatch seam, and never a delete -- raised through its own local `SaveCaptureAlert` type, never the frozen `Attention.Reason` vocabulary a different bounded context owns
- `QuotaManager.saveReserveBytes` (268,435,456 = 256 MiB, D-29): folded into the free-space floor check so a download can never eat into the headroom a save capture needs; confirmed by test (not merely assumed) that save blobs never land in `cache_objects`, that `EvictionPlanner`'s candidate selection structurally never touches `save_revision`, and that evicting a game leaves its saves untouched
- Found and fixed a real bug before it shipped: `fetchHead(saveLineID:)` didn't exclude `staged` tier rows and selected only the pre-04-06 16-column shape, so a rolling staged blob could be mistaken for the line's DAG head and the new columns silently read back as defaults

## Task Commits

1. **Task 1: Two capture tiers, a baseline revision, and artifact-set identity** - `14e55ef` (test, tdd)
2. **Task 2: Crash recovery and the disk-full blocked path** - `a7cd423` (feat, tdd)
3. **Task 3: Saves are free, reserved, and never evictable** - `20ae44d` (test, tdd)

## Files Created/Modified

- `playstead-mac/Playstead/Saves/SaveArtifactSet.swift` - D-08's sorted, timestamp-free capture-unit manifest
- `playstead-mac/Playstead/Saves/SaveCapturePoller.swift` - D-04's staged/promoted/baseline tiers, `startSession()`/`promote()`
- `playstead-mac/Playstead/Saves/SaveSessionRecovery.swift` - D-07's idempotent-by-digest crash recovery
- `playstead-mac/Playstead/Saves/SaveCaptureBlockedState.swift` - D-31's durable blocked-capture state
- `playstead-mac/Playstead/Persistence/Migrations.swift` - New `save_revision` columns and the `save_capture_blocked` table
- `playstead-mac/Playstead/Persistence/SaveStore.swift` - `SaveRevisionRow`'s five new fields, `fetchRevisions(sessionID:)`, `fetchHead` tier-exclusion fix
- `playstead-mac/Playstead/Cache/QuotaManager.swift` - `saveReserveBytes` folded into the floor check
- `playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift` - 9 tests (task 1)
- `playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift` - 9 tests (task 2)
- `playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift` - 6 tests (task 3)

## Decisions Made

See `key-decisions` in frontmatter -- five decisions covering backward-compatible tier integration, the fixed-vs-content-addressed staging path split, deriving abandoned sessions without a new table, folding the reserve into the floor rather than the quota, and keeping the blocked-capture alert outside the frozen attention vocabulary.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `fetchHead(saveLineID:)` excluded neither the new `staged` tier nor selected the five new columns**
- **Found during:** Task 2 (wiring `SaveSessionRecovery`'s `knownHeadDigest` seed from `SaveStore.fetchHead`)
- **Issue:** Task 1 added `tier`/`origin`/`manifest_digest`/`session_id`/`artifact_set_json` to `save_revision` and to `Self.row(from:)`'s 21-column read, but `fetchHead`'s own hand-written `SELECT` still named only the original 16 columns, so those five fields silently fell back to their schema defaults on every `fetchHead` call. Worse, `fetchHead`'s "no children" query had no tier filter at all, so a rolling `staged` row (never a DAG node) could be mistaken for the line's real head.
- **Fix:** `fetchHead`'s `SELECT` now names all 21 columns, and its `WHERE` clause excludes `tier = 'staged'` -- only a `promoted` or `baseline` row can ever be the line's head.
- **Files modified:** `playstead-mac/Playstead/Persistence/SaveStore.swift`
- **Verification:** `SaveSessionRecoveryTests` exercises `fetchHead` indirectly through every replay scenario (all pass); full Unit test plan (325 tests) green
- **Committed in:** `a7cd423` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug, in code this plan's own Task 1 had just introduced).
**Impact on plan:** Necessary for `SaveSessionRecovery`'s correctness; no scope creep -- the touched function (`fetchHead`) was already part of `SaveStore.swift`, a file this plan's Task 1 modified.

## Issues Encountered

None beyond the deviation above.

## Known Stubs

- `SaveDirectUploadTransport.uploadDirectly` (`SaveCaptureBlockedState.swift`) is a declared-but-undialed seam: the real authenticated HTTP streaming transport for D-31's direct-upload escape hatch is deferred to a later plan, mirroring plan 04-04's `SaveBytesPrefetcher` documented-stub precedent for the same reason (transport wiring is outside this plan's declared files). `attemptDirectUpload` is a real, tested no-op when no transport is injected.
- The saves-owned attention item (D-66) that plan 04-10 will wire to `SaveCaptureAlert` does not exist yet -- `SaveCaptureBlockedState` raises its own local `SaveCaptureAlert` today via an injectable `SaveCaptureAlertSink`, which is the seam plan 04-10 will consume.
- `SaveSessionRecovery` is not yet called from `PlaysteadApp`'s launch sequencing -- this plan builds and tests the recovery primitive itself; wiring it into actual app-launch sequencing (enumerating real save lines and constructing real `AbandonedSaveSession` values from the live save directory) is a later plan's integration concern, consistent with 04-04's precedent of building capture primitives before their live-session wiring.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers -- no new network endpoint, auth path, or schema change outside that register was introduced. `save_capture_blocked` is a purely local, non-networked table.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The tier/origin/session columns and `SaveSessionRecovery`'s digest-based idempotency are the foundation plan 04-07 (or whichever plan first wires live session lifecycle) needs to actually call `startSession()`/`observe()`/`settle()`/`promote()` from a real play session and call `SaveSessionRecovery.replayAll` from app launch
- `SaveCaptureAlert`/`SaveCaptureAlertSink` is the exact seam plan 04-10 wires its saves-owned attention source into, without changing `SaveCaptureBlockedState`
- Deferred/flagged for follow-up: the direct-upload transport, live app-launch wiring for recovery, and live session wiring for the poller's tier API -- all tracked above
- Ready for 04-07.

## Self-Check: PASSED

- `[ -f playstead-mac/Playstead/Saves/SaveArtifactSet.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/SaveSessionRecovery.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/SaveCaptureBlockedState.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/SaveCaptureTierTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift ]` → FOUND
- `git log --oneline --all | grep -q 14e55ef` → FOUND
- `git log --oneline --all | grep -q a7cd423` → FOUND
- `git log --oneline --all | grep -q 20ae44d` → FOUND
- `xcodebuild test ... -only-testing:PlaysteadTests/SaveCaptureTierTests` → PASS (9 tests, 0 failures)
- `xcodebuild test ... -only-testing:PlaysteadTests/SaveSessionRecoveryTests` → PASS (9 tests, 0 failures)
- `xcodebuild test ... -only-testing:PlaysteadTests/SaveQuotaInteractionTests` → PASS (6 tests, 0 failures)
- `xcodebuild test ... -testPlan Unit` (full plan) → PASS (325 tests, 0 failures)
- `grep -v '^\s*//' SaveArtifactSet.swift | grep -ciE 'Date\(\)|now|timestamp'` → 0
- `grep -v '^\s*//' SaveSessionRecovery.swift | grep -c 'AdapterExit'` → 0
- `grep -rn 'Attention.Reason' playstead-mac/Playstead/Saves/` → no matches
- `grep -c '268_435_456' QuotaManager.swift` → 1
- `grep -rniE 'neverEvictable|notEvictable' StatusToken.swift` → no matches
- `grep -rn 'AdapterExit' playstead-mac/Playstead/Saves/` → no matches
- `grep -rniE 'func evict|delete' SaveStore.swift` → matches only the pre-existing, test-only `clearAll()` helper (predates this plan; see Known Stubs / plan-level note above)

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*
