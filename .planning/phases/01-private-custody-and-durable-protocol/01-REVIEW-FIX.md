---
phase: 01-private-custody-and-durable-protocol
fixed_at: 2026-08-28T13:45:00Z
review_path: .planning/phases/01-private-custody-and-durable-protocol/01-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-08-28
**Source review:** .planning/phases/01-private-custody-and-durable-protocol/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (1 Critical, 6 Warning — Info findings out of scope per fix_scope)
- Fixed: 7
- Skipped: 0

All fixes were applied, compiled with `mix compile --warnings-as-errors`, and verified against the full test suite (296 tests, 0 failures) after each change, in an isolated git worktree.

## Fixed Issues

### CR-01: Recovery code and password-reset/setup tokens are not excluded from Phoenix's parameter-log filter

**Files modified:** `playstead-server/config/config.exs`, `playstead-server/test/playstead_web/filter_parameters_test.exs`
**Commit:** `fe75f88`
**Applied fix:** Added `code` and `token` to `config :phoenix, :filter_parameters, {:discard, ...}` alongside the existing `password device_code credential` keys. Added a regression test (analogous to `no_mailer_test.exs`) that asserts these keys are actually filtered at runtime via `Phoenix.Logger.filter_values/2` — the compiled form of the config can't be introspected directly by the time tests run (Phoenix rewrites it into an Aho-Corasick automaton at boot), so the test exercises the real filtering function instead of the raw config value.

### WR-01: No throttle on pairing-request redemption and setup-token verification

**Files modified:** `playstead-server/lib/playstead_web/router.ex`, `playstead-server/lib/playstead_web/live/setup_live.ex`, `playstead-server/lib/playstead_web/endpoint.ex`
**Commit:** `397e9c1`
**Applied fix:** Added a dedicated `:throttle_pairing_redeem` pipeline (distinct action key from `:throttle_pairing_request`) to `POST /requests/:id/redeem`; left the poll/`show` endpoint alone since it already has its own request-scoped rate limit (`Pairing.check_poll_rate/1`). Added `:peer_data` to the LiveView socket's `connect_info` and a fixed per-connect-IP rate limit (`Playstead.RateLimiter.hit/3`) on `SetupLive`'s `verify_token` event.

### WR-02: `PlaysteadWeb.Plugs.ClientIp` trusts `X-Forwarded-For` unconditionally with no proxy-count/format validation

**Files modified:** `playstead-server/config/config.exs`, `playstead-server/config/runtime.exs`, `playstead-server/lib/playstead_web/plugs/client_ip.ex`, `playstead-server/lib/playstead/release.ex`, `playstead-server/lib/playstead/application.ex`
**Commit:** `8eb7baa`
**Applied fix:** Made trusting `x-forwarded-for` an explicit, documented config flag (`:playstead, :trust_proxy_headers`, backed by `PLAYSTEAD_PROXY` env var in prod, default `true` to preserve current behavior). `ClientIp` now falls back to `conn.remote_ip` when the flag is `false`. Added `Playstead.Release.warn_if_proxy_trust_unacknowledged!/0`, invoked from `Application.start/2` in prod, which logs a boot-time warning (deliberately not a hard refusal, unlike the other two `Release` gates, to avoid breaking existing deployments) when `PLAYSTEAD_PROXY` is left unset.

### WR-03: `Idempotency.execute/4`'s Multi.run(:effect) reason is not normalized before comparison branches

**Files modified:** `playstead-server/lib/playstead_web/controllers/api/v1/fallback_controller.ex`
**Commit:** `4eefcc9`
**Applied fix:** Added a catch-all `call(conn, {:error, _reason})` clause to `FallbackController` that renders a generic `:internal_error` 500 directly, rather than relying on `ApiProblemHandler`'s exception path to paper over an unmatched reason shape.

### WR-04: `Compaction.oldest_surviving_seq/0` / `Sync.expired?/1` boundary is checked against the whole journal, not the requesting user's entries

**Files modified:** `playstead-server/lib/playstead/sync/compaction.ex`
**Commit:** `f9cf2bd`
**Applied fix:** Added a doc comment on `Compaction.oldest_surviving_seq/0` explicitly stating the global-minimum approach is only correct because `seq` is a single monotonic global counter and compaction is age-based across all owners, warning a future reader not to "fix" this into a per-user query without reconsidering the cross-owner `seq` ordering guarantee.

### WR-05: `ResetPasswordController` and `SetupLive`'s owner-claim step have no throttle either

**Files modified:** `playstead-server/lib/playstead_web/router.ex`, `playstead-server/lib/playstead_web/live/setup_live.ex`
**Commit:** `4dd7aee`
**Applied fix:** Added a `:throttle_reset` pipeline to `POST /reset/:token` (left the `GET` alone since it only renders the form). Added the same per-connect-IP rate limit pattern used for `verify_token` (WR-01) to `SetupLive`'s `create_owner` event, with a new `create_owner_error` assign rendered above the step-2 form on deny.

### WR-06 (addendum): The new build-context regression guard matches only the top-level path segment, not the actual required file path

**Files modified:** `playstead-server/test/playstead/docker_build_context_test.exs`
**Commit:** `c4ebf59`
**Applied fix:** Replaced the top-segment reduction (`Path.split(path) |> hd()`) with a real exact-or-prefix comparison (`staged?/2`) against the full relative resource path, so a Dockerfile `COPY` that narrows the `docs` staging to a subset of the directory (still matching the old top-segment check) would now correctly fail the test.

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-08-28_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
