---
phase: 04-persistent-save-continuity
verified: 2026-09-06T03:30:00Z
status: gaps_found
score: 4/5 must-haves verified
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 1/5
  gaps_closed:
    - "A user can see whether each save revision is local-only, queued, uploaded, current, restored, or conflicted (criterion 2) — SaveHistorySessionBuilder wired at both ReadinessSheetView call sites (04-22), SaveRollup.rollup(for:) given a production caller and removed from the reachability allowlist (04-22)."
    - "A user can export exact original game bytes and persistent-save revisions into deterministic ordinary folders with a readable hash manifest (criterion 4, wiring half) — Export.load_save_revisions/2 now supplies real Playstead.Saves data to all three production layout builders (04-21)."
    - "When two devices save from the same base revision... the user can inspect, choose, export, and resolve either side (criterion 5) — export inherits the 04-21 fix; ConflictComparisonSheet reachability confirmed still wired; SaveOutboxDrainTrigger now drains a resolved divergence to the server on all three trigger classes (04-23)."
    - "Crash-recovered captures enter the CAS (WINDOWS #52, bears on criterion 3's zero-network restore guarantee) — SaveCaptureBytesCommitter extracted and shared by SaveSessionRecovery.replay (04-23)."
  gaps_remaining:
    - "Criterion 4's explicit 'deterministic' guarantee is falsified under a demonstrated (not hypothetical) condition: saves.ex#get_history/2 and saves/branches.ex#heads/2 order revisions by `recorded_at` alone, with no tiebreaker. Two revisions recorded at the same microsecond — plausible exactly in the concurrent-device scenario criterion 5 is about — can be assigned a different `seq`/filename on a re-export, silently renaming a previously-shipped file. This directly contradicts 04-21's own must-have truth #5 ('a revision's seq is never renumbered or reused') and D-59. Found by fresh code review (04-REVIEW-gaps-server.md CR-01), confirmed directly against source in this verification pass (saves.ex:411, branches.ex:45 both read `order_by: [asc: r.recorded_at]` with no secondary key)."
  regressions: []
gaps:
  - truth: "A user can export exact original game bytes and persistent-save revisions into deterministic ordinary folders with a readable hash manifest, then verify the exported bytes and revision evidence."
    status: partial
    reason: "The wiring defect that fully failed this criterion last round (empty :saves slot) is genuinely fixed — Export.load_save_revisions/2 supplies real revision data to every production layout builder, and this is unit/integration tested against real written bytes (04-21). But the criterion's explicit word 'deterministic' is not fully earned: revision ordering has no tiebreaker beyond `recorded_at`, so two revisions committed within the same microsecond (plausible in exactly the concurrent-device-divergence scenario this phase exists to handle) can receive a different seq/filename across two exports of the same underlying data. Nothing detects or logs the tie; the manifest still hashes correctly so Verifier.verify/1 reports success even though a previously-shipped file's name silently changed. This is a real, demonstrated gap (not a hypothetical edge case dismissed by adversarial paranoia) — confirmed directly against saves.ex:411 and branches.ex:45 in this verification pass, both lacking a secondary sort key."
    artifacts:
      - path: "playstead-server/lib/playstead/saves.ex"
        issue: "get_history/2's revisions query (line 411) orders `[asc: r.recorded_at]` only — Postgres gives no ordering guarantee across two separate executions for tied values"
      - path: "playstead-server/lib/playstead/saves/branches.ex"
        issue: "heads/2's base_query (line 45) has the same single-key order_by, feeding the same non-deterministic tie into head resolution"
    missing:
      - "A secondary, stable sort key (e.g. `order_by: [asc: r.recorded_at, asc: r.id]`) on both queries, plus a regression test that commits two revisions with an identical `recorded_at` and asserts their exported seq/filename is stable across two export runs"
deferred: []
behavior_unverified_items:
  - truth: "On a clean paired Mac, a user can restore a compatible checksummed save revision and continue the game (the in-game continuation half)."
    test: "Perform the five steps in 04-13-PLAN.md's Task 3 <how-to-verify> against a real commercial GBA title through the pinned mGBA adapter: observe the .sav file changing on a bounded cadence after an in-game save, a normal quit and a force-quit each capturing a revision, silent auto-restore onto a cleared save directory with no prompt, and the game continuing from the exact saved progress with no in-game 'save corrupt, erase?' prompt."
    expected: "In-game progress after restore matches exactly what was saved before, and mGBA accepts the restored bytes as valid save data."
    why_human: "Requires a real emulator, a real commercial GBA title, and a human judging in-game continuity. This is a designed checkpoint (D-68, CP7-SAVE-C) that must never be marked passed from an automated result — unchanged from the prior verification round; 04-UAT.md still shows testing paused on this item."
human_verification:
  - test: "CP7-SAVE-C — the human continuation proof (see 04-UAT.md test 2)"
    expected: "See behavior_unverified_items above."
    why_human: "Real emulator + real commercial title + human judgment; not synthesizable in this environment; by design per D-68."
---

# Phase 4: Persistent Save Continuity Verification Report

**Phase Goal:** A player can keep one adapter-proven persistent save safe across offline work, clean-Mac restore, export, and divergent-device conflicts without losing either version.
**Verified:** 2026-09-06T03:30:00Z
**Status:** gaps_found
**Re-verification:** Yes — after gap closure (plans 04-21, 04-22, 04-23, executed against the prior 1/5 verification's three gaps)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | After the adapter proves a safe flush, the Mac captures its declared persistent-save artifact and queues it locally while the server is unavailable. | ✓ VERIFIED | Live-session capture path unchanged from prior round (already ✓ VERIFIED then). The prior round's one disclosed caveat — crash-recovered revisions never entering the CAS (WINDOWS #52) — is now closed: `SaveSessionRecovery` holds a required `CASManager` (confirmed: `SaveSessionRecovery.swift:52`, `init(saveStore:casManager:blockedState:)`) and `replay` commits bytes via the shared `SaveCaptureBytesCommitter` before inserting the row (04-23, commit `fd4e2b4`). Both live and crash-recovery capture paths now share one CAS-commit implementation, closing the drift risk that caused #52 in the first place. |
| 2 | A user can see whether each save revision is local-only, queued, uploaded, current, restored, or conflicted rather than being shown a misleading generic sync status. | ✓ VERIFIED | Confirmed directly in source: `saveHistorySessions: { environment.saveHistorySessions(forAssetSetID: entry.id) }` is now present at both `GameRowView.swift:146` and `LibraryShellView.swift:157` (previously both defaulted to `{ [] }`, WINDOWS #43). `SaveHistorySessionBuilder` derives all six states from committed `SaveStore` columns, including a new persisted `restored_here_at` provenance column so `isRestoredHere` is told truthfully rather than guessed. `SaveRollup.rollup(for:)` now has a real production caller (`PlaysteadApp.swift:1101`/`1112`) and its line is removed from `reachability-allowlist.txt` (confirmed: `grep` for `SaveRollup` in the allowlist returns nothing), closing WINDOWS #47. |
| 3 | On a clean paired Mac, a user can restore a compatible checksummed save revision and continue the game. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (file half ✓ VERIFIED) | Unchanged from the prior round: the file-level byte-identical restore proof stands, and the zero-network restore guarantee is now additionally strengthened for the crash-recovery variant by truth 1's fix. The in-game continuation half (CP7-SAVE-C) remains a designed human-only checkpoint per D-68 — `04-UAT.md` still shows "testing paused — CP7-SAVE-C outstanding," untouched by this gap-closure round as instructed. |
| 4 | A user can export exact original game bytes and persistent-save revisions into deterministic ordinary folders with a readable hash manifest, then verify the exported bytes and revision evidence. | ✗ FAILED (partial) | The wiring defect that fully failed this criterion last round is fixed: `Export.load_save_revisions/2` (confirmed: `export.ex:119`) is called from all three production layout builders (confirmed: `export_set/3`, both `Worker.build_layout/1` clauses via `load_saves/3` at `worker.ex:101`), and a real committed revision's bytes are proven to land on disk and hash-match the manifest (`saves_loading_test.exs`). But the criterion's own word "deterministic" is not fully earned: a fresh code review (04-REVIEW-gaps-server.md CR-01) found, and this verification confirmed directly against source, that `Saves.get_history/2` (`saves.ex:411`) and `Branches.heads/2` (`branches.ex:45`) order revisions by `recorded_at` alone with no secondary key. Postgres gives no cross-execution ordering guarantee for tied values, so two revisions recorded within the same microsecond — plausible in exactly the concurrent-device scenario this phase is built around — can be assigned a different `seq`/filename on a later re-export, silently renaming a file already shipped to a self-hoster. See Gaps. |
| 5 | When two devices save from the same base revision, both revisions remain available with device, time, and play context; the user can inspect, choose, export, and resolve either side without silent last-write-wins. | ✓ VERIFIED (with a flagged concurrency defect, not scored as a failure) | Inspect/choose (`ConflictComparisonSheet`, reachable from `ReadinessSheetView`'s "Review versions..." remedy) unchanged and still wired. Export-either-side now writes real bytes (inherits truth 4's fix, and — separately — the *branch letter* a diverged side gets is derived from an immutable fork-root revision id via `SavesLineage.branch_keys/1`, not from `recorded_at`, so which side is "A" vs "B" is stable even though a within-side filename tie could still drift per truth 4's gap). Resolve now reaches the server: `saveOutbox.onEnqueue = { saveTrigger.fire() }` (`PlaysteadApp.swift:549`), plus reachability-regained and scene-active (`drainSaveOutbox()`, called from `applicationDidBecomeActive()`) triggers, closing WINDOWS #42. **Flagged, not scored as a failure:** a fresh code review (04-REVIEW-gaps-mac.md CR-01) found, and this verification confirmed directly against `SaveOutboxDrainTrigger.swift:41-61`, a genuine TOCTOU race — the read of `_lastTask` and the write of the new task happen in two separate locked sections, so two concurrently-invoked `fire()` calls (plausible: a resolution enqueued right as reachability flips online) can both read the same stale `_lastTask` and both call `SaveOutbox.drainOnce` concurrently, defeating the type's own documented single-lane guarantee and the specific concurrency truth 04-23's plan frontmatter declared for this. This is not scored as a criterion-5 failure because the server enforces a `device_id`+`idempotency_key` unique-constraint receipt layer (confirmed: `idempotency/receipt.ex:42-43`) that the outbox's `Idempotency-Key` header already targets — a duplicate concurrent send of the same entry is deduplicated server-side rather than causing data loss or a silent last-write-wins outcome. The client-side invariant is still genuinely broken and should be fixed (see gaps discussion below), but the observable ROADMAP-level truth holds. |

**Score:** 4/5 truths verified (1 present, behavior-unverified — truth 3's human continuation half, by design per D-68); truth 4 is the one genuine remaining gap.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Saves/SaveHistorySessionBuilder` (in `SaveHistorySheet.swift`) | Real per-revision session grouping from `SaveStore` | ✓ VERIFIED | Wired at both call sites; 17 tests in `SaveHistorySessionBuilderTests.swift` cover every behavior bullet |
| `playstead-mac/Playstead/Saves/SaveRollup.swift` | Game-level rollup with a production caller | ✓ VERIFIED | `AppEnvironment.saveRollupSummary(forAssetSetID:)` calls `SaveRollup.rollup(for:)`; allowlist entry removed; `reachability-sweep.sh --strict` passes |
| `playstead-mac/Playstead/Saves/SaveOutboxDrainTrigger.swift` | Drain trigger for `SaveOutbox`, mirroring `OutboxDrainTrigger` | ⚠️ WIRED BUT DEFECTIVE | Wired to all three trigger classes (confirmed), but its own `fire()` has a TOCTOU race defeating the serialization it exists to provide (04-REVIEW-gaps-mac.md CR-01, confirmed against source) |
| `playstead-mac/Playstead/Saves/SaveSessionRecovery.swift` | Crash-recovery replay committing bytes to the CAS | ✓ VERIFIED | Required `CASManager` parameter present; commits via shared `SaveCaptureBytesCommitter` before row insert |
| `playstead-server/lib/playstead/export/saves_lineage.ex` | Pure, stable branch-key derivation | ✓ VERIFIED | No `Repo`/`Playstead.Saves`/filesystem/clock references (confirmed by grep); fork-root-id-based, immutable across replanning |
| `playstead-server/lib/playstead/export.ex` (`load_save_revisions/2`) | Real save-revision loading at the Export context boundary | ✓ VERIFIED (wired) but ⚠️ non-deterministic under a tie | Called from all 3 production layout builders; ordering defect (see truth 4) is in its upstream data source (`Playstead.Saves`), not in this function itself |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `GameRowView.swift` / `LibraryShellView.swift` | `AppEnvironment.saveHistorySessions(forAssetSetID:)` | `saveHistorySessions:` closure override | ✓ WIRED | Confirmed at both call sites (`GameRowView.swift:146`, `LibraryShellView.swift:157`) |
| `AppEnvironment.saveRollupSummary(forAssetSetID:)` | `SaveRollup.rollup(for:)` | direct call | ✓ WIRED | Confirmed (`PlaysteadApp.swift:1101`, `:1112`) |
| `Export.export_set/3` + `Worker.build_layout/1` (both clauses) | `Playstead.Saves` (via `Export.load_save_revisions/2`) | direct call at the D-62 context boundary | ✓ WIRED | Confirmed (`export.ex:42`, `worker.ex:101`); `Layout` module still has zero `Playstead.Saves` references (D-62 boundary holds) |
| `SaveConflictResolver` (`chooseSide`/`keepBoth`) | `SaveOutbox.enqueue` → `SaveOutboxDrainTrigger.fire()` → server | `onEnqueue` closure + 2 more trigger classes | ✓ WIRED (with the flagged race above) | `saveOutbox.onEnqueue = { saveTrigger.fire() }` confirmed at `PlaysteadApp.swift:549`; reachability-regained and `drainSaveOutbox()` (scene-active) confirmed present |
| `Saves.get_history/2` / `Branches.heads/2` | Export `seq`/filename assignment | `recorded_at`-ordered list → `SavesPlan.plan/2`'s `Enum.with_index` | ✗ NOT DETERMINISTIC UNDER TIE | No secondary sort key on either query; confirmed by direct source read this session |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `SaveHistorySheet` | `sessions` | `AppEnvironment.saveHistorySessions(forAssetSetID:)` → `SaveStore.fetchRevisions`/`fetchHeads` | Yes | ✓ FLOWING |
| `SaveHistorySheet` | `summary` | `AppEnvironment.saveRollupSummary(forAssetSetID:)` → `SaveRollup.rollup(for:)` | Yes | ✓ FLOWING |
| `Export.plan/2` saves output | `saves_plan` per set | `Export.load_save_revisions/2` → `Saves.list_lines/2` + `Saves.get_history/2` | Yes, but with a non-deterministic ordering under a recorded_at tie | ⚠️ FLOWING (with an ordering defect) |
| `SaveOutbox` drain | outbound HTTP request | `SaveOutboxDrainTrigger.fire()` → `SaveOutbox.drainOnce(apiClient:)` | Yes, but the trigger's own serialization guarantee is broken under concurrent `fire()` | ⚠️ FLOWING (with a concurrency defect, mitigated server-side) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| saveHistorySessions wired at both call sites | `grep -n "saveHistorySessions:" playstead-mac/Playstead/Library/GameRowView.swift playstead-mac/Playstead/Library/LibraryShellView.swift` | one match in each file | ✓ CONFIRMS FIX (WINDOWS #43) |
| SaveRollup has a production caller | `grep -rn "SaveRollup.rollup" playstead-mac/Playstead \| grep -v Tests` | 2 non-test matches in `PlaysteadApp.swift` | ✓ CONFIRMS FIX (WINDOWS #47) |
| SaveRollup removed from reachability allowlist | `grep -n "SaveRollup" playstead-mac/scripts/ci/reachability-allowlist.txt` | no matches | ✓ CONFIRMS FIX |
| Export supplies real :saves data | `grep -n "load_save_revisions" playstead-server/lib/playstead/export.ex playstead-server/lib/playstead/export/worker.ex` | definition + call sites in `export_set/3` and `load_saves/3` (both `build_layout/1` clauses) | ✓ CONFIRMS FIX (WINDOWS #30) |
| saveOutbox drain trigger wired | `grep -n "saveOutbox\." playstead-mac/Playstead/App/PlaysteadApp.swift` | `onEnqueue` assignment present; `saveOutboxDrainTrigger.fire()` called from `drainSaveOutbox()` | ✓ CONFIRMS FIX (WINDOWS #42) |
| SaveSessionRecovery holds a CASManager | `grep -n "casManager" playstead-mac/Playstead/Saves/SaveSessionRecovery.swift` | required init parameter + `SaveCaptureBytesCommitter` construction | ✓ CONFIRMS FIX (WINDOWS #52) |
| SaveOutboxDrainTrigger.fire() race | Read `SaveOutboxDrainTrigger.swift:41-61` in full | `lock.unlock()` occurs between the `_lastTask` read and its write — two separate critical sections | ✗ CONFIRMS DEFECT (04-REVIEW-gaps-mac.md CR-01, real) |
| Revision ordering tiebreaker | `grep -n "order_by" playstead-server/lib/playstead/saves.ex playstead-server/lib/playstead/saves/branches.ex` | both `get_history/2` (line 411) and `heads/2` (line 45) order by `recorded_at` alone | ✗ CONFIRMS DEFECT (04-REVIEW-gaps-server.md CR-01, real) |
| Idempotency receipt layer exists server-side | `grep -n "unique_constraint" playstead-server/lib/playstead/idempotency/receipt.ex` | `unique_constraint([:device_id, :idempotency_key], ...)` | ✓ CONFIRMS MITIGATION for the drain-trigger race |

Automated gates (Mac Unit 582/0, server 1030/0, `reachability-sweep.sh --strict` exit 0) were taken as given per the task's explicit instruction and were not re-run in this session. All findings above are from direct source inspection of the gap-closure diffs and the two fresh code-review documents, cross-checked against the actual files rather than trusted from the reviews' or summaries' prose.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| SAVE-01 | 04-01, 04-02, 04-03, 04-06, 04-12, 04-15…04-20, 04-23 | Capture + queue locally while server unavailable | ✓ SATISFIED | Truth 1 above — crash-recovery variant now closed |
| SAVE-02 | 04-04, 04-09, 04-10, 04-11, 04-12, 04-16…04-19, 04-22 | Per-revision durability/position/provenance/lineage visibility | ✓ SATISFIED | Truth 2 above |
| SAVE-03 | 04-02, 04-07, 04-13, 04-14, 04-18, 04-20, 04-23 | Restore compatible revision on clean Mac, continue game | ? NEEDS HUMAN (file half satisfied) | Truth 3 above — unchanged, by design |
| SAVE-04 | 04-05, 04-10, 04-11, 04-15, 04-19, 04-21, 04-23 | Divergence: retain both, inspect/choose/export/resolve, no silent LWW | ✓ SATISFIED (with a flagged, server-mitigated concurrency defect) | Truth 5 above |
| PORT-01 | 04-08, 04-10, 04-21 | Export game bytes + save revisions + readable manifest, verify | ✗ PARTIALLY BLOCKED | Truth 4 above — wiring fixed, determinism guarantee not fully earned |

REQUIREMENTS.md marks all five "Complete." That marking now holds for SAVE-01, SAVE-02, SAVE-04 (with the one flagged, mitigated concurrency defect noted above) and remains unproven-not-falsified for SAVE-03's human half. It does **not** fully hold for PORT-01: the export pipeline is wired and functional in the common case, but the explicit "deterministic" requirement is falsified under a demonstrated, realistic tie condition.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `playstead-server/lib/playstead/saves.ex` | 411 | Single-key `order_by` with no tiebreaker feeding a "never renumbers" guarantee | 🛑 Blocker (for the determinism claim in criterion 4) | Causes truth 4's partial failure |
| `playstead-server/lib/playstead/saves/branches.ex` | 45 | Same single-key `order_by` pattern feeding head resolution | 🛑 Blocker (shared root cause) | Same as above |
| `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift` | 41-61 | TOCTOU: read-then-separately-write of `_lastTask` across two lock sections | ⚠️ Warning (mitigated server-side by idempotency receipts) | Violates the type's own documented invariant and 04-23's declared concurrency truth; does not currently break the observable ROADMAP truth |
| `playstead-mac/Playstead/Library/GameRowView.swift` | 468-469 | Ad hoc `SaveStore(localStore:)` construction instead of `environment.saveStore` (pre-existing, re-flagged by 04-REVIEW-gaps-mac.md WR-02) | ℹ️ Info | No observable divergence today (`SaveStore` is stateless); a latent violation of the "one shared store" composition rule |
| `playstead-server/lib/playstead/export/saves_lineage.ex` | 49-66 | `fork_root/4`'s per-revision ancestor walk is O(n²) for a long unforked line (04-REVIEW-gaps-server.md WR-03) | ℹ️ Info | Not a correctness defect; a scale risk for very long save lines, out of this verification's scope to block on |

No `TBD`/`FIXME`/`XXX` debt markers found in any file modified by plans 04-21..04-23 (checked directly against each plan's `files_modified` list).

### Human Verification Required

### 1. CP7-SAVE-C — the human continuation proof

**Test:** Perform 04-13-PLAN.md's Task 3 five steps against a real commercial GBA title through the pinned mGBA adapter, with the server running and the Mac paired.
**Expected:** The .sav file changes on a bounded cadence after an in-game save; a normal quit and a force-quit each capture a revision; restore onto a cleared save directory happens silently with no prompt; the game continues from the exact saved progress with no "save corrupt, erase?" prompt.
**Why human:** Requires a real emulator, a real commercial title, and human judgment of in-game continuity. This is 04-UAT.md's designed, disclosed, blocking-human checkpoint (D-68) — unchanged by this or the prior verification round.

### Gaps Summary

Of the prior round's three failing criteria, two are now fully resolved and confirmed directly against source:

1. **Per-revision save history (criterion 2)** — `saveHistorySessions` is wired at both call sites with real `SaveStore` data, and `SaveRollup` has a production caller. WINDOWS #43 and #47 closed and confirmed.
2. **Divergence resolution reaching the server (half of criterion 5)** — `SaveOutboxDrainTrigger` is wired to all three trigger classes. WINDOWS #42 closed and confirmed.

The third — **export saves data (criterion 4, and the export-either-side half of criterion 5)** — is genuinely fixed for the defect the prior round found (every production export now writes real save bytes, proven by a test that fails if the fix is reverted). But this verification pass, prompted by a fresh code review that ran after the gap-closure plans completed, found the export pipeline's ordering has no tiebreaker beyond `recorded_at`. This is a real, source-confirmed gap in the criterion's explicit "deterministic" word: a tie between two revisions committed at the same microsecond (plausible precisely in the concurrent-device scenario this whole phase exists to handle) can cause a later re-export to assign a different `seq`/filename to an already-shipped revision, silently violating D-59's "never renumbers" guarantee that 04-21's own plan declared as a must-have truth. Nothing in the current test suite would catch this, since `round_trip_test.exs`'s determinism assertions test a fork (different `parent_revision_id`, whose branch key is `id`-derived and therefore stable) rather than a same-branch timestamp tie.

A second finding from the fresh review — `SaveOutboxDrainTrigger.fire()`'s TOCTOU race (04-REVIEW-gaps-mac.md CR-01) — is real and confirmed directly against source, and it does violate 04-23's own declared concurrency truth. It is not scored as a criterion-5 failure because the server's `device_id`+`idempotency_key` unique-constraint receipt layer (confirmed present and applying to this exact header) deduplicates a concurrent double-send before it can cause data loss or a silent last-write-wins outcome. It is flagged here as a real defect that should still be fixed — the client-side serialization guarantee the type exists to provide is currently false, and the existing test (`testTwoOverlappingDrainPassesProduceAtMostOneSuccessfulSend`) cannot detect it because it invokes `fire()` synchronously from one thread.

**Recommended minimal follow-up (not re-litigating the whole gap-closure sequence):**
- Add `order_by: [asc: r.recorded_at, asc: r.id]` (or a proper monotonic tiebreaker) to `Saves.get_history/2` (saves.ex:411) and `Branches.heads/2` (branches.ex:45), plus a regression test committing two revisions with an identical `recorded_at` and asserting stable seq/filename across two export runs.
- Fix `SaveOutboxDrainTrigger.fire()`'s TOCTOU by moving the `_lastTask` read and write into one locked section, plus a test that actually races two `fire()` calls from different queues/tasks rather than calling `fire()` twice synchronously.

Both are small, well-understood, single-function fixes with a clear test recipe already spelled out by the reviews that found them — this does not require a plan of 04-21..04-23's scope, but it should not be silently absorbed into "phase complete" either.

---

_Verified: 2026-09-06T03:30:00Z_
_Verifier: Claude (gsd-verifier)_
