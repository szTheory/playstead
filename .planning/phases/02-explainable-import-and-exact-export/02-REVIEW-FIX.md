---
phase: 02-explainable-import-and-exact-export
fixed_at: 2026-08-30T16:00:00Z
review_path: .planning/phases/02-explainable-import-and-exact-export/02-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 1
status: partial
---

# Phase 02: Code Review Fix Report — Gap-Closure Diff (02-09, 02-10)

**Fixed at:** 2026-08-30
**Source review:** .planning/phases/02-explainable-import-and-exact-export/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (fix_scope = critical_warning): 2 (CR-01, WR-01)
- Fixed: 2
- Skipped (out of scope per fix_scope): 1 (IN-01, info-level)

## Fixed Issues

### CR-01: Import-time ambiguous match and reidentify-time ambiguous match can raise two separate attention items for the same blob

**Files modified:**
- `playstead-server/lib/playstead/recognition.ex`
- `playstead-server/lib/playstead/import.ex`
- `playstead-server/test/playstead/recognition/ambiguous_recognition_test.exs`

**Commit:** `db1f8f7`

**Applied fix:** Made `Recognition.raise_ambiguous/4` public (previously private, used only by `reidentify/2`) and routed `Import.classify_recognized/8`'s import-time ambiguous determination through it. Concretely:

- `Import.classify_recognized/8` now creates the asset set *before* computing the unrecognized reason (previously the asset set was found/created afterward), so it has an `asset_set` in hand when the ambiguous branch fires.
- `unrecognized_reason_for/6` (was `/5`) and `quiet_unrecognized_reason/3` (was `/2`) now thread `asset_set` through to `reference_match_reason/3` (was `/1`), and only run when `determine_outcome/4` has already settled on `:new_asset` — this scopes the new side effect (raising an attention item) to the outcome it actually applies to, rather than running eagerly for every classification as the old code did for the pure-read version.
- When `ReferenceMatch.match/2` returns `{:ambiguous, entries}`, `reference_match_reason/3` now calls `Recognition.raise_ambiguous(user_id, asset_set, blob, entries)` directly — the exact same evidence-row-plus-attention-item bookkeeping `Recognition.reidentify/2`'s ambiguous branch uses, under the `"ambiguous_recognition:#{blob_id}"` grouping key and writing a `reference_match`-provider `Evidence` row.
- The classification map gained an `attention_already_raised?` flag (`true` only when `reason == "ambiguous"`); `raise_attention/4` (shared by `import_single/4` and `complete_staged_file/4`) now short-circuits to `{:ok, nil}` when that flag is set, so it never raises a second, differently-keyed item for the same conflict.
- Writing the `reference_match` evidence row at import time also means the blob is now correctly excluded from `Recognition.reidentify/2`'s `unmatched_candidates/1` on any later pack install, closing the loophole the review's reproduction steps described.

Added a regression test (`ambiguous_recognition_test.exs`, describe block "import-time ambiguous detection converges with reidentify (CR-01)") that reproduces the review's exact scenario: imports a new blob while two conflicting reference packs are already installed, asserts `Attention.count(user_id) == 1` and the correct grouping key/evidence-row immediately after import, then installs a third pack (triggering `reidentify/2`) and re-asserts `Attention.count(user_id) == 1`.

**Verification:** `mix compile` clean; targeted test run (`ambiguous_recognition_test.exs`, `test/playstead/import`, `test/playstead/recognition`, `test/playstead/attention`, and the affected LiveView/controller suites) — 243 tests, 0 failures. Full project suite afterward — 760 tests, 0 failures.

### WR-01: `LocalDisk.read_leading/2` collapses every `File.open` failure reason into `:not_found`, masking operational faults

**Files modified:**
- `playstead-server/lib/playstead/blobs/store/local_disk.ex`
- `playstead-server/test/playstead/blobs/read_leading_test.exs`

**Commit:** `cc0cfc2`

**Applied fix:** Applied the review's suggested fix essentially verbatim — added `require Logger`, and split the `read_leading/2` `File.open/2` error clause into `{:error, :enoent} -> {:error, :not_found}` (the genuine "no such object" case, unchanged caller behaviour) and a distinct `{:error, reason} -> Logger.error(...); {:error, :not_found}` clause that logs the actual reason (permissions, too-many-open-files, I/O error, etc.) before still returning `{:error, :not_found}` — preserving the existing degrade-to-`nil` behaviour for callers while making the operational-fault case observable in logs, as the review requested.

Added a regression test that `File.chmod!`s a freshly-stored object to `0o000`, asserts `Blobs.read_leading/2` still returns `{:error, :not_found}` (behaviour-preserving), and asserts (via `ExUnit.CaptureLog`) that the failure is logged distinctly with the object's sha256 and the underlying reason.

**Verification:** `mix compile` clean, `mix format` applied with no further diff needed; targeted test run (`test/playstead/blobs`) — 26 tests, 0 failures, including the new regression test which correctly exercised the non-`:enoent` branch (confirmed not running as root, since a root process would bypass the permission check). Full project suite afterward — 760 tests, 0 failures.

## Skipped Issues

### IN-01: `Fingerprints.ensure_headerless/2`'s filesystem read runs inside the ambient import transaction

**File:** `playstead-server/lib/playstead/import.ex:194-199`, `playstead-server/lib/playstead/blobs/fingerprints.ex:78-92`

**Reason:** Out of scope. `fix_scope` for this run was `critical_warning` (CR-01 and WR-01 only); IN-01 is an info-level finding and the review itself states "No action required now." Not attempted.

**Original issue:** `classify_recognized/8` calls `Fingerprints.ensure_headerless/2` inside `import_single/4`'s `Repo.transaction/1` block, which performs a synchronous local-disk seek-and-read before the transaction can commit — extending how long the Postgres transaction (and any row locks it holds) stays open. The review flags this as worth a comment or follow-up only if disk latency on the blob volume ever becomes a source of transaction timeouts; no code change is requested.

---

_Fixed: 2026-08-30_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
