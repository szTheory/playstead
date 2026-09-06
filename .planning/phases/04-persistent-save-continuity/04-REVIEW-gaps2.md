---
phase: 04-persistent-save-continuity
reviewed: 2026-09-06T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - playstead-server/lib/playstead/saves.ex
  - playstead-server/lib/playstead/saves/branches.ex
  - playstead-server/lib/playstead/export/saves_plan.ex
  - playstead-server/test/playstead/saves_test.exs
  - playstead-server/test/playstead/saves_branches_test.exs
  - playstead-server/test/playstead/export/round_trip_test.exs
  - playstead-server/test/playstead/export/saves_plan_test.exs
  - playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift
  - playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase 04: Code Review Report (gap-closure round 2)

**Reviewed:** 2026-09-06T00:00:00Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found (no blockers; one warning, two info items)

## Summary

Reviewed commits b0c20a1/595027f (plan 04-24, total-order revision
ordering) and b5dd235 (plan 04-25, `SaveOutboxDrainTrigger.fire()`
critical-section fix), plus the tests added alongside them. I traced
the actual `git diff` for each of the four production files rather than
trusting the surrounding prose, verified the ordering is a genuine
total order end to end, and checked the Swift fix against the exact
race it claims to close.

**Total-order revision ordering (04-24).** `saves.ex`'s `get_history/2`
and `saves/branches.ex`'s `heads/2` both changed their `order_by` from
`[asc: r.recorded_at]` to `[asc: r.recorded_at, asc: r.id]`, and
`export/saves_plan.ex` replaced `Enum.sort_by(& &1.recorded_at,
DateTime)` (stability-dependent, and therefore sensitive to caller
input order) with an explicit `order_key_lte?/2` comparator that
falls back to `a_id <= b_id` on a `recorded_at` tie. I confirmed the
three orderings agree with each other: `id` is `:binary_id` (Postgres
`uuid`) on the `save_revisions` table (`playstead-server/priv/repo/migrations/20260904000001_create_save_lines_and_revisions.exs:27`),
which loads through `Ecto.UUID` as a canonical lowercase 36-character
string; Postgres's `uuid` btree comparison is a raw big-endian byte
comparison of the 16 underlying bytes, which is order-equivalent to
ASCII/string comparison of that canonical lowercase hex representation
(hyphens sit at identical positions in both operands and hex-digit
ASCII order already matches nibble value order for `0-9a-f`). So the
DB-side `asc: r.id` and the pure `a_id <= b_id` string comparator in
`SavesPlan` produce the same order for the same revision set — a real,
not merely asserted, total order, and stable under append per D-59's
own stability argument (a fixed `{recorded_at, id}` key never changes
once assigned). The new tests in `saves_test.exs`,
`saves_branches_test.exs`, and `round_trip_test.exs` genuinely
construct the tie first (via `Repo.update_all` forcing two revisions to
an identical `recorded_at`, always committing the lexically-greater id
first so an unfixed single-key sort would return the wrong order) and
then assert the id-ascending resolution — these are not vacuous.
`saves_plan_test.exs`'s `plan/2 breaks a recorded_at tie...` test
additionally verifies input-order independence (`plan([lower,
greater]) == plan([greater, lower])`), which the old
`Enum.sort_by/3`-based implementation could not have guaranteed.

**`SaveOutboxDrainTrigger.fire()` critical section (04-25).** The diff
moved the `Task<Int, Never> { ... }` construction and the
`_drainCount`/`_lastTask` writes to sit between one
`lock.lock()`/`lock.unlock()` pair, and removed the previous
intermediate `lock.unlock()`/`lock.lock()` that let two concurrent
callers both read the same `_lastTask` as `previous` before either one
published its replacement. I traced through the closure capture: `Task
{ }`'s initializer only enqueues a job (it never runs its body
synchronously inside the initializer call), so building it while
`lock` is held introduces no reentrancy and cannot deadlock; the actual
`await previous?.value` only ever executes after `fire()` has returned
and released the lock. `awaitPending()` and the `drainCount` getter
correctly bracket their single reads of `_lastTask`/`_drainCount` with
the same lock. No queued drain pass can be dropped: every `fire()` call
still produces its own `Task` chained after whatever `_lastTask` was at
the moment its critical section ran, and the read-and-replace is now
indivisible.
`testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass` is a
genuine regression test for the exact race described in the docstring:
it releases two threads into `fire()` at the same instant via a
`DispatchSemaphore` barrier (not two sequential calls on one thread,
which — as the test's own comment notes — could never have exercised
the bug even under the old code, since a synchronous, non-async
function body can't interleave with itself on one thread) and asserts
`maxInFlight == 1` across 200 rounds. Under the pre-fix code, two
threads released simultaneously could both read `previous = nil`
before either published its own task, and both concurrently await
`saveOutbox.drainOnce`, producing `maxInFlight == 2` at least
occasionally — this test would have been flaky-but-failing before the
fix and is deterministic-passing after it.

I found no blocker-level defects in either change. The items below are
lower-severity robustness/coverage observations from the trace above.

## Warnings

### WR-01: `SavesPlan.plan/2`'s id tiebreaker silently assumes canonical-lowercase UUID strings, with nothing enforcing that at the module boundary

**File:** `playstead-server/lib/playstead/export/saves_plan.ex:99-105`
**Issue:** `order_key_lte?/2` breaks a `recorded_at` tie with `a_id <= b_id`, a plain Elixir string comparison. This only produces the same order as the database's `asc: r.id` (Postgres `uuid` byte comparison) because every current caller loads `revision.id` through `Ecto.UUID`, which always returns the canonical lowercase 36-character form. `SavesPlan` is documented as "pure" and takes plain maps (`@type revision_input`), with no validation on `:id`. If a future caller ever passes a non-canonical id string (e.g. uppercase hex, or a non-hyphenated 32-char form — both of which `Ecto.UUID.cast/1` would normalize but a hand-built map bypasses), the export's tie order would silently diverge from `Saves.get_history/2`'s and `Branches.heads/2`'s DB-side order, defeating the whole point of the D-59 stability guarantee for that one tied pair, with no runtime signal that anything went wrong.
**Fix:** Either normalize defensively inside the comparator (`String.downcase(a_id) <= String.downcase(b_id)`, or actually parse/re-render through `Ecto.UUID` if genuine non-canonical input is plausible), or add a doc/typespec note plus a test asserting the module raises or otherwise fails loudly on a non-canonical `:id` rather than silently reordering. A one-line test like `plan/2 raises (or normalizes) when given a non-canonical-case uuid id` would close the gap either way.

## Info

### IN-01: The concurrency regression test never asserts `drainCount`, leaving the counter's behavior under a genuine race unverified

**File:** `playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift:196-240`
**Issue:** `testConcurrentFireCallsFromSeparateThreadsNeverOverlapADrainPass` asserts `maxInFlight == 1` and `totalSent == rounds`, but never checks `trigger.drainCount`. `drainCount` was already incremented inside a lock in the pre-fix code too (the bug was specifically about `previous` being read outside the critical section, not about the counter), so this isn't evidence of a live defect — but it does mean the test suite has no assertion that a "started fire that's still in flight" and the counter genuinely stay in lockstep under real concurrent pressure, which is exactly the kind of guarantee a future refactor of `fire()` could break silently.
**Fix:** Add `XCTAssertEqual(trigger.drainCount, rounds * 2)` after the loop, alongside the existing `maxInFlight`/`totalSent` assertions.

### IN-02: `_lastTask` retains an unbroken chain of completed predecessor `Task` references

**File:** `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift:57-72`
**Issue:** Each new `Task`'s closure captures `previous` (the prior `_lastTask`), and that captured reference lives for the lifetime of the new task's closure, not just until `previous` completes. In the steady state this is harmless (each task is released once the next one supersedes it and finishes), but under a very high `fire()` call rate with slow completions, the reachable object graph momentarily includes the whole chain back to the first still-uncompleted task. This is a design tradeoff inherent to any "await your predecessor" serialization scheme, not a leak, and is explicitly out of the v1 performance-review scope — noted here only because it's a direct consequence of this diff's `previous` capture and worth a one-line doc comment if the team wants it recorded as an accepted tradeoff.
**Fix:** Optional: a comment noting the chain-retention tradeoff, or (if ever needed) hold a `weak`/manually-nilled reference cleared right after `await previous?.value` returns. Not required for correctness.

---

_Reviewed: 2026-09-06T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
