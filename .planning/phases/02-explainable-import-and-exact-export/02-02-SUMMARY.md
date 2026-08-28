---
phase: 02-explainable-import-and-exact-export
plan: 02
subsystem: import-export
tags: [blob-storage, content-addressed-storage, bagit, ecto, streaming-upload, rfc9530, phoenix]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Plan 02-01's error-code registry, Readiness free-space rows and free_bytes/1|required_bytes/2|fits_free_space?/3, inbox/exports mounts, and Playstead.ImportFixtures test scaffolding"
provides:
  - "Playstead.Blobs / Playstead.Blobs.Store behaviour / Playstead.Blobs.Store.LocalDisk: the whole D-11 write path (temp, streaming multi-hash, fsync, read-back verify, atomic rename, DB-constraint-as-collision-authority)"
  - "Playstead.Blobs.MultiHash: single-pass SHA-256/SHA-1/MD5/CRC32"
  - "Playstead.Import.Outcome and its three reason sub-vocabularies: the nine frozen D-25 outcome codes"
  - "blobs, blob_fingerprints, source_files, asset_sets, asset_members, import_receipts schemas and migrations"
  - "Playstead.Import.OrphanSweeper and Playstead.Import.UploadSlots, both supervised at boot"
  - "PUT /api/v1/imports/uploads/:command_id, POST /api/v1/imports/precheck, GET /api/v1/blobs/:sha256"
  - "PlaysteadWeb.Plugs.ReprDigest and PlaysteadWeb.Plugs.UploadConcurrency"
  - "Playstead.Import.import_single/3 and Playstead.Import.reimport_folder/2"
  - "Playstead.Catalogue.member_fingerprint/1 (D-37 natural key)"
  - "Playstead.Export / Playstead.Export.BagitWriter / Playstead.Export.PathSanitizer: minimal RFC 8493 bag export for one asset set"
affects: [02-03, 02-04, 02-05, 02-06, 02-07, 02-08]

actuals:
  tokens: 28633
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Store behaviour + sole-adapter context: Playstead.Blobs is the only caller of the configured Playstead.Blobs.Store adapter, selected via PLAYSTEAD_BLOB_PATH/config at runtime -- the seam a v2 S3 adapter fits without touching import/export"
    - "Repo.insert_all/3 with on_conflict: :nothing + conflict_target, not Repo.insert/2 + catch, for any lookup-or-create under a unique constraint that might run nested inside an ambient Ecto.Multi transaction (a failed constrained Repo.insert aborts the whole surrounding Postgres transaction for every later query in it)"
    - "Header-derived facts merged into conn.params (never replacing it) so an existing generic plug (PlaysteadWeb.Plugs.Idempotency) can be reused completely unforked with a route-specific fingerprint basis"
    - "Never-raises tagged-tuple sanitizer (Playstead.Export.PathSanitizer, modeled on Playstead.CommandId) as the single choke point every filesystem-bound path component passes through, plus a separate resolve-and-confirm-inside-root check"

key-files:
  created:
    - playstead-server/lib/playstead/blobs.ex
    - playstead-server/lib/playstead/blobs/store.ex
    - playstead-server/lib/playstead/blobs/store/local_disk.ex
    - playstead-server/lib/playstead/blobs/multi_hash.ex
    - playstead-server/lib/playstead/blobs/blob.ex
    - playstead-server/lib/playstead/blobs/blob_fingerprint.ex
    - playstead-server/lib/playstead/catalogue.ex
    - playstead-server/lib/playstead/catalogue/asset_set.ex
    - playstead-server/lib/playstead/catalogue/asset_member.ex
    - playstead-server/lib/playstead/import.ex
    - playstead-server/lib/playstead/import/source_file.ex
    - playstead-server/lib/playstead/import/receipt.ex
    - playstead-server/lib/playstead/import/outcome.ex
    - playstead-server/lib/playstead/import/orphan_sweeper.ex
    - playstead-server/lib/playstead/import/upload_slots.ex
    - playstead-server/lib/playstead/export.ex
    - playstead-server/lib/playstead/export/bagit_writer.ex
    - playstead-server/lib/playstead/export/path_sanitizer.ex
    - playstead-server/lib/playstead_web/plugs/repr_digest.ex
    - playstead-server/lib/playstead_web/plugs/upload_concurrency.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/imports_controller.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex
    - playstead-server/priv/repo/migrations/20260828010000_create_blobs.exs
    - playstead-server/priv/repo/migrations/20260828010001_create_source_files.exs
    - playstead-server/priv/repo/migrations/20260828010002_create_asset_sets_and_members.exs
    - playstead-server/priv/repo/migrations/20260828010003_create_import_receipts.exs
    - playstead-server/test/playstead/blobs/multi_hash_test.exs
    - playstead-server/test/playstead/blobs/store_local_disk_test.exs
    - playstead-server/test/playstead/blobs/cas_race_test.exs
    - playstead-server/test/playstead/import/outcome_test.exs
    - playstead-server/test/playstead/import/tracer_round_trip_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/imports_controller_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/blobs_controller_test.exs
  modified:
    - playstead-server/lib/playstead/application.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/config/runtime.exs
    - playstead-server/config/test.exs

key-decisions:
  - "Upload concurrency (D-10's 'at most two simultaneous uploads per device') is tracked by a small dedicated ETS counter (Playstead.Import.UploadSlots), not by extending Playstead.RateLimiter/Throttle: Hammer's fixed-window limiter has no decrement and cannot represent 'how many uploads are in flight right now' -- a genuinely concurrent, not time-windowed, limit."
  - "PlaysteadWeb.Plugs.ReprDigest merges digest+declared-length facts into conn.params under reserved keys rather than replacing conn.params outright, so PlaysteadWeb.Plugs.Idempotency's generic fingerprint calculation is reused completely unforked without erasing the command_id path parameter Phoenix has already merged in."
  - "Both AssetSet-lookup-or-create and Blob-lookup-or-create use Repo.insert_all/on_conflict instead of Repo.insert + catching a unique_constraint changeset error: discovered mid-plan that a failed constrained insert leaves the ambient Postgres transaction aborted for any later query in the same transaction once nested inside Idempotency.execute/4's Ecto.Multi -- insert_all with on_conflict never raises, so there is nothing to recover from."
  - "determine_outcome/3 reports :alias (not :exact_duplicate) when the duplicate source_file's origin is 'reimport', matching D-37's language, even though both codes share the same 'user already holds this blob' detection path."

requirements-completed: [IMPT-02, IMPT-03, PORT-02]

coverage:
  - id: D1
    description: "The write path is temp, streaming hash, fsync, read-back verify, atomic rename, one transaction, with the blobs.sha256 unique constraint as the collision authority"
    requirement: "IMPT-02"
    verification:
      - kind: unit
        ref: "test/playstead/blobs/store_local_disk_test.exs"
        status: pass
      - kind: unit
        ref: "test/playstead/blobs/cas_race_test.exs#ten genuinely concurrent commits of identical bytes converge on exactly one blobs row"
        status: pass
    human_judgment: false
  - id: D2
    description: "Playstead.Blobs is the only caller of the storage adapter, and the behaviour declares all ten D-12 callbacks"
    requirement: "IMPT-02"
    verification:
      - kind: unit
        ref: "grep -c '@callback' lib/playstead/blobs/store.ex (10)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The nine outcome codes are frozen and every receipt carries exactly one"
    requirement: "IMPT-03"
    verification:
      - kind: unit
        ref: "test/playstead/import/outcome_test.exs"
        status: pass
    human_judgment: false
  - id: D4
    description: "Upload, precheck, and blob-serving endpoints exist on the device-authenticated idempotency pipeline with every D-10 code wired to its specified status"
    requirement: "IMPT-03"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/imports_controller_test.exs"
        status: pass
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/blobs_controller_test.exs"
        status: pass
    human_judgment: false
  - id: D5
    description: "Duplicate status and blob-read authorization are evaluated strictly within the calling user's own records; no cross-user leakage in any response"
    requirement: "IMPT-03"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/imports_controller_test.exs#a second upload of identical bytes by a different user yields new_asset for that user and no cross-user leakage"
        status: pass
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/blobs_controller_test.exs#returns 404 for a blob another user holds but the caller does not"
        status: pass
    human_judgment: false
  - id: D6
    description: "Exporting one asset set writes a verifiable RFC 8493 bag whose manifest is sha256sum -c compatible, and reimporting it produces zero new logical records"
    requirement: "PORT-02"
    verification:
      - kind: e2e
        ref: "test/playstead/import/tracer_round_trip_test.exs#upload, export, independent verify, and reimport into the same library round-trips with zero new logical records"
        status: pass
      - kind: e2e
        ref: "test/playstead/import/tracer_round_trip_test.exs#reimporting an exported folder into an empty library restores the set with identical members"
        status: pass
    human_judgment: false
  - id: D7
    description: "The export path sanitizer rejects traversal, absolute paths, and NUL/control bytes, and the writer never deletes or overwrites a file it did not write"
    requirement: "PORT-02"
    verification:
      - kind: unit
        ref: "test/playstead/import/tracer_round_trip_test.exs#Playstead.Export.PathSanitizer"
        status: pass
      - kind: unit
        ref: "test/playstead/import/tracer_round_trip_test.exs#export target and marker safety"
        status: pass
    human_judgment: false

duration: 4h30min
completed: 2026-08-28
status: complete
---

# Phase 2 Plan 2: Explainable Import Tracer Summary

Proves the whole custody path end to end on one file: `PUT /api/v1/imports/uploads/:command_id` streams a ROM straight into a content-addressed local-disk store with streaming SHA-256/SHA-1/MD5/CRC32, verifies it against an RFC 9530 `Repr-Digest`, writes a durable per-file receipt with one of nine frozen outcome codes, and `Playstead.Export.BagitWriter` exports the resulting asset set into a `sha256sum -c`-verifiable RFC 8493 bag that reimports as a duplicate rather than a second copy.

## Performance

- **Duration:** 4h30min
- **Tasks:** 3 completed
- **Files modified:** 37 (33 created, 4 modified)

## Accomplishments
- The write path (`Playstead.Blobs`, `Playstead.Blobs.Store` behaviour, `Playstead.Blobs.Store.LocalDisk`, `Playstead.Blobs.MultiHash`) implements D-11 exactly in order — temp file, streaming multi-hash, fsync, read-back verify, atomic rename into `objects/sha256/ab/cd/<hash>` — with the database's unique constraint on `blobs.sha256` as the sole collision authority, proven under genuine concurrency by `cas_race_test.exs`'s ten-way real-transaction race.
- The API upload path (`PlaysteadWeb.Plugs.ReprDigest`, `PlaysteadWeb.Api.V1.ImportsController`, `Playstead.Import.import_single/3`) streams a request body directly into the store with no in-memory buffering, verifies the declared `Repr-Digest` against the server's own streamed hash before ever committing bytes, and writes `source_file`/`asset_set`/`asset_member`/`import_receipt`/journal-entry in one transaction — duplicate detection and blob-read authorization are both scoped strictly to the calling user.
- `Playstead.Export.BagitWriter` writes a minimal but genuinely RFC 8493 compliant bag (temp-then-fsync-then-rename per file, marker-file-guarded target) whose `manifest-sha256.txt` a self-hoster can verify with plain `sha256sum -c`; `Playstead.Import.reimport_folder/2` re-enters the same single-file import path per manifest entry, so identity naturally follows `Playstead.Catalogue.member_fingerprint/1` with zero extra bookkeeping.

## Task Commits

Each task was committed atomically:

1. **Task 1: The write path — store behaviour, local-disk adapter, streaming multi-hash, and the schemas the commit transaction writes** - `ca3a25d` (feat)
2. **Task 2: The API upload path — precheck, Repr-Digest verification, the durable receipt, and blob byte-serving** - `45239e6` (feat)
3. **Task 3: Minimal one-set export and the reimport round trip that closes the tracer** - `dc11aeb` (feat)

**Plan metadata:** pending (this commit)

## Files Created/Modified

- `playstead-server/lib/playstead/blobs/store.ex` — the D-12 storage adapter behaviour (10 callbacks)
- `playstead-server/lib/playstead/blobs/store/local_disk.ex` — the sole v1 adapter: temp/fsync/verify/rename, DB-constraint-as-authority
- `playstead-server/lib/playstead/blobs/multi_hash.ex` — single-pass SHA-256/SHA-1/MD5/CRC32
- `playstead-server/lib/playstead/blobs.ex` — the only caller of the configured store adapter
- `playstead-server/lib/playstead/import/outcome.ex` — the nine frozen outcome codes and three reason sub-vocabularies
- `playstead-server/lib/playstead/import/orphan_sweeper.ex`, `upload_slots.ex` — supervised tmp-file sweep and per-device upload concurrency counter
- `playstead-server/lib/playstead_web/plugs/repr_digest.ex`, `upload_concurrency.ex` — upload header verification and concurrency cap
- `playstead-server/lib/playstead_web/controllers/api/v1/imports_controller.ex`, `blobs_controller.ex` — upload/precheck/byte-serving endpoints
- `playstead-server/lib/playstead/import.ex` — `import_single/3`, `reimport_folder/2`, `present_for_user?/3`
- `playstead-server/lib/playstead/export.ex`, `export/bagit_writer.ex`, `export/path_sanitizer.ex` — minimal RFC 8493 export and the traversal-safe path sanitizer
- `playstead-server/lib/playstead/catalogue.ex` — `member_fingerprint/1` (D-37)
- Four migrations creating `blobs`, `blob_fingerprints`, `source_files`, `asset_sets`, `asset_members`, `import_receipts`
- `playstead-server/lib/playstead/application.ex` — supervises `OrphanSweeper` and `UploadSlots`
- `playstead-server/lib/playstead_web/router.ex` — the three new `/api/v1` routes and their pipelines
- `playstead-server/config/runtime.exs`, `config/test.exs` — the `Playstead.Blobs` store config and test-env blob/export path + upload-ceiling overrides

## Decisions Made

See `key-decisions` in the frontmatter — summarized: (1) upload concurrency uses a dedicated ETS counter rather than extending the fixed-window rate limiter, (2) the digest plug merges facts into `conn.params` rather than replacing it so the generic idempotency plug stays unforked, (3) both lookup-or-create paths (blob, asset set) use `Repo.insert_all/on_conflict` instead of `Repo.insert` + catch to avoid aborting an ambient nested transaction, and (4) a reimported duplicate reports `:alias` rather than `:exact_duplicate`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Repo.insert` + catch-unique-constraint aborts the ambient transaction when nested inside `Idempotency.execute/4`**
- **Found during:** Task 2 verification (controller tests for duplicate-upload scenarios returned 500)
- **Issue:** Both `Playstead.Blobs.Store.LocalDisk`'s blob lookup-or-create and `Playstead.Import`'s asset-set lookup-or-create used `Repo.insert(changeset)` and, on a unique-constraint violation, fell back to `Repo.get_by!/2` in the same transaction. This works when the calling transaction is the ExUnit sandbox's own top-level transaction (as in Task 1's isolated tests), but a failed constrained `INSERT` still leaves the underlying Postgres transaction aborted (`25P02 in_failed_sql_transaction`) for every later query in that same transaction — and both call sites run nested one level deeper inside `Playstead.Idempotency.execute/4`'s own `Ecto.Multi` transaction once reached through the controller.
- **Fix:** Replaced both `Repo.insert` + catch patterns with `Repo.insert_all/3` using `on_conflict: :nothing` and an explicit `conflict_target`, then always reading the row back with `Repo.get_by!/2`; the affected-row count (0 vs 1) distinguishes "created" from "found existing" without ever raising or aborting the ambient transaction.
- **Files modified:** `playstead-server/lib/playstead/blobs/store/local_disk.ex`, `playstead-server/lib/playstead/import.ex`
- **Verification:** `mix test test/playstead_web/controllers/api/v1/imports_controller_test.exs` and the full `mix precommit` suite (404 tests, 0 failures).
- **Committed in:** `45239e6`

**2. [Rule 1 - Bug] Idempotency fingerprint collided across independent uploads because the path-param overwrite erased `command_id`**
- **Found during:** Task 2 verification (a replay test with a fresh `command_id` per call unexpectedly hit `idempotency_key_mismatch`, and a genuine replay test needed a stable `command_id`)
- **Issue:** The original `PlaysteadWeb.Plugs.ReprDigest` design replaced `conn.params` outright with a synthetic `%{"digest" => ..., "length" => ...}` map for `PlaysteadWeb.Plugs.Idempotency` to fingerprint on. Phoenix merges path parameters (including `:command_id`) into `conn.params` before pipeline plugs run, so overwriting the whole map erased `command_id` from what the controller's `%{"command_id" => command_id}` pattern match expected.
- **Fix:** Changed the plug to merge two reserved keys (`"__repr_digest_sha256"`, `"__declared_length"`) into the existing `conn.params` instead of replacing it, preserving `command_id` and every other path/query param.
- **Files modified:** `playstead-server/lib/playstead_web/plugs/repr_digest.ex`
- **Verification:** `mix test test/playstead_web/controllers/api/v1/imports_controller_test.exs`
- **Committed in:** `45239e6`

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs found and fixed during the task's own verification, before the task's commit).
**Impact on plan:** No scope creep. Both fixes are internal correctness corrections to the exact mechanisms the plan specified (the DB-constraint-as-authority write path, and the unforked idempotency plug reuse); the public contracts (endpoints, outcome codes, receipt shape) are unchanged from the plan.

## Issues Encountered

The plan's task 2 acceptance criterion `grep -rv '^\s*#' .../imports_controller.ex | grep -ci 'upload-offset\|tus\|part_number'` returns 4, not 0, in this implementation — but all four hits are the substring "tus" inside the legitimate words "status" and Phoenix's own `put_status/2` call, not any TUS/chunked/resumable-upload code. A stricter word-boundary grep (`grep -ciE 'upload-offset|\btus\b|part_number'`) returns 0, confirming no chunked/multipart/resumable upload protocol exists anywhere in the controller — the whole-body `PUT` contract the task specifies is exactly what's implemented. Documented here rather than silently treated as passing.

## User Setup Required

None — no external service configuration required. `PLAYSTEAD_BLOB_PATH`/`PLAYSTEAD_EXPORT_PATH`/`PLAYSTEAD_MAX_UPLOAD_BYTES` all have working defaults from plan 02-01's runtime config; a self-hoster following `docs/DEPLOY.md`'s existing inbox/exports mount instructions needs no new steps for this plan.

## Next Phase Readiness

Ready for `02-03` (format recognition). The write path, store behaviour, receipt grain, and member fingerprint are final, production shapes — not prototypes — for the rest of Phase 2 to build on: recognition fills in the `unrecognized`-with-no-evidence seam left here; the inbox scan, session worker, and attention inbox all expand outward from `Playstead.Import.import_single/3`'s single-file path; the full BagIt export (sidecars, per-member checkpoints, write-then-verify second pass, durable `exports` row) expands `Playstead.Export.BagitWriter`'s minimal one-set writer.

No blockers.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-28*

## Self-Check: PASSED

All 12 key created files verified present on disk; all three task commit hashes (`ca3a25d`, `45239e6`, `dc11aeb`) verified present in `git log`. Full `mix precommit` (404 tests) passes clean.
