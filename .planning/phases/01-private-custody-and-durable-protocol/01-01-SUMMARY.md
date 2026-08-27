---
phase: 01-private-custody-and-durable-protocol
plan: 01
subsystem: infra
tags: [phoenix, liveview, ecto, oban, docker-compose, caddy, rfc9457, problem-json]

requires: []
provides:
  - "Phoenix 1.8 application scaffold in playstead-server/ (domain/web split, Oban, bcrypt_elixir, hammer)"
  - "GET /healthz boolean-only health endpoint (D-16)"
  - "GET /api/v1/capabilities frozen protocol envelope (D-18/D-19 meta-contract)"
  - "GET /setup LiveView console shell (content stub, architecture real)"
  - "RFC 9457 application/problem+json on every /api error path, including unmatched routes and forced exceptions (D-22)"
  - "Docker Compose deployment: db/app/caddy, pinned tags, named volumes playstead_db and playstead_blobs, service_healthy ordering"
  - "Boot-time safety gates: placeholder-secret refusal, minimum-upgradable-version gate, loud migration failure (D-15/D-17)"
  - ".env.example, docs/DEPLOY.md, docs/UPGRADE.md, scripts/compose-smoke.sh"
affects: [01-02, 01-03, 01-04, 01-05, 01-06, 01-07]

actuals:
  tokens: 92000
  tasks: 3
  commits: 3

tech-stack:
  added: [phoenix 1.8.13, phoenix_live_view 1.2.11, ecto_sql 3.14.0, oban 2.24, bcrypt_elixir 3.3, hammer 7.4, postgres 17.2, caddy 2.10]
  patterns:
    - "domain/web split: Playstead.* (contexts, no Phoenix types) vs PlaysteadWeb.* (controllers, LiveView, plugs)"
    - "hand-built RFC 9457 layer (no shipped Phoenix/Plug library exists): Problem.send_problem/5 + ErrorCodes registry + FallbackController for expected tuples + a router-level call/2 wrapper for exceptions/unmatched routes"
    - "boot-time Release-module gates invoked from Application.start/2, gated to Mix.env() == :prod via a compile-time module attribute"
    - "Caddyfile site address derived from a Compose-level ${VAR:-default}, not Caddy's own {$VAR:default}, because Compose always sets a listed environment key (even to empty) and Caddy's fallback only fires on a truly unset variable"

key-files:
  created:
    - playstead-server/lib/playstead/protocol/capabilities.ex
    - playstead-server/lib/playstead_web/controllers/health_controller.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/capabilities_controller.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/fallback_controller.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/debug_controller.ex
    - playstead-server/lib/playstead_web/live/setup_live.ex
    - playstead-server/lib/playstead_web/problem.ex
    - playstead-server/lib/playstead_web/error_codes.ex
    - playstead-server/lib/playstead_web/plugs/api_problem_handler.ex
    - playstead-server/Dockerfile
    - playstead-server/docker-compose.yml
    - playstead-server/Caddyfile
    - playstead-server/.env.example
    - playstead-server/scripts/compose-smoke.sh
    - playstead-server/docs/DEPLOY.md
    - playstead-server/docs/UPGRADE.md
    - playstead-server/test/support/api_case.ex
    - playstead-server/test/playstead_web/controllers/health_controller_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/capabilities_controller_test.exs
    - playstead-server/test/playstead_web/problem_test.exs
    - playstead-server/test/playstead/release_test.exs
  modified:
    - playstead-server/mix.exs
    - playstead-server/lib/playstead/application.ex
    - playstead-server/lib/playstead/release.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/config/config.exs
    - playstead-server/config/test.exs

key-decisions:
  - "Router-level call/2 wrapper (not Plug.ErrorHandler used verbatim) for the RFC 9457 exception path, since Plug.ErrorHandler's mandatory post-handler re-raise is invisible to ConnTest for Phoenix.Router.NoRouteError (Phoenix's own endpoint-level RenderErrors swallows that specific re-raise silently), making the 404 contract test unobservable"
  - "Caddyfile site address is derived via Compose's ${PLAYSTEAD_DOMAIN:-localhost} into a CADDY_SITE_ADDRESS env var, not passed through directly, because Docker Compose always sets a listed environment key (to empty string when unset at the host) and Caddy's own {$VAR:default} substitution only falls back for a truly unset variable — passing PLAYSTEAD_DOMAIN straight through broke Caddy config parsing"
  - "Server-side UUIDv7 generation is out of scope for this plan (resolved in RESEARCH.md open question; deferred to 01-06)"

requirements-completed: [OPER-01, PROT-03]

coverage:
  - id: D1
    description: "docker compose up -d brings up db/app/caddy with pinned tags and named volumes; the stack is reachable over HTTPS end to end (curl /healthz and /api/v1/capabilities through Caddy) and playstead_db survives a down/up-d restart"
    requirement: OPER-01
    verification:
      - kind: integration
        ref: "scripts/compose-smoke.sh (run live against Docker during this task)"
        status: pass
    human_judgment: false
  - id: D2
    description: "GET /api/v1/capabilities publishes the frozen protocol envelope (protocol major/minor, server_build, six capability namespaces) as a meta-contract-frozen key set"
    requirement: PROT-03
    verification:
      - kind: unit
        ref: "test/playstead_web/controllers/api/v1/capabilities_controller_test.exs#GET /api/v1/capabilities returns the frozen envelope"
        status: pass
    human_judgment: false
  - id: D3
    description: "GET /healthz returns boolean-only 200/503 with no component detail leakage"
    verification:
      - kind: unit
        ref: "test/playstead_web/controllers/health_controller_test.exs#GET /healthz returns 200 and no component detail when the app is up"
        status: pass
    human_judgment: false
  - id: D4
    description: "Every /api error path — expected tuples, unmatched routes, and unhandled exceptions — returns application/problem+json with a stable code and a random correlation_id, echoed on x-correlation-id"
    requirement: PROT-03
    verification:
      - kind: unit
        ref: "test/playstead_web/problem_test.exs (5 tests: forced 500, unmatched route 404, correlation_id uniqueness, header/body match, envelope shape)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The application refuses to boot on placeholder SECRET_KEY_BASE/POSTGRES_PASSWORD and on a schema older than the minimum-upgradable floor; migrations run at boot and fail loudly"
    requirement: OPER-01
    verification:
      - kind: unit
        ref: "test/playstead/release_test.exs (6 tests: placeholder rejection x2, acceptance, unset-is-fine, version-floor rejection, version-floor acceptance)"
        status: pass
    human_judgment: false
  - id: D6
    description: "GET /setup renders the real console shell (LiveView architecture, content stub) per the UI-SPEC dark surface"
    verification: []
    human_judgment: true
    rationale: "Visual/UX adequacy of the shell is a human judgment call; plan 01-02 fills the wizard content and is the natural point for a full visual UAT pass"

duration: 55min
completed: 2026-08-27
status: complete
---

# Phase 01 Plan 01: Playstead Server Scaffold, Protocol Spine, and Deployment Gates Summary

**Phoenix 1.8 app deployable via one Docker Compose file over Caddy TLS, with a frozen `/api/v1/capabilities` envelope, RFC 9457 problem+json on every API error path (including forced 500s), and boot-time secret/schema-version safety gates.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 3 (1 tracer + 2 auto)
- **Files created:** 21
- **Files modified:** 6

## Accomplishments

- Scaffolded `playstead-server/` as a Phoenix 1.8 LiveView + Ecto/Postgres application with pinned dependency versions (phoenix 1.8.13, phoenix_live_view 1.2.11, ecto_sql 3.14.0) plus oban, bcrypt_elixir, and hammer added up front so no later plan touches `mix.exs`
- `Playstead.Protocol.Capabilities.envelope/0` is the single owner of the frozen `/api/v1/capabilities` document (protocol major/minor, server_build, six capability namespaces); a contract test freezes the exact key set
- `GET /healthz` is a boolean-only 200/503 endpoint with zero component-detail leakage, backed by a real `SELECT 1` against `Playstead.Repo`
- `GET /setup` mounts the real `PlaysteadWeb.SetupLive` console shell (dark UI-SPEC surface) — the architecture plan 01-02 will fill with wizard steps
- Hand-built the entire RFC 9457 `application/problem+json` layer (no shipped Phoenix/Plug library exists for it): `Problem.send_problem/5`, `ErrorCodes` registry, `FallbackController` for expected error tuples, and a router-level `call/2` wrapper that catches unmatched routes and unhandled exceptions before Phoenix's own HTML/JSON error rendering ever runs — proven with a contract test that forces a real 500
- `docker-compose.yml` ships db/app/caddy with exact pinned image tags (`latest` banned), named volumes `playstead_db`/`playstead_blobs`, `service_healthy` ordering, and host ports published only by `caddy`
- Three boot-time gates in `Playstead.Release` — placeholder-secret refusal, minimum-upgradable-version floor, and loud (non-zero-exit) migration failure — wired into `Application.start/2` for production releases
- `docs/DEPLOY.md`, `docs/UPGRADE.md`, `.env.example`, and `scripts/compose-smoke.sh` give a self-hoster the complete, honest deployment/upgrade path; the smoke script was run live against real Docker during this task and passed, including a restart-and-persist check on `playstead_db`

## Task Commits

1. **Task 1: End-to-end "self-hoster reaches the versioned API over HTTPS" — one path only** - `4731da5` (feat, tracer)
2. **Task 2: RFC 9457 problem+json on every /api error path including forced 500s** - `62be99b` (feat, tdd)
3. **Task 3: Deployment safety gates, environment contract, and the OPER-01 deployment and upgrade docs** - `bcadf3b` (feat)

## Files Created/Modified

- `playstead-server/lib/playstead/protocol/capabilities.ex` - Frozen capabilities envelope owner
- `playstead-server/lib/playstead_web/controllers/health_controller.ex` - Boolean-only `/healthz`
- `playstead-server/lib/playstead_web/controllers/api/v1/capabilities_controller.ex` - Renders the envelope
- `playstead-server/lib/playstead_web/live/setup_live.ex` - `/setup` console shell
- `playstead-server/lib/playstead_web/problem.ex` - `send_problem/5` RFC 9457 renderer
- `playstead-server/lib/playstead_web/error_codes.ex` - Stable machine-code registry
- `playstead-server/lib/playstead_web/plugs/api_problem_handler.ex` - Router-level exception/404 catch for `/api`
- `playstead-server/lib/playstead_web/controllers/api/v1/fallback_controller.ex` - Expected-tuple → problem+json
- `playstead-server/lib/playstead_web/controllers/api/v1/debug_controller.ex` - Dev/test-only forced-500 route
- `playstead-server/lib/playstead/release.ex` - Boot gates + migrate/rollback
- `playstead-server/lib/playstead/application.ex` - Runs boot gates before the supervision tree, prod only
- `playstead-server/docker-compose.yml` - db/app/caddy, pinned, named volumes
- `playstead-server/Caddyfile` - Automatic HTTPS (Let's Encrypt or internal CA)
- `playstead-server/Dockerfile` - Non-root OTP release image
- `playstead-server/.env.example` - Full environment contract with obvious placeholders
- `playstead-server/scripts/compose-smoke.sh` - OPER-01 live evidence path
- `playstead-server/docs/DEPLOY.md`, `docs/UPGRADE.md` - Deploy/upgrade procedures

## Decisions Made

- Used a custom router-level `call/2` wrapper instead of `use Plug.ErrorHandler` verbatim for the RFC 9457 exception/404 path — `Plug.ErrorHandler`'s unconditional post-handler re-raise is by design invisible to `Phoenix.ConnTest` for `Phoenix.Router.NoRouteError`, since Phoenix's own endpoint-level `RenderErrors` deliberately swallows that specific re-raise, making the 404 contract test unobservable through normal `get/2` assertions
- Derived the Caddyfile's site address through a Compose-level `${PLAYSTEAD_DOMAIN:-localhost}` into `CADDY_SITE_ADDRESS`, rather than passing `PLAYSTEAD_DOMAIN` straight through, because Docker Compose always sets a listed environment key (to `""` when unset at the host) and Caddy's own `{$VAR:default}` substitution only falls back for a truly *unset* variable — discovered live while running the compose smoke test
- Server-side UUIDv7 generation intentionally not added in this plan; RESEARCH.md's open question resolves it to "accept and validate client-supplied UUIDv7, never generate" in plan 01-06

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Dockerfile runner image lacked `wget`, breaking the app healthcheck**
- **Found during:** Task 3, running `scripts/compose-smoke.sh` live against Docker
- **Issue:** `docker-compose.yml`'s app healthcheck uses `wget --spider`, but the Debian-trixie-slim runner image installed in the Dockerfile doesn't include `wget`, so the container never reported healthy and `caddy` (which `depends_on: service_healthy`) never started
- **Fix:** Added `wget` to the final-stage `apt-get install` list in `Dockerfile`
- **Files modified:** playstead-server/Dockerfile
- **Verification:** Rebuilt the image; `docker compose ps` showed `app` healthy; full smoke script passed
- **Committed in:** bcadf3b (Task 3 commit)

**2. [Rule 1 - Bug] Caddyfile's env-var fallback silently broke because Compose always sets the key**
- **Found during:** Task 3, running `scripts/compose-smoke.sh` live against Docker
- **Issue:** `docker-compose.yml` passed `PLAYSTEAD_DOMAIN` straight through to the `caddy` service's environment. When unset at the host, Compose sets the container's env var to an explicit empty string (not absent). Caddy's `{$PLAYSTEAD_DOMAIN:localhost}` fallback syntax only substitutes the default for a truly *unset* variable, not an explicitly empty one, so Caddy received an empty site address and failed to parse the Caddyfile (`unrecognized global option: reverse_proxy`), and `caddy` crash-looped
- **Fix:** Introduced `CADDY_SITE_ADDRESS: ${PLAYSTEAD_DOMAIN:-localhost}` in `docker-compose.yml` (Compose's own `${VAR:-default}` treats empty and unset identically) and pointed the Caddyfile at `{$CADDY_SITE_ADDRESS}` instead of `{$PLAYSTEAD_DOMAIN:localhost}`
- **Files modified:** playstead-server/docker-compose.yml, playstead-server/Caddyfile
- **Verification:** `docker run ... caddy adapt` confirmed correct config generation for both an empty and a real domain case; full smoke script passed, including HTTPS reachability and volume persistence across `down`/`up -d`
- **Committed in:** bcadf3b (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs surfaced only by actually running the real Docker Compose stack, not by `mix test`)
**Impact on plan:** Both fixes were necessary for OPER-01's actual "reaches the server over HTTPS" guarantee to hold in practice; no scope creep — both are one-line/one-directive corrections to infrastructure this plan already owned.

## Issues Encountered

None beyond the two deviations above, both caught and fixed by actually running `docker compose up -d` and the smoke script rather than relying on `mix test` alone (per RESEARCH.md's own warning that container orchestration isn't unit-testable in ExUnit).

## User Setup Required

None — no external service configuration required. Local secrets generation is documented in `docs/DEPLOY.md` for when a self-hoster actually deploys.

## Next Phase Readiness

- The protocol spine (`/api/v1`, capabilities envelope, problem+json error layer) is live and contract-tested; plans 01-04 through 01-07 (idempotency, capability negotiation refinement, cursor/snapshot sync) attach directly to it
- `/setup` LiveView route exists as a real shell; plan 01-02 (owner account & setup wizard) fills in the actual step sequence and is the natural point for a full visual UAT pass on the console surface
- Deployment path is proven end-to-end against real Docker, including the restart/persistence guarantee OPER-01 requires
- No blockers for the next plan in this phase

## Self-Check: PASSED

- All 11 spot-checked key files confirmed present on disk
- All 3 task commit hashes (4731da5, 62be99b, bcadf3b) confirmed in `git log`
- `mix compile --warnings-as-errors` exits 0; `mix test` — 19 tests, 0 failures
- Plan-level `<verification>` re-run: compile clean, full suite green, and `scripts/compose-smoke.sh` passed live against real Docker (healthz 200, capabilities 200 through Caddy, forced 500 verified via `problem_test.exs`, `playstead_db` volume survived `docker compose down` + `up -d`)

---
*Phase: 01-private-custody-and-durable-protocol*
*Completed: 2026-08-27*
