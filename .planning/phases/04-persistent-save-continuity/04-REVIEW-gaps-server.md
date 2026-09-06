---
phase: 04-persistent-save-continuity
reviewed: 2026-09-06T02:23:49Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - playstead-server/lib/playstead/export.ex
  - playstead-server/lib/playstead/export/saves_lineage.ex
  - playstead-server/lib/playstead/export/worker.ex
  - playstead-server/lib/playstead/saves.ex
  - playstead-server/test/playstead/export/round_trip_test.exs
  - playstead-server/test/playstead/export/saves_lineage_test.exs
  - playstead-server/test/playstead/export/saves_loading_test.exs
findings:
  critical: 1
  warning: 4
  info: 0
  total: 5
status: issues_found
---

# Phase 04: Code Review Report (gap-closure plan 04-21, server side)

**Reviewed:** 2026-09-06T02:23:49Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Scope: the server-side files changed by gap-closure plan 04-21, which fixed the WINDOWS #30/PORT-01 wiring defect (`Export.to_layout_input/1` never attached a `:saves` key, so every production export wrote an empty `saves/` slot). I confirmed the wiring fix itself is correct and reaches both production export paths:

- `Export.load_save_revisions/2` is the single, correctly-scoped crossing into `Playstead.Saves` (D-62), and it is now called from both `Worker.build_layout/1` clauses (`scope: "set"` and `scope: "library"`) as well as the synchronous `Export.export_set/3`. `to_layout_input/2` now threads `saves:` through to `Layout.plan/2` on every path I traced. The wiring gap the prior review flagged is genuinely closed.
- The missing-bytes contract (a revision whose blob no longer exists on this server) is correctly handled end-to-end: `BagitWriter.write_saves_payload!/2` never opens/streams a `:missing` entry, `manifest_lines/1` filters it out via `sha256: nil`, and `Sidecar.saves_sidecar/1` names it `"bytes" => "missing"` with no `path`. `saves_lineage_test.exs`'s "blob absent" test confirms the resulting bag still passes `Verifier.verify/1`.
- `SavesLineage.branch_keys/1` is pure and correctly derives a stable, timestamp-independent fork-root key; `SavesPlan.assign_branch_letters/1` sorts branch keys (immutable UUIDs) ascending, so branch-letter assignment is deterministic and does not depend on map iteration order.

However, one genuine correctness gap remains in the ordering that seq numbers and filenames are derived from (BLOCKER, see CR-01), and the way the fix loads save data for a library-scope export has real efficiency and coverage gaps (WARNINGs). None of these were already recorded in `04-REVIEW.md`/`04-REVIEW-server.md` — I cross-checked and am not re-reporting CR-01 (cross-line parent) or CR-02 (rate limiting) from `04-REVIEW-server.md`, both of which are about different code paths.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Revision ordering has no tiebreaker — ties in `recorded_at` make save-revision `seq` numbers and filenames non-deterministic across re-exports

**File:** `playstead-server/lib/playstead/saves.ex:408-413` (`get_history/2`'s revisions query), and `playstead-server/lib/playstead/saves/branches.ex:42-46` (`heads/2`'s `base_query`)

**Issue:** Both queries that feed the export pipeline's ordering order strictly by `order_by: [asc: r.recorded_at]` with no secondary sort key:

```elixir
revisions =
  from(r in Revision,
    where: r.user_id == ^user_id and r.save_line_id == ^save_line_id,
    order_by: [asc: r.recorded_at]
  )
  |> Repo.all()
```

`Export.load_save_revisions/2` passes this list straight into `SavesLineage.branch_keys/1` and then into `SavesPlan.plan/2`, which re-sorts by the *same* field (`Enum.sort_by(&1.recorded_at, DateTime)`) and assigns `seq` by `Enum.with_index/2`. Elixir's `Enum.sort_by/2` is stable, but that only guarantees ties preserve whatever order the database handed back — and Postgres gives **no** ordering guarantee for rows with equal `ORDER BY` values across two separate query executions (the planner is free to pick a different scan/index path, and two rows with identical `recorded_at` can legally come back in either order on different runs).

`recorded_at` is `DateTime.utc_now() |> DateTime.truncate(:microsecond)` computed once per commit request (`saves.ex:103`). Two revisions committed close together — the exact scenario D-58/D-59 and this whole gap-closure plan exist to handle (concurrent devices forking a save line) — can collide at microsecond granularity, especially on hosts/containers where the underlying clock's actual resolution is coarser than a microsecond. When that happens, re-running the export worker (`Worker.perform/1`, or a deliberate re-enqueue) can allocate a **different** `seq` to the tied revisions on a second run, which:

- Directly violates the D-59 guarantee this plan's own test (`round_trip_test.exs:450-481`, "an appended revision never renumbers or renames a pre-existing revision's exported file") is designed to catch — but that test only fails if a *fork* changes ordering, not a same-branch tie, so it would not catch this.
- Changes the exported filename (`{seq:06}[-branch]-{digest8}.ext`) for a revision that was already shipped to a self-hoster in a previous export, breaking the "never renumbers or renames" promise this feature is explicitly built around.
- Is silent: nothing detects or logs the tie: the manifest still hashes correctly (bytes are unchanged), so `Verifier.verify/1` reports success even though the *name* of a previously-exported file changed between two exports of the same data.

**Fix:** Add `id` (or another stable, unique column) as a secondary sort key to both queries, e.g.:

```elixir
order_by: [asc: r.recorded_at, asc: r.id]
```

Note `id` alone isn't naturally orderable (it's a client-supplied UUID, not a UUIDv7/ULID), so a purely `id`-based tiebreak only guarantees *some* fixed order, not a semantically meaningful one — but a fixed, reproducible order is exactly what's missing today, and that's sufficient to satisfy D-59. If a semantically meaningful tiebreak is wanted, prefer an autoincrementing sequence/`inserted_at` column with real monotonic guarantees at insert time.

## Warnings

### WR-01: N+1 query pattern in library-scope export's saves loading

**File:** `playstead-server/lib/playstead/export/worker.ex:85-95` (`build_layout/1` for `scope: "library"`), `playstead-server/lib/playstead/export.ex:119-148` (`load_save_revisions/2`)

**Issue:** For a `:library`-scope export, `Worker.build_layout/1` calls `load_saves(saves_scope_atom, user_id, asset_set)` once per asset set in `Enum.map(asset_sets, fn asset_set -> ... end)`. Each call to `Export.load_save_revisions/2` that finds a matching save line issues:

1. `Saves.list_lines/2` — 1 query
2. `Saves.get_history/2` → `Repo.get_by(Save, ...)` — 1 query, **redundant**: `list_lines/2` already fetched this exact `Save` row a moment earlier in the same function.
3. `Saves.get_history/2` → `Repo.all(revisions)` — 1 query
4. `Saves.get_history/2` → `Branches.heads/2` — 2 queries (`referenced_parent_ids/2` then the heads query)

That's up to 5 queries per asset set, scaling linearly with library size, with no batching — a textbook N+1 across the whole library export. This is a new cost introduced by this plan: before the wiring fix, no export path called into `Playstead.Saves` at all for a set with a matching content key.

**Fix:** At minimum, avoid the redundant `Save` refetch by having `load_save_revisions/2` pass the already-fetched `line` into a variant of `get_history/2` that skips the `Repo.get_by(Save, ...)` step. For the library case specifically, consider a single batched query across all of the library's content keys (one `Saves.list_lines`-equivalent call keyed by a list of content keys, one `Revision` query with `content_key/line_id IN (...)`) rather than one full round-trip per asset set.

### WR-02: `fetch_all_asset_sets/1`'s doc says "non-excluded" but the query fetches every asset set, causing wasted saves-loading work for sets that get filtered out anyway

**File:** `playstead-server/lib/playstead/export.ex:185-191`

**Issue:**

```elixir
@doc "Fetches every non-excluded asset set for `user_id` with members and blobs preloaded."
@spec fetch_all_asset_sets(pos_integer()) :: [AssetSet.t()]
def fetch_all_asset_sets(user_id) do
  from(a in AssetSet, where: a.user_id == ^user_id)
  |> Repo.all()
  |> Repo.preload(asset_members: {from(m in AssetMember, order_by: m.ordinal), [:blob]})
end
```

There is no `excluded_at`/`excluded` filter here at all — the docstring is simply wrong (this predates 04-21, but 04-21 is the plan that made this function's output feed real, per-set `Saves` queries, so the wasted work is new). `Layout.plan/2` does correctly drop excluded sets later (`include_excluded: false` is the default for the library scope, and `Worker.build_layout/1` doesn't override it), so the final bag is still correct — but `Worker.build_layout/1`'s `Enum.map(asset_sets, fn asset_set -> ... load_saves(...) ... end)` runs the full WR-01 query chain for every excluded set too, before `Layout.plan/2` throws that work away.

**Fix:** Either fix the docstring to match reality, or (better, since it also fixes the wasted work) filter `where: is_nil(a.excluded_at)` at the query level and have the library `build_layout/1` pass `include_excluded: true` explicitly only when a future feature needs it — right now nothing does, since the current default already excludes them post-hoc at real cost.

### WR-03: `SavesLineage.fork_root/4`'s per-revision ancestor walk is O(n²) for a long, unforked save line

**File:** `playstead-server/lib/playstead/export/saves_lineage.ex:49-66`

**Issue:** `branch_keys/1` calls `fork_root/4` once per revision, and for any revision with no fork in its ancestry, `fork_root/4` walks `parent_revision_id` all the way to the root before returning `nil`. For a purely linear save line of `n` revisions (the common case — most save lines never fork), the total work is `1 + 2 + ... + n` = O(n²). `Saves.revision_count_backstop/0` is 100,000 (`saves.ex:41`) and is explicitly "never enforced, only surfaced as attention" (D-28) — so a legitimately long-lived, frequently-saved, never-forked line can genuinely reach tens or hundreds of thousands of revisions. At that scale this recursive walk is effectively unbounded CPU time inside a single Oban job execution (with `max_attempts: 5` and no per-job timeout configured in `Worker`), risking an export that never completes rather than merely being slow.

**Fix:** Compute branch keys iteratively bottom-up (e.g., process revisions in a single pass building a `parent_id -> branch_key` map as you go in topological/recorded_at order, memoizing each revision's resolved branch key instead of re-walking from scratch), turning this into O(n) instead of O(n²).

### WR-04: No test exercises `:library`-scope export's saves wiring — only `:set`-scope is covered

**Files:** `playstead-server/test/playstead/export/round_trip_test.exs`, `playstead-server/test/playstead/export/saves_lineage_test.exs`, `playstead-server/test/playstead/export/saves_loading_test.exs`

**Issue:** All three test files' saves-related tests call `Export.create_export(..., :set, ...)`. Grepping all three files for `:library` finds zero matches. `Worker.build_layout/1` has two separate clauses — one per scope — that independently call `load_saves/3` and thread `saves` into `Export.to_layout_input/2`. The `:set` clause is now well covered (this is exactly the wiring the prior review flagged as broken), but the `:library` clause's equivalent wiring has no test asserting real save-revision bytes land in a library-scope bag. A future edit to the library clause alone (e.g. someone "simplifying" it to call `Export.to_layout_input/1` again, reintroducing the exact WINDOWS #30 defect for library exports only) would not be caught by any test in this plan's suite.

**Fix:** Add at least one test mirroring `saves_loading_test.exs`'s "writes that revision's real bytes into the bag" case but using `Export.create_export(user_id, :library, target_name: ...)` (no `asset_set_id`), asserting the same `data/*/*/saves/revisions/*` file and manifest-line outcome.

---

_Reviewed: 2026-09-06T02:23:49Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
