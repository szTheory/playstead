---
phase: 01-private-custody-and-durable-protocol
reviewed: 2026-08-28T00:00:00Z
depth: standard
files_reviewed: 58
files_reviewed_list:
  - playstead-server/lib/playstead.ex
  - playstead-server/lib/playstead/accounts.ex
  - playstead-server/lib/playstead/accounts/recovery_code.ex
  - playstead-server/lib/playstead/accounts/scope.ex
  - playstead-server/lib/playstead/accounts/setup_token.ex
  - playstead-server/lib/playstead/accounts/user.ex
  - playstead-server/lib/playstead/accounts/user_token.ex
  - playstead-server/lib/playstead/application.ex
  - playstead-server/lib/playstead/audit_log.ex
  - playstead-server/lib/playstead/audit_log/entry.ex
  - playstead-server/lib/playstead/codes.ex
  - playstead-server/lib/playstead/command_id.ex
  - playstead-server/lib/playstead/idempotency.ex
  - playstead-server/lib/playstead/idempotency/prune_expired_worker.ex
  - playstead-server/lib/playstead/idempotency/receipt.ex
  - playstead-server/lib/playstead/pairing.ex
  - playstead-server/lib/playstead/pairing/device.ex
  - playstead-server/lib/playstead/pairing/device_credential.ex
  - playstead-server/lib/playstead/pairing/display_code.ex
  - playstead-server/lib/playstead/pairing/expire_stale_requests_worker.ex
  - playstead-server/lib/playstead/pairing/pairing_request.ex
  - playstead-server/lib/playstead/pairing/rotation_audit_worker.ex
  - playstead-server/lib/playstead/protocol/capabilities.ex
  - playstead-server/lib/playstead/protocol/capability_declaration.ex
  - playstead-server/lib/playstead/protocol/negotiation.ex
  - playstead-server/lib/playstead/protocol/remedy.ex
  - playstead-server/lib/playstead/rate_limiter.ex
  - playstead-server/lib/playstead/readiness.ex
  - playstead-server/lib/playstead/release.ex
  - playstead-server/lib/playstead/repo.ex
  - playstead-server/lib/playstead/setup.ex
  - playstead-server/lib/playstead/sync.ex
  - playstead-server/lib/playstead/sync/change_journal.ex
  - playstead-server/lib/playstead/sync/compaction.ex
  - playstead-server/lib/playstead/sync/compaction_worker.ex
  - playstead-server/lib/playstead/sync/cursor.ex
  - playstead-server/lib/playstead/sync/entity_kind.ex
  - playstead-server/lib/playstead/sync/entry.ex
  - playstead-server/lib/playstead/sync/snapshot.ex
  - playstead-server/lib/playstead/tls_trust.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/capabilities_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/changes_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/debug_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/devices_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/fallback_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/hello_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/pairing_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/snapshot_controller.ex
  - playstead-server/lib/playstead_web/controllers/health_controller.ex
  - playstead-server/lib/playstead_web/controllers/recovery_codes_controller.ex
  - playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex
  - playstead-server/lib/playstead_web/controllers/reset_password_controller.ex
  - playstead-server/lib/playstead_web/controllers/user_session_controller.ex
  - playstead-server/lib/playstead_web/endpoint.ex
  - playstead-server/lib/playstead_web/error_codes.ex
  - playstead-server/lib/playstead_web/live/devices_live.ex
  - playstead-server/lib/playstead_web/live/login_live.ex
  - playstead-server/lib/playstead_web/live/recovery_login_live.ex
  - playstead-server/lib/playstead_web/live/sessions_live.ex
  - playstead-server/lib/playstead_web/live/setup_live.ex
  - playstead-server/lib/playstead_web/live/sudo_live.ex
  - playstead-server/lib/playstead_web/plugs/api_problem_handler.ex
  - playstead-server/lib/playstead_web/plugs/client_ip.ex
  - playstead-server/lib/playstead_web/plugs/device_auth.ex
  - playstead-server/lib/playstead_web/plugs/idempotency.ex
  - playstead-server/lib/playstead_web/plugs/require_setup_open.ex
  - playstead-server/lib/playstead_web/plugs/sudo_mode.ex
  - playstead-server/lib/playstead_web/plugs/throttle.ex
  - playstead-server/lib/playstead_web/problem.ex
  - playstead-server/lib/playstead_web/router.ex
  - playstead-server/lib/playstead_web/user_auth.ex
  - playstead-server/config/config.exs
  - playstead-server/config/dev.exs
  - playstead-server/config/prod.exs
  - playstead-server/config/runtime.exs
  - playstead-server/config/test.exs
  - playstead-server/docker-compose.yml
  - playstead-server/Caddyfile
  - playstead-server/Dockerfile
  - playstead-server/priv/repo/migrations/20260827200000_create_idempotency_receipts.exs
  - playstead-server/priv/repo/migrations/20260827180001_create_devices_and_credentials.exs
  - playstead-server/priv/repo/migrations/20260827210000_add_command_id_to_device_credentials.exs
  - playstead-server/scripts/compose-smoke.sh
  - playstead-server/test/playstead/docker_build_context_test.exs
  - playstead-server/test/playstead_web/controllers/recovery_docs_controller_test.exs
findings:
  critical: 1
  warning: 6
  info: 4
  total: 11
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-08-28
**Depth:** standard
**Files Reviewed:** 58 (lib/ source files prioritized; config, migrations, and deploy files spot-checked; tests treated as lower-priority context; +3 files added by the 01-08 gap-closure incremental review)
**Status:** issues_found

## Summary

This phase implements owner auth, device pairing, capability negotiation, idempotency, and change-journal sync for a self-hosted Phoenix server. The domain code (`Playstead.Pairing`, `Playstead.Idempotency`, `Playstead.Sync.*`, `Playstead.Protocol.*`) is unusually disciplined about the properties it claims: constant-time comparisons are used correctly everywhere a secret is compared (`Plug.Crypto.secure_compare/2` for device codes and cursors, `Bcrypt.no_user_verify/0` on no-match paths), transactions are used correctly to keep idempotency receipts and change-journal entries atomic with the effects they describe, and the advisory-lock-based commit-order fencing in `ChangeJournal` is sound.

The one concrete gap found is a genuine cross-cutting issue: the Phoenix parameter-log filter (`config/config.exs`) discards `password`, `device_code`, and `credential`, but not the recovery-code (`code`) or password-reset/setup token (`token`) parameter keys, both of which are single-use authentication secrets that flow through controller actions whose params Phoenix logs by default. This directly contradicts this codebase's own stated discipline (`Playstead.AuditLog`'s doc comment: "metadata must never carry credential material or a plaintext token") and has no test coverage guarding it, unlike the mailer-removal regression guard the project takes care to test elsewhere.

The remaining findings are lower-severity gaps in defense-in-depth (missing rate limiting on a couple of unauthenticated endpoints) and a few small correctness/robustness nits. No SQL injection, XSS, insecure deserialization, or authorization-bypass vulnerabilities were found; the multi-tenant partitioning boundaries (`ChangeJournal.read_after/3`, `owned_device/2`, `Scope`-gated queries) are consistently enforced at the query level rather than trusted from caller state.

A follow-up incremental review of the 01-08 gap-closure plan (Dockerfile `docs` staging fix, the `/app/blobs` ownership fix, the new build-context regression guard, and the recovery-docs route) found no new Critical or exploitable issues, but did surface one Warning (the new regression-guard test's directory-level matching is coarser than the bug class it's meant to catch) and one Info item (the `/app/blobs` ownership fix has no documented remediation path for volumes provisioned before the fix). See the addendum below.

## Critical Issues

### CR-01: Recovery code and password-reset/setup tokens are not excluded from Phoenix's parameter-log filter

**File:** `playstead-server/config/config.exs:98`
**Issue:**
```elixir
config :phoenix, :filter_parameters, {:discard, ~w(password device_code credential)}
```
This list is missing the parameter keys that carry two other single-use authentication secrets in this application:

- `code` — the recovery-code login submits `%{"recovery" => %{"code" => "<plaintext code>"}}` to `POST /log-in/recovery` (`PlaysteadWeb.UserSessionController.create_via_recovery/2`, wired at `router.ex:193`). Phoenix's default controller instrumentation (`Phoenix.Logger`) logs `conn.params` filtered only by this list, recursing into nested maps — a key literally named `"code"` is not caught by `password`/`device_code`/`credential` and will be logged in the clear on every recovery-code login attempt (successful or not).
- `token` — `GET /reset/:token` and `POST /reset/:token` (`PlaysteadWeb.ResetPasswordController`) carry the single-use, short-expiry password-reset token as a path parameter, which also lands in `conn.params["token"]` and is logged the same way.

Both of these are exactly the kind of "credential material or a plaintext token" `Playstead.AuditLog`'s own module doc explicitly forbids leaking (`lib/playstead/audit_log.ex:12`), and unlike the mailer-removal property (`test/playstead_web/no_mailer_test.exs`), there is no regression test guarding this filter list — confirmed by grep, `filter_parameters`/`discard` appears nowhere in `test/`.

Impact: a recovery code is bcrypt-hashed at rest and single-use, but if it leaks into a log aggregator (common in self-hosted Docker setups piping `docker compose logs` somewhere), an attacker with log read access gets a live, unconsumed credential — the recovery code hasn't been consumed by the point the request is logged, so this is not merely historical residue. The reset token is even more directly exploitable: it is valid for a full hour after being logged, and anyone with log access can complete the password reset and full session wipe/takeover during that window.

**Fix:**
```elixir
config :phoenix, :filter_parameters, {:discard, ~w(password device_code credential code token)}
```
Add a regression test analogous to `no_mailer_test.exs` asserting these keys are present in `Application.get_env(:phoenix, :filter_parameters)`.

## Warnings

### WR-01: No throttle on pairing-request redemption and setup-token verification

**File:** `playstead-server/lib/playstead_web/router.ex:98-105`, `playstead-server/lib/playstead_web/live/setup_live.ex:251-259`
**Issue:** `POST /api/v1/device-pairing/requests/:id/redeem` and `GET/POST` `/api/v1/device-pairing/requests/:id` (the `show`/poll endpoint) are only wrapped in the plain `:api` pipeline — no `PlaysteadWeb.Plugs.Throttle` is attached. The poll endpoint has its own request-scoped rate limit (`Pairing.check_poll_rate/1`), but the redemption endpoint has no per-IP or per-request throttle at all: nothing stops an attacker from firing redemption attempts against a given `id` as fast as the network allows. Similarly, `PlaysteadWeb.SetupLive.handle_event("verify_token", ...)` runs over a LiveView socket with no rate limiting at all — an attacker who can reach `/setup` (only possible pre-claim, per `RequireSetupOpen`, but that window always exists on a fresh install) can fire `verify_token` events far faster than an HTTP-pipeline-throttled endpoint would allow.
Both `device_code` and the setup token are 256-bit values, so brute force is not practically feasible even unthrottled — this is a defense-in-depth gap, not an exploitable weakness on its own, but it is inconsistent with the throttling discipline applied everywhere else credentials are checked (login, sudo, recovery).
**Fix:** Add `pipe_through [:api, :throttle_pairing_request]` (or a dedicated action) to the redeem/show routes, and consider debouncing/rate-limiting `verify_token` LiveView events the same way (e.g. via `Playstead.RateLimiter.hit/3` keyed on the socket's connect IP).

### WR-02: `PlaysteadWeb.Plugs.ClientIp` trusts `X-Forwarded-For` unconditionally with no proxy-count/format validation

**File:** `playstead-server/lib/playstead_web/plugs/client_ip.ex:27-38`
**Issue:** The module's own doc comment states the safety of trusting `x-forwarded-for` depends entirely on an external, undeclared structural invariant — "only the Caddy container publishes host ports" from `docker-compose.yml`. Nothing in this module (or anywhere at the Plug level) verifies that invariant at runtime; if the app is ever run with its port directly published (a misconfiguration a self-hoster could easily introduce when adapting the compose file, or when running outside Docker entirely per `docs/DEPLOY.md`'s "external proxy" path), any external client can forge `x-forwarded-for` and this plug will silently trust it. `client_ip` feeds directly into `Playstead.Pairing.create_request/1`'s `requesting_ip` and per-IP throttle buckets, so a forged value lets an attacker both evade per-IP throttling (spoof a fresh IP each request) and pollute the audit trail's IP attribution for pairing requests.
**Fix:** At minimum, document this as an explicit deployment precondition checked at boot (e.g. warn/refuse when `PLAYSTEAD_PROXY` is unset and the app is not behind Caddy), or take only the trusted-hop value when the connection genuinely originates from the compose network (e.g. validate `conn.remote_ip` is in a configured trusted-proxy CIDR before honoring the header at all, rather than trusting it unconditionally).

### WR-03: `Idempotency.execute/4`'s Multi.run(:effect) reason is not normalized before comparison branches

**File:** `playstead-server/lib/playstead/idempotency.ex:100-116`
**Issue:** `effect_fun.()` is allowed to return any `{:error, reason}`; the resulting `Ecto.Multi` failure is routed to `{:error, reason}` verbatim in `execute/4`'s final `case`. Callers (`DevicesController.run_idempotent/3`) then pass that raw `reason` straight to `FallbackController.call(conn, {:error, reason})`, which only has clauses for `:not_found`, `:unauthorized`, `%Ecto.Changeset{}`, and `{atom, binary}` tuples. `Pairing.rotate_credential/2` can return `{:error, {:invalid_command_id, "must be a valid UUIDv7 string"}}` (handled — matches the `{atom, binary}` clause) but `Pairing.update_self_report/2`'s `Repo.rollback(changeset)` path, or any future effect function that rolls back with an atom not in that closed set, would fall through `FallbackController` with no matching clause and raise a `FunctionClauseError` — which is at least caught by `ApiProblemHandler` and turned into a generic 500, but loses the specific error code/status the caller intended.
**Fix:** Either constrain `effect_fun`'s contract more explicitly (spec/dialyzer) to only return reasons `FallbackController` already handles, or add a final catch-all clause to `FallbackController.call/2` that renders a generic `:internal_error` 500 rather than relying on `ApiProblemHandler`'s exception path to paper over an unmatched reason shape.

### WR-04: `Compaction.oldest_surviving_seq/0` / `Sync.expired?/1` boundary is checked against the whole journal, not the requesting user's entries

**File:** `playstead-server/lib/playstead/sync.ex:63-67`, `playstead-server/lib/playstead/sync/compaction.ex:53-56`
**Issue:** `oldest_surviving_seq/0` computes `min(seq)` across the entire `change_journal_entries` table (all users), and `Sync.expired?/1` compares a given user's decoded cursor against that global minimum. Because `seq` is a single global `bigserial` and compaction deletes rows purely by age (`inserted_at < cutoff`) regardless of owner, this happens to be correct today — but it is a global invariant the read path depends on without asserting it, and the comment set describing `read_after/3`'s per-owner partitioning (`change_journal.ex:97-103`) doesn't call out that the compaction/expiry boundary is deliberately *not* per-owner. A future change that partitions compaction per-owner (e.g. to let an under-utilized user's history survive longer) would silently break this cross-cutting assumption with no test failure pointing at the actual cause.
**Fix:** Add a code comment on `Compaction.oldest_surviving_seq/0` (or `Sync.expired?/1`) explicitly stating that the global-minimum approach is only correct because `seq` is a single monotonic global counter and compaction is age-based across all owners, so a future reader knows not to "fix" this into a per-user query without also reconsidering the cross-owner `seq` ordering guarantee.

### WR-05: `ResetPasswordController` and `SetupLive`'s owner-claim step have no throttle either

**File:** `playstead-server/lib/playstead_web/router.ex:242-248`
**Issue:** `POST /reset/:token` (password reset completion) and the `/setup` wizard's `create_owner` step are reachable with no throttling pipeline. Both are gated by high-entropy, single-use, short-lived tokens so brute force isn't practical, but `POST /reset/:token`'s failure path (`{:error, %Ecto.Changeset{}}`) re-renders the form with the same token still valid — an attacker who obtained a reset token (e.g. via CR-01's log leak) could try many password payloads without being throttled. This compounds CR-01: fixing the log leak removes the most likely way a token leaks, but the missing throttle here means a leaked token's window of exploitability isn't otherwise mitigated.
**Fix:** Add the existing `:throttle_recovery`-style pipeline (or a new `:throttle_reset` action) to the `/reset/:token` scope.

## Info

### IN-01: `Playstead.Idempotency.fetch/3`'s fingerprint over `conn.params` also covers query-string parameters

**File:** `playstead-server/lib/playstead_web/plugs/idempotency.ex:41`
**Issue:** `Idempotency.fingerprint/1` is built from `conn.params`, which in Phoenix is the union of path, query, and body params. For the two idempotent routes today (`PATCH /devices/me`, `POST /devices/me/rotate`) this is harmless since neither uses query params, but it's a latent trap: a client that appends an incidental query parameter (e.g. a cache-busting `?_=123`) to an otherwise-identical idempotent request would get `{:error, :mismatch}` (422) instead of a replay, which is a confusing failure mode for a property meant to make retries safe.
**Fix:** Build the fingerprint from `conn.body_params` (and, if needed, an explicit allowlist of path params) rather than the full merged `conn.params`, so query-string variance can never affect idempotency-key semantics.

### IN-02: `Playstead.Pairing.insert_credential/3`'s `command_id`-less branch is not covered by the same convergence guarantee as documented

**File:** `playstead-server/lib/playstead/pairing.ex:340-388`
**Issue:** The module doc for `insert_credential/2` extensively documents the `command_id` on-conflict convergence behavior, but the plain (`command_id == nil`) branch used by initial pairing redemption (`finalize_redemption/1`) has no such guard — a caller invoking `insert_credential(device_id, nil, nil)` twice for the same device (which can't currently happen given `finalize_redemption/1`'s guarded `WHERE status = 'approved'` update, but is not structurally prevented by `insert_credential/3` itself) would insert two live, unrelated credential rows for one device with no superseding relationship between them. This is currently unreachable in practice but the function's own safety is entirely borrowed from its caller's transaction discipline rather than being self-contained.
**Fix:** No code change strictly required given current callers, but consider a doc note on `insert_credential/3` clarifying that duplicate-prevention for the `command_id == nil` path is the caller's responsibility, not this function's.

### IN-03: Recovery code entropy is lower than the device credential's

**File:** `playstead-server/lib/playstead/codes.ex:14-15`, `playstead-server/lib/playstead/pairing.ex:27-28`
**Issue:** Recovery codes are drawn from a 20-character alphabet, 8 characters total (`log2(20) * 8 ≈ 34.6 bits`), hashed with bcrypt and rate-limited via `:throttle_recovery` — reasonable for a bcrypt-verified, throttled, single-use human-entered code, and not a bug. Flagging only because the module doc's framing ("shares one visual language" with the pairing display code) could read as implying equivalent security properties with the 256-bit `device_code`/credential material elsewhere in the same file set; a reader skimming for "is this a strong secret" could be misled without checking the actual `Enum.map(1..8, ...)` cardinality.
**Fix:** None required; consider a one-line comment on `Codes.random_code/2`'s default arguments noting the resulting ~34.6-bit space is intentional given bcrypt + throttle + single-use, to preempt this exact question in future review.

## Gap-closure addendum (plan 01-08)

Incremental review of the five files changed by the 01-08 gap-closure plan (commits `b6af64e`, `830ab8b`, `c1b2c02`): `playstead-server/Dockerfile`, `playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex`, `playstead-server/scripts/compose-smoke.sh`, `playstead-server/test/playstead/docker_build_context_test.exs`, `playstead-server/test/playstead_web/controllers/recovery_docs_controller_test.exs`. No new Critical issues. Two new findings below; everything else checked out: the `COPY docs docs` staging order is correct relative to `RUN mix compile`, the `@external_resource`/`File.read!/1` embed in `RecoveryDocsController` fails loudly at compile time if the file is missing (no silent fallback), the route is intentionally unauthenticated and serves static content with no injection surface, the `/app/blobs` mkdir+chown runs before `USER nobody` in the runner stage (correct ordering for the intended fix), and the smoke script's new blob-writability assertion correctly runs as the container's actual runtime user (`nobody`) via `$COMPOSE exec -T app`.

### WR-06: The new build-context regression guard matches only the top-level path segment, not the actual required file path

**File:** `playstead-server/test/playstead/docker_build_context_test.exs:77-83, 87-102`
**Issue:** `top_segment/1` reduces both the required `@external_resource` path and every `COPY` source to just their first path component (`Path.split(path) |> hd()`), and `staged_top_segments/0` builds a `MapSet` of only those first components. The comparison in the main test is then set membership on that single top-level segment (lines 21-24), not a path-prefix or exact-path check against the real required resource.

This is coarser than the regression class the test's own moduledoc says it exists to catch. Today `COPY docs docs` genuinely stages the whole `docs/` tree so this happens to be correct, but the guard would equally report "staged" (false green) for a Dockerfile line like `COPY docs/some-other-file.txt docs/some-other-file.txt` or `COPY docs/images docs/images` — both reduce to top segment `"docs"` — even though neither actually copies `docs/RECOVERY.md` into the builder stage. Since `@recovery_doc_path` is read at compile time with `File.read!/1`, that specific failure mode (a Dockerfile edit that narrows the `docs` COPY to a subset of the directory) would break `docker build` while this test still passes, silently defeating the guard it was written to be.
**Fix:** Compare on the actual relative resource path rather than only its top segment, e.g.:
```elixir
defp staged?(resource_relative, staged_sources) do
  Enum.any?(staged_sources, fn source ->
    source == resource_relative or String.starts_with?(resource_relative, source <> "/")
  end)
end
```
and build `staged_sources` from the full (non-reduced) `copy_sources/1` output rather than `Enum.map(&(&1 |> Path.split() |> hd()))`. Keep the top-segment reduction only as a fallback/diagnostic in the failure message, not as the actual pass/fail predicate.

### IN-04: `/app/blobs` ownership fix has no documented remediation path for volumes provisioned before the fix

**File:** `playstead-server/Dockerfile:102-106`
**Issue:** `docker-compose.yml`'s `playstead_blobs` named volume was introduced in an earlier commit (`bcadf3b`, phase 01-01), predating this fix (`c1b2c02`). Docker only populates a named volume's initial ownership/contents from the image directory it shadows the *first* time that volume is used against a given image path; a volume that was already initialized against an older image build (without this `mkdir -p /app/blobs && chown nobody /app/blobs` step) would already exist as a root-owned empty directory, and pulling this fixed image alone will not retroactively `chown` an already-provisioned volume — Docker does not re-run that population step for a volume that already has content (even zero files, since the directory entry itself already exists).

In practice this is self-diagnosing rather than silently broken: `Playstead.Readiness` checks blob-directory writability and would surface `"/app/blobs is not writable"` on the setup wizard (as it did during this same plan's human-verification walkthrough, per `01-08-SUMMARY.md`). But `docs/UPGRADE.md` (read as supporting context) documents backup/restore and image-tag bump steps and says nothing about this specific failure mode or how to fix it (e.g. `docker compose exec -u root app chown nobody /app/blobs`), so an affected self-hoster gets a correct-but-unexplained readiness error with no in-repo pointer to the fix.
**Fix:** Add a short troubleshooting note to `docs/UPGRADE.md` (or `docs/DEPLOY.md`) covering this exact symptom and the one-line remediation (`docker compose exec -u root app chown nobody /app/blobs`, or delete-and-recreate the volume from a fresh backup if it's still empty).

---

_Reviewed: 2026-08-28_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
