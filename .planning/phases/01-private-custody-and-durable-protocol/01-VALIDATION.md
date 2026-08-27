---
phase: 1
slug: private-custody-and-durable-protocol
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-27
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built into Elixir) |
| **Config file** | none — Wave 0 installs (mix project not yet scaffolded) |
| **Quick run command** | `mix test --stale` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test --stale`
- **After every plan wave:** Run `mix test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-T1 (tracer) | 01-01 | 1 | OPER-01, PROT-03 | T-01-02, T-01-03, T-01-04, T-01-05, T-01-SC | No host port but Caddy; no `latest` tags; `/healthz` leaks no detail | integration/contract | `mix test test/playstead_web/controllers/health_controller_test.exs test/playstead_web/controllers/api/v1/capabilities_controller_test.exs` | ❌ W0 | ⬜ pending |
| 01-01-T2 | 01-01 | 1 | PROT-03 | T-01-01 | Forced 500 renders problem+json, never Phoenix HTML | contract | `mix test test/playstead_web/problem_test.exs` | ❌ W0 | ⬜ pending |
| 01-01-T3 | 01-01 | 1 | OPER-01 | T-01-04, T-01-06 | Boot refuses placeholder secrets and too-old schema | unit + manual smoke | `mix test test/playstead/release_test.exs`; `bash scripts/compose-smoke.sh` | ❌ W0 | ⬜ pending |
| 01-02-T1 | 01-02 | 2 | OPER-02 | T-01-10 | No mail-delivery code path survives; bcrypt password auth | unit/LiveView | `mix test test/playstead/accounts_test.exs test/playstead_web/no_mailer_test.exs` | ❌ W0 | ⬜ pending |
| 01-02-T2 | 01-02 | 2 | OPER-02 | T-01-08, T-01-09, T-01-11, T-01-13 | No unauthenticated claim window; concurrent claim yields one owner | unit/LiveView | `mix test test/playstead/setup_test.exs test/playstead_web/live/setup_live_test.exs` | ❌ W0 | ⬜ pending |
| 01-03-T1 | 01-03 | 3 | OPER-02 | T-01-14, T-01-15, T-01-16, T-01-18, T-01-19 | Scheme-gated Secure cookie; sudo gate; fixed throttle; append-only audit | unit/plug/LiveView | `mix test test/playstead/audit_log_test.exs test/playstead_web/live/sessions_live_test.exs test/playstead_web/plugs/sudo_mode_test.exs test/playstead_web/plugs/throttle_test.exs` | ❌ W0 | ⬜ pending |
| 01-03-T2 | 01-03 | 3 | OPER-02 | T-01-17, T-01-18 | Reset ends all sessions; single-use codes and tokens | unit | `mix test test/playstead/accounts_recovery_test.exs` | ❌ W0 | ⬜ pending |
| 01-04-T1 | 01-04 | 4 | PROT-01 | T-01-21, T-01-22, T-01-24, T-01-26, T-01-27, T-01-28 | No code-guess endpoint; no auto-approval; server-side expiry re-check | contract/property | `mix test test/playstead/pairing/display_code_test.exs test/playstead/pairing_test.exs test/playstead_web/controllers/api/v1/pairing_controller_test.exs` | ❌ W0 | ⬜ pending |
| 01-04-T2 | 01-04 | 4 | PROT-01 | T-01-23, T-01-25 | Credential once-only, header-only, hashed; concurrent redeem yields one | contract/concurrency | `mix test test/playstead_web/plugs/device_auth_test.exs test/playstead_web/controllers/api/v1/pairing_controller_test.exs` | ❌ W0 | ⬜ pending |
| 01-04-T3 | 01-04 | 4 | PROT-02 | T-01-28, T-01-29 | Revoking one device provably leaves others working | contract | `mix test test/playstead_web/controllers/api/v1/devices_controller_test.exs test/playstead/pairing_test.exs` | ❌ W0 | ⬜ pending |
| 01-05-T1 | 01-05 | 5 | PROT-01 | T-01-30, T-01-31, T-01-34, T-01-35 | Claims never carry observed-fact authority; expired request inert | LiveView | `mix test test/playstead_web/live/devices_live_test.exs test/playstead/tls_trust_test.exs` | ❌ W0 | ⬜ pending |
| 01-05-T2 | 01-05 | 5 | PROT-02 | T-01-32, T-01-33, T-01-36 | Revoke behind sudo gate; only fingerprint prefix rendered | LiveView | `mix test test/playstead_web/live/devices_live_test.exs` | ❌ W0 | ⬜ pending |
| 01-06-T1 | 01-06 | 6 | PROT-03 | T-01-40, T-01-41 | Range check never equality; incompatible client never locked out | contract/table-driven | `mix test test/playstead/protocol/negotiation_test.exs test/playstead_web/controllers/api/v1/hello_controller_test.exs` | ❌ W0 | ⬜ pending |
| 01-06-T2 | 01-06 | 6 | PROT-04 | T-01-37, T-01-38, T-01-39, T-01-43 | Receipt in the effect's transaction; 409 on in-flight race; 422 on mismatch | contract/concurrency | `mix test test/playstead/idempotency_test.exs test/playstead_web/plugs/idempotency_test.exs` | ❌ W0 | ⬜ pending |
| 01-06-T3 | 01-06 | 6 | PROT-04 | T-01-42 | Post-receipt-expiry replay converges to one effect | invariant/unit | `mix test test/playstead/command_id_test.exs test/playstead/idempotency_test.exs` | ❌ W0 | ⬜ pending |
| 01-07-T1 | 01-07 | 7 | PROT-05 | T-01-44, T-01-45, T-01-47 | Cursor tamper-rejecting; per-owner partition independent of cursor | unit | `mix test test/playstead/sync/cursor_test.exs test/playstead/sync/change_journal_test.exs` | ❌ W0 | ⬜ pending |
| 01-07-T2 | 01-07 | 7 | PROT-05 | T-01-46, T-01-48 | 410 `cursor_expired` exact at the compaction boundary; no offset pagination | contract | `mix test test/playstead/sync/compaction_test.exs test/playstead_web/controllers/api/v1/changes_controller_test.exs` | ❌ W0 | ⬜ pending |
| 01-07-T3 | 01-07 | 7 | PROT-05 | T-01-46, T-01-49, T-01-50 | Missed-every-notification convergence via both recovery paths, incl. tombstone | contract/scenario | `mix test test/playstead_web/controllers/api/v1/convergence_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `playstead-server/` mix project scaffold with ExUnit configured
- [ ] `test/support/conn_case.ex` — HTTP contract test fixtures
- [ ] `test/support/data_case.ex` — Ecto sandbox fixtures

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Docker Compose deploy path boots with persistent volumes | OPER-01 | Requires real Docker runtime outside ExUnit | `docker compose up -d`, verify healthchecks green, restart, confirm data persists |
| Mac Keychain credential retention | OPER-02 | Requires macOS Keychain on device | Pair Mac client, restart app, confirm credential survives without re-pairing |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
