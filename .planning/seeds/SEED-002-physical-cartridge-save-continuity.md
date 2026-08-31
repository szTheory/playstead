---
id: SEED-002
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 3 (mac-offline-play-vertical-slice) — post-review hardening
trigger_when: any milestone or phase that designs save sync, save portability, or device/peripheral integration — surface before locking the save-revision model or the device-pairing surface
scope: unknown — hardware-dependent, likely its own milestone
related: SEED-001 (save-file curation), Phase 4 (Persistent Save Continuity)
---

# SEED-002: Save continuity between real cartridges and emulated play

## Why This Matters

Owner-stated intent (2026-08-31): real collectors own **both** physical cartridges and
emulated copies of the same game, and will want one continuous save across them.

The concrete want: plug a Game Boy cartridge into a cart reader/writer, have Playstead
**pull the save off the cartridge**; and conversely, take a save revision that lives in
Playstead and **write it back onto the cartridge**. Same idea extended to flash carts
(EverDrive-class devices), which are already a common part of how people play originals on
original hardware.

The underlying principle is bigger than the hardware: **a save belongs to the player, not to
the medium it happens to sit on.** Play on the couch on real hardware, continue on the Mac
emulator, put the progress back on the cart. Realistically most enthusiasts have both, and
today those two libraries are entirely disconnected.

This is a strong differentiator. Save sync between emulators is a solved-ish problem; save
continuity across the physical/emulated boundary is not, and it speaks directly to the
custody-and-ownership ethos this project is built on (see `discovery/EXPERIENCE-ETHOS.md`).

## When to Surface

**Trigger:** any work that designs or revises the save-revision model, save portability, or
device/peripheral integration. Most immediately relevant to **Phase 4 (Persistent Save
Continuity)** — not to build then, but so Phase 4's revision model does not accidentally
foreclose it.

Questions to answer when this surfaces:

- **Revision model.** Phase 4's success criteria already cover divergent revisions across two
  devices with device/time/play context. Does a cartridge count as "a device"? If a cart's
  save is just another revision source, much of the model may already fit — but only if
  Phase 4 does not hard-assume every revision originates from a paired Playstead client.
- **Provenance and trust.** A cartridge save has no device credential and no journal cursor.
  How is it attributed, and how is it distinguished from a client-originated revision?
- **Write-back safety.** Writing to a physical cartridge is destructive and often
  irreversible — a battery-backed SRAM cart may hold the only copy of a decades-old save.
  Any write-back path needs a mandatory read-and-archive-first step, and probably an explicit
  typed confirmation. This is a materially higher-stakes operation than anything in v1.0.
- **Hardware landscape.** Which readers/writers are worth supporting, and what do they expose
  (USB serial? mass storage? vendor SDK?). Likely candidates to research: GBxCart RW,
  Joey Jr, retrode-class devices, and the EverDrive/flash-cart family (which mostly present
  as SD cards and may need no special hardware integration at all — possibly the cheapest
  first slice).
- **Save format fidelity.** Raw SRAM from a cart vs. the emulator's `.sav`. The Phase 3 spike
  already pinned mGBA's artifact as `{saveDir}/{romBaseName}.sav`, raw 32 KB SRAM
  (`03-SPIKE-REPORT.md` probe 3) — encouraging, since a raw cart dump may be byte-comparable.
  Verify per system; GB/GBC/GBA differ, and RTC-bearing carts (Pokémon Crystal, Gold/Silver)
  carry clock state beyond plain SRAM.
- **Scope discipline.** This is hardware integration with physical-destruction risk. It
  should almost certainly be its own milestone, gated behind a hardware spike, not bolted
  onto a software phase.

## Explicitly Not Now

The owner flagged this as future thinking, not current scope: *"don't overly stress that
right now."* Nothing in v1.0 should be built for it. The one thing worth protecting today is
**optionality** — Phase 4 should avoid design choices that assume every save revision comes
from a credentialed Playstead client, because that assumption would be expensive to unwind.

## Scope Estimate

Unknown. Almost certainly its own milestone, dependent on a hardware-acquisition and
protocol spike before any planning is meaningful. Flash-cart (SD-based) support may be a
much cheaper first slice than direct cart reader/writer integration, and could validate the
save-continuity UX without any new hardware protocol work at all.
