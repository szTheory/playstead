---
status: issues-found
phase: 04-persistent-save-continuity
depth: standard
files_in_scope: 78
files_reviewed: 56
critical: 2
warning: 11
info: 5
reviewed: 2026-09-04
---

# Phase 04 Code Review — Persistent Save Continuity

Merged from two parallel standard-depth reviews, split by runtime because 78 production
files (~16,000 lines) in a single reviewer context produces a skim rather than a review.
Full findings with line citations live in the two source documents:

- [`04-REVIEW-mac.md`](04-REVIEW-mac.md) — Swift/Mac, 0 critical / 6 warning / 2 info
- [`04-REVIEW-server.md`](04-REVIEW-server.md) — Elixir/server, 2 critical / 5 warning / 3 info

## Coverage — read this before trusting a "clean" reading

| Half | In scope | Fully reviewed | Not opened |
|---|---|---|---|
| Elixir / server | 36 | 36 | 0 |
| Swift / Mac | 42 | 20 | 22 |

The Mac pass prioritized the files load-bearing for save-data safety and **disclosed that
it did not open the remaining 22** (ConflictComparisonSheet, SaveHistorySheet, SaveRollup,
SaveStateModel, SaveVocabulary, SaveCaptureBlockedState, SaveAttentionSource, AdapterPin,
APIClient, Outbox, SyncEngine, the Readiness quartet, ReclaimPromptView, StatusSlotView,
StorageView, PlaysteadApp, UITesting/*). Those files are **unreviewed, not cleared.** Most
are presentation-layer and lower-risk, but that is an inference, not a finding.

## Critical

Both are server-side, both independently verified by the orchestrator against the source
before being recorded here.

### CR-01 — A parent revision is scoped to the user but not to the save line

`playstead-server/lib/playstead/saves.ex:164-174`. `resolve_parent/2` resolves a
client-submitted `parent_revision_id` with
`Repo.get_by(Revision, id: parent_revision_id, user_id: user_id)` — it confirms the parent
belongs to the *same user*, never that it belongs to the *same save line*. No database
constraint backstops it.

**What breaks:** a client can link one game's lineage to another game's revision. Because
history is append-only by design (D-48/D-49/D-52), the resulting provenance corruption is
**permanent and unrecoverable** — the mechanism that makes the DAG trustworthy is the same
mechanism that makes this unfixable. It also feeds bogus input to `SavesLive`'s
ancestor-chain and "since the split" logic.

**Fix:** scope the lookup to the target save line as well as the user, and add a matching
database constraint so the invariant is enforced where it cannot be bypassed.

### CR-02 — D-33's save rate limit and upload concurrency are defined but never applied

`playstead-server/lib/playstead/blobs.ex` defines `save_revision_rate_limit_per_hour/0`
(120), `save_revision_rate_limit_key/1`, `save_upload_slot_key/1` and
`max_save_revision_bytes/0`. Verified by full-tree grep: **every call site outside
`blobs.ex` is a test asserting the constants' names and values.** No production code path
invokes any of them. `router.ex:266` puts the save-upload route through
`[:api, :device_auth, :repr_digest]`, omitting the `:upload_concurrency` pipeline that the
structurally identical imports upload route at line 175 does use.

**What breaks:** a paired device can commit and upload save revisions with no server-side
throttle at all — no rate limit, no concurrency cap, no size ceiling enforced.

**Why it hid:** this is the same shape as WINDOWS #37, closed earlier today. The tests
prove the constants exist and are correctly named; nothing proves they are *reached*. A
green suite therefore reads as "D-33 is implemented" when D-33 is inert. 04-04 recorded
this as a deferral and it stayed unowned through nine subsequent plans.

**Fix:** invoke the limit helpers on the commit path, add `:upload_concurrency` to the
save-upload scope, and add a test that asserts a 121st revision in an hour is refused —
i.e. test the enforcement, not the constant.

## Warning — highest-signal items

Full list in the two source documents; these are the ones that touch save data.

- **WR-01 (Mac)** `JournalApplier.applySave` silently resets a self-authored revision's
  `tier`, `origin`, `manifestDigest`, `sessionID` and `artifactSetJSON` to defaults when the
  journal echoes it back, because `insertRevision`'s `ON CONFLICT DO UPDATE` writes every
  column and the applier does not preserve existing values. Can desync
  `SaveSessionRecovery`'s staged/promoted pairing — i.e. degrade crash recovery.
- **WR-02 (Mac)** `SaveCapturePoller.write()` uses remove-then-move rather than atomic
  `rename(2)` for the rolling `staged` file, reintroducing the exact non-atomic-overwrite
  hazard D-06/D-47 exist to prevent, and which plan 04-01's APFS probe was built to
  characterize. Mitigated by other recovery paths; still a regression against the file's own
  stated discipline.
- **WS-01 (server)** D-52's "keep both, never re-raised" guarantee is derived from the change
  journal via `Saves.fork_acknowledged?/3`, but `Playstead.Sync.Compaction.run/0`
  unconditionally deletes journal entries after 90 days regardless of entity kind. This is
  the event-horizon mistake D-17 explicitly solved for revision lineage, reintroduced for
  acknowledgment state: after 90 days a resolved fork can be re-raised at the user.
- **WS-02 (server)** N+1 query in the comparison sheet's "saves since the split" computation.
- **WS-03 (server)** Unbounded `save_kind`/`slot` values allow the per-line branch cap to be
  sidestepped.
- **WS-04 (server)** Pending-upload conflict-target gap.
- **WS-05 (server)** Unhandled crash path in the export worker if an asset set vanishes mid-job.

### Cross-runtime item worth resolving together

**WR-04 (Mac)** flags that `SaveUploadLane` mints a fresh `command_id` per retry of the same
revision's metadata commit, possibly defeating the idempotency the D-16 two-endpoint split
was designed to provide. The server review documents that the streamed upload route is
deliberately **off** the `:idempotency` pipeline (a stream cannot be fingerprinted) while the
metadata-commit route is **on** it. The two halves were reviewed independently and neither
could settle it alone. Flagged as needing confirmation, not asserted.

## Verified clean — stated explicitly, because absence of a finding is not proof

Both reviewers were asked to confirm the phase's load-bearing invariants rather than only
hunt for defects. These were traced and confirmed:

- **D-44's launch invariant holds.** Pure planner; diverged-check precedes ancestry; only a
  proven-ancestor fast-forward ever overwrites; the executor always re-hashes and never
  writes in place; a throw aborts the launch rather than spawning over a partial write.
- **D-65's per-`assetSetID` mutex** correctly spans prepare → spawn → exit.
- **D-63's backup-exclusion boundary** is correct — the five reconstructable dirs, never the
  root, never `saves/` or `playstead.sqlite3`.
- **`Branches.heads/2`'s role-aware retirement rule** is correct; `role: "acknowledged"`
  edges are properly excluded (this is the bug 04-05 caught and fixed mid-flight).
- **`commit_revision/3`'s `Ecto.Multi` is fully atomic** — partial commits are impossible.
- **Divergence resolution and acknowledgment are genuinely append-only.**
- **D-64's critical free-space reserve** is wired end to end.
- **Tenant scoping holds** across every save read/write path traced — with CR-01 the one
  exception, where the scope is present but too coarse.

## Recommended disposition

1. Fix **CR-01** and **CR-02** before this phase is marked complete. Both are enforcement
   gaps in code whose tests currently pass, which is precisely the failure mode this project
   has already been bitten by.
2. Fix **WR-01**, **WR-02** and **WS-01** — each is a concrete path to degraded save
   durability or a re-raised resolved conflict.
3. Resolve the **WR-04** idempotency question with both runtimes in view.
4. Either review the 22 unopened Mac files or record them as knowingly unreviewed.
