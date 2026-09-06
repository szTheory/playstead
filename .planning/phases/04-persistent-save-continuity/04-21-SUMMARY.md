---
phase: 04-persistent-save-continuity
plan: 21
subsystem: export
tags: [elixir, ecto, export, saves, bagit, oban]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-08's fully-built SavesPlan/Sidecar/BagitWriter saves-slot pipeline, previously unreachable because no caller ever attached a `:saves` key"
provides:
  - "Playstead.Saves.list_lines/2 -- the one new saves query needed"
  - "Playstead.Export.load_save_revisions/2 -- the D-62 context-boundary function that loads a user's real save revisions into SavesPlan.revision_input maps"
  - "Playstead.Export.to_layout_input/2 -- arity-2 variant that attaches a :saves list (default [] keeps every existing caller compiling)"
  - "Playstead.Export.SavesLineage.branch_keys/1 -- pure, stable, device-independent branch-key derivation (D-58)"
  - "All three production layout builders (export_set/3, Worker.build_layout/1 set and library clauses) now load and pass real save data"
affects: [export, saves, catalogue]

actuals:
  tokens: 8403
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Export -> Saves coupling lives at exactly one boundary function (Export.load_save_revisions/2); Layout and SavesPlan remain pure and never mention Playstead.Saves"
    - "Branch keys are derived as the fork-root revision's own immutable id, found by walking parent_revision_id upward -- never from a device name or wall-clock read"
    - "save_kind vocabulary reconciliation (Saves' \"battery\" -> SavesPlan's \"system_save\") lives in exactly one private function (map_save_kind/1)"

key-files:
  created:
    - playstead-server/lib/playstead/export/saves_lineage.ex
    - playstead-server/test/playstead/export/saves_loading_test.exs
    - playstead-server/test/playstead/export/saves_lineage_test.exs
  modified:
    - playstead-server/lib/playstead/export.ex
    - playstead-server/lib/playstead/export/worker.ex
    - playstead-server/lib/playstead/saves.ex
    - playstead-server/test/playstead/export/round_trip_test.exs

key-decisions:
  - "branch_key is the fork root's own UUID (not a sequential letter or hash) -- immutable across replanning, and SavesPlan.assign_branch_letters/1 already turns a stable key into a stable letter, so no new stability logic was needed there."
  - "load_save_revisions/2 selects only the (save_kind: \"battery\", slot: \"0\") line when more than one line exists for a content_key, rather than merging histories -- concatenating two DAGs would make SavesPlan.diverged?/1 lie. Recorded as a disclosed limitation in WINDOWS.md (currently unreachable: the Mac client only ever writes one line)."
  - "saves_scope: :none skips the Saves query entirely (Worker.load_saves/3 short-circuits before calling Export.load_save_revisions/2), not merely discarding the result after loading it, per D-57 / T-04-21-03."

requirements-completed: [PORT-01, SAVE-04]

coverage:
  - id: D1
    description: "An export of a game with a committed save revision writes that revision's real bytes into the bag; the saves/ slot for a game with revisions is non-empty on disk and the bag verifies (ROADMAP criterion 4)."
    requirement: PORT-01
    verification:
      - kind: integration
        ref: "test/playstead/export/saves_loading_test.exs#an export of a game with one committed save revision writes that revision's real bytes into the bag"
        status: pass
      - kind: integration
        ref: "test/playstead/export/saves_loading_test.exs#an asset set with zero save lines still produces an empty saves/ slot and a bag that verifies"
        status: pass
      - kind: integration
        ref: "test/playstead/export/saves_loading_test.exs#deleting the :saves key from to_layout_input/2 makes this test go red (falsification check)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Both sides of a real save divergence export under stable, distinct branch letters, and re-planning the same fork reproduces the same letters (ROADMAP criterion 5's export deep link is real, not an empty slot)."
    requirement: SAVE-04
    verification:
      - kind: unit
        ref: "test/playstead/export/saves_lineage_test.exs#a two-way fork yields two distinct non-nil keys, inherited by every descendant of each side"
        status: pass
      - kind: integration
        ref: "test/playstead/export/saves_lineage_test.exs#two sides of a real fork export under stable, distinct branch letters, and re-planning is stable"
        status: pass
    human_judgment: false
  - id: D3
    description: "A revision whose bytes are not on this server is named in the sidecar/manifest as missing, its file is absent from the payload, and the bag still verifies (D-61)."
    verification:
      - kind: integration
        ref: "test/playstead/export/saves_lineage_test.exs#a revision whose blob is absent from the store produces no payload file, no manifest line, and a bag that still verifies"
        status: pass
    human_judgment: false
  - id: D4
    description: "A battery (system) save line with a single linear head earns a saves/<stem>.sav drop-in copy; a diverged line does not."
    verification:
      - kind: integration
        ref: "test/playstead/export/saves_lineage_test.exs#a battery line with a single linear head gets a saves/<stem>.sav drop-in copy"
        status: pass
      - kind: integration
        ref: "test/playstead/export/saves_lineage_test.exs#a diverged line (multiple heads) gets no drop-in copy"
        status: pass
    human_judgment: false
  - id: D5
    description: "Append-only stability (D-59): a later commit never renumbers or renames an earlier revision's exported filename. Re-exporting is idempotent. Two users sharing a content_key never see each other's save bytes (T-04-21-01)."
    verification:
      - kind: integration
        ref: "test/playstead/export/round_trip_test.exs#an appended revision never renumbers or renames a pre-existing revision's exported file (D-59)"
        status: pass
      - kind: integration
        ref: "test/playstead/export/round_trip_test.exs#re-running the export worker twice against one target leaves every payload byte-identical and still verifies"
        status: pass
      - kind: integration
        ref: "test/playstead/export/round_trip_test.exs#a second user sharing the same content_key never sees the first user's save bytes (T-04-21-01)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-06
status: complete
---

# Phase 04 Plan 21: Real save revisions wired into the export pipeline Summary

**Every production export path now loads real `Playstead.Saves` revisions into the bag via one D-62 boundary function, with stable device-independent branch keys and honest missing-bytes handling -- closing WINDOWS #30 / PORT-01.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-06T01:05:00Z
- **Completed:** 2026-09-06T02:00:00Z
- **Tasks:** 3
- **Files modified:** 7 (3 created, 4 modified)

## Accomplishments

- `Playstead.Saves.list_lines/2` added -- the one new saves query, returning a user's save lines for a content_key.
- `Playstead.Export.load_save_revisions/2` added at the `Playstead.Export` context boundary (D-62): calls `Saves.list_lines/2` and `Saves.get_history/2`, builds `SavesPlan.revision_input` maps including `bytes: :present | :missing` via `Playstead.Blobs.exists?/1`.
- `Export.to_layout_input/2` attaches a `:saves` list; the arity-1 default (`[]`) keeps every pre-existing caller and fixture compiling unchanged.
- All three production layout builders fixed: `Export.export_set/3`, and both `Worker.build_layout/1` clauses (`scope: "set"` and `scope: "library"`), with `saves_scope: :none` skipping the saves read entirely.
- `Playstead.Export.SavesLineage`, a pure module with no `Repo`/filesystem/clock dependency, derives a stable `branch_key` as a fork's own revision id -- immutable across replanning runs and never derived from a device name (D-58).
- `save_kind` vocabulary reconciled in one private function: `"battery"` (Saves) maps to `"system_save"` (SavesPlan's drop-in-eligible literal); any other kind passes through unchanged, keeping the drop-in guard structural.
- Extended `round_trip_test.exs` with append-only stability (D-59), re-export idempotency, and cross-user scoping (T-04-21-01) assertions against the real loader.

## Task Commits

1. **Task 1: TRACER -- one real save line's bytes reach a written, verified bag** - `22d92f7` (feat)
2. **Task 2: Stable branch keys, honest kind mapping, and missing bytes** - `433f7e4` (feat)
3. **Task 3: Prove determinism and re-export stability against the real loader** - `8e32347` (test)

**Plan metadata:** (this commit)

## Files Created/Modified

- `playstead-server/lib/playstead/export/saves_lineage.ex` - Pure branch-key derivation (D-58)
- `playstead-server/test/playstead/export/saves_loading_test.exs` - Tracer test: real bytes reach a written, verified bag
- `playstead-server/test/playstead/export/saves_lineage_test.exs` - Unit + integration coverage for branch keys, kind mapping, drop-in eligibility, missing bytes
- `playstead-server/lib/playstead/export.ex` - `load_save_revisions/2`, `to_layout_input/2`, `map_save_kind/1`, `primary_content_key/1`
- `playstead-server/lib/playstead/export/worker.ex` - Both `build_layout/1` clauses now load real saves via `load_saves/3`
- `playstead-server/lib/playstead/saves.ex` - `list_lines/2`
- `playstead-server/test/playstead/export/round_trip_test.exs` - D-59 append-only, re-export idempotency, cross-user scoping tests

## Decisions Made

- `branch_key` = fork root's own immutable UUID, not a derived hash or sequential counter -- `SavesPlan.assign_branch_letters/1` already turns any stable key into a stable letter, so this is the minimal correct choice.
- Multiple save lines for one `content_key` are not merged; only the `("battery", "0")` line is loaded (v1's only shape). Recorded as a disclosed, currently-unreachable limitation in `.planning/WINDOWS.md`.
- `saves_scope: :none` short-circuits before any `Playstead.Saves` call (via `Worker.load_saves/3`), not merely after loading, satisfying the DoS-avoidance mitigation for T-04-21-03.

## Deviations from Plan

None - plan executed exactly as written. The task 2 acceptance-criteria grep for module purity required rewording `SavesLineage`'s moduledoc to avoid literally containing the strings `Playstead.Saves` / `Repo.` / `File.` / `DateTime.utc_now` in prose (the grep is a raw substring match with no context awareness) -- a documentation wording adjustment, not a behavior change.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ROADMAP criterion 4 (real save bytes in a verifiable folder with a readable hash manifest) is now achievable end to end; criterion 5's "export this version" deep link no longer routes into an empty slot.
- Full test suite: 1030 tests, 0 failures (>= 1015 required by this plan's `<verification>`).
- Falsification check passed: removing the `:saves` key from `to_layout_input/2` makes the byte-reading tracer test (and the falsification test itself) go red, confirming the test reads a written file rather than a fixture.
- Remaining phase 04 gap-closure plans (04-22, 04-23) can proceed; no blockers surfaced here.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-06*
