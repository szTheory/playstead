---
phase: 01-private-custody-and-durable-protocol
plan: 03
subsystem: auth
tags: [phoenix, liveview, hammer, ecto, bcrypt, sudo-mode, rate-limiting, audit-log]

requires:
  - phase: 01-02
    provides: "Playstead.Accounts owner model, Scope, phx.gen.auth session tokens, recovery codes, password_reset UserToken context, LoginLive"
provides:
  - "Playstead.AuditLog: append-only audit entries (record/3 only, no update/delete) for session, sudo, reset, and recovery events"
  - "Accounts.list_sessions/1, revoke_session/2, delete_all_sessions/1 — scoped by %Scope{}, never cross accounts"
  - "PlaysteadWeb.SessionsLive at /settings/sessions: per-session revocation, generic 'Browser session' label, current-session exclusion"
  - "PlaysteadWeb.Plugs.SudoMode (router plug + LiveView on_mount): fresh re-authentication gate for dangerous actions, reused by plan 01-05"
  - "PlaysteadWeb.Plugs.Throttle: hammer-backed fixed per-IP/per-account limits on login, sudo, and recovery-code submission"
  - "Scheme-aware session/remember-me cookie posture (HttpOnly + SameSite=Lax always, Secure only over HTTPS) verified end-to-end"
  - "Playstead.Release.reset_owner_password/0: the D-05a host-side email-free recovery command"
  - "PlaysteadWeb.RecoveryLoginLive + Accounts.consume_recovery_code/2: D-05b email-free recovery-code login"
  - "Accounts.regenerate_recovery_codes/1 reachable only through the sudo-mode gate"
  - "docs/RECOVERY.md, served at /docs/recovery — the login screen's 'Locked out?' destination"
affects: [01-05]

actuals:
  tokens: 20036
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Scheme-aware cookie Secure attribute achieved by deliberately NOT setting :secure in Plug.Session/remember-me cookie options — Plug.Conn.put_resp_cookie/4 already defaults secure:true only when conn.scheme is :https, so reinventing this would have been redundant and riskier than trusting Plug's own behavior"
    - "Sudo-mode re-confirmation reuses the existing UserSessionController.create/2 login endpoint rather than adding a parallel controller: an already-authenticated user re-submitting the same credentials is detected via conn.assigns.current_scope, and records a sudo_confirmed audit entry instead of a plain-login one"
    - "SudoMode is wired both as a router-pipeline plug (covers controller actions and disconnected LiveView mounts) and as a LiveView on_mount hook (covers LiveView-to-LiveView navigate, which bypasses the router's plug pipeline) — same freshness check, two integration points"
    - "Throttle limits are overridable per-call and via Application config; config/test.exs raises them to 100_000 so the full test suite's real POST /log-in traffic (many tests sharing ConnTest's default 127.0.0.1) never self-throttles, while Throttle's own test file exercises the real fixed-limit behavior with small explicit per-call limits"
    - "Password-reset token consumption reuses Accounts.update_user_password/2's existing delete-all-tokens side effect for single-use enforcement, rather than a separate token-deletion step"

key-files:
  created:
    - playstead-server/lib/playstead/audit_log.ex
    - playstead-server/lib/playstead/audit_log/entry.ex
    - playstead-server/lib/playstead/rate_limiter.ex
    - playstead-server/lib/playstead_web/plugs/sudo_mode.ex
    - playstead-server/lib/playstead_web/plugs/throttle.ex
    - playstead-server/lib/playstead_web/live/sessions_live.ex
    - playstead-server/lib/playstead_web/live/sudo_live.ex
    - playstead-server/lib/playstead_web/live/recovery_login_live.ex
    - playstead-server/lib/playstead_web/controllers/reset_password_controller.ex
    - playstead-server/lib/playstead_web/controllers/recovery_codes_controller.ex
    - playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex
    - playstead-server/docs/RECOVERY.md
    - playstead-server/priv/repo/migrations/20260827170500_add_client_label_to_users_tokens.exs
    - playstead-server/priv/repo/migrations/20260827170501_create_audit_log_entries.exs
    - playstead-server/test/playstead/audit_log_test.exs
    - playstead-server/test/playstead/accounts_recovery_test.exs
    - playstead-server/test/playstead_web/plugs/sudo_mode_test.exs
    - playstead-server/test/playstead_web/plugs/throttle_test.exs
    - playstead-server/test/playstead_web/live/sessions_live_test.exs
    - playstead-server/test/playstead_web/live/sudo_live_test.exs
    - playstead-server/test/playstead_web/session_cookie_test.exs
  modified:
    - playstead-server/lib/playstead/accounts.ex
    - playstead-server/lib/playstead/accounts/user_token.ex
    - playstead-server/lib/playstead/release.ex
    - playstead-server/lib/playstead/application.ex
    - playstead-server/lib/playstead_web/user_auth.ex
    - playstead-server/lib/playstead_web/endpoint.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead_web/controllers/user_session_controller.ex
    - playstead-server/lib/playstead_web/live/login_live.ex
    - playstead-server/config/test.exs

key-decisions:
  - "Cookie Secure attribute is scheme-aware for free via Plug.Conn.put_resp_cookie/4's own default behavior — no custom before_send rewriting needed, since neither the session nor remember-me cookie options set :secure explicitly"
  - "Sudo re-confirmation posts through the existing /log-in controller action rather than a new endpoint, distinguishing a re-confirm from a fresh login by checking whether the requester was already authenticated as the same user"
  - "Reset-password and recovery-code-regeneration UIs are plain server-rendered HTML forms (not LiveView) since they need no client-side interactivity beyond a single submit — kept minimal given the human-judgment visual UAT for LiveView surfaces is scoped to Sessions/Sudo/RecoveryLogin"
  - "regenerate_recovery_codes/1 relies entirely on router-level sudo gating for its 'reachable only through sudo mode' guarantee — the context function itself performs no sudo check, so any future caller must gate access before invoking it"

requirements-completed: [OPER-02]

coverage:
  - id: D1
    description: "The owner can see a list of their own browser sessions and revoke any one individually without ending the others"
    requirement: OPER-02
    verification:
      - kind: integration
        ref: "test/playstead_web/live/sessions_live_test.exs#revoking a session revoking one session leaves another session's token valid"
        status: pass
    human_judgment: false
  - id: D2
    description: "Console session cookies are HttpOnly and SameSite=Lax, and Secure is set when and only when the request scheme is HTTPS"
    verification:
      - kind: integration
        ref: "test/playstead_web/session_cookie_test.exs (both http and https, through the real router pipeline)"
        status: pass
      - kind: unit
        ref: "test/playstead_web/user_auth_test.exs#cookie posture (D-06) (remember-me cookie, both schemes)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Remember-me is on by default with a ~60-day window, backed by database session tokens that revocation actually invalidates"
    verification:
      - kind: unit
        ref: "test/playstead_web/user_auth_test.exs#log_in_user/3 writes a cookie if remember_me is configured"
        status: pass
    human_judgment: false
  - id: D4
    description: "Device revocation, credential change, and recovery-code regeneration each require a fresh password re-entry through sudo mode before they execute"
    requirement: OPER-02
    verification:
      - kind: unit
        ref: "test/playstead_web/plugs/sudo_mode_test.exs (fresh/stale/absent sudo confirmation, cross-user isolation)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/sessions_live_test.exs#GET /settings/sessions redirects to /sudo without a fresh sudo confirmation"
        status: pass
    human_judgment: false
  - id: D5
    description: "Login attempts are throttled per IP and per account with a fixed limit, not an adaptive lockout"
    verification:
      - kind: unit
        ref: "test/playstead_web/plugs/throttle_test.exs (per-IP limit, per-account limit across IPs, independent action buckets)"
        status: pass
    human_judgment: false
  - id: D6
    description: "An owner locked out without email can run one documented docker compose exec command that prints a single-use, short-lived reset URL, terminates every existing session, and writes an audit entry"
    requirement: OPER-02
    verification:
      - kind: unit
        ref: "test/playstead/accounts_recovery_test.exs#Release.reset_owner_password/0 (prints URL, deletes sessions, writes audit entry, no-owner case)"
        status: pass
    human_judgment: false
  - id: D7
    description: "An owner can log in by consuming one single-use recovery code, which is then permanently spent and rate-limited like a password"
    verification:
      - kind: unit
        ref: "test/playstead/accounts_recovery_test.exs#Accounts.consume_recovery_code/2 (recovery login path) a consumed recovery code cannot be reused"
        status: pass
    human_judgment: false
  - id: D8
    description: "Session, sudo, revocation, and recovery events are recorded in an append-only audit log"
    verification:
      - kind: unit
        ref: "test/playstead/audit_log_test.exs#record/3 carries no update or delete function"
        status: pass
      - kind: unit
        ref: "test/playstead/accounts_recovery_test.exs (password_reset_issued and recovery_code_consumed entries recorded)"
        status: pass
    human_judgment: false
  - id: D9
    description: "A reset token cannot be consumed twice, and an expired reset token is rejected"
    verification:
      - kind: unit
        ref: "test/playstead/accounts_recovery_test.exs#Accounts.reset_password_with_token/2 (twice-consumed, expired, unknown token cases)"
        status: pass
    human_judgment: false
  - id: D10
    description: "The session list's, sudo modal's, and error banner's visual design (dark console surface, spacing scale, JetBrains Mono where applicable, loading/error/empty/overflow/zero-one-many states) reads as intended per the UI-SPEC"
    verification: []
    human_judgment: true
    rationale: "Automated tests assert markup/text/state-transition behavior (labels, ARIA attributes, redirect targets, revoke/restore logic), not visual fidelity to the UI-SPEC's color, spacing, typography, and truncation/tooltip contract — this needs a human (or the phase's end-of-phase UAT pass) to confirm the rendered Sessions/Sudo/RecoveryLogin surfaces actually look like the dark console spec describes, including the two backstop items (sudo modal layout under a longer validation message; flash/banner wrapping of arbitrary-length remedy text)"

duration: ~90min
completed: 2026-08-27
status: complete
---

# Phase 01 Plan 03: Sessions, Sudo Mode, Throttling, and Email-Free Recovery Summary

**A Sessions list with per-session revocation, a reusable sudo-mode re-authentication gate, scheme-aware cookie posture proven end-to-end through the real Plug.Session pipeline, hammer-backed fixed login/sudo/recovery throttling, an append-only audit log, and two email-free recovery paths (a host-side `docker compose exec` reset command and single-use recovery-code login).**

## Performance

- **Duration:** ~90 min
- **Tasks:** 2 (both `tdd="true"`)
- **Files created:** 21
- **Files modified:** 10

## Accomplishments

- `Playstead.AuditLog.record/3` is the only write path onto the new append-only `audit_log_entries` table — no update or delete function exists anywhere in the module (T-01-18), verified directly with `function_exported?/2` checks
- `Accounts.list_sessions/1`, `revoke_session/2`, and `delete_all_sessions/1` all take `%Scope{}` first, so a session can never be listed or revoked across accounts; `PlaysteadWeb.SessionsLive` renders them with the current session excluded from revocation and a generic "Browser session" label when the client string isn't recognizable (T-01-19) — the raw user-agent string is never persisted
- The session and remember-me cookies never set `:secure` explicitly; `Plug.Conn.put_resp_cookie/4`'s own `maybe_secure_cookie/2` already sets `secure: true` only when `conn.scheme` is `:https`, so the D-06 scheme-aware requirement was satisfied by *not* reinventing behavior Plug already provides correctly — proven with an end-to-end test posting real `https://` and `http://` requests through the router and inspecting the actual `Set-Cookie` response
- `PlaysteadWeb.Plugs.SudoMode` gates session revocation and recovery-code regeneration behind a fresh (`Accounts.sudo_mode?/2`, ~20 min) password re-entry, wired both as a router pipeline plug and a LiveView `on_mount` hook (the latter covers LiveView `navigate`, which bypasses the router's plug pipeline entirely) — `PlaysteadWeb.SudoLive` reuses the existing `/log-in` controller action for re-confirmation rather than duplicating login logic, distinguishing a sudo re-confirm from a fresh login by checking whether the requester was already authenticated as the same user
- `PlaysteadWeb.Plugs.Throttle` (hammer, fixed window, chosen in plan 01-01) enforces separate per-IP and per-account buckets for `:login` and `:recovery` actions; limits are overridable per call and via `config :playstead, PlaysteadWeb.Plugs.Throttle` — raised in `config/test.exs` so the full suite's shared-127.0.0.1 test traffic never self-throttles, while `Throttle`'s own test exercises the real fixed-limit behavior with small explicit limits
- `Playstead.Release.reset_owner_password/0` — the D-05a `docker compose exec` command — mints a single-use, hash-stored `:password_reset` token, deletes every session token for the owner, records a `password_reset_issued` audit entry, and prints the reset URL to stdout exactly once, all inside one transaction
- `PlaysteadWeb.RecoveryLoginLive` + `UserSessionController.create_via_recovery/2` implement D-05b: logging in with one single-use recovery code, throttled on the `:recovery` bucket; `Accounts.regenerate_recovery_codes/1` is reachable only through the `:require_sudo` router pipeline
- `docs/RECOVERY.md` documents both recovery paths in one place; the login screen's "Locked out?" link now resolves via `PlaysteadWeb.RecoveryDocsController` instead of a placeholder href

## Task Commits

1. **Task 1: Sessions list, sudo-mode gate, cookie posture, and login throttling** - `eb093ec` (feat, tdd)
2. **Task 2: Email-free credential recovery — release reset command and recovery-code login** - `100d16c` (feat, tdd)

## Files Created/Modified

- `playstead-server/lib/playstead/audit_log.ex`, `audit_log/entry.ex` - Append-only audit entries
- `playstead-server/lib/playstead/rate_limiter.ex` - Hammer ETS-backed rate limiter
- `playstead-server/lib/playstead_web/plugs/sudo_mode.ex` - Router plug + LiveView on_mount sudo gate
- `playstead-server/lib/playstead_web/plugs/throttle.ex` - Fixed per-IP/per-account throttling
- `playstead-server/lib/playstead_web/live/sessions_live.ex` - Sessions list with per-session revocation
- `playstead-server/lib/playstead_web/live/sudo_live.ex` - Sudo re-authentication prompt
- `playstead-server/lib/playstead_web/live/recovery_login_live.ex` - Recovery-code login form
- `playstead-server/lib/playstead_web/controllers/reset_password_controller.ex` - Consumes the reset token
- `playstead-server/lib/playstead_web/controllers/recovery_codes_controller.ex` - Regenerates recovery codes (sudo-gated)
- `playstead-server/lib/playstead_web/controllers/recovery_docs_controller.ex` - Serves docs/RECOVERY.md
- `playstead-server/docs/RECOVERY.md` - The one-line `docker compose exec` recovery documentation
- `playstead-server/lib/playstead/accounts.ex` - Sessions, recovery, and reset-token functions
- `playstead-server/lib/playstead/release.ex` - `reset_owner_password/0`
- `playstead-server/lib/playstead_web/user_auth.ex` - Client label derivation, 60-day remember-me window
- `playstead-server/lib/playstead_web/endpoint.ex`, `router.ex`, `controllers/user_session_controller.ex` - Cookie posture, routes, sudo-aware login

## Decisions Made

- Scheme-aware cookie `Secure` attribute achieved by deliberately omitting `:secure` from both cookie configs, trusting `Plug.Conn.put_resp_cookie/4`'s built-in scheme-aware default rather than adding custom `before_send` rewriting logic
- Sudo re-confirmation reuses `UserSessionController.create/2` (the existing login endpoint) instead of a parallel controller, keyed on whether the requester is already authenticated as the same user
- Reset-password and recovery-code-regeneration pages are plain server-rendered HTML (not LiveView) — no client-side interactivity needed beyond a single form submit
- `regenerate_recovery_codes/1` performs no sudo check itself; the guarantee comes entirely from the `:require_sudo` router pipeline wrapping its route, so any future caller must gate access before invoking it directly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Full test suite's shared-IP login traffic tripped the per-IP throttle**
- **Found during:** Task 1, running the full suite after wiring `PlaysteadWeb.Plugs.Throttle` into the `POST /log-in` pipeline
- **Issue:** Every test hitting `POST /log-in` through `ConnTest` shares the default `127.0.0.1` remote IP; with ~100+ such requests landing inside the same fixed 1-minute window, the production-realistic per-IP limit throttled the test suite itself, not the feature under test
- **Fix:** Made both limits overridable via `config :playstead, PlaysteadWeb.Plugs.Throttle` (and per-call opts), raised to 100,000 in `config/test.exs`; `Throttle`'s own test file exercises the real fixed-limit behavior directly with small explicit per-call limits, independent of the test-suite-wide config
- **Files modified:** playstead-server/lib/playstead_web/plugs/throttle.ex, playstead-server/config/test.exs, playstead-server/test/playstead_web/plugs/throttle_test.exs
- **Verification:** Full suite green (137 tests); `Throttle`'s own test still proves per-IP and per-account limits deny at the configured threshold
- **Committed in:** eb093ec (Task 1 commit)

**2. [Rule 1 - Bug] `ConnTest` request dispatch discards a manually-set `conn.scheme`**
- **Found during:** Task 1, writing the https/http cookie-posture test through the real router
- **Issue:** `Phoenix.ConnTest`'s `post/3` (and `get/3`, etc.) rebuild the connection struct from scratch via `Plug.Adapters.Test.Conn.conn/4`, deriving `scheme` from the URL string passed to the dispatch call — a `Map.put(:scheme, :https)` applied to the conn beforehand is silently discarded
- **Fix:** Passed a full `https://localhost/...` / `http://localhost/...` URL to `post/3` instead of mutating `:scheme` directly, which is the correct way to control scheme in `ConnTest`
- **Files modified:** playstead-server/test/playstead_web/session_cookie_test.exs
- **Verification:** Both scheme variants correctly assert presence/absence of the `secure` cookie attribute
- **Committed in:** eb093ec (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking test-infrastructure issue, 1 bug in test construction)
**Impact on plan:** Both fixes were necessary for the test suite to correctly and reliably prove the D-06 behaviors; no scope creep — both are corrections to how the new features are tested, not to the features themselves.

## Issues Encountered

None beyond the two deviations above.

## User Setup Required

None — no external service configuration required. The recovery command (`docker compose exec app bin/playstead eval 'Playstead.Release.reset_owner_password()'`) is documented in `docs/RECOVERY.md` for when a self-hoster is actually locked out.

## Next Phase Readiness

- `PlaysteadWeb.Plugs.SudoMode` is ready for plan 01-05 to reuse for device revocation and credential rotation, exactly as D-06 anticipates
- Sessions and the audit log establish the "revocable credentials" mental model plan 01-05's paired-device list extends
- `Playstead.AuditLog`'s event-naming convention (lowercase snake_case, past tense) is established for plan 01-04's pairing events to follow
- Visual/UX fidelity of the Sessions list, sudo modal, and error banners against the UI-SPEC (dark surface, spacing, truncation/tooltip, and the two backstop items) is deferred to the phase's end-of-phase human UAT pass — no blocker for continuing execution
- No blockers for the next plan in this phase

## Self-Check: PASSED

- All 21 created files confirmed present on disk
- Both task commit hashes (`eb093ec`, `100d16c`) confirmed in `git log`
- `mix compile --warnings-as-errors` exits 0; `mix test` — 137 tests, 0 failures
- Plan-level `<verification>` re-run: full suite green; revoking one session leaves others working (`sessions_live_test.exs`); a session cookie carries `Secure` only over HTTPS (`session_cookie_test.exs`, real router pipeline); a dangerous action without a fresh sudo confirmation does not execute (`sudo_mode_test.exs`, `sessions_live_test.exs`); the release reset command prints a single-use URL, ends all sessions, and writes an audit entry (`accounts_recovery_test.exs`); a consumed recovery code cannot be reused (`accounts_recovery_test.exs`)

---
*Phase: 01-private-custody-and-durable-protocol*
*Completed: 2026-08-27*
