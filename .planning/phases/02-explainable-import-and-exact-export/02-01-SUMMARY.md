---
phase: 02-explainable-import-and-exact-export
plan: 01
subsystem: infra
tags: [readiness, docker, compose, error-codes, stream_data, test-scaffolding]

requires:
  - phase: 01-private-custody-and-durable-protocol
    provides: "PlaysteadWeb.ErrorCodes/Problem RFC 9457 registry, Playstead.Readiness three-row summary, blob volume mount pattern"
provides:
  - "Seven D-10 import/export problem codes registered in PlaysteadWeb.ErrorCodes"
  - "Playstead.Readiness rows for :inbox, :exports, :blob_volume_atomicity plus public free_bytes/1, required_bytes/2, fits_free_space?/3"
  - "Inbox (:ro) and exports bind mounts wired through Dockerfile, both compose files, .env.example, config/runtime.exs, DEPLOY.md, and the smoke script"
  - "stream_data (test-only) dependency"
  - "Five phase test directories plus the ROM fixture directory and Playstead.ImportFixtures"
affects: [02-02, 02-03, 02-04, 02-05, 02-06, 02-07, 02-08]

actuals:
  tokens: 9040
  tasks: 3
  commits: 3

tech-stack:
  added: ["stream_data ~> 1.1 (test only)"]
  patterns:
    - "Readiness row extension: %{id:, state:, message:} with a live filesystem probe, following the existing volumes_check/1 shape"
    - "mount_device/1 prefix-match against /proc/self/mountinfo for same-filesystem assertions, extending the exact-match anonymous_volume?/1 technique"
    - "Integer-only free-space margin arithmetic (div/2, no floats) verified by a stream_data property test"

key-files:
  created:
    - playstead-server/test/support/fixtures/import_fixtures.ex
    - playstead-server/test/playstead/import/scaffold_test.exs
    - playstead-server/test/playstead_web/error_codes_registry_test.exs
    - playstead-server/test/playstead/import/.keep
    - playstead-server/test/playstead/export/.keep
    - playstead-server/test/playstead/formats/validators/.keep
    - playstead-server/test/playstead/recognition/.keep
    - playstead-server/test/playstead/attention/.keep
    - playstead-server/test/support/fixtures/roms/.keep
  modified:
    - playstead-server/lib/playstead_web/error_codes.ex
    - playstead-server/lib/playstead/readiness.ex
    - playstead-server/lib/playstead_web/live/setup_live.ex
    - playstead-server/mix.exs
    - playstead-server/mix.lock
    - playstead-server/config/runtime.exs
    - playstead-server/Dockerfile
    - playstead-server/docker-compose.yml
    - playstead-server/docker-compose.ci.yml
    - playstead-server/.env.example
    - playstead-server/docs/DEPLOY.md
    - playstead-server/scripts/compose-smoke.sh
    - playstead-server/test/playstead/readiness_test.exs

key-decisions:
  - "Escalated the :exports readiness row to :error (new state value, alongside existing :ok/:warning) rather than :warning, since D-33 requires the export mount to genuinely be writable before any export job can run"
  - "free_bytes/1 shells out to `df -Pk` (POSIX-portable across the Linux release container and macOS dev) rather than adding a NIF, trading strict byte-for-byte statvfs precision for zero new runtime dependencies; required_bytes/2's margin arithmetic is still pure integer math with no floating-point step"
  - "Filtered Playstead.Readiness.summary/1 back down to the original three ids inside SetupLive, since the one-shot wizard's scope is D-04's database/volumes/https question, not the new import/export mounts, which belong on a future console readiness page"

requirements-completed: [IMPT-01, IMPT-03]

coverage:
  - id: D1
    description: "The seven D-10 import/export problem codes resolve to their specified HTTP statuses through the single PlaysteadWeb.ErrorCodes registry"
    requirement: "IMPT-03"
    verification:
      - kind: unit
        ref: "test/playstead_web/error_codes_registry_test.exs"
        status: pass
    human_judgment: false
  - id: D2
    description: "Readiness reports separate rows for inbox readability, export writability, and blob-volume rename atomicity"
    requirement: "IMPT-01"
    verification:
      - kind: unit
        ref: "test/playstead/readiness_test.exs"
        status: pass
    human_judgment: false
  - id: D3
    description: "Free-space margin arithmetic (bytes + max(1 GiB, 5%)) is integer-exact and never underestimates the requested bytes; one byte over the margin is refused"
    requirement: "IMPT-01"
    verification:
      - kind: unit
        ref: "test/playstead/readiness_test.exs#required_bytes/2 and fits_free_space?/3"
        status: pass
    human_judgment: false
  - id: D4
    description: "Container image pre-creates and chowns /app/inbox and /app/exports to the nobody runtime user before USER nobody"
    requirement: "IMPT-01"
    verification:
      - kind: manual_procedural
        ref: "docker build + docker run --entrypoint sh -c 'ls -ld /app/inbox /app/exports' (verified during this plan's execution, not an automated test)"
        status: pass
    human_judgment: true
    rationale: "Ownership was verified manually with a real docker build during execution; no ExUnit test exercises the Docker build/runtime user directly (docker_build_context_test.exs only guards @external_resource staging, not mount-point ownership) -- a human/CI docker-based check should confirm this on the actual deploy path."
  - id: D5
    description: "Compose files, .env.example, and config/runtime.exs agree on the two mounts and all seven new PLAYSTEAD_* configuration values"
    requirement: "IMPT-01"
    verification:
      - kind: other
        ref: "docker compose config (both docker-compose.yml alone and with docker-compose.ci.yml) -- verified during execution, not an ExUnit test"
        status: pass
    human_judgment: false
  - id: D6
    description: "test scaffolding: five phase test directories, ROM fixture directory, and Playstead.ImportFixtures exist and are on the mix test path"
    requirement: "IMPT-03"
    verification:
      - kind: unit
        ref: "test/playstead/import/scaffold_test.exs"
        status: pass
    human_judgment: false

duration: 70min
completed: 2026-08-28
status: complete
---

# Phase 2 Plan 1: Import/Export Deployment Floor Summary

Registered seven D-10 error codes, extended `Playstead.Readiness` with inbox/export/atomicity rows and integer-exact free-space arithmetic, and wired the inbox/exports mounts through the container image, both compose files, `.env.example`, `config/runtime.exs`, `docs/DEPLOY.md`, and the smoke script.

## Performance

- **Duration:** 70 min
- **Tasks:** 3 completed
- **Files modified:** 22 (9 created, 13 modified)

## Accomplishments
- All seven D-10 problem codes (`import_file_too_large` 413, `storage_insufficient` 507, `import_digest_mismatch` 422, `upload_length_required` 411, `import_empty_file` 422, `too_many_uploads` 429, `import_session_too_large` 422) registered in the single `PlaysteadWeb.ErrorCodes` registry, with `stream_data` added as a test-only dependency and the five phase test directories plus `Playstead.ImportFixtures` in place.
- `Playstead.Readiness.summary/1` now returns six rows: the original `:database`/`:volumes`/`:https` plus `:inbox` (read-only probe), `:exports` (writable probe, escalated to `:error` on failure), and `:blob_volume_atomicity` (same-filesystem check for `tmp/` vs `objects/` via `/proc/self/mountinfo`), alongside public `free_bytes/1`, `required_bytes/2`, and `fits_free_space?/3` for D-10's integer-exact free-space rule.
- The inbox (`:ro`) and exports mounts are consistent across the Dockerfile (pre-created, `nobody`-owned mount points), `docker-compose.yml`, `docker-compose.ci.yml`, `.env.example`, `config/runtime.exs` (all seven new env vars, integer/boolean-parsed with a loud raise on malformed values), `docs/DEPLOY.md` (D-40-compliant "not a backup" language), and `scripts/compose-smoke.sh`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Register the seven D-10 problem codes and add the phase's test scaffolding** - `f52c37c` (feat)
2. **Task 2: Extend Readiness with inbox, export, same-volume, and free-bytes checks** - `189e7cd` (feat)
3. **Task 3: Wire the inbox and export mounts through image, compose, env, docs, and the smoke script** - `bcb59c1` (feat)

**Plan metadata:** pending (this commit)

## Files Created/Modified

- `playstead-server/lib/playstead_web/error_codes.ex` - the seven new D-10 codes in the existing `@registry`
- `playstead-server/lib/playstead/readiness.ex` - inbox/exports/blob_volume_atomicity rows, `free_bytes/1`, `required_bytes/2`, `fits_free_space?/3`
- `playstead-server/lib/playstead_web/live/setup_live.ex` - filtered the wizard's readiness panel back to its original three ids
- `playstead-server/mix.exs`, `mix.lock` - `stream_data` test-only dependency
- `playstead-server/config/runtime.exs` - seven new `PLAYSTEAD_*` env vars, parsed and validated
- `playstead-server/Dockerfile` - `/app/inbox`/`/app/exports` pre-created and chowned to `nobody`
- `playstead-server/docker-compose.yml`, `docker-compose.ci.yml` - inbox/exports bind mounts and env vars
- `playstead-server/.env.example` - documents all seven new vars
- `playstead-server/docs/DEPLOY.md` - documents the two new host folders
- `playstead-server/scripts/compose-smoke.sh` - asserts inbox listable-not-writable, exports writable
- `playstead-server/test/support/fixtures/import_fixtures.ex` - `Playstead.ImportFixtures`
- `playstead-server/test/playstead/import/scaffold_test.exs`, `test/playstead_web/error_codes_registry_test.exs`, `test/playstead/readiness_test.exs` - new/extended tests
- Five `.keep`-tracked phase test directories plus `test/support/fixtures/roms/.keep`

## Decisions Made

- `:exports` readiness failures are reported as `:error` (a new third state alongside `:ok`/`:warning`), since D-33 requires the mount to be genuinely writable before any export job can run — unlike the inbox, which is allowed to be a soft `:warning`.
- `free_bytes/1` shells out to `df -Pk` rather than adding a NIF dependency for a raw `statvfs` call; this is portable across the Linux release container and the macOS dev machine, at the cost of KB-granularity rather than byte-granularity precision. `required_bytes/2`'s margin arithmetic itself remains pure integer math (`div/2`, no floats).
- Filtered `Playstead.Readiness.summary/1`'s six rows back down to the original three inside `SetupLive`, since the one-shot setup wizard's job is D-04's database/volumes/https question — the new import/export rows are scoped to a future console readiness page, not this wizard step.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `SetupLive.readiness_label/1` crashed on the new readiness row ids**
- **Found during:** Task 2 verification (full `mix test` run after extending `Readiness.summary/1`)
- **Issue:** `Playstead.Readiness.summary/1` going from three rows to six broke `PlaysteadWeb.SetupLive`, which renders every row from `Readiness.summary/1` and has a `readiness_label/1` function with clauses only for `:database`/`:volumes`/`:https`. This crashed the wizard's readiness step (`FunctionClauseError`) and failed two pre-existing browser tests (`setup_wizard_journey_test.exs`, `states_test.exs`) that assert exactly three readiness rows render.
- **Fix:** Filtered `Readiness.summary/1`'s result down to the original three ids inside `SetupLive.handle_info(:run_readiness_checks, ...)`, since the wizard's scope was never meant to grow with this phase's mount rows.
- **Files modified:** `playstead-server/lib/playstead_web/live/setup_live.ex`
- **Verification:** `mix test test/playstead_web/browser/setup_wizard_journey_test.exs test/playstead_web/browser/states_test.exs` — 20 features, 0 failures; full `mix precommit` — 358 tests, 0 failures.
- **Committed in:** `bcb59c1` (part of Task 3's commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug fix necessary because the task's own change broke an existing feature).
**Impact on plan:** No scope creep — the fix is a one-function filter that preserves the wizard's exact pre-existing behavior while letting `Readiness.summary/1` correctly grow for this phase's other consumers.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None - no external service configuration required. Self-hosters copying `.env.example` to `.env` will see the seven new documented variables with working defaults; no action is required to keep an existing deployment running (a pre-existing deployment's compose file must still be regenerated from the updated `docker-compose.yml` to pick up the new mounts before Phase 2's import/export features are usable, but that is expected future-plan follow-up, not a Phase-2-01 user action).

## Next Phase Readiness

Ready for `02-02`. The single error-code registry, the six-row `Readiness.summary/1` with `free_bytes/1`/`required_bytes/2`/`fits_free_space?/3`, the inbox/exports mounts, and the shared test scaffolding (`Playstead.ImportFixtures`, five test directories, ROM fixture directory, `stream_data`) are all in place for the blob store, import session, and format-validator work the rest of this phase builds.

No blockers.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-28*
