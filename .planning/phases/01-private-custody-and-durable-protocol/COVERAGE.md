# Phase 1 — API Coverage Declaration

**Detector result:** `api-coverage.cjs` returned `{"detected": false, "signals": []}` against the Phase 1 roadmap scope on 2026-08-27.

No external API integration: this phase *publishes* Playstead's own first-party HTTPS protocol (`/api/v1` capabilities, pairing, idempotency, and snapshot-and-cursor endpoints) and consumes no third-party API, SDK, hosted service, OAuth provider, or webhook source.

The only external components in scope are self-hosted infrastructure images the deployment runs (PostgreSQL and Caddy) and hex.pm library dependencies — neither is an external API surface whose capability set could be partially integrated. Dependency legitimacy is covered separately by the `## Package Legitimacy Audit` in `01-RESEARCH.md` and by threat `T-01-SC` in `01-01-PLAN.md`.

The capability surface this phase *creates* is enumerated and frozen by contract test rather than by a coverage matrix:

| Published surface | Where it is frozen |
|---|---|
| `GET /healthz` | `01-01-PLAN.md` task 1 — shape frozen, never changes (D-16) |
| `GET /api/v1/capabilities` | `01-01-PLAN.md` task 1 — envelope frozen by a full-key-set contract test (D-18) |
| `POST /api/v1/hello` | `01-06-PLAN.md` task 1 — verdict and remedy shape (D-19) |
| `POST /api/v1/device-pairing/requests`, `GET .../:id`, `POST .../:id/redeem` | `01-04-PLAN.md` tasks 1-2 (D-07, D-08, D-10) |
| `GET /api/v1/devices/me`, `PATCH /api/v1/devices/me`, `POST /api/v1/devices/me/rotate` | `01-04-PLAN.md` task 2, `01-06-PLAN.md` task 2 |
| `GET /api/v1/changes`, `GET /api/v1/snapshot` | `01-07-PLAN.md` tasks 2-3 (D-21) |
| RFC 9457 error envelope + machine-code registry | `01-01-PLAN.md` task 2 (D-22) |

**Sync entity-kind vocabulary** is registered in full (`device`, `pairing`, `catalogue`, `job`, `transfer`, `save`) in `01-07-PLAN.md` task 1 even though the last four have no producers until Phases 2-4 — the wire contract is frozen here so later phases attach producers without a protocol change. That obligation is recorded in `01-07-PLAN.md` under `<scope_note>`.
