---
id: SEED-022
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning
trigger_when: when planning migration/onboarding for users with an existing collection, or when curation grows beyond Favorites/Collections into set-level reasoning
scope: medium — reconciliation views and a durable "curated subset" concept, on top of shipped recognition
related: SEED-021 (staged dogfooding ladder), SEED-020 (Steam Deck / Linux second client), SEED-016 (play queue backlog ergonomics), SEED-007 (EmuDeck study)
---

# SEED-022: Reconcile a scattered archive against the curated subset you actually play

## Why This Matters

The owner's real collection is not one pile. It is at least four:

- an external hard drive holding the bulk archive,
- `~/torrents` and `~/Downloads` on the Mac, accumulated ad hoc,
- a set staged on the Steam Deck via EmuDeck — deliberately curated, the
  games he actually wants to play, organized per console,
- and whatever ends up in Playstead as he migrates incrementally.

These overlap unpredictably. The same game may exist in three of them, in
different dumps, different regions, different archive formats, some renamed by
hand years ago. Phase 2's content-addressed import already collapses *exact*
byte duplicates for free, and reference-pack digest matching already identifies
what a blob actually is without trusting its filename. That solves recognition.

It does not solve the question the owner actually asked, which is a **set**
question, not a per-file question:

> "systematically migrate over to it as my source of truth by reconciling it
> with my other collections... my games I actually want to play I've been
> staging on EmuDeck, so that will kinda be my own source of truth for my
> curated collection."

There are two distinct sources of truth here and they answer different things.
The archive is the source of truth for *what I own*. The EmuDeck staging set is
the source of truth for *what I care about*. Migration is not done when the
bytes are all imported — it is done when Playstead can answer both, and the
owner trusts its answers more than he trusts his folders.

The valuable and non-obvious part: **the curated subset is itself worth
capturing as data, and it is the thing most at risk of being lost in a
migration.** Bytes are recoverable — they are hashed, verified, and exportable.
The knowledge of *which forty games out of four thousand are the ones you
actually play, on which console, in which order* exists today only as a folder
layout on a Steam Deck, and a naive "import everything" migration silently
discards it.

## Questions to Explore

- **Reconciliation views.** What are the honest set operations? "In my archive
  but not in Playstead," "in Playstead but not in the archive," "in my curated
  EmuDeck set but not yet cached locally," "imported but never played." Each is
  cheap to compute once contents are hashed, and each answers a real migration
  question.
- **Importing a curation, not just bytes.** Can a directory layout be read as a
  *curation proposal* — these are Collections, this is the per-console
  grouping — separately from importing the files themselves? That preserves the
  EmuDeck staging work instead of flattening it. Reference-pack matching means
  the proposal can be expressed in identified titles rather than filenames.
- **Coverage as a first-class number.** "Your curated set is 38/40 present and
  verified locally; 2 are server-only" is a far more motivating migration
  signal than a raw import count, and it maps directly onto the cache states
  Phase 3 already derives.
- **Remote sources.** The inbox is a local read-only host mount by deliberate
  design (`./inbox:ro` — the source-stays-untouched guarantee is kernel-enforced,
  not application-level). The Steam Deck collection is reachable over SSH. Is the
  right answer to keep the inbox local and treat `rsync` as the documented
  bridge, or is there a safe pull-from-remote story that does not weaken the
  read-only custody posture? Default assumption: keep the boundary, document the
  rsync.
- **Duplicate and variant reasoning across sources.** CAS collapses identical
  bytes automatically, but the interesting cases are near-duplicates: same game,
  different region or dump or archive wrapper. Phase 2 already models aliases
  and variants — do the reconciliation views surface those as one row with
  variants, or as noise?
- **Reversibility.** Every reconciliation action should be undoable and
  exportable, so a wrong bulk decision during migration is never load-bearing.

## When to Surface

Surface when the owner's incremental migration is actually underway — likely
during or just after Phase 5, once the sole-copy gate from SEED-021 is passed
and importing at scale becomes rational. Some of it may be answerable much more
cheaply than it looks, because recognition, cache-state derivation, and curation
primitives all already exist; this is largely new *views* over shipped data
rather than new subsystems.

Do not let it expand Phase 4 or Phase 5 scope.

## Notes

Captured verbatim-in-spirit from the owner's description of his real situation
during Phase 4 planning: a major archive spread across an external drive,
`~/torrents`, `~/Downloads`, and a Steam Deck, plus a deliberately curated
EmuDeck staging set that functions as his personal source of truth for "games I
actually want to play."

Worth restating for whoever picks this up: the answer to "is there a tool that
auto-identifies ROMs by hash" is already **yes, and it shipped in Phase 2** —
`Playstead.Recognition` matches blob digests and headerless-offset fingerprints
against administrator-supplied Logiqx/No-Intro-format DAT packs, entirely
offline, with header-evidence recognition and honest `unknown_system` /
`ambiguous` fallbacks feeding Needs Attention. This seed is about the layer
above that: sets, subsets, and migration confidence.
