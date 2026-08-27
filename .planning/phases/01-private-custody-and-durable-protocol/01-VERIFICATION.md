---
phase: 01-private-custody-and-durable-protocol
verified: 2026-08-27T19:30:00Z
status: gaps_found
score: 6/7 must-have truths verified (roadmap success criteria); 1 blocker found by live Docker build
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "A self-hoster can deploy the private server through the documented Docker Compose path with persistent database and blob volumes, then complete setup in the LiveView console. (Roadmap SC1 / OPER-01)"
    status: failed
    reason: "`docker compose up -d` (the documented, one-file deployment path in docs/DEPLOY.md) cannot even build the app image. `Dockerfile`'s builder stage never `COPY`s the repository's `docs/` directory before `RUN mix compile`, but `PlaysteadWeb.RecoveryDocsController` (added in plan 01-03) reads `docs/RECOVERY.md` at compile time via a module attribute (`@recovery_doc File.read!(Path.join(File.cwd!(), \"docs/RECOVERY.md\"))`). The build fails with `** (File.Error) could not read file \"/app/docs/RECOVERY.md\": no such file or directory` at the `RUN mix compile` step, before the image is ever produced. Reproduced live: ran `scripts/compose-smoke.sh` (the plan's own OPER-01 evidence path) against real Docker Desktop; `docker compose up -d` / `docker compose build` fails deterministically at this step. `mix test` and `mix compile` pass locally only because the repo checkout's cwd already contains `docs/RECOVERY.md` — that condition does not hold inside the Docker build stage at the point `mix compile` runs."
    artifacts:
      - path: "playstead-server/Dockerfile"
        issue: "Builder stage copies `priv`, `lib`, `assets`, `config/runtime.exs`, and `rel`, but never `docs` — `RUN mix compile` (line 62) therefore runs without `docs/RECOVERY.md` present, and `recovery_docs_controller.ex`'s compile-time `File.read!/1` call fails the build outright."
      - path: "playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex"
        issue: "Reads `docs/RECOVERY.md` at compile time via a module attribute rather than at runtime or via `priv/`, making the controller's compilability depend on a file that plan 01-01's Dockerfile (predating this controller, added in plan 01-03) never stages into the builder."
    missing:
      - "Add `COPY docs docs` to the Dockerfile's builder stage before `RUN mix compile` (mirroring the existing `COPY priv priv` / `COPY lib lib` lines), OR move `docs/RECOVERY.md`'s content into `priv/` (which the Dockerfile already copies), OR read the file at runtime instead of compile time with a documented fallback for the case where `docs/` isn't present in a release."
      - "Re-run `bash playstead-server/scripts/compose-smoke.sh` end-to-end against a real Docker build after the fix, since this is exactly the OPER-01 evidence path ExUnit cannot reach and the one this regression slipped through — plan 01-01's summary confirms the smoke script passed at that point in time, but no later plan (01-03 through 01-07) re-ran it after adding compile-time or build-context-dependent code."
human_verification:
  - test: "Visually confirm the setup wizard (plan 01-02), Sessions/Sudo/RecoveryLogin screens (plan 01-03), and the Devices approval queue/device list (plan 01-05) match the UI-SPEC's dark console surface, typography (including the 40px display-code exception), spacing scale, and color-authority separation between claimed and observed fields."
    expected: "The rendered screens visually match the UI-SPEC contract — dark background/card colors, Inter/JetBrains Mono typography, the accent/destructive color reservations, and the specific claimed-vs-observed visual hierarchy on the pairing approval card (D-09)."
    why_human: "Automated tests in plans 01-02, 01-03, and 01-05 assert markup, text content, ARIA attributes, and state-transition behavior, but not visual fidelity (color values as rendered, spacing, typographic scale, truncation/tooltip behavior) — each plan's own SUMMARY.md explicitly flags this as `human_judgment: true` and defers it to this phase's end-of-phase UAT pass."
  - test: "Run `bash playstead-server/scripts/compose-smoke.sh` end-to-end after the Dockerfile fix above, on a clean Docker host."
    expected: "The stack builds, comes up healthy (db/app/caddy), `curl -k https://localhost/healthz` and `/api/v1/capabilities` succeed through Caddy, and `playstead_db` survives a `docker compose down` + `up -d` restart."
    why_human: "Container build/orchestration is outside ExUnit's reach by design (VALIDATION.md marks this manual-only); it is also the exact evidence path that would have caught the Dockerfile gap above before merge, so it must be re-run after the fix, not merely re-read."
---

# Phase 01: Private Custody and Durable Protocol Verification Report

**Phase Goal:** A self-hoster can run a private server and a Mac can pair and recover its authoritative state through a secure, versioned HTTPS protocol.
**Verified:** 2026-08-27
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A self-hoster can deploy the private server through the documented Docker Compose path with persistent database and blob volumes, then complete setup in the LiveView console. | ✗ FAILED | `docker compose build`/`up -d` fails to build the app image (see Gaps below). Setup wizard code itself (plan 01-02) is present, tested, and compiles, but the deployment path that is supposed to deliver it is broken. |
| 2 | An authenticated owner can approve a Mac pairing request, the Mac retains its scoped credential in Keychain, and the owner can revoke that device without disconnecting others. | ✓ VERIFIED | `Playstead.Pairing.approve/2`, `redeem/2` (one-time credential, exactly-once, concurrency-tested), `revoke_device/2` (PROT-02 isolation contract test pairs two devices, revokes one, asserts 401/`device_revoked` for it and 200 for the other in the same test — `test/playstead_web/controllers/api/v1/devices_controller_test.exs`). The Mac-side Keychain storage itself is out of server scope (Phase 3 client), correctly deferred per REQUIREMENTS.md/ROADMAP. `/devices` LiveView (plan 01-05) provides the console surface with sudo-gated revoke. |
| 3 | A client can declare its protocol, app, cache, transfer, adapter, and save capabilities and receive a clear remedy when they are incompatible. | ✓ VERIFIED | `Playstead.Protocol.Negotiation.verdict/2` (range-check, never version equality, table-driven test across 6+ combinations), `Playstead.Protocol.Remedy.build/3` (four required fields), `POST /api/v1/hello` — all in `test/playstead/protocol/negotiation_test.exs` and `test/playstead_web/controllers/api/v1/hello_controller_test.exs`, passing. |
| 4 | After a disconnection, a client can retry a mutation without creating another effect and reconstruct catalogue, job, transfer, and save state through HTTPS snapshot-and-cursor reads without a WebSocket. | ✓ VERIFIED | `Playstead.Idempotency.execute/4` (transactional receipt, 409 on in-flight race, 422 on payload mismatch, replay returns stored response verbatim — `test/playstead/idempotency_test.exs`, `test/playstead_web/plugs/idempotency_test.exs`); `Playstead.Sync` cursor/journal/snapshot with the convergence contract test (`test/playstead_web/controllers/api/v1/convergence_test.exs`) proving `/changes`-only and 410-then-snapshot reconstructions converge identically, including a tombstoned deletion. Catalogue/job/transfer/save entity kinds are registered in the frozen vocabulary now with producers deferred to Phases 2-4, matching the phase's own documented scope note — not a gap for Phase 1. |

**Score:** 3/4 roadmap success criteria fully verified; 1 falsified by a live Docker build failure.

### Additional Plan-Level Must-Haves (spot-checked against code)

All plan-level `must_haves.truths` for OPER-02, PROT-01 through PROT-05 that are testable via `mix test` were independently re-verified by running the full suite live (see below), not merely trusted from SUMMARY.md. All 292 tests pass. Key spot-checks:

- RFC 9457 problem+json on every `/api` error path, including forced 500s and unmatched routes — confirmed via `lib/playstead_web/plugs/api_problem_handler.ex`, `lib/playstead_web/error_codes.ex` registry (17 codes incl. `capability_incompatible`, `idempotency_key_conflict`, `cursor_expired`, `device_revoked`), and `router.ex`'s `use PlaysteadWeb.Plugs.ApiProblemHandler`.
- Named volumes `playstead_db`/`playstead_blobs`, pinned image tags (`postgres:17.2`, `caddy:2.10`, no `latest`), `ports:` only under `caddy`, `condition: service_healthy` present twice — all confirmed by reading `docker-compose.yml` directly.
- Boot-time gates (`Playstead.Release.assert_no_placeholder_secrets!/0`, `assert_minimum_upgradable_version!/0`, `migrate/0`) — present, defined, tested.
- Setup-token bootstrap, once-only concurrent-safe owner claim, recovery codes, readiness summary — present and tested (`Playstead.Setup`, `Playstead.Readiness`).
- Sessions list, sudo-mode gate, scheme-aware cookie posture, throttling, audit log, email-free recovery (reset command + recovery-code login) — present and tested.
- Pairing ceremony (display code, device_code hashing, concurrent-redemption safety, header-only device auth, use-activated rotation, revocation tombstones) — present and tested.
- Idempotency-Key layer with transactional receipts, `command_id` UUIDv7 natural keys with `on_conflict` convergence, Oban unique enqueue — present and tested.
- Change journal, HMAC-signed opaque cursor, 410 `cursor_expired`, transactional snapshot, convergence contract test — present and tested.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-server/docker-compose.yml` | One-file db/app/caddy deployment, named volumes, pinned tags | ✓ VERIFIED (content) / ✗ Build fails | File content is correct per plan; the image it builds does not compile. |
| `playstead-server/Dockerfile` | Non-root OTP release, builds cleanly | ✗ STUB-LIKE GAP | Never copies `docs/` before `mix compile`, breaking the build the moment `recovery_docs_controller.ex` exists (plan 01-03 onward). |
| `playstead-server/lib/playstead_web/problem.ex` | RFC 9457 rendering | ✓ VERIFIED | `send_problem/5` present, contract-tested. |
| `playstead-server/lib/playstead/protocol/capabilities.ex` | Frozen envelope | ✓ VERIFIED | Exact key set, contract-tested, read directly. |
| `playstead-server/lib/playstead/pairing.ex` | Full pairing/device/credential state machine | ✓ VERIFIED | All documented functions present, exercised by 292-test suite. |
| `playstead-server/lib/playstead/idempotency.ex` | Transactional receipt layer | ✓ VERIFIED | Single receipt-insert site inside `Ecto.Multi`, confirmed by reading source. |
| `playstead-server/lib/playstead/sync/*.ex` | Cursor, journal, snapshot, compaction | ✓ VERIFIED | All present; convergence test passes. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `Caddyfile` | `docker-compose.yml` | `reverse_proxy app:` | ✓ WIRED | Present in `Caddyfile`. |
| `endpoint.ex`/`router.ex` | `api_problem_handler.ex` | exception handling forces problem+json | ✓ WIRED | `use PlaysteadWeb.Plugs.ApiProblemHandler` in `router.ex`. |
| `hello_controller.ex` | `protocol/negotiation.ex` | domain-computed verdict | ✓ WIRED | Controller delegates, no inline literal. |
| `plugs/idempotency.ex` | `idempotency.ex` | lookup/fingerprint delegation | ✓ WIRED | Confirmed in plug source. |
| `pairing.ex` | `sync/change_journal.ex` | mutations append journal entries | ✓ WIRED | `ChangeJournal.append`/`tombstone` calls inside pairing mutation transactions. |
| App container | `docs/RECOVERY.md` | compile-time `File.read!/1` | ✗ NOT WIRED | The Docker build context never delivers this file to the builder stage before compile — see Gaps. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite passes | `cd playstead-server && MIX_ENV=test mix test` | 292 tests, 0 failures | ✓ PASS |
| Compile clean | `mix compile --warnings-as-errors` | exit 0 | ✓ PASS |
| Docker Compose deployment builds and serves HTTPS (OPER-01) | `bash scripts/compose-smoke.sh` against real Docker Desktop | Build fails at `RUN mix compile`: `** (File.Error) could not read file "/app/docs/RECOVERY.md"` | ✗ FAIL |
| All commits referenced in every plan's SUMMARY.md exist | `git log --oneline` | All 17 commit hashes across plans 01-01 through 01-07 confirmed present | ✓ PASS |
| Migrations exist for every table each plan claims to add | `ls priv/repo/migrations/` | 11 migrations covering users/auth, setup/recovery, audit log, pairing, devices/credentials, capability declarations, idempotency receipts, command_id, change journal | ✓ PASS |

### Anti-Patterns Found

No `TBD`/`FIXME`/`XXX` debt markers, no `TODO`/`HACK`/`PLACEHOLDER` comments, and no "not yet implemented"/"coming soon" strings found in `lib/`. No blocking anti-patterns beyond the Dockerfile/docs gap above, which is a correctness bug rather than a stub.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| OPER-01 | 01-01 | Deploy via Docker Compose with persistent volumes | ✗ BLOCKED | Docker build fails; compose file content is otherwise correct. See Gaps. |
| OPER-02 | 01-02, 01-03 | Complete setup in LiveView console without editing data/API | ✓ SATISFIED | Setup wizard, sessions, sudo, recovery all present and tested. |
| PROT-01 | 01-04, 01-05 | Owner approves pairing, Mac stores scoped credential | ✓ SATISFIED | Pairing ceremony + one-time credential issuance verified. Keychain storage is Mac-client (Phase 3) scope. |
| PROT-02 | 01-04, 01-05 | Review paired devices, revoke one without affecting others | ✓ SATISFIED | Isolation contract test passes; console UI present. |
| PROT-03 | 01-01, 01-06 | Declare capabilities, get actionable incompatibility response | ✓ SATISFIED | Negotiation + remedy verified. |
| PROT-04 | 01-06 | Safe retry via durable receipt, no duplicate effect | ✓ SATISFIED | Transactional idempotency layer verified. |
| PROT-05 | 01-07 | Reconstruct state via versioned HTTPS snapshot-and-cursor, no persistent WebSocket | ✓ SATISFIED | Cursor/journal/snapshot + convergence test verified. |

No orphaned requirements — all 7 phase requirement IDs (OPER-01, OPER-02, PROT-01 through PROT-05) are declared across the 7 plans and covered above; this exactly matches the phase's assigned requirement set with no additions or omissions.

### Human Verification Required

### 1. Visual/UX fidelity against UI-SPEC

**Test:** Walk the setup wizard, login/sessions/sudo/recovery-login screens, and the Devices approval queue/device list in a browser.
**Expected:** Dark console surface, correct typography (including the one 40px display-code exception), spacing scale, and the claimed-vs-observed visual hierarchy on the pairing evidence card render as the UI-SPEC describes.
**Why human:** Every plan (01-02, 01-03, 01-05) explicitly flags this as `human_judgment: true` in its own SUMMARY.md coverage section — automated tests assert markup/text/ARIA/state transitions, not rendered visual fidelity.

### 2. Re-run the compose smoke test after the Dockerfile fix

**Test:** `bash playstead-server/scripts/compose-smoke.sh` on a clean Docker host, after `docs/` (or an equivalent fix) is added to the Dockerfile's builder stage.
**Expected:** Stack builds and comes up healthy; `/healthz` and `/api/v1/capabilities` respond over HTTPS through Caddy; `playstead_db` survives a restart.
**Why human:** This is the documented manual-only evidence path (VALIDATION.md) and the one that should have caught this regression — it must be physically re-run, not just re-read, once fixed.

### Gaps Summary

Six of seven phase requirements are fully implemented and proven by a green 292-test suite, contract tests for all three roadmap-named contract-gate proofs (idempotency, capability negotiation, cursor convergence), and direct source inspection confirming no stubs or debt markers. However, the phase's very first success criterion — "a self-hoster can deploy the private server through the documented Docker Compose path" — is **currently false**: a live `docker compose build`/`up -d` run against the actual repository fails during the image build, because `Dockerfile` never copies `docs/` into the builder stage before `mix compile` runs, and `PlaysteadWeb.RecoveryDocsController` (introduced in plan 01-03, after plan 01-01 wrote the Dockerfile) reads `docs/RECOVERY.md` at compile time via a module attribute. This was not caught by any plan's own automated verification because `mix compile`/`mix test` succeed when run directly against the git checkout (where `docs/` is present at the working directory), and no plan after 01-01 re-ran the Docker-based smoke test that would have exposed it. This is a single, narrowly-scoped fix (add one `COPY docs docs` line, or move the file under `priv/`, or defer the read to runtime) but it is currently a hard blocker on OPER-01, the phase's foundational deliverable.

---

*Verified: 2026-08-27*
*Verifier: Claude (gsd-verifier)*
