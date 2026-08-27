# Phase 1: Private Custody and Durable Protocol - Context

**Gathered:** 2026-08-27
**Status:** Ready for planning

<domain>
## Phase Boundary

The self-hosted server foundation and the durable client contracts: an opinionated Docker Compose deployment of the Elixir/Phoenix + PostgreSQL server, a LiveView console for setup and administration, owner-approved Mac device pairing with revocation, capability negotiation with actionable incompatibility remedies, idempotent mutations with durable receipts, and HTTPS snapshot-and-cursor state reconstruction — so that disconnects, retries, and missed notifications can never define correctness. LiveView is console delivery only; the versioned HTTPS API is the client protocol. No import, library, cache, play, or save features belong to this phase.

</domain>

<decisions>
## Implementation Decisions

All decisions below were produced by four parallel research fan-outs (security, product/UX, SRE/self-hoster, Elixir/Phoenix idiom, and native-client lenses, with adversarial passes) and approved by the owner as a set. Prior art studied: Jellyfin, Plex, Immich, Home Assistant, Vaultwarden, Portainer, Grafana, Tailscale, Syncthing, Stripe, GitHub, Matrix, LSP, CalDAV (RFC 6578), OAuth Device Grant (RFC 8628), RFC 9457, IETF Idempotency-Key draft.

### Owner Account & First-Run Setup

- **D-01:** Account schema is household-ready from day 1: phx.gen.auth (Phoenix 1.8) users table + Phoenix scopes + a `role` field (`:owner`) + `user_id` FKs on every owned resource. UI stays single-user; no roles matrix, no invite flow. — **Reversibility:** one-way — retrofitting `user_id` onto every table later is a whole-schema migration; the scope struct must thread through all contexts from the first generated line.
- **D-02:** Console authentication is phx.gen.auth **password mode** with the owner auto-confirmed at creation. All email/SMTP-dependent flows (magic links, email confirmation, email reset) are stripped in Phase 1 — no flow anywhere may assume mail delivery. The login-identifier field carries explicit copy that no email is ever sent.
- **D-03:** Secure bootstrap: a single-use setup token printed to container stdout logs on boot while the server is unclaimed (Jupyter pattern). The setup wizard requires it before owner creation; `PLAYSTEAD_SETUP_TOKEN` env var is the documented automation override; the setup route 404s permanently once an owner exists. There is never an unauthenticated first-visit claim window. — **Reversibility:** reversible — but the no-open-claim-window property is a locked security posture, not a convenience choice.
- **D-04:** Setup wizard scope: setup token → owner credentials → recovery codes displayed once → readiness summary (DB migrated, database/blob volumes writable and persistent — catches the anonymous-volume mistake — and honest HTTPS status) → one-line backup nudge. Readiness warnings never block completion. All other configuration lives in settings. The wizard must never imply a backup exists (repository ≠ backup).
- **D-05:** Credential recovery without email, two paths: (a) a Mix-release command runnable via `docker compose exec` that prints a single-use short-lived reset URL, terminates all existing sessions, and writes an audit entry; (b) single-use recovery codes generated at setup, rate-limited like passwords. The login screen links "Locked out?" to the documented one-line command. Host access is the root of trust for both bootstrap and recovery — one principle, documented once.
- **D-06:** Console sessions: phx.gen.auth DB-backed session tokens with remember-me on by default (~60-day window), a Sessions list with per-session revocation placed beside paired devices (one "revocable credentials" mental model), and sudo-mode re-authentication for dangerous actions (device revocation, credential change, recovery-code regeneration). Cookies `HttpOnly` + `SameSite=Lax`, `Secure` set when the request scheme is HTTPS (never hard-forced — breaks LAN plain-HTTP silently). Basic per-IP/per-account login throttling is in scope; adaptive lockout is not.

### Device Pairing

- **D-07:** Pairing flow is RFC 8628-shaped with verification inverted onto the trusted surface: the Mac POSTs a pairing request and displays a short grouped display code (8 chars, Base-20 consonant alphabet, `XXXX-XXXX`); the owner approves it from a Devices approval queue in the LiveView console after visually confirming the code matches the Mac's screen. The Mac polls over plain HTTPS (5s, honoring server `slow_down`) — no WebSocket. Never auto-approve a sole pending request; the code comparison is the entire security property. — **Reversibility:** costly — the pairing ceremony shapes both the Mac client UX and the console's Devices page; changing direction later reworks both surfaces and the protocol.
- **D-08:** Redemption is two-code (RFC 8628 structure): the human-readable display code is only ever compared visually; the Mac redeems with a separate single-use 256-bit `device_code` it generated at request time. There is no unauthenticated endpoint that accepts code guesses.
- **D-09:** Approval evidence card: display code dominant; claimed device name, platform + app version rendered as *claims*; observed requesting IP with a plain-language network hint ("from your local network (192.168.1.24)" / "via Tailscale"); request age. One line of microcopy: "Only approve if this code matches the one on your Mac's screen." Never render spoofable claims with the same visual authority as observed facts. Requesting IP is taken only from the trusted proxy hop.
- **D-10:** Device credential: per-device long-lived opaque token (256-bit random), stored hashed, delivered exactly once at redemption into the Mac's Keychain, sent only via Authorization header (never URLs, never logged). Revocation deletes the credential row and takes effect on next request — honest semantics for weeks-offline clients; no refresh-rotation choreography that could strand them. Console shows only a SHA-256 fingerprint prefix. A use-activated rotation endpoint (`old token valid until new token first used`) ships, but rotation is not forced. Device identity and credential are separate rows so rotation/re-pairing preserve history. — **Reversibility:** costly — the credential model is part of the published client protocol; moving to keypair+JWT later is an additive v-next migration, not an edit.
- **D-11:** Device lifecycle UX: Devices page with owner-editable name (client self-report preserved separately), platform/app version, paired-at, neutral last-seen (weeks-offline is normal, never alarming), fingerprint. Revoke confirmation names the device and consequences (local games/saves stay playable; sync stops). Revoked Mac receives 401 + machine code `device_revoked` and shows humane copy with a one-tap Pair Again; re-pairing always creates a new device record and the old row is retained as a revoked tombstone (never resurrect old rows).
- **D-12:** Pairing protections: 10-minute request expiry with a visible countdown on the Mac; expired requests render inert (no live Approve button) and expiry is re-checked server-side at approval, bound to the specific request ID + code; small fixed pending-queue cap with oldest-evicted; per-IP rate limits on request creation; every pairing event (requested/approved/denied/expired/redeemed/revoked) is audit-logged.

### HTTPS & Deployment

- **D-13:** TLS: bundle Caddy in the Compose file — automatic Let's Encrypt when `PLAYSTEAD_DOMAIN` is set, Caddy internal CA (locally-trusted certs) otherwise — so "secure HTTPS" is true on day one with no domain. The Mac client handles trust via pairing-time root-CA fingerprint display in the console + programmatic pinning in the client (URLSession custom trust evaluation) — no Keychain Access surgery. Tailscale (`tailscale cert`) and bring-your-own-reverse-proxy (`PLAYSTEAD_PROXY=external`, honest plain-HTTP language, never called "secure") are documented supported adapters, never the default. — **Reversibility:** costly — the client's trust bootstrapping is part of the pairing ceremony and the compose file's public shape.
- **D-14:** Compose shape: one file with Postgres + app + Caddy, **all image tags pinned to exact versions** (a new compose per release; `latest` banned), explicitly named volumes `playstead_db` and `playstead_blobs` with "THIS IS YOUR LIBRARY" comments and never-use-`down -v` documentation, `pg_isready`/`/healthz` healthchecks with `depends_on: service_healthy` ordering, `restart: unless-stopped`, no container resource limits in Phase 1 (documented how to add). External-Postgres is a documented override recipe, not the happy path.
- **D-15:** Secure-by-default network/config surface: only Caddy publishes host ports (80/443, overridable via `PLAYSTEAD_HTTP_PORT`/`PLAYSTEAD_HTTPS_PORT`); the app binds only to the compose network on a fixed internal port; Postgres publishes no host port; no default credentials anywhere. `.env.example` documents every variable; the app **refuses to boot** with placeholder `SECRET_KEY_BASE`/`POSTGRES_PASSWORD`, with a documented one-line secret generator. Config layering: env vars (runtime.exs) for infrastructure identity; the lock-after-first-run wizard for one-time human decisions; DB-backed settings for operational state.
- **D-16:** Health: exactly one unauthenticated boolean `/healthz` (200/503; app up + DB `SELECT 1`; no detail leakage) wired into the Docker healthcheck. Richer per-component health (OPER-03) arrives in Phase 5 under a separate authenticated route; `/healthz` never changes shape.
- **D-17:** Upgrades: Ecto migrations auto-run on boot via the standard Release-module pattern, failing loudly with an actionable message (non-zero exit, no silent crash-loop masking), plus a minimum-upgradable-version gate at boot (Immich's lesson — no half-migrating ancient schemas). Migration discipline from Phase 1: backward-compatible, forward-only; never destructive DDL in the release that stops using a column. Phase-1 upgrade doc: backup first (`pg_dump` + blob volume copy, explicitly "a copy on the same disk is not a backup") → bump pinned tag → `pull && up -d` → check `/healthz`. Rollback at this phase = restore the pre-upgrade backup; preflight/rollback tooling is Phase 5 (OPER-04). — **Reversibility:** one-way — migration discipline is a ratchet; a single destructive migration breaks the future OPER-04 rollback story.

### Protocol Contract (PROT-03/04/05)

- **D-18:** Versioning: URL-path major (`/api/v1`), additive-only minor evolution advertised through `GET /api/v1/capabilities` (carrying `protocol {major, minor}`, server build, supported-client ranges). Compatibility is a **range check, never version equality** (Immich lockstep pain is the named anti-pattern — Mac auto-updates while servers stay pinned for months). Breaking changes only at a new path major with a published dual-serve overlap window. The capabilities envelope itself is frozen in Phase 1 contract tests — it is the meta-contract. — **Reversibility:** one-way — `/api/v1` and the capabilities envelope are the published protocol every future client builds on.
- **D-19:** Capability negotiation (PROT-03): per-session handshake — client fetches the capability doc, POSTs a client hello with namespaced capability sets (`protocol`, `app`, `cache`, `transfer`, `adapter`, `save` — only vocabulary REQUIREMENTS names; no unbuilt-feature keys), receives a verdict: `compatible`, `compatible_with_limits` (listing ignored optional capabilities), or `incompatible` with a structured remedy `{who_must_act, side_too_old, minimum_required, detail_url}`. Unknown keys are ignored on both sides. Pairing stores the initial declaration; every session refreshes it. Both sides derive the same verdict from exchanged ranges, so the "each side says upgrade the other" deadlock cannot occur; remedy copy states which side is older, who acts (user vs server admin), and that the library is safe. An incompatible client is never locked out of the capabilities endpoint or revocation surface. Capabilities are contract declarations, never runtime feature toggles or kill switches.
- **D-20:** Idempotency (PROT-04), two layers: (a) required `Idempotency-Key` header per IETF-draft semantics, scoped per device, receipt (request fingerprint + response) written **in the same Ecto transaction as the effect**, ~90-day retention, `409 + Retry-After` when a retry races an in-flight original, 422 with a stable code on payload mismatch under a reused key; (b) client-generated UUIDv7 command/resource IDs as unique-constrained natural keys (`on_conflict` upserts; Oban `unique` for enqueued work) so an outbox replay after receipt expiry converges to the existing effect instead of duplicating. Retries are invisible to users — never surface "duplicate request". — **Reversibility:** one-way — receipt semantics and the required header are published client contract.
- **D-21:** Snapshot-and-cursor recovery (PROT-05): opaque HMAC-signed cursor encoding a monotonic sequence over a compacted per-tenant change journal with tombstone entries for deletions (commit-order fenced — no cursor-gap lost updates; offset pagination banned from the sync path). Stale cursor → `410 Gone` + code `cursor_expired` → client performs full resync from a snapshot endpoint that returns snapshot pages + the as-of cursor inside one consistent transaction; client swaps local read models atomically then resumes the feed. Compaction horizon ≥ receipt retention (90 days) so outbox replay and cursor resync stay mutually consistent. Contract guarantee (assertable in tests): a client that misses every notification converges to identical state via `/changes` or 410→snapshot. UX: reconvergence is silent; the local cache stays browsable read-only; passive "Updating library…" progress only past a duration threshold. — **Reversibility:** one-way — the cursor/410/snapshot contract is the recovery spine every client's sync engine implements.
- **D-22:** Errors: RFC 9457 `application/problem+json` on **every** `/api` error including fallback/exception paths (contract-test a forced 500 — no Phoenix HTML leaking), with extension members: stable machine `code` registry (e.g. `capability_incompatible`, `idempotency_key_conflict`, `cursor_expired`, `device_revoked`), privacy-safe random `correlation_id` (echoed in a header; never derived from ROM names/paths/hashes/credentials), and the structured `remedy` object where applicable. Clients key microcopy off `code` only; contract tests assert codes, never English strings.

### Claude's Discretion

- Exact table/column naming, Caddyfile details, Phoenix project layout, LiveView component structure, and test organization — follow idiomatic Phoenix 1.8 and the decisions above.
- Password minimum-strength policy specifics (zxcvbn-style vs length floor).
- Rate-limiting library choice (Hammer/PlugAttack-style) and exact limits.
- Whether snapshot is one endpoint or per-domain endpoints, provided the transactional snapshot+as-of-cursor property holds.
- Wizard visual design within the experience ethos (UI hint: this phase has LiveView surfaces — a UI-SPEC pass may refine them).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project foundation
- `.planning/PROJECT.md` — Constraints (security, operations, delivery boundary), Key Decisions, priority order (data safety > reliability > clarity > performance > delight > breadth).
- `.planning/REQUIREMENTS.md` — OPER-01, OPER-02, PROT-01–05 verbatim requirement text for this phase.
- `.planning/ROADMAP.md` — Phase 1 goal, success criteria, and the contract gate: HTTP contract tests must prove idempotency receipts, authorization, and cursor reset/convergence.

### Discovery corpus (design authority)
- `.planning/discovery/EXPERIENCE-ETHOS.md` — interaction contracts, error-message questions, quiet-by-default; governs wizard, pairing, revocation, and remedy microcopy.
- `.planning/discovery/WEB-AND-CLIENT-ARCHITECTURE.md` — API-first boundary, LiveView-as-console, capabilities endpoint sketch, pairing-approval-as-authenticated-command.
- `.planning/discovery/TECHNICAL-RISKS.md` — threat model for pairing, remote exposure, audit logging, TLS/storage risks.

### External standards adopted by decision
- RFC 8628 (OAuth Device Authorization Grant) — pairing flow shape, two-code structure, `slow_down` polling.
- RFC 9457 (Problem Details) — API error envelope.
- RFC 6578 (Collection Synchronization) — sync-token/410-Gone resync pattern.
- IETF `draft-ietf-httpapi-idempotency-key-header` — idempotency header semantics.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield. `playstead-server/` and `playstead-mac/` contain only READMEs. This phase creates the Phoenix application in `playstead-server/`.

### Established Patterns
- Phoenix 1.8 idioms are the baseline: phx.gen.auth with scopes, `runtime.exs` release config, Release-module migrations, Oban for durable work.
- Project DNA (PROJECT.md): idiomatic Elixir/Phoenix over generic framework-shaped code; one-way dependency flow; LiveView calls the same application services as the API but is never the protocol.

### Integration Points
- The Mac client (Phase 3) consumes everything this phase publishes: pairing ceremony, capabilities handshake, idempotency headers, cursor/snapshot recovery, problem+json codes, and the pairing-time CA-fingerprint pinning flow. These contracts are the phase's real deliverable; the HTTP contract-test suite is their proof.

</code_context>

<specifics>
## Specific Ideas

- Pairing display-code aesthetic: grouped consonant code like `MKTV-QRZC` — large and dominant on both surfaces.
- Revoked-client microcopy pattern: "This Mac's access was removed from the server. Your downloaded games and saves are still here and playable offline. To reconnect, pair again from Settings."
- Setup token retrieval is the one documented `docker compose logs` moment; the compose docs show the exact command.
- Login screen "Locked out?" links to a doc showing the exact one-line reset command.
- Named-volume comments in the compose file literally warn "THIS IS YOUR LIBRARY".

</specifics>

<deferred>
## Deferred Ideas

- TOTP toggle and passkey/WebAuthn console auth — Phase 5 or v2, once a stable HTTPS-domain story exists.
- Multi-user/household UI, roles matrix, invite flow — v2 (schema is already ready).
- Optional SMTP as a notification channel — later; never a dependency.
- Device keypair + short-lived JWT credentials (Plex 2025 model) — revisit if untrusted-network exposure grows.
- Forced/scheduled token rotation and key expiry — wrong for weeks-offline personal devices.
- QR pairing for camera-bearing clients (phones/handhelds) — future clients.
- Per-device capability scopes beyond a single device scope — blocked on capability model maturing.
- Per-component health API, verified backup/restore, upgrade preflight/rollback tooling — Phase 5 (OPER-03/04, PORT-03/04).
- SSE/WebSocket event push — long-poll only in v1; events are hints, never correctness.
- OpenAPI-driven Swift codegen — publish schemas, hand-write the client transport.
- S3/direct-transfer capability keys, container resource limits, geo/ASN enrichment of pairing IPs, push notification of pairing requests, adaptive login lockout.

</deferred>

---

*Phase: 01-private-custody-and-durable-protocol*
*Context gathered: 2026-08-27*
