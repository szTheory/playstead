---
phase: 1
slug: private-custody-and-durable-protocol
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-27
validated: 2026-08-28
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir 1.19 / OTP 28) + Wallaby 0.31 headless-Chrome browser suite (`test/playstead_web/browser/`, tagged `:browser`) |
| **Config file** | `playstead-server/mix.exs`, `playstead-server/test/test_helper.exs` (auto-skips `:browser` when `chromedriver` is not on PATH) |
| **Quick run command** | `cd playstead-server && mix test --exclude browser` |
| **Full suite command** | `cd playstead-server && mix test` (or `mix precommit` = compile `--warnings-as-errors` + format + full suite; this is the CI `test` job) |
| **Estimated runtime** | quick: ~2 s (336 tests) · full: ~105 s (337 tests + 82 browser features) |
| **Support files** | `test/support/{conn_case,data_case,api_case,browser_case,browser_screens}.ex`, `test/support/fixtures/{accounts,idempotency,pairing,sync,tls}_fixtures.ex` |
| **Deployment proof** | `bash playstead-server/scripts/compose-smoke.sh --fresh` — CI job `compose-smoke` (`.github/workflows/ci.yml`): docker build → fresh volumes → boot → `/healthz` + `/api/v1/capabilities` through Caddy → blob-writability → restart → volume survival |

---

## Sampling Rate

- **After every task commit:** Run `mix test --exclude browser` (~2 s)
- **After every plan wave:** Run `mix test` (full, incl. browser)
- **Before `/gsd-verify-work`:** `mix precommit` must be green
- **Max feedback latency:** 60 seconds (quick run is well inside; the full browser run is a wave-boundary gate, not a per-commit one)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-T1 (tracer) | 01-01 | 1 | OPER-01, PROT-03 | T-01-02, T-01-03, T-01-04, T-01-05, T-01-SC | No host port but Caddy; no `latest` tags; `/healthz` leaks no detail | integration/contract | `mix test test/playstead_web/controllers/health_controller_test.exs test/playstead_web/controllers/api/v1/capabilities_controller_test.exs` | ✅ | ✅ green |
| 01-01-T2 | 01-01 | 1 | PROT-03 | T-01-01 | Forced 500 renders problem+json, never Phoenix HTML | contract | `mix test test/playstead_web/problem_test.exs` | ✅ | ✅ green |
| 01-01-T3 | 01-01 | 1 | OPER-01 | T-01-04, T-01-06 | Boot refuses placeholder secrets and too-old schema | unit + compose smoke (CI) | `mix test test/playstead/release_test.exs test/playstead/readiness_test.exs`; `bash scripts/compose-smoke.sh --fresh` (CI `compose-smoke`) | ✅ | ✅ green |
| 01-02-T1 | 01-02 | 2 | OPER-02 | T-01-10 | No mail-delivery code path survives; bcrypt password auth | unit/LiveView | `mix test test/playstead/accounts_test.exs test/playstead_web/no_mailer_test.exs` | ✅ | ✅ green |
| 01-02-T2 | 01-02 | 2 | OPER-02 | T-01-08, T-01-09, T-01-11, T-01-13 | No unauthenticated claim window; concurrent claim yields one owner | unit/LiveView/browser | `mix test test/playstead/setup_test.exs test/playstead_web/live/setup_live_test.exs test/playstead_web/live/setup_live_env_test.exs test/playstead_web/browser/setup_wizard_journey_test.exs` | ✅ | ✅ green |
| 01-03-T1 | 01-03 | 3 | OPER-02 | T-01-14, T-01-15, T-01-16, T-01-18, T-01-19 | Scheme-gated Secure cookie; sudo gate; fixed throttle; append-only audit | unit/plug/LiveView/browser | `mix test test/playstead/audit_log_test.exs test/playstead_web/live/sessions_live_test.exs test/playstead_web/live/sudo_live_test.exs test/playstead_web/plugs/sudo_mode_test.exs test/playstead_web/plugs/throttle_test.exs test/playstead_web/session_cookie_test.exs test/playstead_web/user_auth_test.exs test/playstead_web/browser/auth_sessions_journey_test.exs` | ✅ | ✅ green |
| 01-03-T2 | 01-03 | 3 | OPER-02 | T-01-17, T-01-18 | Reset ends all sessions; single-use codes and tokens | unit/LiveView | `mix test test/playstead/accounts_recovery_test.exs test/playstead_web/live/recovery_login_live_test.exs` | ✅ | ✅ green |
| 01-04-T1 | 01-04 | 4 | PROT-01 | T-01-21, T-01-22, T-01-24, T-01-26, T-01-27, T-01-28 | No code-guess endpoint; no auto-approval; server-side expiry re-check | contract/property | `mix test test/playstead/pairing/display_code_test.exs test/playstead/pairing_test.exs test/playstead_web/controllers/api/v1/pairing_controller_test.exs` | ✅ | ✅ green |
| 01-04-T2 | 01-04 | 4 | PROT-01 | T-01-23, T-01-25 | Credential once-only, header-only, hashed; concurrent redeem yields one | contract/concurrency | `mix test test/playstead_web/plugs/device_auth_test.exs test/playstead_web/controllers/api/v1/pairing_controller_test.exs` | ✅ | ✅ green |
| 01-04-T3 | 01-04 | 4 | PROT-02 | T-01-28, T-01-29 | Revoking one device provably leaves others working | contract | `mix test test/playstead_web/controllers/api/v1/devices_controller_test.exs test/playstead/pairing_test.exs` | ✅ | ✅ green |
| 01-05-T1 | 01-05 | 5 | PROT-01 | T-01-30, T-01-31, T-01-34, T-01-35 | Claims never carry observed-fact authority; expired request inert | LiveView/browser | `mix test test/playstead_web/live/devices_live_test.exs test/playstead_web/live/devices_live_env_test.exs test/playstead/tls_trust_test.exs test/playstead_web/browser/devices_journey_test.exs` | ✅ | ✅ green |
| 01-05-T2 | 01-05 | 5 | PROT-02 | T-01-32, T-01-33, T-01-36 | Revoke behind sudo gate; only fingerprint prefix rendered | LiveView/browser | `mix test test/playstead_web/live/devices_live_test.exs test/playstead_web/browser/devices_journey_test.exs` | ✅ | ✅ green |
| 01-06-T1 | 01-06 | 6 | PROT-03 | T-01-40, T-01-41 | Range check never equality; incompatible client never locked out | contract/table-driven | `mix test test/playstead/protocol/negotiation_test.exs test/playstead_web/controllers/api/v1/hello_controller_test.exs` | ✅ | ✅ green |
| 01-06-T2 | 01-06 | 6 | PROT-04 | T-01-37, T-01-38, T-01-39, T-01-43 | Receipt in the effect's transaction; 409 on in-flight race; 422 on mismatch | contract/concurrency | `mix test test/playstead/idempotency_test.exs test/playstead_web/plugs/idempotency_test.exs` | ✅ | ✅ green |
| 01-06-T3 | 01-06 | 6 | PROT-04 | T-01-42 | Post-receipt-expiry replay converges to one effect | invariant/unit | `mix test test/playstead/command_id_test.exs test/playstead/idempotency_test.exs` | ✅ | ✅ green |
| 01-07-T1 | 01-07 | 7 | PROT-05 | T-01-44, T-01-45, T-01-47 | Cursor tamper-rejecting; per-owner partition independent of cursor | unit | `mix test test/playstead/sync/cursor_test.exs test/playstead/sync/change_journal_test.exs` | ✅ | ✅ green |
| 01-07-T2 | 01-07 | 7 | PROT-05 | T-01-46, T-01-48 | 410 `cursor_expired` exact at the compaction boundary; no offset pagination | contract | `mix test test/playstead/sync/compaction_test.exs test/playstead_web/controllers/api/v1/changes_controller_test.exs` | ✅ | ✅ green |
| 01-07-T3 | 01-07 | 7 | PROT-05 | T-01-46, T-01-49, T-01-50 | Missed-every-notification convergence via both recovery paths, incl. tombstone; snapshot really runs at REPEATABLE READ under interleaved commits | contract/scenario/real-transaction concurrency | `mix test test/playstead_web/controllers/api/v1/convergence_test.exs test/playstead/sync/snapshot_test.exs test/playstead/sync/snapshot_concurrency_test.exs` | ✅ | ✅ green |
| 01-08-T1 (gap closure) | 01-08 | 8 | OPER-01 | T-01-04 | Builder stage stages `docs/` before `RUN mix compile`; `@external_resource` forces recompilation on edit | build-order guard | `cd playstead-server && awk '/^COPY docs docs$/{c=NR} /^RUN mix compile$/{r=NR} END{exit !(c>0 && r>0 && c<r)}' Dockerfile && mix compile --force --warnings-as-errors` | ✅ | ✅ green |
| 01-08-T2 (gap closure) | 01-08 | 8 | OPER-01 | T-01-04 | Any unstaged or late-staged compile-time embed fails `mix test` with no Docker daemon; `GET /docs/recovery` serves live markdown | unit/contract | `mix test test/playstead/docker_build_context_test.exs test/playstead_web/controllers/recovery_docs_controller_test.exs` | ✅ | ✅ green |
| 01-08-T3 (was `checkpoint:human-verify`) | 01-08 | 8 | OPER-01 | T-01-02, T-01-04 | Cold-start `docker compose` path boots from destroyed volumes, `/app/blobs` writable as `nobody`, data survives restart; UI-SPEC fidelity | compose smoke (CI) + browser | `bash scripts/compose-smoke.sh --fresh` (CI `compose-smoke`); `mix test --only browser` (82 features: palette, typography, coherence, states, copy, 3 journeys, smoke) | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Evidence (2026-08-28):** `mix test` → `82 features, 337 tests, 0 failures` (105.3 s, chromedriver present); `mix test --exclude browser` → `336 tests, 0 failures` (1.5 s). The single `TlsTrustTest` flake noted in 01-08-SUMMARY did not reproduce; the module now passes explicit env maps and is documented as `async: true`-safe.

---

## Wave 0 Requirements

- [x] `playstead-server/` mix project scaffold with ExUnit configured
- [x] `test/support/conn_case.ex` — HTTP contract test fixtures
- [x] `test/support/data_case.ex` — Ecto sandbox fixtures
- [x] (added during execution) `test/support/api_case.ex`, `test/support/browser_case.ex`, `test/support/browser_screens.ex`, `test/support/fixtures/*`

---

## Manual-Only Verifications

All phase behaviors have automated verification.

| Behavior | Requirement | Disposition |
|----------|-------------|-------------|
| Docker Compose deploy path boots with persistent volumes | OPER-01 | **Automated** — was manual at plan time; now `scripts/compose-smoke.sh --fresh` in the CI `compose-smoke` job (fresh volumes, boot banner, `/setup` 200, restart, volume survival, blob writability). Runs on every push to `main` and on PRs touching the deployment surface. |
| Mac Keychain credential retention | OPER-02 (originally listed) | **Not a Phase 1 deliverable** — `playstead-mac/` is a README only; no client code was built in this phase. The server-side half (credential issued exactly once, header-only, hash-stored, suitable for Keychain storage) is automated by `01-04-T2`. Keychain retention itself belongs to the Mac-client phase's VALIDATION.md and is not counted against Phase 1 compliance. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s (quick run ~2 s)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-08-28

---

## Validation Audit 2026-08-28

| Metric | Count |
|--------|-------|
| Gaps found | 0 test-coverage gaps (2 documentation gaps: plan 01-08 absent from the map; Docker manual-only row already automated) |
| Resolved | 2 (map extended with 01-08-T1..T3; manual-only table re-dispositioned) |
| Escalated | 0 |

Method: every `Automated Command` path in the map confirmed present on disk (30/30), full suite executed locally with chromedriver on PATH, CI workflow (`.github/workflows/ci.yml`) read to confirm the compose-smoke path runs unattended. No auditor subagent spawned — nothing to generate.
