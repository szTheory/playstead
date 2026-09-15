---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-15T16:10:00Z
status: human_needed
score: 5/5 roadmap truths verified (SC5's controller-hardware portion present+wired, not behaviorally exercised — unchanged, routed to human verification); WR-07 tie window CLOSED; two architectural residues remain; one new migration defect (WR-08)
behavior_unverified: 1
overrides_applied: 0
covered_files:
  - ".planning/REQUIREMENTS.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-01-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-01-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-02-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-02-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-03-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-03-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-04-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-04-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-05-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-05-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-06-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-06-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-07-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-07-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-08-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-08-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-09-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-09-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-10-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-10-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-11-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-11-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-12-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-12-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-13-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-13-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-14-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-14-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-15-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-15-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-16-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-16-SUMMARY.md"
  - "playstead-mac/Playstead/App/PlaysteadApp.swift"
  - "playstead-mac/Playstead/Cache/AvailabilityReporter.swift"
  - "playstead-mac/Playstead/Persistence/Migrations.swift"
  - "playstead-mac/Playstead/Sync/Outbox.swift"
  - "playstead-mac/Playstead/Sync/OutboxWorker.swift"
  - "playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift"
  - "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
covered_digest: "v1:sha256:96c4cdbe43cc4ee4f3ab7b20bfe8100e85a3faa03c6b146e510f4a23614ff0a3"
re_verification:
  previous_status: "human_needed (one open gap: WR-07, narrowed twice)"
  previous_score: "5/5 roadmap truths; WR-07 partial"
  gaps_closed:
    - "WR-07 residue 1, THE TIE WINDOW: CLOSED at 711f866. `created_at` is second-granularity, so it could not answer a total-order question; the key changed rather than the comparison. `outbox_entries.enqueue_seq` is assigned inside `enqueue`'s existing transaction as one past the greatest of (max live `enqueue_seq`, max `delivered_seq`), and BOTH supersede checks now compare on it. Verified by falsification rather than by trusting the commit: flattening the sequence subquery to the literal `1` fails all three supersede tests — `…ArrivedMeanwhile` (:482,:483,:484), `…AlreadySucceeded` (:519,:520) and the inverted tie test `test_aRetrySharingTheDeliveredReportsTimestampIsStillDroppedAsOlder` (:549,:550) — while the new kind-scoping test keeps passing. Restored byte-exact; 25/25 green at HEAD. The inverted tie test is genuine: it asserts `first.createdAt == second.createdAt` as an explicit premise and still requires the newer report to win."
    - "The decision to reject `(created_at, rowid)` — which my previous report offered as the cheaper option — is CORRECT, and I verified the justification rather than accepting it. SQLite reclaims the rowid of a deleted row when the table has no AUTOINCREMENT, and it reclaims downward when the top rows go: inserting 5 rows, deleting rowid 5 then rowid 4, then inserting, yields rowid 4 for the NEW row. Against a watermark of 5 that new row reads as older and is wrongly dropped — a sporadic wrong-drop, strictly worse than the tie window it would replace. The heavier dedicated sequence was the right call."
  gaps_remaining:
    - "WR-07 residues 2 and 3 (architectural, unchanged, not introduced by any of the three fixes): a late-succeeding in-flight request lands after a newer one and cannot be prevented client-side; and a newer row retired by `markRejected` or quarantine is invisible to both checks. Neither is closable in `Outbox` alone."
    - "WR-08 (NEW this round, found by this verification, not reported by the commit): the defensive migration for the previous watermark schema does not work. A database that already holds the 47ac7b6-era `outbox_delivered_watermark (kind, created_at NOT NULL)` keeps that table — `CREATE TABLE IF NOT EXISTS` is a no-op — and the new INSERT omits `created_at`, so every `markDone` for an availability report throws SQLITE_CONSTRAINT."
  regressions: []
overrides: []
gaps:
  - truth: "03-16-PLAN.md must-have: \"Only the newest full-replacement availability report is ever delivered: enqueuing a new one removes any still-pending or backed-off one, so a backed-off earlier report can no longer land after a later one that already succeeded.\""
    status: partial
    reason: "The ordering question is now genuinely settled — residue 1, the tie window I measured last round, is CLOSED by `enqueue_seq` (see re_verification.gaps_closed for the falsification evidence). TWO residues remain, both architectural and neither introduced by any of the three fixes. (2) A LATE-SUCCEEDING IN-FLIGHT REQUEST. If A is on the wire, B is delivered meanwhile, and A's request then SUCCEEDS, `markDone(A)` correctly leaves the watermark at B (MAX) and deletes the row — but A has already landed on the server AFTER B. No client-side guard can prevent this: A was sent before B existed. Only a server-side monotonic guard closes it, and `Availability.replace_for_device/2` still has none (blind full replacement, re-confirmed by direct read). (3) A NEWER ROW RETIRED WITHOUT BEING DELIVERED. `markRejected` moves a row to `rejected`; exhausting `maxAttempts` moves it to `quarantined`. Neither state is live for `hasNewerLiveEntry`, and neither writes a watermark — correctly, since neither is a delivery. So an older row can be revived and delivered while a newer one sits rejected or quarantined. This does not violate the sentence's final clause (nothing newer succeeded) but does violate its leading clause. Reachability is very low. Disposition unchanged across all four rounds: narrow, self-correcting on the next successful `syncNow()` pass, no permanent data corruption, no trust boundary crossed, no roadmap truth contradicted — a tracked, NON-BLOCKING warning. The client-side half of the sentence is now true; the leading clause cannot be made true in `Outbox` alone."
    artifacts:
      - path: "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
        issue: "`replace_for_device/2` is a blind full replacement with no report ordering/monotonic guard, so nothing server-side rejects a stale report the client could not prevent sending."
    missing:
      - "A server-side monotonic guard on `PUT /api/v1/devices/me/availability` (ignore a report older than the last accepted one for that device). This is the only place residue 2 can be closed at all."
      - "If residues 2 and 3 are instead accepted as permanent limitations, record them in .planning/WINDOWS.md — they are currently described only inside code comments covering the closed halves."
  - truth: "A client that already ran the previous build can still deliver an availability report (implied by the WR-07 fix being effective at all on an existing install)."
    status: failed
    reason: "WR-08, found by this verification and NOT reported by the commit. The `try? ALTER TABLE outbox_delivered_watermark ADD COLUMN delivered_seq ...` is written specifically to upgrade a database holding the 47ac7b6-era schema, and it does not do the job — it half-does it, which is worse than not trying, because the schema then LOOKS migrated. Proven in sqlite3 against the exact statements, not argued: given the old table `(kind TEXT PRIMARY KEY, created_at TEXT NOT NULL)`, `CREATE TABLE IF NOT EXISTS` is a no-op so the stale `created_at NOT NULL` column survives; the ALTER does add `delivered_seq INTEGER NOT NULL DEFAULT 0`, so the column the question asks about IS present; but `recordDeliveredWatermark`'s `INSERT INTO outbox_delivered_watermark (kind, delivered_seq) SELECT ...` omits `created_at`, which is NOT NULL with no default, and fails with `NOT NULL constraint failed: outbox_delivered_watermark.created_at (19)`. `Migrations.run` is called on every `LocalStore` open with no `user_version` gate (grep: 0 occurrences), so this is the steady-state path for such a database, not a one-shot. The consequence is not a silent no-op: `recordDeliveredWatermark` runs inside `markDone`'s transaction, so the throw rolls the transaction back, the delivered row is NOT deleted, and `markDone` throws out to `OutboxWorker.drainOnce`, where a SQLite error is not an `APIClientError` and lands in the generic `catch` — which calls `markPendingForRetry` and sets `stoppedForRetry`. A delivery that SUCCEEDED is therefore treated as a transport failure: the report is re-sent on every retry, `onEntryDelivered` fires again each time, and after `maxAttempts` the entry is quarantined. On such a database the entire WR-07 fix is inert and availability reports never clear the outbox. Blast radius is genuinely narrow — only a database created or migrated by the 47ac7b6 build, which existed for about 18 minutes and was never released, so in practice the author's own dev machine — and fresh installs are unaffected. But note WHY the 25/25 green cannot see it: `OutboxTests.setUpWithError` builds a fresh `LocalStore` in a fresh temp directory for every test, so the suite only ever exercises the new schema. This defect is structurally invisible to the test suite as written."
    artifacts:
      - path: "playstead-mac/Playstead/Persistence/Migrations.swift"
        issue: "`CREATE TABLE IF NOT EXISTS outbox_delivered_watermark (kind, delivered_seq)` plus `try? ALTER ... ADD COLUMN delivered_seq` leaves a pre-existing `created_at TEXT NOT NULL` column in place with no default, which the new INSERT never populates."
      - path: "playstead-mac/Playstead/Sync/Outbox.swift"
        issue: "`recordDeliveredWatermark` inserts only `(kind, delivered_seq)`; on a stale table this throws inside `markDone`'s transaction and is then misclassified by `drainOnce` as a transport failure."
    missing:
      - "Drop and recreate the watermark table when its schema is the old one. The watermark is a pure hint that is legitimately reconstructible as empty — losing it fails OPEN (an entry is retried rather than wrongly dropped), so `DROP TABLE IF EXISTS outbox_delivered_watermark` before the CREATE is both safe and simplest. Recreating-and-copying is unnecessary."
    
behavior_unverified_items:
  - truth: "A user can connect, test, assign, remap, reset, and recover a controller (roadmap SC #5, controller-hardware portion)"
    test: "Connect a real, paired physical game controller; disconnect it mid-session; reconnect it."
    expected: "Connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without requiring a relaunch — matching what ControllerHost's unit tests already prove against an injectable ControllerInputSource."
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 recorded this as FAIL/unproven and 03-10-SUMMARY.md's D1 rationale states the same. Code is present and wired; only real-hardware behavior is unexercised. Unchanged by 847165b/97b1358/47ac7b6, regression-checked."
human_verification:
  - test: "Physical game controller connect/disconnect/reconnect recovery, live input test, remap, and reset on real hardware"
    expected: "Controller lifecycle logic behaves identically against a real device as it does against the injectable simulated input source in unit tests."
    why_human: "No physical or paired controller hardware exists in this execution environment. Reconciled against 03-UAT.md items 8 and 9 (both blocked_by: physical-device) and item 10's blocked sub-record. Carried forward unchanged."
  - test: "Full end-to-end launch of the pinned mGBA adapter against a live paired server, with a downloaded game and installed emulator, from the notarized build, driven by a live interactive display session"
    expected: "Play starts the emulator, the game runs, SRAM periodically flushes, quitting returns to the library, and Gatekeeper accepts the app without any user override (this last part is proven — see 03-NOTARIZATION-EVIDENCE.md)."
    why_human: "This execution environment cannot render a live interactive display session for a human to watch a game actually run. Reconciled against 03-UAT.md item 7. Carried forward unchanged."
  - test: "Visual/typographic fidelity and VoiceOver walkthrough of the LiveView console and the Mac library shell against 03-UI-SPEC.md"
    expected: "Spacing, color rendering, motion timing, and screen-reader sentence flow match the locked design contract on both surfaces."
    why_human: "Only the markup-level/logic-level accessibility contract was automatically verified; no live NSAccessibility tree or interactive rendering was exercised. Reconciled against 03-UAT.md item 10's blocked sub-record. Carried forward unchanged."
  - test: "Drag-in BIOS validation against a real, legally-sourced BIOS file or supported open replacement"
    expected: "A correct BIOS file is accepted and stored under managed storage; an incorrect one is rejected with a clear reason."
    why_human: "No real BIOS file exists in this execution environment, and none should. Reconciled against 03-UAT.md item 13 (result: partial, blocked_by: legally-owned-artifact-required). Carried forward unchanged."
  - test: "LIBR-05's remaining human-judgment UX review item and PLAY-04's physical controller hardware requirement"
    expected: "N/A — tracked for completeness; both requirement IDs stay Pending in REQUIREMENTS.md by explicit scope fence."
    why_human: "PLAY-04 is the same hardware-blocked item above; LIBR-05's remaining scope is a human UX judgment call. Confirmed both still `Pending` at REQUIREMENTS.md lines 137 and 145."
---

# Phase 3: Mac Offline Play Vertical Slice Verification Report

**Phase Goal:** Let a paired Mac browse, selectively cache, preflight, and launch one proven adapter path offline.
**Verified:** 2026-09-15T16:10:00Z (HEAD `4c59dc0`; relevant code commit `711f866`)
**Status:** human_needed
**Re-verification:** Yes — fourth independent pass on WR-07, adjudicating `711f866` (the monotonic-sequence fix) after `47ac7b6` (the delivered watermark) and `847165b` (the live-row check). Everything outside WR-07 was re-checked and stands.

## Verdict: the tie window is CLOSED; a new migration defect (WR-08) is open

Round 3 on WR-07. You asked me to assume this round has something wrong with it too. It does — but not in the ordering logic, which is now right.

### The tie window is genuinely closed

`enqueue_seq` replaces `created_at` as the supersede key, assigned inside `enqueue`'s existing transaction as one past the greatest of (max live `enqueue_seq`, max `delivered_seq`). Both supersede checks compare on it; the watermark stores it.

**Falsified, not trusted.** Flattening the sequence subquery to the literal `1` fails all three supersede tests on their own lines — `…ArrivedMeanwhile` (:482, :483, :484), `…AlreadySucceeded` (:519, :520), and the inverted tie test (:549, :550) — while the new kind-scoping test keeps passing. 25/25 green at HEAD, restored byte-exact.

The inverted tie test is honest: it asserts `first.createdAt == second.createdAt` as an explicit premise and still demands the newer report win. (I initially misread its diff as omitting the `markInFlight` calls and suspected the arithmetic was wrong; reading the file at HEAD showed the calls are there and the test is sound. Recording that because I nearly reported a false finding.)

### Your reasoning for rejecting `(created_at, rowid)` is correct — I checked it

This mattered, since it justified the heavier change, and my previous report had offered `(created_at, rowid)` as an option. Your reasoning holds, and I confirmed it empirically rather than by reading the docs: SQLite reclaims rowids of deleted rows without `AUTOINCREMENT`, and reclaims *downward* as the top rows go. Inserting 5 rows, deleting rowid 5 then rowid 4, then inserting again yields rowid **4** for the new row. Against a stored watermark of 5 that new row reads as older and is wrongly dropped — a sporadic wrong-drop, strictly worse than the tie window it would have replaced. Declining that option was right; the dedicated sequence was the correct call.

### Your four other questions, answered

**Is `enqueue_seq` monotonic under every removal path?** Not globally — and that is fine, though your comment overstates it. Sequences *are* reused. Two paths retire the highest row without raising the watermark: `enqueue`'s own supersede DELETE (which runs before the INSERT's subquery is evaluated, so the new row can take the just-deleted row's number), and `markDone` for a **non-superseding** kind, which deletes without writing any watermark. So "one past the highest value ANY live row or watermark has **ever** held" is not true — it is one past the highest value currently held.

But the invariant that correctness needs does hold. Every comparison the code performs is against either a live row (`hasNewerLiveEntry`) or the watermark (`deliveredWatermark`), and **both terms are inside the MAX**, so a new sequence is strictly greater than everything it will ever be compared against, and no two *live* rows can share a sequence. A reused number only ever duplicates a row that no longer exists and was never delivered as a superseding kind. So: yes, it collides with an already-used number; no, that collision is never observable. Answering your specific worry — `enqueue`'s supersede deleting the highest live row with no delivery having happened does reuse that number, harmlessly.

**Can the backfill collide?** No. `UPDATE outbox_entries SET enqueue_seq = rowid WHERE enqueue_seq = 0` gives pre-existing rows their rowid; every subsequent `enqueue` takes `MAX(...) + 1`, which exceeds `MAX(rowid)`. And since `enqueue` can never assign 0 (both terms are `COALESCE`d to 0 and the expression is `+ 1`, verified in sqlite3 to yield 1 on empty tables), the re-running backfill can never clobber a real value on a later launch.

**`INSERT ... SELECT` with a missing row?** Correct. Verified in sqlite3: the SELECT yields no rows, so nothing is inserted and no error is raised — matching the previous `nil` behaviour. It is also guarded by `if let delivered` upstream.

**Does anything still compare `created_at` where it should compare the sequence?** The supersede path is fully converted — no `created_at` comparison remains in `isSupersededForRetry` or `hasNewerLiveEntry`. `listPending`/`listAll`/`listRejected`/`listQuarantined` still *order* by `created_at ASC, rowid ASC`. I checked whether that is now a defect and it is not: SQLite reclaims only the maximum rowid, so a new row's rowid is always ≥ every live row's, making `rowid ASC` a valid tiebreaker **over live rows** even though it is unsafe against a stored watermark. So the drain order is still correct. Advisory only: `enqueue_seq ASC` would be simpler and provably right, and would leave one ordering key in the module instead of two.

### WR-08 — the new defect: the defensive migration does not work

The `try? ALTER TABLE outbox_delivered_watermark ADD COLUMN delivered_seq ...` exists specifically to upgrade a database holding the 47ac7b6-era schema. It half-works, which is worse than not trying, because the schema then *looks* migrated.

Proven in sqlite3 against the exact statements, not argued:

```
CREATE TABLE outbox_delivered_watermark (kind TEXT PRIMARY KEY, created_at TEXT NOT NULL);  -- the old DB
CREATE TABLE IF NOT EXISTS ... (kind, delivered_seq INTEGER NOT NULL);                       -- no-op
ALTER TABLE outbox_delivered_watermark ADD COLUMN delivered_seq INTEGER NOT NULL DEFAULT 0;  -- succeeds
-- resulting schema: (kind TEXT PRIMARY KEY, created_at TEXT NOT NULL, delivered_seq INTEGER NOT NULL DEFAULT 0)
INSERT INTO outbox_delivered_watermark (kind, delivered_seq) SELECT ... ;
Error: stepping, NOT NULL constraint failed: outbox_delivered_watermark.created_at (19)
```

So the literal answer to your question — "does such a database end up with a usable `delivered_seq`?" — is: the **column** is there, the **table** is unwritable. The stale `created_at NOT NULL` has no default and the new INSERT never populates it. `Migrations.run` is called on every `LocalStore` open with no `user_version` gate (grep: 0 occurrences), so this is the steady state for such a database, not a one-shot.

**The consequence is not a silent no-op.** `recordDeliveredWatermark` runs inside `markDone`'s transaction, so the throw rolls it back and the delivered row is *not* deleted. `markDone` then throws out to `OutboxWorker.drainOnce`, where a SQLite error is not an `APIClientError` and falls into the generic `catch` — which calls `markPendingForRetry` and sets `stoppedForRetry`. A delivery that **succeeded** is therefore treated as a transport failure: the report is re-sent on every retry, `onEntryDelivered` fires again each time, and after `maxAttempts` the entry is quarantined. On such a database the entire WR-07 fix is inert and availability reports never clear the outbox.

**Blast radius is genuinely narrow** — only a database created or migrated by the 47ac7b6 build, which existed for roughly 18 minutes and was never released; in practice your own dev machine. Fresh installs are unaffected. But note *why* 25/25 green cannot see it: `OutboxTests.setUpWithError` builds a fresh `LocalStore` in a fresh temp directory for every test, so the suite only ever exercises the new schema. **This defect is structurally invisible to the test suite as written** — which is the same shape as the reasoning error in each previous round, just relocated from the comparison to the schema.

The fix is smaller than the bug: the watermark is a pure hint, legitimately reconstructible as empty, and losing it fails **open** (an entry is retried rather than wrongly dropped). `DROP TABLE IF EXISTS outbox_delivered_watermark` before the `CREATE` is safe and sufficient; no copy-forward is needed.

### What remains of WR-07 itself

Residues 2 and 3 are unchanged and architectural, closable in neither `Outbox` nor this round: a late-succeeding in-flight request lands after a newer one (only a server-side monotonic guard can close it; `replace_for_device/2` still has none), and a newer row retired by `markRejected` or quarantine is invisible to both checks. Disposition unchanged across all four rounds — tracked, non-blocking. The client-side ordering half of the must-have is now true; the leading clause cannot be made true in `Outbox` alone.

### A note on the compromised local evidence

I did not run the full Unit layer, so WINDOWS #88 did not arise and nothing in this report depends on it. Every result cited here comes from `OutboxTests` (which you correctly identify as unaffected — it spawns no child processes), from sqlite3 run directly against the migration statements, or from source reads. I have not cited the 702/697 figures or hosted CI.

## Regression Re-checks (by source read, not by reading the prior verification)

| Prior finding | Status | Evidence re-derived |
|---|---|---|
| **LIBR-02** (`missing_dependency` structurally unreachable) | ✓ STILL CLOSED | `AvailabilityReporter.buildEntries` computes `missingDependency = !requiredSHAs.isEmpty && hasOrphanedRequiredMember && hasEngaged` from real CAS/queue/pin state. `grep -c 'missingDependency: false'` (comments stripped) → `0`. `grep -c 'replace_for_device(\|%DeviceReport{' library_availability_e2e_test.exs` → `0`. Untouched by `47ac7b6`. |
| **WR-04** (malformed `entries` → 500) | ✓ STILL CLOSED | `do_replace/2` retains the `is_list` clause + `Enum.all?(entries, &is_map/1)` + catch-all through `action_fallback`; absent-key default and `:too_many_entries` branch intact. |
| **WR-05** (enqueue-time newest-wins supersede) | ✓ STILL CLOSED | `Outbox.enqueue` still deletes `kind = ? AND state = 'pending'` inside the insert transaction; all four supersede tests pass in the 24/24 run. |
| **847165b live-row check** | ✓ STILL LOAD-BEARING | Both `…ArrivedMeanwhile` and `…NothingNewerArrived` still pass with the watermark clause disabled, confirming the two clauses are independent and neither masks the other. |

`97b1358` touches `OutboxWorker.swift` only to add `OutboxDrainResult.failureClassification`; creation-order draining, the stop-on-first-retry rule, the WR-01 markInFlight-failure stop, and the permanent-rejection branch are unchanged. No regression.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | Unchanged; LIBR-02 re-confirmed closed above. |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | Unchanged; `AvailabilityState.derive` untouched by all three commits on this head. |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; launch only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | Unchanged. |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ✓ VERIFIED | Unchanged. |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a signed/notarized build after app or server restart | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (controller-hardware portion) / ✓ VERIFIED (notarization portion) | Unchanged; routed to human verification. |

**Score:** 5/5 roadmap truths verified or appropriately routed; 1 present-but-behavior-unverified. WR-07 is a sub-requirement-level must-have from 03-16-PLAN.md, not a roadmap SC, and is tracked in `gaps`.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Persistence/Migrations.swift` | Durable store for the delivered fact + a total order to compare on | ✗ DEFECTIVE (WR-08) | `enqueue_seq` column, backfill and index are all correct. The watermark table's upgrade path is not: `CREATE TABLE IF NOT EXISTS` no-ops on a 47ac7b6-era database and the `try? ALTER` leaves a stale `created_at NOT NULL` with no default, making the table unwritable. Proven in sqlite3. |
| `playstead-mac/Playstead/Sync/Outbox.swift` | Newest-wins supersede across the full entry lifecycle | ⚠️ PARTIAL | Enqueue-time, live-newer and delivered-newer cases implemented, atomic and tested, now on a total order that resolves the tie window. Residues 2/3 remain (architectural); `recordDeliveredWatermark` also throws on a stale schema — see WR-08. |
| `playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift` | Fail-first coverage of all three WR-07 rounds | ⚠️ PARTIAL | 25/25 at HEAD; the inverted tie test and the kind-scoping test are both genuine and load-bearing. But every test builds a fresh `LocalStore` in a fresh temp dir, so no test can exercise a schema upgrade — WR-08 is structurally invisible to this suite. |
| `playstead-mac/Playstead/App/PlaysteadApp.swift` | Comments that do not assert false serialization | ✓ VERIFIED | Both `drainOutbox` and `drainSaveUploads` now state entry/revision-level non-racing without claiming serialization, and point at `Outbox` as the component that must be correct across reentrancy. |
| `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` | Real, non-constant `missing_dependency` signal | ✓ VERIFIED | Re-confirmed; 0 hardcoded literals in executable code. |
| `playstead-server/.../availability_controller.ex` | 422 shape guard on malformed `entries` | ✓ VERIFIED (WR-04) | Guard intact. Noted: still no report-ordering guard, which is why residue 2 has no server-side mitigation. |
| `.planning/REQUIREMENTS.md` | Authoritative requirement traceability | ✓ VERIFIED | Untouched; LIBR-05 (line 137) and PLAY-04 (line 145) still correctly `Pending`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `CurationIntentKind.availabilityReport` → `Outbox.enqueue` | at-most-one-pending-row | `supersedesPending` scoped delete | ✓ WIRED | Unchanged, tested. |
| `Outbox.markDone` → `outbox_delivered_watermark` | the delivered fact outlives the row | single transaction, `INSERT…SELECT` + `MAX` upsert | ⚠️ PARTIAL | Correct on a fresh schema (missing-row case verified safe in sqlite3); throws SQLITE_CONSTRAINT on a 47ac7b6-era schema — WR-08. |
| `Outbox.markPendingForRetry` → `isSupersededForRetry` | drop a superseded revived row | live-row check OR watermark check, both on `enqueue_seq` | ✓ WIRED | Both clauses independently load-bearing; the tie window is closed — flattening the sequence to a constant fails all three supersede tests. |
| `Outbox.onEnqueue` → `OutboxWorker.drainOnce` | post-enqueue drain | `OutboxDrainTrigger.fire()` → `Task { await … }` | ✓ WIRED | PlaysteadApp.swift:648. Still the wiring that makes the reentrancy window reachable; now documented accurately. |
| `AvailabilityReporter.buildEntries` → `missing_dependency` chip | HTTP-driven, no read-model seeding | shared fixture → real controller → LiveView | ✓ WIRED | Re-confirmed by grep (0 bypasses). |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full `OutboxTests` at HEAD `4c59dc0` | `xcodebuild test … -only-testing:PlaysteadTests/OutboxTests` | 25 tests, 0 failures | ✓ PASS |
| `enqueue_seq` is load-bearing (falsification) | sequence subquery → literal `1` | 25 tests, 7 failures across all three supersede tests (:482,:483,:484,:519,:520,:549,:550) | ✓ PASS (fails as required) |
| Total order does not over-reach across kinds | same falsified run | kind-scoping test passed | ✓ PASS |
| `(created_at, rowid)` really is unsafe (justification check) | sqlite3: insert 5, delete rowid 5 then 4, insert | new row got rowid **4** — below a watermark of 5 | ✓ PASS (rejecting rowid was correct) |
| Watermark upgrade path on a 47ac7b6-era DB | sqlite3: old table → CREATE IF NOT EXISTS → ALTER → new INSERT | `NOT NULL constraint failed: outbox_delivered_watermark.created_at (19)` | ✗ FAIL — WR-08 |
| `INSERT…SELECT` with a missing row | sqlite3, fresh schema | exit 0, 0 rows inserted, no error | ✓ PASS |
| Sequence expression on empty tables | sqlite3 `MAX(COALESCE(…),COALESCE(…)) + 1` | `1` — never NULL | ✓ PASS |
| Migration re-runs every open (no version gate) | `grep -c user_version Migrations.swift` | `0` | ✓ PASS (confirms WR-08 is steady-state) |
| Byte-exact restore after the probe | `shasum -a 256`, `git status --short` | match; tree clean apart from this report | ✓ PASS |
| Debt-marker scan (TBD/FIXME/XXX) on all files in `711f866` | `grep -nE` | no matches | ✓ PASS |

Per project convention, every probe restore was done by copying back a saved byte-exact backup, never by `git checkout`.

### Requirements Coverage

All 15 phase requirement IDs accounted for against REQUIREMENTS.md.

| Requirement | Status | Evidence |
|---|---|---|
| LIBR-01 | ✓ SATISFIED | Line 133 Complete. Unchanged. |
| LIBR-02 | ✓ SATISFIED | Line 134 Complete. Re-confirmed closed by direct read. |
| LIBR-03 | ✓ SATISFIED | Line 135 Complete. Unchanged. |
| LIBR-04 | ✓ SATISFIED | Line 136 Complete. Unchanged. |
| LIBR-05 | ? NEEDS HUMAN | Line 137 Pending. Human UX judgment; explicit scope fence. |
| CACH-01 | ✓ SATISFIED | Line 138 Complete. Unchanged. |
| CACH-02 | ✓ SATISFIED | Line 139 Complete. Unchanged. |
| CACH-03 | ✓ SATISFIED | Line 140 Complete. Unchanged. |
| CACH-04 | ✓ SATISFIED | Line 141 Complete. Unchanged. |
| PLAY-01 | ✓ SATISFIED | Line 142 Complete. Unchanged. |
| PLAY-02 | ✓ SATISFIED | Line 143 Complete. Unchanged. |
| PLAY-03 | ✓ SATISFIED | Line 144 Complete. Real-BIOS acceptance remains human-gated (03-UAT.md item 13). |
| PLAY-04 | ? NEEDS HUMAN | Line 145 Pending. Physical controller hardware. |
| PLAY-05 | ✓ SATISFIED | Line 146 Complete. Live interactive launch remains human-gated (03-UAT.md item 7). |
| QUAL-01 | ✓ SATISFIED | Line 155 Complete. Live VoiceOver/visual walkthrough remains human-gated. |

No orphaned requirement IDs.

### Anti-Patterns Found

None in the files modified by the three commits on this head. No `TBD`/`FIXME`/`XXX` markers.

ℹ️ Info (pre-existing, unchanged): `markPendingForRetry` remains the only path from `in_flight` back to `pending`, so a process crash while a row is `in_flight` strands it with no startup recovery sweep — neither retried nor superseded. Out of scope for this gap, but a durable watermark plus a startup sweep would address both together.

### Note on evidence provenance

The `OutboxTests` runs, the falsification of the watermark clause, and the tie probe were all executed by this verification directly and are first-hand results. The reported full local Unit layer (702 tests / 0 failures) was **not** re-run here and is not load-bearing for any verdict above. Hosted CI for `47ac7b6` was not consulted. The intermittent live-server failures tracked as WINDOWS #70/#71/#87 are deliberately **not** attributed to any phase 03 requirement.

### Gaps Summary

Two gaps. **WR-07's ordering question is settled.** `711f866` closes the tie window I measured last round by replacing the key rather than the comparison, and I confirmed the sequence is load-bearing by falsification and confirmed — empirically, in sqlite3 — that your reason for rejecting `(created_at, rowid)` was correct rather than merely plausible. What remains of WR-07 is two architectural residues that `Outbox` cannot close: a late-succeeding in-flight request, and a newer row retired by rejection or quarantine. The first wants a server-side monotonic guard; both want a WINDOWS.md entry if they are to be accepted instead.

**WR-08 is new and mine, not the commit's.** The defensive migration for the previous watermark schema does not work: `CREATE TABLE IF NOT EXISTS` no-ops on an existing table and the `try? ALTER` leaves a stale `created_at NOT NULL` with no default, so every `markDone` for an availability report throws, is misread by `drainOnce` as a transport failure, and quarantines a report that already succeeded. Blast radius is one unreleased build's databases, but the test suite cannot see it at all — every test starts from a fresh store. `DROP TABLE IF EXISTS` before the `CREATE` is a safe and sufficient fix, since the watermark is a reconstructible hint whose loss fails open.

Four human verification items carry forward unchanged: physical controller hardware, a live interactive emulator launch session, a live VoiceOver/visual walkthrough, and real BIOS bytes.

---

_Verified: 2026-09-15T16:10:00Z at HEAD 4c59dc0_
_Verifier: Claude (gsd-verifier) — fourth independent pass on WR-07; no source files modified (working tree clean, probe file restored byte-exact)_
