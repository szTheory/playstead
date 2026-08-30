---
phase: 02-explainable-import-and-exact-export
plan: 10
subsystem: recognition
tags: [recognition, blobs, attention, gap-closure, dat-pack]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Playstead.Blobs.Store.read_leading/2 seam, resolve_format_bytes/2 (02-09) — header evidence reaching production classification and the 66,048-byte Formats read ceiling this plan's SNES HiROM+copier case depends on"
provides:
  - "Playstead.Blobs.Fingerprints.ensure_headerless/2 — the production writer for headerless-offset (D-20) blob_fingerprints rows, called from Playstead.Import.classify_recognized/8"
  - "Playstead.Blobs.Store.digest_from_offset/2 (behaviour + LocalDisk impl + Playstead.Blobs seam) — a storage-agnostic offset-digest read"
  - "A lazy fingerprint backfill inside Playstead.Recognition.reidentify/2 for blobs imported before this plan"
  - "Playstead.Recognition.ReferenceMatch.match/2 returning {:ambiguous, [entry]} — the detector for unrecognized{ambiguous}, previously absent"
  - "Recognition.reidentify/2's ambiguous branch: one appended evidence row, no promotion, one raised ambiguous_recognition attention item"
  - "LogiqxHandler CRC32 zero-padding so DAT digests compare equal to MultiHash-computed ones"
affects: [attention, catalogue, library-console]

actuals:
  tokens: 10956
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "digest_from_offset/2 as a storage-seam callback (not an object_path accessor) — keeps Playstead.Blobs.Store storage-agnostic per D-12; an object-store adapter answers it with a ranged GET"
    - "Second, bounded post-commit seek for headerless fingerprints instead of computing them inside the streaming write pass — keeps format knowledge out of the D-12 storage seam, at the cost of one extra small read only for a detected header (D-11's read-back verify already re-reads every committed object once)"
    - "Ambiguous evidence row written under the same provider_name as a normal reference match, so unmatched_candidates/1's existing already-matched exclusion settles an ambiguous blob until a human resolves it — no separate grouping/exclusion logic needed"
    - "limit: 2 (not 1, not unbounded) on the reference-entry digest lookup — enough to prove a conflict exists, capping how many rows an adversarial pack can make the server enumerate per digest"

key-files:
  created:
    - playstead-server/priv/repo/migrations/20260829010000_add_blob_fingerprints_unique_kind.exs
    - playstead-server/lib/playstead/blobs/fingerprints.ex
    - playstead-server/test/playstead/blobs/fingerprints_test.exs
    - playstead-server/test/playstead/recognition/ambiguous_recognition_test.exs
    - playstead-server/test/support/fixtures/dat/crc_short.dat
  modified:
    - playstead-server/lib/playstead/blobs.ex
    - playstead-server/lib/playstead/blobs/store.ex
    - playstead-server/lib/playstead/blobs/store/local_disk.ex
    - playstead-server/lib/playstead/import.ex
    - playstead-server/lib/playstead/recognition.ex
    - playstead-server/lib/playstead/recognition/reference_match.ex
    - playstead-server/lib/playstead/recognition/logiqx_handler.ex
    - playstead-server/test/playstead/import/session_worker_test.exs
    - playstead-server/test/playstead/recognition/reference_match_test.exs
    - playstead-server/test/playstead/recognition/dat_pack_importer_test.exs

key-decisions:
  - "An ambiguous reference-entry conflict raises its evidence row under ReferenceMatch's own provider_name (not a distinct name) — a second pack cannot un-conflict what the first two already disagreed on, and unmatched_candidates/1's existing exclusion (any blob already carrying a reference_match evidence row is skipped) then settles the blob quietly until a human resolves it, with no new grouping key or exclusion logic required. This is the 'settle it, don't re-raise on every later pack install' choice the plan's objective asked to be recorded."
  - "quiet_unrecognized_reason/2's reference_match_reason/1 (used only to pick the receipt's reason string for import-time new_asset vs unrecognized) also handles {:ambiguous, _} by returning \"ambiguous\" rather than crashing — an incidental but necessary consequence of widening match/2's return shape; it does not raise a second attention item on its own, since raise_attention/3 in import.ex is driven by the same classification map either way and Attention.raise_item/1's grouping-key upsert would collapse a coincident duplicate anyway."
  - "The unique index on {blob_id, kind} is additive-only and the fingerprint rows are derived data reproducible from stored bytes at any time — rated costly, not one-way, in the plan's own reversibility note; this SUMMARY does not relax that."

requirements-completed: [IMPT-03, IMPT-06]

coverage:
  - id: D1
    description: "A real headered NES or SNES import writes exactly one blob_fingerprints row for its applicable kind, idempotently under repeated identical imports"
    requirement: IMPT-03
    verification:
      - kind: unit
        ref: "test/playstead/blobs/fingerprints_test.exs#a headered NES import writes exactly one nes_header_skip16 row with correct digests"
        status: pass
      - kind: unit
        ref: "test/playstead/blobs/fingerprints_test.exs#a headered SNES LoROM import writes exactly one snes_copier_skip512 row"
        status: pass
      - kind: unit
        ref: "test/playstead/blobs/fingerprints_test.exs#a headered SNES HiROM import (the raised read ceiling case) writes the copier row"
        status: pass
      - kind: unit
        ref: "test/playstead/blobs/fingerprints_test.exs#re-importing identical bytes (CAS returns :existing) still leaves exactly one row"
        status: pass
    human_judgment: false
  - id: D2
    description: "A headerless NES/SNES file and random bytes write zero fingerprint rows"
    requirement: IMPT-03
    verification:
      - kind: unit
        ref: "test/playstead/blobs/fingerprints_test.exs#a headerless SNES file and a random-bytes file both write zero rows"
        status: pass
    human_judgment: false
  - id: D3
    description: "A DAT pack keyed to the headerless SHA-1 of a headered NES ROM matches it through Recognition.reidentify/2, including for a blob whose fingerprint row was never written (lazy backfill, no Oban worker)"
    requirement: IMPT-03
    verification:
      - kind: unit
        ref: "test/playstead/blobs/fingerprints_test.exs#a DAT pack keyed to the headerless SHA-1 matches a real headered NES import via reidentify/2"
        status: pass
      - kind: unit
        ref: "test/playstead/blobs/fingerprints_test.exs#a blob whose fingerprint row was never written is back-filled lazily by reidentify/2 with no Oban worker"
        status: pass
    human_judgment: false
  - id: D4
    description: "Two conflicting reference entries sharing one digest raise exactly one ambiguous_recognition attention item naming both candidates, never a silent pick; a duplicate row (same name + dat_pack_id) still resolves as a single match"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/recognition/ambiguous_recognition_test.exs#two conflicting entries sharing one digest raise exactly one ambiguous_recognition item naming both, and the asset stays unmatched"
        status: pass
      - kind: unit
        ref: "test/playstead/recognition/ambiguous_recognition_test.exs#two entries with the same SHA-1, name, and dat_pack_id promote to matched as a single match"
        status: pass
      - kind: unit
        ref: "test/playstead/recognition/reference_match_test.exs#match/2 returns {:ambiguous, entries} for a digest two conflicting entries claim"
        status: pass
    human_judgment: false
  - id: D5
    description: "The ambiguous evidence row is appended, never rewrites a prior row (D-18); a second reidentify/2 run over the same unresolved blob raises no duplicate item; the item clears through the existing correct_system and retain_as_custom resolutions"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/recognition/ambiguous_recognition_test.exs#the ambiguous branch appends exactly one new evidence row and modifies no pre-existing row"
        status: pass
      - kind: unit
        ref: "test/playstead/recognition/ambiguous_recognition_test.exs#running reidentify/2 a second time over the same unresolved blob does not create a second item"
        status: pass
      - kind: unit
        ref: "test/playstead/recognition/ambiguous_recognition_test.exs#resolving the ambiguous item through correct_system clears it"
        status: pass
      - kind: unit
        ref: "test/playstead/recognition/ambiguous_recognition_test.exs#resolving the ambiguous item through retain_as_custom clears it"
        status: pass
    human_judgment: false
  - id: D6
    description: "LogiqxHandler pads a DAT's CRC32 attribute to eight lowercase hex characters so it compares equal to a MultiHash-computed digest"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/recognition/dat_pack_importer_test.exs#a CRC32 attribute fewer than eight characters is padded to eight lowercase hex characters equal to what MultiHash computes for the same bytes"
        status: pass
    human_judgment: false

duration: ~1h40min
completed: 2026-08-30
status: complete
---

# Phase 02 Plan 10: Headerless Fingerprint Writer and Ambiguous-Match Detector Summary

Closed both remaining 02-VERIFICATION.md gaps: `Playstead.Blobs.Fingerprints.ensure_headerless/2` is now the production writer that puts headerless-offset digests into `blob_fingerprints` for a real NES/SNES import (with a lazy backfill for blobs imported earlier), and `Playstead.Recognition.ReferenceMatch.match/2` now returns `{:ambiguous, entries}` instead of silently picking whichever conflicting reference-pack row Postgres ordered first — `Recognition.reidentify/2`'s new branch turns that into exactly one `ambiguous_recognition` inbox item naming both candidates.

## Performance

- **Duration:** ~1h40min
- **Tasks:** 2 completed
- **Files:** 15 changed (5 created, 10 modified)

## Accomplishments

- `Playstead.Blobs.Store.digest_from_offset/2` (behaviour callback + `LocalDisk` implementation delegating to `MultiHash.digest_from_offset/2` + `Playstead.Blobs.digest_from_offset/2` seam entry): a storage-agnostic offset-digest read that keeps `Playstead.Blobs` the sole caller of the configured adapter, with no `object_path` leak across the seam.
- `Playstead.Blobs.Fingerprints.ensure_headerless/2`: maps a `Playstead.Formats.identify/2` result to at most one fingerprint kind (`nes_header_skip16`/16 for an NES signature match, `snes_copier_skip512`/512 for an SNES structure match whose evidence carries a true `copier_header`), computes the digest via the new seam, and writes it with `Repo.insert_all(..., on_conflict: :nothing, conflict_target: [:blob_id, :kind])` — idempotent by construction under the new unique index, and safe inside `Playstead.Import`'s ambient transaction. Called from `classify_recognized/8` once `blob_meta.blob_id` and `format_result` are both known, for both `import_single/4` and `complete_staged_file/4` (they both funnel through `classify_recognized/8`).
- A migration adds `unique_index(:blob_fingerprints, [:blob_id, :kind])`, leaving the existing per-blob index in place for `reidentify/2`'s lookup.
- `Playstead.Recognition.reidentify/2` lazily backfills a missing fingerprint (reading the blob's own leading bytes via `Playstead.Blobs.read_leading/1` from 02-09, then `Formats.identify/2`, then `ensure_headerless/2`) before matching — covering blobs imported before this plan with no Oban worker, no queue, no schedule.
- `Playstead.Recognition.ReferenceMatch.match/2` now returns `{:match, entry} | {:ambiguous, [entry]} | :no_match`. `lookup_by/2` fetches two rows per digest (not one, not unbounded); two rows identical in `name` and `dat_pack_id` resolve as a single match (a duplicate, not a conflict); two rows that differ in either field yield `{:ambiguous, [entry, entry]}` and stop the search at that digest rather than falling through to a weaker one.
- `Recognition.reidentify/2`'s new `{:ambiguous, entries}` branch appends one evidence row (`provider_name: "reference_match"`, `status: "ambiguous"`, `reference_name: nil`, `evidence: %{"candidates" => [%{"name" => _, "dat_pack_id" => _}, ...]}`) — never rewriting a prior row (D-18) — and raises exactly one `unrecognized{ambiguous}` attention item via `Attention.raise_item/1`, which `Attention.Derive.unrecognized_reason("ambiguous")` (already correct, untouched) maps to `:ambiguous_recognition`. It never calls `promote/4` and never emits a catalogue journal entry, since the asset set's state has not changed.
- `Playstead.Recognition.LogiqxHandler` now pads a parsed `crc` attribute to eight lowercase hex characters (`normalize_crc32/1`), fixing the mismatch where an unpadded DAT CRC32 (a leading zero stripped somewhere upstream) could never compare `==` to `MultiHash`'s always-zero-padded computed digest. MD5/SHA-1 stay downcased-only, since those are fixed-width in every real DAT.

## Task Commits

1. **Task 1: End-to-end headerless fingerprint — unique index, production writer on the import path, lazy backfill on reidentify** - `addb7a0` (feat)
2. **Task 2: Detect an ambiguous reference match and raise it as a human decision** - `e32508e` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `priv/repo/migrations/20260829010000_add_blob_fingerprints_unique_kind.exs` - unique index on `{blob_id, kind}`
- `lib/playstead/blobs/fingerprints.ex` - the production fingerprint writer (`ensure_headerless/2`)
- `lib/playstead/blobs.ex`, `lib/playstead/blobs/store.ex`, `lib/playstead/blobs/store/local_disk.ex` - `digest_from_offset/2` at each layer of the storage seam
- `lib/playstead/import.ex` - `ensure_headerless/2` called from `classify_recognized/8`; `reference_match_reason/1` handles `{:ambiguous, _}` without crashing
- `lib/playstead/recognition.ex` - lazy fingerprint backfill and the ambiguous branch (`raise_ambiguous/4`) in `reidentify/2`
- `lib/playstead/recognition/reference_match.ex` - `match/2`'s widened return shape, two-row lookup, duplicate-vs-conflict distinction
- `lib/playstead/recognition/logiqx_handler.ex` - `normalize_crc32/1` zero-padding
- `test/playstead/blobs/fingerprints_test.exs` - production writer + lazy backfill behaviour proofs (created)
- `test/playstead/recognition/ambiguous_recognition_test.exs` - ambiguous detector behaviour proofs (created)
- `test/support/fixtures/dat/crc_short.dat` - unpadded-CRC32 DAT fixture (created)
- `test/playstead/import/session_worker_test.exs` - added the missing `@impl true digest_from_offset/2` clause to the `InsufficientSpaceStore` test double (compile-time `--warnings-as-errors` requirement, same pattern 02-09 hit for `read_leading/2`)
- `test/playstead/recognition/reference_match_test.exs`, `test/playstead/recognition/dat_pack_importer_test.exs` - unit-level return-shape cases and the CRC32-padding case

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

**1. [Rule 1 - Bug] `import.ex`'s `reference_match_reason/1` handles `{:ambiguous, _entries}`**
- **Found during:** Task 2
- **Issue:** Widening `ReferenceMatch.match/2`'s return shape left one caller — `Playstead.Import.reference_match_reason/1`, used only to pick the receipt's quiet reason string (`nil` vs `"no_match"`) for an already-`new_asset` import — with an unhandled `case` clause. A real ambiguous digest hit at import time would raise a `CaseClauseError` and roll back the import transaction.
- **Fix:** Added a clause mapping `{:ambiguous, _entries}` to `"ambiguous"`, the same string the outcome vocabulary and `Attention.Derive.unrecognized_reason/1` already recognize. This is a narrow, necessary consequence of the plan's own widened return shape, not new scope: it prevents a crash and reuses vocabulary the plan already froze.
- **Files modified:** `lib/playstead/import.ex`
- **Verification:** `mix precommit` (758 tests, 0 failures) exercises this path via the existing `unrecognized_reason_for/5` test coverage with no regression.
- **Committed in:** `e32508e` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix).
**Impact:** Prevents a crash on a code path the plan's own return-shape widening made reachable; no scope creep — reuses the plan's own frozen `"ambiguous"` vocabulary.

## Known Stubs

None.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Both 02-VERIFICATION.md gaps this plan targeted are closed:

- Gap 2 (headerless fingerprint writer absent from `lib/`): closed. A real headered NES/SNES import now writes its fingerprint idempotently, and installing a headerless-keyed DAT pack now matches a real ROM through `reidentify/2`, including for blobs imported before this plan via the lazy backfill.
- Gap 1's second half (`unrecognized{ambiguous}` had no detector): closed. `ReferenceMatch.match/2` now surfaces a real conflict instead of silently picking a row; `reidentify/2` turns it into a live, resolvable `ambiguous_recognition` attention item.

`Playstead.Attention.Derive` and `Playstead.Import.Outcome`'s frozen vocabulary are unmodified (`git diff --stat` on both is empty). `Playstead.Blobs` remains the sole caller of the storage adapter; no filesystem path crosses the D-12 seam.

`cd playstead-server && mix precommit` (compile `--warnings-as-errors`, `deps.unlock --unused`, `format --check-formatted`, full test suite): **0 failures, 758 tests** (up from 745 after task 1, 738 before this plan), exit code 0.

Phase 02's requirement gate can now close `IMPT-03` and `IMPT-06` — both were held open pending this plan's gap closure. This is the last plan in Phase 02; a re-run of `/gsd-verify-work 02` should find no remaining gaps against 02-VERIFICATION.md.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-30*

## Self-Check: PASSED
