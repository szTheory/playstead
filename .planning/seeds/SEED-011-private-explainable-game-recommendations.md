---
id: SEED-011
status: dormant
planted: 2026-09-01
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
related: SEED-005 (playtime and last-played stats)
---

# SEED-011: Add private, explainable game recommendations

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-011` to add context._

The owner wants Playstead eventually to help a player discover what to play
next. The implementation does not need machine learning: it should use the
simplest efficient approach that produces useful, delightful results, and only
adopt a more complex model when measured quality justifies it.

A future discovery effort should compare transparent baselines—recently added
or neglected games, system and metadata affinity, favorites, play recency,
session patterns, user-curated collections, diversity, and explicit
dismissals—against content-based or learned approaches. Single-user and sparse
libraries need strong cold-start behavior; collaborative filtering must not
quietly require sending private play history to a shared service.

Recommendations should explain themselves in player language (for example,
"because you favorited two short GBA puzzle games"), support dismiss/not-now
feedback, avoid repetitive popularity loops, and let the owner reset or disable
personalization. Training inputs, derived profiles, and recommendation history
remain user-owned and exportable. Optional enrichment must never gate library
browse, offline launch, saves, or ordinary curation.

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-011` to estimate effort.

## Breadcrumbs

- `.planning/PROJECT.md` — explicitly anticipates restrained recommendations
  inspired by music libraries while keeping them off the critical path
- `.planning/PROJECT.md` — current product decision prioritizes curated personal
  views before an exhaustive recommendation engine
- `.planning/seeds/SEED-005-playtime-and-last-played-stats.md` — possible local
  behavioral signals and their privacy/accuracy constraints
- `playstead-mac/Playstead/Curation/PlaySessionRecorder.swift` — current coarse
  play-session model exists only for Recent and Continue, so broader reuse must
  be an explicit future contract
- `playstead-mac/Playstead/Curation/FavoritesViewModel.swift` — explicit owner
  preference signal already represented in the local-first curation model

## Notes

Captured via one-shot seed capture during Phase 03.5. Begin any future work
with offline, deterministic baselines and a measurable evaluation set; do not
select "AI" or an external recommendation service before proving it improves
quality without compromising privacy, explainability, or administration.
