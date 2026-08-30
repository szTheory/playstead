---
phase: 02-explainable-import-and-exact-export
verified: 2026-08-30T00:00:00Z
status: passed
score: 5/5 roadmap success criteria verified; both previously-open gaps closed
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: "5/5 roadmap success criteria have their primary claim verified; success criterion #2's outcome taxonomy verified for 8/10 reason sub-codes with 2 narrow gaps"
  gaps_closed:
    - "unknown_system? was hardcoded false and unrecognized{ambiguous} had no producer — closed by plan 02-09 (unknown_system?) and plan 02-10 (ambiguous detector)"
    - "blob_fingerprints had no production writer — closed by plan 02-10 (Blobs.Fingerprints.ensure_headerless/2)"
  gaps_remaining: []
  regressions: []
deferred: []
human_verification: []
---

# Phase 2: Explainable Import and Exact Export Verification Report

**Phase Goal:** A user can safely place exact original bytes into managed custody, understand every outcome, and export or reimport them without loss.
**Verified:** 2026-08-30
**Status:** passed
**Re-verification:** Yes — after gap-closure plans 02-09 and 02-10 executed.

## Goal Achievement

### Gap Closure Verification (the two items this re-verification exists to check)

#### Gap 1: `unknown_system?` hardcoded false / `unrecognized{ambiguous}` had no producer

**Root cause claimed:** no production import entry point ever supplied `:format_bytes`, so header evidence never reached classification, and `ReferenceMatch.lookup_by/2` capped every digest query at `limit: 1`, silently picking whichever row Postgres ordered first.

Verified directly against the code (not the SUMMARY's narrative):

- `playstead-server/lib/playstead/blobs/store.ex:64` — `read_leading/2` callback exists on the `Store` behaviour.
- `playstead-server/lib/playstead/blobs/store/local_disk.ex:342` — `read_leading/2` implemented, bounded raw read.
- `playstead-server/lib/playstead/blobs.ex:83-85` — `Playstead.Blobs.read_leading/2` seam entry, sole caller of the adapter.
- `playstead-server/lib/playstead/import.ex:120-133` — `resolve_format_bytes/2` falls back to `read_committed_format_bytes/1` → `Blobs.read_leading/1` when no caller-supplied bytes are present; degrades to `nil` (never fails the import) on `{:error, :not_found}`.
- Both `import_single/4` (line 75) and `complete_staged_file/4` (line 804) call `resolve_format_bytes/2` before their transaction opens.
- `PlaysteadWeb.Api.V1.ImportsController:77` calls `Import.import_single/3` with no `:format_bytes` opt — inherits the resolution.
- `Playstead.Import.SessionWorker:184,217` calls `Import.complete_staged_file/3` with no `:format_bytes` opt — inherits the resolution.
- `Playstead.Import.import_bag_member/3` (private, line 1136) calls `import_single/3` with no `:format_bytes` opt (confirmed by direct read of lines 1136-1150) — inherits the resolution via delegation, as claimed.
- **All three named production entry points are confirmed reachable, not just claimed.**
- `playstead-server/lib/playstead/formats.ex:24` — `@max_read 66_048` (raised from 65,536), clearing the SNES HiROM copier probe's `512 + 0xFFC0 + 0x20 = 66,016`-byte requirement.
- `playstead-server/lib/playstead/import.ex:252,257-258` — `unknown_system?: unknown_system?(extension_guess, format_result)` is a computed expression (`nil` extension guess AND `{:unknown, :none, _}` format result); the only remaining literal `false` is the quarantine branch (line 166), which carries a comment naming D-28 (no evidence to judge a quarantined blob's system) — exactly the documented, deliberate exception.
- `playstead-server/lib/playstead/recognition.ex:67-68` — `packs_installed?/1` exists; `import.ex:265-303` shows `unrecognized_reason_for/5`'s catch-all clause producing `"no_reference_installed"` (no pack) or `"no_match"` (pack installed, no match) — both are real, live producers, not hardcoded.
- `playstead-server/lib/playstead/recognition/reference_match.ex` — `grep -n 'limit:'` shows `limit: 2` at all three digest lookups (SHA-1, MD5, CRC32); the previous `limit: 1` is gone. `match/2`'s `@spec` (line 75) names `{:match, entry} | {:ambiguous, [entry]} | :no_match`. `find_entry/1` (lines 114-122) distinguishes a genuine conflict (`{:ambiguous, [a, b]}`) from a duplicate row (`same_logical_entry?/2` collapses to `{:match, a}`).
- `grep -rn '"ambiguous"' lib/` shows a real producer at `import.ex:317` and `recognition.ex:288,299` (evidence status/reason), in addition to the mapping clause in `attention/derive.ex:54` — the exact spot-check the prior verification ran, now returning a producer instead of only the mapping function.
- `git diff --stat lib/playstead/attention/derive.ex lib/playstead/import/outcome.ex` against the phase-2 baseline is empty per both SUMMARYs' own verification steps, and direct read confirms `Attention.Derive` and the frozen `Outcome` vocabulary are untouched — the decision function and vocabulary were correct all along; only the missing signals were supplied.

**Verdict: Gap 1 CLOSED.** Both the `unknown_system?` flag and the `ambiguous` reason now have live, reachable producers wired to all three real production entry points, not just to unit-test harnesses.

#### Gap 2: `blob_fingerprints` had no production writer

Verified directly against the code:

- `playstead-server/lib/playstead/blobs/fingerprints.ex` — `Playstead.Blobs.Fingerprints.ensure_headerless/2` exists, fully substantive (not a stub): maps a format result to at most one kind (`nes_header_skip16`/16, `snes_copier_skip512`/512), computes digests via `Blobs.digest_from_offset/2`, writes with `Repo.insert_all(..., on_conflict: :nothing, conflict_target: [:blob_id, :kind])`, and returns `0` (never raises/fails the import) when no kind applies or the digest read errors.
- `playstead-server/lib/playstead/import.ex:199` — `_fingerprint_count = Fingerprints.ensure_headerless(blob_meta.blob_id, format_result)` is called from `classify_recognized/8`, which is reached by both `import_single/4` and `complete_staged_file/4` (and therefore `import_bag_member/3` by delegation) — the same three production entry points verified for Gap 1.
- `playstead-server/lib/playstead/blobs/store.ex:93` / `store/local_disk.ex:362` / `blobs.ex:90-95` — `digest_from_offset/2` exists at all three seam layers, delegating to the already-existing `MultiHash.digest_from_offset/2`; `object_path` does not leak across the seam (`grep -rn 'object_path' lib/ | grep -v 'store/local_disk.ex'` returns nothing).
- `playstead-server/priv/repo/migrations/20260829010000_add_blob_fingerprints_unique_kind.exs` exists and is applied (`mix ecto.migrations` shows it `up`); `create unique_index(:blob_fingerprints, [:blob_id, :kind])` makes the `on_conflict: :nothing` insert idempotent under a repeated import of identical bytes.
- `playstead-server/lib/playstead/recognition.ex:212` — the lazy backfill inside `reidentify/2` calls `Fingerprints.ensure_headerless/2` for a blob with no rows yet, before loading fingerprints for matching — covering blobs imported before this plan with no Oban worker (`grep -rn 'Fingerprints' lib/ | grep -i worker` returns nothing).

**Verdict: Gap 2 CLOSED.** `blob_fingerprints` now has a real production writer reachable from every production import entry point, plus a lazy backfill for pre-existing blobs.

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Before importing a supported file, a user sees copy-not-move and storage cost; afterward inspects SHA-256, byte size, provenance. | ✓ VERIFIED (unchanged from prior verification) | `Playstead.Import.Preview.for_upload/2`, `ImportLive` copy-contract test, `LibraryLive.asset_detail`. Not re-examined in depth this pass — no plan 02-09/02-10 file touches this surface, and the full suite (including `test/playstead_web/live/library_live_test.exs`, which 02-09 did touch for outcome-string churn) is green. |
| 2 | An import produces a durable, recoverable receipt that clearly distinguishes new bytes, exact duplicates, aliases/variants, incomplete sets, patched/unrecognized content, quarantined input, and safe failures — including the full sub-reason taxonomy. | ✓ VERIFIED (previously partial — now fully closed) | `Playstead.Import.Outcome`'s nine frozen codes unchanged (`git diff --stat` empty). All prior sub-reasons still produced; the two previously-dead sub-reasons (`unknown_system`, `ambiguous`) now have live producers per the Gap Closure section above. |
| 3 | A user can retain a supported multi-file game as an ordered manifest and resolve Needs Attention items using displayed evidence and safe next actions. | ✓ VERIFIED (unchanged) | Untouched by 02-09/02-10; full suite green including `multi_file_set_test.exs`, `resolutions_test.exs`, `attention_live_test.exs`. |
| 4 | A user can stage a large collection, observe bounded progress, pause, resume, retry, and reconcile without duplicating unchanged content. | ✓ VERIFIED (unchanged) | Untouched by 02-09/02-10 except `session_worker_test.exs`'s test-double gaining the two new `@impl true` store callbacks (`read_leading/2`, `digest_from_offset/2`) — a compile-time requirement, not a behavior change; `session_worker_test.exs` still passes. |
| 5 | A user can export exact original game bytes, verify the export, and reimport without byte changes, missing relationships, or duplicate logical records. | ✓ VERIFIED (unchanged) | Untouched by 02-09/02-10; `round_trip_test.exs`'s five PORT-02 assertions unaffected — `import_bag_member/3` (the reimport path) inherits format-bytes resolution but its identity logic (hash-set-first) is untouched. Full suite green. |

**Score:** 5/5 roadmap success criteria fully verified. Success criterion #2's outcome taxonomy is now verified in full — both previously-dead sub-reasons have live producers reachable from production entry points.

### Required Artifacts (new/changed by gap-closure plans)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-server/lib/playstead/blobs/store.ex` + `store/local_disk.ex` + `blobs.ex` | `read_leading/2` and `digest_from_offset/2` callbacks, bounded, read-only, never decompressing | ✓ VERIFIED | Read directly; both callbacks present at all three seam layers; `Playstead.Blobs` remains sole caller of the configured adapter for these new callbacks. |
| `playstead-server/lib/playstead/blobs/fingerprints.ex` | Production writer for headerless fingerprints | ✓ VERIFIED | Read in full — substantive, idempotent, never fails an import on error. |
| `playstead-server/lib/playstead/import.ex` | `unknown_system?` computed; `resolve_format_bytes/2`; `unrecognized_reason_for/5`; `Fingerprints.ensure_headerless/2` call site | ✓ VERIFIED | All confirmed by direct read at cited line numbers. |
| `playstead-server/lib/playstead/recognition.ex` | `packs_installed?/1`; lazy fingerprint backfill; `{:ambiguous, entries}` branch in `reidentify/2` | ✓ VERIFIED | All present, read directly. |
| `playstead-server/lib/playstead/recognition/reference_match.ex` | `match/2` returns `{:ambiguous, [entry]}`; `limit: 1` removed | ✓ VERIFIED | `limit: 2` at all three lookups; `limit: 1` count is `0`. |
| `playstead-server/priv/repo/migrations/20260829010000_add_blob_fingerprints_unique_kind.exs` | Unique index on `{blob_id, kind}` | ✓ VERIFIED | Exists, applied (`up` in `mix ecto.migrations`). |
| `playstead-server/test/playstead/blobs/{read_leading,fingerprints}_test.exs`, `test/playstead/recognition/ambiguous_recognition_test.exs`, `test/playstead/attention/unknown_system_test.exs`, `test/playstead/formats/identify_test.exs` | Behavior proofs for both gap closures | ✓ VERIFIED | All five files exist; 27 tests across them, all passing when run in isolation. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `PlaysteadWeb.Api.V1.ImportsController` | `Playstead.Formats.identify/2` | blob-resolved format bytes | ✓ WIRED | Confirmed: `imports_controller.ex:77` → `import_single/3` (no `:format_bytes`) → `resolve_format_bytes/2` → `Blobs.read_leading/1` → `identify_format/2`. |
| `Playstead.Import.SessionWorker` | `Playstead.Formats.identify/2` | blob-resolved format bytes | ✓ WIRED | Confirmed: `session_worker.ex:184,217` → `complete_staged_file/3` (no `:format_bytes`) → same resolution path. |
| `Playstead.Import.import_bag_member/3` | `Playstead.Formats.identify/2` | blob-resolved format bytes | ✓ WIRED | Confirmed by direct read of `import.ex:1136-1150`: calls `import_single/3` with no `:format_bytes` opt, inheriting the resolution. |
| `Playstead.Import.classify_recognized/8` | `Playstead.Attention.Derive.attention_reason/1` | computed `unknown_system?` | ✓ WIRED | `import.ex:252` computes the flag from real evidence; `raise_attention/4` passes it into the same transaction as before. |
| `Playstead.Import.classify_recognized/8` | `Playstead.Blobs.Fingerprints.ensure_headerless/2` | called once blob id + format result known | ✓ WIRED | `import.ex:199`, inside the same transaction, before recognition runs. |
| `Playstead.Recognition.ReferenceMatch.match/2` | `Playstead.Blobs.BlobFingerprint` (write side) | production writer on the import path | ✓ WIRED (previously PARTIAL — now closed) | Write side confirmed via `import.ex:199` → `Fingerprints.ensure_headerless/2` → `Blobs.digest_from_offset/2` → `Repo.insert_all`. |
| `Playstead.Recognition.ReferenceMatch.match/2` | `Playstead.Recognition.reidentify/2` → `Playstead.Attention.raise_item/1` | `{:ambiguous, entries}` path | ✓ WIRED | `recognition.ex` ambiguous branch appends evidence, refuses promotion, raises an item with both candidate names. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full regression suite (run once, per constraint) | `cd playstead-server && mix precommit` | `131 features, 13 properties, 758 tests, 0 failures` (165.7s), exit code 0 | ✓ PASS |
| Gap-closure test files in isolation | `mix test test/playstead/blobs/fingerprints_test.exs test/playstead/recognition/ambiguous_recognition_test.exs test/playstead/attention/unknown_system_test.exs test/playstead/blobs/read_leading_test.exs test/playstead/formats/identify_test.exs` | `27 tests, 0 failures` | ✓ PASS |
| `limit: 1` removed from `reference_match.ex` | `grep -c 'limit: 1' lib/playstead/recognition/reference_match.ex` | `0` | ✓ PASS |
| `ambiguous` has a real producer, not only the mapping clause | `grep -rn '"ambiguous"' lib/` | producers at `import.ex:317`, `recognition.ex:288,299`, plus the (unmodified) mapping clause | ✓ PASS |
| `blob_fingerprints` writer exists | `grep -rn 'BlobFingerprint\|Fingerprints' lib/ \| grep -v test` | insert site in `blobs/fingerprints.ex`, called from `import.ex:199` | ✓ PASS |
| `import_bag_member/3` reachability | direct read of `import.ex:1136-1150` | delegates to `import_single/3` with no `:format_bytes` opt | ✓ PASS |
| Migration applied | `mix ecto.migrations` | `20260829010000 add_blob_fingerprints_unique_kind` shows `up` | ✓ PASS |
| `Playstead.Attention.Derive` / `Outcome` untouched | `git diff --stat` against both files (per both SUMMARYs, confirmed by direct read) | empty | ✓ PASS |
| No debt markers in gap-closure files | `grep -rnE 'TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER'` across all 9 changed lib files | no matches | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| IMPT-01 | 02-01, 02-04 | Before-confirmation copy-not-move, storage use | ✓ SATISFIED | Unchanged; not touched by gap closure. |
| IMPT-02 | 02-02, 02-04 | Verify SHA-256, byte size, provenance | ✓ SATISFIED | Unchanged. |
| IMPT-03 | 02-01–02-06, 02-08, 02-09, 02-10 | Durable receipt distinguishing all outcomes, including full sub-reason taxonomy | ✓ SATISFIED (gap closed) | `unknown_system` and `ambiguous` now have live producers; nine frozen outcome codes unchanged. |
| IMPT-04 | 02-03 | Ordered multi-file manifest, explicit required members | ✓ SATISFIED | Unchanged. |
| IMPT-05 | 02-05 | Staged collection: bounded progress, pause/resume/retry/reconcile | ✓ SATISFIED | Unchanged (test-double gained two new `@impl true` clauses for compile-time compliance only). |
| IMPT-06 | 02-03, 02-09, 02-10 | Resolve Needs Attention items via evidence and safe actions | ✓ SATISFIED (gap closed) | Both quiet reasons and the ambiguous-match item are now reachable in production; existing resolutions (`correct_system`, `retain_as_custom`) proven to clear the new `ambiguous_recognition` item. |
| PORT-02 | 02-07 | Verify export, reimport without loss | ✓ SATISFIED | Unchanged; `import_bag_member/3`'s identity logic (hash-set-first) is untouched by the format-bytes resolution it now inherits. |

**Orphaned requirements check:** REQUIREMENTS.md maps IMPT-01 through IMPT-06 and PORT-02 to Phase 2; all seven appear in this phase's plans' `requirements` frontmatter fields (across 02-01 through 02-10). No orphaned requirements.

### Anti-Patterns Found

None. `grep -rnE 'TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER'` across all files modified by plans 02-09 and 02-10 returns zero matches. No stub return patterns, no empty handlers, no hardcoded empty data flowing to receipts/inbox items.

### Regression Check (previously-passed items, quick sanity per re-verification optimization)

- Nine frozen outcome codes: unchanged (`git diff --stat lib/playstead/import/outcome.ex` empty).
- `Playstead.Attention.Derive`: unchanged (`git diff --stat` empty), confirmed by direct read — the mapping function was already correct; only the missing signals were supplied.
- `Playstead.Blobs` sole-adapter-caller invariant: still holds for the new callbacks (`read_leading/2`, `digest_from_offset/2`) — both introduced only in `blobs.ex`/`store.ex`/`store/local_disk.ex`. (Pre-existing direct `LocalDisk.blob_path/delete/capacity_bytes` calls in `hashing_writer.ex`, `preview.ex`, `orphan_sweeper.ex` predate this phase's gap-closure plans and are outside their scope — not a regression introduced here.)
- Export/reimport round-trip (PORT-02): full suite green, no `round_trip_test.exs` changes in either gap-closure plan.
- Full test suite: 758 tests, 0 failures, up from 723 at the prior verification (738 after 02-09, 758 after 02-10 — both SUMMARYs' claimed counts match the actual `mix precommit` run performed independently in this verification).

### Gaps Summary

None remaining. Both gaps recorded in the prior `02-VERIFICATION.md` are closed and independently confirmed against the codebase (not taken on the SUMMARYs' word):

1. `unknown_system?` is now computed live from real evidence at all three production import entry points (`ImportsController`, `SessionWorker`, `import_bag_member/3`), and `unrecognized{ambiguous}` now has a real detector (`ReferenceMatch.match/2`'s widened return shape) reachable from `Recognition.reidentify/2`.
2. `blob_fingerprints` now has a production writer (`Blobs.Fingerprints.ensure_headerless/2`) called from every production import entry point via `classify_recognized/8`, plus a lazy backfill for blobs imported before this plan.

---

*Verified: 2026-08-30*
*Verifier: Claude (gsd-verifier)*
