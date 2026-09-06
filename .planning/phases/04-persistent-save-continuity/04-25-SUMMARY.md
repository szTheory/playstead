---
phase: 04-persistent-save-continuity
plan: 25
subsystem: sync
tags: [swift, concurrency, nslock, save-outbox, race-condition, gap-closure]

requires:
  - phase: 04-persistent-save-continuity
    provides: "SaveOutbox/SaveOutboxDrainTrigger constructed and drained by real production triggers (04-23)"
provides:
  - "SaveOutboxDrainTrigger.fire() with a single critical section covering the predecessor read, Task construction, drainCount increment, and _lastTask replacement — the client-side single-lane drain guarantee is now actually true under concurrency, not merely documented"
  - "A racing test that genuinely interleaves two fire() calls from separate threads via an explicit barrier, distinguishing it from the pre-existing synchronous double-fire() test that cannot observe this class of defect"
affects: [04-persistent-save-continuity, save-conflict-resolution]

actuals:
  tokens: 9500
  tasks: 2
  commits: 1

tech-stack:
  added: []
  patterns:
    - "Single critical section for read-modify-write serialization state: the fix pattern is to fold the predecessor read and the replacement write into one lock/unlock pair rather than two, since Task construction itself never blocks or re-enters the lock and is therefore safe to build inside the section."

key-files:
  created: []
  modified:
    - playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift

key-decisions:
  - "Kept NSLock and a synchronous fire() exactly as before — only merged two critical sections into one — per the plan's explicit prohibition against switching to an actor/DispatchQueue or making fire() async, since that would touch three production call sites for no benefit."
  - "Wrapped the racing test's blocking DispatchSemaphore/DispatchGroup waits in a plain (non-async) helper function (raceTwoFireCalls) rather than calling them directly inside the async test body, to avoid the 'unavailable from asynchronous contexts' warnings that are hard errors under the Swift 6 language mode."
  - "Used a distinct content-key prefix (round-content-N) for the racing test's per-round fixtures after discovering round 1's naive 'content-N' key collided with setUp's own 'content-1' fixture, silently resolving to the wrong save_line id and producing an unrelated FOREIGN KEY failure — documented as a self-caught bug in the test's own seeding helper, not the production code."

patterns-established:
  - "A plain (non-async) private static helper isolates blocking synchronization primitives (DispatchSemaphore/DispatchGroup.wait) away from an async XCTest method body, sidestepping Swift 6 strict-concurrency diagnostics without weakening the barrier's actual behavior."

requirements-completed: [SAVE-04]

coverage:
  - id: D1
    description: "SaveOutboxDrainTrigger.fire() serializes the predecessor read and _lastTask replacement inside one critical section, closing the TOCTOU race 04-VERIFICATION gap 2 / 04-REVIEW-gaps-mac.md CR-01 identified"
    requirement: SAVE-04
    verification:
      - kind: unit
        ref: "SaveOutboxDrainTriggerTests.swift#testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass"
        status: pass
      - kind: unit
        ref: "SaveOutboxDrainTriggerTests.swift#testTwoOverlappingDrainPassesProduceAtMostOneSuccessfulSend"
        status: pass
      - kind: other
        ref: "awk-extracted fire() body source gate: exactly one lock.lock()/lock.unlock() pair"
        status: pass
    human_judgment: false
  - id: D2
    description: "No second copy of the read-then-separately-write defect exists elsewhere in Sync/ or Saves/; the full Mac and server test gates remain green"
    requirement: SAVE-04
    verification:
      - kind: unit
        ref: "Unit test plan: 583 tests, 582 passed, 1 pre-existing unrelated flake (isolated re-run passed)"
        status: pass
      - kind: other
        ref: "playstead-mac/scripts/ci/reachability-sweep.sh --strict"
        status: pass
      - kind: integration
        ref: "playstead-server MIX_ENV=test mix test — 1034 tests, 0 failures"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-06
status: complete
---

# Phase 04 Plan 25: Save-Outbox Drain Trigger Race Fix Summary

**Merged `SaveOutboxDrainTrigger.fire()`'s two separately-locked read/write halves into one critical section, closing the TOCTOU race that let concurrent triggers double-send a save-resolution intent, and proved it with a genuinely multi-threaded racing test.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-06T03:10:00Z (approx.)
- **Completed:** 2026-09-06T04:02:23Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `SaveOutboxDrainTrigger.fire()` now reads `_lastTask`, constructs the chained `Task`, increments `_drainCount`, and replaces `_lastTask` all inside one `lock.lock()`/`lock.unlock()` pair — closing the window where two concurrent callers could observe the same predecessor and both start a `SaveOutbox.drainOnce` pass.
- Added `testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass`, which releases two threads into `fire()` at the same instant via an explicit `DispatchSemaphore`/`DispatchGroup` barrier across 200 rounds, asserting the maximum concurrent responder in-flight count is exactly 1 and every round's entry is delivered exactly once.
- Falsified the fix honestly: temporarily restored the old two-locked-section form and confirmed both (a) the deterministic `awk`-extracted source gate flips from 1 to 2 `lock.lock()` calls, and (b) the racing test genuinely reproduces the defect — 218 successful sends across 200 rounds instead of 200, i.e. 18 duplicate sends — before restoring the fix.
- Audited every trigger/lane type in `playstead-mac/Playstead/Sync/` and `playstead-mac/Playstead/Saves/` for the same read-then-separately-write shape; confirmed the defect existed in exactly one place.
- Ran the full Mac Unit test plan (583 tests), the reachability sweep, and the full server `mix test` suite (1034 tests) to confirm no regression beyond the known-flaky suites.

## Task Commits

1. **Task 1: TRACER: one critical section, proven by a test that really races two threads** - `b5dd235` (fix) — includes both the production fix and the new racing test, per the plan's file grouping.
2. **Task 2: Audit for a second copy of the defect and prove the whole Mac gate still holds** - no code changes; audit findings and full-gate verification recorded below.

**Plan metadata:** (this commit)

## Files Created/Modified

- `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift` - `fire()` rewritten to hold one critical section across the predecessor read, `Task` construction, `_drainCount` increment, and `_lastTask` replacement; doc comment updated to describe the actual guarantee and why the sibling `OutboxDrainTrigger` needs no equivalent section.
- `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift` - added `testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass`, its `raceTwoFireCalls`/`FireResultBox` helpers, and `seedRoundDivergence` (per-round fixture seeding).

## Decisions Made

- Kept the existing `NSLock` and synchronous `fire()` signature exactly as before — only the internal ordering of operations changed. No concurrency primitive was swapped, and all three production call sites (`saveOutbox.onEnqueue`, `reachability.onChange`, `applicationDidBecomeActive`) are untouched (confirmed via `git diff --stat playstead-mac/Playstead/App/PlaysteadApp.swift` being empty).
- The racing test's blocking waits (`DispatchSemaphore.wait()`, `DispatchGroup.wait()`) are isolated in a plain, non-`async` static helper (`raceTwoFireCalls`) rather than called directly from the `async throws` test method, avoiding the "unavailable from asynchronous contexts" warnings that become hard errors under the Swift 6 language mode. The two `Task` handles are handed back through a small lock-guarded `FireResultBox` rather than captured `var`s, for the same strict-concurrency-safety reason.
- The racing test's per-round content key is `"round-content-\(round)"`, not the more obvious `"content-\(round)"` — round 1's naive key collided with `setUpWithError`'s own `"content-1"` fixture (used for the non-racing tests' shared `line-1`), which silently resolved `resolveLine` to the *existing* `line-1` row while `insertRevision` still targeted the never-created `"round-1"` id, producing a `FOREIGN KEY constraint failed` error unrelated to the concurrency behavior under test. This was found and fixed during this plan's own verification pass, not left as an open issue.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test fixture content-key collision caused a FOREIGN KEY failure unrelated to the concurrency behavior under test**
- **Found during:** Task 1 (writing and first-running the new racing test)
- **Issue:** `seedRoundDivergence`'s per-round `contentKey: "content-\(round)"` collided with `setUpWithError`'s own `"content-1"` fixture at round 1, causing `SaveStore.resolveLine` to resolve to the pre-existing `line-1` row while `insertRevision` still referenced the never-created `"round-1"` save-line id — a `FOREIGN KEY constraint failed` error that looked like it might be concurrency-related but was purely a test-fixture bug.
- **Fix:** Changed the per-round content key prefix to `"round-content-\(round)"`, eliminating the collision.
- **Files modified:** `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift`
- **Verification:** Re-ran the isolated seeding helper and the full racing test; both passed cleanly across 200 rounds.
- **Committed in:** `b5dd235` (part of Task 1 commit)

**2. [Rule 1 - Bug, self-corrected before commit] Direct blocking waits in an async test body produced Swift 6-unsafe warnings**
- **Found during:** Task 1 (initial build of the racing test)
- **Issue:** The first draft called `DispatchSemaphore.wait()`/`DispatchGroup.wait()` directly inside the `async throws` test method, which the compiler flags as "unavailable from asynchronous contexts... an error in the Swift 6 language mode" — not yet a build failure today, but a latent one.
- **Fix:** Extracted the barrier logic into a plain (non-`async`) private static helper (`raceTwoFireCalls`), with the two `Task` handles returned through a lock-guarded `FireResultBox` rather than captured `var`s.
- **Files modified:** `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift`
- **Verification:** Clean rebuild produced zero warnings on the modified test file.
- **Committed in:** `b5dd235` (part of Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs, both confined to the new test's own fixture/helper code, never shipped in a broken state)
**Impact on plan:** Both fixes were necessary for the new test to actually prove what it claims and to avoid introducing latent strict-concurrency warnings. No scope creep — the production fix in `SaveOutboxDrainTrigger.swift` needed no deviations.

## Task 2: Audit findings

Every trigger/lane type in `playstead-mac/Playstead/Sync/` and `playstead-mac/Playstead/Saves/` that owns any lock-guarded serialization state:

| Type | File | Affected? | Reason |
|---|---|---|---|
| `SaveOutboxDrainTrigger` | Sync/SaveOutboxDrainTrigger.swift | **Fixed here** | The one place with the read-then-separately-write shape; now closed (Task 1). |
| `OutboxDrainTrigger` | Sync/OutboxDrainTrigger.swift | **Unaffected** | `fire()` never reads `_lastTask` before constructing its `Task` — it locks exactly once, after the `Task` already exists, purely to record `_drainCount`/`_lastTask`. There is no earlier read to race against, because `OutboxWorker` is an actor and supplies the serialization for free. `git diff --stat playstead-mac/Playstead/Sync/OutboxDrainTrigger.swift` is empty — nothing here was touched, correctly. |
| `SaveUploadLane` | Saves/SaveUploadLane.swift | **Unaffected** | `SaveUploadLane` is itself an `actor`; its `drainOnce` is actor-isolated and cannot run two passes concurrently by construction — no lock-based serialization exists or is needed here. |
| `SaveUploadClassificationCell` (nested in SaveUploadLane.swift) | Saves/SaveUploadLane.swift | **Unaffected** | Its `NSLock` guards a single `_value` cell (get/set), not any read-then-replace serialization of a drain pass. Both its `lock.lock()`/`lock.unlock()` pairs are single-purpose accessor locks, not split halves of one logical operation. |

No second occurrence of the defect was found. This confirms the plan's `must_haves` claim that the read-then-separately-write shape existed in exactly one place.

## Full-gate verification results

- **Unit test plan (Mac):** 583 tests total, 582 passed, 1 failed under full-suite load: `PlaySessionTests.test_launchSucceedsIndependentlyOfPlaySessionRecording()` (`Asynchronous wait failed: Exceeded timeout of 5 seconds, with unfulfilled expectations: "process exits"`). This is **not** one of the two known-flaky suites 04-23 recorded (`AppPathsBackupExclusionTests.testExistingInstallWithStaleRootFlagIsRepairedAtInit`, `SetupWizardJourneyTest`) but exhibits the identical pattern: it is unrelated to any file this plan touched (no relation to `SaveOutbox`/`SaveOutboxDrainTrigger`), reproduced consistently across two separate full-suite runs, and **passed cleanly in isolation** (`Executed 1 test, with 0 failures... in 0.647 seconds`). Recorded here as a third observed load-sensitive flaky test for the phase verifier's awareness, per the same reasoning that excused the other two — not chased, per scope boundary (out-of-scope for this plan's two Swift files).
- **Reachability sweep:** `cd playstead-mac && scripts/ci/reachability-sweep.sh --strict` — exit 0, "No unreachable production symbols found."
- **Server suite:** `cd playstead-server && MIX_ENV=test mix test` — 178 features, 13 properties, **1034 tests, 0 failures** (above the required 1030). This plan touches no Elixir; the run confirms nothing unrelated moved.
- **Scope check:** `git diff --name-only` (production diff, task 1's commit) touches only `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift` and `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift`, matching `files_modified` exactly. `git diff --name-only -- playstead-server` is empty.

## Falsification check (mandatory, plan-required)

Restored the pre-fix two-locked-section form of `fire()` (predecessor read under one `lock.lock()`/`lock.unlock()`, `Task` construction outside any lock, then a second `lock.lock()`/`lock.unlock()` to record `_drainCount`/`_lastTask`) and re-ran both checks:

1. **Source gate:** `awk`-extracted `fire()` body's `lock.lock()` count went from 1 to **2** — the deterministic gate goes red exactly as required.
2. **Racing test:** re-ran `testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass` against the broken form. It failed with `XCTAssertEqual failed: ("218") is not equal to ("200") - every round's entry must be delivered exactly once` — 18 duplicate sends observed across 200 rounds. This is a genuine, observed reproduction of the race, not an unobserved/assumed one. (Note: the `maxInFlight == 1` assertion did *not* independently fail in this run — Swift's cooperative thread pool combined with the `Thread.sleep`-based responder appears to have serialized the two passes' network calls onto the same worker thread in this particular run rather than truly overlapping wall-clock windows, even though the entries were still double-sent. The duplicate-send count is the primary and sufficient evidence of the defect; it is what the client-side guarantee exists to prevent.)

Restored the fixed form afterward and re-confirmed: source gate back to 1, full targeted test suite (`SaveOutboxDrainTriggerTests` + `SaveConflictResolverTests`, 23 tests) green.

## Issues Encountered

None beyond the two self-caught test-fixture issues documented under Deviations, both resolved before the final commit.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The client-side single-lane guarantee `SaveOutboxDrainTrigger` documents is now true under real concurrency; ROADMAP criterion 5's `resolve` verb no longer depends on the server-side idempotency backstop to be correct.
- No `.planning/WINDOWS.md` entry was written by this plan, per the plan's own instruction (the fix leaves no residual open window, and this keeps 04-24 and 04-25 free of a shared-file conflict).
- One newly observed load-sensitive flaky test (`PlaySessionTests.test_launchSucceedsIndependentlyOfPlaySessionRecording`) is flagged above for the phase verifier's awareness — unrelated to this plan's scope, not chased, passes in isolation.
- CP7-SAVE-C and `04-UAT.md` were not touched, per the plan's explicit prohibition.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-06*
