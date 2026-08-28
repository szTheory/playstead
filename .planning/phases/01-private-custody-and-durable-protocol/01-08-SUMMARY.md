---
phase: 01-private-custody-and-durable-protocol
plan: 08
subsystem: infra
tags: [docker, docker-compose, elixir, external_resource, ex_unit, dockerfile]

# Dependency graph
requires:
  - phase: 01-private-custody-and-durable-protocol (plans 01-01 through 01-07)
    provides: The Dockerfile, docker-compose.yml, recovery docs controller, and full application this plan repairs and re-verifies.
provides:
  - A Dockerfile builder stage that stages docs/ before RUN mix compile, so docker compose build succeeds from a clean checkout.
  - PlaysteadWeb.RecoveryDocsController's embedded markdown declared as an @external_resource, so edits to docs/RECOVERY.md force recompilation.
  - Playstead.DockerBuildContextTest — a generic, Docker-daemon-free ExUnit guard that fails mix test if any future compile-time embed is unstaged or staged too late in the Dockerfile.
  - PlaysteadWeb.RecoveryDocsControllerTest — route-level coverage for GET /docs/recovery.
  - A runner-stage fix creating /app/blobs owned by nobody before USER nobody, closing a blob-writability regression found during the Item 2 walkthrough.
  - scripts/compose-smoke.sh extended with a blob-writability assertion, so the OPER-01 evidence path itself catches this regression class.
  - Recorded human verification of the OPER-01 compose smoke path and the deferred UI-SPEC visual walkthrough.
affects: [phase-02 (blob storage — the writable /app/blobs mount point this plan fixed is a direct prerequisite), deployment docs, docker-build-context]

# Actuals (#2632)
actuals:
  tokens: 2243
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@external_resource module attributes are the required pattern for any future compile-time file embed, paired with a Dockerfile COPY that precedes RUN mix compile."
    - "Docker named-volume mount points are created root:root before the container's entrypoint runs; any directory a non-root USER must write into needs an explicit mkdir+chown in the runner stage before the USER directive, not just chown on files copied in from the builder stage."

key-files:
  created:
    - playstead-server/test/playstead/docker_build_context_test.exs
    - playstead-server/test/playstead_web/controllers/recovery_docs_controller_test.exs
  modified:
    - playstead-server/Dockerfile
    - playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex
    - playstead-server/scripts/compose-smoke.sh

key-decisions:
  - "Stage docs/ in the builder stage (not moving RECOVERY.md under priv/, not reading it at runtime) — the compile-time embed design was correct, it was simply never staged; see plan 01-08's objective for the full rejected-alternatives rationale."
  - "The generic build-context guard derives its required set from Application.spec(:playstead, :modules) + __info__(:attributes) rather than a hardcoded resource list, so any future compile-time embed is covered with zero test edits."
  - "Extended scripts/compose-smoke.sh with a blob-writability assertion even though the script is not in this plan's files_modified — a deliberate small addition serving must_have truth #2 (the documented OPER-01 evidence path must itself catch this class of regression), not a scope violation. Recorded as a deviation below."

patterns-established:
  - "Any Dockerfile runner-stage directory a non-root USER must write into (named-volume mount points included) needs its own RUN mkdir -p <dir> && chown nobody <dir> before the USER directive."

requirements-completed: [OPER-01]

coverage:
  - id: D1
    description: "Dockerfile builder stage stages docs/ before RUN mix compile; docker compose build completes past the previously-failing compile step."
    requirement: "OPER-01"
    verification:
      - kind: unit
        ref: "mix compile --force --warnings-as-errors (playstead-server/)"
        status: pass
      - kind: unit
        ref: "test/playstead/docker_build_context_test.exs (generic staging/ordering guard)"
        status: pass
      - kind: integration
        ref: "docker compose build — build log shows `RUN mix compile` step completing (captured below)"
        status: pass
    human_judgment: false
  - id: D2
    description: "PlaysteadWeb.RecoveryDocsController declares @recovery_doc_path as @external_resource so editing docs/RECOVERY.md forces recompilation instead of serving stale content."
    requirement: "OPER-01"
    verification:
      - kind: unit
        ref: "test/playstead/docker_build_context_test.exs (anti-vacuity assertion pinning RecoveryDocsController's resource)"
        status: pass
      - kind: manual_procedural
        ref: "touch docs/RECOVERY.md (content change) → mix compile reports 'Compiling 1 file (.ex)'; reverted, mix compile recompiles again"
        status: pass
    human_judgment: false
  - id: D3
    description: "Generic ExUnit guard (Playstead.DockerBuildContextTest) catches an unstaged or late-staged compile-time resource with no Docker daemon required."
    requirement: "OPER-01"
    verification:
      - kind: unit
        ref: "test/playstead/docker_build_context_test.exs#every in-project @external_resource maps to a builder-stage COPY that precedes the compile step"
        status: pass
      - kind: unit
        ref: "test/playstead/docker_build_context_test.exs#the required set is not vacuously empty"
        status: pass
      - kind: manual_procedural
        ref: "Red-state proof: docs COPY line removed → test failure named docs directory + PlaysteadWeb.RecoveryDocsController (demonstrated, reverted)"
        status: pass
      - kind: manual_procedural
        ref: "Ordering proof: docs COPY line moved after RUN mix compile → same test failure (demonstrated, reverted)"
        status: pass
    human_judgment: false
  - id: D4
    description: "GET /docs/recovery route test proves the served bytes equal docs/RECOVERY.md's live bytes, unauthenticated, text/markdown."
    requirement: "OPER-01"
    verification:
      - kind: unit
        ref: "test/playstead_web/controllers/recovery_docs_controller_test.exs#GET /docs/recovery serves the live docs/RECOVERY.md as markdown, unauthenticated"
        status: pass
    human_judgment: false
  - id: D5
    description: "OPER-01 compose smoke path (docker compose build + scripts/compose-smoke.sh) passes end-to-end on a real Docker host after the fix, including the folded-in /app/blobs writability fix."
    requirement: "OPER-01"
    verification:
      - kind: manual_procedural
        ref: "docker compose build + bash scripts/compose-smoke.sh — verbatim SUCCESS output captured below (post-blobs-fix run)"
        status: pass
    human_judgment: false
  - id: D6
    description: "/app/blobs is created and owned by nobody in the runner stage before USER nobody, and is writable inside the running container; scripts/compose-smoke.sh asserts this on every run going forward."
    requirement: "OPER-01"
    verification:
      - kind: manual_procedural
        ref: "docker compose exec app sh -c 'ls -ld /app/blobs && id' — drwxr-xr-x 2 nobody root ...; uid=65534(nobody)"
        status: pass
      - kind: integration
        ref: "scripts/compose-smoke.sh blob-writability assertion (touch+rm inside app container) — SUCCESS output captured below"
        status: pass
    human_judgment: false
  - id: D7
    description: "UI-SPEC visual fidelity walkthrough across setup wizard, login/sessions/sudo/recovery-login, and Devices queue/list, discharging the second human_verification item from 01-VERIFICATION.md."
    requirement: "OPER-01"
    verification: []
    human_judgment: true
    rationale: "Visual fidelity (dark console surfaces, typography scale, spacing, claimed-vs-observed authority hierarchy on the pairing card per D-09) requires a human eye; VERIFICATION.md records this item as human_judgment: true. Human returned PASS for all three screen groups during this plan's checkpoint, with the specific coverage caveats recorded in the walkthrough record below."

duration: 33min (core execution across three task commits; additional wall time spent in two human checkpoint round-trips)
completed: 2026-08-28
status: complete
---

# Phase 01 Plan 08: OPER-01 Docker Build Gap Closure Summary

**Fixed the Dockerfile's missing `docs/` COPY that broke `docker compose build`, added an `@external_resource`/`mix test`-only regression guard for the whole class of bug, discovered and fixed a second real deployment blocker (`/app/blobs` unwritable) during human verification, and physically re-ran the OPER-01 compose smoke path plus the deferred UI-SPEC walkthrough to PASS.**

## Performance

- **Duration:** 33 min core execution (commit-to-commit span across the three task commits); the plan additionally paused twice for human checkpoint verification (Item 1/Item 2 smoke evidence, then the folded-in blobs fix, then the final UI-SPEC walkthrough verdict).
- **Started:** 2026-08-28T02:57:41Z (first task commit)
- **Completed:** 2026-08-28 (this summary)
- **Tasks:** 3 (Task 1 auto, Task 2 auto/tdd, Task 3 checkpoint:human-verify)
- **Files modified:** 5 (2 created, 3 modified — see Files Created/Modified)

## Accomplishments

- `docker compose build` now completes from a clean checkout: the builder stage stages `docs/` before `RUN mix compile`, closing the `File.Error` that blocked Roadmap SC1 / OPER-01.
- `PlaysteadWeb.RecoveryDocsController` declares its embedded markdown as `@external_resource`, so a stale-content bug (editing `docs/RECOVERY.md` without triggering recompilation) is closed as a side effect.
- A generic, Docker-daemon-free ExUnit guard (`Playstead.DockerBuildContextTest`) now fails `mix test` if any current or future compile-time embedded resource is unstaged, or staged after the compile step, in the Dockerfile — derived from `Application.spec(:playstead, :modules)`, not a hardcoded list.
- Route-level test coverage added for `GET /docs/recovery`.
- A second real deployment blocker — `/app/blobs` unwritable by the runner's `nobody` user because Docker creates named-volume mount points `root:root` — was found by the human during the Item 2 walkthrough, folded into this plan (Dockerfile is in `files_modified`), fixed, and the OPER-01 evidence path (`scripts/compose-smoke.sh`) was extended with a blob-writability assertion so this class of regression is caught automatically going forward.
- Both outstanding `human_verification:` items from `01-VERIFICATION.md` are discharged: the OPER-01 compose smoke run (with the blobs fix) and the UI-SPEC visual walkthrough — both PASS, recorded in detail below.

## Task Commits

Each task was committed atomically:

1. **Task 1: Stage the docs directory in the builder stage and make the embed recompile-aware** - `b6af64e` (fix)
2. **Task 2: Add the ExUnit guard that catches an unstaged compile-time resource without Docker** - `830ab8b` (test)
3. **Task 3 (folded-in deviation): Fix /app/blobs writability regression found during the Item 2 walkthrough** - `c1b2c02` (fix)

**Plan metadata:** (this commit) `docs(01-08): complete OPER-01 gap-closure plan`

_Note: Task 3 itself is `type="checkpoint:human-verify"` with `gate="blocking-human"` and produced no code commit of its own beyond the folded-in blobs fix above; the compose-smoke and UI-SPEC evidence gathered under it is recorded in this SUMMARY per the plan's `<output>` instruction._

## Files Created/Modified

- `playstead-server/Dockerfile` — added `COPY docs docs` before `RUN mix compile` (Task 1); added `RUN mkdir -p /app/blobs && chown nobody /app/blobs` before `USER nobody` in the runner stage (folded-in fix).
- `playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex` — `@recovery_doc_path` bound once, declared `@external_resource`, `@recovery_doc` reads through it; comment extended.
- `playstead-server/test/playstead/docker_build_context_test.exs` — new: `Playstead.DockerBuildContextTest`, the generic build-context regression guard.
- `playstead-server/test/playstead_web/controllers/recovery_docs_controller_test.exs` — new: `PlaysteadWeb.RecoveryDocsControllerTest`, route-level coverage for `/docs/recovery`.
- `playstead-server/scripts/compose-smoke.sh` — added a blob-writability assertion (`docker compose exec app sh -c 'touch /app/blobs/.smoke-write-test && rm ...'`) between the initial health checks and the db-marker-row step.

## Decisions Made

- Chose to stage `docs/` in the builder stage rather than relocate `RECOVERY.md` under `priv/` or read it at runtime — see the plan's `<objective>` for the full rejected-alternatives rationale; unchanged from the plan.
- The build-context guard computes its required resource set generically from compiled module attributes rather than a hardcoded path list, so it covers any future compile-time embed with zero test edits.
- Extended `scripts/compose-smoke.sh` outside this plan's `files_modified` to add the blob-writability check — see Deviations below.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, folded in by explicit human/orchestrator approval] `/app/blobs` unwritable by the runner's `nobody` user**
- **Found during:** Task 3's human verification walkthrough (Item 2, setup wizard) — the readiness panel reported `/app/blobs is not writable: permission denied`.
- **Issue:** The runner stage runs as `USER nobody` but never created `/app/blobs` itself; Docker creates the named-volume mount point `root:root` on first `docker compose up`, so the app process could never write into it. `scripts/compose-smoke.sh` never exercised blob writability, which is why the earlier smoke pass (Item 1, first run) did not catch it.
- **Fix:** Added `RUN mkdir -p /app/blobs && chown nobody /app/blobs` in the Dockerfile's runner stage, before `USER nobody`. `playstead-server/Dockerfile` is listed in this plan's `files_modified`, so this is a straightforward Rule 1 correctness fix within scope, not an architectural change.
- **Files modified:** `playstead-server/Dockerfile`.
- **Verification:** Rebuilt image; `docker compose exec app sh -c 'ls -ld /app/blobs && id'` → `drwxr-xr-x 2 nobody root ... /app/blobs`, `uid=65534(nobody)`. `bash scripts/compose-smoke.sh` SUCCESS with the new blob-writability assertion passing. `mix test` still 295/0 failures.
- **Committed in:** `c1b2c02`.

**2. [Small in-scope addition, explicitly approved] Extended `scripts/compose-smoke.sh` with a blob-writability assertion**
- **Found during:** Same Task 3 walkthrough, immediately after fixing #1 above.
- **Issue:** `scripts/compose-smoke.sh` is the documented OPER-01 evidence path but did not exercise blob writability at all — the exact reason the regression above escaped the first smoke run in this same plan.
- **Fix:** Added `docker compose exec app sh -c 'touch /app/blobs/.smoke-write-test && rm /app/blobs/.smoke-write-test'` (with a `fail` on non-zero exit) after the initial `/healthz`/`/api/v1/capabilities` checks and before the db-marker-row step.
- **Files modified:** `playstead-server/scripts/compose-smoke.sh` — **not** listed in this plan's `files_modified`. Recorded here explicitly as a deviation: a small, narrowly-scoped addition directly serving this plan's own must_have truth #2 ("`bash playstead-server/scripts/compose-smoke.sh` passes end-to-end... db/app/caddy report healthy"), not unrelated scope creep.
- **Verification:** `bash scripts/compose-smoke.sh` SUCCESS, with `[compose-smoke] asserting /app/blobs is writable by the app container's runtime user` / `[compose-smoke] /app/blobs is writable` in the output.
- **Committed in:** `c1b2c02`.

---

**Total deviations:** 2 (1 Rule 1 bug fix, 1 small in-scope script addition), both explicitly approved by the human/orchestrator before implementation.
**Impact on plan:** Both were necessary — the blobs bug is a second, independent OPER-01 deployment blocker (blob storage becomes load-bearing starting Phase 2) that would otherwise have shipped broken; the smoke-script addition closes the exact detection gap that let it through. No unrelated scope creep.

## Issues Encountered

- **Docker base-image pull timeouts:** the first `docker compose build` attempt failed twice with `DeadlineExceeded: context deadline exceeded` fetching `docker.io/library/debian:trixie-...` metadata through `docker compose build`'s bake path. Resolved by pulling both base images directly with `docker pull` first (which succeeded immediately), after which `docker compose build` completed normally from the warmed cache. Not a code or plan defect — a transient registry/build-driver interaction in this environment.
- **Host port conflicts:** ports 80 and 8080 were already bound by other local services on this host, so the compose smoke run used `PLAYSTEAD_HTTP_PORT=18080` / `PLAYSTEAD_HTTPS_PORT=18443` via a git-ignored `playstead-server/.env` (values: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `DATABASE_URL`, `SECRET_KEY_BASE` generated with `mix phx.gen.secret`, `PHX_HOST=localhost`). This is a host-specific port remap only — no code or default-port change — and does not affect the documented default path on a host where 80/443 are free.
- **One flaky test observed, not caused by this plan:** a single `mix test` run showed `Playstead.TlsTrustTest` failing (`transport_state/0 reports :internal_ca once a CA root certificate exists on disk`); it passed both in isolation and on an immediate full-suite rerun, indicating pre-existing async test-isolation flakiness around shared TLS-trust filesystem state, unrelated to this plan's changes. Left untouched per the scope-boundary rule (out-of-scope pre-existing issue, not touched by this plan's files).

## Evidence Captured

### `docker compose build` (post-Task-1 fix) — build log excerpt showing the previously-failing step now completing

```
#22 [builder 14/19] RUN mix compile
#22 1.294 Compiling 82 files (.ex)
#22 4.247 Generated playstead app
#22 DONE 4.3s
...
 Image playstead-server-app Built
```
(Previously: `** (File.Error) could not read file "/app/docs/RECOVERY.md": no such file or directory`.)

### `docker compose build` (post-blobs-fix) — new runner-stage layer

```
#32 [final 7/7] RUN mkdir -p /app/blobs && chown nobody /app/blobs
#32 DONE 0.2s
...
 Image playstead-server-app Built
```

### `bash scripts/compose-smoke.sh` — verbatim output, final post-blobs-fix run (`PLAYSTEAD_HTTPS_PORT=18443`)

```
[compose-smoke] bringing the stack up
 Volume playstead-server_playstead_blobs Creating
 Volume playstead-server_playstead_blobs Created
 Container playstead-server-db-1 Starting
 Container playstead-server-db-1 Started
 Container playstead-server-db-1 Waiting
 Container playstead-server-db-1 Healthy
 Container playstead-server-app-1 Starting
 Container playstead-server-app-1 Started
 Container playstead-server-app-1 Waiting
 Container playstead-server-app-1 Healthy
 Container playstead-server-caddy-1 Starting
 Container playstead-server-caddy-1 Started
[compose-smoke] all services healthy
[compose-smoke] https://localhost:18443/healthz -> 200
[compose-smoke] https://localhost:18443/api/v1/capabilities -> 200
[compose-smoke] asserting /app/blobs is writable by the app container's runtime user
[compose-smoke] /app/blobs is writable
[compose-smoke] recording a marker row so we can prove the volume survives a restart
NOTICE:  relation "compose_smoke_marker" already exists, skipping
[compose-smoke] restarting the stack
 Container playstead-server-db-1 Healthy
 Container playstead-server-app-1 Healthy
 Container playstead-server-caddy-1 Started
[compose-smoke] all services healthy
[compose-smoke] https://localhost:18443/healthz -> 200
[compose-smoke] https://localhost:18443/api/v1/capabilities -> 200
[compose-smoke] re-asserting the playstead_db volume survived the restart
[compose-smoke] playstead_db volume survived restart with 2 marker row(s)
[compose-smoke] SUCCESS
```

### `/docs/recovery` against the running container

```
HTTP/2 200
content-type: text/markdown; charset=utf-8
content-length: 2128

# Locked out? Recovering owner access without email
...
```
Proves the compile-time embedded markdown survived from build → release image → running container.

### In-container blobs ownership proof

```
$ docker compose exec app sh -c 'ls -ld /app/blobs && id'
drwxr-xr-x 2 nobody root 4096 Aug 28 03:29 /app/blobs
uid=65534(nobody) gid=65534(nogroup) groups=65534(nogroup)
```

### Task 2 red-state / ordering proofs (demonstrated, then reverted before committing)

- **Red-state (docs COPY line removed):**
  ```
    1) test compile-time external resources are staged before mix compile every in-project
       @external_resource maps to a builder-stage COPY that precedes the compile step
       (Playstead.DockerBuildContextTest)
       ...
         - PlaysteadWeb.RecoveryDocsController embeds /.../docs/RECOVERY.md (directory `docs`)
           — not staged before RUN mix compile
       2 tests, 1 failure
  ```
- **Ordering proof (docs COPY line moved after RUN mix compile):** identical failure, confirming staging late is treated as broken as not staging at all.
- Both states reverted; final `mix test test/playstead/docker_build_context_test.exs test/playstead_web/controllers/recovery_docs_controller_test.exs` → `3 tests, 0 failures`.
- Full suite: `mix test` → `295 tests, 0 failures`. `mix compile --warnings-as-errors` → exit 0.

## UI-SPEC Walkthrough Record (Item 2, human-verified)

Recorded from the human's own verdict during this plan's checkpoint, per screen group:

- **Setup wizard — PASS.** Walked earlier in this session; this walkthrough is what surfaced the `/app/blobs` readiness warning that led to the folded-in fix (`c1b2c02`). After the fix, `Readiness.summary()` was confirmed to report all three items `:ok`, including "/app/blobs is writable on a named volume."
- **Login / sessions / sudo / recovery-login — PASS.** Human logged in, viewed `/settings/sessions`, and reached `/log-in/recovery` (confirming sudo/route access). The recovery-login helper text ("Enter one of the ten single-use codes you saved at setup.") renders in Inter — judged fine/intended, since it is body copy rather than technical text under the UI-SPEC's typography scale. **Coverage caveat, recorded honestly:** the human did not record their recovery codes at setup, so the recovery-code login flow itself was not hand-exercised; coverage for that flow rests on automated tests (`accounts_recovery_test.exs`, `recovery_login_live_test.exs`), not this visual walkthrough.
- **Devices queue and list — PASS.** `/devices` renders correctly. **Coverage caveat, recorded honestly:** no pending pairing request existed at walkthrough time, so the approval card's claimed-vs-observed visual hierarchy (D-09) was not visually exercised against a live request.

### Follow-up notes surfaced during the walkthrough (recorded only, not implemented — candidates for a later phase)

1. The readiness panel is only rendered inside the setup wizard. After setup completes there is no screen showing server health, so a self-hoster cannot re-check e.g. volume writability without shell access. Suggest a post-setup health/readiness view for a later phase.
2. Recovery codes are shown once at setup with no re-issue path visible to a user who skipped saving them at the time. A sudo-gated regenerate action already exists in code (`POST /settings/recovery-codes/regenerate`, gated behind `[:browser, :require_authenticated, :require_sudo]` in `router.ex`) — but it was not confirmed to be surfaced/discoverable in the console UI during this walkthrough. Worth a follow-up check on UI discoverability, not a missing capability.

## User Setup Required

None — no external service configuration required. (The `playstead-server/.env` used for this plan's smoke verification is git-ignored and host-specific; it is not part of the deliverable and does not need to ship.)

## Next Phase Readiness

- Roadmap SC1 / OPER-01 is true: a self-hoster can run `docker compose up -d` from the documented `docs/DEPLOY.md` path on a host with free ports 80/443 and get a healthy stack with persistent, writable `db` and `blobs` volumes.
- The `/app/blobs` writability fix directly unblocks Phase 2 (blob storage), which starts writing into this volume.
- Both `human_verification:` items from `01-VERIFICATION.md` are discharged with recorded evidence above.
- Follow-up candidates (post-setup readiness view; recovery-code regenerate UI discoverability) are noted for future phase consideration, not blocking.

---
*Phase: 01-private-custody-and-durable-protocol*
*Completed: 2026-08-28*
