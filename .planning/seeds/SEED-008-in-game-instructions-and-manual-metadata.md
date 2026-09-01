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

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-008` to estimate effort.

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

## Notes

Captured via one-shot seed capture during Phase 03.5. There is no assumption
that a pause overlay already exists; treat both the pause experience and the
instruction source as future design/research work.
