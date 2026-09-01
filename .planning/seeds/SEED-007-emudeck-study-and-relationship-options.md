---
id: SEED-007
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
---

# SEED-007: Study EmuDeck and evaluate inspiration, contribution, integration, or forking

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-007` to add context._

Owner observation: EmuDeck is a strong real-world experience with many useful
ideas Playstead could learn from. A future discovery effort should study what
works, keep what fits Playstead's custody/continuity values, and deliberately
leave behind what does not.

Possible relationships—taking design inspiration, contributing upstream,
building an integration, or forking—must remain separate evaluated options,
not a predetermined direction. Any code reuse or integration needs current
architecture, maintenance, security, license, trademark, platform, and user-data
reviews. Playstead's durable protocol and self-hosted ownership model must not
become coupled to one frontend or appliance ecosystem.

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-007` to estimate effort.

## Breadcrumbs

- `.planning/discovery/LANDSCAPE.md` — existing ecosystem comparison of
  frontends, launchers, appliances, and Steam Deck-adjacent projects
- `.planning/discovery/USER-FEEDBACK.md` — existing ES-DE/EmulationStation UX
  lessons and controller-first evidence
- `.planning/discovery/TECHNICAL-RISKS.md` — emulator adapters must remain
  client-side plugins behind a neutral server contract
- `.planning/research/FEATURES.md` — a second client/adapter is intentionally
  deferred until the Mac vertical slice is reliable
- `.planning/PROJECT.md` — long-term Steam Deck client vision and explicit
  compatibility/architecture constraints

## Notes

Captured via one-shot seed capture from an owner observation while actively
using EmuDeck. Begin with a documented study; make no integration/fork decision
without current evidence.
