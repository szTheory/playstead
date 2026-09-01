---
id: SEED-009
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
---

# SEED-009: Maintain a coherent ubiquitous domain language

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-009` to add context._

Playstead should periodically inventory the nouns, verbs, events, and state
names used across the domain model, API, persistence, native client, web
console, and planning documents. Accidental aliases—especially three names for
one concept—or one name overloaded across different concepts make the model
harder to understand and allow behavior to drift between layers.

Internal domain language and player-facing gamer language should stay as close
as practical. Where a friendlier UI term genuinely differs from a precise
technical term, the translation should be explicit and documented instead of
emerging independently in each client. An audit should identify canonical
terms, intentional translations, ambiguous names, obsolete synonyms, and
events or actions that lack a stable verb.

This is a domain-model health practice, not a request for immediate broad
renaming. Reviews should happen at natural boundaries and propose bounded,
migration-aware cleanup so API compatibility, persisted data, and historical
artifacts remain safe.

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-009` to estimate effort.

## Breadcrumbs

- `.planning/PROJECT.md` — establishes core product nouns and the boundary
  between durable protocol language and player-facing experience
- `.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` — already
  freezes shared information-architecture nouns and status vocabulary across clients
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/B-curation-ownership-and-sync.md`
  — records the deliberate curation vocabulary: Favorites, Collections,
  Continue, Queue, and Recent
- `playstead-server/lib/playstead/sync/entity_kind.ex` — central registry for
  durable change-journal entity-kind vocabulary
- `playstead-mac/Playstead/Controller/ControllerMapping.swift` — example of a
  fixed adapter-input vocabulary at a client/domain boundary

## Notes

Captured via one-shot seed capture during Phase 03.5. A future audit should
produce a lightweight glossary and a mapping of intentional internal-to-UI
translations, then turn only evidenced inconsistencies into scoped work.
