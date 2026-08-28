---
phase: 02-explainable-import-and-exact-export
reviewed: 2026-08-28T00:00:00Z
depth: standard
files_reviewed: 45
files_reviewed_list:
  - playstead-server/.env.example
  - playstead-server/Dockerfile
  - playstead-server/config/config.exs
  - playstead-server/config/runtime.exs
  - playstead-server/config/test.exs
  - playstead-server/docker-compose.ci.yml
  - playstead-server/docker-compose.yml
  - playstead-server/docs/DEPLOY.md
  - playstead-server/lib/playstead/application.ex
  - playstead-server/lib/playstead/attention.ex
  - playstead-server/lib/playstead/attention/derive.ex
  - playstead-server/lib/playstead/attention/item.ex
  - playstead-server/lib/playstead/attention/quarantine_policy.ex
  - playstead-server/lib/playstead/attention/reason.ex
  - playstead-server/lib/playstead/attention/resolutions.ex
  - playstead-server/lib/playstead/blobs.ex
  - playstead-server/lib/playstead/blobs/blob.ex
  - playstead-server/lib/playstead/blobs/blob_fingerprint.ex
  - playstead-server/lib/playstead/blobs/multi_hash.ex
  - playstead-server/lib/playstead/blobs/release.ex
  - playstead-server/lib/playstead/blobs/store.ex
  - playstead-server/lib/playstead/blobs/store/local_disk.ex
  - playstead-server/lib/playstead/catalogue.ex
  - playstead-server/lib/playstead/catalogue/asset_member.ex
  - playstead-server/lib/playstead/catalogue/asset_set.ex
  - playstead-server/lib/playstead/catalogue/payload.ex
  - playstead-server/lib/playstead/export.ex
  - playstead-server/lib/playstead/export/bagit_writer.ex
  - playstead-server/lib/playstead/export/export_record.ex
  - playstead-server/lib/playstead/export/layout.ex
  - playstead-server/lib/playstead/export/path_sanitizer.ex
  - playstead-server/lib/playstead/export/sanitize.ex
  - playstead-server/lib/playstead/export/sidecar.ex
  - playstead-server/lib/playstead/export/verifier.ex
  - playstead-server/lib/playstead/export/worker.ex
  - playstead-server/lib/playstead/formats.ex
  - playstead-server/lib/playstead/formats/archive.ex
  - playstead-server/lib/playstead/formats/system_id.ex
  - playstead-server/lib/playstead/formats/validators/gb.ex
  - playstead-server/lib/playstead/formats/validators/gba.ex
  - playstead-server/lib/playstead/formats/validators/md.ex
  - playstead-server/lib/playstead/formats/validators/nes.ex
  - playstead-server/lib/playstead/formats/validators/psx_cue.ex
  - playstead-server/lib/playstead/formats/validators/snes.ex
  - playstead-server/lib/playstead/import.ex
  - playstead-server/lib/playstead/import/folder_import.ex
  - playstead-server/lib/playstead/import/hashing_writer.ex
  - playstead-server/lib/playstead/import/inbox.ex
  - playstead-server/lib/playstead/import/orphan_sweeper.ex
  - playstead-server/lib/playstead/import/outcome.ex
  - playstead-server/lib/playstead/import/preview.ex
  - playstead-server/lib/playstead/import/progress.ex
  - playstead-server/lib/playstead/import/receipt.ex
  - playstead-server/lib/playstead/import/session.ex
  - playstead-server/lib/playstead/import/session_worker.ex
  - playstead-server/lib/playstead/import/source_file.ex
  - playstead-server/lib/playstead/import/staging.ex
  - playstead-server/lib/playstead/import/upload_slots.ex
  - playstead-server/lib/playstead/readiness.ex
  - playstead-server/lib/playstead/recognition.ex
  - playstead-server/lib/playstead/recognition/dat_pack.ex
  - playstead-server/lib/playstead/recognition/dat_pack_importer.ex
  - playstead-server/lib/playstead/recognition/evidence.ex
  - playstead-server/lib/playstead/recognition/header_evidence.ex
  - playstead-server/lib/playstead/recognition/logiqx_handler.ex
  - playstead-server/lib/playstead/recognition/no_intro_name.ex
  - playstead-server/lib/playstead/recognition/override.ex
  - playstead-server/lib/playstead/recognition/provider.ex
  - playstead-server/lib/playstead/recognition/reference_entry.ex
  - playstead-server/lib/playstead/recognition/reference_match.ex
  - playstead-server/lib/playstead/sync/snapshot.ex
  - playstead-server/lib/playstead_web/components/layouts/root.html.heex
  - playstead-server/lib/playstead_web/controllers/api/v1/attention_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/exports_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/import_sessions_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/imports_controller.ex
  - playstead-server/lib/playstead_web/error_codes.ex
  - playstead-server/lib/playstead_web/live/attention_live.ex
  - playstead-server/lib/playstead_web/live/attention_live/bulk_bar.ex
  - playstead-server/lib/playstead_web/live/attention_live/evidence_card.ex
  - playstead-server/lib/playstead_web/live/exports_live.ex
  - playstead-server/lib/playstead_web/live/import_live.ex
  - playstead-server/lib/playstead_web/live/import_live/preview_panel.ex
  - playstead-server/lib/playstead_web/live/import_live/receipt_row.ex
  - playstead-server/lib/playstead_web/live/import_sessions_live.ex
  - playstead-server/lib/playstead_web/live/import_sessions_live/session_row.ex
  - playstead-server/lib/playstead_web/live/library_live.ex
  - playstead-server/lib/playstead_web/live/library_live/asset_detail.ex
  - playstead-server/lib/playstead_web/live/reference_packs_live.ex
  - playstead-server/lib/playstead_web/live/setup_live.ex
  - playstead-server/lib/playstead_web/plugs/repr_digest.ex
  - playstead-server/lib/playstead_web/plugs/upload_concurrency.ex
  - playstead-server/lib/playstead_web/router.ex
  - playstead-server/mix.exs
  - playstead-server/priv/repo/migrations/20260828010000_create_blobs.exs
  - playstead-server/priv/repo/migrations/20260828010001_create_source_files.exs
  - playstead-server/priv/repo/migrations/20260828010002_create_asset_sets_and_members.exs
  - playstead-server/priv/repo/migrations/20260828010003_create_import_receipts.exs
  - playstead-server/priv/repo/migrations/20260828020000_create_recognitions.exs
  - playstead-server/priv/repo/migrations/20260828030000_add_asset_member_ordinal_unique_index.exs
  - playstead-server/priv/repo/migrations/20260828040000_create_import_sessions.exs
  - playstead-server/priv/repo/migrations/20260828050000_add_checkpoint_tracking_to_import_sessions.exs
  - playstead-server/priv/repo/migrations/20260828060000_create_attention_items_and_blob_releases.exs
  - playstead-server/priv/repo/migrations/20260828070000_create_recognition_overrides.exs
  - playstead-server/priv/repo/migrations/20260828080000_create_exports.exs
  - playstead-server/priv/repo/migrations/20260828090000_add_provenance_to_asset_sets.exs
  - playstead-server/priv/repo/migrations/20260828230000_create_dat_packs_and_reference_entries.exs
  - playstead-server/priv/repo/migrations/20260828231500_widen_recognitions_inserted_at_precision.exs
  - playstead-server/scripts/compose-smoke.sh
findings:
  critical: 3
  warning: 4
  info: 1
  total: 8
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-08-28T00:00:00Z
**Depth:** standard
**Files Reviewed:** 111 (full required-reading/config file list; see `files_reviewed_list`)
**Status:** issues_found

## Summary

The export write path (`Playstead.Export.Sanitize`, `Layout`, `BagitWriter`, `Verifier`) is careful and consistent about path safety: every filesystem write derives its component through `Sanitize.component/1` and every join is re-validated with `Sanitize.safe_join/2` before touching disk. The blob store's commit path (`Blobs.Store.LocalDisk`) correctly treats the database's unique index as the sole collision authority, and RFC 9530 digest handling in `ReprDigest` converts base64→hex exactly once at the boundary as documented.

However, the **reimport path is the asymmetric twin that was never given the same treatment**: `Playstead.Import.FolderImport` (and the unused, duplicate `Playstead.Import.reimport_folder/2`) build filesystem paths directly from attacker/exporter-controlled manifest and sidecar content with no traversal check at all — the exact class of bug the export writer was carefully hardened against. Separately, the attention-resolution transaction discipline the moduledoc explicitly promises ("the effect and its audit entry are written inside one transaction") is violated by its own implementation: the guard transition commits before the effect's transaction even opens, so a failing effect leaves the item permanently marked resolved with no effect applied. And the API's `attach_companion` resolution accepts client-supplied digest metadata as ground truth instead of verifying it against the stored blob, undermining the digest-verified custody guarantee that is this phase's central premise.

## Critical Issues

### CR-01: Path traversal in reimport via unsanitized manifest/sidecar paths

**File:** `playstead-server/lib/playstead/import/folder_import.ex:41-59, 70-78, 98-99, 140-152`
**File:** `playstead-server/lib/playstead/import.ex:1013-1056` (duplicate/dead `reimport_folder/2`, same bug)

**Issue:** Every path in the export writer is sanitized twice (`Sanitize.component/1` then `Sanitize.safe_join/2`) before it ever touches the filesystem (see `BagitWriter.write_member!/2`). The reimport path does not apply either check:

```elixir
# folder_import.ex
defp import_group(user_id, bag_dir, group_dir, group_entries) do
  sidecar_path =
    Path.join([bag_dir, "tags", strip_data_prefix(group_dir), "playstead-set.json"])
  ...
defp import_plain_file(user_id, bag_dir, %{relative: relative}) do
  meta = rehash!(Path.join(bag_dir, relative))   # relative from manifest-sha256.txt, unchecked
  ...
defp import_with_sidecar(user_id, bag_dir, sidecar, _group_entries) do
  ...
  payload_path = Path.join(bag_dir, spec["path"] || "")   # spec["path"] from attacker JSON, unchecked
```

`relative` comes straight from parsing `manifest-sha256.txt` (`sha256  relative\n` lines, split on two spaces) and `spec["path"]` comes straight from a per-set sidecar (`playstead-set.json`) that the module's own moduledoc says may be "tampered." Neither value is checked for `..` segments, a leading `/`, or a drive prefix before `Path.join/2`. `Path.join(bag_dir, "../../../etc/passwd")` resolves outside `bag_dir`; `File.stat!/1` and `File.stream!/1` will happily read whatever that path names, and `Blobs.put_stream/2` will ingest it into the CAS and attach it to the calling user's library.

Reachability: neither `Import.FolderImport.import_folder/3` nor `Import.reimport_folder/2` is currently wired to any controller or LiveView in this file set (only exercised from `test/playstead/export/round_trip_test.exs` and `test/playstead/import/tracer_round_trip_test.exs`), so it is not exploitable through the running HTTP surface today. It is nonetheless a shipped module implementing this phase's D-37 "hash-set-first reimport" feature and will become reachable the moment a route/console is wired to it — at which point importing (or letting a device sync) a crafted or corrupted bag directory becomes an arbitrary local file read/ingest primitive. This must be fixed before the reimport entry point is exposed, and is flagged now because the sanitizer discipline used everywhere else in this same phase (`Sanitize.safe_join/2`) is the obvious, already-available fix.

**Fix:** Route every path built from manifest/sidecar content through `Sanitize.safe_join(bag_dir, relative)` (or `component/1` per-segment) before any `File.*` call, exactly as `BagitWriter` does for the write side, and reject the entry (or the whole reimport) on failure:

```elixir
defp import_plain_file(user_id, bag_dir, %{relative: relative}) do
  case Sanitize.safe_join(bag_dir, relative) do
    {:ok, payload_path} -> meta = rehash!(payload_path)
    :error -> :skip_or_error
  end
  ...
```

---

### CR-02: Attention resolution can commit "resolved" status with no effect applied

**File:** `playstead-server/lib/playstead/attention/resolutions.ex:225-271`

**Issue:** The moduledoc states: "Every resolution follows the idempotency module's own discipline: the effect and its audit entry are written inside one transaction, never with the audit entry written after the commit." The implementation does not honor this:

```elixir
defp with_resolution(item, target_status, effect_fun) do
  case Attention.try_transition(item, target_status) do   # <- committed immediately, own statement
    {:ok, resolved_item} ->
      Repo.transaction(fn ->                               # <- separate transaction, starts AFTER
        case effect_fun.(resolved_item) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    {:error, :already_resolved} -> {:error, :already_resolved}
  end
end
```

`Attention.try_transition/2` performs its own `Repo.update_all/2` and returns immediately — this is a fully committed write, not part of the `Repo.transaction/1` that follows. If `effect_fun` then returns `{:error, reason}` (e.g. `correct_system/3`'s `Repo.get(AssetSet, ...)` returns `nil` and yields `{:error, :not_found}`; `attach_companion/4` bubbles up `{:error, :no_matching_incomplete_member}` or `{:error, :already_attached_different_blob}` from `Import.attach_companion/4`), the later transaction rolls back — but the item's `status` is already `"resolved"` in the database, permanently, with no audit entry and no side effect. The caller (`AttentionController.resolve/2`, `AttentionLive.dispatch/3`) sees `{:error, reason}` and shows a generic error flash, but the item has silently vanished from the open inbox because it now reads `status: "resolved"`. The only way back is `undo/2`, which the user has no reason to invoke since they were never told the resolution actually "succeeded" at the status level.

This directly contradicts D-27's reversibility/audit-integrity guarantee and the module's own stated discipline, and it is trivially triggerable: any `correct_system` or `attach_companion` call against an item whose associated `asset_set` was concurrently excluded/deleted, or whose declared member name doesn't match an incomplete slot, reproduces it.

**Fix:** Perform the guard transition inside the same transaction as the effect (using `Repo.transaction`'s own guarded update, not a pre-committed `update_all`), or explicitly revert the transition when the effect fails:

```elixir
defp with_resolution(item, target_status, effect_fun) do
  Repo.transaction(fn ->
    case Attention.try_transition(item, target_status) do
      {:ok, resolved_item} ->
        case effect_fun.(resolved_item) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      {:error, :already_resolved} = err -> err
    end
  end)
end
```
(Nesting concerns cited in the code comment about `Idempotency.execute/4`'s outer transaction should be resolved by using `Repo.checkout`/savepoints or by explicitly re-opening the item on effect failure — but silently leaving a phantom "resolved" row is not an acceptable alternative.)

---

### CR-03: `attach_companion` resolution trusts client-supplied blob digest/size without verification

**File:** `playstead-server/lib/playstead_web/controllers/api/v1/attention_controller.ex:74-84`
**File:** `playstead-server/lib/playstead/import.ex:601-650` (`attach_companion/4`, `find_and_attach_member/3`)

**Issue:** The API resolution handler builds the "existing blob" metadata entirely from client-supplied JSON, with no lookup against the actual `Blob` row:

```elixir
defp apply_resolution(item, user_id, %{
       "resolution" => "attach_companion",
       "declared_name" => declared_name,
       "blob_id" => blob_id,
       "sha256" => sha256,
       "size_bytes" => size_bytes
     }) do
  meta = %{blob_id: blob_id, sha256: sha256, size_bytes: size_bytes}
  attrs = %{original_name: declared_name, origin: "attach", size_bytes: size_bytes}
  Resolutions.attach_companion(item, user_id, declared_name, attrs, {:existing, meta})
end
```

`Resolutions.attach_companion/5` → `Import.attach_companion/4` → `insert_source_file/3` and `insert_receipt/5` persist `meta.sha256`/`meta.size_bytes` verbatim into the new `source_files` and `import_receipts` rows, and `find_and_attach_member/3` sets `asset_members.blob_id = meta.blob_id` via a guarded `UPDATE`. At no point is `blob_id` looked up (e.g. `Blobs.get_by_sha256/1` / `Repo.get(Blob, blob_id)`) to confirm that `sha256`/`size_bytes` actually match the blob the id names, nor is there any check that the calling user already legitimately possesses that blob (the moduledoc for `Resolutions.attach_companion/5` explicitly says it attaches "an existing, **already-owned** blob," but ownership is never checked).

This is a direct contradiction of the digest-verified-custody design this entire phase is built around (D-02/D-11/D-20/D-24: every other write path — API upload, browser upload, session worker, reimport rehash — recomputes and verifies the hash server-side before trusting it). Here, an authenticated device can:
1. Forge the receipt's `sha256`/`size_bytes` fields to any value it likes while `blob_id` points at real (correctly-hashed) bytes, corrupting the audit trail this phase calls "explainable."
2. Attach any `blob_id` that exists in the (globally shared, content-addressed) `blobs` table to its own incomplete member slot, bypassing the "already-owned" invariant the resolution's own documentation promises, since nothing here re-derives `blob_id` from a hash the caller can prove they hold.

**Fix:** Look up the blob server-side from the supplied identifier and derive `meta` from the stored row, never from client JSON:

```elixir
defp apply_resolution(item, user_id, %{
       "resolution" => "attach_companion",
       "declared_name" => declared_name,
       "sha256" => sha256
     }) do
  case Playstead.Blobs.get_by_sha256(sha256) do
    nil -> {:error, :not_found}
    blob ->
      unless Playstead.Import.present_for_user?(user_id, blob.sha256, blob.size_bytes) do
        {:error, :not_owned}
      else
        meta = %{blob_id: blob.id, sha256: blob.sha256, size_bytes: blob.size_bytes}
        attrs = %{original_name: declared_name, origin: "attach", size_bytes: blob.size_bytes}
        Resolutions.attach_companion(item, user_id, declared_name, attrs, {:existing, meta})
      end
  end
end
```

## Warnings

### WR-01: `LocalDisk.stream/2` range clause can crash and defeats streaming

**File:** `playstead-server/lib/playstead/blobs/store/local_disk.ex:333-339`

**Issue:**
```elixir
defp build_stream(path, nil), do: File.stream!(path, [], @chunk_size)

defp build_stream(path, first..last//_step) do
  data = File.read!(path)
  last = min(last, byte_size(data) - 1)
  [binary_part(data, first, last - first + 1)]
end
```
This reads the *entire* file into memory for a ranged request rather than seeking/streaming, and never validates `first`: a `first` at or beyond `byte_size(data)`, or a `first > last` after the clamp, makes `binary_part/3` raise `ArgumentError` — an unhandled crash rather than the `{:error, _}` shape every other function in this module returns. `Playstead.Blobs.stream/2` is part of the public store contract (`opts[:range]`) and `Playstead.Import.reimport_folder`/future Range-header support (Phase 3 CACH-01, per `BlobsController`'s own moduledoc) will call this. Currently unreachable (`BlobsController.show/2` never passes a range), but it is a live landmine for the very next caller that does.

**Fix:** Validate `first >= 0`, `first <= last`, and `first < byte_size` before slicing, returning `{:error, :invalid_range}` on violation, and seek+read only the requested span (`:file.pread/3`) instead of loading the whole file.

### WR-02: Sidecar JSON reimport path has no size cap, unlike the DAT-pack parser

**File:** `playstead-server/lib/playstead/import/folder_import.ex:83-94`
**File:** `playstead-server/lib/playstead/export/sidecar.ex:101-111`

**Issue:** `Playstead.Recognition.LogiqxHandler.read_capped/1` explicitly bounds the DAT-pack XML read to 32 MiB before parsing, with a documented rationale (T-02-60/61) about refusing before the file is fully read. `FolderImport.read_sidecar/1` reads `playstead-set.json` with a plain `File.read/1` (no size limit) and hands the full content straight to `Sidecar.parse/1`, which calls `Jason.decode/1` unconditionally. A crafted or corrupted sidecar of unbounded size inside a bag directory being reimported is read entirely into memory before any validation occurs.

**Fix:** Cap the sidecar read the same way `LogiqxHandler.read_capped/1` does (e.g. `File.stat!/1` size check, or a bounded `File.read`), returning "degrade to plain import" for an oversize file rather than reading it in full.

### WR-03: Upload concurrency slot can leak on abnormal termination

**File:** `playstead-server/lib/playstead_web/plugs/upload_concurrency.ex:24-44`
**File:** `playstead-server/lib/playstead/import/upload_slots.ex`

**Issue:** The slot acquired by `UploadSlots.acquire/2` is only released via `register_before_send/2`. If the request process is killed or the connection is abnormally terminated before a response is ever sent (e.g., the process crashes deep inside `Plug.Conn.read_body`/`Blobs.put_stream/2` during a multi-gigabyte streamed upload, or the client resets the TCP connection mid-body), `before_send` callbacks never run and the slot is never decremented. `UploadSlots` has no TTL/expiry and no process-monitor-based cleanup, so repeated crashes/aborts on the same device permanently consume its two-slot ceiling until the node restarts.

**Fix:** Either monitor the request process and release the slot in a `handle_info({:DOWN, ...})` callback in `UploadSlots`, or add an age-based expiry to the ETS entry so a stuck slot self-heals.

### WR-04: Dead, duplicate sanitizer module (`PathSanitizer`) diverges from the one actually used

**File:** `playstead-server/lib/playstead/export/path_sanitizer.ex`

**Issue:** `Playstead.Export.PathSanitizer` implements the same "sanitize + resolve-under-root" contract as `Playstead.Export.Sanitize`, with a slightly different (reject-only, not idempotent-rewrite) semantics, but is never referenced anywhere outside its own file (`grep -rn PathSanitizer lib` finds only its own `defmodule`). All real call sites (`BagitWriter`, `Export.resolve_target/1`, `Layout`) use `Sanitize`. A security-critical module that looks load-bearing (detailed moduledoc citing "RESEARCH Pitfall 5, D-33") but is actually dead invites a future maintainer to wire a new call site to the wrong (unmaintained, untested-in-production-paths) one, or to "fix" a traversal bug in only one of the two.

**Fix:** Delete `PathSanitizer` (its logic is fully subsumed by `Sanitize`), or if it is intentionally reserved for the not-yet-wired reimport path (see CR-01), wire it in now and delete the duplicate reject-vs-rewrite semantics gap.

## Info

### IN-01: `Import.reimport_folder/2` duplicates `FolderImport.import_folder/3` and is unreferenced

**File:** `playstead-server/lib/playstead/import.ex:1002-1065`

**Issue:** `Playstead.Import.reimport_folder/2` and `Playstead.Import.FolderImport.import_folder/3` both parse `manifest-sha256.txt` and reimport payload files, with materially different identity/sidecar logic, and neither is called from any controller or LiveView in this file set — only from tests (`round_trip_test.exs`, `tracer_round_trip_test.exs`). Two independently-evolving implementations of the same reimport concept (one lacking the sidecar/multi-member logic the other has) is a maintenance hazard: a future fix (including the CR-01 path-traversal fix) applied to one is easy to miss in the other.

**Fix:** Consolidate on `FolderImport.import_folder/3` (the more complete implementation) and remove `Import.reimport_folder/2`, or clarify in both moduledocs which one is the intended production entry point.

---

_Reviewed: 2026-08-28T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
