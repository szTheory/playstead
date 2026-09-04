---
id: SEED-032
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) execution
trigger_when: when planning any milestone that touches the adapter IPC contract, real-time session state, identity/presence, or server-hosted coordination; revisit alongside SEED-014 (federation) since lobbies and federation answer overlapping identity questions
scope: very large — deterministic emulation, netcode, NAT traversal, a coordination service, identity/presence, and a social surface. Almost certainly several phases, not one.
related: SEED-031 (recording and shareable moments), SEED-014 (lawful server federation and content distribution), SEED-004 (household player profiles), SEED-019 (system saves versus save states), SEED-013 (real device compatibility lab), SEED-007 (EmuDeck study)
---

# SEED-032: Online multiplayer lobbies

Owner idea, captured during Phase 04 execution, explicitly flagged as carrying
prior-art lessons and strangler-fig integration opportunities. Roadmap
consideration for a future milestone — not v1.0.

## What it is

Play a multiplayer game with someone who is not in the room: a lobby to find or
invite them, a session that connects two or more Playstead clients, and the
emulator driven by more than one player's input.

## The prior art is unusually rich, and unusually clear about what fails

This is a well-trodden category, and the lessons are not subtle:

- **Rollback netcode (GGPO and its descendants) beat delay-based netcode
  decisively**, and the reason generalizes: predict, render immediately, and
  correct on divergence rather than making everyone wait for the slowest peer.
  It requires the ability to save and restore emulator state cheaply, many times
  per second.
- **RetroArch netplay** is the closest direct analog and demonstrates the whole
  shape — lobby discovery, a coordination server, spectators, and per-core
  support that is genuinely uneven. It also demonstrates the failure mode:
  netplay works *per core*, and users cannot tell in advance which combination
  will hold together.
- **Determinism is the real gate, not bandwidth.** Two clients must produce
  identical state from identical inputs. Any divergence in core version, build
  flags, BIOS, or options desynchronizes the session. This is exactly the
  compatibility-fingerprint problem the project has already reasoned about for
  save states — and it is the same fingerprint.
- **Screen-sharing approaches (Parsec, Steam Remote Play Together) sidestep
  determinism entirely** by having one machine run the game and stream frames to
  the other. Radically simpler and adapter-agnostic; costs latency, video
  quality, and the ability for the host to walk away. A legitimately different
  product, and worth deciding against deliberately rather than by omission.
- **NAT traversal is a tax nobody escapes** — STUN/TURN or a relay, and a relay
  is an ongoing hosting cost with an ongoing abuse surface.

## Where the strangler-fig opportunities actually are

The point of naming this now is that Playstead already has the bones of several
pieces, and lobbies could grow around them rather than replacing them:

- **Save states as the session-start primitive.** Rollback needs cheap
  save/restore; joining a lobby mid-game needs exactly one such restore. The
  project already treats save states as fingerprint-bound local artifacts
  (SEED-019). Lobbies need that same fingerprint to be *negotiable between two
  machines* — which is an extension of existing thinking, not a new axis.
- **The adapter capability contract.** Netplay is a declared adapter capability
  in the same way frame capture (SEED-031) would be. Both want the adapter IPC
  boundary to have reserved room. That is a strong argument for designing that
  contract once, with both in mind, rather than twice.
- **Federation as the identity and discovery layer.** SEED-014 already asks who
  a Playstead server trusts and how servers relate. A lobby is a federated
  rendezvous with a different payload. Solving identity/presence once serves
  both; solving it twice is the waste this note exists to prevent.
- **Household profiles (SEED-004)** already establish "which player is this",
  locally. Lobbies extend the same question across machines.
- **Readiness machinery.** The project already computes whether a game is ready
  to launch, and already has vocabulary for saying honestly why it is not.
  "You and this player cannot play together, and here is precisely why" is the
  same engine pointed at a two-machine predicate.

## The questions that decide whether this is ever worth starting

- **Which shape?** Deterministic lockstep/rollback (hard, excellent when it
  works, per-adapter) versus host-and-stream (much simpler, adapter-agnostic,
  worse feel). Pick deliberately and early; they share almost no implementation.
- **Who runs the relay, and what does it cost?** A coordination server and TURN
  relay are recurring infrastructure with an abuse surface, in a project whose
  current posture is a server you run yourself.
- **What is the honest compatibility story?** RetroArch's lesson is that
  "supported" that silently varies per core destroys trust. Playstead's existing
  instinct — declared capabilities, honest readiness vocabulary, a real device
  compatibility lab (SEED-013) — is the right one to apply here, and the reason
  this could be better than the prior art rather than another instance of it.
- **What is lawful?** Same territory as SEED-014. Coordinating play is different
  from distributing content, but a hosted lobby service is a hosted service.

## Breadcrumbs

- `playstead-mac/Playstead/Adapter/AdapterHost.swift` — the process/IPC boundary
  any netplay capability must cross
- `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` — existing
  can-you-play-this-and-why machinery, the natural base for a two-machine predicate
- `playstead-mac/Playstead/Sync/` — existing client/server sync and journal
  infrastructure; note that lobby traffic is real-time and almost certainly does
  NOT belong on this path, but the identity/pairing groundwork does
- `.planning/seeds/SEED-014-lawful-server-federation-and-content-distribution.md`
  — overlapping identity, trust, and hosting questions
- `.planning/seeds/SEED-019-system-saves-versus-save-states.md` — the
  fingerprint/determinism contract lobbies depend on

## Notes

Captured from an owner aside during Phase 04 Wave 2, alongside SEED-031. The two
were raised together and share a dependency: both want room reserved in the
adapter capability contract. If either is ever picked up, design that contract
for both at once. Explicitly not for v1.0 and not to be pulled into Phase 04.
