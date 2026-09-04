---
phase: 04-persistent-save-continuity
plan: 03
subsystem: infra
tags: [elixir, phoenix, ecto, storage, cas, error-codes, rate-limiting]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "The CAS storage seam (Playstead.Blobs, Playstead.Blobs.Store, LocalDisk), Playstead.Readiness's free-space margin, and the RFC 9457 PlaysteadWeb.ErrorCodes registry, all extended (not replaced) here"
provides:
  - "Additive open_write/2 with reserve: :critical (D-64): a 32 KB save write bypasses only the general required_bytes/2 margin, never the 64 MiB physical floor"
  - "Six registered save-domain problem codes the Mac client and plan 04-04's endpoints key their failure microcopy off (D-13, D-24, D-33)"
  - "save:-namespaced UploadSlots key and RateLimiter key derivation, plus the 8 MiB save-revision size cap, for plan 04-04's saves controller to consume (D-33)"
affects: [04-04, 04-06, 04-07, 04-12]

actuals:
  tokens: 6800
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Default-argument arity expansion (`def open_write(byte_size_hint, opts \\\\ [])`) to satisfy two behaviour callback arities with one function clause, keeping the single-arity call byte-for-byte identical to shipped behaviour"
    - "Named limit-constant/key-derivation functions on the existing context module (Playstead.Blobs) rather than a new module, so a not-yet-built downstream context (plan 04-04's Playstead.Saves) has one place to consume them from"

key-files:
  created:
    - playstead-server/test/playstead/readiness_critical_reserve_test.exs
    - playstead-server/test/playstead_web/error_codes_test.exs
  modified:
    - playstead-server/lib/playstead/readiness.ex
    - playstead-server/lib/playstead/blobs/store.ex
    - playstead-server/lib/playstead/blobs/store/local_disk.ex
    - playstead-server/lib/playstead/blobs.ex
    - playstead-server/lib/playstead_web/error_codes.ex
    - playstead-server/test/playstead/import/session_worker_test.exs

key-decisions:
  - "open_write/2's reserve: :critical branch never calls required_bytes/2 — it reads Readiness.free_bytes/1 directly and applies the new pure fits_critical_free_space?/2, so the physical floor is checked in complete isolation from the general margin formula"
  - "Playstead.Blobs.Store.LocalDiskTest's existing single-arity call sites needed no changes: def open_write(byte_size_hint, opts \\\\ []) generates both open_write/1 and open_write/2 automatically, so the behaviour callback for /1 and /2 are satisfied by one function clause"
  - "Save-lane limit constants (8 MiB cap, save: key derivation, 120/hour rate) were added to Playstead.Blobs rather than a new Playstead.Saves module, since that context does not exist until plan 04-04 and the plan's own file list scoped this task to blobs.ex"
  - "Fixed SessionWorkerTest's InsufficientSpaceStore fake to implement the new open_write/2 callback (Rule 1) to avoid a behaviour-compile warning from the newly required arity"

requirements-completed: [SAVE-01]

coverage:
  - id: D1
    description: "open_write/2 with reserve: :critical bypasses only the general free-space margin, never the 64 MiB physical floor; required_bytes/2 and fits_free_space?/3 are pinned unchanged for three input pairs"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/readiness_critical_reserve_test.exs (13 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The six save-domain problem codes (save_binding_incompatible, save_revision_digest_mismatch, save_revision_too_large, save_parent_unknown, save_branch_limit_exceeded, save_revision_immutable) resolve to their decided statuses and are present in the registry"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead_web/error_codes_test.exs (7 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Save upload concurrency is accounted under a save:-prefixed UploadSlots key, distinct from the same device's import-slot counter; no parallel limiter or slots module was created"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/readiness_critical_reserve_test.exs 'save-lane limits (D-33)' describe block (5 tests, all pass)"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-09-03
status: complete
---

# Phase 4 Plan 03: Critical-Reserve Writes, Save Error Codes, and Namespaced Limits Summary

**Additive `open_write/2` with `reserve: :critical` and a 64 MiB physical floor unblocks 32 KB save uploads that the general free-space margin refused, six save-domain problem codes are registered, and save uploads now count against a `save:`-namespaced slot key reusing Phase 2's shipped concurrency/rate machinery.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-09-04T00:40:00Z
- **Completed:** 2026-09-04T01:00:00Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- `Playstead.Readiness.critical_free_floor_bytes/0` (64 MiB) and `fits_critical_free_space?/2` added as pure, additive functions; `required_bytes/2`'s shipped margin formula is byte-for-byte unchanged and pinned by a three-input-pair test
- `Playstead.Blobs.Store` behaviour and `LocalDisk` gained `open_write/2`: `reserve: :critical` routes to a physical-floor-only check (`critical_space_available?/2`), while `open_write/1` and any other `opts` value remain exactly what ships today — proven by a single function clause using default-argument arity expansion
- `Playstead.Blobs.put_stream/3` threads `opts` through to `open_write/2` so a future save-upload caller can request the critical reserve through the existing facade rather than reaching past it into the store
- Six problem codes (`save_binding_incompatible` 422, `save_revision_digest_mismatch` 422, `save_revision_too_large` 413, `save_parent_unknown` 409, `save_branch_limit_exceeded` 422, `save_revision_immutable` 409) registered in `PlaysteadWeb.ErrorCodes`, with no change to any existing entry
- `Playstead.Blobs` gained named save-lane limit functions (`max_save_revision_bytes/0` = 8 MiB, `save_revision_rate_limit_per_hour/0` = 120, `save_upload_slot_key/1`, `save_revision_rate_limit_key/1`) so plan 04-04's controller has one source of truth instead of restating literals; `Playstead.Import.UploadSlots` and `Playstead.RateLimiter` are reused completely unchanged

## Task Commits

1. **Task 1: Add an additive reserve: :critical write path with a hard physical floor** - `3d62b95` (feat, tdd)
2. **Task 2: Register the six save problem codes** - `bbd1e82` (feat, tdd)
3. **Task 3: Namespace save upload concurrency and rate limits** - `3c36f1a` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `playstead-server/lib/playstead/readiness.ex` - Added `critical_free_floor_bytes/0` and `fits_critical_free_space?/2`; `required_bytes/2`/`fits_free_space?/3` untouched
- `playstead-server/lib/playstead/blobs/store.ex` - Behaviour gained `open_write/2` callback alongside the existing `open_write/1`
- `playstead-server/lib/playstead/blobs/store/local_disk.ex` - `open_write/2` with `reserve: :critical` routing to `critical_space_available?/2`; single-arity call unchanged
- `playstead-server/lib/playstead/blobs.ex` - `put_stream/3` threads `opts` to `open_write/2`; added save-lane limit constants and key-derivation functions
- `playstead-server/lib/playstead_web/error_codes.ex` - Six save-domain codes added to `@registry`
- `playstead-server/test/playstead/import/session_worker_test.exs` - Fake `InsufficientSpaceStore` updated to implement the new `open_write/2` callback
- `playstead-server/test/playstead/readiness_critical_reserve_test.exs` - New: 13 tests covering the critical reserve, the pinned margin formula, and the save-lane limit functions
- `playstead-server/test/playstead_web/error_codes_test.exs` - New: 7 tests covering all six save codes' statuses and registry membership

## Decisions Made
- `critical_space_available?/2` reads `Readiness.free_bytes/1` directly and applies the new `fits_critical_free_space?/2` — it never touches `required_bytes/2`, keeping the physical floor and the general margin as two fully independent checks
- `def open_write(byte_size_hint, opts \\ [])` satisfies both the `open_write/1` and `open_write/2` behaviour callbacks with a single function clause, via Elixir's default-argument arity expansion — no separate `open_write/1` definition was needed
- Save-lane limit constants live on `Playstead.Blobs` (not a new `Playstead.Saves` module, which does not exist until plan 04-04) since the plan's own file scope for this task was `blobs.ex`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated the SessionWorkerTest fake store for the new open_write/2 callback**
- **Found during:** Task 1 (adding `open_write/2` to the `Store` behaviour)
- **Issue:** `test/playstead/import/session_worker_test.exs`'s `InsufficientSpaceStore` implements `@behaviour Playstead.Blobs.Store` with only `open_write/1`; adding a required `open_write/2` callback would leave that fake with a missing-callback compiler warning.
- **Fix:** Changed its `open_write/1` clause to `open_write(_byte_size_hint, _opts \\ [])`, satisfying both arities the same way `LocalDisk` does.
- **Files modified:** `playstead-server/test/playstead/import/session_worker_test.exs`
- **Verification:** `MIX_ENV=test mix compile --warnings-as-errors` produces no warnings; full suite (901 tests) passes
- **Committed in:** `3d62b95` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — behaviour-compile warning)
**Impact on plan:** In scope — a direct, mechanical consequence of extending the `Store` behaviour this task itself declared. No architectural change, no scope creep.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `open_write/2` with `reserve: :critical` is the exact seam plan 04-04's `Playstead.Saves` context will call to write a save-revision blob without being refused by the general margin
- All six save problem codes exist and are status-pinned before any endpoint returns them
- `Playstead.Blobs.save_upload_slot_key/1`, `save_revision_rate_limit_key/1`, `max_save_revision_bytes/0`, and `save_revision_rate_limit_per_hour/0` are ready for plan 04-04's controller and rate-limiting plug to consume directly
- Full `mix test` suite: 164 features, 13 properties, 901 tests, 0 failures
- Ready for 04-04.

## Self-Check: PASSED

- `[ -f playstead-server/lib/playstead/readiness.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead/blobs/store.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead/blobs/store/local_disk.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead/blobs.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead_web/error_codes.ex ]` → FOUND
- `[ -f playstead-server/test/playstead/readiness_critical_reserve_test.exs ]` → FOUND
- `[ -f playstead-server/test/playstead_web/error_codes_test.exs ]` → FOUND
- `git log --oneline --all | grep -q 3d62b95` → FOUND
- `git log --oneline --all | grep -q bbd1e82` → FOUND
- `git log --oneline --all | grep -q 3c36f1a` → FOUND
- All plan-level `<verification>` commands re-run above: PASS (readiness_critical_reserve_test.exs + error_codes_test.exs: 20 tests, 0 failures; readiness_test.exs: 20 tests, 0 failures; full suite: 901 tests, 0 failures)

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-03*
