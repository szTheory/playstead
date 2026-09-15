---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-15T14:20:00Z
status: human_needed
score: 5/5 roadmap truths verified (SC5's controller-hardware portion present+wired, not behaviorally exercised — unchanged, routed to human verification); WR-07 narrowed but not fully closed
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
  - "playstead-mac/Playstead/Cache/AvailabilityReporter.swift"
  - "playstead-mac/Playstead/Sync/Outbox.swift"
  - "playstead-mac/Playstead/Sync/OutboxWorker.swift"
  - "playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift"
  - "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
covered_digest: "v1:sha256:88c3cc7d2314272003b98693e57e57bc732779b6298bf5d22ae34103020d9f3c"
re_verification:
  previous_status: "human_needed (one open gap: WR-07)"
  previous_score: "5/5 roadmap truths; WR-07 open"
  gaps_closed: []
  gaps_narrowed:
    - "WR-07: the specific sequence the prior verification named as untested — enqueue A -> A in flight -> enqueue B -> fail A -> markPendingForRetry(A) -> assert B is not later overwritten — is now genuinely closed, in code and in test. Verified independently by falsification, not by reading the commit message: disabling the new guard in place (`if false, entry.kind.supersedesPending, ...`) makes all three clauses of `test_anInFlightReportRevertedForRetryIsDroppedWhenANewerReportArrivedMeanwhile` fail (OutboxTests.swift:482, :483, :484) while every other OutboxTests case still passes; restoring the file byte-exact returns the class to 22/22. The residual hole is a DIFFERENT ordering of the same race — see gaps below."
  gaps_remaining:
    - "WR-07 (narrowed, still open): the new guard requires the newer row to be still LIVE (`state IN ('pending','in_flight')`), but `Outbox.markDone` DELETES the row on success. So in the ordering where the newer report has already SUCCEEDED — which is literally the clause the must-have names — `hasNewerLiveEntry` returns false and the stale older row is revived and later delivered."
  regressions: []
overrides: []
gaps:
  - truth: "03-16-PLAN.md must-have: \"Only the newest full-replacement availability report is ever delivered: enqueuing a new one removes any still-pending or backed-off one, so a backed-off earlier report can no longer land after a later one that already succeeded.\""
    status: partial
    reason: "Materially narrowed by 847165b, but the sentence's own final clause — \"after a later one that already succeeded\" — is still the uncovered case. `markPendingForRetry`'s new guard fires only when `hasNewerLiveEntry` finds a newer row in `state IN ('pending','in_flight')` (Outbox.swift:256-268). `Outbox.markDone` deletes the row on a successful send (Outbox.swift:190-192). Therefore, once the newer report B has actually succeeded, there is no live newer row left for the guard to find, and the older in-flight row A is revived on failure exactly as before. Proven at HEAD by a falsification probe, not by inspection: enqueue A -> markInFlight(A) -> enqueue B -> markInFlight(B) -> markDone(B) -> markPendingForRetry(A) leaves `listPending(at: far future).count == 1`, asserted against 0 (probe failed at OutboxTests.swift:527, \"(1) is not equal to (0)\"). Probe removed and the file restored byte-exact (sha256 f915de04… before and after); tree clean. Reachability is the same mechanism the original WR-07 finding rested on, not a new assumption: Swift actors are reentrant at `await` points, and `OutboxWorker.drainOnce`'s `await apiClient.send(...)` (OutboxWorker.swift:104) is one. The codebase already depends on that being true — `markInFlight` is executed synchronously BEFORE the await precisely so a reentrant pass's `listPending` skips the row, which is only necessary if a reentrant pass can run. And `Outbox.onEnqueue` is wired to `trigger.fire()` (PlaysteadApp.swift:648), which spawns `Task { await worker.drainOnce() }` — so enqueuing B itself starts the pass that can run inside pass 1's suspension, send B, succeed, and delete B's row before A's failure is handled. Nothing mitigates it server-side: `AvailabilityController.replace/2` -> `Availability.replace_for_device/2` is a blind full replacement with no report-timestamp ordering guard. If anything this surviving ordering is the more likely one, since A failing by transport timeout takes longer than B succeeding. `OutboxDrainTrigger.fire()`'s comment — \"The worker is an actor, so overlapping calls serialize rather than racing the same entry\" — is correct about the same entry and incorrect as a general serialization claim; that belief is what the remaining hole rests on. Severity is unchanged from the prior round's judgment and the disposition is deliberately the same: narrow, self-correcting on the next successful `syncNow()` pass, no permanent data corruption, no trust boundary crossed, and it does not contradict the phase's roadmap-level claim. Tracked non-blocking warning — but the must-have sentence as literally worded is still not true, and this verification does not round that up."
    artifacts:
      - path: "playstead-mac/Playstead/Sync/Outbox.swift"
        issue: "`hasNewerLiveEntry` (lines 256-268) scopes \"newer\" to rows still in `pending`/`in_flight`. Because `markDone` (lines 190-192) deletes a successfully delivered row, a newer report that already succeeded is invisible to the guard, and `markPendingForRetry` revives the older superseded row."
    missing:
      - "Either make the supersede decision durable past delivery — e.g. record the `created_at` (or a monotonic sequence number) of the newest `.availabilityReport` accepted by the server and have `markPendingForRetry` compare against that watermark rather than against live rows only — or add a server-side monotonic guard so `replace_for_device/2` ignores a report older than the one it last accepted for that device."
      - "A test covering the surviving ordering (newer report succeeds and its row is deleted BEFORE the older in-flight delivery fails). The probe used in this verification is a ready-made fail-first case."
      - "If instead this is accepted as a permanent limitation, record it in .planning/WINDOWS.md — it is currently documented only inside a code comment that describes the closed half of the race."
behavior_unverified_items:
  - truth: "A user can connect, test, assign, remap, reset, and recover a controller (roadmap SC #5, controller-hardware portion)"
    test: "Connect a real, paired physical game controller; disconnect it mid-session; reconnect it."
    expected: "Connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without requiring a relaunch — matching what ControllerHost's unit tests already prove against an injectable ControllerInputSource."
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 recorded this as FAIL/unproven and 03-10-SUMMARY.md's D1 rationale states the same. Code is present and wired; only real-hardware behavior is unexercised. Unchanged by 847165b/97b1358, regression-checked."
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
**Verified:** 2026-09-15T14:20:00Z
**Status:** human_needed
**Re-verification:** Yes — independent adjudication of commit `847165b` (the WR-07 fix), plus regression re-checks of LIBR-02, WR-04 and WR-05 by direct source read.

## Verdict on WR-07: PARTIALLY CLOSED

I did not take the commit message on trust. I read the code, ran the two new tests, falsified the fix in place to prove it is load-bearing, and then probed the case the fix does not cover.

### What is genuinely closed

The exact sequence the prior verification named as untested is now closed, in code and in test.

`Outbox.markPendingForRetry` (Outbox.swift:210-236) now drops rather than revives a superseded row. The scoping is correct on every axis the instruction asked me to check:

- **Scoped to superseding kinds.** The guard is gated on `entry.kind.supersedesPending`, and `CurationIntentKind.supersedesPending` (CurationIntent.swift:51-60) is an exhaustive switch returning `true` only for `.availabilityReport`. Every other kind falls through to the unchanged retry path. `test_secondFavoriteIntent_isNotSupersededBecauseOnlyReportsAreNewestWins` and the in-order drain tests still pass, so non-superseding kinds still drain in creation order with no entry dropped.
- **`created_at` ties are NOT newer.** `hasNewerLiveEntry` uses `created_at > ?`, strictly. Two reports enqueued inside the same ISO-8601 second cannot delete each other.
- **Self-exclusion.** `id != ?` excludes the row being reverted.

**Falsification, not inspection.** I disabled the guard in place (`if false, entry.kind.supersedesPending, ...`), rebuilt, and ran the class. All three clauses of the drop test failed on their own lines:

```
OutboxTests.swift:482: ("2") is not equal to ("1") - the superseded older report must not be revived alongside the newer one
OutboxTests.swift:483: ("...6B842CBD...") is not equal to ("...C8ED83F9...") - the survivor is the newer report
OutboxTests.swift:484: XCTAssertTrue failed - no backoff window may later deliver the stale report after the newer one
```

19 of 22 cases still passed, so the guard is doing exactly this work and nothing broader. `test_anInFlightReportRevertedForRetryIsKeptWhenNothingNewerArrived` passed both with and without the fix — which is precisely its stated job: it pins the other half, so the fix cannot silently degenerate into "reverting always drops the row". Both of the commit's claims about its own tests check out. `Outbox.swift` was restored byte-exact afterwards (sha256 `b9e089e3…` before and after) and the class returns 22/22.

### What is still open

**The must-have's own final clause — "after a later one that already succeeded" — is still the uncovered case.**

The guard only fires when `hasNewerLiveEntry` finds a newer row in `state IN ('pending', 'in_flight')`. But `Outbox.markDone` **deletes** the row on a successful send:

```swift
func markDone(_ entryID: String) throws {
    try localStore.connection.execute("DELETE FROM outbox_entries WHERE id = ?;", params: [entryID])
}
```

So once the newer report B has actually succeeded, there is no live newer row left for the guard to find, and the older in-flight row A is revived on failure exactly as it was before the fix — then delivered once its backoff expires, reasserting stale facts over newer ones that already landed.

I proved this at HEAD rather than arguing it. A probe driving `enqueue A -> markInFlight(A) -> enqueue B -> markInFlight(B) -> markDone(B) -> markPendingForRetry(A)` asserts `listPending(at: far future).count == 0` and **fails**:

```
OutboxTests.swift:527: error: XCTAssertEqual failed: ("1") is not equal to ("0")
  - PROBE: a stale older report must not be delivered after the newer one already succeeded
```

The probe was removed and `OutboxTests.swift` restored byte-exact (sha256 `f915de04…` before and after); the working tree is clean.

**This is the same race, not a new one.** Reachability rests on exactly the mechanism the original WR-07 finding named — Swift actor reentrancy — and the codebase already depends on that mechanism being real:

1. `OutboxWorker.drainOnce`'s `await apiClient.send(...)` (OutboxWorker.swift:104) is a suspension point. Swift actors are reentrant at `await`, so a second `drainOnce()` task can begin executing while the first is suspended.
2. The code already assumes this: `markInFlight` is executed **synchronously before** the await, specifically so a reentrant pass's `listPending` (which excludes `in_flight`) skips that row. That guard is only necessary if a reentrant pass can run.
3. `Outbox.onEnqueue` is wired to `trigger.fire()` (PlaysteadApp.swift:648), which spawns `Task { await worker.drainOnce() }`. So enqueuing B *itself* starts the pass that can run inside pass 1's suspension window.

Sequence: pass 1 marks A in flight and suspends on `send(A)`; `AvailabilityReporter.reportAll()` enqueues B, firing pass 2; pass 2 sends B, succeeds, and `markDone(B)` deletes the row; pass 1 resumes, `send(A)` fails, `markPendingForRetry(A)` finds no live newer row, and A is revived. If anything this ordering is **more** likely than the one the fix closes, since A failing by transport timeout takes longer than B succeeding on a healthy connection.

Nothing mitigates it server-side: `AvailabilityController.replace/2` → `Availability.replace_for_device/2` is a blind full replacement with no report-timestamp or sequence guard (confirmed by direct read of `availability_controller.ex` — the only guards there are the WR-04 shape check, idempotency, and the 5000-entry limit).

`OutboxDrainTrigger.fire()`'s comment — *"The worker is an actor, so overlapping calls serialize rather than racing the same entry"* — is correct about the same entry and incorrect as a general serialization claim. That belief is what the remaining hole rests on.

### Disposition

The fix is real, correctly scoped, and load-bearing; it closes a genuine subset of the defect. It is **narrower than the must-have sentence it was meant to satisfy**, and I am recording that plainly rather than rounding it up, exactly as the prior verification declined to.

Severity is unchanged from the prior round: narrow, self-correcting on the next successful `syncNow()` pass, no permanent data corruption, no trust boundary crossed, and no contradiction of the phase's roadmap-level claim. Same disposition as the prior round applied to WR-04/WR-05 before they closed — an open, tracked, **non-blocking** warning — so the phase status is not regressed to `gaps_found` for it. But it is not closed.

## Regression Re-checks (by source read, not by reading the prior verification)

| Prior finding | Status | Evidence re-derived this session |
|---|---|---|
| **LIBR-02** (`missing_dependency` structurally unreachable) | ✓ STILL CLOSED | `AvailabilityReporter.buildEntries` computes `missingDependency = !requiredSHAs.isEmpty && hasOrphanedRequiredMember && hasEngaged` from real `CASManager`/`DownloadQueue`/pin state. `grep -v '^\s*//' AvailabilityReporter.swift \| grep -c 'missingDependency: false'` → `0`. `grep -c 'replace_for_device(\|%DeviceReport{' library_availability_e2e_test.exs` → `0`, so the read model is still populated only over HTTP, never seeded. |
| **WR-04** (malformed `entries` → 500) | ✓ STILL CLOSED | `do_replace/2` in `availability_controller.ex` retains the `is_list` clause + `Enum.all?(entries, &is_map/1)` check + catch-all returning `{:error, {:validation_failed, …}}` through the declared `action_fallback`. The absent-key default to `[]` and the `:too_many_entries` branch are both intact. |
| **WR-05** (enqueue-time newest-wins supersede) | ✓ STILL CLOSED | `Outbox.enqueue` (lines 118-136) still deletes `kind = ? AND state = 'pending'` inside the insert transaction. `test_secondAvailabilityReport_supersedesThePendingFirstOne`, `…supersedesABackedOffFirstOne`, `…leavesAnInFlightFirstOneAlone` and `test_drainAfterSupersede_sendsOnlyTheNewerReportBody` all pass in the 22/22 run. |

The other commit on this head, `97b1358`, touches `OutboxWorker.swift` only to add `OutboxDrainResult.failureClassification`. I read the current `drainOnce` in full: creation-order draining, the stop-on-first-retry rule, the WR-01 markInFlight-failure stop, and the permanent-rejection branch are all unchanged. No regression.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | Unchanged; LIBR-02 re-confirmed closed above by direct read. |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | Unchanged. `AvailabilityState.derive` untouched by this session's two commits (absent from both `--name-only` lists). |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; launch only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | Unchanged; not touched by `847165b`/`97b1358`. |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ✓ VERIFIED | Unchanged; not touched this session. |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a signed/notarized build after app or server restart | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (controller-hardware portion) / ✓ VERIFIED (notarization portion) | Unchanged; routed to human verification as before. |

**Score:** 5/5 roadmap truths verified or appropriately routed; 1 present-but-behavior-unverified. WR-07 is a sub-requirement-level must-have from 03-16-PLAN.md, not a roadmap SC, and is tracked in `gaps` above.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Sync/Outbox.swift` | Newest-wins supersede across the full entry lifecycle | ⚠️ PARTIAL | Enqueue-time supersede and the in-flight→reverted-vs-live-newer case are both implemented and tested. The newer-already-succeeded case is not — see Verdict. |
| `playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift` | Fail-first coverage of the WR-07 sequence | ✓ VERIFIED | Both new tests read genuine; the drop test's 3 clauses each fail independently without the fix; the keep test correctly passes both ways. 22/22 at HEAD. |
| `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` | Real, non-constant `missing_dependency` signal | ✓ VERIFIED | Re-confirmed; 0 hardcoded literals in executable code. |
| `playstead-server/.../availability_controller.ex` | 422 shape guard on malformed `entries`; no stale-report ordering guard expected here | ✓ VERIFIED (WR-04) | Guard intact. Noted: it performs a blind full replacement with no report ordering guard, which is why WR-07's residue has no server-side mitigation. |
| `.planning/REQUIREMENTS.md` | Authoritative requirement traceability | ✓ VERIFIED | Untouched by both commits; LIBR-05 (line 137) and PLAY-04 (line 145) still correctly `Pending`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `CurationIntentKind.availabilityReport` → `Outbox.enqueue` | at-most-one-pending-row | `supersedesPending` scoped delete | ✓ WIRED | Unchanged, tested. |
| `Outbox.markPendingForRetry` → `hasNewerLiveEntry` | drop a superseded revived row | kind-scoped, strict-`created_at` live-row query | ⚠️ PARTIAL | Wired and proven load-bearing, but "live" excludes an already-delivered newer row, which `markDone` deletes. |
| `Outbox.onEnqueue` → `OutboxWorker.drainOnce` | post-enqueue drain | `OutboxDrainTrigger.fire()` → `Task { await … }` | ✓ WIRED | PlaysteadApp.swift:648. This is also the wiring that makes WR-07's residual window reachable. |
| Request body → `AvailabilityController.replace/2` | 422 `validation_failed` | shape guard → `action_fallback` | ✓ WIRED | Unchanged. |
| `AvailabilityReporter.buildEntries` → `missing_dependency` chip | HTTP-driven, no read-model seeding | shared fixture → real controller → LiveView | ✓ WIRED | Re-confirmed by grep (0 bypasses). |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| The two WR-07 tests pass at HEAD | `xcodebuild test … -only-testing:PlaysteadTests/OutboxTests` | 22 tests, 0 failures | ✓ PASS |
| The WR-07 fix is load-bearing (falsification) | guard disabled in place, same command | 22 tests, 3 failures — all 3 clauses of the drop test, on their own lines | ✓ PASS (fails as required) |
| The keep test does not merely mirror the fix | same run, fix disabled | `…IsKeptWhenNothingNewerArrived` passed | ✓ PASS |
| Residual hole: newer report already succeeded | probe inserted, same command | `OutboxTests.swift:527 ("1") is not equal to ("0")` | ✗ FAIL — defect confirmed |
| Byte-exact restore after both probes | `shasum -a 256`, `git status --short` | `f915de04…` / `b9e089e3…` match; tree clean | ✓ PASS |
| Debt-marker scan (TBD/FIXME/XXX) on all files in `847165b` + `97b1358` | `grep -nE "TBD\|FIXME\|XXX"` over 11 files | no matches | ✓ PASS |

Per project convention, probe restores were done by copying back a saved byte-exact backup, never by `git checkout`.

### Requirements Coverage

All 15 phase requirement IDs accounted for against REQUIREMENTS.md.

| Requirement | Status | Evidence |
|---|---|---|
| LIBR-01 | ✓ SATISFIED | REQUIREMENTS.md line 133 Complete. Unchanged. |
| LIBR-02 | ✓ SATISFIED | Line 134 Complete. Re-confirmed closed this session by direct read (see Regression Re-checks). |
| LIBR-03 | ✓ SATISFIED | Line 135 Complete. Unchanged. |
| LIBR-04 | ✓ SATISFIED | Line 136 Complete. Unchanged. |
| LIBR-05 | ? NEEDS HUMAN | Line 137 Pending. Human UX judgment; explicit scope fence. |
| CACH-01 | ✓ SATISFIED | Line 138 Complete. Unchanged. |
| CACH-02 | ✓ SATISFIED | Line 139 Complete. Unchanged. |
| CACH-03 | ✓ SATISFIED | Line 140 Complete. Unchanged. |
| CACH-04 | ✓ SATISFIED | Line 141 Complete. Unchanged. |
| PLAY-01 | ✓ SATISFIED | Line 142 Complete. Unchanged. |
| PLAY-02 | ✓ SATISFIED | Line 143 Complete. Unchanged. |
| PLAY-03 | ✓ SATISFIED | Line 144 Complete. BIOS acceptance against real bytes remains human-gated (03-UAT.md item 13, partial). |
| PLAY-04 | ? NEEDS HUMAN | Line 145 Pending. Physical controller hardware. |
| PLAY-05 | ✓ SATISFIED | Line 146 Complete. Live interactive launch remains human-gated (03-UAT.md item 7). |
| QUAL-01 | ✓ SATISFIED | Line 155 Complete. Live VoiceOver/visual walkthrough remains human-gated. |

No orphaned requirement IDs: every ID mapped to Phase 3 in REQUIREMENTS.md appears in the phase's plan frontmatter.

### Anti-Patterns Found

None in the files modified by this session's commits. No `TBD`/`FIXME`/`XXX` markers.

ℹ️ Info (pre-existing, out of this gap's scope, recorded not blocked): `markPendingForRetry` is the *only* path from `in_flight` back to `pending` (grep-confirmed across the Swift sources). A process crash while a row is `in_flight` therefore leaves that row stuck in `in_flight` with no startup recovery sweep, so it is neither retried nor superseded. Not a phase-03 must-have and not evidenced as reachable in a way that affects the roadmap truths — noted for whoever picks up the WR-07 residue, since a durable watermark would address both.

### Note on CI evidence

Local `OutboxTests` runs were executed by this verification directly and are cited above as first-hand results. The reported full local Unit layer (700 tests, 0 failures) was not re-run here; it is not load-bearing for any verdict in this report. Hosted CI runs for `97b1358`/`847165b` were in flight at verification time and are not cited. The intermittent live-server failures tracked as WINDOWS #70/#71/#87 are deliberately **not** attributed to any phase 03 requirement — no evidence connects them, and #70/#87 were addressed in `97b1358`.

### Gaps Summary

One gap, narrowed but not closed. Commit `847165b` genuinely fixes the WR-07 sequence the prior verification named, and I confirmed that independently by falsification rather than by reading the commit message. But the fix defines "superseded" as "a newer row is still live", and a successfully delivered row is deleted — so the must-have's own final clause, a stale report landing *after a later one that already succeeded*, remains reachable through the same actor-reentrancy window, with no server-side ordering guard behind it. A durable watermark (client or server) is what would actually satisfy the sentence as written.

Four human verification items carry forward unchanged: physical controller hardware, a live interactive emulator launch session, a live VoiceOver/visual walkthrough, and real BIOS bytes. None can be executed in this environment.

---

_Verified: 2026-09-15T14:20:00Z_
_Verifier: Claude (gsd-verifier) — independent re-verification; no phase source files were modified (working tree clean, both probe files restored byte-exact)_
