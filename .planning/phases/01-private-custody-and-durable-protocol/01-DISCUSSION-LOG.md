# Phase 1: Private Custody and Durable Protocol - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-27
**Phase:** 01-private-custody-and-durable-protocol
**Areas discussed:** Owner account & first-run setup, Device pairing experience, HTTPS & deployment posture, Incompatibility & recovery UX

---

## Session Mode

The owner selected all four presented gray areas and, instead of per-question interview turns, directed a **research fan-out**: for each decision point, spawn research subagents considering all stakeholder lenses (security, product, technical, design, SRE), pros/cons/tradeoffs, Elixir/Phoenix idioms, lessons from comparable products/ecosystems, patterns/anti-patterns/footguns, an adversarial pass, and then synthesize coherent one-shot recommendations requiring a single approval. Four `gsd-advisor-researcher` agents ran in parallel (one per area). The owner approved the full synthesized set via a single approve/revise/abort gate: **"Approve all"**.

---

## Owner Account & First-Run Setup

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcoded single owner | No users table; config-based | |
| Full multi-tenant | Accounts + memberships + roles now | |
| phx.gen.auth users + owner role + scopes | Household-ready schema, single-user UI | ✓ |
| Magic links (Phoenix 1.8 default) | Requires SMTP — rejected | |
| Password mode, email flows stripped | No mail dependency anywhere | ✓ |
| Open first-visit claim (Jellyfin/Immich) | LAN takeover window — rejected | |
| Portainer-style timed window | Race + restart confusion — rejected | |
| Setup token in container logs | Host access as root of trust | ✓ |
| Env-var credentials | Documented automation override only | ✓ (secondary) |
| CLI reset command + recovery codes | Dual no-email recovery | ✓ |

**User's choice:** Approved the researcher's full synthesis (see CONTEXT.md D-01…D-06).
**Notes:** Prior art driving choices: Jellyfin/Immich open-setup footgun, Portainer timed-window confusion, Grafana default-credential anti-pattern, Jupyter log-token pattern, Nextcloud `occ`/Grafana CLI reset idiom.

---

## Device Pairing Experience

| Option | Description | Selected |
|--------|-------------|----------|
| Mac shows code + console approval queue | RFC 8628 shape, verification on trusted surface | ✓ |
| Console shows code, typed into Mac | Code becomes claimable bearer secret — rejected | |
| QR code | Complexity without removing approval step — rejected | |
| Claim link | Secret sprawl through clipboards/chat — rejected | |
| Per-device long-lived hashed opaque token | Revoke = delete row, next-request effect | ✓ |
| Token + refresh rotation | Offline-client lockout risk — rejected (use-activated rotation endpoint only) | |
| Device keypair + short-lived JWT (Plex 2025) | Over-engineering Phase 1 — deferred | |

**User's choice:** Approved the researcher's full synthesis (see CONTEXT.md D-07…D-12).
**Notes:** Prior art: Jellyfin Quick Connect (and its removed PIN model), Tailscale device approval, HomeKit numeric comparison, Plex X-Plex-Token leak history. Two-code structure eliminates any unauthenticated brute-force surface.

---

## HTTPS & Deployment Posture

| Option | Description | Selected |
|--------|-------------|----------|
| Bundled Caddy (LE with domain, internal CA otherwise) | HTTPS true out of the box; pairing-time CA pinning | ✓ |
| Plain HTTP + BYO reverse proxy | Documented advanced adapter only | ✓ (secondary) |
| Phoenix serves TLS directly | Documented escape hatch only | ✓ (secondary) |
| Tailscale-first | First-class documented recipe, not default | ✓ (secondary) |
| Bundled Postgres + app + Caddy, pinned tags, named volumes | Opinionated single compose | ✓ |
| Minimal compose, everything external | Documented override example only | |
| Auto-migrate on boot (Release module) | With loud failure + min-version gate | ✓ |
| Explicit migrate step | Deferred to Phase-5 preflight (OPER-04) | |

**User's choice:** Approved the researcher's full synthesis (see CONTEXT.md D-13…D-17).
**Notes:** Prior art: Vaultwarden HTTPS requirement, Plex plex.direct (unreplicable), Syncthing click-through warning (anti-goal), Immich pinning/upgrade churn and minimum-version gating. Conflict resolved during synthesis: the deployment researcher's "first visitor claims server" assumption was overridden by the account researcher's stronger log-token bootstrap.

---

## Incompatibility & Recovery UX (Protocol Contract)

| Option | Description | Selected |
|--------|-------------|----------|
| URL-path major `/api/v1` + capabilities doc | Range-based compatibility | ✓ |
| Header/media-type versioning | Invisible in curl/logs — rejected | |
| Stripe date-pinned versions | Wrong cost model for OSS self-hosting — rejected | |
| Per-session capability handshake | Matrix/LSP pattern, verdict + structured remedy | ✓ |
| One-shot declaration at pairing | Kept only as initial record | ✓ (secondary) |
| Per-request capability headers | Chatty, smeared enforcement — rejected | |
| Idempotency-Key header + UUIDv7 natural keys (both) | Defense in depth for month-offline outbox | ✓ |
| Header-only (Stripe) | Receipt expiry breaks long-offline replay — rejected | |
| Opaque signed cursor + compacted journal + 410→snapshot | RFC 6578 pattern | ✓ |
| Full event log, no compaction | Unbounded growth — rejected | |
| Timestamp polling | Clock skew/missed-change footguns — rejected | |
| RFC 9457 problem+json + code registry | Stable codes as contract-test currency | ✓ |
| Custom error envelope | Reinvents solved problem — rejected | |

**User's choice:** Approved the researcher's full synthesis (see CONTEXT.md D-18…D-22).
**Notes:** Prior art: Immich version-lockstep pain (anti-pattern), Matrix /versions and /sync, GitHub additive-change discipline, CalDAV sync-token, IETF idempotency draft. Adversarial cases resolved: version-skew deadlock (shared remedy verdict), receipt expiry during month-offline (UUIDv7 layer), cursor-gap lost updates (commit-order fencing), racing retry (409 + Retry-After).

## Claude's Discretion

- Naming, Caddyfile details, Phoenix project layout, LiveView component structure, test organization.
- Password strength policy specifics; rate-limiting library and exact limits.
- Snapshot endpoint granularity (single vs per-domain) provided transactional snapshot+cursor holds.
- Wizard visual design within the experience ethos.

## Deferred Ideas

TOTP/passkeys; multi-user UI; optional SMTP; keypair+JWT credentials; forced rotation; QR pairing; per-device capability scopes; per-component health API; backup/restore + upgrade preflight/rollback (Phase 5); SSE/WebSocket push; OpenAPI Swift codegen; S3/direct-transfer keys; resource limits; geo/ASN pairing enrichment; pairing push notifications; adaptive login lockout.
