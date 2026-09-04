---
phase: 04-persistent-save-continuity
plan: 05
subsystem: sync
tags: [elixir, phoenix, ecto, postgres, cas, idempotency, journal, dag]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-04's Playstead.Saves bounded context (commit_revision/3, save_lines/save_revisions/save_pending_uploads), Playstead.Sync.SavePayload, the saves_controller, and the (save_line_id, parent_revision_id) index reserved for this plan"
provides:
  - "Playstead.Saves.RevisionParent + Playstead.Saves.Branches (heads/2, diverged?/2): a stored-nowhere, computed-every-time branch-head derivation over the revision DAG"
  - "Accept-and-branch commits: no fast-forward requirement anywhere in Saves.commit_revision/3, plus D-12's recorded base_sha256/base_matched evidence"
  - "The three loud commit caps (save_parent_unknown + Retry-After, save_branch_limit_exceeded, save_revision_immutable) and D-30's same-device confirm / different-device new-revision dedup rule"
  - "PlaysteadWeb.Api.V1.SaveHistoryController: read-only, user-scoped revisions + derived heads (GET /api/v1/saves/lines/:id/history)"
  - "Saves.resolve_divergence/4 and Saves.acknowledge_divergence/3: append-only, convergent, idempotent divergence resolution exposed via POST .../resolve and .../acknowledge"
affects: [04-06, 04-07, 04-09, 04-10, 04-11, 04-12]

actuals:
  tokens: 16229
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A derived-not-stored DAG head: Branches.heads/2 recomputes from parent_revision_id + role-filtered RevisionParent rows on every call, inside the caller's ambient transaction, so 'no automatic winner' and 'never a torn read' both hold by construction rather than by an invariant someone has to remember to maintain"
    - "role-differentiated parent edges: a role: \"chosen\" edge retires its parent from head status exactly like an ordinary single-parent commit; a role: \"acknowledged\" edge is audit trail only and leaves its revision a live head -- this is what gives a resolution's non-chosen side a permanent 'Continue from this one' affordance without a second table or a status column"
    - "A journal-only marker outside the revision DAG (fork_acknowledged) for state that must never retire a head -- any save_revision_parents row unconditionally disqualifies its parent from Branches.heads/2, so 'keep both' cannot be represented as a DAG edge at all"

key-files:
  created:
    - playstead-server/priv/repo/migrations/20260904000002_add_save_lineage_fields_and_parents.exs
    - playstead-server/lib/playstead/saves/revision_parent.ex
    - playstead-server/lib/playstead/saves/branches.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/save_history_controller.ex
    - playstead-server/test/playstead/saves_branches_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs
  modified:
    - playstead-server/lib/playstead/saves.ex
    - playstead-server/lib/playstead/saves/revision.ex
    - playstead-server/lib/playstead/sync/save_payload.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/fallback_controller.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/test/playstead/saves_test.exs

key-decisions:
  - "Branches.heads/2 only retires a revision via the plain parent_revision_id column or a role: \"chosen\" RevisionParent row; a role: \"acknowledged\" row never retires its parent. Without this, resolving a fork would silently make the non-chosen side vanish as a head the instant resolution lands, breaking D-49's permanent 'Continue from this one' affordance and the independent-arrival-order convergence property D-48 requires -- found and fixed during task 3's TDD cycle, not spelled out in the plan's action text."
  - "'Keep both' (acknowledge_divergence/3) is a ChangeJournal marker entry (type: fork_acknowledged), never a save_revision_parents row -- any row in that table disqualifies its parent from head status, so acknowledging inside the DAG structure was structurally impossible without breaking 'heads stay heads' (D-52). No new migration/table was in this task's declared file set, so the existing append-only journal is the correct home for this fact."
  - "D-30's same-device dedup check compares the incoming blob digest and origin device against the *named parent* (what the client asserts as its base), not some server-chosen 'current head' -- this keeps the rule well-defined even mid-divergence, where a line can have more than one head."
  - "The branch-cap check and the accept-or-confirm decision run inside a per-line pg_advisory_xact_lock (P5-WR-001 shape, mirroring Curation), so a concurrent commit on the same line serializes behind whichever request acquires the lock first instead of racing a stale head count."
  - "An id-conflict on Repo.insert (an attempt to overwrite a committed revision) is classified via a changeset unique_constraint(:id, ...) into save_revision_immutable, distinct from a generic 422 validation failure."

patterns-established:
  - "Any table shaped like RevisionParent (child-references-multiple-parents) that feeds a computed-status derivation must decide per-role whether a given edge type participates in that derivation -- documented explicitly in Branches' moduledoc so a future edge role does not accidentally retire something it shouldn't."

requirements-completed: [SAVE-04]

coverage:
  - id: D1
    description: "The server accepts and branches a non-fast-forward commit -- two commits naming the same parent, or a second root, both succeed and both land as heads; there is no fast-forward requirement anywhere in the commit path (D-13)"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_branches_test.exs (7 tests, pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every revision records base_sha256 and a derived base_matched boolean; a mismatch is recorded and the commit still succeeds (D-12), and every ordering is by server recorded_at, never a device-claimed time (D-15)"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_branches_test.exs (base evidence + ordering describe blocks, pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The three loud commit caps: save_parent_unknown (409 + Retry-After, retried transparently), save_branch_limit_exceeded at 32 heads, save_revision_immutable on any attempt to modify a committed revision"
    requirement: "SAVE-04"
    verification:
      - kind: integration
        ref: "playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs (pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-30's dedup invariant: a same-device byte-identical capture bumps confirm_count/last_confirmed_at with no new revision; a different-device byte-identical capture inserts a new revision sharing the blob"
    requirement: "SAVE-04"
    verification:
      - kind: integration
        ref: "playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs (2 tests, pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "GET .../history returns a line's revisions and derived heads, scoped by user_id; a cross-user line read is 404, never 403"
    requirement: "SAVE-04"
    verification:
      - kind: integration
        ref: "playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs (2 tests, pass)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Choosing a side appends one resolution revision naming every divergent head as a parent (one chosen, the rest acknowledged), moves no head pointer, and deletes nothing; the resolution's blob is the chosen side's bytes and adds zero new CAS bytes"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_test.exs (3 tests, pass)"
        status: pass
    human_judgment: false
  - id: D7
    description: "N-way divergence resolves in a single act; two independent resolutions of the same fork (in either arrival order) converge to equal retained-revision sets with no compare-and-swap race; replaying the same idempotency key appends no second resolution revision"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_test.exs (3 tests, pass)"
        status: pass
    human_judgment: false
  - id: D8
    description: "'Keep both' leaves every head standing and marks the fork acknowledged so it is never re-raised as needing a decision, while its heads remain heads"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_test.exs (2 tests, pass)"
        status: pass
    human_judgment: false

duration: 70min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 5: Revision DAG, Commit Invariants, and Append-Only Resolution Summary

**The revision DAG is now complete and load-bearing: accept-and-branch commits with recorded base evidence, a computed-not-stored branch-head derivation, the three loud commit caps plus D-30's confirm/new-revision dedup, a read-only history endpoint, and an append-only divergence-resolution path where "keep both" is a first-class outcome that never removes a head.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-09-04T23:30:00Z
- **Completed:** 2026-09-04T00:40:00Z (see git commit timestamps for exact wall-clock)
- **Tasks:** 3
- **Files modified:** 13 (6 created, 7 modified)

## Accomplishments

- `Playstead.Saves.Branches.heads/2` derives branch heads from the DAG itself on every call, inside the caller's ambient transaction, so a concurrent commit can never be observed as a torn mix of before/after and there is nowhere for a stored "head pointer" to disagree with reality (D-14)
- `Saves.commit_revision/3` now records `base_sha256`/`base_matched` (D-12), never rejects a non-fast-forward commit (D-13), enforces the three loud caps (`save_parent_unknown` + `Retry-After`, `save_branch_limit_exceeded`, `save_revision_immutable`), and implements D-30's same-device-confirms/different-device-branches dedup rule, all inside a per-line advisory-locked transaction
- `PlaysteadWeb.Api.V1.SaveHistoryController` exposes a read-only, user-scoped revisions + derived-heads view; an out-of-scope line is 404, never a distinguishing 403
- `Saves.resolve_divergence/4` appends one CAS-deduped resolution revision naming every divergent head (one `chosen`, the rest `acknowledged`) and `Saves.acknowledge_divergence/3` appends a journal-only "keep both" marker that never touches the DAG -- both exposed as idempotent `POST` commits under `SavesController`
- Found and fixed a real design gap before it shipped: `Branches.heads/2`'s original (task 1) retirement rule treated *any* `RevisionParent` reference as retiring, which would have made a resolution's non-chosen side vanish as a head the instant resolution landed -- fixed by making only `role: "chosen"` edges retire, exactly matching D-49's permanent "Continue from this one" promise

## Task Commits

1. **Task 1: Lineage fields, accept-and-branch, and derived branch heads** - `35224cb` (feat, tdd)
2. **Task 2: Commit invariants, caps, and the read-only history endpoint** - `8f56f00` (feat, tdd)
3. **Task 3: Append-only divergence resolution** - `2297f1e` (feat, tdd)

## Files Created/Modified

- `playstead-server/priv/repo/migrations/20260904000002_add_save_lineage_fields_and_parents.exs` - Lineage/clock-evidence columns on `save_revisions`; the `save_revision_parents` join table
- `playstead-server/lib/playstead/saves/revision_parent.ex` - The N-way parent-edge schema (`role`: `chosen`/`acknowledged`)
- `playstead-server/lib/playstead/saves/branches.ex` - `heads/2`, `diverged?/2`: the computed, role-aware branch-head derivation
- `playstead-server/lib/playstead/saves/revision.ex` - New provenance/clock-evidence/confirm fields; `unique_constraint(:id, ...)` for immutability classification
- `playstead-server/lib/playstead/saves.ex` - `commit_revision/3` extended with base evidence, caps, dedup, and the advisory lock; new `get_history/2`, `resolve_divergence/4`, `acknowledge_divergence/3`, `needs_divergence_decision?/2`
- `playstead-server/lib/playstead/sync/save_payload.ex` - Additive frozen keys for the new provenance/clock-evidence fields (D-17)
- `playstead-server/lib/playstead_web/controllers/api/v1/save_history_controller.ex` - The read-only history endpoint
- `playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex` - `resolve_divergence/2`, `acknowledge_divergence/2` actions
- `playstead-server/lib/playstead_web/controllers/api/v1/fallback_controller.ex` - `save_parent_unknown` clause carrying `Retry-After`
- `playstead-server/lib/playstead_web/router.ex` - History/resolve/acknowledge routes
- `playstead-server/test/playstead/saves_branches_test.exs` - 7 tests: accept-and-branch, heads, base evidence, ordering
- `playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs` - 8 tests: history, 404 scoping, caps, dedup, backstops
- `playstead-server/test/playstead/saves_test.exs` - Extended: 3 context-level invariant tests (task 2) + 8 divergence-resolution tests (task 3)

## Decisions Made

See `key-decisions` in frontmatter -- five decisions, most notably the role-aware head-retirement fix (found during task 3's TDD cycle) and the choice to represent "keep both" as a journal marker rather than a DAG edge, since no DAG edge can exist without retiring its parent from head status.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Branches.heads/2`'s original retirement rule would have broken D-48/D-49 the instant a fork was resolved**
- **Found during:** Task 3 (writing the "two devices resolve the same fork independently" test)
- **Issue:** Task 1's `Branches.heads/2` treated any `save_revision_parents` reference (any role) as retiring a revision from head status. Once task 3's `resolve_divergence/4` inserted a `RevisionParent` row for every divergent head (one `chosen`, the rest `acknowledged`), the *non-chosen* heads would have been retired too -- vanishing as heads the moment a fork was resolved. This directly contradicts D-49 ("the non-chosen version stays on screen with a live 'Continue from this one' button, permanently") and would have broken the independent-arrival-order convergence property, since a second, differently-choosing resolution would find its target head already gone.
- **Fix:** `Branches.heads/2` now retires a revision only via the plain `parent_revision_id` column or a `role: "chosen"` join row; a `role: "acknowledged"` row is audit trail only and never retires its parent.
- **Files modified:** `playstead-server/lib/playstead/saves/branches.ex` (also reworded a doc comment that tripped the `winner`/`preferred_side`/`auto_resolve`/`pick_side` acceptance grep purely by using the phrase "no automatic winner" in prose describing D-14's *absence* of such a rule -- reworded without changing meaning)
- **Verification:** `saves_test.exs`'s "two devices resolving the same fork independently in both arrival orders" test, plus the unchanged `saves_branches_test.exs` suite (7/7 still pass)
- **Committed in:** `2297f1e` (Task 3 commit)

### Noted, Not Fixed

**2. [Acceptance-criterion false positive] The task 2 grep for `def delete_revision|def prune|def purge|ttl` also flags a pre-existing, unrelated constant**
- **Found during:** Task 2's acceptance-criteria verification pass
- **Issue:** `grep -rniE 'def delete_revision|def prune|def purge|ttl' playstead-server/lib/playstead/saves.ex` matches `@pending_upload_ttl_seconds` and its one use site -- both written in plan 04-04, governing the D-16 upload-pointer's TTL, not revision retention. No delete/prune/purge function exists in this file.
- **Resolution:** Left as-is. Renaming an accurately-named, pre-existing constant purely to satisfy an overly broad regex would reduce clarity for a genuinely different concept (upload-pointer expiry vs. revision retention) and risks touching code outside this plan's task 2 scope for no functional benefit.
- **Impact:** None on correctness -- confirmed by direct inspection that no delete/prune/purge path exists anywhere in `saves.ex`.

---

**Total deviations:** 1 auto-fixed (1 bug, found via TDD before it shipped), 1 documented acceptance-criterion false positive (no code change).
**Impact on plan:** The bug fix is what makes D-48/D-49's "permanent Continue from this one" promise and the independent-resolution convergence property actually true; without it this plan would have shipped a resolution flow that silently violated its own must-have truths on the very next fork.

## Issues Encountered

None beyond the deviation above.

## Known Stubs

None. `acknowledge_divergence/3`'s journal marker is not yet consumed by any client-facing surface (console or Mac) -- that wiring is explicitly out of scope for this server-only plan and belongs to plans 04-10 (console) and 04-11 (Mac conflict resolver), per this plan's own `key_links`.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers. T-04-05-01 through T-04-05-07 are all mitigated as designed: accept-and-branch (never a silent-loss rejection), `save_revision_immutable` on any mutation attempt, strict `user_id` scoping with 404-not-403 on the history endpoint, the 32-head branch cap, the accepted per-user growth backstop (D-28), `recorded_at`-only ordering, and the no-compare-and-swap resolution append verified by the both-arrival-orders test.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The revision DAG, its derived branch heads, and the append-only resolution path are now the structural foundation every later divergence-facing surface (console, Mac conflict resolver) builds on
- `Saves.needs_divergence_decision?/2` is ready for plan 04-10's saves-owned attention source to consume without needing to re-derive acknowledgment logic
- `resolve_divergence/4`/`acknowledge_divergence/3`'s shapes are exactly what plans 04-10 (console) and 04-11 (Mac) both append through, per this plan's `key_links`
- Per-user backstop constants (`Saves.revision_count_backstop/0`, `Saves.storage_bytes_backstop/0`) are defined and documented but intentionally not wired to any surfacing yet -- that is plan 04-10's job
- Ready for 04-06.

## Self-Check: PASSED

- `[ -f playstead-server/priv/repo/migrations/20260904000002_add_save_lineage_fields_and_parents.exs ]` -> FOUND
- `[ -f playstead-server/lib/playstead/saves/revision_parent.ex ]` -> FOUND
- `[ -f playstead-server/lib/playstead/saves/branches.ex ]` -> FOUND
- `[ -f playstead-server/lib/playstead_web/controllers/api/v1/save_history_controller.ex ]` -> FOUND
- `[ -f playstead-server/test/playstead/saves_branches_test.exs ]` -> FOUND
- `[ -f playstead-server/test/playstead_web/controllers/api/v1/save_history_controller_test.exs ]` -> FOUND
- `git log --oneline --all | grep -q 35224cb` -> FOUND
- `git log --oneline --all | grep -q 8f56f00` -> FOUND
- `git log --oneline --all | grep -q 2297f1e` -> FOUND
- `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_test.exs test/playstead/saves_branches_test.exs test/playstead_web/controllers/api/v1/save_history_controller_test.exs` -> PASS (30 tests, 0 failures)
- `cd playstead-server && MIX_ENV=test mix test` (full suite) -> PASS (933 tests, 0 failures; baseline was 907 before this plan)
- Acceptance-criteria greps for task 1 (recorded_at ordering, no fast-forward vocabulary) -> PASS
- Acceptance-criteria grep for task 2 (no delete/prune/purge) -> PASS with one documented pre-existing false positive (see Deviations)
- Acceptance-criteria grep for task 3 (no winner/preferred_side/auto_resolve/pick_side vocabulary) -> PASS (after the doc-comment reword recorded above)

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*
