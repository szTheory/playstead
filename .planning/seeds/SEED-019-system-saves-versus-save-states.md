---
id: SEED-019
status: dormant
planted: 2026-09-02
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when designing save curation, a per-game save hub, or any surface that lists both persistent saves and save states
scope: large — save-domain contracts, information architecture, client UX, accessibility, and destructive-action semantics
related: SEED-012 (memory-card screen as save explorer), SEED-001 (save-file curation), SEED-010 (physical memory-card save archive), SEED-006 (save-progress screenshots and game hub)
---

# SEED-019: Find the honest UI/UX for system saves versus save states

## Why This Matters

Playstead has to present two kinds of artifact that are alike enough to invite a
single surface and different enough that one surface can quietly lie. A memory-card
or cartridge **system save** is the game's own record of progress, written by the
game through the console's rules: coarse, deliberate, portable across hardware, and
meaningful without an emulator. A **save state** is a snapshot of the whole machine,
written by the emulator: instantaneous, arbitrarily frequent, often bound to one
emulator version, and meaningless outside it.

Collapsing them costs the user real things. A save state can silently rot when an
emulator updates while a system save keeps working for decades. A system save can be
exported to real hardware while a save state cannot. "Continue where I left off"
means something different for each. Yet keeping them fully separate is its own
failure: a player thinks in terms of *where they are in the game*, not in terms of
which subsystem wrote the bytes, and forcing that distinction into navigation makes
the product feel like a filesystem.

The design space between those failures is the thing worth exploring, and it is
mostly unexplored by existing front ends, which typically pick one extreme.

## Questions to Explore

- What is the smallest honest vocabulary? Are these two kinds of one thing, two
  distinct things that share a shelf, or a spectrum with system saves and save
  states at the ends? Settle this in the domain language before the pixels.
- Can one timeline hold both — the game's own progress plus machine snapshots
  hanging off it — so a player reads recency and position without reading types?
- Which verbs are shared and which must diverge? Copy, move, delete, export,
  restore, favorite, and annotate may all mean different things per kind, and a
  verb that means two things is worse than two verbs.
- How does durability get expressed without nagging? A save state bound to an
  emulator version is a real fragility the user should feel *before* relying on it,
  not after it breaks. Is that a badge, a sort order, a promotion prompt?
- Should the product offer promotion — "make this permanent" — turning a save state
  into something durable by resuming and letting the game save through its own
  rules? That may be the move that makes one surface honest.
- What happens on conflict, when a system save and a newer save state disagree
  about progress? This is the case that most tempts a lying UI.
- What does an emulator that supports neither, or only one, do to the surface?
- Accessibility and controller-first navigation for both kinds, with equivalent
  list semantics, screen-reader labels, and reduced-motion behavior.

## When to Surface

Surface during a save-curation, per-game hub, or client save-management phase, and
only after immutable save-revision and provenance contracts are explicit — the same
precondition SEED-012 carries. Design the taxonomy and the verbs first; the visual
metaphor (memory-card explorer or otherwise) is downstream of that decision and is
SEED-012's subject.

## Breadcrumbs

- `.planning/seeds/SEED-012-memory-card-explorer-save-library.md` — the visual
  metaphor this taxonomy would feed
- `.planning/seeds/SEED-001-save-file-curation.md` — owner annotations, favorites,
  and conflict-safe curation
- `.planning/seeds/SEED-010-physical-memory-card-save-archive.md` — whole-card
  images versus parsed saves, and read-only acquisition
- `.planning/discovery/EXPERIENCE-ETHOS.md` — Playstead's interaction principles

## Notes

Captured from the owner's observation that system saves and save states are "kind of
similar but not quite the same either — they have to be handled differently but then
similar in some ways," and the wish to explore that design space properly rather
than settle it by default. SEED-012 treats the memory-card screen as an interaction
metaphor; this seed is the prior question of what the objects actually are and which
differences a player must be able to see. Not a change to current verification work.
