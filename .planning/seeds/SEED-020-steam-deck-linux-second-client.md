---
id: SEED-020
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning
trigger_when: when scoping the milestone after v1.0, choosing the second independent client, or planning the owner's migration off EmuDeck
scope: large — a second client plus the protocol-boundary proof it exists to produce
related: SEED-007 (EmuDeck study and relationship options), SEED-013 (real-device compatibility lab), SEED-017 (progressive deployment modes)
---

# SEED-020: Make Steam Deck / Linux the second independent client

## Why This Matters

The owner already plays on a Steam Deck on the same LAN, set up with EmuDeck.
That is the incumbent this project is implicitly competing with for his own
daily use, and it is the concrete reason a second client matters sooner than a
platform-neutrality argument alone would justify.

Today the v1.0 roadmap is Mac-only in every client phase. `PROJECT.md` records
the long-term vision of "a platform-neutral protocol and family of clients for
Mac, Windows, Linux, Steam Deck, PSP/Vita-class homebrew devices, arcade and
living-room systems, and the web," and its Out of Scope list defers breadth
until "portability must be proven with a narrow adapter and then a second
independent client/adapter." So a second client is already the stated next
structural step — this seed names which one and why it should be the Deck.

The argument for the Deck specifically, over Windows or web:

- **It is the only candidate the owner will actually use every day.** A second
  client that nobody dogfoods proves the protocol on paper and nothing else.
- **It is the strongest protocol-boundary test available.** Different OS,
  different distribution model (Flatpak vs. notarized .app), different
  filesystem and sandbox semantics, different controller stack, different
  emulator packaging. Whatever leaked from the Mac client into the "shared"
  protocol will surface here.
- **It has a real incumbent to be measured against.** EmuDeck already solves
  acquisition-adjacent setup well. Playstead's differentiator is custody,
  provenance, and save continuity — claims that are testable side-by-side on the
  same hardware with the same library.
- **The save-continuity work in Phase 4 is the thing worth proving across two
  devices.** SAVE-04 (divergent revisions from the same base, no silent
  last-write-wins) is designed for exactly the Mac-plus-Deck situation, but with
  a Mac-only client it can only ever be tested with two Macs or a simulated
  second device. The Deck turns that requirement's headline case into a real one.

## Questions to Explore

- Client shape: native Linux app, Flatpak, or a Deck-appropriate Gamescope/Game
  Mode integration? What does "launch from the Deck's own UI" require?
- Does the existing HTTPS snapshot-and-cursor protocol survive contact with a
  second client unchanged, or does the Mac client hold assumptions that were
  never actually in the protocol? That answer is the real deliverable.
- How much of the Mac client is genuinely portable logic (sync engine, cache
  state derivation, readiness engine, save capture discipline) versus SwiftUI
  presentation? Is there a shared-core extraction worth doing first?
- Adapter story on Linux: the Deck already has emulators installed and managed
  by EmuDeck. Does Playstead install its own pinned adapter (consistent with the
  Mac posture), or can it adopt an already-present emulator — and what does that
  do to the "hash-pinned, empirically proven adapter" guarantee?
- Coexistence, not conquest: can Playstead be the custody and save layer while
  EmuDeck stays the launcher, at least initially? That is a far cheaper first
  integration than replacing the frontend, and it is the honest migration path.
- Certificate and pairing UX on a device with no Keychain equivalent — where does
  the scoped device credential live, and what is the revocation story?
- Does the export/reimport contract (PORT-01/02) give a safe manual bridge in the
  meantime — export from Playstead, drop into EmuDeck's expected layout?

## When to Surface

Surface when scoping the milestone after v1.0. This is explicitly not v1.0 work:
the Mac path must first be sealed through Phase 5's restore drill, or the second
client inherits unproven foundations and the protocol boundary gets tested
against a moving target.

The natural sequencing is: v1.0 seals Mac custody + play + saves + recovery →
second client (this seed) proves the protocol was real → breadth claims become
defensible instead of aspirational.

One nuance worth preserving: the owner's stated near-term tolerance is "if I can
use the Mac for now that's fine." So this is a roadmap commitment, not an
urgency. Do not let it pull scope into v1.0.

## Notes

Captured from the owner's own dogfooding question during Phase 4 planning —
"when can I actually start uploading my ROMs to it... I've got this Steam Deck"
— and his explicit request that Steam Deck be on the roadmap.

The related seeds cover adjacent but different ground: SEED-007 is about the
relationship with EmuDeck as a project (inspiration, contribution, integration,
forking); SEED-013 is the evidence-backed compatibility matrix and hardware lab.
This seed is narrower and more concrete than either: ship one Linux/Deck client
as the deliberate second implementation of the protocol.
