---
phase: 02-explainable-import-and-exact-export
fixed_at: 2026-08-30T20:26:19Z
review_path: .planning/phases/02-explainable-import-and-exact-export/02-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-08-30T20:26:19Z
**Source review:** .planning/phases/02-explainable-import-and-exact-export/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (this run used `fix_scope: all`, bringing IN-01 into scope alongside the previously in-scope CR-01 and WR-01)
- Fixed: 3
- Skipped: 0

## Fixed Issues

### CR-01: Import-time ambiguous match and reidentify-time ambiguous match can raise two separate attention items for the same blob

**Files modified:** `playstead-server/lib/playstead/import.ex`, `playstead-server/lib/playstead/recognition.ex`
**Commit:** `db1f8f7` (fixed in a prior fix pass, this run)
**Applied fix:** Verified against current code rather than re-applied. `classify_recognized/8` now routes the import-time "ambiguous" reason through `reference_match_reason/3`, which calls `Recognition.raise_ambiguous/4` directly — the same bookkeeping (`reference_match`-provider evidence row + `"ambiguous_recognition:#{blob_id}"` grouping key) `Recognition.reidentify/2`'s ambiguous branch uses. `attention_already_raised?: reason == "ambiguous"` in `import.ex` (with an explicit `# CR-01` comment) prevents `raise_attention/4` from raising a second, differently-keyed item for the same conflict. Confirmed by reading `import.ex:266-274` and the surrounding `unrecognized_reason_for/3` clauses — the two call sites now converge on one attention item and one evidence-exclusion signal, matching the fix's stated intent.

### WR-01: `LocalDisk.read_leading/2` collapses every `File.open` failure reason into `:not_found`, masking operational faults

**Files modified:** `playstead-server/lib/playstead/blobs/store/local_disk.ex`
**Commit:** `cc0cfc2` (fixed in a prior fix pass, this run)
**Applied fix:** Verified against current code rather than re-applied. `read_leading/2` now has separate `{:error, :enoent} -> {:error, :not_found}` and `{:error, reason} -> Logger.error(...); {:error, :not_found}` clauses (with a `# WR-01` comment documenting the rationale), matching the review's suggested distinction between the genuinely-benign "not found" case and other operational faults (`:eacces`, `:emfile`, `:eio`, etc.), which are now logged distinctly via `Logger.error` before falling back to the same caller-facing `:not_found` degradation.

### IN-01: `Fingerprints.ensure_headerless/2`'s filesystem read runs inside the ambient import transaction

**Files modified:** `playstead-server/lib/playstead/import.ex`
**Commit:** `fc5b559`
**Applied fix:** Per the review's own recommendation ("no action required now"), applied the minimal appropriate change — a clarifying comment at the `Fingerprints.ensure_headerless/2` call site in `classify_recognized/8` documenting that this call runs inside `import_single/4`'s ambient `Repo.transaction/1`, that a detected header triggers a synchronous local-disk read before the transaction can commit (extending row-lock duration, e.g. via `find_or_create_asset_set/4`'s `insert_all`), and the two follow-up options the review named (computing the fingerprint outside the transaction, or moving it to an async job) should blob-volume disk latency ever become a source of transaction timeouts. No behavior change — no risky refactor was applied, consistent with the review's guidance.

## Verification

- `mix compile --warnings-as-errors` in `playstead-server/` — compiled cleanly (163 files, no warnings) with the IN-01 comment change applied.
- `mix test test/playstead/import/session_worker_test.exs test/playstead/import/tracer_round_trip_test.exs` — 1 property, 20 tests, 0 failures.
- Both compile and test verification ran in the **main checkout** (`~/projects/playstead/playstead-server`), which has `_build`/deps installed, not the isolated fix worktree (which has neither). The IN-01 change was temporarily copied into the main checkout for verification, then reverted there via `git checkout --` before being committed for real inside the isolated worktree (`gsd-reviewfix/02-55780`) and fast-forwarded onto `main`. This makes the reported compile/test results reproducible from the current `main` checkout after cleanup.
- CR-01 and WR-01 were verified by reading current source (no changes needed, no compile/test re-run required since no code was touched for those two findings this pass).

---

_Fixed: 2026-08-30T20:26:19Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
