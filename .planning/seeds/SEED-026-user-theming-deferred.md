---
id: SEED-026
status: dormant
classification: deliberately deferred — considered and declined for now
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning
trigger_when: when users actually ask for it more than once, or when a design-token layer already exists for other reasons (see SEED-027) and theming becomes nearly free
scope: medium if built on an existing token layer; large if it becomes a plugin/marketplace surface
related: SEED-027 (Playstead brand and design system), SEED-024 (first-run TLS trust experience)
---

# SEED-026: User-installable themes — considered, deliberately deferred

## Status: deferred on purpose

This seed exists to record that theming **was considered and consciously
declined for now**, so the question does not get re-litigated from scratch every
time someone asks. It is not a backlog item awaiting capacity; it is a decision
with a stated rationale and a stated condition for revisiting.

## Why It Was Deferred

The owner's own framing was the strongest argument against it:

> "I'm guessing some people are gonna want to make this themeable — although
> Steam and Nintendo eShop are not themeable... that might just be future bloat."

That comparison is doing real work. The two most successful game libraries in
consumer software are **not** user-themeable, and their coherence is part of
what makes them feel trustworthy and finished. A library you keep your
collection in benefits from looking like one considered thing, not like a
surface someone else skinned.

The concrete costs of shipping themes early:

- **Every theme is a compatibility surface.** Once people install themes, any
  UI change can break them, and you inherit a soft obligation not to move
  things. That is a large tax to accept before the product's own visual identity
  is even settled.
- **It permanently widens the accessibility contract.** Phase 3 established a
  real accessibility and contrast floor, verified by automated audits in Phase
  3.5. A user-supplied theme can violate every one of those guarantees, and then
  the resulting inaccessible UI is still *your* product in the user's eyes.
  Either themes are validated against the contrast floor — which is genuine
  engineering — or the floor quietly becomes a suggestion.
- **It is the wrong order.** Theming abstracts design tokens for *other people*
  before Playstead has decided what its own tokens mean (SEED-027). Abstracting
  an identity you have not yet defined produces a token layer shaped by nothing
  in particular.
- **Distribution implies a plugin surface.** "People could download themes"
  means hosting, moderation, versioning, and potentially untrusted CSS in the
  console — a meaningful security surface for an app whose selling point is
  custody.

## What Would Change the Answer

Revisit if any of these become true:

- **The token layer exists anyway.** If SEED-027's brand work produces a real,
  semantic design-token layer, theming becomes mostly *exposing* something that
  already exists rather than building it. That is when the cost drops sharply
  and this becomes worth reconsidering.
- **Users ask repeatedly and specifically.** Not "can I theme it" once, but
  concrete requests — usually light mode, higher contrast, or larger type. Note
  those three are **accessibility and preference features, not theming**, and
  should be shipped directly as first-class options rather than delegated to a
  theme system.
- **A living-room or handheld client appears** (SEED-020) where a genuinely
  different visual mode — TV-distance typography, controller-first focus states —
  is a functional requirement rather than decoration.

## Notes

Captured verbatim-in-spirit from the owner during Phase 4 planning, including his
own instinct that it may be "future bloat" and his request that it be recorded as
considered-and-classified rather than silently dropped.

The likely honest resolution: ship **light mode and a high-contrast mode as
supported first-class options**, keep one coherent identity, and treat
user-installable themes as a separate decision that only becomes cheap after
SEED-027.
