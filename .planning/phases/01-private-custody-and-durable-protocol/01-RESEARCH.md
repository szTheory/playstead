# Phase 1: Private Custody and Durable Protocol - Research

**Researched:** 2026-08-27
**Domain:** Elixir/Phoenix self-hosted server bootstrap, RFC 8628-shaped device pairing, versioned HTTP protocol contracts (capability negotiation, idempotency, cursor/snapshot sync, RFC 9457 errors)
**Confidence:** MEDIUM-HIGH — standard stack and RFC shapes are well documented; two load-bearing gaps were found in Step 3 that change how the planner must sequence tasks (see Common Pitfalls #1 and #2).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Owner Account & First-Run Setup**
- D-01: Account schema is household-ready from day 1: phx.gen.auth (Phoenix 1.8) users table + Phoenix scopes + a `role` field (`:owner`) + `user_id` FKs on every owned resource. UI stays single-user; no roles matrix, no invite flow. Reversibility: one-way.
- D-02: Console authentication is phx.gen.auth **password mode** with the owner auto-confirmed at creation. All email/SMTP-dependent flows (magic links, email confirmation, email reset) are stripped in Phase 1 — no flow anywhere may assume mail delivery. The login-identifier field carries explicit copy that no email is ever sent.
- D-03: Secure bootstrap: a single-use setup token printed to container stdout logs on boot while the server is unclaimed (Jupyter pattern). The setup wizard requires it before owner creation; `PLAYSTEAD_SETUP_TOKEN` env var is the documented automation override; the setup route 404s permanently once an owner exists. There is never an unauthenticated first-visit claim window. Reversibility: reversible, but the no-open-claim-window property is a locked security posture.
- D-04: Setup wizard scope: setup token → owner credentials → recovery codes displayed once → readiness summary (DB migrated, database/blob volumes writable and persistent, honest HTTPS status) → one-line backup nudge. Readiness warnings never block completion. All other configuration lives in settings. The wizard must never imply a backup exists.
- D-05: Credential recovery without email, two paths: (a) a Mix-release command runnable via `docker compose exec` that prints a single-use short-lived reset URL, terminates all existing sessions, and writes an audit entry; (b) single-use recovery codes generated at setup, rate-limited like passwords. The login screen links "Locked out?" to the documented one-line command. Host access is the root of trust for both bootstrap and recovery.
- D-06: Console sessions: phx.gen.auth DB-backed session tokens with remember-me on by default (~60-day window), a Sessions list with per-session revocation placed beside paired devices, and sudo-mode re-authentication for dangerous actions (device revocation, credential change, recovery-code regeneration). Cookies `HttpOnly` + `SameSite=Lax`, `Secure` set when the request scheme is HTTPS (never hard-forced). Basic per-IP/per-account login throttling is in scope; adaptive lockout is not.

**Device Pairing**
- D-07: Pairing flow is RFC 8628-shaped with verification inverted onto the trusted surface: the Mac POSTs a pairing request and displays a short grouped display code (8 chars, Base-20 consonant alphabet, `XXXX-XXXX`); the owner approves it from a Devices approval queue in the LiveView console after visually confirming the code matches the Mac's screen. The Mac polls over plain HTTPS (5s, honoring server `slow_down`) — no WebSocket. Never auto-approve a sole pending request. Reversibility: costly.
- D-08: Redemption is two-code (RFC 8628 structure): the human-readable display code is only ever compared visually; the Mac redeems with a separate single-use 256-bit `device_code` it generated at request time. There is no unauthenticated endpoint that accepts code guesses.
- D-09: Approval evidence card: display code dominant; claimed device name, platform + app version rendered as *claims*; observed requesting IP with a plain-language network hint; request age. Microcopy: "Only approve if this code matches the one on your Mac's screen." Requesting IP is taken only from the trusted proxy hop.
- D-10: Device credential: per-device long-lived opaque token (256-bit random), stored hashed, delivered exactly once at redemption into the Mac's Keychain, sent only via Authorization header (never URLs, never logged). Revocation deletes the credential row and takes effect on next request. Console shows only a SHA-256 fingerprint prefix. A use-activated rotation endpoint (`old token valid until new token first used`) ships, but rotation is not forced. Device identity and credential are separate rows. Reversibility: costly.
- D-11: Device lifecycle UX: Devices page with owner-editable name, platform/app version, paired-at, neutral last-seen, fingerprint. Revoke confirmation names the device and consequences. Revoked Mac receives 401 + machine code `device_revoked` with a one-tap Pair Again; re-pairing always creates a new device record and the old row is retained as a revoked tombstone.
- D-12: Pairing protections: 10-minute request expiry with a visible countdown on the Mac; expired requests render inert and expiry is re-checked server-side at approval, bound to the specific request ID + code; small fixed pending-queue cap with oldest-evicted; per-IP rate limits on request creation; every pairing event is audit-logged.

**HTTPS & Deployment**
- D-13: TLS: bundle Caddy in the Compose file — automatic Let's Encrypt when `PLAYSTEAD_DOMAIN` is set, Caddy internal CA otherwise. The Mac client handles trust via pairing-time root-CA fingerprint display in the console + programmatic pinning in the client (URLSession custom trust evaluation). Tailscale (`tailscale cert`) and bring-your-own-reverse-proxy (`PLAYSTEAD_PROXY=external`) are documented supported adapters, never the default. Reversibility: costly.
- D-14: Compose shape: one file with Postgres + app + Caddy, **all image tags pinned to exact versions** (`latest` banned), explicitly named volumes `playstead_db` and `playstead_blobs` with "THIS IS YOUR LIBRARY" comments and never-use-`down -v` documentation, `pg_isready`/`/healthz` healthchecks with `depends_on: service_healthy` ordering, `restart: unless-stopped`, no container resource limits in Phase 1. External-Postgres is a documented override recipe, not the happy path.
- D-15: Secure-by-default network/config surface: only Caddy publishes host ports (80/443, overridable via `PLAYSTEAD_HTTP_PORT`/`PLAYSTEAD_HTTPS_PORT`); the app binds only to the compose network on a fixed internal port; Postgres publishes no host port; no default credentials anywhere. `.env.example` documents every variable; the app **refuses to boot** with placeholder `SECRET_KEY_BASE`/`POSTGRES_PASSWORD`. Config layering: env vars (runtime.exs) for infrastructure identity; the lock-after-first-run wizard for one-time human decisions; DB-backed settings for operational state.
- D-16: Health: exactly one unauthenticated boolean `/healthz` (200/503; app up + DB `SELECT 1`; no detail leakage) wired into the Docker healthcheck. Richer per-component health (OPER-03) arrives in Phase 5 under a separate authenticated route; `/healthz` never changes shape.
- D-17: Upgrades: Ecto migrations auto-run on boot via the standard Release-module pattern, failing loudly with an actionable message, plus a minimum-upgradable-version gate at boot. Migration discipline from Phase 1: backward-compatible, forward-only; never destructive DDL in the release that stops using a column. Phase-1 upgrade doc: backup first → bump pinned tag → `pull && up -d` → check `/healthz`. Rollback at this phase = restore the pre-upgrade backup; preflight/rollback tooling is Phase 5. Reversibility: one-way.

**Protocol Contract (PROT-03/04/05)**
- D-18: Versioning: URL-path major (`/api/v1`), additive-only minor evolution advertised through `GET /api/v1/capabilities` (carrying `protocol {major, minor}`, server build, supported-client ranges). Compatibility is a **range check, never version equality**. Breaking changes only at a new path major with a published dual-serve overlap window. The capabilities envelope itself is frozen in Phase 1 contract tests. Reversibility: one-way.
- D-19: Capability negotiation (PROT-03): per-session handshake — client fetches the capability doc, POSTs a client hello with namespaced capability sets (`protocol`, `app`, `cache`, `transfer`, `adapter`, `save` — only vocabulary REQUIREMENTS names; no unbuilt-feature keys), receives a verdict: `compatible`, `compatible_with_limits`, or `incompatible` with a structured remedy `{who_must_act, side_too_old, minimum_required, detail_url}`. Unknown keys are ignored on both sides. Pairing stores the initial declaration; every session refreshes it. An incompatible client is never locked out of the capabilities endpoint or revocation surface. Capabilities are contract declarations, never runtime feature toggles or kill switches.
- D-20: Idempotency (PROT-04), two layers: (a) required `Idempotency-Key` header per IETF-draft semantics, scoped per device, receipt (request fingerprint + response) written **in the same Ecto transaction as the effect**, ~90-day retention, `409 + Retry-After` when a retry races an in-flight original, 422 with a stable code on payload mismatch under a reused key; (b) client-generated UUIDv7 command/resource IDs as unique-constrained natural keys (`on_conflict` upserts; Oban `unique` for enqueued work) so an outbox replay after receipt expiry converges to the existing effect instead of duplicating. Retries are invisible to users. Reversibility: one-way.
- D-21: Snapshot-and-cursor recovery (PROT-05): opaque HMAC-signed cursor encoding a monotonic sequence over a compacted per-tenant change journal with tombstone entries for deletions (commit-order fenced — no cursor-gap lost updates; offset pagination banned from the sync path). Stale cursor → `410 Gone` + code `cursor_expired` → client performs full resync from a snapshot endpoint that returns snapshot pages + the as-of cursor inside one consistent transaction; client swaps local read models atomically then resumes the feed. Compaction horizon ≥ receipt retention (90 days). Contract guarantee: a client that misses every notification converges to identical state via `/changes` or 410→snapshot. UX: reconvergence is silent. Reversibility: one-way.
- D-22: Errors: RFC 9457 `application/problem+json` on **every** `/api` error including fallback/exception paths (contract-test a forced 500 — no Phoenix HTML leaking), with extension members: stable machine `code` registry, privacy-safe random `correlation_id` (echoed in a header; never derived from ROM names/paths/hashes/credentials), and the structured `remedy` object where applicable. Clients key microcopy off `code` only; contract tests assert codes, never English strings.

### Claude's Discretion
- Exact table/column naming, Caddyfile details, Phoenix project layout, LiveView component structure, and test organization — follow idiomatic Phoenix 1.8 and the decisions above.
- Password minimum-strength policy specifics (zxcvbn-style vs length floor).
- Rate-limiting library choice (Hammer/PlugAttack-style) and exact limits.
- Whether snapshot is one endpoint or per-domain endpoints, provided the transactional snapshot+as-of-cursor property holds.
- Wizard visual design within the experience ethos (a UI-SPEC pass — already produced — refines these surfaces).

### Deferred Ideas (OUT OF SCOPE)
- TOTP toggle and passkey/WebAuthn console auth — Phase 5 or v2.
- Multi-user/household UI, roles matrix, invite flow — v2 (schema is already ready).
- Optional SMTP as a notification channel — later; never a dependency.
- Device keypair + short-lived JWT credentials (Plex 2025 model) — revisit if untrusted-network exposure grows.
- Forced/scheduled token rotation and key expiry.
- QR pairing for camera-bearing clients — future clients.
- Per-device capability scopes beyond a single device scope.
- Per-component health API, verified backup/restore, upgrade preflight/rollback tooling — Phase 5.
- SSE/WebSocket event push — long-poll only in v1.
- OpenAPI-driven Swift codegen — publish schemas, hand-write the client transport.
- S3/direct-transfer capability keys, container resource limits, geo/ASN enrichment of pairing IPs, push notification of pairing requests, adaptive login lockout.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OPER-01 | Self-hoster deploys via one documented Docker Compose path with explicit persistent DB/blob volumes | D-13, D-14, D-15 — Compose shape, pinned tags, named volumes, healthchecks; see Standard Stack (Caddy) and Architecture Patterns (Compose skeleton) |
| OPER-02 | Self-hoster completes initial setup in LiveView console without editing app data or calling the device API by hand | D-03, D-04 — setup-token bootstrap + wizard; see Common Pitfalls #1 (phx.gen.auth default is magic-link, not password) |
| PROT-01 | Authenticated owner approves Mac pairing; Mac stores scoped credential in Keychain | D-07, D-08, D-10, D-12 — RFC 8628-shaped two-code flow; see Architecture Patterns (Pairing state machine) |
| PROT-02 | Authenticated owner reviews paired devices and revokes one without affecting others | D-10, D-11 — per-device credential row, tombstone-on-revoke |
| PROT-03 | Client declares protocol/app/cache/transfer/adapter/save capabilities; gets actionable incompatibility remedy | D-18, D-19 — capabilities envelope + range-check verdict; see Architecture Patterns (Capability negotiation) |
| PROT-04 | Disconnected client retries a mutation safely, gets original receipt not a duplicate | D-20 — Idempotency-Key + Ecto transaction receipt + UUIDv7 natural keys; see Common Pitfalls #3 (race window) |
| PROT-05 | Client that misses notifications reconstructs state via versioned HTTPS snapshot-and-cursor API, no WebSocket required | D-21 — HMAC cursor + compacted journal + 410/snapshot; see Common Pitfalls #4 (offset pagination trap) |
</phase_requirements>

## Summary

This phase is almost entirely specified by CONTEXT.md — 22 locked decisions already fix the shape of setup, pairing, TLS, deployment, and the four protocol contracts (capabilities, idempotency, cursor/snapshot, problem+json). The planner's real job is sequencing and catching two places where the locked decisions collide with what the underlying tools actually do out of the box.

The most important finding: **Phoenix 1.8's `mix phx.gen.auth` generator defaults to magic-link authentication with mandatory email confirmation, and has no flag to produce password-only auth** [VERIFIED: phoenix.hexdocs.pm/mix_phx_gen_auth.html]. D-02 requires "password mode" with every email/SMTP-dependent flow stripped. This is not a generator invocation choice — it requires running the generator, then deleting/rewriting the magic-link mailer calls, confirmation-token flow, and reset-via-email flow, replacing them with the password path the generator already scaffolds as a secondary option, and building D-03/D-05's non-email bootstrap and recovery in their place. The planner must budget this as an explicit "post-generation auth surgery" task, not assume `--hashing-lib` or similar flags exist for it.

Second: **there is no RFC 9457 (`problem+json`) library for Phoenix/Plug** [CITED: elixirforum.com/t/proposal-plug-problemdetail-rfc-9457-standard-error-format-for-http-apis/74784] — as of this research a proposal exists but nothing is shipped. D-22 requires this on every `/api` error path including the framework's own exception fallback. This must be hand-built as a small `Plug.Exception`-catching layer plus a Phoenix fallback controller, with an explicit contract test that forces a 500 and asserts JSON (never the default Phoenix HTML error page) — this is exactly the kind of gap the phase's "contract gate" spike flag exists to catch.

Everything else — Caddy automatic HTTPS/internal CA, Oban unique jobs, Ecto transactional receipts, HMAC-signed opaque cursors, Docker Compose healthcheck ordering — is standard, well-documented Elixir/Phoenix/Docker practice with no surprising gaps.

**Primary recommendation:** Generate `mix phx.gen.auth Accounts User users` first for its scope/session/session-token scaffolding, then treat everything email-shaped in the generated code as scaffolding to be replaced per D-02/D-03/D-05 — do not try to configure your way out of magic-link mode.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Owner auth / sessions | API/Backend (Phoenix contexts) | Frontend Server (LiveView console UI) | phx.gen.auth generates both; domain logic (Accounts context) must not depend on LiveView or the API controller layer — both call it. |
| Setup wizard | Frontend Server (LiveView) | API/Backend | LiveView is console-only per project constraint; wizard steps call the same Accounts/Settings contexts the API would use, never a private code path. |
| Device pairing (request/approve/redeem) | API/Backend | Frontend Server (approval queue UI) | The Mac only ever talks to `/api/v1`; the LiveView approval screen is a privileged consumer of the same pairing context, issuing the same "approve" command an admin API caller would. |
| Capability negotiation | API/Backend | — | Pure protocol contract; no UI surface owns this. |
| Idempotency / receipts | API/Backend + Database | — | Receipt write must be transactional with the effect — this is a Postgres/Ecto responsibility, not application-memory caching. |
| Cursor/snapshot sync | API/Backend + Database | — | Change journal is a Postgres table; HMAC signing/verification is a stateless API-layer concern. |
| TLS/reverse proxy | CDN/Edge (Caddy container) | — | Caddy terminates TLS and is the only container publishing host ports; the Phoenix app never sees raw TLS. |
| Deployment/health | Database + API/Backend | CDN/Edge (Caddy healthcheck proxying) | `/healthz` is served by the app but gates Compose orchestration and Caddy upstream routing. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| phoenix | 1.8.13 [VERIFIED: hex.pm/api/packages/phoenix, published 2026-08-25] | Web framework, contexts, generators | Project-mandated; ships `phx.gen.auth` with Scopes built in |
| phoenix_live_view | 1.2.11 [VERIFIED: hex.pm/api/packages/phoenix_live_view, published 2026-08-27] | Console UI (setup wizard, devices, library admin) | Bundled with Phoenix 1.8; only sanctioned client-protocol-adjacent UI per D-19/architecture boundary |
| ecto_sql / postgrex | ecto_sql 3.14.0 [VERIFIED: hex.pm/api/packages/ecto_sql] | Data layer, migrations, transactional receipts | Standard Phoenix data layer; transactions are the mechanism D-20 requires |
| oban | 2.24.0 [VERIFIED: hex.pm/api/packages/oban, published 2026-08-25] | Durable background work (setup-token cleanup, recovery-code issuance jobs, future import/transfer work) | Postgres-backed, no Redis dependency — matches PROJECT.md's "no Kafka/Redis in v1" constraint; `unique` option gives idempotent enqueue for D-20b |
| bcrypt_elixir | 3.3.2 [VERIFIED: hex.pm/api/packages/bcrypt_elixir] | Password hashing (phx.gen.auth default hashing lib on Unix) | Default `--hashing-lib` choice for phx.gen.auth; battle-tested, 53M+ all-time downloads |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| plug_attack or hammer | plug_attack 0.4.3 / hammer 7.4.0 [VERIFIED: hex.pm] | Per-IP/per-account rate limiting (D-06 login throttling, D-12 pairing-request rate limits) | Claude's Discretion per CONTEXT.md — either is standard; `hammer` has a pluggable backend (ETS is sufficient for single-node v1), `plug_attack` is Plug-native rule composition. Pick one, do not mix. |
| jason | latest (Phoenix default) | JSON encoding for API responses and the hand-built problem+json envelope | Ships as Phoenix's default JSON library; no reason to swap for this phase |
| :crypto (OTP) | bundled with Erlang/OTP 28 | HMAC-SHA256 cursor signing (D-21), 256-bit random token/device-code generation (D-08/D-10) | Standard library — do not add a third-party crypto dependency for HMAC or `:crypto.strong_rand_bytes/1` |
| Ecto.UUID / uuid7 | Ecto 3.14 ships UUIDv7 support via `Ecto.UUID` type + app-level generation, OTP 28's `:erlang` has no native v7 generator — use a small helper or `uniq` package | Client-generated UUIDv7 command/resource IDs (D-20b) | Verify UUIDv7 generation approach at planning time — Ecto's built-in `Ecto.UUID.generate/0` produces v4, not v7; confirm whether a v7 helper is needed in Elixir or only in the Swift client for Phase 1's contract-test fixtures. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| phx.gen.auth generated password+magic-link scaffold | Third-party `phx_gen_auth` hex package | That package targets Phoenix 1.5 and is unmaintained relative to Phoenix 1.8's built-in generator [VERIFIED: hex.pm/api/packages/phx_gen_auth description states "Phoenix 1.5"] — do not use it. |
| Hand-built RFC 9457 plug | Wait for `Plug.ProblemDetail` proposal to ship | Proposal is unmerged as of this research; hand-rolling ~100 lines of plug code is small and well-bounded, matches the "Don't Hand-Roll" exception for genuinely simple, spec-literal formatting |
| Caddy bundled reverse proxy | nginx / Traefik | D-13 already locks Caddy specifically for its zero-config automatic HTTPS + internal CA duality; do not reopen |
| `hammer`/`plug_attack` | Custom Ecto-backed rate limiter | Reinvents a solved, small problem; both libraries are lightweight enough not to justify hand-rolling |

**Installation:**
```bash
# from playstead-server/ after `mix phx.new playstead --umbrella=false --live`
mix deps.get
# add to mix.exs deps: {:oban, "~> 2.24"}, {:bcrypt_elixir, "~> 3.3"}, {:hammer, "~> 7.4"} (or :plug_attack)
```

**Version verification:** All versions above were confirmed via `curl https://hex.pm/api/packages/<name>` at research time (2026-08-27); re-check immediately before scaffolding since Phoenix/LiveView both shipped patch releases within the prior 48 hours.

## Package Legitimacy Audit

> The `package-legitimacy check` tool only supports `npm|pypi|crates` ecosystems; hex.pm was audited manually against the same signal set (age, downloads, source repo, maintainer).

| Package | Registry | Age | Downloads (all-time) | Source Repo | Verdict | Disposition |
|---------|----------|-----|----------------------|-------------|---------|-------------|
| phoenix | hex.pm | 12+ yrs | 154M | github.com/phoenixframework/phoenix | OK | Approved |
| phoenix_live_view | hex.pm | 7+ yrs | 44M | github.com/phoenixframework/phoenix_live_view | OK | Approved |
| ecto_sql | hex.pm | 8+ yrs | 127M | github.com/elixir-ecto/ecto_sql | OK | Approved |
| oban | hex.pm | 6+ yrs | 26.5M | github.com/oban-bg/oban | OK | Approved |
| bcrypt_elixir | hex.pm | 8+ yrs | 53.7M | github.com/riverrun/bcrypt_elixir | OK | Approved |
| hammer | hex.pm | 8+ yrs | 31.7M | github.com/ExHammer/hammer | OK | Approved |
| plug_attack | hex.pm | 9+ yrs | 1.68M | github.com/michalmuskala/plug_attack | OK | Approved (lower downloads but long-lived, single-purpose, maintained by a core Elixir community member) |
| phx_gen_auth (third-party) | hex.pm | targets Phoenix 1.5 | n/a | github.com/aaronrenner/phx_gen_auth | SUS — stale, superseded | REMOVED — do not use; Phoenix 1.8's built-in `mix phx.gen.auth` replaces it entirely |

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** `phx_gen_auth` (third-party hex package) — superseded by Phoenix's built-in generator; excluded from Standard Stack above, listed only to prevent accidental `mix deps` confusion.

## Architecture Patterns

### System Architecture Diagram

```
 Self-hoster (host machine)                    Mac client
 ─────────────────────────                     ──────────
 docker compose up -d                           pairing request (POST /api/v1/device-pairing/requests)
        │                                                │
        ▼                                                ▼
 ┌────────────────────────────────────────────────────────────────┐
 │ Caddy (only port publisher: 80/443)                             │
 │  - automatic Let's Encrypt (PLAYSTEAD_DOMAIN set)                │
 │  - internal CA cert (no domain — self-signed, fingerprint shown) │
 └───────────────────────────┬──────────────────────────────────┘
                              │ reverse-proxied, internal compose network only
                              ▼
 ┌────────────────────────────────────────────────────────────────┐
 │ Phoenix app (playstead) — internal port only, no host binding   │
 │                                                                  │
 │  /setup (LiveView, 404s after owner exists)                     │
 │     └─ setup token check → Accounts.create_owner → recovery     │
 │        codes → readiness summary (DB/volumes/HTTPS)             │
 │                                                                  │
 │  /                (LiveView console, phx.gen.auth session)      │
 │     ├─ Devices approval queue → Pairing.approve(request_id)     │
 │     └─ Sessions list → sudo-mode re-auth for revoke/rotate       │
 │                                                                  │
 │  /api/v1 (versioned HTTP boundary — the actual product contract)│
 │     ├─ GET  /capabilities                                       │
 │     ├─ POST /device-pairing/requests   (device_code minted)     │
 │     ├─ GET  /device-pairing/requests/:id  (poll, honors slow_down)│
 │     ├─ POST /device-pairing/requests/:id/redeem (device_code →  │
 │     │        device credential, once)                            │
 │     ├─ POST /hello   (capability negotiation verdict)           │
 │     ├─ POST /<mutating routes>  (Idempotency-Key required,      │
 │     │        receipt written same Ecto.Multi txn as the effect) │
 │     ├─ GET  /changes?cursor=...  (HMAC cursor, 410→snapshot)    │
 │     └─ GET  /snapshot            (transactional page + as-of    │
 │              cursor)                                             │
 │                                                                  │
 │  /healthz  (unauthenticated boolean; app up + DB SELECT 1)      │
 │                                                                  │
 │  Every /api error path → RFC 9457 problem+json (incl. 500s)     │
 └───────────────────────────┬──────────────────────────────────┘
                              ▼
                    ┌───────────────────┐
                    │ Postgres           │  named volume playstead_db
                    │  - users/sessions   │
                    │  - device_pairings  │
                    │  - devices/credentials (separate rows)
                    │  - idempotency_receipts (90d retention)
                    │  - change_journal (compacted, tombstoned)
                    │  - audit_log        │
                    └───────────────────┘
                              │
                    named volume playstead_blobs (created, unused until Phase 2)
```

### Recommended Project Structure
```
playstead-server/
├── lib/
│   ├── playstead/                  # domain — no Phoenix/LiveView/API types
│   │   ├── accounts/                # phx.gen.auth: User, UserToken, Scope
│   │   ├── pairing/                 # DevicePairingRequest, Device, DeviceCredential
│   │   ├── protocol/                # Capabilities doc, negotiation verdict logic
│   │   ├── idempotency/             # IdempotencyReceipt, fingerprint comparison
│   │   ├── sync/                    # ChangeJournal, Cursor (HMAC encode/decode)
│   │   └── release.ex                # boot-time migrate/0, min-version gate
│   └── playstead_web/
│       ├── controllers/api/v1/       # capabilities_controller, pairing_controller, ...
│       ├── plugs/                    # problem_json fallback, idempotency plug, auth plugs
│       ├── live/                     # setup_live, devices_live, sessions_live
│       └── router.ex                 # /api/v1 scope, LiveView console scope, /healthz
├── priv/repo/migrations/
├── docker-compose.yml
├── Dockerfile                        # from mix phx.gen.release --docker
├── Caddyfile
└── .env.example
```

### Pattern 1: Setup-token bootstrap (Jupyter pattern)
**What:** On boot, if no owner exists, generate a single-use token, print it to stdout, and store its hash. The `/setup` route requires the token (or `PLAYSTEAD_SETUP_TOKEN` env override) before rendering the owner-creation form. Once an owner row exists, `/setup` 404s unconditionally.
**When to use:** First-run only; this is D-03's entire security property — there is never an unauthenticated claim window.
**Example:**
```elixir
# lib/playstead/release.ex (Application boot, not a Mix task — releases have no Mix)
def ensure_setup_token do
  if Playstead.Accounts.owner_exists?() do
    :ok
  else
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    Playstead.Accounts.store_setup_token_hash(:crypto.hash(:sha256, token))
    IO.puts("""
    ============================================================
    Playstead setup token (use once, within the setup wizard):
    #{token}
    ============================================================
    """)
  end
end
```
Source pattern generalized from D-03; no external library needed — `:crypto` is OTP-bundled [VERIFIED: Erlang/OTP 28 present in this environment, `erl -version`/`elixir --version` output confirms OTP 28].

### Pattern 2: RFC 8628-shaped pairing with inverted verification
**What:** Mac POSTs a request and receives both a `device_code` (private, 256-bit, single-use) and a `user_code`/display code (public, 8-char grouped consonant alphabet). The Mac shows the display code; the owner compares it visually in the LiveView approval queue and approves by request ID. The Mac polls `GET /device-pairing/requests/:id` every 5s (or the server's `slow_down` interval) until it observes `approved`, then redeems with its `device_code` to receive the one-time device credential.
**When to use:** This is the entire PROT-01 flow; RFC 8628 defines the polling/`slow_down` semantics precisely enough to contract-test against.
**Example:**
```elixir
# state machine states — persisted, not process/LiveView state
:pending -> :approved | :denied | :expired
:approved -> :redeemed  # one-shot; redeeming twice must 409, never re-issue

# expiry re-checked at BOTH poll time and approval time, bound to request_id + code
def approve(request_id, owner_scope) do
  with {:ok, req} <- fetch_pending(request_id),
       true <- not expired?(req) do
    Repo.update(req, status: :approved, approved_by: owner_scope.user.id)
  else
    _ -> {:error, :expired_or_gone}
  end
end
```

### Pattern 3: Idempotency receipt in the same transaction as the effect
**What:** Every mutating `/api/v1` endpoint requires `Idempotency-Key`. Before executing, look up an existing receipt for `{device_id, idempotency_key}`. If found and the request fingerprint matches, return the stored response verbatim (no re-execution). If found with a different fingerprint, 422 with a stable code. If none found, run the effect and receipt-write inside one `Ecto.Multi`.
**When to use:** PROT-04, D-20a. This is the load-bearing contract-test surface named in the roadmap's "contract gate."
**Example:**
```elixir
# Source: IETF draft-ietf-httpapi-idempotency-key-header-07 semantics (2025-10-15)
Ecto.Multi.new()
|> Ecto.Multi.run(:check_receipt, fn repo, _ -> IdempotencyReceipts.fetch(repo, device_id, key) end)
|> Ecto.Multi.run(:effect, fn repo, %{check_receipt: nil} -> do_the_mutation(repo, params) end)
|> Ecto.Multi.insert(:receipt, fn %{effect: result} ->
  IdempotencyReceipt.changeset(%{device_id: device_id, key: key, fingerprint: fp, response: result})
end)
|> Repo.transaction()
```

### Pattern 4: HMAC-signed opaque cursor over a compacted change journal
**What:** The change journal is an append-only, periodically-compacted table with tombstone rows for deletions. A cursor is `Base.url_encode64(seq <> hmac(seq, secret))`. `GET /changes?cursor=X` verifies the HMAC, rejects tampering, and if `seq` is older than the compaction horizon returns `410 Gone` with `cursor_expired`. The client then calls the snapshot endpoint, which returns pages plus an as-of cursor computed inside the *same* transaction as the page read (`SELECT ... FOR SHARE`/consistent snapshot isolation), so the client can resume the feed from exactly that cursor with no gap.
**When to use:** PROT-05, D-21.
**Example:**
```elixir
# Source: general pattern from Ecto Cursor Pagination libraries (opaque + HMAC-signed cursor)
# adapted here for change-journal semantics, not row pagination
def encode_cursor(seq, secret), do: 
  sig = :crypto.mac(:hmac, :sha256, secret, Integer.to_string(seq))
  Base.url_encode64(<<seq::64, sig::binary>>, padding: false)
```
Offset pagination (`LIMIT/OFFSET`) is explicitly banned from this path — CONTEXT.md D-21 names this as an anti-pattern because offsets shift under concurrent writes and can silently skip or duplicate rows, which is exactly the "cursor-gap lost update" this contract must rule out.

### Pattern 5: RFC 9457 problem+json on every /api path, including exceptions
**What:** Because no Plug/Phoenix library ships this, build (a) a Phoenix fallback controller returning `application/problem+json` for expected error tuples, and (b) a top-level `Plug.ErrorHandler`/`render_errors` override in the API endpoint so that even an *unhandled exception* renders problem+json, not Phoenix's default HTML/JSON exception page.
**When to use:** D-22; contract-test with a deliberately-raising route to prove the fallback catches framework-level exceptions too, not just application-level error tuples.
**Example:**
```elixir
# config/config.exs (or per-endpoint) — force JSON, not HTML, for API scope
# lib/playstead_web/plugs/problem_json_error_handler.ex
def render_problem(conn, status, code, detail, extra \\ %{}) do
  correlation_id = generate_correlation_id()  # random, never derived from paths/hashes
  conn
  |> put_resp_content_type("application/problem+json")
  |> put_resp_header("x-correlation-id", correlation_id)
  |> send_resp(status, Jason.encode!(Map.merge(%{
       type: "about:blank", title: title_for(code), status: status,
       code: code, correlation_id: correlation_id, detail: detail
     }, extra)))
end
```

### Anti-Patterns to Avoid
- **Configuring phx.gen.auth to "skip email" instead of removing it in code:** there is no such flag; treat the generator output as a starting scaffold, not final code (see Common Pitfall #1).
- **LiveView process/assign state as the source of truth for pairing or device state:** LiveView remounts on reconnect; every pairing/device/idempotency/cursor fact must be durable in Postgres, read fresh on every mount [CITED: phoenix-live-view.hexdocs.pm — reconnect re-runs mount/3].
- **Offset pagination anywhere on the `/changes` or `/snapshot` path** — explicitly banned by D-21; use only the HMAC cursor.
- **Multipart/ETag-as-content-identity** — not relevant to Phase 1's blob volume (empty until Phase 2) but noted so the blob volume plumbing doesn't preemptively adopt this anti-pattern from the discovery corpus.
- **Hard-forcing `Secure` cookies regardless of scheme** — breaks LAN plain-HTTP self-hosters silently (D-06); gate on the actual request scheme.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Password hashing | Custom scrypt/PBKDF2 wrapper | `bcrypt_elixir` (phx.gen.auth default) | Constant-time comparison, salt handling, and cost-factor tuning are exactly the class of code that must not be reinvented |
| Session tokens | Custom signed-cookie session scheme | phx.gen.auth's DB-backed session token pattern | Already generated, already handles remember-me/expiry/hashing per Phoenix's own security review |
| Rate limiting | Ecto-backed sliding-window counter from scratch | `hammer` or `plug_attack` | Small, solved, well-tested; hand-rolling risks race conditions under concurrent requests |
| TLS/cert issuance & renewal | Custom ACME client or manual cert management | Caddy (bundled) | Caddy's automatic HTTPS + internal CA is the entire reason D-13 locked it in; reimplementing ACME is high-risk, zero-value |
| UUID v7 generation (if needed) | Hand-rolled timestamp+random UUID | An existing small `uniq`/`uuidv7`-style hex package, verified before adoption | Getting the monotonicity/sortability bits subtly wrong defeats the purpose of choosing v7 over v4 for natural-key ordering |

**Key insight:** Every "don't hand-roll" item above is a security-adjacent primitive (auth, crypto, TLS) where the phase's own risk framing (data safety > reliability) makes library reuse strictly higher priority than code ownership.

## Common Pitfalls

### Pitfall 1: Assuming phx.gen.auth has a "password-only" flag
**What goes wrong:** A task is written as "run `mix phx.gen.auth Accounts User users --hashing-lib bcrypt`" and assumed to satisfy D-02. It does not — Phoenix 1.8's generator defaults to magic-link login and mandatory email confirmation, and the CLI has no flag to suppress magic links [VERIFIED: phoenix.hexdocs.pm/mix_phx_gen_auth.html; corroborated by mikezornek.com/posts/2025/5/phoenix-magic-link-authentication/, which states explicitly "there is no option to prefer email/password as the primary user flow"].
**Why it happens:** Phoenix 1.7 and earlier defaulted to password auth; the 1.8 generator changed defaults and this is easy to miss when working from older tutorials/memory.
**How to avoid:** Plan an explicit task: generate normally, then delete/rewrite the magic-link controller actions, the mailer-dependent confirmation flow, and the email-based reset flow, retaining only the password-login path the generator scaffolds as secondary. Wire D-03's setup-token flow and D-05's Mix-release recovery command as the actual account-creation/recovery paths, replacing the generator's email-driven ones outright.
**Warning signs:** Any generated code path that calls `Accounts.deliver_login_instructions/2` or similar mailer functions still being reachable from a route — those all assume mail delivery and must be removed, not just left dormant, per D-02's "no flow anywhere may assume mail delivery."

### Pitfall 2: Assuming an RFC 9457 library exists for Phoenix
**What goes wrong:** A task assumes `{:problem_detail, "~> x.x"}` or similar exists and can be dropped in. As of this research, only a forum proposal exists, unmerged [CITED: elixirforum.com/t/proposal-plug-problemdetail-rfc-9457-standard-error-format-for-http-apis/74784].
**Why it happens:** RFC 9457/7807 is common enough elsewhere (Spring, ASP.NET, Rust) that its absence in the Elixir ecosystem is easy to assume away.
**How to avoid:** Budget a small hand-built plug/fallback-controller task (see Architecture Pattern 5). Contract-test it against a route that deliberately raises, to prove framework-level exceptions are also caught — this is explicitly named in the roadmap's contract-gate spike flag ("no Phoenix HTML leaking").
**Warning signs:** Any test that only exercises the "happy path" fallback controller and never forces an unhandled exception will pass while still leaking Phoenix's default HTML error page in production.

### Pitfall 3: Idempotency receipt write racing the effect
**What goes wrong:** If the receipt is written *after* an external commit (e.g., a separate transaction, or after an Oban job enqueue that isn't itself part of the transaction), a retry that arrives between the effect committing and the receipt committing will re-execute the effect.
**Why it happens:** It's tempting to write the receipt in an `after_commit` hook or a separate `Repo.insert` call for code cleanliness.
**How to avoid:** D-20 is explicit: receipt and effect must be in the *same* `Ecto.Multi`/transaction. For Oban-enqueued side effects, use Oban's `unique` option keyed on the same idempotency key/command ID so a duplicate enqueue attempt (from a replayed outbox) converges rather than double-enqueuing [CITED: hexdocs.pm/oban/Oban.Worker.html — unique job configuration].
**Warning signs:** A contract test that fires the same `Idempotency-Key` twice in rapid succession (simulating a client retry racing the original) and observes two effects instead of one 409+original-receipt pair.

### Pitfall 4: Cursor pagination reusing a generic Ecto pagination library's row-cursor semantics
**What goes wrong:** Off-the-shelf Ecto cursor-pagination libraries (`paginator`, `ecto_cursor`) solve *list pagination* (stable ordering over a queryable), not *change-feed convergence* (deletions, compaction, resumability across arbitrary gaps). Adopting one wholesale for `/changes` risks silently dropping tombstones or being unable to detect "cursor too old, must resync."
**Why it happens:** The generic libraries are the first search result and share vocabulary ("opaque cursor," "HMAC-signed") with D-21's requirement, inviting a drop-in that doesn't actually implement compaction-horizon/410 semantics.
**How to avoid:** Use the *pattern* (opaque, signed cursor) from these libraries but implement the change-journal/tombstone/compaction/410 logic directly against this phase's own schema — no existing hex package solves the full PROT-05 contract end to end.
**Warning signs:** A "missed every notification" contract test (named explicitly in D-21) that can't actually be written because the pagination library has no concept of a stale/expired cursor distinct from "no more rows."

## Code Examples

### Docker Compose skeleton (D-13, D-14, D-15, D-16)
```yaml
# Source: pattern verified against Caddy automatic-HTTPS docs (caddyserver.com/docs/automatic-https)
# and standard Docker Compose depends_on/service_healthy usage
services:
  db:
    image: postgres:17.2  # pinned exact tag — never `latest`
    volumes:
      - playstead_db:/var/lib/postgresql/data  # THIS IS YOUR LIBRARY — never `docker compose down -v`
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER"]
      interval: 5s
      timeout: 5s
      retries: 5
    # no ports: — Postgres publishes no host port
    restart: unless-stopped

  app:
    image: playstead/server:1.0.0  # pinned per-release; a new compose file ships per release
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:4000/healthz"]
    volumes:
      - playstead_blobs:/app/blobs  # THIS IS YOUR LIBRARY
    # no ports: — internal compose network only
    restart: unless-stopped

  caddy:
    image: caddy:2.10  # pinned
    ports:
      - "${PLAYSTEAD_HTTP_PORT:-80}:80"
      - "${PLAYSTEAD_HTTPS_PORT:-443}:443"
    depends_on:
      app:
        condition: service_healthy
    restart: unless-stopped

volumes:
  playstead_db:
  playstead_blobs:
```

### Caddyfile — automatic HTTPS with domain, internal CA without
```
# Source: caddyserver.com/docs/automatic-https
{$PLAYSTEAD_DOMAIN:localhost} {
	@has_domain expression {$PLAYSTEAD_DOMAIN} != ""
	tls internal   # active only when no PLAYSTEAD_DOMAIN — Caddy's own CA, fingerprint shown in setup wizard
	reverse_proxy app:4000
}
```
Caddy generates its own local CA when serving non-public hosts and uses it to sign certificates automatically [CITED: caddyserver.com/docs/automatic-https]; the CA root cert can be extracted from the container volume for D-13's pairing-time fingerprint display.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `mix phx.gen.auth` password-first (Phoenix ≤1.7) | Magic-link-first with password as secondary option (Phoenix 1.8) | Phoenix 1.8 release, 2026 [CITED: phoenixframework.org/blog/phoenix-1-8-released] | Any Phase 1 task copied from a pre-1.8 tutorial will scaffold the wrong default flow — see Pitfall 1 |
| `Plug.Conn` scope/assigns passed ad hoc | Phoenix Scopes as a first-class generated struct | Phoenix 1.8 | D-01's `role` field belongs on the Scope struct alongside `user_id`, not bolted on separately — check the generated `lib/playstead/accounts/scope.ex` before adding `role` |
| RFC 7807 `application/problem+json` | RFC 9457 (obsoletes 7807, same media type, adds registration guidance) | RFC 9457 published 2023 | No wire-format change for Phase 1's purposes; cite RFC 9457, not 7807, in code comments and docs per D-22 |

**Deprecated/outdated:**
- Third-party `phx_gen_auth` hex package: superseded entirely by Phoenix 1.8's built-in generator; do not add it as a dependency.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `hammer` or `plug_attack` are both suitable and roughly equivalent for D-06/D-12 rate limiting — chosen per Claude's Discretion | Standard Stack, Don't Hand-Roll | Low — CONTEXT.md explicitly delegates this choice; either library is well-established, so a wrong pick is a refactor, not a correctness risk |
| A2 | UUIDv7 generation on the Elixir side may require a small helper package (`Ecto.UUID.generate/0` produces v4) | Standard Stack (Supporting) | Medium — if the planner assumes v7 is available for free from Ecto and it isn't, the natural-key ordering property D-20b relies on for outbox replay convergence may silently degrade to v4's non-monotonic ordering; verify at plan time with a quick `Ecto.UUID` doc check or spike |
| A3 | Postgres 17.2 and Caddy 2.10 are reasonable exact pins for the Compose skeleton | Code Examples | Low — these are illustrative pins; the planner/executor should confirm current stable tags at scaffold time rather than treating 17.2/2.10 as load-bearing version requirements |

## Open Questions

1. **Exact UUIDv7 generation strategy for Elixir**
   - What we know: D-20b requires client-generated UUIDv7 IDs; the Mac client (Swift) can likely use a modern UUID v7 API or a small library. The Elixir side's own need for v7 (vs. accepting client-supplied v7 strings as opaque values) is less clear — the server may never need to *generate* v7 itself if IDs are always client-supplied.
   - What's unclear: whether any server-side code path (e.g., Oban job dedup keys) needs to mint its own UUIDv7 values, which would require adding a small hex dependency.
   - Recommendation: Treat server-side UUIDv7 as "accept and validate format from client," not "generate," unless a specific Phase 1 task proves otherwise; confirm during planning before adding a dependency.

2. **Exact recovery-code format and storage (D-05b)**
   - What we know: single-use recovery codes generated at setup, rate-limited like passwords, displayed once.
   - What's unclear: exact code alphabet/length and hashing scheme were left to Claude's Discretion implicitly (not explicitly called out, but not locked either).
   - Recommendation: Mirror the pairing display-code convention (Base-20 consonant alphabet) for visual consistency, hash with the same bcrypt mechanism as passwords, store as a set of single-use rows (not a single hashed blob) so individual codes can be marked consumed independently.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker | Compose deployment (OPER-01) | ✓ | 29.5.2 [VERIFIED: `docker --version` this session] | — |
| Docker Compose | Compose deployment (OPER-01) | ✓ | v5.1.3 [VERIFIED: `docker compose version` this session] | — |
| Elixir | Phoenix app development | ✓ | 1.19.5 on OTP 28 [VERIFIED: `elixir --version` this session] | — |
| Mix | Phoenix generators, release tooling | ✓ | 1.19.5 [VERIFIED: `mix --version` this session] | — |
| PostgreSQL (host) | Local dev only — production Postgres runs in Compose | ✓ (Homebrew 14.17) | 14.17 [VERIFIED: `psql --version` this session] | Not required for Compose deployment; only relevant if developing/testing outside containers |
| Caddy | TLS termination in Compose | ✗ (not installed on host) | — | Not needed on host — Caddy runs exclusively inside the Compose stack per D-13; no local fallback required |

**Missing dependencies with no fallback:** none — Caddy's absence on the host is expected and by design.
**Missing dependencies with fallback:** none blocking.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir/Phoenix default) |
| Config file | none yet — `test/test_helper.exs` created by `mix phx.new`; see Wave 0 |
| Quick run command | `mix test --only phase1` (tag new contract tests) or `mix test test/playstead_web/controllers/api/v1/` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OPER-01 | Compose stack boots healthy with pinned images and named volumes | integration (docker compose up + curl /healthz) | `docker compose up -d && curl -f https://localhost/healthz` (documented, likely CI job not `mix test`) | ❌ Wave 0 |
| OPER-02 | Setup wizard completes owner creation without direct DB/API access | LiveView integration test (`Phoenix.LiveViewTest`) | `mix test test/playstead_web/live/setup_live_test.exs` | ❌ Wave 0 |
| PROT-01 | Owner approves pairing; Mac receives credential once | contract test (ExUnit + `Phoenix.ConnTest`) | `mix test test/playstead_web/controllers/api/v1/pairing_controller_test.exs` | ❌ Wave 0 |
| PROT-02 | Revoking one device doesn't affect others | contract test | `mix test test/playstead_web/controllers/api/v1/devices_controller_test.exs` | ❌ Wave 0 |
| PROT-03 | Capability negotiation returns correct verdict for compatible/limited/incompatible ranges | contract test, property-style (multiple range combinations) | `mix test test/playstead_web/controllers/api/v1/capabilities_controller_test.exs` | ❌ Wave 0 |
| PROT-04 | Retry with same Idempotency-Key returns original receipt, not a duplicate effect; concurrent retry gets 409 | contract test (incl. a concurrency/race test) | `mix test test/playstead/idempotency_test.exs` | ❌ Wave 0 |
| PROT-05 | Client that misses every notification converges via `/changes` or `410`→snapshot | contract test simulating full outage | `mix test test/playstead_web/controllers/api/v1/changes_controller_test.exs` | ❌ Wave 0 |
| D-22 | Every `/api` error, including a forced 500, returns `application/problem+json` | contract test (deliberately raising route) | `mix test test/playstead_web/plugs/problem_json_test.exs` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/playstead_web/controllers/api/v1/` (fast contract subset)
- **Per wave merge:** `mix test` (full suite)
- **Phase gate:** Full suite green before `/gsd-verify-work`; additionally run the Compose smoke test (`docker compose up -d`, wait for healthy, `curl /healthz`) since that path is not exercised by ExUnit.

### Wave 0 Gaps
- [ ] `test/support/conn_case.ex` extension for API scope (JSON, no session cookies) — separate from LiveView `conn_case`
- [ ] `test/support/pairing_fixtures.ex` — shared fixtures for device-pairing contract tests
- [ ] `test/support/idempotency_fixtures.ex` — shared fixtures for receipt/race tests
- [ ] Framework install: ExUnit ships with Elixir — no install needed; `mix phx.new --live` scaffolds `test/` structure
- [ ] A documented (not necessarily `mix test`-automated) Compose smoke-test script for OPER-01, since container orchestration isn't unit-testable in ExUnit

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | phx.gen.auth password hashing (bcrypt), DB-backed session tokens, sudo-mode re-auth for dangerous actions (D-06), per-IP/per-account throttling (`hammer`/`plug_attack`) |
| V3 Session Management | yes | phx.gen.auth session token table, `HttpOnly`+`SameSite=Lax` cookies, `Secure` gated on request scheme (D-06), remember-me ~60-day window |
| V4 Access Control | yes | Phoenix Scopes enforce `user_id`/owner scoping on every context call; device credentials are per-device opaque tokens checked on every `/api/v1` request via Authorization header |
| V5 Input Validation | yes | Ecto changesets on every mutation; capability-hello and idempotency-key payloads validated before touching domain logic; RFC 9457 envelope on rejection |
| V6 Cryptography | yes | bcrypt for passwords (never hand-rolled hashing), `:crypto.strong_rand_bytes/1` for device codes/tokens/setup token (OTP-bundled, never a custom RNG), HMAC-SHA256 for cursor signing — all via OTP `:crypto`, no third-party crypto primitive reimplementation |
| V9 Communications (TLS) | yes | Caddy-terminated TLS (Let's Encrypt or internal CA), pairing-time CA-fingerprint pinning in the Mac client, cookies scheme-gated rather than hard-forced |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Pairing-code guessing / brute force | Tampering / Elevation of Privilege | 256-bit `device_code` (not the human display code) is the only credential-bearing secret; no unauthenticated endpoint accepts code guesses (D-08); per-IP rate limits on request creation (D-12) |
| Sole-pending-request auto-approval race | Elevation of Privilege | D-07 explicitly forbids ever auto-approving a lone pending request — approval requires an explicit owner action bound to request ID + code, re-validated server-side at approval time |
| Session fixation / stolen session cookie | Spoofing | `HttpOnly`+`SameSite=Lax` cookies, DB-backed (revocable) session tokens, sudo-mode re-auth gate on dangerous actions |
| Idempotency-key replay to force duplicate effects | Tampering | Receipt keyed on `{device_id, idempotency_key}` with fingerprint comparison; mismatched fingerprint under a reused key is a 422, not a re-execution |
| Cursor tampering to read another tenant's change feed | Tampering / Information Disclosure | HMAC-signed cursor rejects any modification; per-tenant scoping enforced independently of cursor contents (cursor encodes position, never identity/authorization) |
| Verbose error leakage (paths, hashes, stack traces) | Information Disclosure | RFC 9457 envelope with a stable `code` registry and a random (never derived) `correlation_id`; `/healthz` explicitly returns no detail beyond the boolean (D-16) |
| Plaintext HTTP on LAN silently downgrading security expectations | Spoofing / Tampering | `Secure` cookie flag gated on actual request scheme rather than hard-forced, so LAN plain-HTTP doesn't silently break logins — but the UI must make the non-HTTPS state honest, never implying "secure" when it isn't (ties to D-13's `PLAYSTEAD_PROXY=external` "never called secure" language) |

## Sources

### Primary (HIGH confidence)
- hex.pm package API (phoenix, phoenix_live_view, ecto_sql, oban, bcrypt_elixir, hammer, plug_attack, nimble_totp, phx_gen_auth) — version/age/downloads/repo verified live, 2026-08-27
- phoenix.hexdocs.pm/mix_phx_gen_auth.html — generator flags, hashing-lib options, scope generation
- caddyserver.com/docs/automatic-https — internal CA / automatic HTTPS behavior
- Local environment probes (`docker --version`, `docker compose version`, `elixir --version`, `mix --version`, `psql --version`) — this session

### Secondary (MEDIUM confidence)
- mikezornek.com/posts/2025/5/phoenix-magic-link-authentication/ — corroborates phoenix.hexdocs.pm finding that no password-only generator flag exists
- elixirforum.com/t/proposal-plug-problemdetail-rfc-9457-standard-error-format-for-http-apis/74784 — confirms absence of a shipped RFC 9457 Plug library
- hexdocs.pm/oban/Oban.Worker.html — unique job configuration for idempotent enqueue
- datatracker.ietf.org draft-ietf-httpapi-idempotency-key-header-07 — current idempotency header draft semantics

### Tertiary (LOW confidence)
- General WebSearch results on Ecto cursor-pagination libraries (paginator, ecto_cursor) — used only to confirm the "opaque + HMAC-signed cursor" pattern exists elsewhere; the change-journal/tombstone/compaction implementation itself is not covered by any of these libraries and must be hand-built per D-21 (see Pitfall 4)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all core library versions verified live against hex.pm at research time
- Architecture: HIGH — CONTEXT.md's 22 decisions already fully specify the protocol shapes; this research confirms the underlying tools support them
- Pitfalls: MEDIUM-HIGH — the two load-bearing gaps (phx.gen.auth defaults, missing RFC 9457 library) were confirmed via official docs and a corroborating independent source each

**Research date:** 2026-08-27
**Valid until:** ~30 days (2026-09-26) — Phoenix/LiveView ship frequent patch releases; re-verify exact pins immediately before scaffolding
