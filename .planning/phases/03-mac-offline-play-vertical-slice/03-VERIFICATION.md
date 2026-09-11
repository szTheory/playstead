---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-11T12:00:00Z
status: gaps_found
score: 4/5 roadmap truths verified (1 partial — controller-hardware portion of SC5 present+wired but not behaviorally exercised); Requirements Coverage below carries 1 additional unresolved requirement (LIBR-02, now partial rather than fully blocked) not captured by the 5 numbered roadmap truths
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: "gaps_found (frontmatter), but that file was last edited by the 03-14 executor whose own work it was grading — its LIBR-02 'resolved' claim is treated here as an unverified assertion, not evidence"
  previous_score: "claimed 5/5 roadmap truths + LIBR-02 fully resolved; not reproducible in full"
  gaps_closed:
    - "The prior VERIFICATION.md's LIBR-02 diagnosis (2 of 6 states discriminate, the other 4 fall through unfiltered to `true`) is genuinely closed. Independently re-read `library_live.ex:182-208`: the unconditional pass-through clause is gone, replaced by one explicit clause per frozen vocabulary value (`needs_attention`, `missing_dependency`, `downloading`, `queued`, `ready_offline` matching `[:pinned, :verified]`, `server_only`), each delegating to `StatusSlot`'s ordered rank ladder. A device-reported read model (`Playstead.Availability`, `PUT /api/v1/devices/me/availability`, migration `device_asset_availability`) now backs this filter with real per-device facts merged per user, replacing the prior state where the server had no fact to filter four of the six values on at all. Regression-verified: server suite 1065 tests / 0 failures; Mac suite 645 tests / 0 failures (both at HEAD 33a06a1)."
  gaps_remaining:
    - "LIBR-02 is NOT fully closed. `AvailabilityReporter.buildEntries` (playstead-mac/Playstead/Cache/AvailabilityReporter.swift:141) hardcodes `missingDependency: false` on every entry it ever builds, for every game, unconditionally — confirmed by direct read. There is no other writer of `device_asset_availability.missing_dependency` anywhere in this codebase (the field is device-reported only per `Playstead.Availability`'s own moduledoc; no other client exists). The consequence is structural, not incidental: the `missing_dependency` filter chip — one of the six values this same gap-closure round set out to make 'genuinely discriminate' — can never return a non-empty result in any real deployment. `library_live_test.exs`'s six-value discrimination test (line 577) proves discrimination only by seeding `missing_dependency: true` directly into the read model, bypassing the Mac client entirely; no test proves the fact can ever arise from a real device report, because it can't. This was surfaced independently in this session's code review (03-REVIEW-GAPS.md Round 2, WR-06) and confirmed here by direct source read, not taken on the review's word alone. 03-14-SUMMARY.md's own 'Known Stubs' section discloses the hardcoded `false` but frames it as merely 'not exercised by this plan's behavior list' and states it 'does not corrupt the read model, it simply never asserts that fact' — true but materially understated: a console filter chip that structurally can never match anything is functionally equivalent to the original pass-through defect, just inverted (always-empty instead of always-everything), and neither `.planning/WINDOWS.md` (grepped, zero mentions of `missing_dependency` or this gap) nor REQUIREMENTS.md's LIBR-02 text was updated to disclose or narrow this at the point REQUIREMENTS.md's checkbox was flipped to Complete. REQUIREMENTS.md line 37 (`- [x] **LIBR-02**`) and line 134 (`| LIBR-02 | Phase 3 | Complete |`) are therefore an overclaim: 5 of 6 documented availability/readiness states are genuinely findable in production; 1 of 6 (missing dependency) is not and cannot be without further Mac-client work (a real signal for 'a required member the catalogue manifest names but that is absent locally and not currently downloading or queued') or an explicit owner decision to narrow LIBR-02's scope and record that narrowing in WINDOWS.md."
  regressions: []
overrides: []
gaps:
  - truth: "A user can select or install one supported Mac adapter, see its exact system/emulator/version/content/BIOS/save support, validate a locally supplied BIOS or supported open replacement, and receive a preflight remedy for each blocking readiness condition."
    status: resolved
    resolved_at: 2026-09-10
    resolved_by: "03-11-PLAN.md"
    reason: "RESOLVED (composition-root wiring only — real-bytes acceptance stays operator-verified, tracked honestly rather than claimed). Regression-checked this session: BiosReferences.production is still wired at PlaysteadApp's composition root, 03-BIOS-PIN.json's 3-source provenance array is unchanged, BiosProductionReferenceTests still exists. No regression from 03-13/03-14 (neither plan touched Adapter/ files)."
    artifacts:
      - path: "playstead-mac/Playstead/Adapter/BiosStore.swift"
        issue: "None — unchanged since prior verification, regression-checked."
      - path: "playstead-mac/Playstead/Adapter/BiosReferences.swift"
        issue: "None — unchanged since prior verification, regression-checked."
      - path: ".planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json"
        issue: "None — unchanged since prior verification, regression-checked."
    missing: []
  - truth: "A user can launch one legally testable game through the supported adapter from a signed/notarized Mac build, exit safely, and relaunch it after an application or server restart."
    status: resolved
    resolved_at: 2026-09-11
    resolved_by: "03-12-PLAN.md"
    reason: "RESOLVED. Regression-checked this session: 03-13/03-14 did not touch any notarization script or evidence file. 03-NOTARIZATION-EVIDENCE.md's submission ID and RelaunchTests pass count are unchanged from prior verification."
    artifacts:
      - path: "playstead-mac/scripts/sign-and-notarize.sh"
        issue: "None — unchanged since prior verification, regression-checked."
      - path: "playstead-mac/scripts/verify-notarized-release.sh"
        issue: "None — unchanged since prior verification, regression-checked."
      - path: ".planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md"
        issue: "None — unchanged since prior verification, regression-checked."
    missing: []
  - truth: "Two CRITICAL path-traversal defects (CR-01, CR-02) identified in 03-REVIEW.md remain unpatched in the codebase."
    status: resolved
    resolved_at: 2026-09-10
    resolved_by: "03-REVIEW-FIX.md (2026-08-31)"
    reason: "RESOLVED. Regression-checked this session: PathSafety.swift, AppPaths.swift, LaunchMaterializer.swift untouched by 03-13/03-14 (both plans' files_modified lists confirm neither file appears)."
    artifacts:
      - path: "playstead-mac/Playstead/App/PathSafety.swift"
        issue: "None — unchanged, regression-checked."
      - path: "playstead-mac/Playstead/Cache/LaunchMaterializer.swift"
        issue: "None — unchanged, regression-checked."
      - path: "playstead-mac/Playstead/App/AppPaths.swift"
        issue: "None — unchanged, regression-checked."
    missing: []
  - truth: "LIBR-02: A user can quickly find games through search, filters, systems, and availability or readiness state."
    status: partial
    reason: "SUBSTANTIALLY IMPROVED, NOT FULLY CLOSED. The pass-through defect this gap originally named (4 of 6 values fell through unfiltered) is genuinely fixed: `matches_availability?/3` now has one explicit clause per frozen vocabulary value, backed by a real device-reported read model (`Playstead.Availability`, `PUT /api/v1/devices/me/availability`) that a real Mac client (`AvailabilityReporter.swift`) actually populates via an after-the-fact outbox report on every sync. 5 of 6 values (`needs_attention`, `downloading`, `queued`, `ready_offline`, `server_only`) are genuinely reachable end-to-end from real device facts. But the 6th, `missing_dependency`, is hardcoded `false` by the only writer that exists (`AvailabilityReporter.buildEntries`, line 141) with no other code path in the codebase ever setting it true — the chip is structurally dead in production, not merely 'less complete.' A value that discriminates correctly in a unit test that seeds the read model directly, but can never be made true by the one real client that exists, does not satisfy 'a user can find games through... readiness state' for that state: a user who selects that chip gets a permanently empty result with no way to ever populate it, which is a materially different (if less actively misleading) failure mode than the original always-everything pass-through, not an acceptable substitute for it. REQUIREMENTS.md was flipped to Complete for LIBR-02 on the strength of the SUMMARY's 'all six genuinely discriminate' framing, which is true of the LiveView clause logic but not true of production reachability — that flip is an overclaim and should be reverted to Pending, or LIBR-02's text explicitly narrowed by owner decision to exclude the missing-dependency state, with that narrowing recorded in WINDOWS.md. Neither has happened as of this verification. This finding originates from this session's own code review (03-REVIEW-GAPS.md Round 2, WR-06) and was independently confirmed here by direct source read of AvailabilityReporter.swift and a codebase-wide grep for any other writer of `missing_dependency`/`missingDependency` (none found)."
    artifacts:
      - path: "playstead-server/lib/playstead_web/live/library_live.ex"
        issue: "Resolved for the pass-through defect — matches_availability?/3 has one clause per value, no catch-all reaches a real filter value. Not an issue in itself; the gap is upstream, in what the Mac client ever reports."
      - path: "playstead-mac/Playstead/Cache/AvailabilityReporter.swift"
        issue: "Line 141 hardcodes `missingDependency: false` unconditionally for every entry — this is the actual remaining gap. No real signal exists in this codebase for 'a required member the catalogue names but is absent locally and not downloading/queued,' which is what this fact is supposed to mean."
    missing:
      - "Either implement a real Mac-client signal for missing_dependency (a required member present in the catalogue manifest but absent from CASManager and not currently downloading nor queued), or explicitly record in .planning/WINDOWS.md and get an owner decision narrowing LIBR-02's requirement text to the five reachable states, then correct REQUIREMENTS.md's Complete marking accordingly."
      - "Revert or caveat REQUIREMENTS.md line 37/134's 'Complete' marking for LIBR-02 until one of the above happens."
  - truth: "WR-04 (unvalidated `entries` payload → 500 instead of 422) and WR-05 (stale full-replacement availability report can be delivered out of order via outbox backoff) — non-blocking warnings from this session's own code review, recorded for tracking, not treated as phase-blocking on their own."
    status: open
    reason: "Confirmed genuine by this verification's own read of the review's cited lines (AvailabilityController.replace/2 has no shape guard on `entries` before calling Availability.replace_for_device/2; Outbox.listPending's backoff-skip ordering combined with AvailabilityReporter enqueuing a fresh unrelated row on every syncNow() pass means a backed-off earlier report can be delivered after a later one that succeeded first, temporarily showing stale facts). Neither one contradicts LIBR-02's core 'can a user find a game by availability' claim for the 5 reachable states, and both are pre-existing-pattern robustness gaps (a malformed body from a compromised/buggy device client; a rare backoff-interleaving race), not new correctness regressions in this session's diff beyond what they already introduce. Tracked here rather than as a hard gate because fixing them is not required to make the roadmap-level phase goal true, but they should not be lost."
    artifacts:
      - path: "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
        issue: "WR-04 — no shape validation on `entries` before it reaches a context function whose only guard is `is_list`; a non-list or non-map-element entry raises uncaught into a generic 500 instead of the sibling endpoints' 422."
      - path: "playstead-mac/Playstead/Sync/Outbox.swift"
        issue: "WR-05 — listPending's backoff-skip ordering, combined with AvailabilityReporter enqueuing an unrelated fresh row every syncNow() pass, allows an earlier backed-off full-replacement report to be delivered after a later one that already succeeded, temporarily reintroducing stale facts."
    missing:
      - "WR-04: validate entries is a list of maps before calling into Playstead.Availability, returning 422 :validation_failed like sibling endpoints."
      - "WR-05: supersede/cancel any still-pending or backed-off .availabilityReport outbox row before enqueuing a new one, since only the newest full-replacement report is ever meaningful."
behavior_unverified_items:
  - truth: "A user can connect, test, assign, remap, reset, and recover a controller (roadmap SC #5, controller-hardware portion)"
    test: "Connect a real, paired physical game controller; disconnect it mid-session; reconnect it."
    expected: "Connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without requiring a relaunch — matching what ControllerHost's unit tests already prove against an injectable ControllerInputSource."
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 recorded this as FAIL/unproven, and 03-10-SUMMARY.md's own D1 rationale states the same — all logic is unit-tested against a simulated input source only. Code is present and wired (ControllerHost is registered at AppEnvironment construction); only real-hardware behavior is unexercised. Unchanged by 03-13/03-14, regression-checked."
human_verification:
  - test: "Physical game controller connect/disconnect/reconnect recovery, live input test, remap, and reset on real hardware"
    expected: "Controller lifecycle logic behaves identically against a real device as it does against the injectable simulated input source in unit tests."
    why_human: "No physical or paired controller hardware exists in this execution environment. Reconciled against 03-UAT.md items 8 and 9 (both `blocked_by: physical-device`) and item 10's blocked sub-record (`physical-device-and-experiential-review`). Unchanged this session."
  - test: "Full end-to-end launch of the pinned mGBA adapter against a live paired server, with a downloaded game and installed emulator, from the notarized build, driven by a live interactive display session"
    expected: "Play starts the emulator, the game runs, SRAM periodically flushes, quitting returns to the library, and Gatekeeper accepts the app without any user override (this last part is proven — see 03-NOTARIZATION-EVIDENCE.md)."
    why_human: "This sandboxed/headless execution environment cannot render a live interactive display session for a human to watch a game actually run. Reconciled against 03-UAT.md item 7 (`blocked_by: third-party`). Unchanged this session."
  - test: "Visual/typographic fidelity and VoiceOver walkthrough of the LiveView console and the Mac library shell against 03-UI-SPEC.md"
    expected: "Spacing, color rendering, motion timing, and screen-reader sentence flow match the locked design contract on both surfaces."
    why_human: "Multiple SUMMARYs (03-05 D3/D7, 03-06 D2, 03-07 D6, 03-08 D3, 03-10 D2) state that only the markup-level/logic-level accessibility contract was automatically verified — no live NSAccessibility tree or interactive rendering was exercised. Reconciled against 03-UAT.md item 10's blocked sub-record. Unchanged this session."
  - test: "Drag-in BIOS validation against a real, legally-sourced BIOS file or supported open replacement"
    expected: "A correct BIOS file is accepted and stored under managed storage; an incorrect one is rejected with a clear reason."
    why_human: "What remains genuinely human-only is acceptance of real, legally-owned BIOS bytes: no real BIOS file exists in this execution environment, and none should. Reconciled against 03-UAT.md item 13 (`result: partial`). Unchanged this session."
  - test: "Implement or explicitly descope the missing_dependency availability signal on the Mac client, then re-run the LIBR-02 verdict"
    expected: "Either AvailabilityReporter reports a real, non-hardcoded missing_dependency fact for at least one code path, making that filter chip capable of returning a result in production, or an owner explicitly narrows LIBR-02's requirement text to the five states that are genuinely reachable and that narrowing is recorded in WINDOWS.md and REQUIREMENTS.md is corrected to match."
    why_human: "This is not hardware-blocked like the other four items — it is a code-completeness decision (implement the real signal, which needs a product decision about what 'missing dependency' means operationally, e.g. a required BIOS/firmware file absent from CASManager and not currently downloading) or a scope decision (accept 5/6 as sufficient and say so explicitly). Left as a decision item rather than an automatic code fix because 03-13-PLAN.md's own Task 1 checkpoint already shows this project treats availability-vocabulary scope questions as owner decisions, not something a verifier or executor should unilaterally resolve by picking an implementation."
---

# Phase 3: Mac Offline Play Vertical Slice Verification Report

**Phase Goal:** A newly paired Mac can browse a curated server library, download only chosen verified content, and launch one deliberately supported game offline through a tested adapter.
**Verified:** 2026-09-11T12:00:00Z
**Status:** gaps_found
**Re-verification:** Yes — this is an independent re-derivation after 03-13-PLAN.md and 03-14-PLAN.md executed a gap-closure pass against the LIBR-02 gap recorded in the prior 03-VERIFICATION.md. That prior file was last edited by the 03-14 executor itself; its LIBR-02 "resolved" claim is treated here as an unverified assertion, re-derived independently from source, tests, and this session's own code review rather than trusted.

## Verdict on LIBR-02 (the specific question this re-verification was asked to adjudicate)

**LIBR-02 is not genuinely closed. It is substantially improved but partially, not fully, resolved.**

What 03-13/03-14 genuinely fixed, confirmed by direct source read:
- The original defect — `matches_availability?/3`'s unconditional pass-through clause that let 4 of 6 documented values fall through unfiltered — is gone. Confirmed at `library_live.ex:182-208`: one explicit clause per frozen vocabulary value, delegating to `StatusSlot`'s rank ladder, with a fail-closed catch-all that itself refuses anything `AvailabilityVocabulary.valid?/1` doesn't recognize.
- A real device-reported read model now exists and is genuinely fed by a real Mac client: `Playstead.Availability`, `PUT /api/v1/devices/me/availability`, and `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` (an outbox producer invoked from `syncNow()`, confirmed wired at `PlaysteadApp.swift:804` and never on a launch path).
- 5 of 6 filter values (`needs_attention`, `downloading`, `queued`, `ready_offline`, `server_only`) are genuinely reachable end-to-end in production from real device facts.
- Authn/authz on the new endpoint is genuinely sound (per-device, per-user scoping tested with a real negative case), the shared vocabulary is genuinely single-sourced across Elixir/Swift/JSON with bidirectional negative-case tests, and the migration's constraints are correct.
- Regression-clean: server suite 1065 tests / 0 failures; Mac suite 645 tests / 0 failures.

What is **not** closed, confirmed by direct source read of `AvailabilityReporter.swift:141` and a codebase-wide grep finding no other writer:

`AvailabilityReporter.buildEntries` hardcodes `missingDependency: false` on every entry it ever produces, unconditionally, for every game. No other code path in this codebase ever sets `missing_dependency` true on a real device report. `library_live_test.exs`'s six-value discrimination test proves the *filter clause* discriminates correctly, but it proves this by seeding `missing_dependency: true` directly into the database, bypassing the one real client that exists — a passing contract test standing in for a production path that does not exist. The practical, user-facing consequence is that the `missing_dependency` filter chip will show zero results, permanently, in every real deployment: not "less complete" data, a structurally dead filter dimension. This is functionally the mirror image of the original defect (always-empty instead of always-everything) for one of the six documented values, and it was not caught by the gap-closure plan's own testing because the test never exercises the real client's reporting path for this fact.

This was independently surfaced by this session's own code review (03-REVIEW-GAPS.md Round 2, finding WR-06) and independently confirmed here by direct source read rather than accepted on the review's word — `grep -rn "missing_dependency\|missingDependency"` across both codebases finds exactly one writer (`AvailabilityReporter.swift:141`, hardcoded `false`) and no other production code path that could ever flip it.

**REQUIREMENTS.md's LIBR-02 checkbox (`- [x]`, line 37) and traceability row (`Complete`, line 134) are an overclaim.** They should be reverted to Pending, or the requirement text should be explicitly narrowed by an owner decision to the five reachable states (with that narrowing recorded in `.planning/WINDOWS.md`), before this can be marked Complete. Neither correction has been made as of this verification.

WR-04 (malformed `entries` payload crashes to 500 instead of 422) and WR-05 (a backed-off, out-of-order `.availabilityReport` outbox entry can temporarily reassert stale facts) were also confirmed genuine by direct read of the cited code. Both are real robustness gaps worth fixing, but neither contradicts the core "can a user find a game by availability" claim for the five reachable states, so they are tracked as open, non-blocking warnings rather than phase-blocking gaps.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | Unchanged from prior verification. See Requirements Coverage below for the narrower, requirement-level LIBR-02 caveat, which does not invalidate this roadmap-level truth as literally worded (the console does let a user browse, search, and filter — one of six availability filter values is unreachable in production, not the whole browse/search capability). |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | Unchanged — this is the Mac client's own `AvailabilityState.derive` six-state pure function (CACH-02), a distinct code path from the web console's filter (LIBR-02), confirmed by reading both; they share no implementation. |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; game launchable only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | Unchanged from prior verification; not touched by 03-13/03-14. |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ✓ VERIFIED | Unchanged from prior verification; not touched by 03-13/03-14. |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a **signed/notarized** build after app or server restart | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (controller-hardware portion) / ✓ VERIFIED (notarization portion) | Unchanged from prior verification; not touched by 03-13/03-14. |

**Score:** 4/5 roadmap truths fully verified; 1 partial (SC #5 — controller-hardware portion present-but-unverified, unchanged this session).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-server/lib/playstead_web/live/library_live.ex` | LIBR-02's full availability/readiness-state filter | ⚠️ PARTIAL | `matches_availability?/3` now has one clause per value with no pass-through (fixed). But one of the six facts it filters on (`missing_dependency`) can never be true in production — the defect has moved from "filter logic incomplete" to "filter logic complete, one input never populated." |
| `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` | Real device-reported availability facts | ⚠️ PARTIAL | Exists, substantive, wired (invoked from `syncNow()`, registered at `AppEnvironment`). 4 of 5 non-derived facts (`downloading`, `verified`, `pinned`, `download_percent`) are computed from real local state; the 5th (`missing_dependency`) is hardcoded `false` at line 141 with no real signal behind it. |
| `playstead-server/lib/playstead/availability.ex`, `availability_vocabulary.ex`, `availability_controller.ex` | Device-report ingestion, per-user merge, frozen vocabulary | ✓ VERIFIED | Authn/authz, cross-user isolation, vocabulary single-sourcing, and migration constraints all confirmed genuine by direct read this session. |
| `.planning/REQUIREMENTS.md` | Authoritative requirement traceability | ✗ INCORRECT for LIBR-02 | Marks LIBR-02 Complete (`[x]`, line 37; `Complete`, line 134). This is an overclaim per the finding above — should be Pending or explicitly narrowed. |
| `.planning/WINDOWS.md` | Known-stub ledger | ✗ MISSING ENTRY | Grepped for `missing_dependency` and `LIBR-02`: zero mentions. The gap-closure review's suggested fix option (b) — record this as a distinct, higher-visibility gap here — was not done. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `library_live.ex` availability chips | `matches_availability?/3` | `phx-click`/`handle_event` | ✓ WIRED | All six values now have an explicit clause; no pass-through remains. |
| `AvailabilityReporter.reportAll()` | `PUT /api/v1/devices/me/availability` | `Outbox` → `OutboxWorker` | ✓ WIRED (for 4 of 5 facts) / ✗ NEVER TRUE (for `missing_dependency`) | The transport and endpoint are genuinely wired and authenticated; the `missing_dependency` field is hardcoded false at the source, so no wiring failure exists — the fact itself is never computed. |
| `Playstead.Availability.facts_for_user/1` | `LibraryLive.status_for/2` | `StatusSlot.rank/1` | ✓ WIRED | Confirmed line-by-line by this session's code review; not re-litigated further here. |

### Behavioral Spot-Checks / Test Execution

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Server suite | `mix test` | 1065 tests, 0 failures | ✓ PASS |
| Mac suite | `xcodebuild test -scheme Playstead` | 645 tests, 0 failures | ✓ PASS |
| UAT tally self-check | `bash scripts/check-uat-tally.sh` | `OK: 03-UAT.md: total=44 blocked=3, partial=2, pass=39` (44 = 39+3+2+0, consistent) | ✓ PASS |
| Named contract test existence | `AvailabilityReporterTests`, `AvailabilityVocabularyContractTests` | Both suites exist and are named in `run-mac-verification.sh --required-test`; included in the 645-test Mac run above | ✓ PASS |

### Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| LIBR-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| LIBR-02 | ⚠️ PARTIAL | REQUIREMENTS.md marks Complete; this verification finds that overclaimed. 5 of 6 documented availability/readiness states are genuinely reachable via a real device-reported model with no pass-through defect (genuine, substantial progress since the prior verification, which found only 2 of 6 working). The 6th (`missing_dependency`) is structurally unreachable in production — hardcoded `false` at the only writer that exists. See Verdict section above for full reasoning. Recommend REQUIREMENTS.md be reverted to Pending or LIBR-02's text explicitly narrowed by owner decision, recorded in WINDOWS.md. |
| LIBR-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| LIBR-04 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| LIBR-05 | ? NEEDS HUMAN | REQUIREMENTS.md: Pending. Unchanged from prior verification. |
| CACH-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| CACH-02 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| CACH-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| CACH-04 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| PLAY-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| PLAY-02 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged. |
| PLAY-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged from prior verification (BIOS composition-root wiring, regression-checked this session). |
| PLAY-04 | ? NEEDS HUMAN | REQUIREMENTS.md: Pending. Unchanged from prior verification. |
| PLAY-05 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Unchanged from prior verification (real notarization, regression-checked this session). |
| QUAL-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. 03-13/03-14's own test suites (1065 + 645 tests, 0 failures) support this; not itself in question. |

No orphaned requirements found. **LIBR-02 remains the one substantively unresolved requirement**, now partial rather than fully blocked.

### Anti-Patterns Found

No debt markers (TBD/FIXME/XXX) found in 03-13/03-14's changed files. Three Warnings from this session's own code review (03-REVIEW-GAPS.md Round 2) are genuine and confirmed by this verification's own independent read:

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `AvailabilityReporter.swift` | 141 | Hardcoded `false` feeding a documented, user-facing filter dimension that no other code path can ever set true | 🛑 Blocker for full LIBR-02 closure (not a blocker for the phase's roadmap-level goal, which does not name this specific state) | The `missing_dependency` filter chip can never return a result in production. |
| `availability_controller.ex` | 24 | Unvalidated `entries` param shape, no guard before it reaches a function whose only clause requires `is_list` | ⚠️ Warning | A malformed client payload crashes to a generic 500 instead of the sibling endpoints' 422. |
| `Outbox.swift` / `AvailabilityReporter.swift` | 141-148 / 103-107 | Backoff-skip ordering can deliver an earlier full-replacement report after a later one that already succeeded | ⚠️ Warning | Transient staleness of the availability read model after a retry interleaving; self-corrects on the next `syncNow()`. |

Pre-existing WR-01/WR-02/WR-03 (BIOS crash-window orphan, `mktemp -u` race, fixed-sleep liveness checks) from Round 1 remain open, untouched by this session's scope.

### Human Verification Required

See `human_verification` in frontmatter — 5 items. Four are unchanged, legitimately hardware/experiential-only (physical controller, live emulator session, VoiceOver walkthrough, real BIOS bytes). The 5th replaces the prior file's incorrectly-closed LIBR-02 item: it is a code-completeness/scope decision (implement a real `missing_dependency` signal, or have an owner explicitly narrow LIBR-02 and record it in WINDOWS.md), not a hardware limitation — flagged here for prompt resolution rather than left open indefinitely.

### Gaps Summary

The gap-closure plans 03-13/03-14 delivered genuine, substantial, verifiable progress: the original LIBR-02 defect (4 of 6 filter values passing through unfiltered) is fully fixed, backed by a real device-reported read model with sound authn/authz, a single-sourced vocabulary, and clean regression runs (1065 server tests, 645 Mac tests, 0 failures). That should be credited.

However, this phase cannot be marked `passed` or have LIBR-02 marked Complete, because:

1. **One of the six documented filter values (`missing_dependency`) is structurally unreachable in production** — hardcoded `false` at its only writer, confirmed by direct source read and a codebase-wide grep finding no alternate writer. A passing unit test that seeds this fact directly into the database does not substitute for a reachable production path; this is exactly the "presence is not behavior" distinction this project's own verification discipline exists to catch, applied here to a data-completeness gap rather than a wiring gap.
2. **REQUIREMENTS.md's Complete marking for LIBR-02 is consequently an overclaim** and should be corrected — either reverted to Pending pending a real fix, or the requirement text narrowed by an explicit owner decision (recorded in WINDOWS.md) to the five states that are genuinely reachable.
3. The four pre-existing human/hardware-only items (physical controller, live emulator session, VoiceOver walkthrough, real BIOS bytes) remain open and are not gaps in the actionable sense — unchanged from the prior verification.
4. Two non-blocking warnings (WR-04, WR-05) confirmed genuine and tracked, not treated as phase-blocking.

Recommended next step: implement a real `missing_dependency` signal on the Mac client, or get an explicit owner decision narrowing LIBR-02 and update WINDOWS.md + REQUIREMENTS.md to match, then re-run this verification. Once LIBR-02 is genuinely resolved or explicitly and honestly narrowed, the remaining blockers are all human/hardware-only, at which point the correct terminal status becomes `human_needed` — but not `passed`, per this project's own gate rules, until every human-verification item is explicitly resolved by a human.

---

*Verified: 2026-09-11T12:00:00Z*
*Verifier: Claude (gsd-verifier)*
