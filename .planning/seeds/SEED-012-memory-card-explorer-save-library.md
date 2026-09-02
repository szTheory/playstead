---
id: SEED-012
status: dormant
planted: 2026-09-01
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
related: SEED-001 (save-file curation), SEED-010 (physical memory-card save archive), SEED-006 (save-progress screenshots and game hub), SEED-019 (system saves versus save states)
---

# SEED-012: Reimagine the console memory-card screen as a save explorer

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-012` to add context._

Original console memory-card screens made saves feel like tangible possessions:
they occupied recognizable slots or blocks, carried icons and labels, and could
be deliberately copied, moved, inspected, or deleted. Playstead could reinterpret
that interaction model as a modern save explorer and curation surface instead of
reproducing a literal or purely nostalgic skeuomorphism.

The explorer could connect whole-card images, parsed save entries, persistent-save
revisions, and emulator-specific save states without pretending those artifacts
are interchangeable. Depending on what the source format can actually prove, it
could show device or card provenance, capacity or block usage, favorite or
treasured markers, owner notes, screenshots, revision ancestry, compatibility,
and explicit import, export, copy, archive, or restore actions.

Familiar verbs must retain honest custody semantics. “Copy,” “move,” and “delete”
must not silently mutate exact archived bytes, discard revision history, or erase
provenance. Destructive actions should identify the precise artifact affected,
confirm consequences, and preserve the project's export and recovery guarantees.

The visual concept should remain fast, accessible, and controller-friendly, with
equivalent list navigation, screen-reader labels, keyboard support, reduced-motion
behavior, and clear format/system/compatibility evidence. System-inspired themes
must not copy proprietary trade dress or assets without appropriate rights.

## When to Surface

**Trigger:** when relevant

Surface this seed when designing save curation, a per-game save/history hub,
physical memory-card import review, or controller-first client navigation. It
should be considered only after the underlying immutable save-revision and
provenance contracts are explicit.

## Scope Estimate

**Unknown** — likely spans information architecture, save-domain contracts,
accessibility, controller navigation, and multiple client surfaces; estimate when
the relevant save or client-UX milestone is selected.

## Breadcrumbs

- `.planning/seeds/SEED-019-system-saves-versus-save-states.md` — the prior
  question of what these artifacts are and which differences must stay visible
- `.planning/seeds/SEED-001-save-file-curation.md` — owner annotations,
  favorites, keep/protect intent, provenance, and conflict-safe save curation
- `.planning/seeds/SEED-010-physical-memory-card-save-archive.md` — read-only
  acquisition and the distinction between a whole card image and parsed saves
- `.planning/seeds/SEED-006-save-progress-screenshots-and-game-hub.md` — visual
  progress recognition and the future per-game hub
- `.planning/discovery/EXPERIENCE-ETHOS.md` — Playstead's interaction principles
- `.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` — current
  client accessibility, status, and interaction contracts

## Notes

Captured via one-shot seed capture during Phase 03.5 from the owner's observation
that classic memory-card screens may be a strong interaction metaphor for a
future save explorer. Keep it out of the current phase until save custody and
revision semantics can support the interface honestly.
