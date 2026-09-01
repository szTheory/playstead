---
id: SEED-005
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
---

# SEED-005: Playtime and friendly last-played statistics

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-005` to add context._

Owner inspiration: EmuDeck surfaces compact continuity signals such as
“last played 7 seconds ago” and “playtime 4 minutes.” Playstead already records
coarse play-session start/end times and derives a most-recent play timestamp,
so a later product phase could explore trustworthy cumulative playtime and
human-friendly recency in library, Recent, Continue, or game-detail surfaces.

Any future design should define what counts as playtime, handle crashes and
unfinished sessions honestly, preserve offline convergence, and avoid implying
more timing precision than the underlying session lifecycle can support.

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-005` to estimate effort.

## Breadcrumbs

- `playstead-mac/Playstead/Curation/PlaySessionRecorder.swift` — local coarse
  session start/end lifecycle already exists
- `playstead-server/lib/playstead/curation.ex` — server derives per-game
  `last_played_at` from recorded sessions
- `playstead-mac/Playstead/Persistence/Migrations.swift` — local Recent mirror
  already stores `last_played_at`
- `playstead-mac/Playstead/Curation/RecentShelfView.swift` — likely future UI
  surface for friendly recency and aggregate playtime

## Notes

Captured via one-shot seed capture from an EmuDeck observation. Enrich with
trigger, why, display surfaces, and scope at your convenience.
