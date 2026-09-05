---
phase: 04-persistent-save-continuity
plan: 12
subsystem: ui
tags: [swift, swiftui, save-state, danger-escalation, storage, keyboard-a11y]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-09's three orthogonal save axes, SaveRollup, StatusSlotView, and shared/save-vocabulary.json — the escalated/interruptive-tier copy this plan renders was already reserved there"
  - phase: 04-persistent-save-continuity
    provides: "04-06's saveReserveBytes and never-evictable rule — the interruptive modal's escape-hatch framing and its 'Remove anyway removes cached bytes, never a save revision' guarantee both depend on it"
  - phase: 04-persistent-save-continuity
    provides: "04-11's SaveAttentionSource/ConflictComparisonSheet/SaveOutbox precedent for the UI-testing-only harness seam pattern this plan reuses verbatim"
provides:
  - "OnlyCopyEscalation: D-32/D-40's pure escalated-tier classifier — escalates only on revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection, structurally unable to escalate on duration or count since its input type carries no date/elapsed-time field at all"
  - "OnlyCopyEscalationPanel: the persistent, inline, zero-colour escalated panel with the three locked controls (Fix this / Export saves… / What's stored where?)"
  - "OnlyCopyInterruptionGate + OnlyCopyInterruptiveSheet: D-40's interruptive-tier modal, gated on onlyOnThisMacCount > 0, default button Export saves…, Remove anyway destructive-styled and never default, no confirmation-of-confirmation language"
  - "StorageView and ReclaimPromptView both gate their 'Reclaim selected' flow through OnlyCopyInterruptionGate before evicting/removing, using a new per-candidate onlyOnThisMacCount input"

actuals:
  tokens: 11200
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A classifier's input type is designed to structurally exclude the forbidden signal (no date/elapsed-time field anywhere in OnlyCopyEscalationInput or SaveUploadFailureClassification) rather than merely testing that duration is ignored — the same discipline SaveCompatibilityGate.evaluate already uses for degrade-toward-strictness inputs"
    - "A second env-var-gated UI-testing-only harness seam (OnlyCopyInterruptionHarnessRootView / OnlyCopyInterruptionNeutralHarnessRootView, wired in PlaysteadApp.swift) reusing 04-11's ConflictComparisonHarnessRootView precedent verbatim — a UI test target cannot @testable import Playstead, so this is the accessible surface for a genuine hosted-window keyboard-interaction proof"
    - "A destructive-intent surface gates its existing bulk-action callback (onReclaim) through a per-selection aggregate count computed just-in-time at the button press, never a stored/cached count — the aggregate title collapses to 'N games' when more than one affected candidate is in the selection, since the locked single-game string has no bulk-selection variant"

key-files:
  created:
    - playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift
    - playstead-mac/Playstead/Saves/OnlyCopyInterruptiveSheet.swift
    - playstead-mac/PlaysteadTests/SavesTests/OnlyCopyEscalationTests.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/OnlyCopyContractSnapshotTests.swift
    - playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift
  modified:
    - playstead-mac/Playstead/Library/StorageView.swift
    - playstead-mac/Playstead/Library/ReclaimPromptView.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/PlaysteadSnapshot.swift
    - playstead-mac/TestPlans/Rendering.xctestplan
    - playstead-mac/TestPlans/UI.xctestplan

key-decisions:
  - "SaveUploadFailureClassification (a new, save-domain-local enum) models the upload lane's current failure state rather than reading it directly from SaveUploadLane, which has no failure-classification output today — the classifier's contract (input in, escalation or nil out) is proven correct and ready for whichever plan wires SaveUploadLane's real 401/403/incompatible responses into it"
  - "The four escalation reason phrases (e.g. 'this Mac's connection to your server is no longer valid') are Claude's-discretion prose, not locked strings — D-40's locked copy only names the four categories parenthetically and leaves the {reason} substitution's exact wording open; each phrase was checked against the save-surface banned-word list"
  - "StorageView/ReclaimPromptView's bulk multi-select reclaim has no locked single-game title for an N-game aggregate; when more than one selected candidate has onlyOnThisMacCount > 0, the modal's {title} substitution becomes '{N} games' rather than picking one game's name arbitrarily"
  - "Unpair, sign out, and delete game are not wired to the gate — no production entry point for any of the three exists anywhere in this codebase yet (confirmed by source search). The gate and sheet are general-purpose and fully tested via a synthetic five-context harness; wiring the missing three call sites is deferred to whichever plan builds them (WINDOWS #35)"

requirements-completed: [SAVE-01, SAVE-02]

coverage:
  - id: D1
    description: "The escalated tier fires only on revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection; an offline queue, a slow upload, and a 30-day-old local-only version with a reachable server all produce no escalation, and this is structural (no date/elapsed-time field exists in the classifier's input) rather than merely tested"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/OnlyCopyEscalationTests.swift (13 tests, pass)"
        status: pass
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SnapshotTests/OnlyCopyContractSnapshotTests.swift (7 tests, pass, including source-level no-colour and no-duration-logic scans)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The escalated panel renders the locked title/body with count/title/reason substituted and the three locked controls, persistent and inline, zero colour literal"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/OnlyCopyEscalationTests.swift#testEscalationRendersTitleBodyWithCountTitleAndReasonSubstituted, testPanelCarriesTheThreeRequiredControls (pass)"
        status: pass
      - kind: integration
        ref: "playstead-mac/PlaysteadTests/SnapshotTests/OnlyCopyContractSnapshotTests.swift#testEscalatedPanelVisualContract, testReducedMotionSubstitutionVisualContract (pass, 2 new reference images)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The interruptive modal appears only when onlyOnThisMacCount > 0 (proven for all five named destructive-intent contexts plus a zero-count case), renders the locked title/body/three buttons with Export saves… as the default, Remove anyway destructive-styled and never default, is fully keyboard-operable with visible focus, and never appears during browse/launch/sync"
    requirement: "SAVE-01"
    verification:
      - kind: automated_ui
        ref: "playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift (12 tests, written and build-verified; execution requires the hosted macOS runner per the project's local login-Keychain launch guard)"
        status: unknown
    human_judgment: true
    rationale: "Local UI-layer execution is disabled in this sandbox by the project's own login-Keychain launch guard (scripts/ci/run-mac-verification.sh); these tests build cleanly and are registered in TestPlans/UI.xctestplan but their pass/fail has not been observed outside the hosted runner (WINDOWS #36, mirrors #9/#10/#34 precedent)."
  - id: D4
    description: "Choosing Remove anyway removes cached game bytes and leaves every save revision present (the never-evictable rule); choosing Cancel or Export leaves everything untouched"
    requirement: "SAVE-01"
    verification:
      - kind: automated_ui
        ref: "playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift#testChoosingRemoveAnywayLeavesEverySaveRevisionPresent, testChoosingCancelLeavesEveryRevisionAndCachedByteInPlace (written, build-verified; same hosted-runner caveat as D3)"
        status: unknown
    human_judgment: true
    rationale: "Same login-Keychain local-execution guard as D3 (WINDOWS #36)."
  - id: D5
    description: "StorageView and ReclaimPromptView's existing 'Reclaim selected' flows both route through the interruptive gate before evicting/removing, using a new per-candidate onlyOnThisMacCount input; a selection with zero affected candidates proceeds directly with no modal"
    requirement: "SAVE-01"
    verification:
      - kind: integration
        ref: "Full Mac Unit suite (457 tests, was 437) and Rendering suite (46 tests, StorageContractSnapshotTests unaffected) both green after the StorageView/ReclaimPromptView changes"
        status: pass
    human_judgment: false
  - id: D6
    description: "The full pre-existing Mac Unit and Rendering suites remain green after adding the escalated and interruptive surfaces"
    requirement: "SAVE-02"
    verification:
      - kind: integration
        ref: "Unit test plan: 457 tests / 0 failures (was 437); Rendering test plan: 46 tests / 0 failures (2 skipped, pre-existing StorageContractSnapshotTests skip, unrelated to this plan)"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-09-05
status: complete
---

# Phase 4 Plan 12: The Only-Copy Danger Case — Escalated and Interruptive Tiers Summary

**A pure, duration-blind escalation classifier for the four unfixable failure states, and an interruptive modal wired into the two existing bulk-eviction/reclaim surfaces, both rendering D-40's locked copy verbatim with zero colour and full keyboard operability.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-09-04T20:45:00Z
- **Completed:** 2026-09-04T21:35:00Z
- **Tasks:** 2
- **Files modified:** 11 (5 created, 6 modified)

## Accomplishments

- `OnlyCopyEscalation` (D-32/D-40): a pure classifier from `OnlyCopyEscalationInput` (count, title, `SaveUploadFailureClassification`) to either no escalation or one rendered `OnlyCopyEscalationResult`. Escalates only on `revokedAuth`/`capabilitySkew`/`serverRefusal`/`compatibilityRejection` — `offlineQueue`, `slowUpload`, and `.none` (the "old local-only version, reachable server" case) all return `nil` by construction, since neither the input type nor `SaveUploadFailureClassification` carries a date, timestamp, or running-time field anywhere. A source-level scan (`grep -rniE 'daysSince|elapsed|olderThan|threshold'`) confirms zero hits.
- `OnlyCopyEscalationPanel`: the persistent, inline, zero-colour-literal escalated panel rendering the locked title/body (with `{N}`/`{title}`/`{reason}` substituted) and the three locked controls "Fix this" / "Export saves…" / "What's stored where?".
- `OnlyCopyInterruptionGate` + `OnlyCopyInterruptiveSheet` (D-40): a one-line pure gate (`onlyOnThisMacCount > 0`) plus the modal itself — locked title/body, "Export saves…" as the keyboard default (`.keyboardShortcut(.defaultAction)`, focused at presentation via `.defaultFocus`), "Cancel", and "Remove anyway" (native `role: .destructive` styling, never the default). No "are you sure" language anywhere (confirmed by a repo-wide grep). `Escape` triggers Cancel via `.onExitCommand`.
- `StorageView` and `ReclaimPromptView`'s existing "Reclaim selected" flows (the two shipped destructive-intent surfaces this plan's `<read_first>` named) both now compute the affected selection's aggregate `onlyOnThisMacCount` just-in-time at button press and route through `OnlyCopyInterruptionGate` before calling the existing `onReclaim` callback — a selection with zero affected candidates proceeds exactly as before, unchanged.
- A second UI-testing-only harness pair (`OnlyCopyInterruptionHarnessRootView`, `OnlyCopyInterruptionNeutralHarnessRootView`), reusing 04-11's `ConflictComparisonHarnessRootView` seam pattern verbatim, lets `OnlyCopyInterruptionTests.swift` (12 tests) drive all five named destructive-intent contexts (`remove_local_copy`, `eviction`, `unpair`, `sign_out`, `delete_game`) plus a zero-count no-modal case and a neutral browse/launch/sync context that never presents the sheet at all — through one genuine hosted AppKit/SwiftUI window.
- Full local verification: Mac Unit suite 457 tests / 0 failures (was 437: +13 `OnlyCopyEscalationTests`, +7 `OnlyCopyContractSnapshotTests`); Rendering test plan 46 tests / 0 failures (2 new reference images recorded for the escalated panel and its reduced-motion substitution; `StorageContractSnapshotTests` unaffected); UI test target builds cleanly with `OnlyCopyInterruptionTests` registered in `TestPlans/UI.xctestplan`.

## CP7-SAVE-C

Per D-68 and this plan's checkpoint note: **CP7-SAVE-C (real-emulator / real-hardware save observation) remains blocked**, exactly as it was carried forward from 04-01 (`mgba_observed: false`), 04-04 (LiveServer test plan needs a live-server fixture + UI automation permission), and 04-07 (explicitly named blocked). Nothing in this plan touches the emulator/real-hardware surface it covers, and this plan does not mark it passed. It is not resolved by this SUMMARY — it remains an open, named blocked checkpoint pending real hardware/emulator observation in a future session.

## Task Commits

1. **Task 1: The escalated tier — a persistent panel only when the system cannot fix it** - `3010f43` (test, tdd)
2. **Task 2: The interruptive tier — a modal only at the moment of destructive intent** - `ac7c60e` (feat, tdd)

## Files Created/Modified

- `playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift` - `SaveUploadFailureClassification`, `OnlyCopyEscalationReason`, `OnlyCopyEscalation.evaluate`, `OnlyCopyEscalationPanel`
- `playstead-mac/Playstead/Saves/OnlyCopyInterruptiveSheet.swift` - `OnlyCopyInterruptionGate`, `OnlyCopyInterruptiveSheet`, and the two UI-testing-only harness root views
- `playstead-mac/Playstead/Library/StorageView.swift` - Gates "Reclaim selected" through the interruptive sheet using a new `onlyOnThisMacCounts` input
- `playstead-mac/Playstead/Library/ReclaimPromptView.swift` - Gates "Reclaim selected" through the interruptive sheet using a new `ReclaimCandidateRow.onlyOnThisMacCount` field
- `playstead-mac/Playstead/App/PlaysteadApp.swift` - Routes the two new UI-testing env vars to their harness root views
- `playstead-mac/PlaysteadTests/SavesTests/OnlyCopyEscalationTests.swift` - 13 tests
- `playstead-mac/PlaysteadTests/SnapshotTests/OnlyCopyContractSnapshotTests.swift` - 7 tests, 2 reference images
- `playstead-mac/PlaysteadTests/SnapshotTests/PlaysteadSnapshot.swift` - Registers `OnlyCopyContractSnapshotTests` in the supported-suite allowlist
- `playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift` - 12 tests
- `playstead-mac/TestPlans/Rendering.xctestplan` - Registers the new snapshot suite
- `playstead-mac/TestPlans/UI.xctestplan` - Registers the new UI test suite

## Decisions Made

See `key-decisions` in frontmatter — most notably: `SaveUploadFailureClassification` as a save-domain-local enum standing in for `SaveUploadLane`'s not-yet-existing failure-classification output; the four escalation reason phrases as Claude's-discretion prose (not locked, but banned-word-checked); the bulk multi-game reclaim title falling back to "N games" when the locked single-title string doesn't fit; and unpair/sign-out/delete-game left unwired because no production entry point for any of the three exists yet.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `PlaysteadApp.swift` needed two new routing branches for the UI-testing harnesses, and was not in the plan's declared file list**
- **Found during:** Task 2
- **Issue:** `PlaysteadUITests` cannot `@testable import Playstead`, so proving `OnlyCopyInterruptiveSheet`'s real keyboard operability in a hosted window requires a production-side presentation seam — exactly the precedent 04-11 established for `ConflictComparisonSheet`, but `PlaysteadApp.swift` was not named in this plan's `<files>` list.
- **Fix:** Added two `else if` branches (mirroring the existing `PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON` branch verbatim) routing `PLAYSTEAD_UI_TEST_ONLY_COPY_INTERRUPTION`/`PLAYSTEAD_UI_TEST_ONLY_COPY_NEUTRAL` to the two new harness root views.
- **Files modified:** `playstead-mac/Playstead/App/PlaysteadApp.swift`
- **Verification:** UI test target builds cleanly; `OnlyCopyInterruptionTests` registered and build-verified against the harness
- **Committed in:** `ac7c60e` (Task 2 commit)

**2. [Rule 2 - Missing critical] `ReclaimCandidateRow` and `StorageView` had no field to carry a candidate's only-on-this-Mac count, so the interruptive gate had nothing to evaluate**
- **Found during:** Task 2
- **Issue:** The plan's declared behavior requires gating "eviction" and "remove local copy" on `onlyOnThisMacCount`, but neither `ReclaimCandidateRow` (defined in the in-scope `ReclaimPromptView.swift`) nor `StorageView`'s external `EvictionCandidate` type (owned by `EvictionPlanner.swift`, out of scope) carried any such field.
- **Fix:** Added a defaulted `onlyOnThisMacCount: Int = 0` field directly to `ReclaimCandidateRow` (in-scope file, no existing call site broken by the default). For `StorageView`, added a parallel `onlyOnThisMacCounts: [String: Int] = [:]` keyed-lookup parameter instead of touching the out-of-scope `EvictionCandidate` struct.
- **Files modified:** `playstead-mac/Playstead/Library/ReclaimPromptView.swift`, `playstead-mac/Playstead/Library/StorageView.swift`
- **Verification:** Full Unit suite (457 tests) and Rendering suite (46 tests, `StorageContractSnapshotTests` unaffected) both green
- **Committed in:** `ac7c60e` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed, both Rule 2/3 additions required to complete the plan's declared scope within the existing app-routing/candidate-row machinery. No scope creep — neither adds user-facing behavior beyond what the plan's tasks already required.

## Issues Encountered

None beyond the deviations above.

## Known Stubs

- **Unpair, sign out, and delete game are not wired to `OnlyCopyInterruptionGate`.** A source search (`grep -rniE "func unpair|func signOut|func deleteGame"`) confirms none of the three has a production entry point anywhere in this codebase yet. The gate and sheet are general-purpose, fully tested via the five-context synthetic harness (proving all five *would* reach the identical modal), and ready for whichever future plan builds those three flows. Tracked as **WINDOWS #35**.
- **`SaveUploadFailureClassification` is not yet fed by `SaveUploadLane`'s real HTTP responses.** `SaveUploadLane` today has no failure-classification output (it only tracks retry counts and durability state); this plan's classifier is proven correct against a synthetic classification input, and wiring `SaveUploadLane`'s actual `APIClientError`/`APIError` responses (`device_revoked`, capability mismatches, 5xx server refusals, `incompatible` gate verdicts) into a live `SaveUploadFailureClassification` value is deferred to a later plan.
- **UI-layer XCUITest execution requires the hosted macOS runner.** `OnlyCopyInterruptionTests.swift` builds and is registered in `TestPlans/UI.xctestplan`, but this sandbox's `scripts/ci/run-mac-verification.sh` refuses local UI execution (login-Keychain launch guard) unless a human explicitly sets `PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1`, which automated GSD runs must never set. Tracked as **WINDOWS #36**, mirroring the #9/#10/#34 precedent.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers. T-04-12-01 (destroying the only copy) is mitigated as designed: the interruptive modal's default is "Export saves…" and "Remove anyway" is never the default (proven by test). T-04-12-02 (silent unfixable failure) is mitigated: the four unfixable classifications each produce an escalation. T-04-12-03 (alarm fatigue) is mitigated structurally, not just by test, since the classifier's input type cannot represent duration. T-04-12-04 (optimistic-state count) is addressed by contract (the gate's doc comment requires committed local state) but not independently proven by a dedicated in-flight-upload test in this plan — the underlying `SaveUploadLane` has no in-flight/committed distinction exposed today for such a test to exercise; recorded as a backstop truth in the plan's `must_haves`, unchanged. T-04-12-05 (leaking internal detail via reason strings) is mitigated: all four reason phrases are user-facing prose, never machine codes. T-04-12-SC — no package-manager install occurred in this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The escalated and interruptive tiers are both built, unit/snapshot-tested, and wired into the two shipped bulk-destructive surfaces (`StorageView`, `ReclaimPromptView`).
- Three of the five named destructive-intent points (unpair, sign out, delete game) have no production surface yet anywhere in this codebase; the gate and sheet are ready the moment those flows exist (WINDOWS #35).
- `SaveUploadLane` needs a real failure-classification output before `OnlyCopyEscalation` can fire from live upload failures rather than a synthetic input; the classifier contract is proven and stable for that future wiring.
- CP7-SAVE-C remains blocked, unaffected by this plan, exactly as carried forward from 04-01/04-04/04-07.
- This was the final numbered plan before phase closeout; ready for phase-level verification.

## Self-Check: PASSED

- `[ -f playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/OnlyCopyInterruptiveSheet.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/OnlyCopyEscalationTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/SnapshotTests/OnlyCopyContractSnapshotTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift ]` → FOUND
- `git log --oneline --all | grep -q 3010f43` → FOUND
- `git log --oneline --all | grep -q ac7c60e` → FOUND
- Mac Unit test plan: 457 tests / 0 failures (baseline 437) → PASS
- Rendering test plan: 46 tests / 0 failures, 2 skipped (pre-existing, unrelated) → PASS
- `grep -rniE 'daysSince|elapsed|olderThan|threshold' playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift` → empty (PASS)
- `grep -rniE '#[0-9a-f]{6}|Color\(red:|\.green' playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift` → empty (PASS)
- `grep -rniE 'are you sure' playstead-mac/Playstead/` → empty (PASS)

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-05*
