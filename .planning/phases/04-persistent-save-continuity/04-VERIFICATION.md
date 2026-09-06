---
phase: 04-persistent-save-continuity
verified: 2026-09-06T00:06:49Z
status: gaps_found
score: 1/5 must-haves verified
behavior_unverified: 1
overrides_applied: 0
gaps:
  - truth: "A user can see whether each save revision is local-only, queued, uploaded, current, restored, or conflicted rather than being shown a misleading generic sync status."
    status: failed
    reason: "The only per-revision surface, SaveHistorySheet, is driven exclusively by the `sessions: [SaveHistorySession]` parameter on ReadinessSheetView. That parameter is a closure defaulted to `{ [] }` (ReadinessSheetView.swift:27) and is never passed a real implementation at any of ReadinessSheetView's two call sites (GameRowView.swift, LibraryShellView.swift). A real user opening 'Review versions...' for a non-diverged save line always sees the sheet's empty state, regardless of how much real history exists in SaveStore. The game-level rollup that was supposed to give a coarser reading of the same information, `SaveRollup.rollup(for:)` (D-36), has zero production callers anywhere in the codebase (confirmed: only self-reference in SaveRollup.swift). The only real per-game signal reaching a user is ReadinessEngine's coarse `SaveReadinessCase` (ready / local-only / two-versions) surfaced in the readiness sheet's Save row — durability-only, not the full six-state vocabulary this criterion names, and not per-revision."
    artifacts:
      - path: "playstead-mac/Playstead/Readiness/ReadinessSheetView.swift"
        issue: "saveHistorySessions closure defaults to `{ [] }` (line 27) and is never overridden at either call site"
      - path: "playstead-mac/Playstead/Saves/SaveRollup.swift"
        issue: "D-36's rollup string builder has zero callers outside its own file and test target (WINDOWS #47)"
      - path: "playstead-mac/Playstead/Saves/SaveHistorySheet.swift"
        issue: "Takes only `sessions: [SaveHistorySession]` — no fallback path renders raw SaveStore revisions when sessions is empty"
    missing:
      - "A real `saveHistorySessions` closure in AppEnvironment/GameRowView/LibraryShellView that groups SaveStore's actual revisions into SaveHistorySession values, wired to both ReadinessSheetView call sites"
      - "A production call site for SaveRollup.rollup(for:), or removal of the dead code if the readiness Save row is the intended replacement surface"
  - truth: "A user can export exact original game bytes and persistent-save revisions into deterministic ordinary folders with a readable hash manifest, then verify the exported bytes and revision evidence."
    status: failed
    reason: "Playstead.Export.to_layout_input/1 (export.ex:63-84) builds the Layout.plan/2 input map with no `:saves` key. Layout.build_saves_plan/3 (layout.ex:158-159) reads `Map.get(set, :saves, [])`, so every production export — from the game-detail export action, the console 'Export saves' control, and the divergence comparison sheet's 'Export this version...' deep link (which all route through the same Export module) — writes an empty saves slot. The full SavesPlan/Sidecar/BagitWriter pipeline (04-08) is real and unit-tested, but it never receives real Playstead.Saves revision data in production. This is PORT-01's saves half, and it is the sole reason 04-08's otherwise-complete pipeline does not satisfy the roadmap criterion."
    artifacts:
      - path: "playstead-server/lib/playstead/export.ex"
        issue: "to_layout_input/1 (lines 63-84) omits :saves; no code path anywhere in the module fetches Playstead.Saves revisions for the asset set being exported"
      - path: "playstead-server/lib/playstead/export/layout.ex"
        issue: "build_saves_plan/3 (line 158-159) silently defaults to an empty list when :saves is absent from the input map — the correct behavior for the missing-data case, but it means the empty pipeline output is indistinguishable from 'game has no saves'"
    missing:
      - "to_layout_input/1 (or its caller) must fetch the asset set's save revisions via Playstead.Saves and populate the :saves key before calling Layout.plan/2"
  - truth: "When two devices save from the same base revision, both revisions remain available with device, time, and play context; the user can inspect, choose, export, and resolve either side without silent last-write-wins."
    status: failed
    reason: "Inspect/choose/keep-both work: ConflictComparisonSheet is wired into ReadinessSheetView's 'Review versions...' remedy for a genuine unacknowledged divergence (confirmed added in commit c223218 / plan 04-16, which postdates and effectively resolves the ledger's WINDOWS #32), and the append-only SaveConflictResolver logic is unit-tested and works fully offline. But two of the four verbs this criterion requires are broken: (1) 'Export this version...' deep-links to the same server-side Export machinery that unconditionally produces an empty saves slot (the PORT-01 defect above), so exporting either side of a divergence produces a folder with no save bytes in it; (2) the resolution's durable local record has no path to the server — `saveOutbox` is constructed once in AppEnvironment.swift but is never drained by any trigger (no `saveOutbox.drainOnce()` call site exists anywhere, confirmed by source grep), unlike SaveUploadLane and the general Outbox, both of which are drained on real triggers. A resolved fork is therefore recorded locally and may never reach the server, which is a materially different outcome than the criterion's promise that resolution converges across devices."
    artifacts:
      - path: "playstead-mac/Playstead/App/PlaysteadApp.swift"
        issue: "saveOutbox is constructed (line 466) but no drain trigger fires SaveOutbox.drainOnce() anywhere in this file or elsewhere in production code (contrast with saveUploadLane.drainOnce() at line 542, which is wired to a real trigger)"
      - path: "playstead-server/lib/playstead/export.ex"
        issue: "Same to_layout_input/1 gap as above — the comparison sheet's export action inherits it"
    missing:
      - "A drain trigger for SaveOutbox equivalent to the one SaveUploadLane already has"
      - "The to_layout_input/1 fix listed above (shared root cause)"
deferred:
  - truth: "Two mGBA instances launching against the same 32 KB .sav are prevented from corrupting it (D-65)"
    addressed_in: "Already shipped in this phase (04-02, AdapterLaunchMutex) — not deferred; listed here only to confirm it is out of scope for this report's gaps, not silently dropped."
behavior_unverified_items:
  - truth: "On a clean paired Mac, a user can restore a compatible checksummed save revision and continue the game (the in-game continuation half)."
    test: "Perform the five steps in 04-13-PLAN.md's Task 3 <how-to-verify> against a real commercial GBA title through the pinned mGBA adapter: observe the .sav file changing on a bounded cadence after an in-game save, a normal quit and a force-quit each capturing a revision, silent auto-restore onto a cleared save directory with no prompt, and the game continuing from the exact saved progress with no in-game 'save corrupt, erase?' prompt."
    expected: "In-game progress after restore matches exactly what was saved before, and mGBA accepts the restored bytes as valid save data."
    why_human: "Requires a real emulator, a real commercial GBA title, and a human judging in-game continuity. This is a designed checkpoint (D-68, CP7-SAVE-C) that must never be marked passed from an automated result — the file-level automated proxy (SaveRestoreProofTests, passing) proves only that captured bytes round-trip byte-identically to disk, not that the emulator or the game accept them as valid progress."
human_verification:
  - test: "CP7-SAVE-C — the human continuation proof (see 04-UAT.md test 2)"
    expected: "See behavior_unverified_items above."
    why_human: "Real emulator + real commercial title + human judgment; not synthesizable in this environment; by design per D-68."
---

# Phase 4: Persistent Save Continuity Verification Report

**Phase Goal:** A player can keep one adapter-proven persistent save safe across offline work, clean-Mac restore, export, and divergent-device conflicts without losing either version.
**Verified:** 2026-09-06T00:06:49Z
**Status:** gaps_found
**Re-verification:** No — initial verification (Phase 4 has never had a VERIFICATION.md; confirmed by `v1.0-MILESTONE-AUDIT.md`'s "unverified_phases" entry and absence of a prior `04-*-VERIFICATION.md` in the phase directory).

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | After the adapter proves a safe flush, the Mac captures its declared persistent-save artifact and queues it locally while the server is unavailable. | ✓ VERIFIED | `SaveSessionCoordinator`/`SaveCapturePoller`/`SaveUploadLane` are all constructed and reachable from the real Play path (`PlayPathSaveWiringTests`, 12 tests; WINDOWS #44/#45/#46 fixed by 04-19 commits `3691ec3`/`fb6ad53`). Capture bytes are committed into the CAS before the revision row is inserted (04-20, `de3aec1`), so a locally-captured revision reads `bytesLocal: true` (`LaunchSaveContextBuilderTests.testASaveCapturedOnThisMacIsReportedAsBytesLocalWithNoServerInvolvement`). Note: the crash-recovery path (`SaveSessionRecovery.replay`) does *not* share this CAS-commit fix — it holds no `CASManager` and its recovered revisions read `bytesLocal: false` (WINDOWS #52, open). This is a genuine, disclosed gap in the crash-recovery variant of this truth, but the primary live-session capture-and-queue path is proven. Recorded here rather than silently absorbed. |
| 2 | A user can see whether each save revision is local-only, queued, uploaded, current, restored, or conflicted rather than being shown a misleading generic sync status. | ✗ FAILED | See gaps. `SaveHistorySheet` — the only surface built to show per-revision state — always renders empty in production because `ReadinessSheetView.saveHistorySessions` defaults to `{ [] }` and is never overridden. `SaveRollup` (D-36's coarser game-level string) has zero production callers. Only a coarse `SaveReadinessCase` (ready / local-only / two-versions) reaches the user via the readiness sheet's Save row — real, but not the per-revision six-state vocabulary this criterion names. |
| 3 | On a clean paired Mac, a user can restore a compatible checksummed save revision and continue the game. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (file half ✓ VERIFIED) | The automated proxy `SaveRestoreProofTests.testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir` passes and proves byte-identical restore through the real `SavePlanExecutor` the launch path uses (executed locally this session per 04-VALIDATION.md, 1 test, 0 failures). The in-game continuation half (CP7-SAVE-C) is a designed human-only checkpoint per D-68 and remains genuinely blocked on human execution — this is expected, not a defect, and is routed to human verification rather than scored as failed. Separately, WINDOWS #52 means a crash-recovered revision specifically would fail the "zero-network restore" half of this same criterion, since its bytes never entered the CAS. |
| 4 | A user can export exact original game bytes and persistent-save revisions into deterministic ordinary folders with a readable hash manifest, then verify the exported bytes and revision evidence. | ✗ FAILED | See gaps. `Export.to_layout_input/1` never populates `:saves`; every real export writes an empty saves slot regardless of how much save history exists. The game-bytes half (Phase 2) is unaffected and still works; only the saves half of PORT-01 fails. |
| 5 | When two devices save from the same base revision, both revisions remain available with device, time, and play context; the user can inspect, choose, export, and resolve either side without silent last-write-wins. | ✗ FAILED | See gaps. Inspect/choose/keep-both are real and wired (ConflictComparisonSheet reachable via ReadinessSheetView's "Review versions..." remedy since plan 04-16, commit `c223218`; append-only resolution logic unit-tested and works offline). Export-either-side inherits the criterion-4 defect (empty saves slot). Resolve does not reliably reach the server: `saveOutbox` has no drain trigger anywhere in production code. |

**Score:** 1/5 truths verified (1 present, behavior-unverified — truth 3's human continuation half, by design per D-68)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift` | Owns capture lifecycle, commits to CAS | ✓ VERIFIED | Wired, tested, CAS commit present (04-20) |
| `playstead-mac/Playstead/Saves/SaveSessionRecovery.swift` | Crash-recovery replay, same durability guarantee as live path | ⚠️ ORPHANED GUARANTEE | Constructed in production (`AppEnvironment.recoverAbandonedSaveSessionsAtLaunch`), but holds no `CASManager` — inserts a revision row without committing bytes (WINDOWS #52) |
| `playstead-mac/Playstead/Saves/SaveUploadLane.swift` | Dedicated save upload lane, drained ahead of curation outbox | ✓ VERIFIED (wired) | Constructed and drained on real triggers (04-19); end-to-end success against a live server unproven (no live-server environment available — recorded as Manual-Only in 04-VALIDATION.md, not a defect in this session) |
| `playstead-mac/Playstead/Saves/SaveRollup.swift` | Game-level rollup string (D-36) | ✗ STUB (orphaned) | Zero production callers (WINDOWS #47) |
| `playstead-mac/Playstead/Saves/SaveHistorySheet.swift` | Per-revision session-grouped history | ⚠️ ORPHANED DATA | View itself renders correctly against test fixtures; its production data source (`saveHistorySessions`) is never wired, so it always shows the empty state for real users (WINDOWS #43) |
| `playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift` | Divergence comparison sheet | ✓ VERIFIED (wired) | Reachable from ReadinessSheetView's "Review versions..." remedy since 04-16 (`c223218`) — this resolves the ledger's still-open WINDOWS #32, which predates that commit |
| `playstead-server/lib/playstead/export/saves_plan.ex` + `sidecar.ex` + `bagit_writer.ex` | Real save-revision export pipeline | ⚠️ HOLLOW | Built and unit-tested against synthetic data; never receives real revision data because `Export.to_layout_input/1` omits `:saves` (WINDOWS #30 / PORT-01) |
| `playstead-mac/Playstead/App/PlaysteadApp.swift` (`saveOutbox`) | Durable local record of divergence resolution, drained to server | ⚠️ ORPHANED | Constructed but never drained (no `saveOutbox.drainOnce()` call site found; contrast with `saveUploadLane.drainOnce()`, which is wired) — WINDOWS #42 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `SaveSessionCoordinator` (capture) | `SaveStore` + CAS | `commitCaptureBytes` | ✓ WIRED | Confirmed by 04-20's `de3aec1` and passing `SaveSessionCoordinatorTests` CAS tests |
| `GameRowView.play()` | `LaunchSavePlanner`/`SavePlanExecutor` | `executeSavePlan` closure | ✓ WIRED | `PlayPathSaveWiringTests` (12 tests); WINDOWS #37 fixed |
| `ReadinessSheetView` (Save row remedy) | `ConflictComparisonSheet` | `.reviewSaveVersions` remedy branch | ✓ WIRED | Confirmed directly in source (lines 177-185); reachable from a real "Review versions..." action when a genuine unacknowledged divergence exists |
| `ReadinessSheetView` (Save row remedy) | `SaveHistorySheet` | `saveHistorySessions()` closure | ✗ NOT_WIRED | Closure defaults to `{ [] }`, never overridden at either call site (`GameRowView.swift`, `LibraryShellView.swift`) |
| `Export.to_layout_input/1` | `Playstead.Saves` (revision fetch) | direct call | ✗ NOT_WIRED | No call into `Playstead.Saves` exists anywhere in `export.ex`; `:saves` key is simply absent from the map |
| `ConflictComparisonSheet` "Export this version..." | Server export pipeline | `openConsoleSavesExport` deep link | ⚠️ PARTIAL | The deep link itself fires correctly, but the pipeline it reaches inherits the empty-`:saves` defect above |
| Divergence resolution (`SaveConflictResolver`) | Server (`saveOutbox` drain) | `OutboxDrainTrigger`-equivalent | ✗ NOT_WIRED | `saveOutbox` constructed, never drained (WINDOWS #42) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `SaveHistorySheet` | `sessions` | `ReadinessSheetView.saveHistorySessions()` | No — default closure returns `[]`, never overridden | ✗ HOLLOW_PROP |
| `Export.plan/2` saves output | `saves_plan` per set | `Map.get(set, :saves, [])` in `layout.ex` | No — `set` map never carries `:saves` | ✗ DISCONNECTED |
| Readiness Save row | `SaveReadinessCase` | `AppEnvironment.saveReadinessCase(for:)` | Yes, for all cases except `.serverHasNewer` (WINDOWS #41, a narrower and separately-tracked gap not blocking this verification) | ✓ FLOWING (mostly) |
| Divergence card attention rung | conflicted state | Saves-owned attention source union | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| SaveRollup has no production caller | `grep -rn "SaveRollup\." playstead-mac/Playstead \| grep -v Tests` | no matches outside `SaveRollup.swift` itself | ✓ CONFIRMS FAILURE (matches WINDOWS #47) |
| saveHistorySessions never overridden | `grep -rn "saveHistorySessions:" playstead-mac/Playstead` | only the default-parameter declaration | ✓ CONFIRMS FAILURE (matches WINDOWS #43) |
| Export never supplies :saves | Read `export.ex:63-84` and `layout.ex:154-165` | `to_layout_input/1` has no `:saves` key; `build_saves_plan/3` falls back to `[]` | ✓ CONFIRMS FAILURE (matches WINDOWS #30) |
| saveOutbox drain trigger | `grep -n "saveOutbox\." PlaysteadApp.swift` | no output | ✓ CONFIRMS FAILURE (matches WINDOWS #42) |
| ConflictComparisonSheet reachability | `grep -n "ConflictComparisonSheet(" playstead-mac/Playstead/Readiness/ReadinessSheetView.swift` + `git log` on that file | wired in commit `c223218` (plan 04-16), later than WINDOWS #32's 2026-09-04 recording | ⚠️ LEDGER STALE — code confirms this is actually resolved |
| SaveSessionRecovery holds no CASManager | Read `SaveSessionRecovery.swift` in full | confirmed: no `CASManager` property, `insertRevision` called with no CAS commit | ✓ CONFIRMS FAILURE (matches WINDOWS #52) |

Full server (`mix test`) and Mac (Unit/Rendering) suites were not re-run in this session per the task's explicit instruction to take the already-established green results (545/545 Mac Unit, 44/46 Mac Rendering + 2 skipped, 1015/1015 Elixir, clean `reachability-sweep.sh --strict`) as given. All findings above are from direct source inspection, not test execution, which is the correct instrument for wiring/data-flow gaps that a passing unit-test-against-a-fixture cannot see.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| SAVE-01 | 04-01, 04-02, 04-03, 04-06, 04-12, 04-15…04-20 | Capture + queue locally while server unavailable | ✓ SATISFIED (primary path) / ⚠️ partial on crash-recovery variant | Truth 1 above |
| SAVE-02 | 04-04, 04-09, 04-10, 04-11, 04-12, 04-16…04-19 | Per-revision durability/position/provenance/lineage visibility | ✗ BLOCKED | Truth 2 above — REQUIREMENTS.md marks this "Complete"; that claim does not hold against production wiring |
| SAVE-03 | 04-02, 04-07, 04-13, 04-14, 04-18 | Restore compatible revision on clean Mac, continue game | ? NEEDS HUMAN (file half satisfied) | Truth 3 above |
| SAVE-04 | 04-05, 04-10, 04-11, 04-15, 04-19 | Divergence: retain both, inspect/choose/export/resolve, no silent LWW | ✗ BLOCKED | Truth 5 above — export and resolve-to-server verbs broken |
| PORT-01 | 04-08, 04-10 (saves half only; game-bytes half shipped Phase 2) | Export game bytes + save revisions + readable manifest, verify | ✗ BLOCKED | Truth 4 above — game-bytes half still fine; saves half writes empty data in every real export |

**REQUIREMENTS.md currently marks all five of the above "Complete."** That marking does not hold against the codebase as verified in this report for SAVE-02, SAVE-04, and PORT-01, and is unproven (not falsified) for SAVE-01's crash-recovery variant and SAVE-03's human continuation half.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `playstead-mac/Playstead/Readiness/ReadinessSheetView.swift` | 27 | Default closure `{ [] }` masquerading as a wired data source | 🛑 Blocker | Directly causes truth 2's failure |
| `playstead-server/lib/playstead/export.ex` | 63-84 | Missing key rather than an explicit stub value — silently produces valid-shaped-but-empty output | 🛑 Blocker | Directly causes truth 4 and part of truth 5's failure |
| `playstead-mac/Playstead/Saves/SaveRollup.swift` | (whole file) | Fully-built, fully-tested, zero-caller dead code | ⚠️ Warning | Indicates the intended surfacing mechanism for D-36 was superseded by ReadinessEngine without SaveRollup being removed or wired — leaves ambiguity about which is the real surface |
| `playstead-mac/Playstead/App/PlaysteadApp.swift` | 466 (construction), no drain call site | Constructed-but-never-driven collaborator | ⚠️ Warning | Directly causes part of truth 5's failure |

No `TBD`/`FIXME`/`XXX` debt markers found in any file touched by this phase's commits (checked against the full file list from `git log --name-only` over `playstead-mac/Playstead/Saves`, `playstead-server/lib/playstead/export`, `playstead-server/lib/playstead/saves*`, `playstead-mac/Playstead/Readiness`).

### Human Verification Required

### 1. CP7-SAVE-C — the human continuation proof

**Test:** Perform 04-13-PLAN.md's Task 3 five steps against a real commercial GBA title through the pinned mGBA adapter, with the server running and the Mac paired.
**Expected:** The .sav file changes on a bounded cadence after an in-game save; a normal quit and a force-quit each capture a revision; restore onto a cleared save directory happens silently with no prompt; the game continues from the exact saved progress with no "save corrupt, erase?" prompt.
**Why human:** Requires a real emulator, a real commercial title, and human judgment of in-game continuity. This is 04-UAT.md's designed, disclosed, blocking-human checkpoint (D-68) — it is not a gap introduced by this verification pass, and this report does not fabricate a pass/fail for it.

### Gaps Summary

Three of the five roadmap success criteria fail on direct source inspection, all traceable to two root causes plus one narrower one, all already disclosed in `WINDOWS.md` prior to this verification:

1. **The saves half of every export is empty in production** (`Export.to_layout_input/1` never supplies `:saves`, WINDOWS #30). This single defect independently fails criterion 4 (export) and half of criterion 5 (export either side of a divergence), because the divergence comparison sheet's export action deep-links into the same broken pipeline.
2. **Per-revision history never renders real data** (`saveHistorySessions` defaults to an unwired empty closure, WINDOWS #43; its intended coarser sibling `SaveRollup` has zero callers, WINDOWS #47). This fails criterion 2 outright — a real user cannot see per-revision state, only a coarse newest-revision durability reading via the readiness Save row.
3. **Divergence resolution has no path back to the server** (`saveOutbox` is constructed but never drained, WINDOWS #42). This fails the remaining "resolve" half of criterion 5 for cross-device convergence.

A fourth, narrower defect — crash-recovered captures never enter the CAS (`SaveSessionRecovery` holds no `CASManager`, WINDOWS #52) — does not fail criterion 1 (the live-session capture-and-queue path is proven), but does compromise criterion 3's zero-network restore guarantee for the specific case of a revision recovered from a crash rather than captured during a live session.

None of these are test-coverage gaps — every one is a demonstrable, direct-from-source wiring or data-supply defect, confirmed independently by this verification (not merely inherited from WINDOWS.md, though all four were already recorded there). One item in WINDOWS.md (#32, ConflictComparisonSheet unreachable) was found to be **stale** — plan 04-16's commit `c223218` wired it into ReadinessSheetView after WINDOWS #32 was recorded, and this verification confirms that specific concern is now resolved; the ledger should be updated accordingly, though it is not this report's place to edit it.

Twenty plans, 545/545 Mac Unit tests, 1015/1015 Elixir tests, and a clean strict reachability sweep are real and load-bearing evidence that the underlying mechanisms (capture, CAS, lineage, compatibility gate, export layout, conflict model) are each independently sound. The phase's failure mode throughout is consistent: mechanisms are built and tested against fixtures or synthetic data, but the last connection to real production data (a real asset set's saves, a real SaveStore's grouped sessions, a real outbox drain trigger) was left for a plan that was never written. This is exactly the "task completion ≠ goal achievement" pattern this verification exists to catch.

---

_Verified: 2026-09-06T00:06:49Z_
_Verifier: Claude (gsd-verifier)_
