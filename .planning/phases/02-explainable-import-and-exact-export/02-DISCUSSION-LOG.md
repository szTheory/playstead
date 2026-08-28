# Phase 2: Explainable Import and Exact Export - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-28
**Phase:** 2-explainable-import-and-exact-export
**Areas discussed:** Import surfaces & staging, Formats & recognition, Receipts & Needs Attention, Export & reimport identity

**Method:** The owner selected all four gray areas and asked that every decision point be fanned out across stakeholder lenses (security, product, technical/Elixir, design, ops, preservation domain) with online prior-art research and an adversarial pass, then synthesized into one-shot recommendations. Four parallel `gsd-advisor-researcher` agents produced one report per area (preserved in `discussion-research/`). The orchestrator reconciled cross-area conflicts and put the twelve points where lenses disagreed to the owner in three AskUserQuestion rounds. The owner accepted the recommended option in all twelve.

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Import surfaces & staging | Ingestion surfaces with no Mac client, job shape, reconcile strategy | ✓ |
| Formats & recognition | v1 allowlist, IMPT-04 format, alias/variant/patched without a DAT | ✓ |
| Receipts & Needs Attention | Receipt granularity, resolution semantics, quarantine retention | ✓ |
| Export & reimport identity | Export target, layout, sidecar, verify, reimport identity | ✓ |

**User's choice:** All four, plus the fan-out/research/adversarial-synthesis method instruction.

---

## Cross-area reconciliations (orchestrator, before owner rounds)

1. Verify-after-write conflict (A-08 "no re-read" vs C-06 "re-read every file") → escalated to owner (round 1).
2. B's extra outcome codes (`archive_not_opened`, `header_check_failed`, `kept_as_is`) folded into C's nine codes as `unrecognized{reason}`; archives and signature mismatches are never quarantined; quarantine reserved for policy failures.
3. Pause mechanism: A-04 (session flag checked between files, job exits, resume re-enqueues) chosen over E6's `{:snooze}`; export reuses import's model.
4. `GET /api/v1/blobs/:sha256` Range support scoped to what PORT-02's API-written-export contract test needs; resumable ranges proven in Phase 3.
5. Microcopy fix: research C's alias line ("different bytes, same release") contradicted the frozen alias definition (same bytes, different name); CONTEXT.md carries the corrected line.

---

## Round 1

| Question | Options | Selected |
|---|---|---|
| DAT-pack import in Phase 2? | In, as last droppable plan / Out (header evidence only) | In ✓ |
| Export folder shape | BagIt-compliant / Flat tree + SHA256SUMS | BagIt ✓ |
| Archives before the security gate | Accept opaque with preflight warning / Refuse at preflight | Accept opaque ✓ |
| Re-read and re-hash after write | Default-on with config knob / Trust streaming hash + fsync | Default-on ✓ |

## Round 2

| Question | Options | Selected |
|---|---|---|
| Reclaim path for soft-excluded bytes | No reclaim in Phase 2 / Minimal sudo-gated hard reclaim | No reclaim ✓ |
| Routing of `unrecognized{no_reference_installed}` | Library with quiet badge / One grouped inbox item per session | Library badge ✓ |
| Reuse sidecar asset-set UUID on reimport | Reuse if globally unused / Always mint fresh | Reuse ✓ |
| Inbox mount shape | Read-only bind mount `./inbox:/app/inbox:ro` / Named volume | Bind mount ✓ |

## Round 3

| Question | Options | Selected |
|---|---|---|
| Cancel semantics for staged import | Keep copied files, stop the rest / Offer "stop and remove" | Keep ✓ |
| Browser upload ceiling | 4 GiB browser / 8 GiB API vs 8 GiB everywhere | Split ✓ |
| Format allowlist breadth | Seven ids (gba gb gbc nes md snes psx) / GBA + PSX only | Seven ✓ |
| Whole-library export of quarantined/unrecognized | Include under `_quarantined/` `_unsorted/` / Exclude by default | Include ✓ |

**Done gate:** "I'm ready for context" (no further gray areas requested).

---

## Claude's Discretion

- Table/column names, Ecto schema layout, migration ordering, LiveView component structure.
- Chunk sizes, `Task.async_stream` timeouts, Oban Lifeline tuning, PubSub topics.
- System-slug display names, `_unsorted`/`_quarantined` folder names, console IA (UI-SPEC pass).
- `precheck` batch vs single; No-Intro grammar coverage; BagIt profile JSON and README prose.

## Deferred Ideas

See the `<deferred>` section of `02-CONTEXT.md` (import/staging, formats/recognition, receipts/inbox, export groups).
