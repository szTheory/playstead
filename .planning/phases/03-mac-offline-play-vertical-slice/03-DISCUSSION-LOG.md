# Phase 3: Mac Offline Play Vertical Slice - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-30
**Phase:** 3-mac-offline-play-vertical-slice
**Areas discussed:** Adapter spike & first emulator, Curation ownership & sync, Library experience without artwork, Cache & download semantics

---

## Mode

The owner selected all four presented gray areas and requested the fan-out research mode used in Phases 1–2: for each area, multi-lens research (security, product/UX, platform, licensing, distributed-systems, accessibility, creative direction) with online prior-art study and adversarial passes, synthesized into one-shot recommendations approved as a set. Four `gsd-advisor-researcher` agents ran in parallel; full option tables and sources live in `discussion-research/A…D-*.md`.

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Adapter spike & first emulator | Candidate matrix, distribution posture, bundling, spike design, BIOS | ✓ |
| Curation ownership & sync | Server vs client ownership, protocol shape, conflicts, parity | ✓ |
| Library experience without artwork | Visual identity, hierarchy, navigation, empty states, motion | ✓ |
| Cache & download semantics | Transfer mechanics, cache layout, capacity/pin/evict, queue, verification | ✓ |

## Owner ruling: save-flush requirement

| Option | Description | Selected |
|--------|-------------|----------|
| Periodic flush required (Recommended) | Save probe passes only with an observable periodic/on-demand on-disk flush during play; RetroArch+mGBA wins if mGBA standalone cannot show one | ✓ |
| At-exit flush acceptable | mGBA stays primary; save contract documents durability at clean exit only | |
| Let the spike decide empirically | Pick whichever candidate demonstrates the most observable flush | |

**User's choice:** Periodic flush required
**Notes:** Research flagged this as an owner ruling, not an engineering call — mGBA standalone mmaps its `.sav` and flushes deterministically only at clean exit, leaving a crash-window loss that conflicts with priority #2 (reliable play and save continuity).

## Set approval

| Option | Description | Selected |
|--------|-------------|----------|
| Approve as a set | Lock all recommendations into 03-CONTEXT.md | ✓ |
| Request changes | Adjust specific decisions first | |

**User's choice:** Approve as a set (with the periodic-flush ruling applied)

## Claude's Discretion

SwiftUI architecture and persistence library; Phoenix schema/route naming and fractional-index mechanics; exact glyphs/palette/type scale (UI-SPEC pass refines); spike homebrew title (must write SRAM) and SPIKE-REPORT format; quota/reclaim microcopy; play-event batching.

## Deferred Ideas

Auto-evict/LRU (v2); periodic cache scrub (Phase 5); controller on-screen keyboard; stored smart collections (v2); open BIOS declarations; Sparkle auto-update; background/chunked/tus transfer (TRAN-01 v2); metadata/artwork providers (META-01 v2); household curation sharing (v2); second client/browser play (separate spikes); playtime analytics (v2).
