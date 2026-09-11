---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-11T18:00:00Z
status: human_needed
score: 5/5 roadmap truths verified (SC5's controller-hardware portion present+wired, not behaviorally exercised — unchanged, routed to human verification); LIBR-02 requirement-level truth now genuinely resolved
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: "gaps_found — LIBR-02 partial (missing_dependency structurally unreachable in production)"
  previous_score: "4/5 roadmap truths verified; LIBR-02 requirement-level truth: partial"
  gaps_closed:
    - "LIBR-02 (missing_dependency structurally unreachable): CLOSED. `AvailabilityReporter.buildEntries` (playstead-mac/Playstead/Cache/AvailabilityReporter.swift:150-176) now computes `missingDependency` as `!requiredSHAs.isEmpty && hasOrphanedRequiredMember && hasEngaged` — a real predicate over CAS presence, download-queue state, and pin state, not a hardcoded constant. Confirmed by direct read: zero occurrences of `missingDependency: false` as a literal in executable code. Proven end-to-end, not just at the LiveView clause: `playstead-server/test/playstead_web/live/library_availability_e2e_test.exs` PUTs `shared/availability-report-fixture.json` verbatim to `PUT /api/v1/devices/me/availability` through the real controller and asserts the `missing_dependency` chip renders the reported game — confirmed by direct read that this test file contains zero calls to `replace_for_device(` and zero constructions of `%DeviceReport{` (grep count 0), so the read model is populated only via HTTP, never seeded directly. A second, independent code review round (03-REVIEW-GAPS.md Round 3) reached the same conclusion by tracing the same diff and lines."
    - "WR-04 (malformed entries body crashes to 500): CLOSED. `AvailabilityController.replace/2`'s new `do_replace/2` (playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex) has an explicit `is_list` + `Enum.all?(entries, &is_map/1)` guard and a catch-all returning `{:error, {:validation_failed, detail}}` through the existing `action_fallback`, matching the sibling `ImportsController.precheck/2` pattern. 4 new tests each assert 422 on its own line; the absent-key and well-formed cases are confirmed unaffected."
    - "REQUIREMENTS.md's LIBR-02 marking is no longer an overclaim: checkbox and traceability row were flipped to Complete by 03-16 Task 3, gated on 03-15's and 03-16's own observed test runs, with a clause-to-test mapping recorded in 03-16-SUMMARY.md that explicitly requires the availability/readiness clause to be proved by a Mac-client-driven or HTTP-driven test — confirmed genuine, not self-graded on an unverified assertion, by this independent re-verification's own direct source read."
  gaps_remaining:
    - "WR-07 (new this round, found by 03-REVIEW-GAPS.md Round 3 and independently confirmed here by direct source read): `Outbox.enqueue`'s newest-wins supersede (added by 03-16 for WR-05) only deletes rows in `state = 'pending'` at the moment a new `.availabilityReport` is enqueued — deliberately leaving an `in_flight` row untouched, since a request already on the wire cannot be recalled (correct as far as it goes, and tested: `test_secondAvailabilityReport_leavesAnInFlightFirstOneAlone`). But `Outbox.markPendingForRetry` (Outbox.swift:210-225), which is what moves a row *back* from `in_flight` to `pending` after a transport failure, never re-runs that supersede check. Because `OutboxWorker`'s `await apiClient.send(...)` (OutboxWorker.swift:93) is a suspension point and `Outbox` is a plain, non-actor-isolated class, a second `.availabilityReport` can be enqueued while the first is genuinely in flight; if that first delivery then fails and reverts to `pending` via `markPendingForRetry`, the outbox ends up with two `pending` rows — the newer one (delivered first, since `listPending` orders `created_at ASC`) and the older, now-backed-off one, which is still delivered once its backoff expires, temporarily reverting the read model to stale facts. No test in `OutboxTests.swift` exercises this specific sequence (enqueue A -> mark A in-flight -> enqueue B while A in-flight -> fail A -> markPendingForRetry(A) -> assert B is not later overwritten by A). This is the specific edge the 03-16 must-have text claims is closed and is not, in full."
  regressions: []
overrides: []
gaps:
  - truth: "03-16-PLAN.md must-have: \"Only the newest full-replacement availability report is ever delivered: enqueuing a new one removes any still-pending or backed-off one, so a backed-off earlier report can no longer land after a later one that already succeeded.\""
    status: open
    reason: "TRUE at enqueue time (the snapshot the plan's own tests exercise) but FALSE across the full lifecycle once an in-flight row reverts to pending. Confirmed genuine by this verification's own direct read of Outbox.swift:107-152 (enqueue's delete is scoped to state='pending' only, matching the code comment's own stated scope) and Outbox.swift:210-225 (markPendingForRetry moves in_flight back to pending with no re-run of the supersede check). Traced and independently confirmed against 03-REVIEW-GAPS.md Round 3's WR-07 finding, which supplies the same file:line evidence and the same race trace (an OutboxWorker suspension point at await apiClient.send, combined with Outbox's lack of actor isolation, is what opens the window for AvailabilityReporter.reportAll() to enqueue a second report while the first is mid-flight). This is a narrow, low-frequency, self-correcting race (the read model corrects itself on the next successful syncNow() pass) — it does not corrupt data permanently, does not cross a trust boundary, and does not block the phase's core roadmap-level claim that a user can find games by availability state in ordinary operation. Classified as a non-blocking, tracked warning consistent with how this same verification treated WR-04/WR-05 in the prior round, not as a phase-blocking gap — but the specific must-have sentence as literally worded is not fully true, and this verification will not round that up to VERIFIED."
    artifacts:
      - path: "playstead-mac/Playstead/Sync/Outbox.swift"
        issue: "markPendingForRetry (lines 210-225) does not re-run CurationIntentKind.supersedesPending's delete when a row reverts from in_flight to pending, so a newer already-delivered report's row can still be followed by a reverted, now-stale older report once its backoff expires."
    missing:
      - "Either re-run the kind-scoped pending supersede inside markPendingForRetry for the specific case where a newer row of the same kind was enqueued during the in-flight window, or accept this as a documented, permanent limitation and record it in .planning/WINDOWS.md rather than leaving it undocumented outside the code review file."
behavior_unverified_items:
  - truth: "A user can connect, test, assign, remap, reset, and recover a controller (roadmap SC #5, controller-hardware portion)"
    test: "Connect a real, paired physical game controller; disconnect it mid-session; reconnect it."
    expected: "Connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without requiring a relaunch — matching what ControllerHost's unit tests already prove against an injectable ControllerInputSource."
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 recorded this as FAIL/unproven, and 03-10-SUMMARY.md's own D1 rationale states the same — all logic is unit-tested against a simulated input source only. Code is present and wired (ControllerHost is registered at AppEnvironment construction); only real-hardware behavior is unexercised. Unchanged by 03-15/03-16, regression-checked."
human_verification:
  - test: "Physical game controller connect/disconnect/reconnect recovery, live input test, remap, and reset on real hardware"
    expected: "Controller lifecycle logic behaves identically against a real device as it does against the injectable simulated input source in unit tests."
    why_human: "No physical or paired controller hardware exists in this execution environment. Reconciled against 03-UAT.md items 8 and 9 (both blocked_by: physical-device) and item 10's blocked sub-record. Unchanged this session."
  - test: "Full end-to-end launch of the pinned mGBA adapter against a live paired server, with a downloaded game and installed emulator, from the notarized build, driven by a live interactive display session"
    expected: "Play starts the emulator, the game runs, SRAM periodically flushes, quitting returns to the library, and Gatekeeper accepts the app without any user override (this last part is proven — see 03-NOTARIZATION-EVIDENCE.md)."
    why_human: "This sandboxed/headless execution environment cannot render a live interactive display session for a human to watch a game actually run. Reconciled against 03-UAT.md item 7 (blocked_by: third-party). Unchanged this session."
  - test: "Visual/typographic fidelity and VoiceOver walkthrough of the LiveView console and the Mac library shell against 03-UI-SPEC.md"
    expected: "Spacing, color rendering, motion timing, and screen-reader sentence flow match the locked design contract on both surfaces."
    why_human: "Multiple SUMMARYs (03-05 D3/D7, 03-06 D2, 03-07 D6, 03-08 D3, 03-10 D2) state that only the markup-level/logic-level accessibility contract was automatically verified — no live NSAccessibility tree or interactive rendering was exercised. Reconciled against 03-UAT.md item 10's blocked sub-record. Unchanged this session."
  - test: "Drag-in BIOS validation against a real, legally-sourced BIOS file or supported open replacement"
    expected: "A correct BIOS file is accepted and stored under managed storage; an incorrect one is rejected with a clear reason."
    why_human: "What remains genuinely human-only is acceptance of real, legally-owned BIOS bytes: no real BIOS file exists in this execution environment, and none should. Reconciled against 03-UAT.md item 13 (result: partial). Unchanged this session."
  - test: "LIBR-05's remaining human-judgment UX review item and PLAY-04's physical controller hardware requirement"
    expected: "N/A — tracked for completeness; these two requirement IDs stay Pending in REQUIREMENTS.md by this plan's own explicit scope fence and are unrelated to LIBR-02's closure."
    why_human: "PLAY-04 is the same hardware-blocked item as the controller item above; LIBR-05's remaining scope is a human UX judgment call not advanced by 03-15/03-16 and not part of this re-verification's remit (03-16's own scope fence explicitly leaves both Pending)."
---

# Phase 3: Mac Offline Play Vertical Slice Verification Report

**Phase Goal:** A newly paired Mac can browse a curated server library, download only chosen verified content, and launch one deliberately supported game offline through a tested adapter.
**Verified:** 2026-09-11T18:00:00Z
**Status:** human_needed
**Re-verification:** Yes — this is an independent re-derivation after 03-15-PLAN.md and 03-16-PLAN.md executed a second gap-closure pass against the LIBR-02 gap (specifically the `missing_dependency` structural-unreachability finding) recorded in the prior 03-VERIFICATION.md, plus WR-04 and WR-05 tracked alongside it.

## Verdict on LIBR-02 (the specific question this re-verification was asked to adjudicate)

**LIBR-02 is now genuinely closed.** The prior verification's blocking finding — `AvailabilityReporter.buildEntries` hardcoding `missingDependency: false` on every entry, making that filter chip structurally unreachable in production — is fixed. Confirmed by direct read of `AvailabilityReporter.swift:150-176`: the fact is now `!requiredSHAs.isEmpty && hasOrphanedRequiredMember && hasEngaged`, computed from real `CASManager`, `DownloadQueue`, and pin-store state, with `hasEngaged` present specifically to keep `server_only` reachable for an untouched game (matching the prior verification's own diagnosis of the failure mode this predicate had to avoid repeating in the opposite direction).

Critically, the proof this time runs through the real client and the real transport, not a test that seeds the server read model. `playstead-server/test/playstead_web/live/library_availability_e2e_test.exs` reads `shared/availability-report-fixture.json` from disk, PUTs it verbatim (rewriting only `asset_set_id`) to `PUT /api/v1/devices/me/availability` through the real controller with real device authentication, then mounts the LiveView and asserts the `missing_dependency` chip renders the reported game while `server_only` still returns its own distinct game. I confirmed by direct grep that this test file contains zero occurrences of `replace_for_device(` and zero constructions of `%DeviceReport{` — the exact bypass the prior round's six-value discrimination test relied on is structurally excluded here. A second, independently-authored code review round (03-REVIEW-GAPS.md Round 3) traced the same lines and reached the same conclusion; I did not take that on the review's word, I re-read `AvailabilityReporter.swift`, the e2e test file, and the fixture directly and reached the same conclusion myself.

`REQUIREMENTS.md`'s LIBR-02 checkbox (line 37, `[x]`) and traceability row (line 134, `Complete`) are no longer an overclaim — confirmed genuine, gated on 03-15's and 03-16's own observed test runs per 03-16-SUMMARY.md's coverage table, and not self-graded against `03-VERIFICATION.md` or `03-UAT.md` (both files are untouched by 03-15/03-16, confirmed by their absence from both plans' `files_modified` and by this verification's own read).

WR-04 (malformed `entries` payload crashing to 500) is also genuinely closed: `AvailabilityController.replace/2`'s new `do_replace/2` has an explicit `is_list` + all-maps guard with a catch-all routed through the existing `action_fallback`, matching the sibling `ImportsController.precheck/2` pattern, with four separately-named tests each asserting 422 on its own line.

## Verdict on the new WR-07 finding (adjudicated explicitly per this run's instruction — not rounded up)

**The 03-16 must-have "a backed-off earlier report can no longer land after a later one that already succeeded" is NOT fully true.** I independently confirmed the mechanism the Round 3 review names, by direct read rather than accepting the review's framing:

- `Outbox.enqueue` (Outbox.swift:107-152) deletes rows matching the incoming intent's kind only where `state = 'pending'`, explicitly and deliberately leaving an `in_flight` row alone — this is correct given a request already on the wire cannot be recalled, and it is tested (`test_secondAvailabilityReport_leavesAnInFlightFirstOneAlone`, `Outbox.swift:129-134` comment states the scope explicitly).
- `Outbox.markPendingForRetry` (Outbox.swift:210-225) is the only code path that moves a row from `in_flight` back to `pending`, after a transport failure. It updates `state`, `attempt_count`, and `next_retry_at` — nothing in this function consults `supersedesPending` or re-runs the delete that `enqueue` performs.
- `Outbox` has no actor isolation of its own, and `OutboxWorker.drainOnce`'s `await apiClient.send(...)` (OutboxWorker.swift:93) is a suspension point, so `AvailabilityReporter.reportAll()` — invoked on every `syncNow()` pass — can call `outbox.enqueue(.availabilityReport(...))` while an earlier report from a prior `syncNow()` pass is still `in_flight` inside a concurrent `drainOnce()` call.
- If that earlier in-flight delivery then fails and `markPendingForRetry` reverts it to `pending` with a future `next_retry_at`, the outbox now holds two `pending` `.availabilityReport` rows: the newer one (delivered first, per `listPending`'s `created_at ASC` order) and the older, backed-off one — which, once its backoff window expires, is delivered *after* the newer one already succeeded, temporarily reasserting stale facts until the next `syncNow()` pass self-corrects.

No test in `OutboxTests.swift` exercises this specific sequence (enqueue A → mark A in-flight → enqueue B while A is in-flight → fail A → `markPendingForRetry(A)` → assert B's facts are not later overwritten by A). I checked: the five new 03-16 tests cover enqueue-time supersede against a pending row and against a backed-off-but-not-yet-in-flight row, and confirm an in-flight row alone survives a concurrent enqueue — but none of them drives the row through in-flight-then-reverted-then-collides-with-a-newer-pending-row.

**This is a genuine, narrow gap, and I am not rounding it up to VERIFIED.** It is also, on its own severity, not a phase-blocking defect: it is self-correcting on the very next successful `syncNow()` pass, it never crosses a trust/user boundary, it never corrupts data permanently, and it does not contradict the phase's roadmap-level claim that a user can ordinarily find games by availability state — this is the same severity class as WR-04 and WR-05 were before this round closed them, and I am treating it with the same disposition: an open, tracked, non-blocking warning, not a gap that forces the whole phase to `gaps_found`. The must-have sentence itself, however, is not something I can mark closed — see the `gaps` entry above.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | Unchanged from prior verification; now also strengthened by LIBR-02's genuine closure (see Verdict above) rather than caveated by it. |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | Unchanged — Mac client's own `AvailabilityState.derive` six-state pure function (CACH-02), confirmed unmodified by this round (`git diff --exit-code -- AvailabilityState.swift` clean, per 03-15-SUMMARY.md and re-confirmed by absence from both plans' `files_modified`). |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; game launchable only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | Unchanged from prior verification; not touched by 03-15/03-16. |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ✓ VERIFIED | Unchanged from prior verification; not touched by 03-15/03-16. |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a **signed/notarized** build after app or server restart | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (controller-hardware portion) / ✓ VERIFIED (notarization portion) | Unchanged from prior verification; not touched by 03-15/03-16. |

**Score:** 5/5 roadmap truths now count as verified/appropriately-routed (LIBR-02's underlying requirement-level defect that previously caveated truth #1 is closed); SC #5's controller-hardware portion remains present-but-behavior-unverified, routed to human verification as before.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` | Real, non-constant `missing_dependency` signal | ✓ VERIFIED | `buildEntries` computes the fact from CAS/queue/pin state (lines 150-176); zero hardcoded `missingDependency: false` literals in executable code (grep confirmed). |
| `shared/availability-report-fixture.json` | Two-sided fixture proving Swift-encoder/HTTP-transport parity | ✓ VERIFIED | Exists, tracked in git, contains all four required states (`missing_dependency: true`, `downloading: true`, `verified: true`, all-false). Read by both `AvailabilityReporterTests.swift` and `library_availability_e2e_test.exs` (grep confirms both files reference the fixture path). |
| `playstead-server/test/playstead_web/live/library_availability_e2e_test.exs` | HTTP-driven proof the chip is reachable in production | ✓ VERIFIED | Confirmed by direct read: PUTs the fixture through the real controller with real device auth, asserts the LiveView chip; zero `replace_for_device(`/`%DeviceReport{` occurrences (grep count 0). |
| `playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex` | 422 shape guard on malformed `entries` | ✓ VERIFIED | `do_replace/2` two-clause guard + catch-all routed through `action_fallback`; existing `:too_many_entries` branch preserved. |
| `playstead-mac/Playstead/Sync/Outbox.swift` | Newest-wins supersede for `.availabilityReport` | ⚠️ PARTIAL | Enqueue-time supersede genuinely implemented and tested for the pending/backed-off-at-enqueue-time case. Does NOT cover the in-flight-then-reverted-to-pending race (WR-07) — see Verdict and gaps above. |
| `.planning/REQUIREMENTS.md` | Authoritative requirement traceability | ✓ VERIFIED | LIBR-02 checkbox (`[x]`, line 37) and traceability row (`Complete`, line 134) confirmed genuine per the Verdict above; LIBR-05 and PLAY-04 correctly left `Pending` (grep confirmed), matching 03-16's explicit scope fence. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `AvailabilityReporter.buildEntries` | `shared/availability-report-fixture.json` | Swift encoder test | ✓ WIRED | `test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture` (per 03-15-SUMMARY.md, part of the 17/17 Mac run). |
| `shared/availability-report-fixture.json` | `PUT /api/v1/devices/me/availability` → `missing_dependency` chip | Elixir HTTP-driven test | ✓ WIRED | `library_availability_e2e_test.exs`, confirmed by direct read; no direct read-model seeding. |
| Request body → `AvailabilityController.replace/2` | 422 `validation_failed` | shape guard → `action_fallback` | ✓ WIRED | `do_replace/2`'s catch-all confirmed present; `action_fallback` declaration confirmed present in the controller. |
| `CurationIntentKind.availabilityReport` → `Outbox.enqueue` | at-most-one-pending-row | `supersedesPending` scoped delete | ⚠️ PARTIAL | Wired and tested for the enqueue-time snapshot; NOT wired into `markPendingForRetry`'s in-flight-to-pending transition (WR-07). |

### Behavioral Spot-Checks / Test Execution

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Server suite (post wave 1, LIBR-02 real-signal) | `mix test` | 178 features, 13 properties, 1066 tests, 0 failures (per 03-15-SUMMARY.md, matches orchestrator-reported post-wave-1 gate) | ✓ PASS |
| Server suite (post wave 2, WR-04/WR-05 + LIBR-02 flip) | `mix test` | 178 features, 13 properties, 1072 tests, 0 failures (per 03-16-SUMMARY.md, matches orchestrator-reported post-wave-2 gate at df6794a) | ✓ PASS |
| Mac unit suite (AvailabilityReporterTests) | `xcodebuild test -only-testing:PlaysteadTests/AvailabilityReporterTests` | 17/17, 0 failures, no `Executed 0 tests` line | ✓ PASS |
| Mac unit suite (OutboxTests + AvailabilityReporterTests, wave 2) | `xcodebuild test -only-testing:...` | 37/37, 0 failures | ✓ PASS |
| Transport-fidelity grep | `grep -c 'replace_for_device(\\|%DeviceReport{' library_availability_e2e_test.exs` | `0` | ✓ PASS |
| Hardcoded-constant grep | `grep -v '^\s*//' AvailabilityReporter.swift \| grep -c 'missingDependency: false'` | `0` | ✓ PASS |
| Debt-marker scan (TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER) on all 03-15/03-16 modified files | `grep -n -E ...` | no matches in any of 8 files checked | ✓ PASS |

### Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| LIBR-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| LIBR-02 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Confirmed genuine this session — see Verdict section above. All six availability/readiness states are now reachable end-to-end from a real device report through a real HTTP transport, proven by a test that does not seed the read model directly. |
| LIBR-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| LIBR-04 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| LIBR-05 | ? NEEDS HUMAN | REQUIREMENTS.md: Pending. Unchanged from prior verification; not advanced by 03-15/03-16 (explicit scope fence). |
| CACH-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| CACH-02 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| CACH-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| CACH-04 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| PLAY-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| PLAY-02 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| PLAY-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| PLAY-04 | ? NEEDS HUMAN | REQUIREMENTS.md: Pending. Unchanged from prior verification; not advanced by 03-15/03-16 (explicit scope fence, hardware-blocked). |
| PLAY-05 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| QUAL-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. 03-15/03-16's own test suites (up to 1072 server tests, 37 new Mac tests, 0 failures) support this; not itself in question. |

No orphaned requirements found. All 15 phase requirement IDs (LIBR-01..05, CACH-01..04, PLAY-01..05, QUAL-01) are accounted for above; LIBR-02 is the one that changed status this round, from partial to satisfied.

### Anti-Patterns Found

No debt markers (TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER) found in any of the 8 files modified by 03-15/03-16 that were checked directly by this verification.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Outbox.swift` | 210-225 (`markPendingForRetry`) | Newest-wins supersede not re-run on in-flight → pending transition (WR-07) | ⚠️ Warning (self-correcting, non-blocking — see Verdict above) | A backed-off report can still be delivered after a later one that already succeeded, in a narrow concurrent-enqueue-during-in-flight window; corrects itself on the next `syncNow()` pass. |

Pre-existing WR-01/WR-02/WR-03 (BIOS crash-window orphan, `mktemp -u` race, fixed-sleep liveness checks) from Round 1 remain open, untouched by this session's scope. WR-04, WR-05, and WR-06 from Round 2 are all now closed (WR-05's fix is real but its residual gap is re-recorded here as WR-07, per Round 3's own framing).

### Human Verification Required

See `human_verification` in frontmatter — 5 items, 4 unchanged from the prior verification (physical controller, live emulator session, VoiceOver walkthrough, real BIOS bytes — all environment/hardware/experiential-blocked) plus one bookkeeping item reconfirming LIBR-05/PLAY-04 remain correctly Pending and outside this round's remit. The prior round's 5th item (the LIBR-02 missing_dependency scope decision) is resolved and removed — it was a code-completeness decision, and the code was completed.

### Gaps Summary

The gap-closure plans 03-15/03-16 delivered genuine, verifiable closure of the LIBR-02 defect this phase's prior verification blocked on: `missing_dependency` is now a real, computed, HTTP-transport-proven signal, and REQUIREMENTS.md's Complete marking for LIBR-02 is no longer an overclaim. WR-04 (malformed payload → 500) is also genuinely closed.

However, this phase's WR-05 fix (newest-wins outbox supersede) is real but incomplete: a residual race (WR-07, found independently by this session's own Round 3 code review and independently confirmed here by direct source read) means a backed-off, in-flight-reverted earlier report can still be delivered after a later one that already succeeded, in a narrow concurrent-enqueue window. This is tracked as an open, non-blocking warning — consistent with how this same verification treated WR-04/WR-05 in the prior round before they were closed — because it is self-correcting, does not cross a trust boundary, does not corrupt data permanently, and does not contradict the phase's roadmap-level claim that a user can ordinarily find games by availability state.

The phase's overall status is `human_needed`, not `passed`, because four pre-existing human/hardware-only items remain open and unrelated to this round's work: physical controller hardware (PLAY-04 and roadmap SC #5's hardware portion), a live interactive emulator session, an experiential VoiceOver/visual-fidelity walkthrough, and acceptance of real legally-owned BIOS bytes. None of these is a gap in the actionable sense — they are environment-blocked, not code-incomplete — and per this project's own gate rules, `passed` requires the human verification section to be empty, which it is not.

Recommended next step: this phase's LIBR-02-specific gap-closure work is done. Any further work on this phase is either (a) closing WR-07 with a targeted fix (re-run the kind-scoped supersede inside `markPendingForRetry`, or explicitly accept and document the residual race in `.planning/WINDOWS.md`), which is optional given its non-blocking severity, or (b) resolving the five human-verification items, which requires physical hardware, a live interactive session, and human UX judgment that cannot be supplied by further automated work in this environment.

---

*Verified: 2026-09-11T18:00:00Z*
*Verifier: Claude (gsd-verifier)*
