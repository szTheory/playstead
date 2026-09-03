---
id: SEED-023
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning
trigger_when: when planning Phase 5 OPER-03 component health, when publishing a Kubernetes/Nomad deployment adapter, or before anything wires /healthz as a restart trigger
scope: small — one additional endpoint plus documented probe semantics; larger only if orchestrator adapters ship
related: SEED-017 (progressive deployment modes)
---

# SEED-023: Separate liveness from readiness before an orchestrator restarts the fleet

## Why This Matters

`/healthz` today runs `SELECT 1` against `Playstead.Repo` and returns 200 or
503. By Kubernetes semantics that is a **readiness** probe, not a liveness
probe — it reports on a *dependency*, not on whether this process is wedged.

Its current consumers are correct for readiness. The compose healthcheck
(`wget --spider /healthz`) and Caddy's `depends_on: service_healthy` both use it
for ordering and traffic admission, which is exactly what a readiness signal is
for. So nothing is broken right now.

The hazard is what happens the first time someone wires the obvious-looking
endpoint into an orchestrator's `livenessProbe`, which is a near-certainty the
moment a Kubernetes/Nomad deployment adapter exists (SEED-017 anticipates
exactly that):

> Postgres has a transient blip. `SELECT 1` fails on every app instance
> simultaneously. Every liveness probe fails. The orchestrator restarts every
> app pod at once. The restarts do not fix anything, because the app was never
> the problem — and now a brief database hiccup has become a full outage with a
> cold cache and a thundering herd of reconnects on recovery.

That is the classic cascading-failure antipattern, and the shape of this
codebase makes it easy to walk into: the endpoint is named `/healthz` (the
conventional liveness name), it is documented as a "boolean health endpoint",
and its response shape is explicitly **frozen** — so the fix cannot be "make
`/healthz` smarter later," it has to be a separate route.

The distinction to encode:

| Probe | Question | Checks dependencies? | Failure action |
|---|---|---|---|
| **Liveness** | Is this process wedged beyond recovery? | **No** — never | Restart me |
| **Readiness** | Should traffic come to me right now? | **Yes** | Remove me from the pool |
| **Startup** | Has slow initialization finished? | Sometimes | Hold off the other two |

The owner's read was right on both counts: `/healthz` is doing readiness duty,
and `/api/v1/capabilities` returning 200 is closer to a real readiness signal
for *clients* specifically (it proves the negotiated contract is being served,
not merely that the process answers).

## Questions to Explore

- Add a dependency-free liveness route (the BEAM is scheduling, the endpoint
  supervisor is up, no Repo call) and document `/healthz` as readiness? Naming
  is the hard part, since `/healthz` already has the conventional liveness name
  and a frozen shape — `/livez` + `/readyz` is the Kubernetes-idiomatic pair,
  and keeping `/healthz` as a frozen alias of readiness costs nothing.
- Is a **startup** probe warranted? Migrations run at boot, so first-boot
  readiness is genuinely slower than steady-state. The compose healthcheck
  already carries `start_period: 20s`, which is the same idea expressed in
  Compose's vocabulary — worth making explicit rather than incidental.
- How does this interact with **Phase 5 / OPER-03**, which builds per-component
  health (database, blob store, durable queues, migrations, capacity, backup
  freshness) behind an authenticated route? That richer surface is diagnostic,
  not a probe — probes must stay unauthenticated, cheap, and dependency-honest.
  Settling probe semantics is a natural prerequisite for OPER-03, and doing it
  there avoids a second pass.
- Should readiness deliberately fail while a destructive operation (restore,
  migration, upgrade preflight) is in progress, so traffic drains cleanly? That
  is a genuine use of readiness that also serves Phase 5's recovery work.
- What should readiness do about *degraded but serving* states — blob store
  unreachable while Postgres is fine? Offline browse still works; downloads do
  not. Binary readiness may be too blunt.

## When to Surface

Surface during Phase 5 (OPER-03 component health) — that phase is already
opening the health surface, so the probe split is cheap there and expensive
later. Surface **immediately and unconditionally** if any orchestrator
deployment adapter is planned, because that is the moment the hazard becomes
live rather than theoretical.

Do not expand Phase 4 for this. Nothing today is misbehaving.

## Notes

Raised by the owner during Phase 4 planning: *"are we considering liveness
probes, readiness probes... I'm guessing healthz is our liveness and readiness
would be api/v1/capabilities returning 200 — just double checking the semantics
so at some point it's all good."*

The correction worth recording is that `/healthz` is currently the **readiness**
probe, not the liveness one, and there is no liveness probe at all. That is fine
under Docker Compose and dangerous under an orchestrator.

Current state for whoever picks this up: `PlaysteadWeb.HealthController`
(`lib/playstead_web/controllers/health_controller.ex`) — 200/503, body carries
no component detail, no version, shape frozen by D-16; routed at
`lib/playstead_web/router.ex:102` outside any auth pipeline.
