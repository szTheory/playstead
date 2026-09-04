---
id: SEED-033
status: dormant
planted: 2026-09-04
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) execution
trigger_when: when planning the Mac client home/landing surface, any retention or "resume intent" UX, or the milestone that picks up SEED-011; revisit before SEED-011 is scoped, since this seed defines the surface that would consume its output
scope: medium-to-large — an information architecture question, a mood/intent taxonomy, and a ranking consumer. Depends on SEED-011 for ranking and SEED-016 for queue mechanics; contributes the opening surface neither of them owns.
related: SEED-011 (private explainable recommendations — the ENGINE), SEED-016 (play queue backlog ergonomics — the QUEUE), SEED-005 (playtime and last-played stats — the SIGNAL), SEED-006 (per-game hub and progress media — where a pick LANDS), SEED-004 (household player profiles — whose mood?), SEED-022 (collection reconciliation and curated subsets)
---

# SEED-033: "What should I play?" — a mood-aware home surface

Owner idea, captured during Phase 04 execution. Explicitly for roadmap
consideration, not v1.0.

## The idea

When you open Playstead, the first thing you see helps you answer the only
question that actually matters at that moment: **what am I going to play right
now?** Not a grid of everything you own — a small, honest set of suggestions that
keeps you on track and meets you where you are.

## Why this is not a duplicate of SEED-011 or SEED-016

The boundary matters, because three seeds now touch this territory and they
should not collapse into one mush:

| Seed | Owns |
|---|---|
| **SEED-011** | The **engine** — how candidates are ranked, explained in player language, and kept private and resettable |
| **SEED-016** | The **queue** — capture, reorder, remove, sync; the backlog as a durable list of intent |
| **SEED-033** (this) | The **opening surface and the intent axis** — what you see on launch, and the fact that the right answer depends on the player's *current mood*, not just their history |

SEED-011 asks "which games rank highest?" This seed asks "**ranked for what?**" —
and asserts that there is no single correct ranking because the player's goal
changes session to session.

## The insight worth keeping: mood is an input, not a preference

The owner's framing was that a player arrives in one of several distinct modes,
and the same library should answer differently for each:

- **"Surprise me"** — feeling random; wants a genuinely arbitrary pick from
  something plausible, and the delight is in not deciding
- **"Old favorites"** — comfort mode; wants the known-good thing, not discovery
- **"Crush the backlog"** — wants the shortest path to a game *finished* and off
  the list; optimizes for commitment and completability
- **"Finish what I started"** — wants games with real progress mid-flight;
  optimizes for resumability, which is exactly what Phase 04's save continuity
  work makes knowable

These are not user *settings* to configure once. They are **per-session
intents**, and the cheapest useful version of this feature is simply *asking* —
a few honest entry points rather than a model that silently guesses which mood
you are in and gets it wrong.

That framing is worth preserving because it inverts the usual build order.
The naive path is "build a recommender, then find somewhere to put it." The
better path is "name the four jobs, give each an honest entry point, and let
even a transparent baseline do a genuinely good job at each one." Most of the
value here needs no ranking sophistication at all — SEED-011 already argues for
transparent baselines before learned models, and a mood axis is precisely what
makes simple baselines feel smart.

## The constraint the owner stated, and it should be load-bearing

**"The whole point is just for the gamer to have fun."** Respect the player,
meet their needs, meet them where they are.

That is a real design constraint with teeth, and it rules things out:

- No engagement maximization. A surface that "keeps you on track" is a *tool*
  for the player's own stated intent, never a retention mechanism operating on
  them. SEED-016 already flags this line — do not turn Playstead into an
  attention-maximizing engagement system — and it applies with more force here,
  because the launch surface is the highest-leverage place to violate it.
- No guilt. A backlog surface that reads as a chore list, or that shames the
  player for unfinished games, fails the stated goal directly. "Crush the
  backlog" must be a mode the player *chooses*, never the app's default posture.
- No dark patterns on the opening screen: no streaks, no artificial urgency,
  no manufactured FOMO.
- The player must be able to turn it off and just see their library.

## What Phase 04 makes newly possible

Worth noting because it is not a coincidence that this idea surfaced now: **the
"finish what I started" mode is only honestly answerable once save continuity
exists.** Before Phase 04, "you have progress in this game" is a guess. After it,
progress is durable, versioned, and — critically — knowable across machines.
SEED-005's playtime and last-played stats are the other half of the signal.

So this seed's dependencies are already being built; it just should not be
started until there is a reason to design the client home surface.

## Immediate decision points, for whenever this is picked up

Recorded now so a future fan-out has somewhere to start:

1. **Ask or infer?** Explicit mode selection is cheaper, more honest, and more
   respectful than mood inference — and mood inference has an obvious creep risk.
   Strong prior toward asking; worth an explicit decision rather than drift.
2. **Does this replace the library view or sit above it?** Replacing the library
   with an algorithmic surface is the kind of decision that is very hard to walk
   back, and users of media apps frequently resent it.
3. **How many suggestions?** Small is the whole point. A wall of recommendations
   is just the library again.
4. **What does "completable" mean** for the backlog-crushing mode, given
   Playstead has no notion of game length or completion? This may need metadata
   it does not have (SEED-008), or may be answerable honestly from the player's
   own play patterns alone.
5. **Whose mood, in a household?** (SEED-004.) A shared machine with per-profile
   intent is a different design from a single-player one.
6. **Offline and cold-start.** A new library with no history must still produce a
   good answer for all four modes. SEED-011 already flags cold-start as a
   first-class requirement.

## Breadcrumbs

- `playstead-mac/Playstead/Library/` — where a home/landing surface would live
- `playstead-mac/Playstead/Curation/PlaySessionRecorder.swift` — existing
  per-session data; a primary signal for "finish what I started"
- `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` — a suggestion the
  player cannot actually launch right now is worse than no suggestion; any pick
  must be readiness-filtered
- `.planning/seeds/SEED-011-private-explainable-game-recommendations.md` — engine
- `.planning/seeds/SEED-016-play-queue-backlog-ergonomics.md` — queue
- `.planning/seeds/SEED-005-playtime-and-last-played-stats.md` — signal

## Notes

Captured from an owner aside during Phase 04 Wave 3, in the same series as
SEED-031 and SEED-032. The owner asked that this be held for ongoing roadmap
consideration and that a future pass fan out on the decision points above. Not to
be pulled into Phase 04.
