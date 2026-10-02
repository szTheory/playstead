---
id: SEED-035
status: dormant
planted: 2026-10-02
planted_during: v1.0 / quick task 261002-hwa
trigger_when: before the next adapter, installer, or emulator host/core contract work
scope: emulator integration, artifact integrity, fixture provenance
---

# SEED-035: First-party host/core artifacts and fixture provenance

## Why This Matters

Playstead's future integration must identify and verify both the host and the
core it loads. A single adapter artifact pin cannot describe independently
versioned host and core artifacts or prove which core is installed and loaded.
The project also needs a deterministic, legally distributable fixture for
repeatable CI without weakening its private user-content posture.

## Owner Direction and Fixture Policy

- Playstead does not build emulator cores or a new emulation ABI. The owner
  builds cores in separate repositories. Each core repository produces a C
  library, a headless runner, and a thin Libretro adapter; no core-specific
  standalone player is planned.
- RetroArch is the interim host. A future shared host provisionally belongs
  under the Playstead product/repository umbrella, behind an adapter and in a
  separately launched least-privilege process. Revisit a separate repository
  only if independent users or lifecycle needs justify that boundary.
- Prefer a tiny Playstead-authored deterministic homebrew game/ROM, checked
  into Git together with its source, generated fixture, explicit license, and
  provenance, if it satisfies the required test oracle.
- The repository already contains the self-authored, MIT-licensed
  `playstead-mac/spike/testrom/savetest.gba` and its source/build files. Reuse
  it for the behaviors it actually covers; verify it against the continuation
  oracle before treating it as a replacement for an interactive resume fixture.
- A third-party fixture may be checked in or used by public CI only after
  verifying explicit rights from its public repository for distribution of
  the ROM, source code, assets, audio/data, and required attribution. Record
  the exact license and provenance. Do not infer ROM rights from a core or
  emulator license.
- AerevenAdvance remains private unless its rights are independently
  established. No fixture bytes or fixture implementation are authorized by
  this seed.

## Playstead-Facing Core and Host Requirements

Owner input for future core design, recorded 2026-10-02:

- Deterministic, non-interactive input replay with a framebuffer check. Phase
  06's current evidence is a narrow mGBA 0.10.5 plus private AerevenAdvance
  result; it is not a general compatibility claim.
- Periodic and on-demand battery-save flush, with an explicit way for the host
  to know when a requested flush is complete.
- Orderly shutdown on `SIGTERM` with documented, distinguishable exit outcomes
  for clean exit, failure, and forced termination.
- Keep runtime writes out of the ROM's directory. Do not mutate canonical save
  files through in-place memory-mapped writes; stage and safely publish flushed
  save data through the host's managed save location.
- Reserve frame access at the adapter/host boundary before that contract is
  frozen, as called out by [SEED-031](SEED-031-gameplay-recording-and-shareable-moments.md).
- Require deterministic execution and inexpensive save/restore as design
  capabilities, as called out by [SEED-032](SEED-032-online-multiplayer-lobbies.md).
- Give save states a compatibility fingerprint that identifies the core and
  build, system/firmware, content, and relevant core options or serialization
  format; never imply that states are universally portable.

This is a continuity-focused requirements baseline, not a complete frozen ABI.
Before designing the core/host contract, specify deterministic input timing,
frame metadata, flush/quit acknowledgement and timeout behavior, and the exact
fingerprint fields. The existing list does not settle those details or authorize
renderer/audio implementation.

## Future Host/Core Pin Contract

Before the next adapter, installer, or host/core contract implementation,
design a primary pin identity for a **compatible host/core pair**. The
contract should represent:

- Explicit host and core artifact roles with independent versions.
- Archive hashes and installed-file hashes for each artifact.
- Artifact provenance, license, and supported platform/architecture.
- A manifest describing compatible host/core pairs and constraints.
- Staged installation with atomic promotion and rollback on failure.
- A launch descriptor that selects the intended core library for the host.
- Runtime verification that the process loaded the pinned core artifact.
- A legacy standalone adapter as one supported pin case, not the universal
  identity model.

The pin pair is the future primary identity; a host version alone or adapter
version alone cannot establish compatibility or artifact integrity.

## Boundaries

This is a dormant planning seed. It does not authorize implementation of an
emulator host, renderer, audio stack, core, ROM fixture, installer, database
schema, or ORM model. Do not reuse or extend the Plan 06-20 Libretro harness;
it is test-only and throwaway. Revisit this seed when its trigger is reached,
then research current emulator licensing, platform support, and artifact
distribution rights before planning implementation.

## Provenance

Owner decision recorded 2026-10-02 in quick task `261002-hwa`. The durable
decision source is
`.planning/quick/261002-hwa-record-first-party-emulator-core-directi/261002-hwa-PLAN.md`;
project context is `.planning/PROJECT.md`, and the test-only harness
disposition is recorded in
`.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-20-SUMMARY.md`.
