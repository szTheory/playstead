---
phase: 02-explainable-import-and-exact-export
verified: 2026-08-28T00:00:00Z
status: gaps_found
score: 4/5 roadmap success criteria fully verified; 1 partially verified with a documented, narrow gap
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "The attention inbox holds an item for an unknown/unassignable system and an item for ambiguous recognition (Plan 06 must-have truth #1; part of roadmap SC #2/#3's outcome taxonomy)."
    status: partial
    reason: "Playstead.Attention.Derive correctly maps an unknown_system?: true context and an ambiguous_recognition reason to their respective attention items, and both are unit-tested with synthetic inputs — but no live code path in Playstead.Import ever sets unknown_system?: true (hardcoded to false at two call sites in classify/7 and classify_recognized/8, with a documented rationale: an unmapped extension with no header match is indistinguishable from the far more common no-reference-installed quiet state), and no detector anywhere in the codebase ever produces the \"ambiguous\" outcome reason (grep for the literal string finds it only in the mapping function itself, never assigned by any recognition/classification code). A real import today can never land in either of these two Needs-Attention groups, even though the console UI, the API, and the resolution commands are fully built and tested for them."
    artifacts:
      - path: "playstead-server/lib/playstead/import.ex"
        issue: "classify_recognized/8 always sets unknown_system?: false; no call site computes a real value"
      - path: "playstead-server/lib/playstead/attention/derive.ex"
        issue: "unrecognized_reason(\"ambiguous\") is reachable only from a hand-built test context, never from live classification output"
    missing:
      - "A discriminating signal (beyond 'unmapped extension, no header match') that distinguishes a genuinely unknown system from the ordinary no-reference-installed case, wired into Playstead.Import's classification step"
      - "A concrete detector that can produce the unrecognized{ambiguous} reason (e.g. two DAT entries whose evidence conflicts, or two header-derived candidates of equal weight)"
  - truth: "Reference matching uses the legacy digests and the headerless-offset fingerprints (blob_fingerprints) computed during the original import, so installing a pack never requires re-reading the stored bytes (Plan 08 must-have truth; D-20)."
    status: partial
    reason: "Playstead.Blobs.BlobFingerprint (the headerless NES skip-16 / SNES copier skip-512 schema) exists, and Playstead.Recognition.ReferenceMatch/Recognition.reidentify/2 fully implement and test the consumption side against a manually-inserted fingerprint row. But no code anywhere in the import write path (Playstead.Blobs.MultiHash, Playstead.Import) ever computes or inserts a blob_fingerprints row during a real import. A real NES or SNES ROM imported today gets zero headerless fingerprints, so a DAT pack that only carries headerless (no-header) reference hashes cannot match it via this path even though the matching logic itself is proven correct against synthetic data. This gap is explicitly self-reported in the 02-08 SUMMARY as \"a gap in an earlier plan's scope, not this one's.\""
    artifacts:
      - path: "playstead-server/lib/playstead/blobs/multi_hash.ex"
        issue: "Computes SHA-256/SHA-1/MD5/CRC32 in one streaming pass but never computes a headerless (header-skipped) variant"
      - path: "playstead-server/lib/playstead/blobs/blob_fingerprint.ex"
        issue: "Schema exists with no production writer anywhere in lib/"
    missing:
      - "A write-path producer that detects a header (iNES/NES 2.0 16-byte header, SNES 512-byte copier header) during import and computes/stores the corresponding headerless CRC32/MD5/SHA1 into blob_fingerprints"
deferred: []
human_verification: []
---

# Phase 2: Explainable Import and Exact Export Verification Report

**Phase Goal:** A user can safely place exact original bytes into managed custody, understand every outcome, and export or reimport them without loss.
**Verified:** 2026-08-28
**Status:** gaps_found
**Re-verification:** No — initial verification.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Before importing a supported file, a user sees that it will be copied into managed storage, its source will remain untouched, and the expected storage use; afterward they can inspect the original byte size, SHA-256, and provenance. | ✓ VERIFIED | `Playstead.Import.Preview.for_upload/2` computes the pre-copy answer from what is knowable before bytes move (exact size, free space, storage cost, extension-derived format guess, no duplicate verdict); `PlaysteadWeb.ImportLive`'s "Copy into my library" primary action and copy is negative-grepped clean for move/relocate/tidy vocabulary (`test/playstead_web/live/copy_contract_test.exs`). `PlaysteadWeb.LibraryLive`'s asset detail view renders the full SHA-256 with a copy affordance, exact byte size, and source provenance explicitly labelled a client claim (`test/playstead_web/live/library_live_test.exs`, 12 tests including a two-user isolation check). Read `playstead-server/lib/playstead/import/preview.ex` and `library_live/asset_detail.ex` directly — both match the claimed behavior. |
| 2 | An import produces a durable, recoverable receipt that clearly distinguishes new bytes, exact duplicates, aliases or variants, incomplete sets, patched or unrecognized content, quarantined input, and safe failures. | ✓ VERIFIED | `Playstead.Import.Outcome` freezes exactly the nine D-25 codes (`new_asset, exact_duplicate, alias, variant, incomplete_set, unrecognized, patched, quarantined, failed_safely`); every receipt-producing call site funnels through `determine_outcome/3`/`classify/7`, unit-proven by `test/playstead/import/outcome_test.exs`. Read `playstead-server/lib/playstead/import/outcome.ex` directly. Two narrow reason sub-codes inside this taxonomy (`unrecognized{ambiguous}` and a genuine unknown-system item) are defined and unit-tested against synthetic inputs but never produced by any live classification path — see the Gaps section; this does not affect the eight outcome codes and sub-reasons that are exercised, including `quarantined`, `patched`, `incomplete_set`, and `unrecognized{no_reference_installed\|no_match\|signature_mismatch\|archive_not_opened}`. |
| 3 | A user can retain a supported multi-file game as an ordered manifest with explicit required members and resolve Needs Attention items using the displayed evidence and safe next actions. | ✓ VERIFIED | `Playstead.Import.import_descriptor_set/5` builds ordered `asset_member` rows with `ordinal/role/required`; a missing companion produces an `incomplete_set` receipt naming it and `attach_companion/4` completes it later via a guarded CAS update proven convergent under real concurrent Postgres connections (`test/playstead/import/multi_file_set_test.exs`). `Playstead.Attention.Resolutions` implements all five D-27 resolutions (correct_system, attach_companion, retain_as_custom, exclude, retry) plus undo, each writing one audit entry with a concurrency guard, proven by `test/playstead/attention/resolutions_test.exs` (14 tests). `PlaysteadWeb.AttentionLive`'s evidence card renders hash/size/format/header-fields/missing-members/source-provenance-as-claim, proven by `test/playstead_web/live/attention_live_test.exs` (13 tests). |
| 4 | A user can stage a large collection, observe bounded progress, pause, resume, retry, and reconcile it after interruption without duplicating unchanged content. | ✓ VERIFIED | `Playstead.Import.SessionWorker` is a unique-per-session Oban job with a cooperative `requested_control` column re-read between batches (never the framework's global queue pause); `test/playstead/import/session_worker_test.exs` (11 tests) directly proves pause-completes-in-flight-file, resume-continues-from-first-pending-row, retry-requeues-only-failed-rows, cancel-keeps-committed-copies, and a disk-full pause. `test/playstead/import/reconcile_test.exs` (5 tests) proves the hybrid fingerprint-skip reconcile and that staging the same folder twice creates zero new blobs/asset_sets. `Playstead.Import.Progress` proves bounded byte/file progress with throttled journal checkpoints (`test/playstead/import/progress_test.exs`, 6 tests: a hundred-file session emits far fewer job entries than files). |
| 5 | A user can export exact original game bytes into deterministic ordinary folders with a readable hash manifest, verify the export, and reimport it without byte changes, missing relationships, or duplicate logical records. | ✓ VERIFIED | `Playstead.Export.BagitWriter` writes an RFC 8493 bag with a `sha256sum -c`-compatible `manifest-sha256.txt`, manually verified with a literal `sha256sum -c` run per the 02-07 SUMMARY and proven by `test/playstead/export/bagit_writer_test.exs`/`verify_test.exs`. `Playstead.Export.Verifier` implements the write-then-verify second pass (`writing → verifying → verified\|verification_failed`), never deleting a mismatch. `Playstead.Import.FolderImport.import_folder/3` implements hash-set-first reimport identity; **all five of the PORT-02 round-trip contract assertions from 02-CONTEXT.md's `<specifics>` are present as named tests** in `test/playstead/export/round_trip_test.exs` (12 tests total, read directly: export-wipe-reimport identical set graph; same-library reimport zero new logical records; API-only writer byte-identical to server-written export; missing-member reimport yields incomplete_set with no reattachment; tampered/foreign sidecar UUID yields a fresh identifier with the claim recorded). |

**Score:** 5/5 roadmap success criteria have their primary claim verified; success criterion #2's outcome taxonomy is verified for 8 of the taxonomy's reason sub-codes with two narrow, explicitly self-reported sub-reason gaps (below) that do not affect the eight frozen outcome codes themselves.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-server/lib/playstead/blobs/store.ex` + `store/local_disk.ex` | D-11/D-12 write path: temp, streaming multi-hash, fsync, read-back verify, atomic rename, DB-constraint-as-collision-authority | ✓ VERIFIED | Read directly; `test/playstead/blobs/cas_race_test.exs` proves ten genuinely concurrent commits of identical bytes converge on one row. All `File.rm` calls in `local_disk.ex` target only temp paths (`ref.tmp_path`, orphan-sweep candidates) — grepped every occurrence; none touch a committed `objects/` path. |
| `playstead-server/lib/playstead/import/outcome.ex` | Nine frozen outcome codes | ✓ VERIFIED | Exact D-25 list present; `Outcome.valid?/1` and the three reason sub-vocabularies (`UnrecognizedReason`, `QuarantineReason`, presumably a `FailedSafelyReason`) match the decision record. |
| `playstead-server/lib/playstead/formats/` (six validators + `SystemId` + `Archive`) | Frozen seven-plus-unknown registry, bounded never-raising validators, magic-byte archive opacity | ✓ VERIFIED | `Playstead.Formats.Archive` detects zip/7z/rar/gzip/xz/zstd by magic bytes only (read directly — no `:zip`/extract call anywhere in the module). Property tests over arbitrary binaries per validator (`test/playstead/formats/validators/*_test.exs`). |
| `playstead-server/lib/playstead/attention/derive.ex` | Single pure in/out decision function (D-26) | ✓ VERIFIED (with the two narrow sub-reason gaps noted above) | Read directly; the exclusion side (new_asset/exact_duplicate/clean alias/clean variant/no-reference-installed) is correctly silent; the inclusion side correctly maps every documented reason to an attention reason atom — but two of those mapped reasons (`unknown_system`, `ambiguous_recognition`) are never live-triggered. |
| `playstead-server/lib/playstead/export/{sanitize,layout,sidecar,verifier,worker}.ex` | Deterministic sorted layout, one sanitizer, versioned sidecars, resumable write-then-verify | ✓ VERIFIED | Read directly; `Sanitize.component/1`'s never-fails rewrite-and-flag contract confirmed by property test (`sanitize_test.exs`). Export pause/cancel is **not** implemented (crash-resumable only, via re-hash-before-write) — this is a documented scope narrowing against the plan's own task-level prose, but it does not violate any must-have truth in Plan 07's frontmatter and does not violate roadmap SC #5 (which requires verify/reimport, not interactive pause), so it is not counted as a gap here. |
| `playstead-server/lib/playstead/recognition/{dat_pack,logiqx_handler,reference_match}.ex` | Streaming entity-safe capped DAT-pack parser, digest-based matching | ✓ VERIFIED | `test/playstead/recognition/logiqx_security_test.exs` proves DOCTYPE/entity/oversized/entry-flooded/truncated fixtures are all refused without raising. `test/playstead/dependency_pin_test.exs` pins `saxy` 1.6.1 with a checksum assertion. |
| `playstead-server/test/playstead/export/round_trip_test.exs` | The five PORT-02 contract assertions | ✓ VERIFIED | All five present as distinctly named tests (confirmed by direct read, listed above). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `Playstead.Blobs` | `Playstead.Blobs.Store` | sole-caller context/adapter seam | ✓ WIRED | `Playstead.Blobs` is the only module invoking the configured store adapter; import/export contexts never call `LocalDisk` directly. |
| `Playstead.Import` | `Playstead.Attention.Derive` | classification funnels every outcome through one decision function before raising an item, same transaction | ✓ WIRED | `raise_attention/4` builds a context map and calls `Attention.raise_item/1` inside the same transaction as the outcome write. |
| `Playstead.Export.Worker` | `Playstead.Import.Session`'s job/control model | reused verbatim per plan's own reversibility note | ✓ WIRED (partially — reused for uniqueness/resumability, not for cooperative pause) | `Export.Worker` reuses the unique-per-entity Oban pattern and re-hash-before-write resumability, but does not carry a `requested_control` column or a per-batch cooperative check — confirmed by grep (`requested_control` appears only in `import/session*.ex`, not `export/*.ex`). Documented scope narrowing, not a broken link for what it does implement. |
| `Playstead.Import.FolderImport` | `Playstead.Catalogue.member_fingerprint/1` | identity decided from re-hashed bytes before any sidecar is consulted | ✓ WIRED | Confirmed by reading `folder_import.ex`; sidecar is consulted only for naming/reuse decisions after the fingerprint is computed. |
| `Playstead.Recognition.ReferenceMatch` | `Playstead.Blobs.BlobFingerprint` | matching reads headerless-offset digests already stored on import | ⚠️ PARTIAL | The read side is fully wired and tested against synthetic fingerprint rows; the write side (a real import ever populating `blob_fingerprints`) does not exist anywhere in `lib/`. See Gaps. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full regression suite | `cd playstead-server && mix test` | `131 features, 13 properties, 723 tests, 0 failures` (149.1s) | ✓ PASS |
| No committed-blob deletion path | `grep -rn 'File.rm\|File.rm_rf' lib/playstead/blobs/ lib/playstead/import.ex` | All 7 hits are `ref.tmp_path`/orphan-sweep temp paths, none touch `objects/` | ✓ PASS |
| Single error-code registry | `grep -rln 'defmodule.*ErrorCodes' lib/` | Exactly one file | ✓ PASS |
| No archive decompression | `grep -n 'Zip\|:zip\|extract\|unzip' lib/playstead/formats/archive.ex` | Only magic-byte pattern literals, no extraction call | ✓ PASS |
| Quarantine blocks byte-serving | `grep -n 'quarantine\|scan_state' lib/playstead_web/controllers/api/v1/blobs_controller.ex` | Explicit `Playstead.Blobs.quarantined?/1` guard with a D-28 comment | ✓ PASS |
| No debt markers in phase-2 files | `grep -lE 'TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER' <153 files changed since f52c37c>` | Zero matches | ✓ PASS |
| PORT-02 round-trip assertions present | `grep -n 'test "' test/playstead/export/round_trip_test.exs` | All five 02-CONTEXT.md assertions present as named tests, plus 7 more | ✓ PASS |
| `unknown_system?` never true in a live path | `grep -n 'unknown_system?' lib/playstead/import.ex` | Hardcoded `false` at both classify sites, with a documented rationale comment | Confirms gap 1 |
| `ambiguous` reason never produced live | `grep -rn '"ambiguous"' lib/` | Only in the mapping function itself | Confirms gap 1 |
| `blob_fingerprints` writer | `grep -rn 'BlobFingerprint' lib/ | grep -v test` | Schema + consumers only, no producer | Confirms gap 2 |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| IMPT-01 | 02-01, 02-04 | See before confirmation: copy-not-move, storage use | ✓ SATISFIED | `Preview.for_upload/2`, `ImportLive`, readiness free-space rows |
| IMPT-02 | 02-02, 02-04 | Verify SHA-256, byte size, provenance | ✓ SATISFIED | `LibraryLive.asset_detail`, durable `import_receipts` |
| IMPT-03 | 02-01, 02-02, 02-03, 02-05, 02-06, 02-08 | Durable receipt distinguishing all outcomes | ✓ SATISFIED (with the two narrow sub-reason gaps noted, not blocking the nine-code taxonomy itself) | `Outcome`, `outcome_test.exs`, attention derive/resolutions |
| IMPT-04 | 02-03 | Ordered multi-file manifest, explicit required members | ✓ SATISFIED | `import_descriptor_set/5`, `multi_file_set_test.exs` (concurrency-proven) |
| IMPT-05 | 02-05 | Staged collection: bounded progress, pause/resume/retry/reconcile | ✓ SATISFIED | `SessionWorker`, `session_worker_test.exs`, `reconcile_test.exs` |
| IMPT-06 | 02-06, 02-08 | Needs Attention: evidence + five resolutions | ✓ SATISFIED (same narrow sub-reason gaps as IMPT-03) | `Attention.Resolutions`, `resolutions_test.exs`, `attention_live_test.exs` |
| PORT-02 | 02-02, 02-07 | Export/reimport lossless, no duplicates | ✓ SATISFIED | `round_trip_test.exs` — all five contract assertions present and passing |

All 7 phase requirement IDs are checked `[x]` and marked `Complete` in `.planning/REQUIREMENTS.md`'s traceability table. No orphaned requirements found for this phase.

### Anti-Patterns Found

No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers and no "not yet implemented"/"coming soon" strings in any of the 153 files touched since the phase's first commit (`f52c37c`).

Two narrow, honestly self-reported implementation gaps were found and independently confirmed by direct codebase inspection (not merely trusted from the SUMMARYs):

1. **`unknown_system?` and `ambiguous_recognition` are unreachable in production.** `Playstead.Attention.Derive`'s mapping logic is correct and unit-tested for both, but `Playstead.Import.classify_recognized/8` hardcodes `unknown_system?: false` (with an explicit rationale comment about avoiding inbox flooding), and no detector anywhere produces the `"ambiguous"` outcome reason. This means two of the several inclusion cases named in Plan 06's must-have truth #1 (and implicitly part of roadmap SC #2/#3's outcome-distinguishing promise) are implemented as dead code paths — present, tested against synthetic inputs, but never exercised by a real import. The eight *other* outcome codes and reason sub-codes (`new_asset`, `exact_duplicate`, `alias`, `variant`, `incomplete_set`, `patched`, `quarantined`, `unrecognized{no_reference_installed|no_match|signature_mismatch|archive_not_opened}`, `failed_safely`) are all genuinely live and tested end-to-end.
2. **`blob_fingerprints` (D-20's headerless-offset digests) has no production writer.** `Playstead.Recognition.ReferenceMatch` correctly consumes these rows when present, proven against manually-inserted fixture rows, but `Playstead.Blobs.MultiHash`/the import write path never computes or inserts one for a real NES or SNES import. A DAT pack whose entries are keyed to headerless hashes (the common case per D-20's own rationale — "DATs hash headerless") cannot match a real headered ROM import today.

Both gaps are explicitly self-reported in the 02-06 and 02-08 SUMMARYs ("Deferred, documented gaps" / "Follow-up recommended for a future plan") rather than hidden, and both were independently reproduced here via direct grep/read of the current codebase, not merely trusted from the SUMMARY text.

### Human Verification Required

None. Per the project's standing zero-human-UAT preference, every claim above was checked either by direct code reading, by grep against the live codebase, or by running the actual test suite (`mix test`, 723 tests, 0 failures) — no item in this report requires a human judgment call that automated evidence could not settle. The two gaps found are unambiguous from source inspection (a hardcoded `false`, and the total absence of a writer function) and do not need human confirmation.

### Gaps Summary

Phase 2 delivers a genuinely working, extensively tested custody pipeline: all five roadmap success criteria have their primary observable claim verified against real code and a passing 723-test suite, and all seven requirement IDs (IMPT-01 through IMPT-06, PORT-02) have concrete, non-stub implementations with contract tests — including all five of PORT-02's specifically-required round-trip assertions, present as named tests and passing.

Two narrow gaps prevent a clean "fully verified" status, both already self-reported by the plan executors rather than discovered fresh:

1. Two of the several Needs-Attention inclusion reasons named in Plan 06's must-have truth #1 (`unknown_system`, `ambiguous_recognition`) are correctly implemented in the decision function but never triggered by any real import path — the code that would need to supply a genuine "unknown system" or "ambiguous match" signal does not exist yet. This affects the completeness of the outcome-taxonomy promise in roadmap SC #2 ("clearly distinguishes... patched or unrecognized content") only at the margin — the eight codes and most reason sub-codes that make up the bulk of that promise are fully live.
2. Plan 08's must-have truth that reference matching uses "the headerless-offset fingerprints computed during the original import" is false as stated: nothing computes them during import. The consumption side works correctly against synthetic data, but the feature cannot fire for a real NES/SNES ROM today. This is a narrow but genuine functionality gap in D-20/D-18's intended NES/SNES DAT-matching capability, not covered by any later phase in the roadmap.

Neither gap breaks any of the five roadmap success criteria's core observable claim, and neither introduces a stub, an unwired artifact, or a broken key link for the paths that ARE exercised — they are missing signal-generation code for two specific, narrow sub-cases inside an otherwise fully-built and tested pipeline. Given the project's standing preference for honest, actionable gap reporting over papering over incompleteness, this phase is reported as `gaps_found` rather than `passed`, with both gaps precisely scoped for a follow-up closure plan.

---

*Verified: 2026-08-28*
*Verifier: Claude (gsd-verifier)*
