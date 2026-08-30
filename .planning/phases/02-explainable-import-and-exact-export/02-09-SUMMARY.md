---
phase: 02-explainable-import-and-exact-export
plan: 09
subsystem: import
tags: [recognition, attention, blobs, formats, gap-closure]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Playstead.Blobs.Store CAS seam, Playstead.Formats validators, Playstead.Recognition.HeaderEvidence, Playstead.Attention.Derive, DatPack/ReferenceEntry/ReferenceMatch (02-01 through 02-08)"
provides:
  - "Playstead.Blobs.Store.read_leading/2 (behaviour + LocalDisk impl + Playstead.Blobs seam): a bounded, read-only leading-bytes read of a committed blob"
  - "Format bytes resolved automatically at all three production import entries (ImportsController, SessionWorker, import_bag_member/3) when no caller supplies them — header evidence now reaches classification for every real import"
  - "Playstead.Formats' read ceiling raised to 66,048 bytes so an SNES HiROM image with a 512-byte copier header is recognizable"
  - "Playstead.Import.classify_recognized/8 computes unknown_system? live from the two D-16 evidence axes instead of hardcoding false"
  - "Playstead.Recognition.packs_installed?/1 and a live producer for both D-26 quiet unrecognized reasons (no_reference_installed, no_match)"
affects: [attention, recognition, catalogue, library-console]

actuals:
  tokens: 9996
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "One defaulting point inside Playstead.Import (resolve_format_bytes/2) rather than editing every call site — callers that already hold bytes keep their explicit override; every other caller inherits the resolution for free, including future call sites"
    - "packs_installed?/1 as a single cheap existence query, keeping the overwhelmingly common no-pack path a single indexed lookup rather than a per-system coverage query the schema cannot answer"

key-files:
  created:
    - playstead-server/test/playstead/blobs/read_leading_test.exs
    - playstead-server/test/playstead/formats/identify_test.exs
    - playstead-server/test/playstead/attention/unknown_system_test.exs
  modified:
    - playstead-server/lib/playstead/blobs.ex
    - playstead-server/lib/playstead/blobs/store.ex
    - playstead-server/lib/playstead/blobs/store/local_disk.ex
    - playstead-server/lib/playstead/formats.ex
    - playstead-server/lib/playstead/import.ex
    - playstead-server/lib/playstead/recognition.ex
    - playstead-server/test/playstead/recognition/header_evidence_test.exs
    - playstead-server/test/playstead/attention/quarantine_test.exs
    - playstead-server/test/playstead/import/tracer_round_trip_test.exs
    - playstead-server/test/playstead/import/session_worker_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/imports_controller_test.exs
    - playstead-server/test/playstead_web/live/import_live_test.exs
    - playstead-server/test/playstead_web/live/library_live_test.exs

key-decisions:
  - "One private helper (resolve_format_bytes/2) inside import.ex resolves format_bytes for both import_single/4 and complete_staged_file/4 rather than editing three call sites, per the plan's own reasoning: it covers import_bag_member/3 for free (delegates to import_single/4) and cannot be defeated by a future fourth call site forgetting the option"
  - "Playstead.Formats' @max_read raised to 66,048 (not exactly 66,016) — the smallest round ceiling that clears the SNES copier probe's 512 + 0xFFC0 + 0x20 requirement"
  - "no_reference_installed vs no_match decided on whether the user has any pack installed at all, not per-system coverage — neither DatPack nor ReferenceEntry carries a system column, so per-system coverage is not derivable from the schema"
  - "No new grouping key for unknown_system — Playstead.Import.attention_grouping_key/1 and Attention.upsert_item/1's existing {user_id, grouping_key, reason} conflict target already collapse a session's unknown-system files into one item"

requirements-completed: [IMPT-03, IMPT-06]

coverage:
  - id: D1
    description: "Every production import entry (API upload, staged session, bag-member reimport) identifies format from the committed blob's own bytes with no caller cooperation"
    requirement: IMPT-03
    verification:
      - kind: unit
        ref: "test/playstead/recognition/header_evidence_test.exs#production import entries identify format from the committed blob (02-09 gap closure)"
        status: pass
    human_judgment: false
  - id: D2
    description: "An SNES HiROM image with a 512-byte copier header is recognized now that the read ceiling admits it"
    requirement: IMPT-03
    verification:
      - kind: unit
        ref: "test/playstead/formats/identify_test.exs"
        status: pass
    human_judgment: false
  - id: D3
    description: "A file with no extension claim and no header claim lands exactly one grouped unknown_system attention item; grouping collapses within a session/single-upload correctly"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/attention/unknown_system_test.exs"
        status: pass
    human_judgment: false
  - id: D4
    description: "Both D-26 quiet unrecognized reasons (no_reference_installed, no_match) have live producers and remain excluded from the attention inbox"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/attention/unknown_system_test.exs"
        status: pass
    human_judgment: false
  - id: D5
    description: "Playstead.Blobs.read_leading/2 is a bounded, read-only leading-bytes read that never mutates a committed object"
    requirement: IMPT-03
    verification:
      - kind: unit
        ref: "test/playstead/blobs/read_leading_test.exs"
        status: pass
    human_judgment: false

duration: ~2h
completed: 2026-08-30
status: complete
---

# Phase 02 Plan 09: Wire Header Evidence Into Production, Live unknown_system and Quiet Reasons Summary

Closed the shared root cause behind both 02-VERIFICATION.md gaps — no production import call site ever supplied `:format_bytes`, so header evidence never reached classification — then made `unknown_system?` live and gave both quiet `unrecognized` reasons real producers.

## Performance

- **Duration:** ~2h
- **Tasks:** 2 completed
- **Files:** 16 changed (3 created, 13 modified)
- **Commits:** 2 task commits (`cd8f80f`, `fda7538`)

## Accomplishments

- `Playstead.Blobs.Store.read_leading/2` (behaviour callback + `LocalDisk` implementation + `Playstead.Blobs` seam): a bounded, read-only leading-bytes read of a committed blob, keeping `Playstead.Blobs` the sole caller of the configured adapter.
- `Playstead.Import` resolves `format_bytes` from the just-committed blob whenever a caller supplies none, in one shared private helper used by both `import_single/4` and `complete_staged_file/4`. All three production entries — `PlaysteadWeb.Api.V1.ImportsController`, `Playstead.Import.SessionWorker`, and `Playstead.Import.import_bag_member/3` (which delegates to `import_single/4`) — now identify format from real bytes for the first time. A missing object degrades to `nil` rather than failing the import.
- `Playstead.Formats`' `@max_read` raised from 65,536 to 66,048 bytes, so an SNES HiROM image carrying a 512-byte copier header (needing 512 + 0xFFC0 + 0x20 = 66,016 bytes) is now recognizable — a live bug fix and a precondition for plan 02-10's SNES copier fingerprint.
- `Playstead.Import.classify_recognized/8` computes `unknown_system?` from the two D-16 evidence axes (extension guess, header/format result) instead of hardcoding `false`. A container result (archive) never qualifies — it keeps its own reason and its own grouped item. The quarantine branch keeps its literal `false` with a comment naming D-28 (no evidence to judge a quarantined blob's system).
- `Playstead.Recognition.packs_installed?/1`: a single existence query over `dat_packs` for a user. `Playstead.Import.unrecognized_reason_for/5` (renamed from `/3`) now decides between D-26's two quiet reasons using it: `no_reference_installed` when the user has no pack installed at all, `no_match` when a pack is installed but `Playstead.Recognition.ReferenceMatch.match/2` finds nothing against the blob's stored digests and headerless-offset fingerprints. Both existing higher-priority clauses (`archive_not_opened`, `signature_mismatch`) are unchanged and still win first.
- No new grouping key was needed: `attention_grouping_key/1` plus `Attention.upsert_item/1`'s existing `{user_id, grouping_key, reason}` conflict target already collapse a session's unknown-system files into one counted item and give a single API upload its own item.

## Task Commits

1. **Task 1: Wire header evidence into production — bounded blob read through the store seam, format bytes at every import entry** - `cd8f80f` (feat)
2. **Task 2: Make unknown_system live and give the two quiet unrecognized reasons real producers** - `fda7538` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `lib/playstead/blobs/store.ex` - `read_leading/2` callback, documented bounded/read-only/never-decompressing
- `lib/playstead/blobs/store/local_disk.ex` - `read_leading/2` implementation: bounded raw read, EOF-as-success
- `lib/playstead/blobs.ex` - `read_leading/2` public seam, `@default_leading_bytes` 66,048
- `lib/playstead/formats.ex` - `@max_read` raised to 66,048 with a comment recording the SNES copier reach
- `lib/playstead/import.ex` - `resolve_format_bytes/2`, computed `unknown_system?`, `unrecognized_reason_for/5`, `quiet_unrecognized_reason/2`
- `lib/playstead/recognition.ex` - `packs_installed?/1`
- `test/playstead/blobs/read_leading_test.exs` - bounded-read proof (short object, long object, unknown digest, object untouched)
- `test/playstead/formats/identify_test.exs` - SNES HiROM copier recognition at the new ceiling
- `test/playstead/attention/unknown_system_test.exs` - one item, grouped item (count 3), two-item non-collapse, two quiet-reason cases, archive-not-unknown-system case
- `test/playstead/recognition/header_evidence_test.exs` - named tests proving header evidence reaches classification with no `:format_bytes` option, at both `import_single/4` and `complete_staged_file/4`
- `test/playstead/attention/quarantine_test.exs`, `test/playstead/import/tracer_round_trip_test.exs`, `test/playstead/import/session_worker_test.exs`, `test/playstead_web/controllers/api/v1/imports_controller_test.exs`, `test/playstead_web/live/import_live_test.exs`, `test/playstead_web/live/library_live_test.exs` - updated assertions for the expected blast radius (below)

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

None beyond what the plan's own objective explicitly anticipated and pre-authorized — see "Expected Suite Churn" below, which is not a deviation but the plan's own documented consequence of giving `no_reference_installed` a real producer.

## Expected Suite Churn (pre-documented in the plan's objective)

Giving `no_reference_installed` a producer moved every receipt that previously reported `new_asset` with no reason to `unrecognized{no_reference_installed}` wherever the importing user has no reference pack installed and the outcome was otherwise `new_asset`. Six test files needed their expected outcome values updated to match this newly-correct behavior (not weakened — each assertion still proves what it originally proved, with the corrected expected value):

- `test/playstead/attention/quarantine_test.exs` — two tests switched their fixtures from unmapped-extension random bytes (which would now trip `unknown_system` too) to real GBA header bytes, so the "produces zero attention items" assertion still tests the D-26 quiet-exclusion path it was written for.
- `test/playstead/recognition/header_evidence_test.exs` — "not classified as a failure" now asserts `outcome != "failed_safely"` rather than `== "new_asset"`, preserving the test's actual intent.
- `test/playstead/import/tracer_round_trip_test.exs` — a reimport-into-empty-library outcome assertion updated to `unrecognized`/`no_reference_installed`; the identity claim the test proves (set/member restoration) is unaffected and asserted separately.
- `test/playstead_web/controllers/api/v1/imports_controller_test.exs` — three `"new_asset"` response assertions updated to `"unrecognized"` for uploads from users with no pack installed.
- `test/playstead_web/live/import_live_test.exs` — two tests updated: one switched to real GBA bytes and asserts the `unrecognized` outcome code and "Not yet identified" copy; the reload test asserts the same quiet copy survives a page reload.
- `test/playstead_web/live/library_live_test.exs` — "receipt whose asset has since been identified" now asserts `"At import: unrecognized"` (was `"At import: new_asset"`), since the receipt captured at import genuinely has no pack installed at that point; the "now: recognized" half (proving the later reference match) is unchanged.

Also fixed a pre-existing test-double gap: `test/playstead/import/session_worker_test.exs`'s `InsufficientSpaceStore` fake didn't implement the new `read_leading/2` callback, which `mix compile --warnings-as-errors` would have failed on — added the missing `@impl true` clause returning `{:error, :not_found}` (a safe default `resolve_format_bytes/2` already degrades gracefully from).

**Total deviations:** 0 unplanned. **Impact:** All test changes are the plan's own explicitly pre-authorized blast radius, applied deliberately per-assertion rather than by weakening or deleting any test.

## Known Stubs

None.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Both 02-VERIFICATION.md gap-1 concerns (unreachable `unknown_system?`, unreachable `ambiguous`/quiet-reason production) related to this plan's scope are closed: `unknown_system?` is now computed from real evidence and both quiet `unrecognized` reasons have live producers. The shared root cause plan 02-10 depends on — header evidence never reaching production classification — is closed, and the SNES HiROM copier recognition fix unblocks plan 02-10's SNES copier fingerprint work directly.

`mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format --check-formatted, full test suite): **0 failures, 738 tests** (up from 723 before this plan; 726 preserved for-task-1 test-count parity was exceeded by task 2's own additions), exit code 0.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-30*

## Self-Check: PASSED
