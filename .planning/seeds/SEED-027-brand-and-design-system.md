---
id: SEED-027
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning
trigger_when: before any public release, before a second client makes visual divergence permanent, or when UI-SPEC decisions start being re-argued per phase
scope: large — brand identity work plus a semantic design-token layer and motion system across two clients
related: SEED-026 (user theming — deferred until this exists), SEED-020 (Steam Deck / Linux second client), SEED-024 (first-run experience)
---

# SEED-027: Establish the Playstead brand and a real design system

## Why This Matters

Playstead currently has **conventions** — a locked `03-UI-SPEC.md` contract, a
status vocabulary and its ladder, card geometry rules, honest empty states, an
accessibility and contrast floor, and a snapshot harness that fails CI on visual
regression. That is genuinely more discipline than most projects have, and it is
worth saying that the foundation is good.

What it does not have is an **identity**: a logo, a defined palette with semantic
meaning, a type scale, a spacing system, a motion language, and a written
rationale tying them together. The colors currently live as hex literals inline
in LiveView templates (`#94A3B8`, `#0F172A`, `#334155`, `#38BDF8` appear directly
in `setup_live.ex`). That works, and it is consistent by convention — but nothing
*enforces* the consistency, nothing names what those colors mean, and nothing
tells a future contributor which one to reach for.

Three forces make this worth doing before too long:

1. **A second client makes divergence permanent.** SEED-020 anticipates a
   Linux/Steam Deck client. Two clients built from conventions rather than shared
   tokens will drift, and reconciling them afterward is far more expensive than
   defining the tokens once. The Mac client and the LiveView console already have
   this exposure today.
2. **The product's whole pitch is trustworthiness.** Custody, provenance, exact
   bytes, honest status. Visual polish is not decoration for a product like this —
   coherence and craft are how trustworthiness is *communicated* before anyone
   reads a word. A library that looks unfinished undermines a claim of safety.
3. **Every re-argument costs a phase.** Without a system, each new surface
   re-derives spacing, color, and motion from adjacent screens. That is how
   subtle inconsistency accumulates, and it is invisible until you see two
   screens side by side.

## What This Would Cover

- **Identity**: name treatment, logo/mark, and what "Playstead" should feel like.
  The name suggests a *homestead* for play — somewhere your things live safely,
  which is exactly the product thesis and a strong brief for a designer.
- **Palette with semantics.** Not just hex values, but named roles — surface,
  raised surface, border, primary text, secondary text, accent, and the status
  colors, which here are load-bearing rather than decorative. The status
  vocabulary (server-only, queued, partial, verified-local, pinned, safe-to-evict,
  and Phase 4's local-only/uploaded/current/restored/conflicted) is a *semantic
  system already* — it deserves a color system that encodes the ladder rather
  than one hue per state chosen ad hoc.
- **Typography**: a type scale, weights, and the rules for honest titles and
  truncation. Card geometry already forbids title-derived color and cover art —
  those constraints imply a typographic identity that has not been written down.
- **Spacing and layout**: a spacing scale, density rules, and the eight-step
  navigation order that is already locked in UI-SPEC.
- **Motion**: micro-animations, durations, easing — and crucially the
  reduced-motion substitutions, which Phase 3.5 already snapshot-tests. A motion
  system with the accessibility variant designed in from the start rather than
  retrofitted.
- **Tokens as the deliverable.** The output should be a real token layer
  consumable by both SwiftUI and the LiveView/Tailwind console, not a PDF
  brand book that drifts from the code within a month. A brand book that cannot
  be imported is a document about a design system, not a design system.

## Questions to Explore

- Does the token layer live in one shared source of truth generating both
  platforms' definitions, or two hand-synced copies with a test asserting parity?
  The project's existing instinct — see the snapshot contract — favors an
  enforced check over a convention.
- How do design tokens interact with the **locked UI-SPEC contracts** and the
  snapshot tests? Ideally tokens make those tests *stronger* (assert against
  named roles rather than hex literals) rather than churning them.
- Is this one focused milestone, or continuous work threaded through phases?
  Identity work benefits from being done once, deliberately, with a real
  designer; token adoption can then be incremental.
- Does the accessibility floor become *easier* to hold with semantic tokens —
  contrast ratios verified once per token pair rather than per component? That
  would be a strong argument for doing this sooner.

## When to Surface

Surface before any public release, and definitely before the second client
(SEED-020) makes divergence permanent. It is explicitly not v1.0 work — v1.0 is
about proving custody, play, saves, and recovery actually work, and a brand
cannot rescue a product that has not proven those. But it should not wait long
after.

Note that SEED-026 (user theming) is deliberately deferred *until this exists* —
theming an identity you have not defined is backwards, and once a semantic token
layer exists, theming becomes a much cheaper conversation.

## Notes

Raised by the owner during Phase 4 planning: a wish to "flesh out the so-called
brand for Playstead — its logo, its colors, typography, padding, design tokens,
design system," producing "a palette that makes it look really consistent and
good looking, polished UI/UX, micro-animations all nice and tight... all in a
design system that looks coherent."

Current state for whoever picks this up: `03-UI-SPEC.md` holds the locked visual
contract; `PlaysteadTests/LibraryContractSnapshotTests` and
`StorageContractSnapshotTests` enforce it on the Mac side; the console's colors
are inline hex literals in LiveView templates. The discipline exists; the
identity and the token layer do not.
