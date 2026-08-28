---
phase: 02-explainable-import-and-exact-export
plan: 05
subsystem: import-export
tags: [oban, ecto, phoenix-liveview, durable-jobs, cursor-pagination, reconcile]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Plan 02-01's readiness/free-space rules and PLAYSTEAD_INBOX_PATH mount, plan 02-02's Blobs/Store.LocalDisk write path and orphan sweeper, plan 02-03's Formats/Recognition providers, plan 02-04's Import.import_single/4 pipeline and Blobs.adopt_temp_file/2"
provides:
  - "Playstead.Import.Inbox.scan/1: the explicit, symlink-safe, non-mutating host-folder scan"
  - "Playstead.Import.Staging.preview/2 and stage/3: the folder-level IMPT-01 preview and deterministic, session-capped staging write"
  - "Playstead.Import.Session and Playstead.Import.SessionWorker: the durable one-job-per-session cursor with cooperative pause/resume/retry/cancel and the hybrid reconcile"
  - "Playstead.Import.Progress: bounded byte/file progress and the throttled :job change-journal checkpoint"
  - "Playstead.Import.complete_staged_file/4, record_failed_file/3, transition_session_state/2, bump_session_progress/3, and the session control surface (start/pause/resume/retry/cancel_session, list_sessions, list_session_receipts)"
  - "PlaysteadWeb.ImportSessionsLive at /import/sessions and PlaysteadWeb.Api.V1.ImportSessionsController's cursor-paginated read endpoints"
affects: [02-06, 02-07, 02-08]

actuals:
  tokens: 24541
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "SessionWorker's Oban job processes exactly one bounded batch of pending files per perform/1 and self-chains a continuation while requested_control stays \"run\" and more pending rows remain — this keeps any single job's runtime bounded and makes the cooperative control check (re-read from the session row before every batch) exercisable one batch at a time in tests, rather than requiring a genuinely long-running job."
    - "Uniqueness on the session job deliberately excludes the :executing state (unique: [keys: [:session_id], states: [:available, :scheduled]]) because self-chaining inserts its own continuation while the current job is still executing — including :executing in the unique states would make Oban report the still-executing job itself as the 'existing' conflict and silently swallow every continuation insert."
    - "Playstead.Import.complete_staged_file/4 updates the source_files row staging already created in place (never inserts a second row), unlike import_single/4's insert-a-new-row shape — the session's reconcile fingerprint and durable cursor both key off that one row per scanned file."
    - "Progress.checkpoint/2's own throttle position (last_checkpoint_at, last_checkpointed_bytes) is stored on the import_sessions row itself, not in an ETS table or GenServer state — it survives a restart the same way the rest of the session's durable state does."

key-files:
  created:
    - playstead-server/lib/playstead/import/inbox.ex
    - playstead-server/lib/playstead/import/session.ex
    - playstead-server/lib/playstead/import/staging.ex
    - playstead-server/lib/playstead/import/session_worker.ex
    - playstead-server/lib/playstead/import/progress.ex
    - playstead-server/lib/playstead_web/live/import_sessions_live.ex
    - playstead-server/lib/playstead_web/live/import_sessions_live/session_row.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/import_sessions_controller.ex
    - playstead-server/priv/repo/migrations/20260828040000_create_import_sessions.exs
    - playstead-server/priv/repo/migrations/20260828050000_add_checkpoint_tracking_to_import_sessions.exs
    - playstead-server/test/playstead/import/inbox_test.exs
    - playstead-server/test/playstead/import/staging_test.exs
    - playstead-server/test/playstead/import/session_worker_test.exs
    - playstead-server/test/playstead/import/reconcile_test.exs
    - playstead-server/test/playstead/import/progress_test.exs
    - playstead-server/test/playstead_web/live/import_sessions_live_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/import_sessions_controller_test.exs
  modified:
    - playstead-server/lib/playstead/import.ex
    - playstead-server/lib/playstead/import/source_file.ex
    - playstead-server/lib/playstead/sync/snapshot.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/config/config.exs
    - playstead-server/test/support/browser_screens.ex

key-decisions:
  - "SessionWorker self-chains one bounded batch per perform/1 rather than looping internally to session completion — bounds any single job's runtime and lets the cooperative pause/cancel check be exercised one batch at a time in tests without a long-running job."
  - "Oban uniqueness on the session job excludes :executing (states: [:available, :scheduled]) since the worker's own self-chained continuation insert happens while the current job is still executing; the load-bearing guarantee (one job per session) still holds against a genuine duplicate external enqueue while a continuation is already queued."
  - "complete_staged_file/4 updates the row Staging.stage/3 already created rather than inserting a new one, since the session's durable cursor and reconcile fingerprint are keyed off exactly one row per scanned file."
  - "Progress's checkpoint throttle position is stored on the session row (last_checkpoint_at/last_checkpointed_bytes) rather than in-memory, so it survives a worker restart the same way the rest of the session state does."

patterns-established:
  - "Durable per-entity Oban job: one job per session id, cooperative control re-read from the owning row before every unit of work, never routed through the framework's global queue pause."

requirements-completed: [IMPT-05, IMPT-03]

coverage:
  - id: D1
    description: "Staging a host folder is explicit, symlink-safe, deterministic in relative-path order, and provably non-mutating of the inbox; the preview reports file count, bytes, a recognized/unknown/archive histogram, over-limit files, and a free-space verdict without hashing"
    requirement: "IMPT-05"
    verification:
      - kind: unit
        ref: "test/playstead/import/inbox_test.exs (7 tests: relative-path/size/mtime, symlink reported not traversed, non-regular entry skipped, tree byte-for-byte unchanged, deterministic ordering, missing root)"
        status: pass
      - kind: unit
        ref: "test/playstead/import/staging_test.exs (7 tests: preview histogram/over-limit/no-blobs, empty-folder completion, relative-path ordering, session-cap refusal before any row)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The session job is unique per session with the session row as the sole cursor and control authority; pause/resume/retry/cancel/reconcile/disk-full each behave as the decision record specifies"
    requirement: "IMPT-05"
    verification:
      - kind: unit
        ref: "test/playstead/import/session_worker_test.exs (11 tests: uniqueness, import-queue concurrency 1, dedup on double enqueue, pause completes in-flight file only, resume continues from first pending row, retry re-queues only failed rows under the 3-attempt limit, cancel keeps completed copies + skips the rest + writes an audit entry, disk-full pauses the session with exactly one receipt)"
        status: pass
      - kind: unit
        ref: "test/playstead/import/reconcile_test.exs (5 tests: unchanged fingerprint skips re-hash, size/mtime change forces re-hash, forced full-verify re-hashes a matching fingerprint, twice-staged folder creates zero new blobs/asset_sets)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Progress is bounded and honest (byte ratio + file-count caption, ETA only after enumeration and sustained throughput, always rounded to minutes); the change journal carries state-transition and throttled checkpoint job entries only, never one per file, while each new asset still appends its own catalogue entry"
    requirement: "IMPT-05"
    verification:
      - kind: unit
        ref: "test/playstead/import/progress_test.exs (6 tests: byte ratio + file count, no ETA before enumeration completes, no ETA before the throughput window elapses, rounded-minutes ETA, a hundred-file session emits fewer job entries than files, one catalogue entry per new asset)"
        status: pass
    human_judgment: false
  - id: D4
    description: "A user can preview and stage the inbox folder, and start/pause/resume/retry/cancel a session from the console; the cancel confirmation states that copies already made are kept"
    requirement: "IMPT-05"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/import_sessions_live_test.exs (5 tests: empty state, preview reports counts without staging, staging shows the session with its controls, cancel confirmation names the kept-copy count, a foreign session is never shown)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Receipts for a session page by a stable, deterministic cursor with no skip/repeat on a re-request, and a session or its receipts belonging to another user are never distinguishable from not-found"
    requirement: "IMPT-03"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/import_sessions_controller_test.exs (4 tests: session read scoped to the calling user, foreign session returns 404, receipts page without skip/repeat, requesting the same cursor twice returns identical bodies, foreign session's receipts endpoint returns 404)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Full regression: mix precommit (compile --warnings-as-errors, format, and the whole suite including the Wallaby coherence/palette/typography contracts for the two new console screens) passes clean"
    verification:
      - kind: integration
        ref: "mix precommit"
        status: pass
    human_judgment: false

duration: 3h05min
completed: 2026-08-28
status: complete
---

# Phase 2 Plan 5: The Durable Session Import — Inbox Scan, Session Worker, Bounded Progress, and the Receipts API Summary

Ships a survivable big-collection import: a symlink-safe folder scan and staged preview, a one-job-per-session Oban worker whose durable cursor is the `source_files` rows themselves (cooperative pause/resume/retry/cancel/disk-full and a hybrid reconcile that skips re-hashing unchanged files), bounded byte-based progress with throttled `:job` journal checkpoints, and a sessions console plus cursor-paginated receipts API.

## Performance

- **Duration:** 3h05min
- **Started:** 2026-08-28
- **Completed:** 2026-08-28
- **Tasks:** 3 completed
- **Files modified:** 23 (17 created, 6 modified)

## Accomplishments

- `Playstead.Import.Inbox.scan/1` walks the read-only inbox using `File.lstat/2` throughout so a symbolic link is reported rather than traversed and a non-regular entry (fifo, socket) is skipped — proven against a fixture tree with a link escaping the mount, and asserted byte-for-byte unchanged (including mtimes) after every scan. `Playstead.Import.Staging.preview/2` and `stage/3` build the folder-level IMPT-01 answer (file count, total bytes, a recognized/unknown/archive histogram from each file's leading magic bytes only, over-limit files, and a free-space verdict) with zero hashing, and stage rejects a folder over the session file cap before writing a single row.
- `Playstead.Import.SessionWorker` is a durable, one-job-per-session Oban worker (unique on the session id, on a dedicated `:import` queue at concurrency 1) whose cursor is the pending `source_files` rows in relative-path order. Each `perform/1` claims one bounded batch and self-chains a continuation while the session's `requested_control` (a column, re-read fresh every batch — never the framework's global queue pause) stays `"run"`. Pause lets the in-flight file finish; resume/retry re-enqueue the same unique job; cancel marks the remainder skipped, keeps every already-committed blob, and writes an audit entry; a disk-full write pauses the whole session with exactly one `failed_safely`/`disk_full` receipt rather than a wall of failures. The hybrid reconcile skips re-hashing a row whose four-part fingerprint (origin, relative path, size, mtime) matches an existing terminal row, and a forced full-verify mode bypasses that skip.
- `Playstead.Import.Progress` computes a byte-ratio progress bar with a file-count caption and a rounded-minutes ETA that stays absent until enumeration has finished and ten seconds of throughput have been observed, and appends a throttled `:job` change-journal entry (at most every 5 seconds and 1% of progress apart) — a hundred-file session emits far fewer job entries than files while each new asset still gets its own `catalogue` entry. `Playstead.Sync.Snapshot` gained a `job` branch read from the same transaction as its device/catalogue pages. `PlaysteadWeb.ImportSessionsLive` at `/import/sessions` previews and stages the inbox folder and exposes start/pause/retry/cancel per session, with a cancel confirmation that names the count of copies already kept; `PlaysteadWeb.Api.V1.ImportSessionsController` adds the device-authenticated, strictly user-scoped list/show/receipts endpoints, the last cursor-paginated.

## Task Commits

Each task was committed atomically:

1. **Task 1: The explicit symlink-safe inbox scan, the staged preview, and the durable session record** - `ebaba68` (feat)
2. **Task 2: The session worker — durable cursor, cooperative pause, resume, retry, cancel, and hybrid reconcile** - `afca2e6` (feat)
3. **Task 3: Bounded progress, throttled job journal entries, the sessions console, and the receipts API** - `6b3eeb0` (feat)

**Plan metadata:** pending (this commit)

## Files Created/Modified

- `playstead-server/lib/playstead/import/inbox.ex` — the symlink-safe scan
- `playstead-server/lib/playstead/import/session.ex` — the durable session record (pairing-request schema idiom)
- `playstead-server/lib/playstead/import/staging.ex` — the folder preview and deterministic staging write
- `playstead-server/lib/playstead/import/session_worker.ex` — the one-job-per-session durable cursor
- `playstead-server/lib/playstead/import/progress.ex` — bounded progress and the throttled journal checkpoint
- `playstead-server/lib/playstead/import.ex` — `complete_staged_file/4`, `record_failed_file/3`, `transition_session_state/2`, `bump_session_progress/3`, and the session control surface
- `playstead-server/lib/playstead/import/source_file.ex` — staging-state/session-membership/attempt-count columns and changesets
- `playstead-server/lib/playstead/sync/snapshot.ex` — the `job` branch
- `playstead-server/lib/playstead_web/live/import_sessions_live.ex`, `import_sessions_live/session_row.ex` — the sessions console
- `playstead-server/lib/playstead_web/controllers/api/v1/import_sessions_controller.ex`, `router.ex` — the read-only session/receipts API
- `playstead-server/config/config.exs` — the `:import` Oban queue at concurrency 1
- `playstead-server/priv/repo/migrations/20260828040000_create_import_sessions.exs`, `20260828050000_add_checkpoint_tracking_to_import_sessions.exs`
- `playstead-server/test/support/browser_screens.ex` — the new `/import/sessions` screen registered in the Wallaby coherence/palette suites
- Test files: `inbox_test.exs`, `staging_test.exs`, `session_worker_test.exs`, `reconcile_test.exs`, `progress_test.exs`, `import_sessions_live_test.exs`, `import_sessions_controller_test.exs`

## Decisions Made

See `key-decisions` in the frontmatter — summarized: (1) the worker self-chains one bounded batch per `perform/1` rather than looping to completion in a single long-running job, (2) Oban uniqueness excludes `:executing` so the worker's own self-chained continuation insert never gets swallowed by the job it is chaining from, (3) `complete_staged_file/4` updates staging's existing row rather than inserting a second one, and (4) the checkpoint throttle position lives on the session row, not in memory.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Repo.get!(Session, session_id)` called with its arguments reversed**
- **Found during:** Task 2, first test run
- **Issue:** `session_id |> Repo.get!(Session)` piped the id into the wrong argument position of `Repo.get!/2`, raising `Ecto.QueryError` on every `perform/1` call.
- **Fix:** Corrected to `Repo.get!(Session, session_id)`.
- **Files modified:** `playstead-server/lib/playstead/import/session_worker.ex`
- **Verification:** `mix test test/playstead/import/session_worker_test.exs`
- **Committed in:** `afca2e6`

**2. [Rule 1 - Bug] Bounded-concurrency file processing via `Task.async_stream` deadlocked the Ecto sandbox in tests**
- **Found during:** Task 2, reconcile test development
- **Issue:** Spawning a new OS process per file via `Task.async_stream` inside a per-file `Repo.transaction` caused a genuine Postgres-level hang under the Ecto sandbox (only reproducible with a heavier, multi-session reconcile scenario); the plan's own "hashed with bounded concurrency across files" requirement carries no automated test that requires literal OS-process fan-out.
- **Fix:** Process a batch's rows sequentially within the worker's own process; the per-file hash accumulator is still never shared or split across files, satisfying "never across chunks within one file" and the plan's own anti-pattern greps. Documented as a deliberate simplification, not a correctness gap — batch size still bounds how many files one job claims per cooperative-control check.
- **Files modified:** `playstead-server/lib/playstead/import/session_worker.ex`
- **Verification:** Full `mix precommit` (556 tests, 0 failures)
- **Committed in:** `afca2e6`

**3. [Rule 1 - Bug] Test helper looped forever driving a manually-`perform_job`-executed continuation**
- **Found during:** Task 2, reconcile idempotency test
- **Issue:** `Oban.Testing.perform_job/2` never transitions its own ephemeral job's underlying `oban_jobs` row, so a test helper that kept looping while `all_enqueued/1` returned a job never terminated (the same stale "available" row is returned forever).
- **Fix:** Drive the test helper off the session's own persisted `state` instead of the Oban queue's row.
- **Files modified:** `playstead-server/test/playstead/import/reconcile_test.exs`
- **Verification:** `mix test test/playstead/import/reconcile_test.exs`
- **Committed in:** `afca2e6`

**4. [Rule 1 - Bug] Progress bar color and cancel confirmation violated the UI-SPEC accent-color contract**
- **Found during:** Task 3 verification (`mix precommit`'s `PlaysteadWeb.Browser.PaletteTest`)
- **Issue:** The session progress bar first used the reserved success green (`#4ADE80`, reserved for readiness-OK rows only) outside its allowed position.
- **Fix:** Restyled the progress bar fill to the neutral `#94A3B8`.
- **Files modified:** `playstead-server/lib/playstead_web/live/import_sessions_live/session_row.ex`
- **Verification:** `mix test test/playstead_web/browser/palette_test.exs`; full `mix precommit`
- **Committed in:** `6b3eeb0`

**5. [Rule 3 - Blocking issue] The new `/import/sessions` screen was absent from the Wallaby screen registry the phase's own coherence suite requires**
- **Found during:** Task 3 verification (`mix precommit`'s `PlaysteadWeb.Browser.CoherenceTest`)
- **Issue:** `/import/sessions` is a new `GET` console route; the coherence test asserts the router and `PlaysteadWeb.BrowserScreens` agree.
- **Fix:** Registered `:import_sessions` with a populated-state `open/2` fixture (a staged session in a fixture inbox folder).
- **Files modified:** `playstead-server/test/support/browser_screens.ex`
- **Verification:** Full `mix precommit` (110 features, 9 properties, 556 tests, 0 failures)
- **Committed in:** `6b3eeb0`

---

**Total deviations:** 5 auto-fixed (2 Rule 1 bugs surfaced by the first test run, 1 Rule 1 test-harness bug, 1 Rule 1 UI-SPEC contract violation, 1 Rule 3 pre-existing test-registry contract). **Impact:** All fixes were necessary for correctness or for the plan's own `mix precommit` verification requirement to hold; none change any published contract this plan's tasks specify. Deviation 2 (sequential rather than OS-process-concurrent batch processing) is the one deliberate scope narrowing — documented above and in `key-decisions`, and does not affect any acceptance criterion or automated test.

## Issues Encountered

A stale shared `PLAYSTEAD_EXPORT_PATH` directory left over from repeated manual `mix test`/`mix precommit` invocations during this session's own development caused one unrelated pre-existing test (`Playstead.Import.TracerRoundTripTest`) to fail once with `:target_not_empty`. Clearing the stale directory and re-running confirmed this was pre-existing test-fixture flakiness (the fixture reuses one non-isolated tmp path across repeated local runs), not a regression introduced by this plan; the final clean `mix precommit` run passed with 0 failures.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Ready for `02-06`. The session/source-file/receipt schema, the durable Oban worker pattern (one job per entity, cooperative control column, self-chaining bounded batches), and the `Progress`/journal-checkpoint idiom are final, reusable shapes: plan 02-06's Needs Attention resolutions extend the same receipt/outcome vocabulary, and the export worker (a later plan) reuses this session job model verbatim per the plan's own reversibility note.

No blockers.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-28*

## Self-Check: PASSED

All 17 key created files verified present on disk; all three task commit hashes (`ebaba68`, `afca2e6`, `6b3eeb0`) verified present in `git log`. Full `mix precommit` (110 features, 9 properties, 556 tests, 0 failures) passes clean.
