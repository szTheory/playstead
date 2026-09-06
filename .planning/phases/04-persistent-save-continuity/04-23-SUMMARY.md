---
phase: 04-persistent-save-continuity
plan: 23
subsystem: saves
tags: [swift, swiftui, cas, outbox, sync, windows-ledger]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-21's real save revisions in export, 04-22's real save history/rollup wiring -- both gap-closure plans this plan finishes alongside"
provides:
  - "SaveOutboxDrainTrigger -- SaveOutbox's drain trigger, wired to the same three trigger classes (post-enqueue, reachability-regained, scene-active) the curation outbox already has"
  - "SaveCaptureBytesCommitter -- the CAS-commit implementation extracted out of SaveSessionCoordinator and shared with SaveSessionRecovery, so the live and crash-recovery capture paths cannot drift apart again"
  - "SaveSessionRecovery.replay commits a promoted capture's bytes into the CAS before inserting its row, closing the crash-recovery half of the zero-network restore guarantee"
  - "A truthful WINDOWS.md: #30, #42, #43, #47, #52 marked fixed with resolving commits recorded; the stale #32 closed with the commit that actually resolved it"
affects: [saves, sync, export]

actuals:
  tokens: 17755
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "SaveOutboxDrainTrigger mirrors OutboxDrainTrigger's shape exactly (drainCount, awaitPending()) but self-serializes overlapping fire() calls by awaiting the previous task, since SaveOutbox is a plain class rather than an actor"
    - "A shared CAS-commit implementation (SaveCaptureBytesCommitter) is the single spelling both the live capture path and the crash-recovery path call, rather than two copies that drift apart"
    - "WINDOWS ledger entries are closed via gsd-tools windows fixed <id> (keeps frontmatter counters consistent), then hand-annotated with the resolving commit hash in the description"

key-files:
  created:
    - playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift
    - playstead-mac/Playstead/Saves/SaveCaptureBytesCommitter.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift
  modified:
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/Playstead/Sync/Outbox.swift
    - playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift
    - playstead-mac/Playstead/Saves/SaveSessionRecovery.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift
    - playstead-mac/PlaysteadTests/SyncTests/JournalRevisionMergeTests.swift
    - .planning/WINDOWS.md

key-decisions:
  - "SaveOutboxDrainTrigger serializes its own passes (await the previous _lastTask before starting the next) rather than relying on actor isolation, because SaveOutbox.drainOnce is a plain method on a plain class, not an actor method like OutboxWorker.drainOnce."
  - "CASManager construction moved ahead of the saves block in AppEnvironment.init (rather than making SaveSessionRecovery's casManager property optional), since SaveSessionRecovery now needs one and casManager was previously constructed later in init."
  - "A CAS commit failure on the recovery path is recorded as a D-31 blockage and does not abort the row insert -- identical to the live path's contract, since the row's localPath is still where SaveUploadLane reads bytes from."
  - "WINDOWS #32 closed as STALE rather than fixed-by-this-plan: ConflictComparisonSheet was wired into ReadinessSheetView by plan 04-16 / commit c223218, which postdates the ledger entry; the row now records c223218 as the resolving commit."

requirements-completed: [SAVE-01, SAVE-03, SAVE-04]

coverage:
  - id: D1
    description: "A divergence resolved on this Mac reaches the server: SaveOutbox.drainOnce(apiClient:) has a production call site fired on the same trigger classes Outbox/SaveUploadLane use (ROADMAP criterion 5's resolve verb)."
    requirement: SAVE-04
    verification:
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift (9 tests covering every <behavior> bullet)"
        status: pass
      - kind: integration
        ref: "PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testResolvingThroughTheProductionEntryPointReachesTheWireWithTheRightPathAndKey"
        status: pass
    human_judgment: false
  - id: D2
    description: "A save revision recovered from a crashed session has its bytes in the CAS, so LaunchSaveContextBuilder reports bytesLocal: true for it and zero-network restore of a crash-recovered revision works (ROADMAP criterion 3)."
    requirement: SAVE-01
    verification:
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_replay_commitsThePromotedRevisionsBytesToTheCAS"
        status: pass
      - kind: integration
        ref: "PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_launchSaveContextBuilder_reportsBytesLocalTrue_forACrashRecoveredRevision"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_falsification_bytesLocalIsFalseWhenTheCASWasNeverCommittedTo"
        status: pass
    human_judgment: false
  - id: D3
    description: "Running crash recovery twice commits the same digest to the CAS at most once and inserts no second revision row; a CAS commit that throws still inserts the row and records a blockage without propagating."
    requirement: SAVE-03
    verification:
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_replayAllRunTwice_insertsNoSecondRow_commitsNoSecondCopy"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift#test_aThrowingCASCommit_stillInsertsTheRow_recordsABlockage_andReplayReturnsNormally"
        status: pass
    human_judgment: false
  - id: D4
    description: "Draining the save outbox twice sends each entry under the same Idempotency-Key and a delivered entry is deleted; a rejected send leaves local resolution intact and increments attempt_count."
    verification:
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testEverySendCarriesTheEntrysIdempotencyKeyAndARetryReplaysTheSameKey"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testARejectedSendLeavesTheEntryQueuedAndDispositionUntouched"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift#testASuccessfulDrainDeletesTheEntryAndASecondDrainSendsNothing"
        status: pass
    human_judgment: false
  - id: D5
    description: "The WINDOWS ledger reports the same thing the source does: #30, #42, #43, #47, #52 fixed with resolving commits; stale #32 closed with the commit that actually resolved it; CP7-SAVE-C left untouched."
    verification:
      - kind: other
        ref: "gsd-tools windows status (ok: true); WINDOWS.md counters open_count 41->35, fixed_count 11->17, total_count unchanged at 53"
        status: pass
      - kind: other
        ref: "6 confirming greps from 04-VERIFICATION's spot-check table, each returning the opposite of what verification recorded"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-09-06
status: complete
---

# Phase 04 Plan 23: Save outbox drains, crash-recovered bytes enter the CAS, ledger closed honestly Summary

**A resolved save divergence now reaches the server via a new SaveOutboxDrainTrigger wired to all three trigger classes, crash-recovered captures commit their bytes into the CAS through a shared SaveCaptureBytesCommitter, and the WINDOWS ledger records six real resolutions -- five fixed-by-this-phase, one closed as stale by an earlier plan's commit.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-09-06T01:44:00Z
- **Completed:** 2026-09-06T02:29:00Z
- **Tasks:** 3
- **Files modified:** 10 (3 created, 7 modified)

## Accomplishments

- `SaveOutboxDrainTrigger` (new, mirrors `OutboxDrainTrigger`'s shape) serializes its own drain passes and is wired to all three trigger classes `AppEnvironment` already uses for the curation outbox: post-enqueue (`SaveOutbox.onEnqueue`, new), reachability-regained (added to the existing `reachability.onChange` closure), and scene-active (`drainSaveOutbox()`, called from `applicationDidBecomeActive()`). Closes WINDOWS #42 -- a resolved divergence now converges across devices instead of sitting in a table nothing reads.
- `SaveSessionCoordinator.commitCaptureBytes` extracted verbatim into a shared `SaveCaptureBytesCommitter` type; `SaveSessionRecovery` now takes a required `CASManager` and an optional `SaveCaptureBlockedState`, and `replay` commits a promoted capture's bytes into the CAS (after the already-recorded-digest guard, before the row insert) exactly like the live path. A commit failure records a D-31 blockage and does not abort the insert or propagate. Closes WINDOWS #52 -- a crash-recovered revision's bytes are now as local as a live capture's.
- `AppEnvironment.init` moves `CASManager` construction ahead of the saves block so `SaveSessionRecovery` can receive it.
- WINDOWS #30, #42, #43, #47, #52 marked `fixed` via `gsd-tools windows fixed <id>`, each row annotated with its resolving commit. The stale #32 (ConflictComparisonSheet wiring, actually resolved by plan 04-16's commit `c223218` before this ledger entry was even written) closed the same way, recording *why* it closed rather than merely *that* it closed.
- CP7-SAVE-C left exactly as it is: a blocking human checkpoint in `04-UAT.md`, never marked passed, no automated substitute (D-68).

## Task Commits

1. **Task 1: Drain the save outbox -- a resolution that actually reaches the server** - `5c6439c` (feat)
2. **Task 2: Crash-recovered captures enter the CAS, like every other capture** - `fd4e2b4` (feat)
3. **Task 3: Close the ledger, honestly** - `4dc9c60` (docs)

**Plan metadata:** (this commit)

## Files Created/Modified

- `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift` - New drain trigger mirroring `OutboxDrainTrigger`, self-serializing since `SaveOutbox` is not actor-isolated
- `playstead-mac/Playstead/Sync/Outbox.swift` - `SaveOutbox.onEnqueue` closure, fired only after a successful enqueue transaction
- `playstead-mac/Playstead/App/PlaysteadApp.swift` - `saveOutboxDrainTrigger` property, all three trigger wirings, `drainSaveOutbox()`, `CASManager` construction reordered ahead of the saves block, `SaveSessionRecovery` construction passes `casManager`/`blockedState`
- `playstead-mac/Playstead/Saves/SaveCaptureBytesCommitter.swift` - New shared CAS-commit implementation extracted from `SaveSessionCoordinator`
- `playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift` - `commitCaptureBytes` now delegates to `SaveCaptureBytesCommitter`
- `playstead-mac/Playstead/Saves/SaveSessionRecovery.swift` - Required `CASManager`, optional `SaveCaptureBlockedState`; `replay` commits bytes to the CAS before inserting the row and records a blockage on failure
- `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift` - New: 9 tests covering every `<behavior>` bullet of task 1
- `playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift` - 4 new tests (CAS commit on replay, `bytesLocal` true + falsification, throwing commit, `replayAll` twice) plus updated constructor call sites
- `playstead-mac/PlaysteadTests/SyncTests/JournalRevisionMergeTests.swift` - Updated `SaveSessionRecovery` construction site for the new required `casManager` parameter
- `.planning/WINDOWS.md` - 6 rows marked fixed with resolving commits recorded; counters updated

## Decisions Made

- `SaveOutboxDrainTrigger.fire()` awaits the previously started task before starting the next, substituting for the actor isolation `OutboxWorker`/`OutboxDrainTrigger` get for free.
- `CASManager` construction moved earlier in `AppEnvironment.init` rather than making `SaveSessionRecovery.casManager` optional -- a `nil` default would silently reproduce the exact hole this plan closes.
- A CAS commit failure on the recovery path never aborts the row insert -- identical contract to the live path, since the row's `localPath` is still where `SaveUploadLane` reads bytes from.
- WINDOWS #32 closed as *stale*, not fixed-by-this-plan, with the actual resolving commit (`c223218` from plan 04-16) recorded in its description.

## Deviations from Plan

None - plan executed exactly as written. Two commit-staging notes worth recording since `PlaysteadApp.swift`'s `AppEnvironment.init` is touched by both tasks 1 and 2 in the same edit region: task 1's commit (`5c6439c`) includes the `CASManager` construction reorder needed by task 2 (both live in the same init edit), and task 2's commit (`fd4e2b4`) contains no further `PlaysteadApp.swift` diff since it was already captured. This is a staging-attribution artifact only -- both tasks' acceptance criteria and verification passed independently before either commit was made.

### Auto-fixed Issues

None beyond the plan's own instructions.

---

**Total deviations:** 0 auto-fixed.
**Impact on plan:** None -- executed as specified.

## Issues Encountered

- The plan's task 3 `<verify>` block calls `gsd-tools query frontmatter.validate .planning/WINDOWS.md --schema windows`, but the installed `gsd-tools.cjs` (`~/.claude/gsd-core/bin/gsd-tools.cjs`) does not recognize a `windows` schema for `frontmatter.validate` (available: `plan, plan-gap-closure, summary, verification`) -- a tool-version mismatch, not a defect in this plan's WINDOWS.md edits. Verified the ledger's integrity equivalently via `gsd-tools windows status`, which returned `ok: true` with a correctly-parsed ledger and the expected counter deltas.
- The server test suite's first run showed a single unrelated failure (`PlaysteadWeb.Plugs.ThrottleTest#test call/2 allows requests under the per-IP limit`) under full-suite load; this plan touches zero server files. Re-ran the test in isolation (0 failures) and the full suite again (1030 tests, 0 failures), confirming a timing-sensitive pre-existing flake, not a regression from this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ROADMAP criterion 5's `resolve` verb now converges across devices (save outbox drains); criterion 3's zero-network restore guarantee holds for crash-recovered revisions as well as live ones.
- Full Swift Unit suite: 582 tests, 0 failures (plan required >= 545). Rendering suite: 47 executed / 2 skipped, 0 failures (plan required >= 46/2). `reachability-sweep.sh --strict`: exit 0. Server suite: 1030 tests, 0 failures.
- Falsification check passed: deleting `saveOutbox.onEnqueue = { saveTrigger.fire() }` turns `testResolvingThroughTheProductionEntryPointReachesTheWireWithTheRightPathAndKey` red; restoring it turns the suite green again with no residual diff.
- WINDOWS ledger: `open_count` 41->35, `fixed_count` 11->17, `total_count` unchanged at 53. This was the final gap-closure plan of phase 04-persistent-save-continuity's declared 04-21..04-23 sequence.
- CP7-SAVE-C remains the phase's one outstanding human continuation proof, unaffected by this plan.

## Self-Check: PASSED

- All created files verified present on disk: `SaveOutboxDrainTrigger.swift`, `SaveCaptureBytesCommitter.swift`, `SaveOutboxDrainTriggerTests.swift`.
- All task and metadata commit hashes (`5c6439c`, `fd4e2b4`, `4dc9c60`) verified present in `git log --oneline --all`.
- Re-ran full Swift Unit suite: 582 tests, 0 failures.
- Re-ran Rendering suite: 47 executed / 2 skipped, 0 failures.
- Re-ran `scripts/ci/reachability-sweep.sh --strict`: exit 0, "No unreachable production symbols found."
- Re-ran server `MIX_ENV=test mix test`: 1030 tests, 0 failures.
- Falsification check re-verified: removing `saveOutbox.onEnqueue`'s assignment turns the production-entry-point test red; restoring it turns the suite green with a clean `git diff`.
- All six task 3 acceptance-criteria greps re-run and confirmed passing.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-06*
