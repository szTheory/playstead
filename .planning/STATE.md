---
gsd_state_version: 1.0
current_phase: 02
current_phase_name: Explainable Import and Exact Export
status: executing
stopped_at: Completed 02-02-PLAN.md
last_updated: "2026-08-28T18:55:03.114Z"
last_activity: 2026-08-28
last_activity_desc: Phase 02 execution started
state_head: dc11aeb0c1a24695140d5f4b11b291c6c5a32931
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 16
  completed_plans: 10
  percent: 20
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-08-28)

**Core value:** A locally available game and its progress remain effortless to play, safe, understandable, synchronized, and fully under the user's control.
**Current focus:** Phase 02 — Explainable Import and Exact Export

## Current Position

Phase: 02 (Explainable Import and Exact Export) — EXECUTING
Plan: 3 of 8
Status: Ready to execute
Last activity: 2026-08-28 — Phase 02 execution started

Progress: [████████████████████] 8/8 plans ([██░░░░░░░░] 20%) — Phase 1 complete; Phase 2 not yet planned

## Performance Metrics

**Velocity:**

- Total plans completed: 8
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| — | — | — | — |
| 01 | 8 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 55 min | 3 tasks | 27 files |
| Phase 01 P02 | 70min | 2 tasks | 29 files |
| Phase 01-private-custody-and-durable-protocol P03 | 90 min | 2 tasks | 31 files |
| Phase 01 P04 | 55min | 3 tasks | 22 files |
| Phase 01 P05 | 45min | 2 tasks | 10 files |
| Phase 01 P06 | 80min | 3 tasks | 28 files |
| Phase 01 P07 | 65min | 3 tasks | 17 files |
| Phase 01 P08 | 33min | 3 tasks | 5 files |
| Phase 02 P01 | 70 min | 3 tasks | 22 files |
| Phase 02-explainable-import-and-exact-export P02 | 4h30min | 3 tasks | 37 files |

## Accumulated Context

### Decisions

- The MVP is a five-phase Mac-to-server custody and continuity proof; the first active phase establishes the durable private-server and HTTPS protocol contracts.
- All native client recovery flows must converge through the versioned API; LiveView is the first-party console, never the client protocol.
- The first adapter, macOS distribution posture, parser depth, and persistent-save behavior are empirical gates, not pre-approved platform promises.
- [Phase 01]: Router-level call/2 wrapper (not Plug.ErrorHandler verbatim) for RFC 9457 exception/404 handling, since ConnTest cannot observe Plug.ErrorHandler's mandatory re-raise for Phoenix.Router.NoRouteError
- [Phase 01]: Caddyfile site address derived via Compose localhost into CADDY_SITE_ADDRESS, since Compose always sets a listed env key (even empty) but Caddy's own {$VAR:default} only falls back on truly-unset vars
- [Phase 01]: [Phase 01]: Setup-token consumption uses a guarded UPDATE ... WHERE consumed_at IS NULL inside claim/2's Ecto.Multi, relying on Postgres row-level serialization instead of an explicit SELECT FOR UPDATE, to guarantee exactly one owner from concurrent claims
- [Phase 01]: [Phase 01]: Login screen keeps the generated Email field alongside Password since D-02's no-email constraint is about mail delivery, not the login identifier
- [Phase 01]: [Phase 01]: revoke_device/2 keeps device_credentials rows (only sets revoked_at) rather than deleting them, since deletion would make a revoked device's next request indistinguishable from unauthorized, breaking the PROT-02 device_revoked contract
- [Phase 01]: [Phase 01]: pairing_requests uses utc_datetime_usec (not the app-wide utc_datetime default) so pending-queue eviction's oldest-request selection is deterministic under a fast request burst
- [Phase 01]: Per-action sudo freshness check (Accounts.sudo_mode?/1) instead of a whole-route gate for /devices, so the read-only approval queue and device list stay reachable without forcing re-authentication on every visit
- [Phase 01]: Console-triggered credential rotation UI deliberately not built in plan 01-05 — D-10 rotation already ships as a device-initiated action via /api/v1/devices/me/rotate, a stronger auth factor than owner sudo with an actual delivery path
- [Phase 01]: Added a read-only caddy_data volume mount to the app service in docker-compose.yml so Playstead.TlsTrust can read Caddy's internal-CA root certificate for pairing-time client pinning
- [Phase 01]: [Phase 01]: on_conflict convergence detection required {:replace, [:updated_at]} not :nothing, since Ecto client-generates binary_id primary keys before INSERT, making :nothing's returned struct identical between insert and no-op conflict
- [Phase 01]: [Phase 01]: Only the protocol capability namespace is required for a compatible negotiation verdict; app/cache/transfer/adapter/save mismatches degrade to compatible_with_limits, never incompatible
- [Phase 01]: Commit-order fencing for the change journal uses a write-side pg_advisory_xact_lock rather than read-side xact-id/snapshot-xmin filtering, since the latter is untestable under Ecto Sandbox's shared-transaction test harness
- [Phase 01]: Stage docs/ in the Docker builder stage before RUN mix compile (not relocating RECOVERY.md under priv/, not reading it at runtime) to fix OPER-01's docker compose build failure
- [Phase 01]: Added a generic ExUnit build-context guard (Playstead.DockerBuildContextTest) deriving required staged resources from Application.spec(:playstead, :modules) so any future compile-time embed is covered without hardcoding
- [Phase 01]: Runner-stage /app/blobs must be mkdir+chown'd to nobody before USER nobody, since Docker creates named-volume mount points root:root; scripts/compose-smoke.sh now asserts blob writability
- [Phase 02]: [Phase 02]: Escalated the Readiness :exports row to a new :error state (alongside existing :ok/:warning) since D-33 requires the export mount to be genuinely writable before any export job can run
- [Phase 02]: [Phase 02]: free_bytes/1 shells out to df -Pk (portable across the Linux release container and macOS dev) instead of adding a NIF for a raw statvfs call; required_bytes/2's margin arithmetic stays pure integer math
- [Phase 02]: Repo.insert_all/on_conflict replaces Repo.insert+catch for lookup-or-create under a unique constraint nested inside Idempotency.execute's Ecto.Multi — A failed constrained Repo.insert aborts the ambient Postgres transaction for any later query in that same transaction once nested one level deeper
- [Phase 02]: Upload concurrency uses a dedicated ETS counter (UploadSlots), not Hammer/RateLimiter — Hammer's fixed-window limiter has no decrement and cannot represent how many uploads are in flight right now

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3 must pass the Mac adapter spike (signing/notarization or sandbox posture, controller, BIOS, launch/recovery, and safe save flush) before a supported adapter is promised.
- Phase 2 must pass an adversarial archive-security gate before enabling archive extraction or deep inspection.
- ⚠️ [Phase 01] Open code-review findings (01-REVIEW.md, status issues_found): CR-01 recovery codes / reset & setup tokens not in Phoenix's parameter log filter; WR-01/05 no throttle on pairing redemption, setup-token verification, or password reset; WR-02 X-Forwarded-For trusted unconditionally; WR-06 build-context guard compares only top-level path segments. Address before exposing the server beyond a trusted LAN.
- ⚠️ [Phase 01] `mix test` is intermittently flaky (~1 in 3 full runs): `System.put_env("PLAYSTEAD_PROXY", ...)` in tls_trust_test.exs / setup_live_test.exs races async tests in devices_live_test.exs. Fix test isolation before relying on CI as a gate.
- ⚠️ [Phase 01] Volumes provisioned against a pre-01-08 image keep a root-owned /app/blobs; docs/UPGRADE.md has no note on the symptom or the one-line remediation (`docker compose exec -u root app chown nobody /app/blobs`).
- ⚠️ [Phase 01] Readiness panel is only visible inside the one-shot setup wizard; recovery codes cannot be regenerated from the console (both added to PROJECT.md Active requirements).

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260826-tqx | Adopt Playstead as the project identity, update the planning corpus, establish workspace subproject folders, and rename the parent workspace | 2026-08-26 | 1fd0dbe | [260826-tqx-adopt-playstead-as-the-project-identity-](./quick/260826-tqx-adopt-playstead-as-the-project-identity-/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Platform expansion | Second client/adapter, browser play, and broad compatibility matrices | v2 / separate spike | 2026-08-26 |
| Storage and transfer | S3-compatible storage and direct/multipart resumable upload | v2 / separate spike | 2026-08-26 |
| Optional services | Hosted storage, achievements, recommendations, and metadata/artwork expansion | v2 / separate review | 2026-08-26 |

## Session Continuity

Last session: 2026-08-28T18:55:03.081Z
Stopped at: Completed 02-02-PLAN.md
Resume file: None
