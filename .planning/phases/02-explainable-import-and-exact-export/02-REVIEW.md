---
phase: 02-explainable-import-and-exact-export
reviewed: 2026-08-30T00:00:00Z
depth: standard
files_reviewed: 24
files_reviewed_list:
  - playstead-server/lib/playstead/blobs.ex
  - playstead-server/lib/playstead/blobs/fingerprints.ex
  - playstead-server/lib/playstead/blobs/store.ex
  - playstead-server/lib/playstead/blobs/store/local_disk.ex
  - playstead-server/lib/playstead/formats.ex
  - playstead-server/lib/playstead/import.ex
  - playstead-server/lib/playstead/recognition.ex
  - playstead-server/lib/playstead/recognition/logiqx_handler.ex
  - playstead-server/lib/playstead/recognition/reference_match.ex
  - playstead-server/priv/repo/migrations/20260829010000_add_blob_fingerprints_unique_kind.exs
  - playstead-server/test/playstead/attention/quarantine_test.exs
  - playstead-server/test/playstead/attention/unknown_system_test.exs
  - playstead-server/test/playstead/blobs/fingerprints_test.exs
  - playstead-server/test/playstead/blobs/read_leading_test.exs
  - playstead-server/test/playstead/formats/identify_test.exs
  - playstead-server/test/playstead/import/session_worker_test.exs
  - playstead-server/test/playstead/import/tracer_round_trip_test.exs
  - playstead-server/test/playstead/recognition/ambiguous_recognition_test.exs
  - playstead-server/test/playstead/recognition/dat_pack_importer_test.exs
  - playstead-server/test/playstead/recognition/header_evidence_test.exs
  - playstead-server/test/playstead/recognition/reference_match_test.exs
  - playstead-server/test/playstead_web/controllers/api/v1/imports_controller_test.exs
  - playstead-server/test/playstead_web/live/import_live_test.exs
  - playstead-server/test/playstead_web/live/library_live_test.exs
  - playstead-server/test/support/fixtures/dat/crc_short.dat
findings:
  critical: 1
  warning: 1
  info: 1
  total: 3
status: issues_found
---

# Phase 02: Code Review Report — Gap-Closure Diff (02-09, 02-10)

**Reviewed:** 2026-08-30
**Depth:** standard
**Files Reviewed:** 24
**Status:** issues_found

**Scope note:** this pass covers only the gap-closure diff `cd8f80f^..HEAD` (plan 02-09: wiring header evidence into production import and making `unknown_system` live; plan 02-10: the headerless blob-fingerprint writer and the ambiguous reference-match detector). It supersedes the prior 02-REVIEW.md report for these files; the rest of phase 02 was reviewed separately and is out of scope here.

## Summary

The gap-closure work is well-tested for each path in isolation — `Fingerprints.ensure_headerless/2`, `ReferenceMatch.match/2`'s `{:ambiguous, _}` return, and `Recognition.reidentify/2`'s ambiguous-item handling all have direct, well-targeted tests, and I traced the CRC32-padding fix, the raised `@max_read` ceiling, and the transactional/idempotency reasoning in the store adapter and found them sound. The one real defect found is a cross-path interaction the tests never exercise: `Import.classify_recognized/8`'s new "ambiguous" quiet-reason branch (added in 02-09/02-10) can raise an `ambiguous_recognition` attention item for a blob at **import** time through a different code path than `Recognition.reidentify/2`'s ambiguous handler, and the two paths use different grouping keys and different evidence bookkeeping — so the same underlying digest conflict can end up with two separate open attention items instead of the "exactly one" invariant the reidentify docstring explicitly promises. See CR-01.

## Critical Issues

### CR-01: Import-time ambiguous match and reidentify-time ambiguous match can raise two separate attention items for the same blob

**File:** `playstead-server/lib/playstead/import.ex:293-321` (`quiet_unrecognized_reason/2`, `reference_match_reason/1`) and `playstead-server/lib/playstead/recognition.ex:167-186, 273-307` (`reidentify/2`, `raise_ambiguous/4`)

**Issue:** `Recognition.reidentify/2`'s ambiguous branch is explicitly designed, and tested, to raise **exactly one** `ambiguous_recognition` attention item per blob, ever — the docstring states: "a second pack cannot un-conflict what the first two packs already disagreed on, and re-raising the same item on every later pack install would be noise." This guarantee is enforced by two things working together: (1) `raise_ambiguous/4` inserts an `Evidence` row under `ReferenceMatch.name()` ("reference_match"), and (2) `unmatched_candidates/1` excludes any blob that already carries a `reference_match`-provider evidence row from future `reidentify/2` passes.

The new import-time path added in this gap closure (`Import.classify_recognized/8` → `unrecognized_reason_for/5` → `quiet_unrecognized_reason/2` → `reference_match_reason/1`) also calls `ReferenceMatch.match/2` directly, and when it returns `{:ambiguous, _}`, sets the receipt's outcome to `:unrecognized` with reason `"ambiguous"`. `raise_attention/4` then derives `:ambiguous_recognition` via `Playstead.Attention.Derive` and raises an item — but with `grouping_key: attention_grouping_key(source_file)` (session- or single-file-scoped), **not** `"ambiguous_recognition:#{blob.id}"` as `raise_ambiguous/4` uses. Critically, this import-time path never inserts a `reference_match`-provider `Evidence` row (only the `HeaderEvidence` provider's row is written via `recognize_and_record/3`), so the blob is **not** excluded from `unmatched_candidates/1` afterward.

Concrete sequence that reproduces the bug:
1. User has two conflicting reference packs installed, both claiming the same SHA-1.
2. User imports a new ROM whose bytes hash to that SHA-1. `import_single/4` classifies it as `:unrecognized`/`"ambiguous"` and raises attention item A with grouping key `"single:<source_file_id>"` (or the session id). No `reference_match` evidence row is written.
3. Later, the user installs a third, unrelated pack. Per D-18, installing a pack triggers `Recognition.reidentify/2`, which re-scans the library. Because no `reference_match` evidence row exists for this blob, it is still an "unmatched candidate." `ReferenceMatch.match/2` is still ambiguous (the same two original entries still conflict), so `raise_ambiguous/4` fires again — this time with grouping key `"ambiguous_recognition:<blob_id>"`, a **different** key from item A's, so the `on_conflict` upsert in `Attention.raise_item/1` (`conflict_target: [:user_id, :grouping_key, :reason]`) does not collapse the two, producing item B alongside the still-open item A.

The user now sees two separate open "More than one possible match" inbox items for what is a single underlying digest conflict — directly contradicting the stated "exactly one" invariant and D-31's "calm, neutral number" goal. There is no test anywhere in the diff (or the wider test suite, confirmed by grep) exercising the import-time ambiguous branch at all, so this interaction is currently unverified.

**Fix:** Route the import-time ambiguous determination through the same `raise_ambiguous/4` bookkeeping `Recognition.reidentify/2` uses (writing the `reference_match`-provider evidence row and using the `"ambiguous_recognition:#{blob_id}"` grouping key), or have `classify_recognized/8` call a single shared helper for "ambiguous at any point" so both call sites converge on one attention item and one evidence-exclusion signal. At minimum, add a regression test that imports a new blob while two conflicting packs are already installed and asserts `Attention.count/1 == 1` both immediately after import and after a subsequent `Recognition.reidentify/2` call.

## Warnings

### WR-01: `LocalDisk.read_leading/2` collapses every `File.open` failure reason into `:not_found`, masking operational faults as "content identification degraded"

**File:** `playstead-server/lib/playstead/blobs/store/local_disk.ex:341-359`

**Issue:** `read_leading/2` is new in this diff and is the sole production path `Import.resolve_format_bytes/2` uses to fetch bytes for format identification on every import that doesn't pass `opts[:format_bytes]` explicitly (i.e. every real production caller, per the updated moduledoc). Its `case File.open(path, [...]) do {:error, _reason} -> {:error, :not_found} end` clause maps *any* open failure — permission denied (`:eacces`), too many open files (`:emfile`), a stale/corrupted mount, an I/O error (`:eio`) — to the same `{:error, :not_found}` the caller already treats as the benign "no such object" case. `Import.read_committed_format_bytes/1` then degrades silently to `format_bytes = nil`, which cascades into `format_result = nil`, `unknown_system?` staying `false`, and no format identification for that import — with nothing in the logs or receipt distinguishing "this blob genuinely doesn't exist" from "the blob volume has a permissions or I/O problem and every import's format identification is silently degrading." Since this same object was just written by `commit/2`/`place_and_record/2` moments earlier in the same call chain, a spurious `:not_found` here is disproportionately likely to indicate a real operational fault (e.g. a permissions regression on the blob volume) rather than a missing object.

**Fix:** Distinguish `:enoent` (genuinely not found — the only case the caller's `nil`-degradation is meant for) from other `File.open` error reasons, and log or surface the latter distinctly (e.g. `Logger.error` with the reason, or a distinct `{:error, :io_error}` the caller can choose to alert on) rather than silently absorbing it into the same path as "no format identification for this file."

```elixir
@impl true
def read_leading(sha256, byte_count) do
  path = object_path(blob_path(), sha256)

  case File.open(path, [:read, :binary, :raw]) do
    {:ok, io} ->
      try do
        case :file.read(io, byte_count) do
          {:ok, data} -> {:ok, data}
          :eof -> {:ok, <<>>}
        end
      after
        :file.close(io)
      end

    {:error, :enoent} ->
      {:error, :not_found}

    {:error, reason} ->
      Logger.error("read_leading/2 failed to open committed object #{sha256}: #{inspect(reason)}")
      {:error, :not_found}
  end
end
```

## Info

### IN-01: `Fingerprints.ensure_headerless/2`'s filesystem read runs inside the ambient import transaction

**File:** `playstead-server/lib/playstead/import.ex:194-199`, `playstead-server/lib/playstead/blobs/fingerprints.ex:78-92`

**Issue:** `classify_recognized/8` calls `Fingerprints.ensure_headerless/2` from inside `import_single/4`'s `Repo.transaction/1` block. `ensure_headerless/2` performs a `Repo.get(Blob, blob_id)` followed by `Blobs.digest_from_offset/2`, which does a synchronous local-disk seek-and-read of up to the whole object (`MultiHash.digest_from_offset/2`) before the transaction can commit. This is consistent with `Fingerprints`' own moduledoc, which already acknowledges the tradeoff ("the cost is one extra read... for files where a header was actually detected"), so this is not a correctness defect — but it does mean a slow or contended disk read now extends how long the Postgres transaction (and any row locks it holds, e.g. via `find_or_create_asset_set/4`'s `insert_all`) stays open. Worth a comment or follow-up note if disk latency on the blob volume ever becomes a source of transaction timeouts.

**Fix:** No action required now; if this becomes an operational issue, consider computing the headerless fingerprint outside the transaction (accepting a small window where the fingerprint row could lag the committed blob) or moving it to an async job as the moduledoc's own "reversible" framing anticipates.

---

_Reviewed: 2026-08-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
