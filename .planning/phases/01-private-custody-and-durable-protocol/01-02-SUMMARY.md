---
phase: 01-private-custody-and-durable-protocol
plan: 02
subsystem: auth
tags: [phoenix, phx.gen.auth, ecto, bcrypt, phoenix-scopes, liveview, setup-wizard]

requires:
  - phase: 01-01
    provides: "Phoenix app scaffold, /setup LiveView console shell, Docker Compose volumes/deployment"
provides:
  - "Playstead.Accounts: household-ready owner model (role, Scope struct), password-only auth, no email flows anywhere"
  - "Playstead.Setup: setup-token bootstrap (D-03) and the once-only, concurrency-safe owner-claim transition"
  - "Playstead.Readiness: database/volumes/HTTPS readiness summary for the wizard's final step"
  - "Four-step setup wizard (PlaysteadWeb.SetupLive) and password login (PlaysteadWeb.LoginLive) at /log-in"
  - "Playstead.Codes: Base-20 consonant alphabet code generator shared by recovery codes and (later) pairing display codes"
affects: [01-03, 01-04, 01-05]

actuals:
  tokens: 32300
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Accounts context functions accept a %Scope{} carrying role, threaded from Phoenix 1.8's generated Scope struct (D-01)"
    - "Once-only state transitions (setup-token consumption) implemented as an UPDATE ... WHERE <flag> IS NULL inside an Ecto.Multi — Postgres row-level locking serializes concurrent attempts to exactly one winner, no explicit SELECT FOR UPDATE needed"
    - "Single-use secrets (recovery codes) stored as individually bcrypt-hashed rows, never as one blob, so each can be consumed independently"
    - "Router-level plug (not LiveView mount logic) enforces the /setup 404-after-owner-exists property, since only a plug can produce a real HTTP 404 status for the ConnTest-observable case"

key-files:
  created:
    - playstead-server/lib/playstead/accounts.ex
    - playstead-server/lib/playstead/accounts/user.ex
    - playstead-server/lib/playstead/accounts/user_token.ex
    - playstead-server/lib/playstead/accounts/scope.ex
    - playstead-server/lib/playstead/accounts/setup_token.ex
    - playstead-server/lib/playstead/accounts/recovery_code.ex
    - playstead-server/lib/playstead/setup.ex
    - playstead-server/lib/playstead/readiness.ex
    - playstead-server/lib/playstead/codes.ex
    - playstead-server/lib/playstead_web/user_auth.ex
    - playstead-server/lib/playstead_web/live/login_live.ex
    - playstead-server/lib/playstead_web/controllers/user_session_controller.ex
    - playstead-server/lib/playstead_web/plugs/require_setup_open.ex
    - playstead-server/test/playstead/accounts_test.exs
    - playstead-server/test/playstead/setup_test.exs
    - playstead-server/test/playstead_web/live/login_live_test.exs
    - playstead-server/test/playstead_web/live/setup_live_test.exs
    - playstead-server/test/playstead_web/no_mailer_test.exs
    - playstead-server/test/support/fixtures/accounts_fixtures.ex
  modified:
    - playstead-server/lib/playstead_web/live/setup_live.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead/application.ex
    - playstead-server/lib/playstead_web/components/core_components.ex
    - playstead-server/mix.exs
    - playstead-server/config/config.exs
    - playstead-server/config/dev.exs
    - playstead-server/config/prod.exs
    - playstead-server/config/test.exs
    - playstead-server/config/runtime.exs

key-decisions:
  - "Login screen keeps the generated Email field alongside Password — D-02's 'no email flows' constraint is about mail delivery, not about the login identifier field, and phx.gen.auth's email-based lookup is the least-invasive path to a working password auth model"
  - "The 'Locked out?' link on /log-in points at a plain (non-verified-route) href of /docs/recovery, since plan 01-03 creates that route; using Phoenix's ~p sigil here would fail mix compile --warnings-as-errors until the route exists"
  - "Setup-token consumption uses a guarded UPDATE (WHERE consumed_at IS NULL) inside the claim/2 Ecto.Multi rather than an explicit row lock — Postgres serializes concurrent UPDATEs on the same row, so this alone gives OPER-02's 'exactly one owner from two concurrent claims' guarantee, verified with two Task.async processes racing the real Postgres Sandbox connection"
  - "Playstead.Readiness's HTTPS check derives its state entirely from env vars (PLAYSTEAD_PROXY, PLAYSTEAD_DOMAIN) and a compile-time Mix.env() check, since the app process never terminates TLS itself (Caddy does) and has no visibility into the actual negotiated certificate"
  - "The anonymous-Docker-volume check reads /proc/self/mountinfo as a best-effort heuristic (a named volume's host path contains a project-prefixed name; an anonymous volume's contains a bare 64-hex-char id) and falls back to a lenient 'ok, could not verify' when that file or pattern isn't available (e.g. non-Linux/dev), since readiness warnings must never produce a false block"

requirements-completed: [OPER-02]

coverage:
  - id: D1
    description: "A self-hoster completes initial setup entirely in the LiveView console — setup token, owner credentials, recovery codes shown once, honest readiness summary — without touching application data or the device API directly"
    requirement: OPER-02
    verification:
      - kind: integration
        ref: "test/playstead_web/live/setup_live_test.exs#the full wizard flow walks token -> credentials -> recovery codes -> readiness -> finish"
        status: pass
    human_judgment: false
  - id: D2
    description: "No code path anywhere sends or attempts to send email; every magic-link/confirmation/reset-via-email flow generated by phx.gen.auth was deleted, not left dormant"
    verification:
      - kind: unit
        ref: "test/playstead_web/no_mailer_test.exs#no reachable deliver_*/Swoosh/Mailer code path exists in lib/"
        status: pass
      - kind: unit
        ref: "test/playstead_web/no_mailer_test.exs#the router declares no confirm/magic route path"
        status: pass
    human_judgment: false
  - id: D3
    description: "The users table carries role defaulting to :owner, and Scope carries it too, ready for every future owned-resource context call"
    requirement: OPER-02
    verification:
      - kind: unit
        ref: "test/playstead/accounts_test.exs#register_owner/1 sets role to :owner and confirms the account at creation"
        status: pass
    human_judgment: false
  - id: D4
    description: "While no owner exists, the server prints a single-use setup token to stdout on boot; PLAYSTEAD_SETUP_TOKEN overrides it and is never reprinted"
    verification:
      - kind: unit
        ref: "test/playstead/setup_test.exs#mint_token/0 mints and stores a hashed token, printing it to stdout"
        status: pass
      - kind: unit
        ref: "test/playstead/setup_test.exs#mint_token/0 honors PLAYSTEAD_SETUP_TOKEN and does not print it"
        status: pass
    human_judgment: false
  - id: D5
    description: "/setup 404s permanently once an owner exists — there is never an unauthenticated first-visit claim window"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/setup_live_test.exs#GET /setup returns 404 once an owner exists"
        status: pass
    human_judgment: false
  - id: D6
    description: "Two concurrent setup submissions with the same valid token create exactly one owner account; the loser gets a token-already-used error"
    requirement: OPER-02
    verification:
      - kind: integration
        ref: "test/playstead/setup_test.exs#claim/2 two concurrent claims with the same token create exactly one owner"
        status: pass
    human_judgment: false
  - id: D7
    description: "Recovery codes are displayed exactly once at setup, stored as individually bcrypt-hashed rows, never re-displayable"
    verification:
      - kind: unit
        ref: "test/playstead/setup_test.exs#claim/2 creates exactly one owner with a valid token"
        status: pass
    human_judgment: false
  - id: D8
    description: "The readiness summary reports database, volumes, and HTTPS state honestly, and warnings never block wizard completion"
    requirement: OPER-02
    verification:
      - kind: integration
        ref: "test/playstead_web/live/setup_live_test.exs#readiness warnings never block completion a warning row does not disable the Finish setup control"
        status: pass
    human_judgment: false
  - id: D9
    description: "The login screen carries the no-email helper text and a Locked out? link; a bad password renders an inline generic error without blanking the page"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/login_live_test.exs#login page renders login page with the D-02 no-email helper text and a Locked out? link"
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/login_live_test.exs#user login - password redirects to login page with a flash error if credentials are invalid"
        status: pass
    human_judgment: false
  - id: D10
    description: "The wizard's visual design (dark console surface, JetBrains Mono code display, spacing/typography per UI-SPEC) reads as intended, and the empty/loading/error/populated states specified in the UI-SPEC hold up visually"
    verification:
      - kind: integration
        ref: "test/playstead_web/browser/setup_wizard_journey_test.exs#first run: token → credentials → recovery codes → readiness → login → recovery login"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/states_test.exs#E1 (error, backstop: recovery-code grid never clips, zero-one-many readiness rows)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/typography_test.exs#the setup token field is code-role: 20px / 0.04em JetBrains Mono"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/palette_test.exs#setup: accent, destructive, success and warning are used only where reserved"
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/loading_contract_test.exs (inline loading affordances, no full-page overlay)"
        status: pass
    human_judgment: false

duration: ~70min
completed: 2026-08-27
status: complete
---

# Phase 01 Plan 02: Owner Account, Phoenix Scopes, and the Setup Wizard Summary

**Password-only owner auth generated via `mix phx.gen.auth` with every magic-link/email flow surgically removed, plus a setup-token bootstrap and a four-step LiveView wizard (token → credentials → recovery codes → readiness) that gives a self-hoster a working owner account without touching the database or API by hand.**

## Performance

- **Duration:** ~70 min
- **Tasks:** 2 (both `tdd="true"`)
- **Files created:** 19
- **Files modified:** 10

## Accomplishments

- Ran `mix phx.gen.auth Accounts User users`, then deleted the generated `UserNotifier`, the Swoosh/`Mailer` dependency and config, the magic-link controller actions and LiveViews, and the email-confirmation/email-change flows outright — `test/playstead_web/no_mailer_test.exs` is a standing regression guard proving no `deliver_*`/`Swoosh`/`Mailer` reference or `confirm`/`magic` route survives
- Added a `role` field (`Ecto.Enum`, `:owner` default) to `User` in the same migration set that creates `users`, and threaded it onto the generated `Scope` struct — the household-ready foundation every later owned-resource context call builds on (D-01)
- `Playstead.Accounts.register_owner/1`, `owner_exists?/0`, and `get_user_by_password/2` are the API `Playstead.Setup` calls; `confirmed_at` is set at creation since there's no confirmation email to wait for
- `Playstead.Setup.mint_token/0` runs at boot (a documented no-op in `:test`, where the Ecto Sandbox pool has no owner process to check out queries against): mints a 256-bit token, hashes and stores it, and prints it once to stdout in an unmissable banner; `PLAYSTEAD_SETUP_TOKEN` overrides and is never reprinted
- `Setup.claim/2` is a single `Ecto.Multi`: verify the token, register the owner, consume the token via a guarded `UPDATE ... WHERE consumed_at IS NULL`, and generate 10 recovery codes — all-or-nothing, so a validation failure never burns the token. Verified with two real `Task.async` processes racing the same Postgres connection: exactly one owner is created, the loser gets `token_already_used`
- `Playstead.Readiness.summary/0` returns the three fixed rows (database, volumes, HTTPS) the wizard's final step needs — volumes detection includes a best-effort anonymous-Docker-volume heuristic via `/proc/self/mountinfo`, and the HTTPS row distinguishes Let's Encrypt / internal CA / external proxy / plain HTTP as four honestly-separate states, never a single boolean
- `PlaysteadWeb.SetupLive` now implements the full four-step wizard inside the existing console shell; `PlaysteadWeb.LoginLive` (renamed and reworked from the generated `UserLive.Login`) is the password-only login screen with the UI-SPEC's no-email helper text and "Locked out?" link
- `Playstead.Codes` generates Base-20 consonant-alphabet codes (the same visual convention plan 01-04's pairing display code will use) via crypto-strong rejection sampling — used now for recovery codes

## Task Commits

1. **Task 1: Generate phx.gen.auth, then strip every email-dependent flow and add the owner role and Scope** - `f083fc0` (feat)
2. **Task 2: Setup-token bootstrap and the four-step setup wizard** - `99447b7` (feat)

## Files Created/Modified

- `playstead-server/lib/playstead/accounts.ex` - Owner registration, password auth, recovery-code generation/consumption
- `playstead-server/lib/playstead/accounts/user.ex` - `role` field, `owner_registration_changeset/3`
- `playstead-server/lib/playstead/accounts/scope.ex` - `role` threaded onto the Scope struct
- `playstead-server/lib/playstead/accounts/user_token.ex` - Session tokens + generic hashed-token builder for `:password_reset` (plan 01-03)
- `playstead-server/lib/playstead/accounts/setup_token.ex` - Single-use setup-token row
- `playstead-server/lib/playstead/accounts/recovery_code.ex` - Individually-consumable bcrypt-hashed recovery code rows
- `playstead-server/lib/playstead/setup.ex` - `mint_token/0`, `verify_token/1`, `claim/2`
- `playstead-server/lib/playstead/readiness.ex` - `summary/0` (database/volumes/HTTPS)
- `playstead-server/lib/playstead/codes.ex` - Base-20 consonant code generator
- `playstead-server/lib/playstead_web/live/setup_live.ex` - Four-step setup wizard
- `playstead-server/lib/playstead_web/live/login_live.ex` - Password-only login screen
- `playstead-server/lib/playstead_web/controllers/user_session_controller.ex` - Password-only session create/delete
- `playstead-server/lib/playstead_web/plugs/require_setup_open.ex` - 404s `/setup` once an owner exists
- `playstead-server/lib/playstead_web/router.ex` - `/log-in`, `/log-out`, gated `/setup`
- `playstead-server/lib/playstead/application.ex` - Boots `Setup.mint_token/0` after the Repo starts (skipped in `:test`)
- `playstead-server/lib/playstead_web/components/core_components.ex` - `code_display/1` (JetBrains Mono code presentation)

## Decisions Made

- Login screen keeps the generated Email field alongside Password rather than dropping to a password-only form — D-02's constraint is about mail delivery, not the login identifier
- "Locked out?" links to a plain (non-`~p`-verified) `/docs/recovery` href since plan 01-03 creates that route; using the verified-route sigil now would fail `mix compile --warnings-as-errors`
- Setup-token consumption relies on Postgres's own row-level serialization of a guarded `UPDATE`, not an explicit `SELECT ... FOR UPDATE` — simpler and already proven correct under real concurrent load in the test
- Readiness's HTTPS state is derived from env vars and a compile-time `Mix.env()` check (the app never terminates TLS itself); the anonymous-volume detection is a best-effort `/proc/self/mountinfo` heuristic that degrades to "ok, unverifiable" rather than ever producing a false warning-turned-block

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `mix phx.gen.auth` generated a duplicate `bcrypt_elixir` dependency**
- **Found during:** Task 1, `mix deps.get` after running the generator
- **Issue:** `mix.exs` already declared `{:bcrypt_elixir, "~> 3.3"}` from plan 01-01; the generator added a second, older-constrained `{:bcrypt_elixir, "~> 3.0"}` entry, producing a "dependency is duplicated" warning
- **Fix:** Removed the generator's duplicate entry, keeping plan 01-01's `~> 3.3`
- **Files modified:** playstead-server/mix.exs
- **Verification:** `mix deps.get` runs clean with no duplicate-dependency warning
- **Committed in:** f083fc0 (Task 1 commit)

**2. [Rule 1 - Bug] `verify_token/1` crashed comparing `consumed_at` to `nil` in a query**
- **Found during:** Task 2, writing `setup_test.exs`
- **Issue:** `Repo.get_by(SetupToken, token_hash: hash, consumed_at: nil)` raises `ArgumentError` — Ecto forbids `nil` equality comparisons in queries, requiring `is_nil/1` instead
- **Fix:** Rewrote as an explicit `from` query using `is_nil(t.consumed_at)`
- **Files modified:** playstead-server/lib/playstead/setup.ex
- **Verification:** `mix test test/playstead/setup_test.exs` passes, including the `PLAYSTEAD_SETUP_TOKEN` and re-verification-after-failed-claim tests that exercise this path
- **Committed in:** 99447b7 (Task 2 commit)

**3. [Rule 3 - Blocking] Stale `swoosh`/`idna` entries left in `mix.lock` after removing the Swoosh dependency**
- **Found during:** Task 1, after deleting `{:swoosh, "~> 1.16"}` from `mix.exs`
- **Issue:** `mix.lock` still pinned `swoosh` and its transitive `idna` dependency, which `mix deps.get`/`mix compile` tolerate but leave as unused cruft
- **Fix:** Ran `mix deps.unlock --unused` followed by `mix deps.get`
- **Files modified:** playstead-server/mix.lock
- **Verification:** `grep swoosh mix.lock` returns no matches; full suite still green
- **Committed in:** f083fc0 (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (1 blocking dependency conflict, 1 bug, 1 blocking lockfile cruft)
**Impact on plan:** All three were necessary corrections surfaced by actually running the generator and the real test suite; no scope creep beyond what D-01/D-02/D-03/D-04/D-05b already required.

## Issues Encountered

None beyond the three deviations above.

## User Setup Required

None — no external service configuration required. The setup token itself is retrieved via `docker compose logs` at deployment time, which `docs/DEPLOY.md` (plan 01-01) already documents.

## Next Phase Readiness

- Owner accounts, Phoenix Scopes with `role`, and the setup wizard are complete and fully tested (100 tests passing, `mix compile --warnings-as-errors` clean)
- `Playstead.Accounts.UserToken`'s `:password_reset` context and `Accounts.update_user_password/2` are already in place for plan 01-03's release-command reset flow; the login screen's "Locked out?" link is wired to `/docs/recovery`, a path plan 01-03 must create
- `Playstead.Codes`'s Base-20 consonant alphabet is ready for plan 01-04's pairing display code to reuse
- No blockers for the next plan in this phase

## Self-Check: PASSED

- All 19 created files confirmed present on disk
- Both task commit hashes (`f083fc0`, `99447b7`) confirmed in `git log`
- `mix compile --warnings-as-errors` exits 0; `mix test` — 100 tests, 0 failures
- Plan-level `<verification>` re-run: full suite green, no mailer/magic-link/email-confirmation code path in `lib/` (regression-tested), `GET /setup` renders pre-owner and 404s post-owner, two concurrent `claim/2` calls with one token produce exactly one owner row, and the login screen renders the no-email helper text and "Locked out?" link

---
*Phase: 01-private-custody-and-durable-protocol*
*Completed: 2026-08-27*
