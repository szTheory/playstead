---
phase: 01-private-custody-and-durable-protocol
verified: 2026-08-28T15:30:02Z
status: passed
score: 4/4 roadmap success criteria verified; 7/7 phase requirements satisfied
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: passed
  previous_score: 4/4 roadmap success criteria verified; 7/7 phase requirements satisfied
  gaps_closed:
    - "All seven human_judgment: true coverage items across the eight plan SUMMARYs (UI-SPEC visual fidelity of setup/login/sessions/sudo/devices; snapshot interleaved-write concurrency) are now human_judgment: false, backed by a real headless-Chrome Wallaby browser suite (test/playstead_web/browser/, 82 features / 9 files) that asserts UI-SPEC's actual palette hexes, typography tokens, and cross-screen coherence rules against the rendered DOM, plus a real-Postgres-transaction concurrency test (test/playstead/sync/snapshot_concurrency_test.exs) that proves the REPEATABLE READ isolation property under genuine concurrent commits rather than by inspection."
    - "A real correctness bug in Playstead.Sync.Snapshot was found and fixed: the isolation_level: :repeatable_read option passed to Repo.transaction/2 was silently ignored by Ecto/Postgrex (the transaction actually ran at the Postgres default READ COMMITTED). Snapshot.read/2 now issues an explicit SET TRANSACTION ISOLATION LEVEL REPEATABLE READ as the transaction's first statement, config-gated off only under the Ecto sandbox (config/test.exs set_isolation: false) because Postgres refuses a level change after a transaction has run a statement; the concurrency test re-enables it for its own top-level transactions and asserts SHOW transaction_isolation == 'repeatable read' at the exact commit-interleaving barrier."
  gaps_remaining: []
  regressions: []
---

# Phase 01: Private Custody and Durable Protocol Verification Report

**Phase Goal:** A self-hoster can run a private server and a Mac can pair and recover its authoritative state through a secure, versioned HTTPS protocol.
**Verified:** 2026-08-28T15:30:02Z
**Status:** passed
**Re-verification:** Yes — refreshing a `passed` report after the codebase and plan summaries changed post-verification (coverage-item conversion from human judgment to automated tests, a real snapshot isolation-level bug fix, console UI/font/palette changes, and a new CI workflow).

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A self-hoster can deploy the private server through the documented Docker Compose path with persistent database and blob volumes, then complete setup in the LiveView console. | ✓ VERIFIED | Unchanged since previous pass on the code that matters (Dockerfile `COPY docs docs` before `RUN mix compile`, `/app/blobs` chowned to `nobody`). Re-confirmed by reading `playstead-server/Dockerfile` directly (both lines present, correctly ordered) and by re-running `docker compose build && bash scripts/compose-smoke.sh --fresh` end-to-end today (`/tmp` / `~/.claude/jobs/55abde66/tmp/smoke2.log`, `COMPOSE_PROJECT_NAME=playstead-smoke-ci`): fresh volumes destroyed, stack brought up, all three services healthy, `/healthz` and `/api/v1/capabilities` return 200 through Caddy, `/app/blobs` writable, `playstead_db` marker row survives `down`+`up -d`, `SUCCESS`, `smoke exit=0`. A new `.github/workflows/ci.yml` `compose-smoke` job now runs this same path in CI on every push to `main` and on PRs touching deployment-surface files, closing the "who runs this next time" gap the previous verification flagged as a documentation lag. |
| 2 | An authenticated owner can approve a Mac pairing request, the Mac retains its scoped credential in Keychain, and the owner can revoke that device without disconnecting others. | ✓ VERIFIED | `Playstead.Pairing.approve/2`, `redeem/2`, `revoke_device/2` unchanged in substance; regression-confirmed by a full `mix precommit` run today (337 tests including the browser-driven `devices_journey_test.exs#pair → approve → redeem → rename → revoke (sudo) → tombstone`, 0 failures on the clean run). |
| 3 | A client can declare its protocol, app, cache, transfer, adapter, and save capabilities and receive a clear remedy when they are incompatible. | ✓ VERIFIED | `Playstead.Protocol.Negotiation.verdict/2`, `Remedy.build/3`, `POST /api/v1/hello` unchanged in substance; regression-confirmed by the same full suite run (`test/playstead/protocol/negotiation_test.exs`, `test/playstead_web/controllers/api/v1/hello_controller_test.exs`, 0 failures). |
| 4 | After a disconnection, a client can retry a mutation without creating another effect and reconstruct catalogue, job, transfer, and save state through HTTPS snapshot-and-cursor reads without a WebSocket. | ✓ VERIFIED | `Playstead.Idempotency.execute/4` unchanged. The convergence property is now proven more strongly than at the prior verification: `Playstead.Sync.Snapshot.read/2` was found to run at the Postgres default READ COMMITTED rather than the claimed REPEATABLE READ (Ecto/Postgrex silently drop the `isolation_level:` transaction option) and was fixed to issue an explicit `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ`. Read the fix directly in `lib/playstead/sync/snapshot.ex` (`set_isolation?/0` gate, `Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")` as the transaction's first statement) and the config gate (`config/test.exs:56` `set_isolation: false`, required because Postgres rejects a level change once a transaction — including the Ecto sandbox's single wrapping transaction — has already run a statement). `test/playstead/sync/snapshot_concurrency_test.exs` proves this under real, independently-committing Postgres transactions (`Sandbox.mode(Repo, :auto)`, `async: false`): one test asserts `Repo.query!("SHOW transaction_isolation").rows == [["repeatable read"]]` at the exact barrier where a competing write commits mid-transaction, then proves that write is excluded from the page and delivered exactly once on resume; a second test proves a 5-device, 3-page read with pairs/renames/revokes interleaved between pages converges to exactly the fresh state with every mutation delivered once. Both tests pass (`mix test test/playstead/sync/snapshot_concurrency_test.exs`, part of today's clean full-suite run). |

**Score:** 4/4 roadmap success criteria verified (unchanged from previous pass; SC4's underlying evidence base is now materially stronger than at the last verification, having caught and fixed a real bug).

### Coverage-Item Re-Audit (what actually changed since the previous VERIFICATION.md)

The previous `01-VERIFICATION.md` recorded two outstanding human-verification items already discharged by recorded evidence at that time (Docker compose smoke; UI-SPEC visual walkthrough). Since then, every plan SUMMARY's `coverage:` entries across all eight plans (01-01 through 01-08) were converted from `human_judgment: true`/absent to `human_judgment: false` with automated-test refs. Grepped every SUMMARY for `human_judgment` — **zero remaining `true` entries**; all 62 items are `false`, and `01-UAT.md`'s own summary line confirms `passed: 62 / issues: 0 / pending: 0 / skipped: 0 / blocked: 0`, `[none — every deliverable is deterministically covered; no human checkpoint remains]`.

| Coverage claim | Backing artifact | Verified how |
|---|---|---|
| UI-SPEC visual fidelity (setup wizard, login/sessions/sudo/recovery-login, Devices) | `test/playstead_web/browser/palette_test.exs`, `typography_test.exs`, `coherence_test.exs`, `states_test.exs`, `copy_test.exs`, plus 3 end-to-end journey tests and a smoke test — 9 files, 1,332 LOC, 82 Wallaby features | Read the actual assertions, not just filenames. `palette_test.exs` walks every computed color on every registered screen (`BrowserScreens.screens()`) and asserts it is one of the nine UI-SPEC hex values, and separately asserts the four semantic colors (accent/destructive/success/warning) appear only in an explicit allow-list of element ids/prefixes/suffixes. `coherence_test.exs` asserts the canvas background hex, the `Inter` font family, a single 28px/600 `h1`, no horizontal scroll at desktop and phone widths, and 44×44px minimum icon-only button targets with action-verb `aria-label`s — the screen registry itself is checked against the router `#the screen registry covers every console route in the router`) so a route cannot silently opt out of coverage. These are genuine DOM/computed-style assertions against a real headless Chrome, not smoke checks. |
| Snapshot interleaved-write concurrency (previously an inspection-only human-judgment claim) | `test/playstead/sync/snapshot_concurrency_test.exs` | Read in full (above). Switches the Ecto sandbox to `:auto` mode so independent test processes get real pooled Postgres connections and commit for real; proves both the in-transaction-commit-exclusion property and multi-page convergence. This exercise is what caught the real `isolation_level:` bug described above. |

### Required Artifacts (unchanged from previous pass, plus items introduced since)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-server/Dockerfile` | `COPY docs docs` before `RUN mix compile`; `/app/blobs` writable by `nobody` | ✓ VERIFIED | Unchanged; re-read directly. |
| `playstead-server/lib/playstead/sync/snapshot.ex` | Real REPEATABLE READ isolation, not a silently-dropped Ecto option | ✓ VERIFIED | `set_isolation?/0` reads `Application.get_env(:playstead, __MODULE__, []) |> Keyword.get(:set_isolation, true)`; `Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")` issued as the transaction's first statement when true. Module doc explicitly documents *why* (`isolation_level:` is silently ignored by Ecto/Postgrex) rather than glossing over it. |
| `playstead-server/config/test.exs` | `set_isolation: false` for `Playstead.Sync.Snapshot` under the sandbox | ✓ VERIFIED | Line 56, confirmed by grep and by the module doc's explanation of why the sandbox requires this (Postgres refuses a level change after any statement has run in a transaction, and the sandbox wraps a whole test in one). |
| `playstead-server/test/playstead/sync/snapshot_concurrency_test.exs` | Real independent-transaction proof of the isolation property and multi-page convergence | ✓ VERIFIED | 2 tests, both pass; asserts `SHOW transaction_isolation` directly at the critical barrier. |
| `playstead-server/test/playstead_web/browser/*` (9 files) | Automated UI-SPEC enforcement replacing the human visual walkthrough | ✓ VERIFIED | 82 features across palette/typography/coherence/states/copy/3 journeys/smoke; all pass in a clean run. |
| `.github/workflows/ci.yml` | CI gate running `mix precommit` (unit + LiveView + browser + integration) and a Docker cold-start compose-smoke job | ✓ VERIFIED | Read in full. `test` job runs `mix precommit` with a real Postgres service container and headless Chrome via `browser-actions/setup-chrome@v1`, uploads Wallaby failure screenshots on failure, and asserts a clean working tree post-build. `compose-smoke` job path-filters to infra-relevant files (or always runs on `main`), builds the real Docker image, and runs `scripts/compose-smoke.sh --fresh` with real generated secrets. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `Snapshot.read/2` transaction | Postgres | `Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")` gated by `set_isolation?/0` | ✓ WIRED | Confirmed by direct read and by the concurrency test's `SHOW transaction_isolation` assertion inside the actual code path (not a mock). |
| `test/playstead_web/browser/*` | Rendered DOM via Wallaby/ChromeDriver | `use PlaysteadWeb.BrowserCase`, `BrowserScreens.open/2`, `computed_style`/`style_walk`/`js` helpers | ✓ WIRED | Ran the full suite twice locally (chromedriver present); 82 features execute against a real headless Chrome instance, not a stub. |
| `.github/workflows/ci.yml` `test` job | `mix precommit` | `run: mix precommit` with `WALLABY_CHROME_BINARY` env from the Chrome setup step | ✓ WIRED | Read directly; matches the local `mix precommit` alias behavior exercised in this verification. |
| `.github/workflows/ci.yml` `compose-smoke` job | `scripts/compose-smoke.sh --fresh` | `docker/build-push-action@v6` then `bash scripts/compose-smoke.sh --fresh` | ✓ WIRED | Read directly; matches the manually re-run smoke path (`smoke2.log`) verified today. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full precommit-equivalent suite (unit + LiveView + browser + integration) | `cd playstead-server && mix precommit` | First run: 337 tests, 1 failure (`setup_wizard_journey_test.exs`, `#nav-account` not found — a Wallaby DOM-poll timing race). Isolated re-run of the same file: 1 feature, 0 failures. Full clean re-run: 337 tests, **0 failures**. | ⚠️ FLAKY (browser-suite timing, non-blocking — see Anti-Patterns) |
| Snapshot isolation level really takes effect under real concurrent transactions | `mix test test/playstead/sync/snapshot_concurrency_test.exs` (part of the clean full run) | 2 tests, 0 failures; asserts `SHOW transaction_isolation == 'repeatable read'` at the interleaving barrier | ✓ PASS |
| Docker Compose cold-start deployment (OPER-01), re-run today | `docker compose build && bash scripts/compose-smoke.sh --fresh` on a real Docker host | `SUCCESS`, `smoke exit=0` — fresh volumes, all services healthy, `/healthz`/`/api/v1/capabilities` 200, `/app/blobs` writable, `playstead_db` marker row survives restart (see `~/.claude/jobs/55abde66/tmp/smoke2.log`) | ✓ PASS (re-run, not just recorded evidence) |
| No debt markers in any file touched since the prior verification | `grep -n -E "TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER|placeholder|coming soon|not yet implemented" <every file in `git diff --name-only 8eb7baa..HEAD`>` | No matches in any of the ~75 touched files (lib, test, config, CI, scripts) | ✓ PASS |
| All commits referenced exist | `git log --oneline` | `55e0eba` (snapshot isolation fix), `cd56edd` (CI workflow), `52a4847` (console UI/palette/fonts), `f1b43ab`/`fbc9966` (browser suite) all present | ✓ PASS |

### Anti-Patterns Found

No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers and no "not yet implemented"/"coming soon" strings in any file touched since the previous verification (checked all ~75 files across `lib/`, `test/`, `config/`, `scripts/`, and `.github/workflows/`).

⚠️ **Warning (pre-existing flakiness class, narrower than before, non-blocking):** the previous verification documented a `System.put_env`-based async race in `tls_trust_test.exs`/`devices_live_test.exs`; commit `6b24ea8` (`fix(server): make transport-state env pure and async-safe (kills PLAYSTEAD_PROXY test flake)`) appears to have addressed that specific class — no failures of that kind occurred in either of today's two full runs. A *different*, new flake was observed once today: `setup_wizard_journey_test.exs`'s `#nav-account` assertion failed on the first full run (`Wallaby.ExpectationNotMetError` — element not yet rendered/visible when the assertion polled) and passed cleanly both in isolation and on an immediate full-suite re-run. This is consistent with ordinary headless-browser DOM-timing flakiness under load (36 max_cases running Wallaby sessions concurrently), not a functional defect — the same journey (`devices_journey_test.exs`, `auth_sessions_journey_test.exs`) exercises the identical `#nav-account` element and passed in both runs. Does not affect any roadmap success criterion. No action required for phase-goal purposes; worth a follow-up if browser-suite flakiness becomes disruptive to CI (e.g., raising Wallaby's default `max_wait_time` or reducing browser test concurrency).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| OPER-01 | 01-01, 01-08 | Deploy via Docker Compose with persistent volumes | ✓ SATISFIED | Re-run today, `SUCCESS`. REQUIREMENTS.md checkbox `[x]` and traceability table `Complete`. |
| OPER-02 | 01-02, 01-03 | Complete setup in LiveView console without editing data/API | ✓ SATISFIED | Regression-confirmed; REQUIREMENTS.md `[x]`/`Complete`. |
| PROT-01 | 01-04, 01-05 | Owner approves pairing, Mac stores scoped credential | ✓ SATISFIED | Regression-confirmed via `devices_journey_test.exs`; REQUIREMENTS.md `[x]`/`Complete`. |
| PROT-02 | 01-04, 01-05 | Review paired devices, revoke one without affecting others | ✓ SATISFIED | Regression-confirmed; REQUIREMENTS.md `[x]`/`Complete`. |
| PROT-03 | 01-01, 01-06 | Declare capabilities, get actionable incompatibility response | ✓ SATISFIED | Regression-confirmed; REQUIREMENTS.md `[x]`/`Complete`. |
| PROT-04 | 01-06 | Safe retry via durable receipt, no duplicate effect | ✓ SATISFIED | Regression-confirmed; REQUIREMENTS.md `[x]`/`Complete`. |
| PROT-05 | 01-07 | Reconstruct state via versioned HTTPS snapshot-and-cursor, no persistent WebSocket | ✓ SATISFIED | Strengthened by the isolation-level fix and the new real-transaction concurrency test; REQUIREMENTS.md `[x]`/`Complete`. |

All 7 phase requirement IDs (OPER-01, OPER-02, PROT-01 through PROT-05) are checked `[x]` and marked `Complete` in `.planning/REQUIREMENTS.md`'s traceability table — the "documentation bookkeeping lag" flagged as non-blocking in the previous verification is now resolved; no orphaned requirements.

### Human Verification Required

None. All 62 `01-UAT.md` items are `result: pass`, `source: automated`; the `01-UAT.md` Gaps section reads `[none — every deliverable is deterministically covered; no human checkpoint remains]`. Every coverage item across all eight plan SUMMARYs is `human_judgment: false` with an automated-test ref, confirmed by direct grep (zero `human_judgment: true` matches) and by reading the referenced tests' actual assertions rather than trusting the label.

### Gaps Summary

No gaps. This re-verification confirms the prior `passed` status still holds and finds the evidence base for two previously-fragile claims (UI-SPEC visual fidelity, snapshot concurrency correctness) has been substantially strengthened: what were `human_judgment: true`/inspection-based claims are now enforced by a real 82-feature headless-Chrome browser suite and a real-Postgres-transaction concurrency test, and that concurrency test caught and led to the fix of a genuine bug (`isolation_level:` being silently dropped by Ecto/Postgrex, leaving `Snapshot.read/2` at READ COMMITTED instead of the documented REPEATABLE READ). A CI workflow now runs the full precommit gate plus the Docker cold-start smoke on every relevant push/PR, closing the "who re-runs this" gap. One non-blocking, ordinary browser-suite DOM-timing flake was observed and reproduced-away (passes in isolation and on immediate re-run); it does not affect any roadmap truth.

---

*Verified: 2026-08-28T15:30:02Z*
*Verifier: Claude (gsd-verifier)*
