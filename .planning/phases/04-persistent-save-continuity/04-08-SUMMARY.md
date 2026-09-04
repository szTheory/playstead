---
phase: 04-persistent-save-continuity
plan: 08
subsystem: export
tags: [elixir, phoenix, ecto, bagit, export, determinism]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-05's revision DAG, Saves.Branches.heads/2/diverged?/2, and the (save_line_id, parent_revision_id) lineage this plan's revision-input contract mirrors"
provides:
  - "Playstead.Export.SavesPlan: pure planner for the reserved saves/ export slot -- sequence numbers, device-independent branch letters, and a linear-system_save-only drop-in copy"
  - "Sidecar.root/1 and Sidecar.set/1 populated saves object with branches always present, plus a companion saves.txt tag file per set"
  - "ExportRecord.saves_scope (persisted, default \"all\") and Layout.plan/2's opts[:saves] (:all | :none), threaded through Export.Worker so a re-enqueued job reproduces the same plan"
affects: [04-09, 04-10, 04-11, 04-12, 04-13]

actuals:
  tokens: 21500
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A pure, data-in/data-out planner (SavesPlan) mirroring Layout.plan_set's shape exactly -- the caller loads revision data and hands it in as plain maps; the planner performs no Repo, filesystem, or clock call, so it is trivially fuzz-testable and its determinism claims are literal equality assertions"
    - "Branches are always present in a nested sidecar structure, even for a fully linear history (single-element list, branch: nil) -- the structural guard against a diverged slot ever collapsing into a flat list is the schema, not a convention a future writer could forget"
    - "A missing-bytes payload entry is represented as sha256: nil in the manifest-entry map, reusing BagitWriter's existing manifest_lines/1 filter (Enum.filter(& &1.sha256)) that already excludes members with no blob -- no new missing-bytes code path was needed in the manifest writer"

key-files:
  created:
    - playstead-server/lib/playstead/export/saves_plan.ex
    - playstead-server/test/playstead/export/saves_plan_test.exs
    - playstead-server/test/playstead/export/sidecar_test.exs
    - playstead-server/priv/repo/migrations/20260904000003_add_saves_scope_to_export_records.exs
  modified:
    - playstead-server/lib/playstead/export/sidecar.ex
    - playstead-server/lib/playstead/export/bagit_writer.ex
    - playstead-server/lib/playstead/export/layout.ex
    - playstead-server/lib/playstead/export/export_record.ex
    - playstead-server/lib/playstead/export/worker.ex
    - playstead-server/test/playstead/export/layout_test.exs
    - playstead-server/test/playstead/export/bagit_writer_test.exs

key-decisions:
  - "SavesPlan takes revision_input maps carrying an already-resolved branch_key (nil for shared/pre-fork history, a stable string per fork) and is_head (from Branches.heads/2) rather than reconstructing DAG topology itself -- keeps the planner genuinely pure and lets it be authored/tested standalone in this plan, ahead of the real Playstead.Saves -> Export data-loading wire-up (deliberately out of this plan's declared files; see Known Stubs)."
  - "Layout.plan_set defaults a set's :saves input to [] when absent, so every existing caller (Export.to_layout_input/1, all prior layout_test.exs fixtures) is unaffected until a later plan attaches real revision data -- opts[:saves] :none/:all is fully wired and tested against synthetic input in the meantime."
  - "A missing-bytes revision's manifest entry gets sha256: nil, reusing the existing member-with-no-blob path in manifest_lines/1 instead of adding a second exclusion branch -- one filter, two reasons a file might be legitimately absent from the payload."
  - "Sidecar.root/1's saves marker stays a static {kind: \"saves\", branches: []} rather than aggregating real counts across sets -- root/1 is called with no set-level argument today (BagitWriter calls Sidecar.root() with zero args), so there is no data to aggregate from at that call site without a separate change outside this plan's files."
  - "Fixed bagit_writer_test.exs's pre-existing assertion on the old {\"kind\" => \"reserved\", \"entries\" => []} placeholder shape (Rule 3, blocking issue) -- required for the plan's own verification block (full suite must pass) since that file is not itself in this plan's declared file set."

patterns-established:
  - "A revision or member's payload presence is represented uniformly as sha256: nil in the manifest-entry map, not as a separate boolean flag -- any future 'this artifact intentionally has no bytes on this server' case slots into the same filter."

requirements-completed: [PORT-01]

coverage:
  - id: D1
    description: "Save revisions are exported into the reserved saves/ slot with sequence numbers in recorded_at order and device-independent branch letters"
    requirement: "PORT-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/export/saves_plan_test.exs (12 tests, pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A linear slot gets a drop-in saves/{stem}.sav copy named from the primary member's original basename; a diverged slot or a non-system_save revision gets none"
    requirement: "PORT-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/export/saves_plan_test.exs (drop-in tests, pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The sidecar's saves key carries branches always present (even linear = single element), a companion saves.txt readable manifest, and a missing-bytes revision is named as missing while absent from manifest-sha256.txt/fetch.txt so sha256sum -c still succeeds"
    requirement: "PORT-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/export/sidecar_test.exs (9 tests, pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "saves_scope is persisted on ExportRecord (migration + changeset) and Layout.plan/2's opts[:saves] reproduces the same plan from a persisted record; determinism is asserted as plan purity, write reproducibility (byte-identical except two Phase-2-inherited exceptions), and append-only stability"
    requirement: "PORT-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/export/layout_test.exs (7 new tests, 17 total in file, pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The full pre-existing export suite and the full server test suite remain green after the sidecar/layout changes"
    requirement: "PORT-01"
    verification:
      - kind: integration
        ref: "mix test test/playstead/export/ (85 tests, pass); mix test full suite (961 tests, 0 failures, up from 933 baseline)"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 8: Save Export Layout — Filling Phase 2's Reserved Slot Summary

**A pure `Export.SavesPlan` fills Phase 2's reserved `saves/` export socket with device-independent, append-only-stable filenames, a `branches`-always-present sidecar, a `saves.txt` readable manifest, and a persisted `saves_scope` so a re-enqueued export job never silently changes what it includes.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-09-04T15:20:00Z (approx.)
- **Completed:** 2026-09-04T15:32:27Z
- **Tasks:** 3
- **Files modified:** 12 (4 created, 8 modified — including two pre-existing test files updated to match the new sidecar shape)

## Accomplishments

- `Playstead.Export.SavesPlan` plans one save slot from a flat list of already-loaded revisions: `{seq:06}[-{branch}]-{digest8}.{ext}` filenames, sequence numbers stable under append, branch letters derived from a stable `branch_key` (never a device name), and a drop-in `saves/{stem}.sav` copy defined only for a linear `system_save` slot — never for a diverged one or a save state
- `Sidecar.root/1` and `Sidecar.set/1` fill the reserved `"saves" => {"kind": "reserved", "entries": []}` placeholder with real content; `branches` is always present (a single-element list even for linear history), so a diverged slot cannot serialise as a flat list implying one history
- `BagitWriter` writes save revisions and the drop-in copy through the existing `write_member!`-style path (resumable, fsync-then-rename) and a new `saves.txt` tag file per set; a missing-bytes revision is named in the sidecar as `"bytes": "missing"` and is absent from `manifest-sha256.txt`/`fetch.txt`, so `sha256sum -c` still succeeds
- `Layout.plan/2` gains `opts[:saves]` (`:all` default, `:none`), read exactly like `include_excluded`; `ExportRecord` persists `saves_scope` (migration `20260904000003`) so `Export.Worker` reconstructs the identical plan on any re-enqueue instead of falling back to a default
- `layout_test.exs` directly asserts D-59's three-part determinism definition: plan purity, write reproducibility (two `write_bag/2` runs differ only in `bag-info.txt`/`tagmanifest-sha256.txt`, enumerated in the assertion so a third exception can never sneak in unnoticed), and append-only stability (appending a revision never changes a previously written revision file's bytes)

## Task Commits

1. **Task 1: The pure Export.SavesPlan and the filename grammar** - `a039426` (test+feat combined, tdd)
2. **Task 2: Populate the reserved sidecar key and write the readable manifest** - `8a899fa` (feat, tdd)
3. **Task 3: Saves scope, persisted on the record, and asserted determinism** - `31f4ce4` (feat, tdd)

**Plan metadata:** (this commit)

_Note: each task combined its RED test file and GREEN implementation into a single commit rather than two separate `test(...)`/`feat(...)` commits — see Deviations._

## Files Created/Modified

- `playstead-server/lib/playstead/export/saves_plan.ex` - New pure planner: sequencing, branch letters, drop-in eligibility
- `playstead-server/test/playstead/export/saves_plan_test.exs` - 12 tests covering all behaviors in the plan's `<behavior>` list
- `playstead-server/lib/playstead/export/sidecar.ex` - `root/1`/`set/1` populate `saves`; new `saves_sidecar/1` private helper
- `playstead-server/lib/playstead/export/bagit_writer.ex` - Writes save-slot payload entries and `saves.txt`
- `playstead-server/test/playstead/export/sidecar_test.exs` - 9 tests: branches-always-present, missing bytes, `saves.txt`, round-trip fields
- `playstead-server/test/playstead/export/bagit_writer_test.exs` - Fixed one pre-existing assertion for the new sidecar shape
- `playstead-server/lib/playstead/export/layout.ex` - `opts[:saves]`, `saves_scope_atom/1`, per-set `saves_plan` construction and path prefixing
- `playstead-server/lib/playstead/export/export_record.ex` - `saves_scope` field + changeset validation
- `playstead-server/lib/playstead/export/worker.ex` - Reads persisted `saves_scope`, threads it into `Layout.plan/2`
- `playstead-server/priv/repo/migrations/20260904000003_add_saves_scope_to_export_records.exs` - New column + check constraint
- `playstead-server/test/playstead/export/layout_test.exs` - 7 new tests: opt default/override, plan purity, write reproducibility, append-only stability, re-enqueue reproduction, no-`Playstead.Saves`-alias guard

## Decisions Made

See `key-decisions` in frontmatter. Most notable: `SavesPlan` takes an already-DAG-resolved `revision_input` (with `branch_key`/`is_head` precomputed by whatever future caller loads real `Playstead.Saves` data) rather than performing DAG traversal itself — this keeps the planner genuinely pure and lets this plan build, test, and commit it standalone, exactly as `discussion-research/H-save-export-shape.md`'s `D-H9` seam specifies (`Export.Layout` gets data, never a query).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed bagit_writer_test.exs's assertion on the old reserved-placeholder sidecar shape**
- **Found during:** Task 2, after changing `Sidecar.root/1`'s `"saves"` value from `{"kind": "reserved", "entries": []}` to `{"kind": "saves", "branches": []}`
- **Issue:** `bagit_writer_test.exs` (not in this plan's declared files) asserted `decoded["saves"]["entries"] == []`, which the new shape no longer satisfies (there is no `"entries"` key at all).
- **Fix:** Updated the one assertion to `decoded["saves"]["branches"] == []`.
- **Files modified:** `playstead-server/test/playstead/export/bagit_writer_test.exs`
- **Verification:** `mix test test/playstead/export/bagit_writer_test.exs` passes; required by the plan's own `<verification>` block ("the full suite passes, proving the sidecar change did not break Phase 2's shipped export tests").
- **Committed in:** `8a899fa` (Task 2 commit)

### Noted, Not Fixed (documented scope boundary)

**2. [Scope decision] Real `Playstead.Saves` -> `Export` data loading is not wired in this plan**
- **Found during:** Task 1 design
- **Issue:** `discussion-research/H-save-export-shape.md`'s `D-H9` names `Playstead.Export.to_layout_input/2` gaining a `:saves` key populated by the caller from `Playstead.Saves.export_inputs/2` (a function that does not yet exist). Neither `export.ex` nor any accessor on `Playstead.Saves` for "all revisions for this content_key" is in this plan's declared `files_modified`.
- **Resolution:** `SavesPlan`, `Sidecar`, and `Layout` are fully built, tested, and wired to accept real revision data the moment a future plan attaches a `:saves` list to a set's layout input (`Layout.plan_set` already defaults the key to `[]`, so nothing breaks in the meantime). Until then, an actual export produces an empty (but structurally correct) `saves` object.
- **Impact:** No production export currently includes real save history — the plumbing is complete and tested against synthetic data, but the final data-loading wire (`Playstead.Saves` -> `Export.to_layout_input/1` -> `Export.Worker`) is left for a later plan in this phase (04-09 through 04-13 are the remaining plans in this wave sequence).

**3. [Scope decision] The console `saves_scope` control (D-H10) is not built in this plan**
- **Found during:** Task 3
- **Issue:** The plan's task 3 action text mentions "the console gets one control for the saves scope," but `exports_live.ex` is not in this plan's declared `files_modified`, and no acceptance criterion tests a UI control.
- **Resolution:** `ExportRecord.saves_scope` defaults to `"all"` at the schema/DB level, so every export today behaves exactly as before this plan (all revisions, when any exist). Wiring a user-facing control to set it to `"none"` is left for the console plan in this sequence.
- **Impact:** None on correctness — the default preserves existing behavior; the option exists and is fully tested, just not yet user-settable through the LiveView console.

### Process Note (not a deviation, documented for transparency)

Each `tdd="true"` task's RED (failing test) and GREEN (implementation) steps were combined into one commit per task rather than two separate commits, since the module/feature was new and small enough that writing the test alongside the implementation in one pass was more efficient than a strict two-commit cycle. All tests were verified to genuinely exercise the new behavior (no vacuous "assert true" tests), and each task's commit message is prefixed to reflect its dominant nature (`test(...)` for task 1, `feat(...)` for tasks 2 and 3).

---

**Total deviations:** 1 auto-fixed (blocking, pre-existing test), 2 documented scope decisions (data-loading wire-up and console control both deferred to later plans in this phase's sequence), 1 process note (combined RED/GREEN commits).
**Impact on plan:** All must-have truths, prohibitions, and acceptance criteria in the plan are met by the code built in this plan's declared files. The two deferred items are genuinely out of this plan's declared file scope and do not affect the reserved-slot layout, sidecar schema, or determinism guarantees this plan establishes — they affect only whether a *live* export today carries real save history, which requires touching files outside this plan.

## Issues Encountered

None beyond the deviations above.

## Known Stubs

- **Real save-revision data is not yet loaded into any export.** `Export.to_layout_input/1` (unmodified by this plan) does not attach a `:saves` key to its output, so `Layout.plan_set`'s `Map.get(set, :saves, [])` always defaults to `[]` in production today. The entire `SavesPlan` → `Sidecar` → `BagitWriter` pipeline is built and tested against synthetic revision data and is ready to receive real data the moment a future plan wires `Playstead.Saves` revisions into `Export.to_layout_input/1` (or an equivalent boundary function). Tracked in Deviation 2 above.
- **The console has no UI control for `saves_scope`.** The field defaults to `"all"` and is fully persisted/threaded through the worker; only the LiveView control to set it to `"none"` is unbuilt. Tracked in Deviation 3 above.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers. All six threats (T-04-08-01 through T-04-08-06) are mitigated as designed: every saves path component routes through `Sanitize.component/1`/`reserved_saves_name?/1` (no new sanitize code written); a diverged slot never gets a drop-in copy and `branches` is always present; missing bytes are named and kept out of `fetch.txt`; `saves_scope` is persisted so a re-run reproduces the same plan; branch letters never leak a device name; and the DoS threat is accepted per the plan's own disposition (bounded by plan 04-03's 8 MiB artifact cap and 04-05's per-user backstops).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `Export.SavesPlan`, the populated sidecar, `saves.txt`, and the persisted `saves_scope` are the complete, tested plumbing for the reserved `saves/` export slot — ready for a later plan to wire real `Playstead.Saves` revision data into `Export.to_layout_input/1` and a console control into `exports_live.ex`
- The `revision_input` contract (`id`, `sha256`, `size_bytes`, `recorded_at`, `save_kind`, `is_head`, `branch_key`, `bytes`) is the exact shape a future data-loading boundary function must produce, derived directly from `Playstead.Saves.Revision` and `Playstead.Saves.Branches.heads/2`'s existing fields
- Ready for the next plan in this phase's sequence.

## Self-Check: PASSED

- `[ -f playstead-server/lib/playstead/export/saves_plan.ex ]` → FOUND
- `[ -f playstead-server/test/playstead/export/saves_plan_test.exs ]` → FOUND
- `[ -f playstead-server/priv/repo/migrations/20260904000003_add_saves_scope_to_export_records.exs ]` → FOUND
- `git log --oneline --all | grep -q a039426` → FOUND
- `git log --oneline --all | grep -q 8a899fa` → FOUND
- `git log --oneline --all | grep -q 31f4ce4` → FOUND
- `cd playstead-server && MIX_ENV=test mix test test/playstead/export/saves_plan_test.exs` → PASS (12 tests, 0 failures)
- `cd playstead-server && MIX_ENV=test mix test test/playstead/export/sidecar_test.exs` → PASS (9 tests, 0 failures)
- `cd playstead-server && MIX_ENV=test mix test test/playstead/export/layout_test.exs` → PASS (17 tests, 0 failures)
- `cd playstead-server && MIX_ENV=test mix test test/playstead/export/` → PASS (85 tests, 0 failures)
- `cd playstead-server && MIX_ENV=test mix test` (full suite) → PASS (961 tests, 0 failures; baseline was 933 before this plan)
- `grep -v '^\s*#' saves_plan.ex | grep -ciE 'Repo\.|File\.|DateTime.utc_now|NaiveDateTime.utc_now'` → 0 (PASS)
- `grep -c 'reserved_saves_name?' saves_plan.ex` → 1 (PASS, ≥1)
- `grep -v '^\s*#' sidecar.ex | grep -c '"kind" => "reserved"'` → 0 (PASS)
- `git diff playstead-server/lib/playstead/export/verifier.ex` → empty (PASS)
- `git diff playstead-server/lib/playstead/export/sanitize.ex` → empty (PASS)
- `grep -c 'saves_scope' export_record.ex` → 4 (PASS, ≥2)
- `grep -v '^\s*#' layout.ex | grep -c 'Playstead.Saves'` → 0 (PASS)

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*
