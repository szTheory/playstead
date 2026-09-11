---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-11T00:00:00Z
status: gaps_found
score: 4/5 roadmap truths verified (1 partial — controller-hardware portion of SC5 present+wired but not behaviorally exercised); Requirements Coverage below carries 1 additional unresolved requirement (LIBR-02) not captured by the 5 numbered roadmap truths
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: "passed (frontmatter claim — INVALID, see Correction below)"
  previous_score: "5/5 (as claimed; not reproducible against the gate rules)"
  gaps_closed:
    - "PLAY-03 / roadmap SC #4: BiosStore's production reference set was empty (functionally inert). Independently re-verified: BiosReferences.production is now wired at PlaysteadApp's composition root (`grep -v '^\\s*//' PlaysteadApp.swift | grep -c 'references: BiosReferences.production'` = 1), backed by a real, 3-source-cited pin (03-BIOS-PIN.json) and BiosProductionReferenceTests. Genuine, not vacuous."
    - "PLAY-05 / roadmap SC #5 (notarization sub-claim): no genuinely notarized build had ever existed. Independently re-verified against 03-NOTARIZATION-EVIDENCE.md and the orchestrator's own direct tool runs: `stapler validate` succeeded, `spctl` names `source=Notarized Developer ID` with no override, `notarytool history` shows submission 8465f74d-5468-4b73-9885-fb0ea1dafcdd Accepted. Genuine, not vacuous."
  gaps_remaining:
    - "LIBR-02 (declared Phase 3 requirement): REQUIREMENTS.md still lists LIBR-02 as unchecked/Pending. Source-verified: `library_live.ex`'s `matches_availability?/3` only implements 2 of the 6 documented availability/readiness states (`queued`, `server_only`); the other four (`partial`, `verified-local`, `pinned-offline`, `safe-to-evict`) fall through to `true` (unfiltered). This is not new — 03-05-SUMMARY.md's own D3 rationale and 03-UAT.md item 4 (`blocked_by: prior-phase`, open since 2026-08-31) already disclosed it honestly — but it was never carried into the phase-level Requirements Coverage verdict, which instead marked LIBR-02 '✓ SATISFIED'. That was an overclaim. No later phase's success criteria address completing this (checked Phase 3.5, 4, 4.5, 5 in ROADMAP.md)."
  regressions: []
overrides: []
gaps:
  - truth: "A user can select or install one supported Mac adapter, see its exact system/emulator/version/content/BIOS/save support, validate a locally supplied BIOS or supported open replacement, and receive a preflight remedy for each blocking readiness condition."
    status: resolved
    resolved_at: 2026-09-10
    resolved_by: "03-11-PLAN.md"
    reason: "RESOLVED (composition-root wiring only — real-bytes acceptance stays operator-verified, tracked honestly rather than claimed). A real, two-independent-source-cited reference for the pinned gba system (16384-byte expected length, SHA-256 fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570, corroborated by higan's own documentation, the DS-Homebrew wiki, and GBATEK) is now pinned at .planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json and wired into PlaysteadApp's composition root via BiosReferences.production, closing the exact gap this entry named: BiosStore no longer has an empty reference set in production. Re-verified independently in this session by direct source read: BiosReferences.swift exists with the pinned literal, PlaysteadApp.swift line 498 passes `references: BiosReferences.production` to BiosStore's initializer (exactly 1 non-comment occurrence), and 03-BIOS-PIN.json carries a 3-source provenance array. What is NOT claimed as proven: acceptance of real, legally-owned BIOS bytes has not been exercised in this environment (no real BIOS file exists here to test against, and none should) — that remains the one operator-verified step, checkable in a single command via scripts/verify-bios-reference.sh."
    artifacts:
      - path: "playstead-mac/Playstead/Adapter/BiosStore.swift"
        issue: "None — the composition root now supplies BiosReferences.production instead of an empty array (PlaysteadApp.swift)."
      - path: "playstead-mac/Playstead/Adapter/BiosReferences.swift"
        issue: "None — re-read directly this session; production constant present, mirrors 03-BIOS-PIN.json, provenance URLs in doc comment."
      - path: ".planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json"
        issue: "None — re-read directly this session; provenance array with 3 independent citable sources for the pinned gba reference."
    missing: []
  - truth: "A user can launch one legally testable game through the supported adapter from a signed/notarized Mac build, exit safely, and relaunch it after an application or server restart."
    status: resolved
    resolved_at: 2026-09-11
    resolved_by: "03-12-PLAN.md"
    reason: "RESOLVED. The owner enrolled in the Apple Developer Program, installed a Developer ID Application certificate and a notarytool credential profile, and answered the 03-12-PLAN.md Task 2 blocking-human checkpoint 'enrolled'. Task 3 then ran scripts/verify-notarized-release.sh end to end against a real build: notarytool submit --wait returned status Accepted (submission 8465f74d-5468-4b73-9885-fb0ea1dafcdd), xcrun stapler staple/validate succeeded, and spctl --assess --type execute --verbose named source=Notarized Developer ID with no user override. Independently re-confirmed this session via the orchestrator's own direct tool runs on HEAD f8c0e67 (clean tree): `stapler validate` -> 'The validate action worked!' exit 0; `spctl --assess -vv` -> accepted, source=Notarized Developer ID, origin=Developer ID Application: Johnathan Bryan (6CH9Y797RU); `notarytool history` shows submission 8465f74d-5468-4b73-9885-fb0ea1dafcdd Accepted. RelaunchTests (2/2) ran against that exact notarized, exported artifact and passed."
    artifacts:
      - path: "playstead-mac/scripts/sign-and-notarize.sh"
        issue: "None — now runs a genuine notarized submission end to end in strict mode, proven against a real Developer ID Application identity."
      - path: "playstead-mac/scripts/verify-notarized-release.sh"
        issue: "None — the single end-to-end command this gap required."
      - path: ".planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md"
        issue: "None — re-read directly this session; verbatim tool output, submission ID matches independently-confirmed notarytool history."
    missing: []
  - truth: "Two CRITICAL path-traversal defects (CR-01, CR-02) identified in 03-REVIEW.md remain unpatched in the codebase."
    status: resolved
    resolved_at: 2026-09-10
    resolved_by: "03-REVIEW-FIX.md (2026-08-31)"
    reason: "RESOLVED. Regression-checked directly against current source this session (unchanged since prior verification). `playstead-mac/Playstead/App/PathSafety.swift` is the single validation point for every server-supplied string that becomes a path component: `isValidDigest` is a 64-char lowercase-hex allowlist; `AppPaths.objectURL(for:)` (line 117) and `partialURL(for:)` (line 128) both call `PathSafety.validatedDigest` and throw; `LaunchMaterializer.materialize` (line 60) calls `PathSafety.validatedFilename` and throws `MaterializationError.unsafeMember` rather than materializing a sanitized path. No regression found."
    artifacts:
      - path: "playstead-mac/Playstead/App/PathSafety.swift"
        issue: "None — re-read directly this session; unchanged, still the fix."
      - path: "playstead-mac/Playstead/Cache/LaunchMaterializer.swift"
        issue: "None — line 60 still calls validatedFilename and throws unsafeMember."
      - path: "playstead-mac/Playstead/App/AppPaths.swift"
        issue: "None — objectURL/partialURL still validate before building any path component."
    missing: []
  - truth: "LIBR-02: A user can quickly find games through search, filters, systems, and availability or readiness state."
    status: resolved
    resolved_by: "03-13-PLAN.md, 03-14-PLAN.md"
    reason: "Built: a device-reported, per-user-merged availability read model (03-13: Playstead.Availability, PUT /api/v1/devices/me/availability, cache capability 1.1.0) backing a six-value console filter (03-13: LibraryLive.matches_availability?/3, one clause per value, no pass-through) that is now actually fed by a real device (03-14: Playstead/Cache/AvailabilityReporter.swift, an after-the-fact outbox producer wired at AppEnvironment's composition root and invoked from syncNow(), never a launch path). Commands that proved it this session: `cd playstead-mac && xcodebuild test -scheme Playstead -destination 'platform=macOS' -only-testing:PlaysteadTests/AvailabilityReporterTests -only-testing:PlaysteadTests/AvailabilityVocabularyContractTests` (16 tests, 0 failures) and `cd playstead-server && mix test` (1065 tests, 0 failures, at the 03-13 baseline). Mapping note: this gap's original text (above) characterized the six values as \"partial, verified-local, pinned-offline, safe-to-evict\" plus queued/server-only — that was CACH-02 wording, the Mac client's own six-case AvailabilityState ladder. The console's actual six filter values instead follow 03-UI-SPEC.md's locked Search and filters table and D-13 (03-13-SUMMARY.md's key-decision): `needs_attention`, `missing_dependency`, `downloading`, `ready_offline` (pinned/verified merged), `queued`, `server_only` — a UI-SPEC-native vocabulary, not a re-exposure of AvailabilityState's ladder. `safe_to_evict` is deliberately excluded (storage-view-only concept, never a console filter chip per D-13)."
    artifacts:
      - path: "playstead-server/lib/playstead_web/live/library_live.ex"
        issue: "Resolved — matches_availability?/3 now has one clause per UI-SPEC value, no pass-through (03-13); the read model behind it is now genuinely fed by a real device (03-14)."
      - path: "playstead-mac/Playstead/Cache/AvailabilityReporter.swift"
        issue: "Resolved — the Mac client actually reports its availability facts; before 03-14 this file did not exist and no device ever wrote to the read model 03-13 built."
    missing: []
behavior_unverified_items:
  - truth: "A user can connect, test, assign, remap, reset, and recover a controller (roadmap SC #5, controller-hardware portion)"
    test: "Connect a real, paired physical game controller; disconnect it mid-session; reconnect it."
    expected: "Connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without requiring a relaunch — matching what ControllerHost's unit tests already prove against an injectable ControllerInputSource."
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 recorded this as FAIL/unproven, and 03-10-SUMMARY.md's own D1 rationale states the same — all logic is unit-tested against a simulated input source only. Code is present and wired (ControllerHost is registered at AppEnvironment construction); only real-hardware behavior is unexercised."
human_verification:
  - test: "Physical game controller connect/disconnect/reconnect recovery, live input test, remap, and reset on real hardware"
    expected: "Controller lifecycle logic behaves identically against a real device as it does against the injectable simulated input source in unit tests."
    why_human: "No physical or paired controller hardware exists in this execution environment. Reconciled against 03-UAT.md items 8 and 9 (both `blocked_by: physical-device`) and item 10's blocked sub-record (`physical-device-and-experiential-review`)."
  - test: "Full end-to-end launch of the pinned mGBA adapter against a live paired server, with a downloaded game and installed emulator, from the notarized build, driven by a live interactive display session"
    expected: "Play starts the emulator, the game runs, SRAM periodically flushes, quitting returns to the library, and Gatekeeper accepts the app without any user override (this last part is now proven — see 03-NOTARIZATION-EVIDENCE.md)."
    why_human: "This sandboxed/headless execution environment cannot render a live interactive display session for a human to watch a game actually run. Reconciled against 03-UAT.md item 7 (`blocked_by: third-party` — requires the pinned emulator installed locally plus a real downloaded game, neither of which can ship in CI)."
  - test: "Visual/typographic fidelity and VoiceOver walkthrough of the LiveView console and the Mac library shell against 03-UI-SPEC.md"
    expected: "Spacing, color rendering, motion timing, and screen-reader sentence flow match the locked design contract on both surfaces."
    why_human: "Multiple SUMMARYs (03-05 D3/D7, 03-06 D2, 03-07 D6, 03-08 D3, 03-10 D2) state that only the markup-level/logic-level accessibility contract was automatically verified (aria attributes, accessible names, a declarative accessibility-manifest walk) — no live NSAccessibility tree or interactive rendering was exercised. Reconciled against 03-UAT.md item 10's blocked sub-record (experiential VoiceOver pronunciation/sentence-quality review, distinct from its separately-passing automated keyboard/live-tree record)."
  - test: "Drag-in BIOS validation against a real, legally-sourced BIOS file or supported open replacement"
    expected: "A correct BIOS file is accepted and stored under managed storage; an incorrect one is rejected with a clear reason."
    why_human: "03-11-PLAN.md resolved the composition-root wiring gap (see gaps above) — BiosReferences.production now carries a real, cited reference and BiosProductionReferenceTests proves it is reached. What remains genuinely human-only is acceptance of real, legally-owned BIOS bytes: no real BIOS file exists in this execution environment, and none should. Reconciled against 03-UAT.md item 13 (`result: partial`)."
  - test: "Complete LIBR-02's availability/readiness-state filter, or record an explicit owner decision to descope it, then re-run the console find-a-game UX review"
    expected: "Either the console lets a user filter by all 6 documented availability/readiness states, or REQUIREMENTS.md's LIBR-02 text is explicitly narrowed by owner decision to match what was actually built (queued/server-only only), at which point it can be checked off."
    why_human: "RESOLVED by the build path, not a descope decision (03-13-PLAN.md, 03-14-PLAN.md): the console now genuinely filters by all six UI-SPEC availability/readiness values over device-reported facts a real Mac client actually sends. See the `gaps` entry above for the full mapping and the tests that proved it. REQUIREMENTS.md's LIBR-02 checkbox is checked as of this plan. 03-UAT.md item 4 is `pass` (previously `blocked_by: prior-phase`, open since 2026-08-31)."
---

# Phase 3: Mac Offline Play Vertical Slice Verification Report

**Phase Goal:** A newly paired Mac can browse a curated server library, download only chosen verified content, and launch one deliberately supported game offline through a tested adapter.
**Verified:** 2026-09-11T00:00:00Z
**Status:** gaps_found
**Re-verification:** Yes — this is an independent re-derivation after 03-11-PLAN.md (BIOS composition-root wiring) and 03-12-PLAN.md (notarization) executed against the two gaps recorded in the 2026-08-30 initial verification.

## Correction to the Prior VERIFICATION.md

The version of this file left by the 03-12 executor had frontmatter `status: passed` with a **non-empty `human_verification` array containing 4 items** in that same frontmatter block. Per this project's own verifier gate rules, `passed` is only valid when the human-verification section is empty — any human-verification item forces `human_needed` at minimum, and any FAILED must-have forces `gaps_found` ahead of that. That prior status was **not reproducible against the gate it is supposed to satisfy**, independent of anything else found in this session. This report corrects it.

Separately, this session found that the prior file's Requirements Coverage table marked **LIBR-02 "✓ SATISFIED"** while the project's own `.planning/REQUIREMENTS.md` has never checked that requirement off and 03-UAT.md has carried it as `blocked` since 2026-08-31. That is a second, independent overclaim, unrelated to the two gaps 03-11/03-12 closed. Both corrections are reflected below.

## What This Session Independently Re-Verified as Genuinely Closed

Both gap-closure plans hold up under direct source inspection — this is real, non-vacuous work:

1. **PLAY-03 / BIOS composition-root wiring (03-11-PLAN.md).** `playstead-mac/Playstead/Adapter/BiosReferences.swift` exists and defines `BiosReferences.production` with the pinned `gba` reference (16384 bytes, SHA-256 `fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570`). `PlaysteadApp.swift:498` passes `references: BiosReferences.production` into `BiosStore`'s initializer — confirmed by direct read, exactly 1 non-comment occurrence. `03-BIOS-PIN.json` carries a 3-source provenance array (higan docs, DS-Homebrew wiki, GBATEK). This is a real fix to a previously-empty, functionally-inert reference set.
2. **PLAY-05 / real notarization (03-12-PLAN.md).** `03-NOTARIZATION-EVIDENCE.md` contains verbatim `notarytool submit --wait` output showing submission `8465f74d-5468-4b73-9885-fb0ea1dafcdd` reaching `status: Accepted`. This matches the orchestrator's own independently-run confirmation commands on HEAD `f8c0e67` (`stapler validate`, `spctl --assess`, `notarytool history`), all of which this verifier treats as primary evidence rather than SUMMARY narration.
3. **CR-01/CR-02 path-traversal fixes (regression-checked, untouched by 03-11/03-12).** `PathSafety.swift`, `AppPaths.swift`, and `LaunchMaterializer.swift` still enforce allowlist validation at both ingest and path-construction. No regression.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | Unchanged from prior verification — 03-03 (Mac snapshot read, zero bytes downloaded), 03-05/03-06 (LiveView console + Mac library shell), extensive test coverage. See Requirements Coverage below for a narrower, requirement-level caveat (LIBR-02) that does not invalidate this roadmap-level truth as literally worded. |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | Unchanged — 03-02 (Range/If-Range/206/416/HEAD contract), 03-07 (DownloadQueue, `AvailabilityState.derive` six-state pure function, exhaustively tested). Note: this is the *Mac client's* six-state derivation (CACH-02), a distinct code path from the web console's partial availability filter (LIBR-02, below) — confirmed by reading both; they do not share an implementation. |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; game launchable only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | Unchanged — 03-07 (QuotaManager, PinStore, EvictionPlanner), 03-03/03-09 (PreflightChecker/ReadinessEngine, zero-network-call proof). |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ✓ VERIFIED | 03-09 delivers AdapterInstaller/AdapterCapabilityCard/ReadinessEngine. BIOS-validation sub-claim now genuinely wired (see above) — `BiosProductionReferenceTests` (3/3) proves a correctly-sized non-matching candidate reaches digest comparison rather than being refused for "no known reference." Acceptance of real, legally-owned BIOS bytes remains unproven in this environment (see human_verification) — that carve-out does not diminish this truth as literally worded ("validate a locally supplied BIOS," which the wiring now genuinely does for well-formed candidates). |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a **signed/notarized** build after app or server restart | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (controller-hardware portion) / ✓ VERIFIED (notarization portion) | Notarization: genuinely closed, see above and 03-NOTARIZATION-EVIDENCE.md. Controller lifecycle: implemented and unit-tested against a simulated `ControllerInputSource`, registered at `AppEnvironment` construction, but never exercised against real hardware (probe 5, FAIL/unproven; no physical controller was ever available). This portion is present and wired, not behaviorally proven — routed to human_verification, not counted as VERIFIED. |

**Score:** 4/5 roadmap truths fully verified; 1 partial (SC #5 — notarization portion closed this session, controller-hardware portion present-but-unverified).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Adapter/BiosReferences.swift` | Real, cited production BIOS reference | ✓ VERIFIED | Re-read directly this session; present, substantive, wired into `PlaysteadApp.swift:498`. |
| `playstead-mac/Playstead/Adapter/BiosStore.swift` | BIOS validation logic + reference-set seam | ✓ VERIFIED (wired) | No longer orphaned — production reference set is non-empty, reached at the composition root. |
| `playstead-mac/scripts/sign-and-notarize.sh` / `verify-notarized-release.sh` | Signed, notarized release pipeline | ✓ VERIFIED | Ran for real against a Developer ID Application identity; evidence in `03-NOTARIZATION-EVIDENCE.md`, cross-confirmed by the orchestrator's own independent tool runs. |
| `playstead-mac/Playstead/App/PathSafety.swift`, `AppPaths.swift`, `Cache/LaunchMaterializer.swift` | CR-01/CR-02 path-traversal fix | ✓ VERIFIED | Regression-checked; unchanged, still enforcing allowlist validation. |
| `playstead-server/lib/playstead_web/live/library_live.ex` | LIBR-02's full availability/readiness-state filter | ⚠️ PARTIAL | `matches_availability?/3` implements 2 of 6 documented states; the rest pass through unfiltered. See gaps. |
| `.planning/REQUIREMENTS.md` | Authoritative requirement traceability | ✓ VERIFIED (as ground truth) | Correctly withholds "Complete" for LIBR-02, LIBR-05, and PLAY-04 — this document's own Pending markers turned out to be more accurate than the prior VERIFICATION.md's Requirements Coverage table. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `PlaysteadApp.swift` composition root | `BiosStore` | `BiosReferences.production` argument | ✓ WIRED | Exactly 1 non-comment occurrence, confirmed by direct grep this session. |
| `verify-notarized-release.sh` | Apple notary service | `notarytool submit --wait` | ✓ WIRED | Submission `8465f74d-...` reached `status: Accepted`, independently confirmed via `notarytool history`. |
| `LaunchMaterializer`/`AppPaths` | `PathSafety` | direct function calls, typed throws | ✓ WIRED | Unchanged, regression-checked. |
| `library_live.ex` availability chips | `matches_availability?/3` | `phx-click`/`handle_event` | ⚠️ PARTIAL | Wired for the 2 implemented states; the other 4 have no corresponding discrimination logic. |

### Requirements Coverage

All 15 declared requirement IDs for Phase 3 were cross-referenced against `.planning/REQUIREMENTS.md`'s own checkbox and traceability-table state (not against plan SUMMARY `requirements-completed` claims, which are self-reported and in at least 3 cases — LIBR-02, LIBR-05, PLAY-04 — contradicted by REQUIREMENTS.md's own Pending marking).

| Requirement | Status | Evidence |
|-------------|--------|----------|
| LIBR-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| LIBR-02 | ✗ BLOCKED | REQUIREMENTS.md: Pending (never checked, across every commit in project history). Source-verified incomplete: `matches_availability?/3` covers 2 of 6 documented states. Disclosed since 2026-08-30 (03-05-SUMMARY D3), open in 03-UAT.md item 4 since 2026-08-31, still open today. Not deferred to any later phase. **New gap this session** — the prior VERIFICATION.md incorrectly marked this "✓ SATISFIED." |
| LIBR-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| LIBR-04 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| LIBR-05 | ? NEEDS HUMAN | REQUIREMENTS.md: Pending. Underlying surfaces (ImportLive, ImportSessionsLive, DevicesLive/approval_card) exist in the same Phoenix router/app as LibraryLive, but 03-05-SUMMARY's own D3 coverage entry marks this `human_judgment: true` with an unresolved find-a-game UX review. Routed to human_verification (owner scope decision), not classified as a hard code-absence gap. |
| CACH-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| CACH-02 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| CACH-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| CACH-04 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| PLAY-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| PLAY-02 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |
| PLAY-03 | ✓ SATISFIED | REQUIREMENTS.md: Complete. Gap closed this session (see above); composition-root wiring genuinely reaches the digest comparison. Real-byte acceptance remains an operator step, consistent with REQUIREMENTS.md marking this Complete for the wiring-level claim the requirement text actually makes ("drag in ... for validation"). |
| PLAY-04 | ? NEEDS HUMAN | REQUIREMENTS.md: Pending. Controller lifecycle logic complete and unit-tested; real-hardware behavior unproven (no hardware available in this environment). Correctly withheld by REQUIREMENTS.md. |
| PLAY-05 | ✓ SATISFIED | REQUIREMENTS.md: Complete (flipped by 03-12-PLAN.md, independently re-confirmed this session against real notarization evidence). |
| QUAL-01 | ✓ SATISFIED | REQUIREMENTS.md: Complete. |

No orphaned requirements found. **One requirement (LIBR-02) is a new gap surfaced by this re-verification**, not created by 03-11/03-12 but never previously carried into a Requirements Coverage verdict correctly.

### Anti-Patterns Found

No new anti-patterns from 03-11/03-12's changed files (`BiosReferences.swift`, `BiosStore.swift`, `PlaysteadApp.swift`, `sign-and-notarize.sh`, `verify-notarized-release.sh`). Both plans' SUMMARYs document Rule-1 bug fixes found and fixed during real execution (vacuous `-only-testing` filters matching 0 tests, a missing `codesign -dvvv` flag, notarytool's raw-`.app` rejection) — these read as genuine debugging discoveries, not swept-under-rug defects, and are documented with commit references in both SUMMARYs.

The pre-existing WR-01 through WR-04 warnings from the original code review remain open (OutboxWorker ordering, unbounded digest-mismatch retry, swallowed errors in AppPaths/CASManager) — untouched by this session's scope, not re-litigated here.

### Human Verification Required

See `human_verification` in frontmatter — 5 items, reconciled against `03-UAT.md`'s actual per-item results (not its stale aggregate footer — see note below): physical controller hardware (items 8, 9, and 10's blocked sub-record), a live interactive emulator session (item 7), VoiceOver experiential walkthrough (item 10's blocked sub-record), real BIOS-byte acceptance (item 13), and an owner scope decision on LIBR-02's remaining availability states (item 4).

**Note on 03-UAT.md's own internal inconsistency:** This session counted 03-UAT.md's 44 numbered items directly (`grep -c '^### [0-9]+\.'`) and found the true per-item distribution is **38 pass, 4 blocked (items 4, 7, 8, 9), 2 partial (items 10, 13), 0 skipped** — not the file's own "Current Test" annotation line ("5 blocked ... items 4, 7, 8, 9, 11" — item 11 is actually `pass`) nor its "Summary" footer ("total: 44, passed: 31, blocked: 12, skipped: 1"), both of which are stale and do not match the file's own body. The orchestrator's briefing figure of "12 blocked" traces to this stale footer, not the ground truth in the file. This is a documentation-hygiene defect in 03-UAT.md itself, separate from the phase's functional gaps, and should be fixed (recompute and rewrite the footer) the next time this file is touched.

### Gaps Summary

Two of the three previously-recorded gaps in this file (BIOS composition-root wiring, notarization) are **genuinely, verifiably closed** — this session independently confirmed both by reading the actual current source and evidence files rather than trusting either plan's SUMMARY prose, and found no vacuous checks, no empty reference sets, and a real Apple notarization acceptance. That is substantial, real progress and should be credited as such.

However, this phase cannot be marked `passed`:

1. **The prior file's own `status: passed` was invalid on its face** — it carried a non-empty `human_verification` array in the same frontmatter block, which this project's own gate rules say forces at least `human_needed`. This is corrected here.
2. **LIBR-02 is a genuine, undeferred, source-verified gap** — the web console's availability/readiness-state filter covers 2 of 6 documented states, has been openly disclosed since 2026-08-30, and was never resolved or explicitly descoped by an owner decision. The prior Requirements Coverage table incorrectly marked it "✓ SATISFIED," which this re-verification corrects to ✗ BLOCKED.
3. Four items remain legitimately human/hardware-only and are not gaps in the actionable sense (physical controller, live emulator session, VoiceOver walkthrough, real BIOS bytes) — these were already honestly disclosed by the executors and are preserved here.

Recommended next step: either complete LIBR-02's remaining 4 availability states in `library_live.ex`, or record an explicit owner decision narrowing LIBR-02's requirement text to match what was actually built, then re-run this verification. Once that is resolved, the remaining blockers are all human/hardware-only, at which point the correct terminal status is `human_needed`, not `gaps_found` — but that is not automatically `passed` either, per this project's own gate rules, until every human-verification item is explicitly resolved by a human.

**Post-verification note (03-14-PLAN.md, LIBR-02 gap closure, build path taken):** The gap and human_verification entries above are the frozen historical record of what this session found and are left as written. The `gaps` entry for the LIBR-02 truth (near the top of this file's frontmatter) and its corresponding `human_verification` entry have been updated in place to `resolved` by 03-13-PLAN.md and 03-14-PLAN.md, with the commands that proved it — see those entries for the full mapping. This top-level `status:` field is deliberately left `gaps_found`, unchanged by this note: the remaining human-verification items (physical controller, live emulator session, VoiceOver walkthrough, real BIOS bytes) still require an independent re-verification to move this phase's terminal status forward, and this plan does not claim to be that re-verification.

---

*Verified: 2026-09-11T00:00:00Z*
*Verifier: Claude (gsd-verifier)*
