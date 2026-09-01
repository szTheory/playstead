---
id: SEED-010
status: dormant
planted: 2026-09-01
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when relevant
scope: unknown
related: SEED-002 (physical cartridge save continuity), Phase 4 (Persistent Save Continuity)
---

# SEED-010: Archive childhood saves from physical memory cards and accessories

## Why This Matters

_To be filled in. Run `$gsd-capture --seed --enrich SEED-010` to add context._

The owner wants Playstead eventually to import saves from original physical
media such as PlayStation memory cards, Nintendo 64 Controller Paks, and
similar console accessories. These may contain decades-old personal progress
that deserves the same understandable custody, history, backup, and export
guarantees as newer emulator-generated saves.

A future discovery effort should inventory currently obtainable readers and
adapters, their supported platforms and protocols, open-source tooling, format
coverage, reliability, and maintenance status. The first responsibility is
archival: make a read-only acquisition, preserve the exact original card image
or bytes, record reader/tool/format provenance, verify repeated reads when
possible, and only then derive individual game-save records or compatible
emulator copies. Conversion must never replace or mutate the source archive.

The model needs to distinguish a whole-card image from a parsed save, identify
region/title/slot uncertainty honestly, retain unknown blocks, and avoid
claiming portability until a specific system, format, emulator, and version
combination is proven. Any later write-back feature is higher-risk and belongs
under SEED-002's mandatory read-and-archive-first safety rules.

## When to Surface

**Trigger:** when relevant

This seed will surface during `$gsd-new-milestone` when the milestone scope matches.

## Scope Estimate

**Unknown** — run `$gsd-capture --seed --enrich SEED-010` to estimate effort.

## Breadcrumbs

- `.planning/seeds/SEED-002-physical-cartridge-save-continuity.md` — related
  physical/emulated save boundary, hardware landscape, provenance, and
  destructive write-back safeguards
- `.planning/ROADMAP.md` — Phase 4 introduces immutable save revisions,
  restoration, export, and conflict preservation
- `.planning/discovery/TECHNICAL-RISKS.md` — memory cards and battery saves are
  distinct persistent-save types requiring explicit adapter contracts
- `.planning/PROJECT.md` — exact-byte custody, documented export, and no silent
  save conflict or source mutation are core product constraints
- `playstead-mac/docs/SUPPORT-MATRIX.md` — current support is deliberately
  limited to one adapter-proven `.sav` contract

## Notes

Captured via one-shot seed capture during Phase 03.5. Keep the first slice
archival and read-only. Candidate systems and readers require a current
hardware/tooling investigation before any implementation plan is selected.
