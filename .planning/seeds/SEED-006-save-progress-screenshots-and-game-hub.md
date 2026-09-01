---
id: SEED-006
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
---

# SEED-006: Save-progress screenshots and a polished per-game hub

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-006` to add context._

Owner idea: when opening a game, make recognizable progress the first thing a
player sees—ideally a screenshot associated with a save or save state—inside a
polished per-game hub. The hub could eventually bring together play/continue,
progress history, saves, compatibility/readiness, provenance, and other
game-specific actions without crowding the main library.

The screenshot must be presented as context, not proof that a save is portable
or compatible. Save states remain emulator/core/build/options/content-bound;
persistent saves have a different portability contract. Any capture mechanism
must be adapter-capability-driven, privacy-aware, bounded, and optional.

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-006` to estimate effort.

## Breadcrumbs

- `.planning/discovery/USER-FEEDBACK.md` — already identifies a save gallery
  with thumbnails as a high-value follow-on
- `.planning/research/FEATURES.md` — save gallery and richer recovery views are
  deferred until revision correctness exists
- `.planning/PROJECT.md` — explicitly forbids universal save-state guarantees
- `.planning/discovery/WEB-AND-CLIENT-ARCHITECTURE.md` — save states are local
  experimental artifacts keyed by an exact compatibility fingerprint
- `playstead-mac/Playstead/Curation/PlaySessionRecorder.swift` — existing
  per-game continuity data a future hub could summarize

## Notes

Captured via one-shot seed capture from an owner observation while using
EmuDeck. Long-term polish goal only; do not pull it into Phase 03.5.
