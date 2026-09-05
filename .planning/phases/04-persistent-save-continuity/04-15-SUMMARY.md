---
phase: 04-persistent-save-continuity
plan: 15
subsystem: api
tags: [elixir, ecto, postgres, rate-limiting, upload-concurrency, foreign-key-constraint]

# Dependency graph
requires:
  - phase: 04-persistent-save-continuity
    provides: "04-03's save problem codes and D-33 rate-limit/upload-slot constants, 04-04's commit_revision/3 and two-endpoint save-upload split, 04-05's save lineage DAG"
provides:
  - "resolve_parent/2 scoped to the committing save line, not merely the calling user (CR-01)"
  - "a composite database FK making a cross-save-line parent link unrepresentable, independent of application code"
  - "D-33's save-revision hourly rate limit invoked on the commit path (CR-02)"
  - "D-33's namespaced save-upload concurrency slot applied to the save-upload route, with replay-safe dedup keyed on command_id"
affects: [04-persistent-save-continuity]

actuals:
  tokens: 9500
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Composite FK (id, save_line_id) referencing (id, save_line_id) with MATCH SIMPLE NULL semantics to make a scoping invariant unrepresentable in the schema, not just unwritten by application code"
    - "UploadSlots keyed by (bucket, unique_key) pair rather than a bare counter, so a caller can opt into replay-safe dedup (save route) while a caller needing none keeps identical behavior via a fresh key per call (imports route)"

key-files:
  created:
    - playstead-server/priv/repo/migrations/20260904000005_constrain_revision_parent_to_save_line.exs
    - playstead-server/test/playstead/saves_lineage_scoping_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/saves_limits_test.exs
  modified:
    - playstead-server/lib/playstead/saves.ex
    - playstead-server/lib/playstead/saves/revision.ex
    - playstead-server/lib/playstead/import/upload_slots.ex
    - playstead-server/lib/playstead_web/plugs/upload_concurrency.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex
    - playstead-server/test/playstead/readiness_critical_reserve_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/imports_controller_test.exs

key-decisions:
  - "CR-01's refusal reuses save_parent_unknown (409) rather than minting a new code -- the client cannot distinguish 'id does not exist' from 'id exists but is on a different line', which is deliberate: neither case should leak information about save lines the caller doesn't own or isn't operating on."
  - "The composite FK's ON DELETE changes from the original single-column nilify_all to the default NO ACTION, because a composite SET NULL would null every local column including the NOT-NULL save_line_id. Safe because nothing in this codebase deletes an individual revision -- the only delete path is save_lines' own cascade, which removes parent and child together in one statement, so NO ACTION never sees a dangling reference."
  - "save_revision_parents (04-05's N-way divergence edge table) was deliberately NOT given the same composite-FK treatment. insert_parent_edges/2 only ever writes edges sourced from Branches.heads(user_id, save_line_id), which is already single-line by construction -- there is no code path that can insert a cross-line edge there today. Adding a save_line_id column purely to backstop an invariant the single write path already guarantees was judged not worth the schema churn; flagged here for whoever adds a second write path to that table."
  - "Task 2 replay-safety design point (explicitly called out in the plan): keyed the concurrency slot dedup on command_id rather than releasing on connection teardown. The save-upload route is off :idempotency (D-16, a stream cannot be fingerprinted) but DOES supply a stable per-attempt identifier in the path -- command_id survives a retry of the same upload. UploadSlots.acquire/3 now takes a (bucket, unique_key) pair where re-acquiring an already-held pair is a no-op, so a retried upload never consumes a second slot from the device's 2-slot save budget. The teardown-release alternative was rejected because register_before_send-based release already doesn't fire on an abnormal disconnect for EITHER route (imports or saves) -- that is a separate, pre-existing crash-cleanup gap out of this plan's scope, and fixing only the save route's teardown path would have been an inconsistent partial fix."

requirements-completed: [SAVE-01, SAVE-04]

coverage:
  - id: D1
    description: "A submitted parent_revision_id is accepted only when it belongs to the same save line as the revision being committed, backstopped by a database constraint"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "test/playstead/saves_lineage_scoping_test.exs#commit_revision/3 refuses a cross-save-line parent (CR-01)"
        status: pass
      - kind: unit
        ref: "test/playstead/saves_lineage_scoping_test.exs#a direct Repo.insert bypassing the context is rejected by the DATABASE constraint"
        status: pass
    human_judgment: false
  - id: D2
    description: "D-33's save-revision hourly rate limit is invoked on the commit path and refuses an over-budget device"
    requirement: "SAVE-04"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/saves_limits_test.exs#the save-revision rate limit is enforced on the commit path (D-33/CR-02)"
        status: pass
    human_judgment: false
  - id: D3
    description: "D-33's namespaced save-upload concurrency slot is applied to the save-upload route, replay-safe against a retried command_id"
    requirement: "SAVE-04"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/saves_limits_test.exs#the save-upload concurrency slot is namespaced and applied (D-33/CR-02)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 15: Gap Closure -- CR-01 Lineage Scoping and CR-02 Save-Lane Limits Summary

**Scoped a revision's parent to its own save line (app + DB composite FK) and wired D-33's previously-inert rate limit and namespaced upload slot into the save commit/upload paths.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-04T22:15:00Z
- **Completed:** 2026-09-04T23:10:00Z
- **Tasks:** 2
- **Files modified:** 11 (3 created, 8 modified)

## Accomplishments

- `Saves.resolve_parent/2` now scopes a submitted `parent_revision_id` to the save line being committed to (threaded from the already-resolved `line` in `commit_revision/3`'s `Ecto.Multi`), not merely to the calling user. A cross-line parent -- same user or different -- is refused with the existing `save_parent_unknown` (409) code.
- Migration `20260904000005` backstops the same rule in Postgres: a unique index on `save_revisions (id, save_line_id)` plus a composite FK on `(parent_revision_id, save_line_id)` referencing that pair makes a cross-line link unrepresentable even via a direct `Repo.insert` that bypasses `Saves` entirely. The migration detects and loudly aborts on any pre-existing violating row rather than silently repairing or dropping (history is append-only).
- `SavesController.create_revision/2` now calls `Playstead.RateLimiter.hit/3` against `Blobs.save_revision_rate_limit_key/1` before committing, refusing a device's 121st save revision in an hour with the registered `rate_limited` (429) code -- the first production call site for that constant outside its own tests.
- The save-upload route now runs through a new `:save_upload_concurrency` pipeline gated on `Blobs.save_upload_slot_key/1`'s `"save:"`-namespaced budget, so a save upload never contends with a concurrent game import for the same device.
- `Playstead.Import.UploadSlots` was extended to dedupe acquire/release by a `(bucket, unique_key)` pair: the save route's plug instance keys that dedupe on the path's `command_id`, so a retried upload (the route is deliberately off `:idempotency` per D-16) never consumes a second slot from the device's 2-slot save budget. The imports route passes a fresh key per call, so its existing behavior is unchanged.

## Task Commits

1. **Task 1: CR-01 -- a parent revision must belong to the same save line** - `0a716f6` (fix)
2. **Task 2: CR-02 -- make the D-33 save-lane limits actually apply** - `2f2f2ac` (fix)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `playstead-server/priv/repo/migrations/20260904000005_constrain_revision_parent_to_save_line.exs` - composite FK + violating-row detection
- `playstead-server/test/playstead/saves_lineage_scoping_test.exs` - drives `commit_revision/3` and a direct `Repo.insert` to prove enforcement at both layers
- `playstead-server/test/playstead_web/controllers/api/v1/saves_limits_test.exs` - drives the real upload/commit endpoints, asserting refusals for over-budget rate limit, oversized declared length, concurrency cap, and no-leak/no-double-consume on retry
- `playstead-server/lib/playstead/saves.ex` - `resolve_parent/2` scoped to `save_line_id`
- `playstead-server/lib/playstead/saves/revision.ex` - `foreign_key_constraint/3` renamed to match the new composite FK constraint name
- `playstead-server/lib/playstead/import/upload_slots.ex` - `acquire/3` + `release/2` with dedup-key semantics
- `playstead-server/lib/playstead_web/plugs/upload_concurrency.ex` - `:bucket_fn` + `:dedupe_param` options
- `playstead-server/lib/playstead_web/router.ex` - `:save_upload_concurrency` pipeline, wired into the save-upload route
- `playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex` - `check_revision_rate_limit/1` before `run_idempotent/5`
- `playstead-server/test/playstead/readiness_critical_reserve_test.exs` - updated to the new `UploadSlots` arity (pre-existing constant-shape test, arity-fixed only, not otherwise changed)
- `playstead-server/test/playstead_web/controllers/api/v1/imports_controller_test.exs` - updated to the new `UploadSlots` arity

## Decisions Made

See `key-decisions` in frontmatter. In short: reused `save_parent_unknown` rather than a new code; chose `NO ACTION` over the original `nilify_all` for the composite FK's `ON DELETE` (a composite `SET NULL` cannot work against a `NOT NULL` `save_line_id`, and it's unneeded since parent+child always cascade-delete together); left `save_revision_parents` unconstrained because its single write path is already line-scoped by construction; and keyed the save-upload concurrency dedup on `command_id` rather than pursuing connection-teardown release, since the latter doesn't fix the actually-reachable replay scenario and would have left an inconsistent partial fix for a separate, pre-existing crash-cleanup gap shared by both upload routes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed two pre-existing test call sites broken by the `UploadSlots` API change**
- **Found during:** Task 2
- **Issue:** `UploadSlots.acquire/2` and `release/1` were changed to `acquire/3`/`release/2` to support dedup keys (needed for CR-02's replay-safety design point). Two existing test files called the old 2-arity/1-arity functions directly: `test/playstead/readiness_critical_reserve_test.exs` (a pre-existing 04-03 constant-shape test for the save/import slot namespace split) and `test/playstead_web/controllers/api/v1/imports_controller_test.exs` (the imports concurrency-cap test).
- **Fix:** Updated both call sites to the new arity with distinct dedup keys per held slot, preserving identical test semantics (same number of slots held/released, same assertions).
- **Files modified:** `test/playstead/readiness_critical_reserve_test.exs`, `test/playstead_web/controllers/api/v1/imports_controller_test.exs`
- **Verification:** Both files pass; full suite confirmed no other call sites of the old arity existed.
- **Committed in:** `2f2f2ac` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking).
**Impact on plan:** Necessary compile/test fix caused directly by the `UploadSlots` API change this task made; no scope creep, no behavior change to the imports lane.

## Issues Encountered

The full `mix test` run intermittently failed a single Wallaby browser feature test (`PlaysteadWeb.Browser.SetupWizardJourneyTest`, "first run: token -> ... -> recovery login") -- this is the exact pre-existing flake named in this plan's own testing notes. Confirmed by re-running that file in isolation (passes, 1/1). The full suite otherwise reports 1010 tests / 0 failures, above the 995-test baseline. An earlier attempt to run the full suite twice also hit unrelated environmental issues (a stale backgrounded `beam.smp` process holding port 4000 from a prior interrupted run, and a subsequent Postgres crash-recovery cycle triggered by force-killing that stale process) -- both were transient host-state artifacts of this session's own tooling, not caused by any code change in this plan, and were resolved before the final clean run.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

CR-01 and CR-02 are annotated as fixed in `04-REVIEW.md` with their commit hashes. The phase review's remaining open items (MC-01..MC-04 Mac-side wiring gaps, and the WR/WS warnings) are out of this plan's scope -- this plan closed only the two server-side Critical findings it was scoped to.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*

## Self-Check: PASSED

All key files verified present on disk; both task commits (`0a716f6`, `2f2f2ac`) verified in `git log`; both new test files pass in isolation and as part of the full suite (1010 tests / 0 non-flake failures, above the 995 baseline).
