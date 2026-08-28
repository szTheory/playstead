---
phase: 01-private-custody-and-durable-protocol
verified: 2026-08-28T00:00:00Z
status: passed
score: 4/4 roadmap success criteria verified; 7/7 phase requirements satisfied
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 3/4 roadmap success criteria (6/7 must-have truths)
  gaps_closed:
    - "A self-hoster can deploy the private server through the documented Docker Compose path with persistent database and blob volumes, then complete setup in the LiveView console. (Roadmap SC1 / OPER-01) — Dockerfile now stages docs/ before RUN mix compile; docker compose build completes; a second real blocker (/app/blobs owned root:root, unwritable by the nobody runtime user) was found and fixed during human verification; the OPER-01 compose smoke path was physically re-run on a real Docker host and passed end-to-end, including the new blob-writability assertion."
  gaps_remaining: []
  regressions: []
---

# Phase 01: Private Custody and Durable Protocol Verification Report

**Phase Goal:** A self-hoster can run a private server and a Mac can pair and recover its authoritative state through a secure, versioned HTTPS protocol.
**Verified:** 2026-08-28
**Status:** passed
**Re-verification:** Yes — after gap closure (plan 01-08)

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A self-hoster can deploy the private server through the documented Docker Compose path with persistent database and blob volumes, then complete setup in the LiveView console. | ✓ VERIFIED | **Gap closed.** `playstead-server/Dockerfile` line 61 now contains `COPY docs docs`, placed after `COPY lib lib` and strictly before `RUN mix compile` (confirmed by direct read and by re-running `mix compile --force --warnings-as-errors`, exit 0). Independently falsified the fix by temporarily deleting `COPY docs docs` and re-running `mix test test/playstead/docker_build_context_test.exs`: it failed, naming `PlaysteadWeb.RecoveryDocsController` and the `docs` directory exactly as designed; restored the line and reconfirmed green (3/3). A second, independent deployment blocker (`/app/blobs` created `root:root` by Docker's named-volume mount and unwritable by the runner's `nobody` user) was found during human verification and fixed in the same Dockerfile (`RUN mkdir -p /app/blobs && chown nobody /app/blobs` before `USER nobody`, confirmed present at line 108). `01-08-SUMMARY.md` records the human-run `bash scripts/compose-smoke.sh` output verbatim on a real Docker host: all three services (db/app/caddy) healthy, `/healthz` and `/api/v1/capabilities` return 200 through Caddy, the new blob-writability assertion passes, and `playstead_db` survives `docker compose down` + `up -d` with marker rows intact. Per this task's explicit instruction, this recorded human evidence is accepted — no contradicting evidence found in the codebase. |
| 2 | An authenticated owner can approve a Mac pairing request, the Mac retains its scoped credential in Keychain, and the owner can revoke that device without disconnecting others. | ✓ VERIFIED (regression check) | Unchanged by plan 01-08 (`pairing.ex`, `devices_controller.ex` not in `files_modified`). Full suite re-run confirms `Playstead.Pairing.approve/2`, `redeem/2`, `revoke_device/2` and the PROT-02 isolation contract test still pass. |
| 3 | A client can declare its protocol, app, cache, transfer, adapter, and save capabilities and receive a clear remedy when they are incompatible. | ✓ VERIFIED (regression check) | Unchanged by plan 01-08. `Playstead.Protocol.Negotiation.verdict/2`, `Remedy.build/3`, `POST /api/v1/hello` tests still pass. |
| 4 | After a disconnection, a client can retry a mutation without creating another effect and reconstruct catalogue, job, transfer, and save state through HTTPS snapshot-and-cursor reads without a WebSocket. | ✓ VERIFIED (regression check) | Unchanged by plan 01-08. `Playstead.Idempotency.execute/4` and the `Playstead.Sync` cursor/journal/snapshot convergence contract test still pass. |

**Score:** 4/4 roadmap success criteria verified (previously 3/4; the single blocker is closed).

### Required Artifacts (gap-closure scope)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-server/Dockerfile` | Builder stage stages `docs/` before `RUN mix compile`; runner stage creates a writable `/app/blobs` for `nobody` | ✓ VERIFIED | Both lines present and correctly ordered; `docker compose build` succeeds per 01-08-SUMMARY's captured build log (`RUN mix compile` step completes; final `RUN mkdir -p /app/blobs && chown nobody /app/blobs` layer completes). |
| `playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex` | `@recovery_doc_path` declared as `@external_resource` so edits force recompilation | ✓ VERIFIED | Read directly: `@recovery_doc_path` bound once, `@external_resource @recovery_doc_path` declared, `@recovery_doc` reads through it. Single shared path literal, not two independent ones. |
| `playstead-server/test/playstead/docker_build_context_test.exs` | Generic ExUnit guard tying every `@external_resource` to a builder-stage COPY before compile | ✓ VERIFIED | 2 tests, both pass. Derives required set from `Application.spec(:playstead, :modules)` + `__info__(:attributes)` (no hardcoded resource list — `grep -c '__info__'` = 2). Independently red-stated by removing `COPY docs docs`: failed with the expected message; restored and reconfirmed green. |
| `playstead-server/test/playstead_web/controllers/recovery_docs_controller_test.exs` | Route-level proof `GET /docs/recovery` serves live `docs/RECOVERY.md` bytes, unauthenticated | ✓ VERIFIED | Test asserts status 200, `text/markdown` content type, and byte-for-byte equality against `File.read!("docs/RECOVERY.md")` read at test time (not a fixture that can drift) — passes. |
| `playstead-server/scripts/compose-smoke.sh` | Extended with a blob-writability assertion | ✓ VERIFIED | `touch`/`rm` inside `/app/blobs` via `docker compose exec`, `fail`s on non-zero exit; present at lines 71-74; exercised and passing per the recorded human-run output. |

### Key Link Verification (gap-closure scope)

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| Dockerfile builder stage | `docs/RECOVERY.md` | `COPY docs docs` before `RUN mix compile` | ✓ WIRED | Previously "NOT WIRED" in 01-VERIFICATION.md's initial pass — now confirmed wired by direct file read, `mix compile` success, and the automated guard test. |
| `docker_build_context_test.exs` | Dockerfile | Parses COPY lines before the compile step; compares against every module's `:external_resource` attribute | ✓ WIRED | Confirmed by both the passing state and an independently reproduced red state (line removed → named failure; line restored → pass). |
| `scripts/compose-smoke.sh` | `docker compose build` | The OPER-01 evidence path physically re-run | ✓ WIRED | 01-08-SUMMARY records the verbatim `docker compose build` log (mix compile step completing, blobs-chown layer completing) and the full `compose-smoke.sh` SUCCESS output including the new blob-writability assertion, on a real Docker host — the exact evidence path the original gap escaped through. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Compile clean | `cd playstead-server && mix compile --force --warnings-as-errors` | exit 0 | ✓ PASS |
| Full test suite passes | `cd playstead-server && MIX_ENV=test mix test` | 295 tests; 0-1 failures across repeated runs (see Anti-Patterns) | ⚠️ FLAKY (see below) |
| Build-context guard fails red when the fix is reverted | remove `COPY docs docs`, run `mix test test/playstead/docker_build_context_test.exs` | Failed, naming `docs` directory + `PlaysteadWeb.RecoveryDocsController`; restored and reconfirmed green (2/2) | ✓ PASS (verifier-reproduced) |
| Recovery route test | `mix test test/playstead_web/controllers/recovery_docs_controller_test.exs` | 1 test, 0 failures | ✓ PASS |
| Docker Compose deployment builds and serves HTTPS (OPER-01) | `docker compose build && bash scripts/compose-smoke.sh` on a real Docker host | SUCCESS — verbatim output captured in `01-08-SUMMARY.md` (services healthy, `/healthz`/`/api/v1/capabilities` 200, blobs writable, `playstead_db` survives restart) | ✓ PASS (human-run, evidence recorded per plan instruction) |
| All commits referenced in 01-08-SUMMARY.md exist | `git log --oneline` | `b6af64e`, `830ab8b`, `c1b2c02` all present | ✓ PASS |

### Anti-Patterns Found

No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers and no "not yet implemented"/"coming soon" strings in any file this plan modified or created.

⚠️ **Warning (pre-existing, not introduced by plan 01-08, non-blocking):** `mix test` is intermittently flaky. Across 6 independent full-suite runs during this verification, 2 failed (once in `PlaysteadWeb.DevicesLiveTest`'s CA-fingerprint-panel tests, once in the same test asserting a different fingerprint expectation), both with the identical root cause: `test/playstead/tls_trust_test.exs` (and `test/playstead_web/live/setup_live_test.exs`) call `System.put_env("PLAYSTEAD_PROXY", "external")` in `async: true` tests. `System.put_env/2` mutates the OS-process-global environment, which every concurrently-scheduled async `ExUnit` case reads via `Playstead.TlsTrust.transport_state/0`; the `on_exit` cleanup in `tls_trust_test.exs` is correct but runs after that test's own assertions, not before another async test's concurrent read. This race is scheduler-order-dependent (no `--seed` is pinned), which is why 3 of my 6 runs, and the SUMMARY's own recorded run, showed 0 failures. It is **not caused by this gap-closure plan** — none of `tls_trust.ex`, `devices_live.ex`, `tls_trust_test.exs`, `devices_live_test.exs`, or `setup_live_test.exs` are in 01-08's `files_modified`, and `01-08-SUMMARY.md` itself independently flagged the same class of issue ("one flaky test observed, not caused by this plan... pre-existing async test-isolation flakiness"). It does not affect any of the 4 roadmap success criteria, which are independently proven by non-racy contract tests (idempotency, negotiation, convergence). Recommend a follow-up fix in a later phase: replace the global `System.put_env`/`System.get_env` pattern in `TlsTrust`/`Readiness` with an `Application.get_env`-backed or per-process-configurable seam so these tests can run `async: true` safely, or mark the affected test modules `async: false`.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| OPER-01 | 01-01, 01-08 | Deploy via Docker Compose with persistent volumes | ✓ SATISFIED | Both the compile-time build blocker and the blobs-writability blocker are fixed and proven by an automated regression guard plus a physically re-run compose smoke test on a real Docker host. |
| OPER-02 | 01-02, 01-03 | Complete setup in LiveView console without editing data/API | ✓ SATISFIED | Unchanged by 01-08; regression-confirmed via full suite. |
| PROT-01 | 01-04, 01-05 | Owner approves pairing, Mac stores scoped credential | ✓ SATISFIED | Unchanged by 01-08; regression-confirmed. |
| PROT-02 | 01-04, 01-05 | Review paired devices, revoke one without affecting others | ✓ SATISFIED | Unchanged by 01-08; regression-confirmed. |
| PROT-03 | 01-01, 01-06 | Declare capabilities, get actionable incompatibility response | ✓ SATISFIED | Unchanged by 01-08; regression-confirmed. |
| PROT-04 | 01-06 | Safe retry via durable receipt, no duplicate effect | ✓ SATISFIED | Unchanged by 01-08; regression-confirmed. |
| PROT-05 | 01-07 | Reconstruct state via versioned HTTPS snapshot-and-cursor, no persistent WebSocket | ✓ SATISFIED | Unchanged by 01-08; regression-confirmed. |

All 7 phase requirement IDs (OPER-01, OPER-02, PROT-01 through PROT-05) declared across the 8 plans (01-01 through 01-08) are accounted for in REQUIREMENTS.md's traceability table (each maps to Phase 1) — no orphaned requirements. Note: `.planning/REQUIREMENTS.md`'s per-requirement checkbox and Traceability-table `Status` column (`OPER-02`/`PROT-01..05` still show "Gaps Found", though only OPER-01 was ever actually gapped) reflect the pre-gap-closure state and were not updated as part of plan 01-08's scope — this is a documentation bookkeeping lag in a tracking artifact, not a code or functional gap; the actual truths behind those requirement IDs were fully verified in the initial pass and reconfirmed here by regression check.

### Human Verification Required

None outstanding. Both items from the prior `01-VERIFICATION.md` are discharged:

1. **OPER-01 compose smoke on a real Docker host** — `01-08-SUMMARY.md` records the verbatim `bash scripts/compose-smoke.sh` output ending in `[compose-smoke] SUCCESS`, run after both Dockerfile fixes, including the new blob-writability assertion and a restart-survival check on the `playstead_db` volume. Accepted per this task's instruction to treat recorded human/executor evidence as satisfied.
2. **UI-SPEC visual fidelity walkthrough** — `01-08-SUMMARY.md` records a human PASS verdict for all three screen groups (setup wizard; login/sessions/sudo/recovery-login; devices queue/list), with two honestly-disclosed coverage caveats: the recovery-code login flow itself was not hand-exercised (no codes were saved at setup time, so coverage rests on automated tests only), and the pairing approval card's claimed-vs-observed hierarchy (D-09) was not visually exercised because no pending request existed at walkthrough time. These are disclosed scope limitations, not contradicting evidence, and do not reopen the item — noted here for transparency, not as a new gap.

### Gaps Summary

No gaps remain. Plan 01-08 closed the single blocking gap from the prior verification pass: the Dockerfile now stages `docs/` before `RUN mix compile`, verified both by a direct, independently-reproduced red/green test of the new `Playstead.DockerBuildContextTest` guard and by re-reading the recorded, physically-executed `docker compose build` + `scripts/compose-smoke.sh` run on a real Docker host. A second real deployment blocker discovered mid-verification (`/app/blobs` unwritable by the `nobody` runtime user) was fixed within the same plan and is likewise proven by recorded evidence. All four roadmap success criteria for Phase 1 now hold, all seven phase requirement IDs are satisfied, and both outstanding human-verification items are discharged. One non-blocking, pre-existing test-suite flakiness issue (global `System.put_env` env-var race across async tests in `tls_trust_test.exs`/`setup_live_test.exs` vs. `devices_live_test.exs`) is documented above as a warning and recommended follow-up; it does not affect any roadmap truth and was not introduced by this phase's gap-closure work.

---

*Verified: 2026-08-28*
*Verifier: Claude (gsd-verifier)*
