---
id: SEED-016
status: dormant
planted: 2026-09-02
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when the existing Play Queue reaches player UAT or a future curation/retention UX phase is planned
scope: small-to-medium — player research, terminology, queue ergonomics, and cross-client UI refinement
---

# SEED-016: Refine the Play Queue into an excellent game backlog

## Why This Matters

Playstead already defines the server-canonical, per-user, synced **Play Queue** as
a backlog/watchlist: games the player intends to play, not a per-device playback
buffer. The future opportunity is to make that intent genuinely useful—quick to
capture from anywhere, easy to scan when deciding what to play next, simple to
reorder or remove, and consistent across the Mac client and web console.

This is a refinement seed, not a second queue model and not a request to change
the Phase 3 implementation during Phase 03.5.

## Questions to Explore

- Validate the player-facing name through the ubiquitous-language work: **Play
  Queue**, **Up Next**, **Backlog**, or a carefully separated internal/public
  vocabulary. Avoid making it sound like an automatic launch queue.
- Study how players actually choose a next game: ordering, lightweight priority,
  recently added, estimated commitment, system/device readiness, local
  availability, multiplayer context, and deliberate randomness. Add fields only
  when a named job cannot be solved with existing order and filters.
- Make add/remove/reorder actions fast, reversible, keyboard/controller-friendly,
  offline-capable, and honest about sync. Preserve the existing server-canonical
  queue and per-row idempotent/fractional-ordering contracts.
- Consider gentle prompts or views that help a player resume intent without
  turning Playstead into an attention-maximizing engagement system. Never hide
  ownership, readiness, or export behind personalization.
- Research watchlist/backlog lessons from Netflix, Plex, Letterboxd, Steam,
  console libraries, and dedicated game-backlog tools. Separate useful
  information architecture and cross-device continuity from dark patterns,
  autoplay pressure, opaque ranking, and retention-at-all-costs incentives.
- Explore how the queue should interact with Collections, Favorites, Continue,
  Recent, recommendations, device compatibility, and “not working here” status
  without collapsing those distinct player intents into one overloaded list.

## When to Surface

Surface after the current Play Queue receives real player UAT, or while planning
a dedicated curation/library UX phase. Start with observed friction and a small
vertical improvement rather than speculative metadata or a new recommendation
engine.

## Breadcrumbs

- `.planning/phases/03-mac-offline-play-vertical-slice/03-CONTEXT.md` — D-07
  establishes queue-as-backlog/watchlist, server-canonical and synced
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/B-curation-ownership-and-sync.md`
  — one queue per user, prior-art comparison, and “Up Next” naming candidate
- `.planning/seeds/SEED-009-ubiquitous-domain-language-audits.md` — player-facing
  and internal terminology convergence
- `.planning/seeds/SEED-011-private-explainable-game-recommendations.md` — future
  recommendations must remain distinct from explicit player queue intent
- `.planning/seeds/SEED-013-real-device-compatibility-lab.md` — readiness and
  device-specific “not working” evidence that may inform what is playable next

## Notes

Captured from the owner's idea to make backlog curation help answer “what did I
want to play next?” and to examine Netflix-like watchlist lessons without copying
Netflix or inheriting its engagement incentives.
