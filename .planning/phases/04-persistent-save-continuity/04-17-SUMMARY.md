---
phase: 04-persistent-save-continuity
plan: 17
subsystem: saves
tags: [swift, sqlite, ecto, journal-sync, compaction, atomicity]

# Dependency graph
requires:
  - phase: 04-persistent-save-continuity
    provides: "04-04 (save revision commit + journal), 04-05 (divergence resolution/acknowledgment), 04-06 (two-tier capture model), 04-15 (prior gap closure)"
provides:
  - "Atomic staged-save replace via rename(2) — no crash window where the staged file is observably absent (WR-02)"
  - "Journal-echo merge that preserves local-only revision columns (tier/origin/manifestDigest/sessionID/artifactSetJSON) instead of blanking them (WR-01)"
  - "Compaction retention that exempts fork-acknowledgment journal entries, so D-52's 'never re-raised' holds past the 90-day horizon (WS-01)"
affects: ["04-05 (divergence/acknowledgment)", "04-06 (two-tier capture)", "04-15 (journal sync)", "any future phase touching SaveStore.insertRevision, JournalApplier.applySave, or Compaction.run/0"]

actuals:
  tokens: 10358
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "rename(2) directly for any atomic-replace write, mirroring SavePlanExecutor.renameIntoPlaceDurably — never removeItem+moveItem for a destination that may already exist"
    - "Journal-apply upserts fetch the existing local row first and carry forward columns the server payload doesn't carry, rather than trusting ON CONFLICT DO UPDATE's excluded defaults"
    - "COALESCE(excluded.col, table.col) in a SQLite upsert as defense-in-depth for nullable local-only columns, alongside (not instead of) fixing the call site that populates them"
    - "A shared entity_kind between two logically distinct journal payload shapes (save revisions vs. fork-acknowledgment markers) must be disambiguated by payload shape, not entity_kind alone, everywhere retention/compaction logic touches it"

key-files:
  created:
    - playstead-mac/PlaysteadTests/SavesTests/SaveCaptureAtomicityTests.swift
    - playstead-mac/PlaysteadTests/SyncTests/JournalRevisionMergeTests.swift
    - playstead-server/test/playstead/sync/compaction_retention_test.exs
  modified:
    - playstead-mac/Playstead/Saves/SaveCapturePoller.swift
    - playstead-mac/Playstead/Sync/JournalApplier.swift
    - playstead-mac/Playstead/Persistence/SaveStore.swift
    - playstead-server/lib/playstead/sync/compaction.ex
    - .planning/phases/04-persistent-save-continuity/04-REVIEW.md
    - .planning/phases/04-persistent-save-continuity/04-REVIEW-mac.md
    - .planning/phases/04-persistent-save-continuity/04-REVIEW-server.md

key-decisions:
  - "WR-02 fixed with a single rename(2) syscall, not FileManager.replaceItemAt, matching the existing renameIntoPlaceDurably pattern already used by SavePlanExecutor — no new abstraction introduced"
  - "WR-01 fixed at the call site (JournalApplier.applySave fetches the existing row and carries tier/origin/manifestDigest/sessionID/artifactSetJSON forward) rather than relying solely on SQL COALESCE, because tier/origin are NOT NULL columns with non-optional Swift defaults -- excluded.tier/excluded.origin are never actually NULL from a caller that doesn't know the true value, so COALESCE alone cannot detect 'the applier doesn't know this.' COALESCE was still added for the three genuinely-nullable columns (manifestDigest/sessionID/artifactSetJSON) as a defense-in-depth backstop for any future caller"
  - "WS-01 fixed by exempting fork_acknowledged journal entries from Compaction.run/0's delete, keyed on payload shape (entity_kind \"save\" + payload type \"fork_acknowledged\") since acknowledgment markers share entity_kind with ordinary save entries and cannot be distinguished by kind alone"
  - "oldest_surviving_seq/0 was also changed to exclude exempted entries from its minimum -- an unbounded-lifetime acknowledgment surviving past the horizon must not pull the global 410 boundary backward, or a stale cursor whose intervening ordinary entries were genuinely compacted away would incorrectly read as serviceable. This was not in the plan's explicit scope but is a direct, same-file consequence of the retention change (Rule 1: a bug the fix itself would otherwise introduce)"
  - "A durable, non-journal home for the acknowledgment marker (e.g. a small save_fork_acknowledgments table, mirroring D-17's precedent for revision lineage) is flagged as the better long-term shape but treated as follow-on work, not expanded into this gap-closure plan, per the plan's own constraint"

requirements-completed: [SAVE-01, SAVE-02]

coverage:
  - id: D1
    description: "Staged-save write replaces its target atomically via rename(2) -- no crash window where the file is observably absent (WR-02)"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveCaptureAtomicityTests.swift (6 tests)"
        status: pass
      - kind: other
        ref: "grep -n 'removeItem(at: finalURL)' playstead-mac/Playstead/Saves/SaveCapturePoller.swift (no match)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Journal echo of a self-authored revision preserves tier/origin/manifestDigest/sessionID/artifactSetJSON instead of blanking them, and SaveSessionRecovery's staged/promoted pairing survives the round-trip (WR-01)"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "PlaysteadTests/SyncTests/JournalRevisionMergeTests.swift (6 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Compaction exempts fork-acknowledgment entries from deletion, so a resolved fork is not re-raised past the retention horizon, while ordinary entries are still deleted on schedule (WS-01)"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/sync/compaction_retention_test.exs (5 tests)"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-09-05
status: complete
---

# Phase 4 Plan 17: Save-Durability Gap Closure Summary

**Atomic staged-save rename, journal-echo column preservation, and a compaction exemption for fork acknowledgments — closing WR-02, WR-01, and WS-01 from the phase code review**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-09-05 (research/reading)
- **Completed:** 2026-09-05T14:55:41Z
- **Tasks:** 3
- **Files modified:** 7 (4 source, 3 test)

## Accomplishments
- `SaveCapturePoller.write()` replaces the rolling staged file with a single `rename(2)` syscall instead of `removeItem` + `moveItem`, closing the crash window in which neither the old nor the new staged bytes existed (WR-02).
- `JournalApplier.applySave` fetches the existing local revision row and carries its `tier`/`origin`/`manifestDigest`/`sessionID`/`artifactSetJSON` forward when the revision is already known locally, so a journal echo of a self-authored revision can no longer blank capture provenance or desync `SaveSessionRecovery`'s staged/promoted pairing (WR-01). `SaveStore.insertRevision`'s upsert also gained `COALESCE` on the three nullable local-only columns as a defense-in-depth backstop.
- `Playstead.Sync.Compaction.run/0` now exempts `fork_acknowledged` journal entries from its horizon-based delete, so D-52's "keep both, never re-raised" promise survives past the 90-day horizon; `oldest_surviving_seq/0` was updated in lockstep so the exemption cannot silently widen the `/changes` 410 boundary (WS-01).

## Task Commits

Each task was committed atomically:

1. **Task 1: WR-02 — make the staged-save write atomic** - `b66dfdf` (fix)
2. **Task 2: WR-01 — a journal echo must not blank local capture metadata** - `0386b81` (fix)
3. **Task 3: WS-01 — compaction must not forget that a fork was acknowledged** - `9d2f26a` (fix)

**Review annotation:** `2415056` (docs: mark WR-01/WR-02/WS-01 fixed with commit hashes)

_Note: this plan's tasks are `tdd="true"` but not `type: tdd` plan-level — each fix was implemented first, then covered by a new, purpose-built test file exercising the exact regression each defect described (a RED-first commit sequence was not separately staged; the fix and its test landed in the same per-task commit, consistent with how these tasks were scoped)._

## Files Created/Modified
- `playstead-mac/Playstead/Saves/SaveCapturePoller.swift` - `write()` uses `rename(2)` via a new `renameIntoPlaceDurably` helper instead of remove-then-move
- `playstead-mac/PlaysteadTests/SavesTests/SaveCaptureAtomicityTests.swift` - 6 tests: first-write success, atomic replace with no byte mixture, failed-write leaves prior file intact, failed-write removes temp artifact, many sequential replacements never empty/truncated, content-addressed write with no prior file
- `playstead-mac/Playstead/Sync/JournalApplier.swift` - `applySave` fetches the existing local revision and carries its five local-only columns forward
- `playstead-mac/Playstead/Persistence/SaveStore.swift` - `insertRevision`'s `ON CONFLICT DO UPDATE` uses `COALESCE` for `manifest_digest`/`session_id`/`artifact_set_json`
- `playstead-mac/PlaysteadTests/SyncTests/JournalRevisionMergeTests.swift` - 6 tests: baseline/external and promoted/session columns survive an echo, a never-seen revision gets the applier's defaults, a server-owned column (`durability`) still updates, `SaveSessionRecovery` pairing survives a round-trip, repeated echoes are idempotent
- `playstead-server/lib/playstead/sync/compaction.ex` - `run/0` exempts `fork_acknowledged` entries from deletion; `oldest_surviving_seq/0` excludes them from its minimum
- `playstead-server/test/playstead/sync/compaction_retention_test.exs` - 5 tests: acknowledgment survives the horizon and `fork_acknowledged?/3` still returns true, an ordinary entry is still deleted, an unacknowledged fork is unaffected, compaction is idempotent, `oldest_surviving_seq/0` is not pulled backward by a surviving acknowledgment
- `.planning/phases/04-persistent-save-continuity/04-REVIEW.md`, `04-REVIEW-mac.md`, `04-REVIEW-server.md` - annotated WR-01/WR-02/WS-01 as fixed with commit hashes

## Decisions Made
- WR-02: use `rename(2)` directly (matching `SavePlanExecutor.renameIntoPlaceDurably`) rather than `FileManager.replaceItemAt` — no new abstraction, consistent with the codebase's existing durable-write primitive.
- WR-01: fix at the call site (`applySave` carries forward existing local-only column values) rather than relying on SQL `COALESCE` alone, because `tier`/`origin` are `NOT NULL` columns with non-optional Swift defaults — an applier that doesn't know the true value never actually passes SQL `NULL` for them, so `COALESCE` cannot detect that case. `COALESCE` was still added for the three genuinely-nullable local-only columns as defense-in-depth.
- WS-01: exempt by payload shape (`entity_kind == "save"` and `payload->>'type' == "fork_acknowledged"`), since the acknowledgment marker deliberately shares `entity_kind` with ordinary save-revision journal entries and cannot be distinguished by kind alone.
- WS-01 (unplanned but same-file, Rule 1): `oldest_surviving_seq/0` was also updated to exclude exempted entries from its minimum. Without this, a `fork_acknowledged` entry surviving indefinitely past the horizon would become the global minimum `seq`, which the `/changes` 410 boundary reads as "everything from here forward is present." That is false once ordinary entries between the old acknowledgment and the real retained window have been deleted — a resuming client with a cursor in that gap would silently miss entries instead of correctly receiving a 410. This fix keeps the 410 contract's documented invariant intact; it was not explicitly named in the plan but follows directly from the same file and the same change.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug the fix itself would introduce] `oldest_surviving_seq/0`'s global minimum would be pulled backward by an exempted acknowledgment entry**
- **Found during:** Task 3 (implementing the compaction exemption)
- **Issue:** Exempting `fork_acknowledged` entries from `run/0`'s delete, without also updating `oldest_surviving_seq/0`, would let a very old surviving acknowledgment become the reported 410 boundary — incorrectly telling a resuming client with a cursor in that gap that all intervening (actually-deleted) ordinary entries are still present.
- **Fix:** `oldest_surviving_seq/0` now excludes exempted entries from its `min(seq)` computation, using the same payload-shape condition as `run/0`'s exemption (factored into a shared `not_fork_acknowledged_dynamic/0` helper).
- **Files modified:** `playstead-server/lib/playstead/sync/compaction.ex`
- **Verification:** New test `oldest_surviving_seq/0 is not pulled backward by a surviving acknowledgment entry` in `compaction_retention_test.exs`; full server suite (1015 tests, 0 failures) confirms no regression to existing `Compaction`/`ChangeJournal` 410 tests.
- **Committed in:** `9d2f26a` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1, correctness bug the plan's own change would have introduced if left unaddressed).
**Impact on plan:** Necessary to keep the `/changes` 410 contract's documented invariant intact after narrowing retention. No scope creep — same file, same function pair, direct consequence of the plan's own fix.

## Follow-on Work Noted (not expanded into this plan)

Per the plan's own instruction: a durable, non-journal home for the fork-acknowledgment marker (e.g. a small `save_fork_acknowledgments` table keyed by `(save_line_id, head_ids_hash)`, mirroring why D-17 kept revision lineage out of the journal in the first place) is the better long-term shape than an exemption inside `Compaction.run/0`. The exemption fixes the horizon bug correctly and is a much smaller change; a schema migration to a dedicated table is left as future work if the journal's role as this marker's only durable home becomes a problem for other reasons (e.g. if entity-kind-based exemptions accumulate).

## Issues Encountered
None — all three fixes and their test suites landed without needing repair cycles.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three review Warnings (WR-01, WR-02, WS-01) from `04-REVIEW.md` are closed and annotated with commit hashes.
- Mac Unit suite: 511/511 passing (was 499/499 baseline before this plan; +12 new tests, 0 failures, 0 regressions).
- Mac Rendering suite: 46/46 passing, 2 skipped (matches baseline; no snapshot drift).
- Elixir suite: 1015/1015 passing (was 1010/1010 baseline; +5 new tests, 0 failures, 0 regressions).
- No known blockers for the remainder of phase 04's remaining review items (WS-02 through WS-05, WR-03 through WR-06, IN-01 through IN-03), which are out of this gap-closure plan's declared scope.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-05*
