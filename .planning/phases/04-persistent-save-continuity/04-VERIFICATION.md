---
phase: 04-persistent-save-continuity
verified: 2026-09-06T05:00:00Z
status: human_needed
score: 4/5 must-haves verified
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 4/5
  gaps_closed:
    - "Criterion 4's 'deterministic' guarantee (PORT-01) — `Saves.get_history/2` (saves.ex:411) and `Branches.heads/2` (branches.ex:45) now order `[asc: r.recorded_at, asc: r.id]`, a genuine total order confirmed against source in this pass. `SavesPlan.plan/2` (saves_plan.ex) replaced its stability-dependent `Enum.sort_by(& &1.recorded_at, DateTime)` with an `order_key_lte?/2` comparator over `{recorded_at, id}`, making plan purity independent of caller input order (04-24, commits b0c20a1/595027f). Four new tests construct a real microsecond tie, are demonstrated red against the unfixed code (SUMMARY records the exact failing assertions), and pass green after the fix — independently re-run in this verification pass (53/53 tests, 0 failures, in the four targeted files)."
    - "Criterion 5's client-side TOCTOU race in `SaveOutboxDrainTrigger.fire()` (SAVE-04) — the predecessor read, `Task` construction, `_drainCount` increment, and `_lastTask` replacement now happen inside one `lock.lock()`/`lock.unlock()` pair (confirmed directly against `SaveOutboxDrainTrigger.swift:41-73` in this pass), closing the window where two concurrent `fire()` calls could both read the same stale predecessor and both start a `drainOnce` pass (04-25, commit b5dd235). A genuinely multi-threaded racing test was demonstrated red against the reverted two-section form (218 sends across 200 rounds — 18 duplicates) and green after the fix. An audit of every lock-guarded type in `Sync/` and `Saves/` found no second occurrence of the defect."
  gaps_remaining: []
  regressions: []
gaps: []
deferred: []
behavior_unverified_items:
  - truth: "On a clean paired Mac, a user can restore a compatible checksummed save revision and continue the game (the in-game continuation half)."
    test: "Perform the five steps in 04-13-PLAN.md's Task 3 <how-to-verify> against a real commercial GBA title through the pinned mGBA adapter: observe the .sav file changing on a bounded cadence after an in-game save, a normal quit and a force-quit each capturing a revision, silent auto-restore onto a cleared save directory with no prompt, and the game continuing from the exact saved progress with no in-game 'save corrupt, erase?' prompt."
    expected: "In-game progress after restore matches exactly what was saved before, and mGBA accepts the restored bytes as valid save data."
    why_human: "Requires a real emulator, a real commercial GBA title, and a human judging in-game continuity. This is a designed checkpoint (D-68, CP7-SAVE-C) that must never be marked passed from an automated result — unchanged across all three verification rounds; 04-UAT.md still shows testing paused on this item, untouched by 04-24/04-25 per their own explicit prohibitions."
human_verification:
  - test: "CP7-SAVE-C — the human continuation proof (see 04-UAT.md test 2)"
    expected: "See behavior_unverified_items above."
    why_human: "Real emulator + real commercial title + human judgment; not synthesizable in this environment; by design per D-68."
---

# Phase 4: Persistent Save Continuity Verification Report

**Phase Goal:** A player can keep one adapter-proven persistent save safe across offline work, clean-Mac restore, export, and divergent-device conflicts without losing either version.
**Verified:** 2026-09-06T05:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap-closure round 2 (plans 04-24, 04-25), superseding the prior 4/5 verification whose one remaining gap (criterion 4's "deterministic" word) is now closed.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | After the adapter proves a safe flush, the Mac captures its declared persistent-save artifact and queues it locally while the server is unavailable. | ✓ VERIFIED | Unchanged from the prior round — not touched by 04-24/04-25 (neither plan modifies any Mac capture/CAS file). Quick regression check: `SaveSessionRecovery.swift` still holds the required `CASManager` and commits via `SaveCaptureBytesCommitter`; `git diff --stat` for 04-24/04-25 confirms zero overlap with this surface. |
| 2 | A user can see whether each save revision is local-only, queued, uploaded, current, restored, or conflicted rather than being shown a misleading generic sync status. | ✓ VERIFIED | Unchanged from the prior round — `SaveHistorySessionBuilder` wiring and `SaveRollup`'s production caller are untouched by this round's two plans (confirmed: neither plan's `files_modified` list touches `SaveHistorySheet.swift`, `GameRowView.swift`, `LibraryShellView.swift`, or `PlaysteadApp.swift`'s rollup call). |
| 3 | On a clean paired Mac, a user can restore a compatible checksummed save revision and continue the game. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (file half ✓ VERIFIED) | Unchanged from all prior rounds. The file-level byte-identical restore proof stands. The in-game continuation half (CP7-SAVE-C) remains a designed human-only checkpoint per D-68 — both 04-24 and 04-25 explicitly prohibited touching CP7-SAVE-C or 04-UAT.md, and `git log` for both plans confirms neither file was touched. |
| 4 | A user can export exact original game bytes and persistent-save revisions into deterministic ordinary folders with a readable hash manifest, then verify the exported bytes and revision evidence. | ✓ VERIFIED | **Gap closed.** Confirmed directly against source in this pass: `saves.ex:411` (`get_history/2`) and `branches.ex:45` (`heads/2`, `base_query`) both now read `order_by: [asc: r.recorded_at, asc: r.id]`. `saves_plan.ex`'s `plan/2` now sorts via `Enum.sort(&order_key_lte?/2)`, a comparator that falls back to `a_id <= b_id` on a `recorded_at` tie — confirmed by direct read of lines 60-105. The falsifying test (`round_trip_test.exs:483`, "two revisions sharing one recorded_at keep identical seq and filenames across two independent exports (D-59)") constructs a real microsecond tie via `Repo.update_all`, exports twice into distinct targets, and asserts identical filenames plus a stable id-to-seq mapping. Re-run independently in this verification pass: `PORT=4099 MIX_ENV=test mix test test/playstead/export/round_trip_test.exs test/playstead/saves_test.exs test/playstead/saves_branches_test.exs test/playstead/export/saves_plan_test.exs` → **53 tests, 0 failures**. The SUMMARY additionally records the mandatory pre-fix red (3 failures, each for the expected reason — unstable order under the unfixed single-key sort) which a fresh code review (04-REVIEW-gaps2.md) independently re-traced against the actual diff and confirmed is a genuine, not vacuous, total order (Postgres `uuid` byte-comparison of the canonical-lowercase form is order-equivalent to the pure Elixir string comparator). |
| 5 | When two devices save from the same base revision, both revisions remain available with device, time, and play context; the user can inspect, choose, export, and resolve either side without silent last-write-wins. | ✓ VERIFIED | **Flagged client-side race closed.** Confirmed directly against `SaveOutboxDrainTrigger.swift:41-73` in this pass: the predecessor read (`let previous = _lastTask`), `Task` construction, `_drainCount` increment, and `_lastTask` replacement now all sit inside one `lock.lock()`/`lock.unlock()` pair — the intermediate unlock/re-lock the prior round's gap depended on is gone. The new racing test (`testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass`) releases two threads into `fire()` simultaneously via a `DispatchSemaphore` barrier across 200 rounds and asserts `maxInFlight == 1` and `totalSent == rounds`. The SUMMARY records the mandatory pre-fix red (218 sends across 200 rounds — 18 genuine duplicates — with the reverted two-section form) and a source-level gate (exactly one `lock.lock()` in the extracted `fire()` body) that also flips red on revert. A fresh code review (04-REVIEW-gaps2.md) independently traced the closure capture and confirmed `Task{}`'s initializer only enqueues a job (never runs synchronously), so building it inside the lock introduces no reentrancy or deadlock risk. Task 2's audit of every lock-guarded type in `Sync/`+`Saves/` found the defect existed in exactly one place, now fixed; the sibling `OutboxDrainTrigger` (actor-isolated worker) and `SaveUploadLane` (itself an actor) are confirmed structurally immune. Export-either-side still inherits truth 4's fix; resolve still reaches the server via the three trigger classes wired in 04-23, now genuinely single-laned. |

**Score:** 4/5 truths verified; the fifth (truth 3) is present and file-verified but its in-game continuation half is, by design (D-68/CP7-SAVE-C), never machine-verifiable — it routes to human verification rather than counting as a failure.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-server/lib/playstead/saves.ex` (`get_history/2`) | Total-order revision query | ✓ VERIFIED | `order_by: [asc: r.recorded_at, asc: r.id]` confirmed at line 411; doc comment updated to state the total order and D-15 rationale |
| `playstead-server/lib/playstead/saves/branches.ex` (`heads/2`) | Total-order head query | ✓ VERIFIED | Same two-key `order_by` confirmed on `base_query`; `user_id` scoping unchanged (grep count identical to pre-change per SUMMARY) |
| `playstead-server/lib/playstead/export/saves_plan.ex` (`plan/2`) | Input-order-independent pure sort | ✓ VERIFIED | `order_key_lte?/2` comparator over `{recorded_at, id}` confirmed at lines 96-105; module purity intact (no `Repo`/`Playstead.Saves`/`File.`/`DateTime.utc_now` call, confirmed by grep) |
| `playstead-server/test/playstead/export/round_trip_test.exs` | Falsifying tie regression test | ✓ VERIFIED | Test present at line 483; re-run in this pass, passes; SUMMARY records demonstrated pre-fix red |
| `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift` | Single-critical-section `fire()` | ✓ VERIFIED | Confirmed by direct read: one `lock.lock()`/`lock.unlock()` pair spans predecessor read through `_lastTask` replacement (lines 47-73) |
| `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift` | Genuine multi-thread racing test | ✓ VERIFIED | `testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass` confirmed present (line 196); SUMMARY records demonstrated pre-fix red (218/200 sends) and post-fix green |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `Saves.get_history/2` / `Branches.heads/2` | Export `seq`/filename assignment | `recorded_at, id`-ordered list → `SavesPlan.plan/2`'s `Enum.sort(&order_key_lte?/2)` → `Enum.with_index` | ✓ WIRED, DETERMINISTIC | Confirmed by direct source read; both the DB-side and pure-planner orderings now agree on a total order, closing the prior round's `✗ NOT DETERMINISTIC UNDER TIE` finding |
| `SaveConflictResolver` (`chooseSide`/`keepBoth`) | `SaveOutbox.enqueue` → `SaveOutboxDrainTrigger.fire()` → server | `onEnqueue` closure + reachability-regained + scene-active triggers | ✓ WIRED, SINGLE-LANED | Wiring unchanged from 04-23; the trigger's own serialization guarantee is now genuinely true rather than merely documented, closing the prior round's `⚠️ WIRED BUT DEFECTIVE` finding |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `Export.plan/2` saves output | `saves_plan` per set | `Export.load_save_revisions/2` → `Saves.list_lines/2` + `Saves.get_history/2` (now total-ordered) | Yes, deterministically | ✓ FLOWING (defect closed) |
| `SaveOutbox` drain | outbound HTTP request | `SaveOutboxDrainTrigger.fire()` → `SaveOutbox.drainOnce(apiClient:)`, now single-critical-section serialized | Yes, exactly-once per trigger | ✓ FLOWING (defect closed) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Revision ordering has a total-order tiebreaker | `grep -n "asc: r.recorded_at, asc: r.id" playstead-server/lib/playstead/saves.ex playstead-server/lib/playstead/saves/branches.ex` | one match in each file | ✓ CONFIRMS FIX |
| `SavesPlan.plan/2` no longer relies on stable-sort input order | `grep -c "Enum.sort_by(& &1.recorded_at, DateTime)" playstead-server/lib/playstead/export/saves_plan.ex` | 0 (single-key sort removed) | ✓ CONFIRMS FIX |
| Targeted determinism test suite (independently re-run, not just trusted from SUMMARY) | `PORT=4099 MIX_ENV=test mix test test/playstead/export/round_trip_test.exs test/playstead/saves_test.exs test/playstead/saves_branches_test.exs test/playstead/export/saves_plan_test.exs` | `53 tests, 0 failures` | ✓ PASS |
| `SaveOutboxDrainTrigger.fire()` has one critical section | Read `SaveOutboxDrainTrigger.swift:47-73` in full | single `lock.lock()`/`lock.unlock()` pair spans predecessor read through `_lastTask` write | ✓ CONFIRMS FIX |
| New racing test exists and is not the old synchronous-double-call shape | `grep -n "testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass\|DispatchSemaphore\|DispatchGroup" playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift` | test present, uses explicit barrier primitives | ✓ CONFIRMS FIX (not re-run — requires xcodebuild, taken from SUMMARY's recorded green run plus independent code-review trace) |
| WINDOWS.md untouched by either gap-closure plan (as both plans declared) | `git log --oneline -3 -- .planning/WINDOWS.md` | last write is 04-23's `4dc9c60`; no 04-24/04-25 commit present | ✓ CONFIRMS — no shared-file conflict introduced |

**Note on test-suite reliability (carried forward from this run's context, not dismissed):** the full server suite has shown non-deterministic total test counts and one late-stage ETS-crash-after-summary pattern in gate runs outside this verification's own targeted re-run. Because of this, this verification did NOT rely on a full-suite "N tests, 0 failures" summary as its evidence for criterion 4. Instead it (a) independently re-ran only the four files the fix touches — a small, fast, fully-observed run (53/53, 0 failures, tail output inspected directly, no truncation possible at this size) — and (b) cross-checked every changed line of source directly. The Mac-side racing test could not be independently re-run in this session (requires an `xcodebuild` build cycle) and is accepted on the strength of (a) the SUMMARY's recorded, specific, falsifying red/green results (218/200 sends pre-fix, exact assertion failure text quoted) and (b) a fresh, independently-argued code review that traced the actual closure-capture semantics rather than trusting the SUMMARY's prose. This is disclosed rather than silently smoothed over.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| SAVE-01 | 04-01, 04-02, 04-03, 04-06, 04-12, 04-15…04-20, 04-23 | Capture + queue locally while server unavailable | ✓ SATISFIED | Truth 1 above, unchanged this round |
| SAVE-02 | 04-04, 04-09, 04-10, 04-11, 04-12, 04-16…04-19, 04-22 | Per-revision durability/position/provenance/lineage visibility | ✓ SATISFIED | Truth 2 above, unchanged this round |
| SAVE-03 | 04-02, 04-07, 04-13, 04-14, 04-18, 04-20, 04-23 | Restore compatible revision on clean Mac, continue game | ? NEEDS HUMAN (file half satisfied) | Truth 3 above, unchanged — CP7-SAVE-C |
| SAVE-04 | 04-05, 04-10, 04-11, 04-15, 04-19, 04-21, 04-23, 04-24, 04-25 | Divergence: retain both, inspect/choose/export/resolve, no silent LWW | ✓ SATISFIED | Truth 5 above — client-side race closed by 04-25; export-either-side determinism closed by 04-24 |
| PORT-01 | 04-08, 04-10, 04-21, 04-24 | Export game bytes + save revisions + readable manifest, verify, deterministically | ✓ SATISFIED | Truth 4 above — the "deterministic" word is now earned, closed by 04-24 |

**REQUIREMENTS.md discrepancy (documentation staleness, not a code gap):** `.planning/REQUIREMENTS.md` currently marks SAVE-01, SAVE-02, and SAVE-03 as unchecked `[ ]` with status "Gaps Found" in its tracking table (lines 59-61, 147-149), while SAVE-04 and PORT-01 are checked `[x]`/"Complete" (updated by the 04-24/04-25 SUMMARY commits). This is stale: commit `3292a17` ("revert premature Complete requirements after gaps found") reverted all five checkmarks together before the round-1 gap-closure plans (04-21/22/23) landed, and nothing since has re-marked SAVE-01/02/03 even though the prior verification round (04-VERIFICATION.md, 4/5 score) already scored truths 1 and 2 as fully SATISFIED and truth 3 as satisfied-except-for-its-designed-human-checkpoint. This verification's own source inspection confirms SAVE-01/02's supporting code is intact and untouched by any regression this round. **Recommendation:** update REQUIREMENTS.md's checkboxes/table for SAVE-01 and SAVE-02 to `[x]`/"Complete", and for SAVE-03 to reflect "Complete pending CP7-SAVE-C human sign-off" rather than leaving all three flagged as "Gaps Found" — a reader of REQUIREMENTS.md alone would currently and incorrectly conclude those three requirements are still broken. Not treated as a phase-blocking gap because the underlying code was independently confirmed against the actual REQUIREMENTS.md description text (SAVE-01 and SAVE-02 as literally worded) in this and the prior verification pass — it is a doc-sync omission, not a functional failure.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `playstead-server/lib/playstead/export/saves_plan.ex` | 96-105 | `order_key_lte?/2`'s tiebreaker assumes canonical-lowercase UUID strings with no validation at the module boundary (04-REVIEW-gaps2.md WR-01) | ⚠️ Warning (latent, not currently triggered) | The sole production caller (`Export.load_save_revisions/2`) always supplies `id` through `Ecto.UUID`, which is always canonical lowercase — confirmed by direct check of `export.ex:119` and the revision struct's field typing. No current code path can trigger the divergence this warning describes. Recorded for future-caller awareness, not a phase-blocking defect. |
| `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift` | 57-72 | `_lastTask` retains an unbroken chain of completed predecessor `Task` references under sustained high-frequency `fire()` calls (04-REVIEW-gaps2.md IN-02) | ℹ️ Info | Explicitly not a leak — a documented, accepted design tradeoff of the "await your predecessor" chaining scheme; reviewer flagged as optional. |
| `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift` | 196-240 | New racing test never asserts `trigger.drainCount` alongside `maxInFlight`/`totalSent` (04-REVIEW-gaps2.md IN-01) | ℹ️ Info | Not evidence of a live defect (the counter was already lock-protected pre-fix); a coverage gap for a future refactor, not this round's fix. |

No `TBD`/`FIXME`/`XXX` debt markers found in either file modified by 04-24 or 04-25 (checked directly by grep against each plan's `files_modified` list, and confirmed absent in the diffs reviewed above).

### Human Verification Required

### 1. CP7-SAVE-C — the human continuation proof

**Test:** Perform 04-13-PLAN.md's Task 3 five steps against a real commercial GBA title through the pinned mGBA adapter, with the server running and the Mac paired.
**Expected:** The .sav file changes on a bounded cadence after an in-game save; a normal quit and a force-quit each capture a revision; restore onto a cleared save directory happens silently with no prompt; the game continues from the exact saved progress with no "save corrupt, erase?" prompt.
**Why human:** Requires a real emulator, a real commercial title, and human judgment of in-game continuity. This is 04-UAT.md's designed, disclosed, blocking-human checkpoint (D-68) — unchanged across all three verification rounds, and both gap-closure plans in this round explicitly declared it out of scope and left it untouched (confirmed via `git log`).

### Gaps Summary

Both gaps from the prior (4/5) verification round are closed and independently confirmed in this pass:

1. **Criterion 4's "deterministic" word (PORT-01)** — `Saves.get_history/2` and `Branches.heads/2` now impose a total order (`recorded_at` then `id` ascending), and `SavesPlan.plan/2`'s sort was additionally hardened (beyond the verification's literal recommendation, declared as such) to be input-order-independent. Verified by direct source read of every changed line, an independently re-run targeted test suite (53/53, 0 failures), and a fresh code review that traced the DB-vs-Elixir ordering equivalence argument rather than trusting the claim.

2. **Criterion 5's client-side TOCTOU race (SAVE-04)** — `SaveOutboxDrainTrigger.fire()`'s predecessor-read and `_lastTask`-replacement now share one critical section, closing the race that let two concurrent triggers both observe the same stale predecessor. Verified by direct source read, the SUMMARY's recorded and specific pre-fix/post-fix falsification (218 vs 200 sends), a fresh code review's independent closure-capture trace, and an audit confirming no second occurrence of the defect elsewhere in the codebase.

No new gaps were found. Three minor, non-blocking items are carried forward as **warnings/info** rather than gaps (WR-01's latent non-canonical-UUID assumption, and two info-level notes) — see Anti-Patterns above. One **documentation-staleness discrepancy** in REQUIREMENTS.md's checkbox/table state for SAVE-01/02/03 is flagged for correction but does not reflect an actual code gap (see Requirements Coverage above).

The phase goal is achieved for every criterion this environment can verify. The sole remaining item — truth 3's in-game continuation — is, by explicit design (D-68/CP7-SAVE-C), a human-only checkpoint that has never been in scope for automated verification in any round of this phase. Per the status decision tree, a non-empty human-verification section means this phase's status is `human_needed`, not `passed`, even though zero gaps remain and every other must-have is fully verified.

---

_Verified: 2026-09-06T05:00:00Z_
_Verifier: Claude (gsd-verifier)_
