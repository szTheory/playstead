---
id: SEED-008
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
---

# SEED-008: Put instructions and manuals within easy reach while playing

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-008` to add context._

The owner wants a quick way to see game instructions from a pause menu or
equivalent in-game surface. It should help someone resume a game without
leaving the controller-first experience or hunting through unrelated screens.

A future discovery effort should first investigate current metadata/manual
providers, their coverage, provenance, APIs, licensing, redistribution rights,
and offline-cache terms. Playstead should consider maintaining its own database
only if the evidence shows a durable gap worth the legal and operational cost.

The design should distinguish between project-authored control hints, adapter
or controller mappings, links to external sources, redistributable community
documentation, and private user-supplied manuals. It must not scrape or
redistribute proprietary manuals without permission. Optional instruction
metadata must also remain off the launch critical path and be useful offline
when legitimately cacheable.

Treat metadata enrichment as an explicit, understandable delivery policy rather
than a one-time bulk scrape. A likely balanced default is lightweight identity
plus cover/box art and one representative screenshot when legitimately available;
videos, additional galleries, manuals, and other large or rights-sensitive media
can be fetched just in time or selected per game/collection. Players who value a
fully prepared offline library should also be able to choose a bounded "make this
ready" action after seeing the estimated request count, download size, storage
impact, provider constraints, and exactly which media classes will be cached.

Explore a small set of intention-revealing policies—such as minimal, balanced,
and offline-complete—plus per-media overrides, rather than exposing every provider
knob. Defaults should adapt to library size, network/storage limits, provider
rate quotas, existing cache coverage, and player interest without making opaque
decisions. Prefetch can prioritize favorites, Continue/recent titles, pinned
collections, or explicitly selected games, while eviction remains independent
from canonical ROM/save custody and never removes private user-supplied manuals.

Every fetched asset needs source/provider, lookup evidence, license/usage terms,
fetch time, confidence, transformation history, cacheability/expiry, and user
override provenance. Respect API quotas and backoff; coalesce duplicate requests;
resume bounded jobs; expose partial/failed enrichment without blocking play; and
never treat a high request allowance as permission to scrape or redistribute.
Investigate whether videos should be streamed, cached on demand, or represented
by a poster/preview by default, since their bandwidth, storage, codec, and rights
costs differ materially from still images.

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.
Surface before adopting a metadata provider, building bulk catalogue enrichment,
designing per-game hubs, or promising an offline-complete media experience.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-008` to estimate effort.
Split into provider/legal research, a media/provenance schema, bounded enrichment
jobs and cache policy, then player-facing defaults and per-game/collection controls.

## Breadcrumbs

- `.planning/PROJECT.md` — manuals are already modeled as possible game-release
  assets, while optional metadata services must never gate offline play
- `.planning/discovery/USER-FEEDBACK.md` — game releases may include manuals and
  metadata must preserve source, confidence, and user correction
- `.planning/discovery/EXPERIENCE-ETHOS.md` — player-facing flows are
  controller-first and advanced information should appear progressively in context
- `.planning/discovery/LANDSCAPE.md` — existing ecosystem and metadata-service
  research provides a starting point for provider discovery
- `playstead-mac/Playstead/Controller/ControllerSettingsView.swift` — current
  local controller-mapping surface that could supply honest control hints
- `.planning/seeds/SEED-006-save-progress-screenshots-and-game-hub.md` — related
  per-game hub, where catalogue media and player-progress captures must remain
  visibly distinct

## Notes

Captured via one-shot seed capture during Phase 03.5. There is no assumption
that a pause overlay already exists; treat both the pause experience and the
instruction source as future design/research work. Enriched on 2026-09-01 from
the owner's catalogue observation: prefer smart cover/screenshot defaults and
just-in-time caching, while still offering an explicit bounded way to prepare
richer video/manual metadata for chosen games or an offline library.
