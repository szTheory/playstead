---
id: SEED-001
status: dormant
planted: 2026-08-30
planted_during: v1.0 / Phase 3 (mac-offline-play-vertical-slice) execution
trigger_when: any milestone or phase that designs launcher/client UX (library, curation, or save-sync surfaces) — surface before locking that UI spec
scope: unknown
---

# SEED-001: Save-file curation as a first-class UX concept

## Why This Matters

Owner-stated intent (2026-08-30, mid-Phase-3): a user's **save-file collection may matter more to them than their game collection**. Saves represent invested play, and a valued save is one of the strongest "I'll come back and play this" signals the product can observe. Today curation covers five game-centric nouns (Favorites, Collections, Queue, Continue dismissals, Play sessions — D-07..D-10); saves are treated as sync payload, not as something a user browses, organizes, or treasures.

Owner follow-up (2026-09-01): not every captured save has equal personal
meaning. Some are incidental traces from briefly trying a game; others preserve
childhood progress, a completed challenge, a rare unlock, a family member's
playthrough, or another moment the owner deeply cares about. Playstead should
let the owner express that distinction instead of treating every revision as an
anonymous timestamped blob.

Future exploration should include favorite/treasured saves, names, notes,
tags, and explicit keep/protect signals. Provenance should remain attached:
origin device or physical medium, import method, emulator/core and version,
game/content fingerprint, format identity, capture time, revision ancestry,
conversion history, and what is known versus inferred. Optional screenshots
may make meaningful revisions recognizable, while the exact save bytes remain
the authority.

Curation metadata must never silently choose a conflict winner, rewrite the
canonical save head, or imply compatibility. It may influence presentation,
retention suggestions, backup emphasis, or recommendation signals only through
explicit, explainable rules. Incidental saves should remain recoverable under
the normal retention contract unless the owner deliberately deletes them.

The player-facing model should not expose an undifferentiated wall of immutable
revisions. Explore named save lines or familiar slots—such as "before the final
battle," "challenge run," or "family playthrough"—that the player can save over
in the ordinary sense while Playstead retains an append-only revision stream
behind that name. The latest compatible revision can be the default view, with
history, ancestry, conflicts, provenance, and restoration available on demand.
This may borrow event-sourcing ideas, but the architecture should follow the
custody and recovery requirements rather than adopting event sourcing as a goal.

The interaction should support low-friction rename, annotate, protect, branch,
compare, restore, archive, and deliberately delete actions, using collection-
or crate-like curation only where it improves the player's mental model. A
logical slot/name must not erase conflicting device histories or make an old
revision unrecoverable merely because the player "saved over" it.

## When to Surface

**Trigger:** whenever we design or revise the UI/UX of launchers that connect to Playstead (Mac client, web console, future clients) — especially any work touching the library/curation surface or persistent-save handling. Also relevant to the next milestone's requirements gathering (`/gsd-new-milestone`).

Questions to answer when this surfaces:
- Should saves be a curated noun alongside the existing five (browse, favorite, annotate, pin saves)?
- Does save curation change the status ladder / card anatomy locked in 03-UI-SPEC.md?
- Is "has treasured saves" a Continue/Recent ranking signal?
- Which provenance fields belong to immutable revision evidence, which are
  owner-editable annotations, and which are derived hints?
- Does "favorite" mean presentation only, or also an explicit retention and
  backup-protection promise? The UI must state the contract precisely.
- How should named milestones, notes, tags, screenshots, and physical-media
  imports appear in a per-game save-history hub without confusing persistent
  saves with emulator-specific save states?
- How are annotations, favorites, and provenance included in documented export
  and restored without changing the checksummed save bytes?
- Is the primary player-facing noun a save, slot, line, checkpoint, memory, or
  something else—and how does it map to immutable revisions and conflict heads?
- Can a player reuse one named slot while the system retains bounded history,
  and what retention/compaction policy keeps that history useful rather than
  overwhelming?
- When should branching be explicit, and when should the product quietly show a
  simple current save with recoverable history behind it?

## Scope Estimate

**Unknown** — likely touches server curation model, sync entity kinds, and every client's library UI; estimate when triggered.
Split discovery from implementation: first validate the player mental model and
information hierarchy, then specify the durable named-line/revision mapping,
retention contract, export shape, and conflict semantics.

## Breadcrumbs

- `.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` — locked Phase 3 design contract this would extend
- `playstead-server/lib/playstead/curation.ex` — the five curation nouns this would join (D-07..D-10)
- `.planning/phases/03-mac-offline-play-vertical-slice/03-SPIKE-REPORT.md` — D-03 save-flush cadence evidence (saves are already a custody focus)
- `.planning/seeds/SEED-006-save-progress-screenshots-and-game-hub.md` — related
  visual progress and per-game hub concept, with save-state compatibility caveats
- `.planning/seeds/SEED-010-physical-memory-card-save-archive.md` — physical-media
  provenance and read-only archival source for imported save revisions
- PROJECT.md core value: "a locally available game **and its progress** remain … fully under the user's control"

## Notes

Captured via one-shot seed capture from an owner remark during Phase 3
execution. Enriched from the owner's 2026-09-01 distinction between incidental
and personally meaningful saves, and again from the idea of player-named slots
backed by an append-only revision stream; no separate duplicate seed was created.
