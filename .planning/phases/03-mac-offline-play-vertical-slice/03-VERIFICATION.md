---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-15T15:05:00Z
status: human_needed
score: 5/5 roadmap truths verified (SC5's controller-hardware portion present+wired, not behaviorally exercised — unchanged, routed to human verification); WR-07 narrowed twice, still not fully closed
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
covered_digest: "v1:sha256:78c6cda6cb5e127ee0cf7b8e03fb7fcb9fdcdbba1b7294d86b7c5baf83771a25"
re_verification:
  previous_status: "human_needed (one open gap: WR-07, narrowed by 847165b)"
  previous_score: "5/5 roadmap truths; WR-07 partial"
  gaps_closed:
    - "WR-07 residue found at 847165b (a newer report that had ALREADY SUCCEEDED was invisible to the guard, because `markDone` deletes the delivered row): CLOSED at 47ac7b6. The delivered fact now outlives the row in `outbox_delivered_watermark`, written by `markDone` inside the same transaction as the DELETE, and consulted by `markPendingForRetry` via `isSupersededForRetry`. Verified independently by falsification, not by trusting the commit: replacing only the two watermark lines with `return false` fails `test_anInFlightReportRevertedForRetryIsDroppedWhenTheNewerReportAlreadySucceeded` at OutboxTests.swift:519 with exactly (\"1\") is not equal to (\"0\") and at :520, while the tie test and BOTH live-row tests keep passing — so the watermark clause is load-bearing and is not merely duplicating the live-row check. Restored byte-exact; 24/24 green at HEAD."
  gaps_remaining:
    - "WR-07 (narrowed a second time, still open): `created_at` is second-granularity, so \"newer\" is a partial order and the watermark cannot resolve a tie. Proven at HEAD, not argued: two enqueues 0.8s apart collapse to the identical `created_at` string, and in that window a stale report stays deliverable after a newer one already succeeded. The new tie test pins this as intended behavior, so it is a deliberate trade, not an oversight — but the must-have sentence is still false inside a one-second window."
  regressions: []
overrides: []
gaps:
  - truth: "03-16-PLAN.md must-have: \"Only the newest full-replacement availability report is ever delivered: enqueuing a new one removes any still-pending or backed-off one, so a backed-off earlier report can no longer land after a later one that already succeeded.\""
    status: partial
    reason: "Narrowed substantially and correctly a second time by 47ac7b6, but still not the sentence as literally worded. THREE residues remain, in descending order of reachability. (1) THE TIE WINDOW. `Outbox.enqueue` stamps `created_at` with `ISO8601DateFormatter()`, which has no fractional seconds. Proven at HEAD by probe, not by inspection: two enqueues at genuinely distinct instants 0.8s apart both produce `2023-11-14T22:13:20Z` (probe clause A failed: \"(\\\"2023-11-14T22:13:20Z\\\") is equal to (\\\"2023-11-14T22:13:20Z\\\")\"). Because `isSupersededForRetry` compares `entry.createdAt < watermark` strictly, an older report whose `created_at` merely TIES the delivered watermark is revived and stays deliverable after the newer one already succeeded (probe clause B failed at the same run). `test_aRetryWhoseCreatedAtTiesTheDeliveredWatermarkIsStillRetried` pins exactly this as intended. The strictness itself is the RIGHT call given the data available — non-strict would drop a delivery nothing newer actually replaced, a worse failure — so this is not a wrong comparison, it is a comparison made over a key that cannot express the ordering it is being asked about. The codebase already maintains the total order that would resolve it: `listPending` and `hasNewerLiveEntry` both order by `created_at ASC, rowid ASC`, explicitly acknowledging that ties occur. The watermark discards the `rowid` half of that order. Storing a monotonic sequence (or `(created_at, rowid)`) instead of `created_at` alone would let the drop test and the tie test both pass with no trade. (2) AN IN-FLIGHT REQUEST THAT SUCCEEDS LATE. If A is on the wire, B is delivered meanwhile, and A's request then SUCCEEDS, `markDone(A)` records `MAX` (watermark stays at B, correct) and deletes the row — but A has already landed on the server AFTER B. No client-side guard can prevent this; the request was sent before B existed. Only a server-side monotonic guard closes it, and `Availability.replace_for_device/2` has none (blind full replacement, re-confirmed by direct read). This residue is architectural and pre-existing, not introduced by either fix. (3) A NEWER ROW RETIRED WITHOUT BEING DELIVERED. `markRejected` moves a row to `rejected` and quarantine moves it to `quarantined`; neither state is `live` for `hasNewerLiveEntry` and neither writes a watermark (correctly — neither is a delivery). So an older row can be revived and delivered while a newer one sits rejected/quarantined. This does not violate the sentence's final clause (nothing newer succeeded) but does violate its leading clause, \"only the newest ... is ever delivered\". Reachability is very low: quarantine needs 8 failed attempts while the older row stays in flight throughout. Disposition unchanged and deliberately consistent with both prior rounds: narrow, self-correcting on the next successful `syncNow()` pass, no permanent data corruption, no trust boundary crossed, does not contradict any roadmap-level truth — a tracked, NON-BLOCKING warning. But the sentence is not yet true as written, and this verification again does not round that up."
    artifacts:
      - path: "playstead-mac/Playstead/Sync/Outbox.swift"
        issue: "`isSupersededForRetry` (lines 298-307) compares second-granularity `created_at` strings, so it cannot distinguish \"older\" from \"same second\". Ties inside a one-second window fall through to revival. The watermark table stores `created_at` only, discarding the `rowid` tiebreaker the sibling ordering queries already rely on."
      - path: "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
        issue: "`replace_for_device/2` is a blind full replacement with no report ordering/monotonic guard, so nothing server-side rejects a stale report that the client could not prevent sending."
    missing:
      - "Store a total order in `outbox_delivered_watermark` — a monotonic sequence assigned at enqueue, or `(created_at, rowid)` — and compare against that instead of `created_at` alone. This is the one change that would let the drop test and the tie test both hold, closing residue (1) with no trade."
      - "For residue (2), a server-side monotonic guard on `PUT /api/v1/devices/me/availability` (ignore a report older than the last accepted one for that device). This is the only place it can be closed at all."
      - "If residues (2) and (3) are instead accepted as permanent limitations, record them in .planning/WINDOWS.md — they are currently described only inside code comments covering the closed halves."
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
**Verified:** 2026-09-15T15:05:00Z (HEAD `47ac7b6`)
**Status:** human_needed
**Re-verification:** Yes — third independent pass on WR-07, adjudicating commit `47ac7b6` (the delivered-watermark fix) after `847165b` (the live-row fix). Everything outside WR-07 was re-checked and stands.

## Verdict on WR-07: the residue I found is CLOSED; the must-have is still not true as written

### What `47ac7b6` genuinely closes

The residue I reported at `847165b` — a newer report that had **already succeeded** was invisible, because `markDone` deletes the delivered row — is properly fixed. The delivered fact now outlives the row:

- `Migrations.swift` adds `outbox_delivered_watermark (kind TEXT PRIMARY KEY, created_at TEXT NOT NULL)`. One row per kind, so it cannot grow.
- `markDone` reads the row, then inside **one** `localStore.transaction` writes the watermark (for a `supersedesPending` kind) and deletes the row.
- `recordDeliveredWatermark` upserts with `ON CONFLICT(kind) DO UPDATE SET created_at = MAX(created_at, excluded.created_at)` — SQLite's two-argument scalar `max()`, so the watermark only ever rises. Correct, and necessary: deliveries genuinely can complete out of creation order.
- `isSupersededForRetry` returns true on **either** a strictly newer live row (the old check) **or** `entry.createdAt < deliveredWatermark(ofKind:)`.

**I verified this by falsification rather than by reading the commit message.** Replacing only the two watermark lines with `return false` fails the new test on its own lines, with exactly the signature reported:

```
OutboxTests.swift:519: ("1") is not equal to ("0") - a stale older report must not be delivered after the newer one already succeeded
OutboxTests.swift:520: XCTAssertTrue failed - and no backoff window may deliver it later either
```

while `test_aRetryWhoseCreatedAtTiesTheDeliveredWatermarkIsStillRetried` and **both** live-row tests (`…ArrivedMeanwhile`, `…NothingNewerArrived`) kept passing. That is the important part: the watermark clause is doing work the live-row clause does not, and it is not over-reaching into cases the other tests own. Restored byte-exact; 24/24 green at HEAD.

**On the specific mechanics you asked me to check:**

- **Is the transaction atomic with respect to the DELETE?** Yes. The upsert and the DELETE are both inside the same `localStore.transaction` closure, so the watermark can never be recorded without the row being dropped, nor the row dropped without the watermark. The *read* (`rows(where: "id = ?")`) is outside the transaction, which is benign: the only paths that delete a row are `markDone` itself, `enqueue`'s supersede (scoped to `state = 'pending'`, and this row is `in_flight`), and `markPendingForRetry`'s own drop (which targets the entry being reverted). None can race this row, and a stale read could only ever record a `created_at` that was genuinely delivered.
- **Missing row?** `delivered` is `nil`, so no watermark is written and the DELETE no-ops. Correct — a watermark is never invented for a row that does not exist.
- **Can a watermark row exist while the corresponding entry was never delivered?** No. `recordDeliveredWatermark` has exactly one caller (Outbox.swift:206), inside `markDone`'s transaction, using the delivered row's own `created_at`. Grep-confirmed.
- **The corrected comments** in `drainOutbox`/`drainSaveUploads` now state the reentrancy fact accurately: overlapping passes never race the same *entry* (because `markInFlight` precedes the `await`), but they are not serialized. That was the belief the defect rested on, and it is properly retired.

### What is still not true

**Residue 1 — the tie window. This is the one that matters, and you were right to suspect the trade.**

`Outbox.enqueue` stamps `created_at` with `ISO8601DateFormatter()`, which emits no fractional seconds. I probed this at HEAD rather than assuming it:

```
OutboxTests.swift:553: XCTAssertNotEqual failed: ("2023-11-14T22:13:20Z") is equal to ("2023-11-14T22:13:20Z")
  - PROBE-A: two distinct instants 0.8s apart must not collapse to the same created_at
OutboxTests.swift:562: XCTAssertTrue failed
  - PROBE-B: the stale report must not stay deliverable after the newer one already succeeded
```

Two enqueues at genuinely distinct wall-clock instants **0.8 seconds apart** produce the identical `created_at` string — so ties are not a test artifact produced by passing the same `Date` twice, they arise from ordinary sub-second-apart enqueues. And inside that window the stale report is revived and stays deliverable after the newer one already succeeded. That is the must-have's final clause, still false.

**Your strict comparison is the right call, and it is still not enough.** Non-strict would drop a delivery that nothing newer actually replaced — a worse failure, and `test_aRetryWhoseCreatedAtTiesTheDeliveredWatermarkIsStillRetried` correctly forbids it. So you did not choose wrongly between two options; both options are lossy, because `created_at` at second granularity is a **partial** order and you are asking it a total-order question. You have not traded one gap for another so much as hit the floor of what this key can answer.

The way out is already in the codebase: `listPending` and `hasNewerLiveEntry` both order by `created_at ASC, rowid ASC` — the code already knows ties happen and already carries a tiebreaker. The watermark stores `created_at` alone and discards it. Storing a monotonic sequence (assigned at enqueue) or `(created_at, rowid)` would make "newer" exact, and the drop test and the tie test would both pass with no trade at all.

**Residue 2 — an in-flight request that succeeds late.** If A is on the wire, B is delivered meanwhile, and A's request then *succeeds*, `markDone(A)` correctly leaves the watermark at B (`MAX`) and deletes the row — but A has already landed on the server **after** B. No client-side guard can prevent this: A was sent before B existed. Only a server-side monotonic guard closes it, and `Availability.replace_for_device/2` has none (blind full replacement, re-confirmed by direct read of the controller). This is architectural and pre-existing, introduced by neither fix — but it is why the sentence's leading clause, "only the newest ... is ever delivered", cannot be made true client-side alone.

**Residue 3 — a newer row retired without being delivered.** `markRejected` moves a row to `rejected`; exhausting `maxAttempts` moves it to `quarantined`. Neither state is live for `hasNewerLiveEntry`, and neither writes a watermark — correctly, since neither is a delivery. So an older row can be revived and delivered while a newer one sits rejected or quarantined. This does not violate the "already succeeded" clause (nothing newer succeeded), only the leading clause. Reachability is very low — quarantine needs 8 failed attempts while the older row stays in flight throughout — so I record it rather than press it.

### Disposition

The fix is real, correctly scoped, atomic, and load-bearing, and it closes the exact residue I reported. It is **still narrower than the must-have sentence**, and I am saying so plainly for the third time rather than rounding up because the previous finding was addressed.

Severity is unchanged across all three rounds: narrow, self-correcting on the next successful `syncNow()` pass, no permanent data corruption, no trust boundary crossed, no roadmap truth contradicted. Same disposition — an open, tracked, **non-blocking** warning, so the phase is not regressed to `gaps_found` for it. Residue 1 is the only one worth another commit, and it is a small one: change what the watermark stores.

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
| `playstead-mac/Playstead/Persistence/Migrations.swift` | Durable store for the delivered fact | ✓ VERIFIED | `outbox_delivered_watermark`, one row per kind, `CREATE TABLE IF NOT EXISTS`, bounded. |
| `playstead-mac/Playstead/Sync/Outbox.swift` | Newest-wins supersede across the full entry lifecycle | ⚠️ PARTIAL | Enqueue-time, live-newer, and delivered-newer cases all implemented, atomic, and tested. The tie window (and residues 2/3) remain — see Verdict. |
| `playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift` | Fail-first coverage of both WR-07 rounds | ✓ VERIFIED | 24/24 at HEAD. My probe is kept permanently as `…WhenTheNewerReportAlreadySucceeded`; the tie test correctly prevents watermark over-reach. |
| `playstead-mac/Playstead/App/PlaysteadApp.swift` | Comments that do not assert false serialization | ✓ VERIFIED | Both `drainOutbox` and `drainSaveUploads` now state entry/revision-level non-racing without claiming serialization, and point at `Outbox` as the component that must be correct across reentrancy. |
| `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` | Real, non-constant `missing_dependency` signal | ✓ VERIFIED | Re-confirmed; 0 hardcoded literals in executable code. |
| `playstead-server/.../availability_controller.ex` | 422 shape guard on malformed `entries` | ✓ VERIFIED (WR-04) | Guard intact. Noted: still no report-ordering guard, which is why residue 2 has no server-side mitigation. |
| `.planning/REQUIREMENTS.md` | Authoritative requirement traceability | ✓ VERIFIED | Untouched; LIBR-05 (line 137) and PLAY-04 (line 145) still correctly `Pending`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `CurationIntentKind.availabilityReport` → `Outbox.enqueue` | at-most-one-pending-row | `supersedesPending` scoped delete | ✓ WIRED | Unchanged, tested. |
| `Outbox.markDone` → `outbox_delivered_watermark` | the delivered fact outlives the row | single transaction, `MAX` upsert | ✓ WIRED | One caller, inside the DELETE's transaction; falsification-proven load-bearing. |
| `Outbox.markPendingForRetry` → `isSupersededForRetry` | drop a superseded revived row | live-row check OR watermark check | ⚠️ PARTIAL | Both clauses independently load-bearing; the watermark comparison is blind inside a one-second tie window. |
| `Outbox.onEnqueue` → `OutboxWorker.drainOnce` | post-enqueue drain | `OutboxDrainTrigger.fire()` → `Task { await … }` | ✓ WIRED | PlaysteadApp.swift:648. Still the wiring that makes the reentrancy window reachable; now documented accurately. |
| `AvailabilityReporter.buildEntries` → `missing_dependency` chip | HTTP-driven, no read-model seeding | shared fixture → real controller → LiveView | ✓ WIRED | Re-confirmed by grep (0 bypasses). |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full `OutboxTests` at HEAD `47ac7b6` | `xcodebuild test … -only-testing:PlaysteadTests/OutboxTests` | 24 tests, 0 failures | ✓ PASS |
| Watermark clause is load-bearing (falsification) | watermark lines → `return false`, same command | 24 tests, 2 failures — both on the new drop test, `("1") is not equal to ("0")` at :519 | ✓ PASS (fails as required) |
| Watermark does not duplicate the live-row check | same falsified run | `…ArrivedMeanwhile` and `…NothingNewerArrived` both passed | ✓ PASS |
| Watermark does not over-reach | same falsified run | tie test passed | ✓ PASS |
| Residue: tie window reachable from distinct instants | probe, 0.8s apart | `("2023-11-14T22:13:20Z") is equal to (…)` — collapsed | ✗ FAIL — residue confirmed |
| Residue: stale report deliverable in the tie window | same probe | stale entry still in `listPending` at far-future | ✗ FAIL — residue confirmed |
| Byte-exact restore after both probes | `shasum -a 256`, `git status --short` | `43582f28…` / `1e372f83…` match; tree clean | ✓ PASS |
| Debt-marker scan (TBD/FIXME/XXX) on all files in the three commits | `grep -nE` | no matches | ✓ PASS |

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

One gap, narrowed twice, still open. `47ac7b6` genuinely closes the residue I reported at `847165b`, and I confirmed that independently by falsification rather than by reading the commit message — the watermark clause is load-bearing, atomic with the DELETE, correct on the missing-row path, and cannot invent a watermark for an undelivered entry.

What remains is a key-granularity problem, not a logic error: `created_at` has one-second resolution, so "newer" is a partial order, and inside a one-second window a stale report is still revived and delivered after a newer one succeeded. The strict comparison is the better of the two available choices, and the tie test correctly forbids the alternative — the fix is to store a total order (monotonic sequence, or `(created_at, rowid)`, which the sibling ordering queries already use) rather than to change the comparison. Two further residues — a late-succeeding in-flight request, and a newer row retired by rejection or quarantine — cannot be closed client-side at all and want either a server-side monotonic guard or an explicit WINDOWS.md entry.

Four human verification items carry forward unchanged: physical controller hardware, a live interactive emulator launch session, a live VoiceOver/visual walkthrough, and real BIOS bytes.

---

_Verified: 2026-09-15T15:05:00Z at HEAD 47ac7b6_
_Verifier: Claude (gsd-verifier) — third independent pass on WR-07; no source files modified (working tree clean, all probe files restored byte-exact)_
