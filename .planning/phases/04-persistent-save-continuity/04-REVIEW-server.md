---
status: issues-found
scope: server-elixir
files_reviewed: 36
critical: 2
warning: 5
info: 3
---

# Phase 4 Server-Side Review — Persistent Save Continuity

Scope: the 36 files in `/tmp/gsd-scope-server.txt` (playstead-server/lib/**, the four new migrations, `shared/save-vocabulary.json`). Test files excluded except where their absence is itself the finding (none found — no test-coverage claims are made either way here since tests were out of scope for reading).

Known, already-tracked gaps (WINDOWS.md #30/#32-#39) are **not** re-reported. I did confirm #30 (real `Playstead.Saves` revision data is not wired into `Export.to_layout_input/1` — `to_layout_input/1` in `export.ex:63-84` never adds a `:saves` key, so `Layout.build_saves_plan/3` always sees `Map.get(set, :saves, [])` == `[]` in production) and it is exactly as severe as recorded, not more.

---

## Critical Issues

### CR-01: A revision's `parent_revision_id` is never checked against its own save line — a client can silently link two different games' lineages

**File:** `playstead-server/lib/playstead/saves.ex:163-174` (`resolve_parent/2`), with no compensating check anywhere else in the commit path, and no DB constraint in `playstead-server/priv/repo/migrations/20260904000001_create_save_lines_and_revisions.exs:26-31` or `.../20260904000002_add_save_lineage_fields_and_parents.exs`.

**What is wrong:** `commit_revision/3` resolves (or creates) a save line keyed on `(user_id, content_key, save_kind, slot)` (D-10), then separately resolves `parent_revision_id` via:

```elixir
defp resolve_parent(user_id, parent_revision_id) do
  case Repo.get_by(Revision, id: parent_revision_id, user_id: user_id) do
    nil -> {:error, {:save_parent_unknown, ...}}
    %Revision{} = parent -> {:ok, parent}
  end
end
```

This only scopes by `user_id`. It never checks `parent.save_line_id == line.id`. Nothing downstream (`Revision.create_changeset/2`, the `save_revisions` migration, or `save_revision_parents`) enforces same-line parentage either — the FK on `parent_revision_id` just points at `save_revisions.id`, any line.

**Why it matters:** A revision committed on save-line A (e.g. game X's battery save) can carry a `parent_revision_id` pointing at a revision that actually belongs to save-line B (e.g. a completely different game Y the same user owns). The server will accept this silently and journal it as legitimate lineage. Concretely:

- `Playstead.Saves.Branches.heads/2` computes "referenced parent ids" scoped to the *child's* `save_line_id` (`branches.ex:69-76`), so a cross-line parent is invisible to line B's own head computation — B's real head stays a head, while A's revision now points forever at a foreign line's revision as its "parent". Since revisions are immutable and append-only, this can never be corrected once committed.
- `SavesLive.ancestor_chain/2` and `since_split_count/3` (`saves_live.ex:154-172`) walk `parent_revision_id` assuming every ancestor stays on the same line; a cross-line parent silently pulls a different game's revision (and, transitively, its own ancestors) into "saves since the split" / common-ancestor computation for an unrelated game, producing nonsensical counts on the comparison sheet with no visible error.
- This is reachable by any authenticated device with a benign client bug (e.g. reusing a stale local `parent_revision_id` after switching games), not just a malicious actor, and once committed it is unrecoverable per the append-only design this phase is built around (D-09/D-11).

This does not delete or overwrite bytes, so it is not literal data loss, but it silently and permanently corrupts the provenance graph the whole feature (and D-50's "since the split" UI) depends on, with zero server-side guardrail.

**Fix:** In `resolve_parent/2`, once the line is resolved, also verify `parent.save_line_id == line.id` (this requires reordering so `resolve_parent` runs after — or is passed — the resolved `line`, which the `Ecto.Multi` already threads through `commit_outcome/9`). A parent belonging to a different line should be rejected the same way an unknown parent is (`{:error, {:save_parent_unknown, ...}}` or a new dedicated code), never silently accepted.

---

### CR-02: D-33's save-revision rate limit and save-lane upload concurrency are defined but never wired in — a paired device can commit/upload save revisions with no server-side throttle

**Files:**
- `playstead-server/lib/playstead/blobs.ex:198-236` — defines `max_save_revision_bytes/0` (enforced, see below), `save_revision_rate_limit_per_hour/0` (120/hour), `save_upload_slot_key/1` (`"save:" <> device_id` namespace), `save_revision_rate_limit_key/1`.
- `playstead-server/lib/playstead_web/router.ex:265-269` — the save-upload route's pipeline is `[:api, :device_auth, :repr_digest]` only; contrast with the imports upload route at `router.ex:174-178`, which additionally has `:idempotency, :upload_concurrency`.
- `playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex` — `create_revision/2` (the 120/hour-capped action per D-33) never calls `Playstead.RateLimiter.hit/3` or references `save_revision_rate_limit_key/1` anywhere.

**What is wrong:** I grepped the whole `lib/` tree for every caller of `save_revision_rate_limit_key/1`, `save_revision_rate_limit_per_hour/0`, and `save_upload_slot_key/1`: none exist outside their own definitions in `blobs.ex`. This is dead, never-invoked plumbing. Concretely:

1. **No rate limit at all** on `POST /api/v1/saves/revisions`. D-33 names "120 revisions/hour/device, reusing Phase 2's shipped upload-limit machinery" as a server cap; nothing enforces it.
2. **No concurrency cap** on `PUT /api/v1/saves/uploads/:command_id` — the route omits `:upload_concurrency` entirely (unlike the structurally identical imports route). Even if the shared `PlaysteadWeb.Plugs.UploadConcurrency` plug were added to this route, it keys `UploadSlots.acquire(device.id, ...)` on the bare `device.id` (`upload_concurrency.ex:26-28`), not the `"save:" <> device_id` namespaced key `Blobs.save_upload_slot_key/1` was clearly written to provide — so a save upload in flight would consume the *same* 2-slot budget as a concurrent ROM import for that device, which is the opposite of D-33's explicit "namespaced ... under a `save:` key" requirement and D-32's "dedicated save-only upload lane."

**Why it matters:** A single compromised or misbehaving paired device can commit unlimited save revisions per hour (each up to 8 MiB, and — per D-28 — kept forever, never pruned) and can run unlimited concurrent save uploads. The per-user backstops (`revision_count_backstop`/`storage_bytes_backstop` in `saves.ex:41-42`) are attention-only by design (never refuse), so the *only* thing standing between an abusive/buggy device and unbounded storage growth was supposed to be this rate limit — and it isn't there. This is exactly the kind of "treat uploads ... as untrusted; use validation, quotas, bounded workers" gap the project's own AGENTS.md names as a hard constraint.

**Fix:** Add `Playstead.RateLimiter.hit(Blobs.save_revision_rate_limit_key(device.id), <window>, Blobs.save_revision_rate_limit_per_hour())` inside `SavesController.create_revision/2` (or `Saves.commit_revision/3`) before committing, returning `rate_limited` (429, already registered) on breach. Add `:upload_concurrency` (or a save-specific variant keyed on `Blobs.save_upload_slot_key/1`) to the save-upload route's pipeline in `router.ex`.

---

## Warnings

### WR-01: "Keep both" acknowledgment is derived from the change journal, which is compacted at 90 days — D-52's "never re-raised" promise silently breaks after that horizon

**Files:** `playstead-server/lib/playstead/saves.ex:587-603` (`fork_acknowledged?/3`), `playstead-server/lib/playstead/sync/compaction.ex:38-46` (`Compaction.run/0`).

**What is wrong:** `acknowledge_divergence/3` ("Keep both") writes only a synthetic `fork_acknowledged` marker into the change journal (`Playstead.Sync.Entry`, via `ChangeJournal.append/4`) — deliberately never into `save_revisions`/`save_revision_parents` (the moduledoc at `saves.ex:436-443` explains why). `needs_divergence_decision?/2` calls `fork_acknowledged?/3`, which re-derives "was this exact head-set already acknowledged?" by querying `Entry` for the most recent `fork_acknowledged` entry on that line (`saves.ex:590-603`) — with no time bound.

`Playstead.Sync.Compaction.run/0` unconditionally deletes every `Entry` row older than `horizon/0` (floor 90 days), regardless of `entity_kind` (`compaction.ex:38-46`: `from(e in Entry, where: e.inserted_at < ^cutoff) |> Repo.delete_all()`).

**Why it matters:** Once a `fork_acknowledged` entry is older than the compaction horizon and gets deleted, `fork_acknowledged?/3` finds nothing, returns `false`, and `needs_divergence_decision?/2` flips back to `true` for a fork the user explicitly dismissed with "Keep both" months earlier. The next commit on that line (`after_commit_attention/2` in `saves.ex:300-309`) — or any other caller of `needs_divergence_decision?/2`, including `SavesLive.load_diverged_lines/1` — will silently re-raise the `divergence` attention item and put "Two versions of your progress" back in front of the user for a fork they already resolved. This is the *exact* event-horizon mistake D-17 explicitly called out and solved for revision lineage ("journal-only lineage would have a 90-day event horizon") — but the acknowledgment marker itself was put in the one place D-17 says not to put durable saves state, with no equivalent fix. No data is lost, but the locked, explicitly-decided D-52 promise ("never re-raised for that fork") is provably false past 90 days.

**Fix:** Either give the acknowledgment marker a durable, non-journal home (e.g. a small `save_fork_acknowledgments` table keyed by `(save_line_id, head_ids_hash)`, mirroring why lineage itself isn't journal-only), or exempt `entity_kind == "save"` `fork_acknowledged` entries from `Compaction.run/0`.

### WR-02: N+1 query pattern in the comparison sheet's "saves since the split" computation

**File:** `playstead-server/lib/playstead_web/live/saves_live.ex:154-172` (`since_split_count/3`, `ancestor_chain/2`).

**What is wrong:** For every side rendered in the comparison sheet, `ancestor_chain/2` walks `parent_revision_id` one hop at a time via `Stream.unfold`, issuing one `Saves.get_revision/2` (`Repo.get_by`) query per ancestor, per head. With N heads and a chain depth of D, this is O(N×D) individual database round-trips per page render.

**Why it matters:** D-28 is "keep every revision forever" with backstops at 100k revisions/user — chains on a long-lived save line can legitimately be long. This LiveView renders on every mount of `/saves/:id` and after every `choose`/`keep-both` action (`load_line/1` is called from `handle_event` too), so this cost is paid repeatedly, not just once. Explicitly named in this review's priorities as a class of defect to flag (N+1 in LiveView render paths).

**Fix:** Batch-load each side's full ancestor set with a single recursive CTE (or one `Repo.all` keyed on the line, then walk the in-memory map) instead of one query per hop per head.

### WR-03: Pending-upload row's `user_id` is not part of the conflict target — a colliding `command_id` from a different user overwrites the blob pointer but keeps the original owner (needs confirmation: low practical likelihood)

**File:** `playstead-server/lib/playstead/saves.ex:65-82` (`record_pending_upload/5`), `playstead-server/lib/playstead/saves/pending_upload.ex:17-19` (PK is `id` alone).

**What is wrong:** `save_pending_uploads` is keyed purely on `id` (the client-supplied `command_id`), and `record_pending_upload/5` upserts with `conflict_target: [:id]`, replacing only `[:blob_sha256, :size_bytes, :expires_at, :updated_at]` — never `user_id` or `device_id`. If two different users' devices ever submit the same `command_id` (client-generated UUIDv7; collision requires either a client bug reusing a fixed/predictable value or extraordinary bad luck), the second call silently overwrites the *first* user's row's blob pointer while the row keeps the *first* user's `user_id`. A subsequent `commit_revision/3` by user A (the original owner of that `command_id`) would then attach user B's uploaded bytes into user A's save history via `fetch_pending_upload/2`, since that lookup is scoped by `user_id` and finds the (now-mutated) row.

**Why it matters:** This is a cross-tenant data-integrity concern, not a currently-provable exploit — `command_id` is expected to carry enough entropy (UUIDv7) that an accidental collision is negligible, and a deliberate attacker would need another authenticated device to independently reuse the exact same value at the right moment. Flagging as a genuine design gap (no ownership check in the conflict target) rather than a proven vulnerability; I could not confirm exploitability within this review's scope.

**Fix:** Add `user_id` (and/or `device_id`) to `conflict_target`, or add an explicit `WHERE user_id = ...` guard / a changeset check that refuses to replace a pending upload owned by a different user.

### WR-04: `Save.create_changeset/2` does not bound or enumerate `save_kind`/`slot`, letting a line explosion bypass the per-line 32-head cap

**File:** `playstead-server/lib/playstead/saves/save.ex:27-37`.

**What is wrong:** `content_key` is regex-validated (64-hex), but `save_kind` and `slot` — both free-form client-supplied strings that participate in the save-line identity tuple `(user_id, content_key, save_kind, slot)` — have no `validate_inclusion`, no length bound, and no format check. D-10 says `save_kind` is `"battery"` only in v1.

**Why it matters:** `Saves.check_branch_cap/3` (`saves.ex:225-240`) enforces the 32-branch-head cap *per line*. Because `save_kind`/`slot` are unconstrained, a device can manufacture an unbounded number of distinct save lines for the same `content_key` (`"battery"`, `"battery2"`, `"battery3"`, ... or garbage `slot` values), each getting its own fresh 32-head allowance. The only backstop that still applies is the per-user aggregate `revision_count_backstop`/`storage_bytes_backstop` (`saves.ex:41-42`), which is attention-only (never refuses, per D-28) — so this doesn't cause data loss, but it does let the per-line cap be trivially sidestepped and compounds CR-02's missing rate limit.

**Fix:** `validate_inclusion(:save_kind, ["battery"])` for v1 (or whatever the adapter-declared contract's valid `save_kind` set is), and a reasonable length/format bound on `slot`.

### WR-05: Export worker crashes (rather than failing the export cleanly) if the source asset set is gone by job execution time

**File:** `playstead-server/lib/playstead/export/worker.ex:69-81` (`build_layout/1`), `playstead-server/lib/playstead/export.ex:63-84` (`to_layout_input/1`).

**What is wrong:** `build_layout/1` for `scope: "set"` calls `Export.fetch_asset_set(user_id, asset_set_id)`, which returns `nil` if the asset set no longer exists or is no longer owned by `user_id`. `Export.to_layout_input/1` pattern-matches only `%AssetSet{} = asset_set` in its function head, so `to_layout_input(nil)` raises `FunctionClauseError` inside the Oban job.

**Why it matters:** This crashes the export job (retried up to 5 times via `max_attempts: 5`, then discarded), leaving the `ExportRecord` permanently stuck in `status: "writing"` with no user-visible error and no path to `verification_failed` — a silent stuck state rather than a clean, reported failure. I could not find an asset-set deletion path in this phase's scope to confirm this is reachable today, so this is a defensive/robustness gap rather than a confirmed live bug — flagging because the failure mode (crash vs. a handled `{:error, ...}`) is a real gap regardless of current reachability.

**Fix:** Handle `nil` explicitly in `build_layout/1` and fail the export via `ExportRecord.verification_failed_changeset/2` (or a dedicated failed state) instead of letting the job crash.

---

## Info

### IN-01: `shared/save-vocabulary.json` and the shipped console copy both say "connect" where the locked copy table in `04-CONTEXT.md` says "sync" — plausibly a deliberate, correct fix, but undocumented as such

**Files:** `shared/save-vocabulary.json:89` (`"result.console_after_choosing"`), `playstead-server/lib/playstead_web/live/saves_live.ex:196`, vs. `.planning/phases/04-persistent-save-continuity/04-CONTEXT.md` line 237 ("Continuing from {Origin}. Your Macs will use this version the next time they **sync**.").

Both the shipped fixture and the LiveView consistently use "next time they **connect**" instead of the CONTEXT.md table's "sync" — which is actually correct given the vocabulary rules explicitly ban the word "sync" from every save surface (`04-CONTEXT.md`'s own "Banned from every save surface" list includes `sync`). This looks like the implementer correctly resolving a self-contradiction in the locked-copy source material, and it's applied consistently in both the fixture and the code (no cross-runtime drift). Flagging only because CONTEXT.md itself was not updated to reflect the correction, so a future reader diffing against it would see a false mismatch. No functional issue.

### IN-02: `Playstead.Saves.AttentionItem.bump_count_changeset/1` is dead code

**File:** `playstead-server/lib/playstead/saves/attention_item.ex:46-49`.

Never called anywhere; `AttentionSource.upsert/4` increments `count` at the `Repo.insert(on_conflict: [inc: [count: 1]], ...)` level instead. Mirrors the same unused function already present on `Playstead.Attention.Item` (pre-existing pattern, not introduced here) — harmless but should either be used or removed.

### IN-03: No independent re-verification of actual streamed bytes against `Blobs.max_save_revision_bytes/0`

**File:** `playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex:44-57` (`run_upload/3`).

The 8 MiB cap is enforced only against the client-*declared* `Content-Length` (`conn.assigns.declared_length`, set by `ReprDigest`) before streaming begins; nothing re-checks the actual cumulative bytes written by `Blobs.put_stream/3` against that same cap while streaming. In practice this is not exploitable today because the underlying HTTP adapter (Cowboy) reads exactly `Content-Length` bytes and no more, so a client cannot smuggle extra bytes past a small declared length — this is purely a defense-in-depth observation, not a live vulnerability as far as I could establish.

---

## What I looked at and found clean

- `Playstead.Saves.Branches.heads/2` correctly implements the role-aware retirement rule called out in the review brief: only `role: "chosen"` `RevisionParent` rows retire a parent from head status; `role: "acknowledged"` rows are deliberately excluded (`branches.ex:78-86`). This matches D-48/D-52 exactly and I could not find the "not role-aware" bug class described as a prior defect in this codebase's current state.
- `commit_revision/3`'s `Ecto.Multi` composition (line resolve-or-insert → advisory lock → blob-exists check → parent resolve → revision insert + journal append) is atomic as designed; I traced every branch and found no partial-commit path — a failure at any step rolls back the whole transaction, including the attention-source and backstop side effects in `after_commit_attention/2`, which run inside the same transaction.
- `resolve_divergence/4` and `acknowledge_divergence/3` are genuinely append-only: I found no code path that moves, deletes, or rewrites an existing `save_revisions`/`save_revision_parents` row.
- D-64's critical-reserve free-space floor (`Readiness.fits_critical_free_space?/2`, `LocalDisk.open_write/2`'s `reserve: :critical` branch) is wired correctly end-to-end from `SavesController.run_upload/3` through to the store adapter.
- Authorization: every save read/write path I checked (`Saves.get_history/2`, `SaveHistoryController.show/2`, `SavesLive`, `resolve_divergence/4`, `acknowledge_divergence/3`, `Export` calls reachable from `SavesLive.export_version/3`) scopes strictly by `user_id`, and a line outside the caller's scope returns `{:error, :not_found}` rather than a distinguishable "forbidden" — no tenancy hole found.
- Migrations are additive/forward-only, each has the indexes the CONTEXT document calls for (`(save_line_id, parent_revision_id)`, `(user_id)`, `(blob_sha256)`), and the `exports.saves_scope` backfill default (`"all"`) is safe for existing rows.
