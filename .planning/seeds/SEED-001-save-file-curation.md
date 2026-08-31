---
id: SEED-001
status: dormant
planted: 2026-08-30
planted_during: v1.0 / Phase 3 (mac-offline-play-vertical-slice) execution
trigger_when: any milestone or phase that designs launcher/client UX (library, curation, or save-sync surfaces) — surface before locking that UI spec
scope: unknown
---

# SEED-001: Save-file curation as a first-class UX concept

## Why This Matters

Owner-stated intent (2026-08-30, mid-Phase-3): a user's **save-file collection may matter more to them than their game collection**. Saves represent invested play, and a valued save is one of the strongest "I'll come back and play this" signals the product can observe. Today curation covers five game-centric nouns (Favorites, Collections, Queue, Continue dismissals, Play sessions — D-07..D-10); saves are treated as sync payload, not as something a user browses, organizes, or treasures.

## When to Surface

**Trigger:** whenever we design or revise the UI/UX of launchers that connect to Playstead (Mac client, web console, future clients) — especially any work touching the library/curation surface or persistent-save handling. Also relevant to the next milestone's requirements gathering (`/gsd-new-milestone`).

Questions to answer when this surfaces:
- Should saves be a curated noun alongside the existing five (browse, favorite, annotate, pin saves)?
- Does save curation change the status ladder / card anatomy locked in 03-UI-SPEC.md?
- Is "has treasured saves" a Continue/Recent ranking signal?

## Scope Estimate

**Unknown** — likely touches server curation model, sync entity kinds, and every client's library UI; estimate when triggered.

## Breadcrumbs

- `.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` — locked Phase 3 design contract this would extend
- `playstead-server/lib/playstead/curation.ex` — the five curation nouns this would join (D-07..D-10)
- `.planning/phases/03-mac-offline-play-vertical-slice/03-SPIKE-REPORT.md` — D-03 save-flush cadence evidence (saves are already a custody focus)
- PROJECT.md core value: "a locally available game **and its progress** remain … fully under the user's control"

## Notes

Captured via one-shot seed capture from an owner remark during Phase 3 execution; enrich with `/gsd-capture --seed --enrich SEED-001` if scope firms up.
