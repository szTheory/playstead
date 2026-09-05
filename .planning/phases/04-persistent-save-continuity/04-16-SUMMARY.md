---
phase: 04-persistent-save-continuity
plan: 16
subsystem: saves
tags: [swift, swiftui, wiring, gap-closure, save-safety]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-09's SaveStateModel/SaveRollup three-axis model, StatusSlotView.forSaveState(conflicted:), and ReadinessEngine's saveReadiness: parameter"
  - phase: 04-persistent-save-continuity
    provides: "04-10's console /saves/:id SavesLive export surface and saves-scope export control"
  - phase: 04-persistent-save-continuity
    provides: "04-11's SaveAttentionSource, ConflictComparisonSheet, and SaveConflictResolver"
  - phase: 04-persistent-save-continuity
    provides: "04-12's OnlyCopyEscalation/OnlyCopyEscalationPanel and OnlyCopyInterruptiveSheet"
provides:
  - "AppEnvironment.saveStore/saveOutbox/saveConflictResolver: the single shared instances every save-safety surface reads and writes, replacing the zero, hardcoded, or ad hoc values each surface fed itself before"
  - "Real only-copy counts reaching ReclaimPromptView and StorageView, so OnlyCopyInterruptionGate can fire (MC-01) and its export escape hatch deep-links to the console instead of doing nothing (MC-02)"
  - "The D-38 divergence badge unioned into the card's rank-1 status rung (MC-03), the D-37 Save row reporting real SaveReadinessCase state (MC-04), OnlyCopyEscalationPanel with a real call site (MC-05), and ConflictComparisonSheet reachable and functional from ReadinessSheetView (MC-06)"
affects: [04-17]

actuals:
  tokens: 14449
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A single shared SaveStore/SaveOutbox/SaveConflictResolver constructed once in AppEnvironment's composition root, mirroring the existing curation-store single-instance rule -- every save-safety surface (reclaim, storage, readiness, the card badge, escalation, comparison) reads the same committed state instead of each computing or hardcoding its own"
    - "Wiring tests that drive AppEnvironment methods identical to what the production view calls (environment.reclaimCandidateRows(), .readinessReport(for:), .hasUnacknowledgedSaveDivergence(assetSetID:)) rather than constructing the leaf SwiftUI component directly -- the shape that let all six MC defects pass 481 prior green tests"

key-files:
  created:
    - playstead-mac/PlaysteadTests/SavesTests/OnlyCopyWiringTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift
  modified:
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/Playstead/Library/LibraryShellView.swift
    - playstead-mac/Playstead/Library/GameRowView.swift
    - playstead-mac/Playstead/Library/ReclaimPromptView.swift
    - playstead-mac/Playstead/Library/StorageView.swift
    - playstead-mac/Playstead/Readiness/ReadinessSheetView.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/StorageContractSnapshotTests.swift
    - .planning/phases/04-persistent-save-continuity/04-REVIEW.md

key-decisions:
  - "Removed the zero/[:] defaults on ReclaimCandidateRow.onlyOnThisMacCount and StorageView.onlyOnThisMacCounts entirely, per the plan's own instruction -- a defaulted safety input is precisely how three separate call sites silently omitted it. Every caller (2 production, 3 test) now supplies an explicit value."
  - "The comparison sheet and the escalated panel have no natural 'game detail'/'attention inbox' home yet (neither Mac surface exists in this codebase). Both were wired into ReadinessSheetView instead -- the closest existing per-game surface, and the same file SaveHistorySheet is already correctly wired into (mirrored per the plan's own read_first pointer). 'Review versions...' now opens ConflictComparisonSheet for a genuine fork and SaveHistorySheet otherwise, since the remedy is currently produced only by the .twoVersions case."
  - "MC-02's export deep link narrows to the FIRST affected candidate's save line when multiple only-copy games are selected at once -- no bulk/per-revision export target exists in the shipped Export.SavesPlan pipeline (04-10-SUMMARY.md's own documented limitation), so narrowing to one game is the honest, buildable interpretation of D-62 within this plan's scope."
  - "MC-05's escalation panel is genuinely gated (real count, real reachability-based classification that correctly suppresses on offline/slow-upload) but the four unfixable reasons (revoked auth, capability skew, server refusal, compatibility rejection) still cannot fire because SaveUploadLane has no wired failure-classification output anywhere in production -- a distinct, pre-existing gap (mac2 review WR-04), not rebuilt here. Recorded in WINDOWS.md rather than silently left unmentioned."
  - "saveReadinessCase(for:) does not compute .serverHasNewer -- it needs per-device session context this client doesn't track. Every other case, including the higher-priority .twoVersions warning D-46 requires, is computed. Recorded in WINDOWS.md."
  - "ConflictComparisonSheet's playTimeSinceSplit always renders the 'No recorded play here' fallback -- no per-device session/fork association exists in this schema, mirroring the exact same documented limitation plan 04-10's console comparison panel already carries for the identical reason."
  - "thisDeviceOrigin is the literal string 'This Mac' -- no device-name registry exists on this client (LaunchSaveContextBuilder falls back to the raw device id for the same reason); this matches the existing UI-testing harness's own placeholder."
  - "AppEnvironment now constructs SaveOutbox/SaveConflictResolver so a resolution durably records locally, but no drain trigger (OutboxDrainTrigger-equivalent) is wired for SaveOutbox -- a resolved fork may not reach the server promptly. This is the other half of mac2 review WR-04 and out of this plan's declared MC-01..MC-06 scope; recorded in WINDOWS.md, not silently left unfixed-and-unmentioned."

patterns-established:
  - "Wiring gap-closure tests belong at the AppEnvironment seam, not the leaf-component seam -- assert the exact method call the production view makes, never construct the leaf view/sheet in isolation."

requirements-completed: [SAVE-01, SAVE-02]

coverage:
  - id: D1
    description: "MC-01: OnlyCopyInterruptionGate fires from both reclaim surfaces with a real, committed-state-derived only-copy count"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/OnlyCopyWiringTests.swift#testReclaimCandidateRowsCarryRealOnlyOnThisMacCount, #testReclaimCandidateRowsReportZeroWhenEverythingIsUploaded, #testInFlightUploadStillCountsAsOnlyOnThisMac, #testStorageSnapshotCarriesRealOnlyOnThisMacCounts, #testStorageSnapshotOmitsCandidatesWithNoOnlyCopyRevisions"
        status: pass
    human_judgment: false
  - id: D2
    description: "MC-02: the interruptive sheet's default 'Export saves...' button deep-links to the console's export surface and clears the deferred destructive selection, never performing the destructive action"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/OnlyCopyWiringTests.swift#testConsoleSavesExportURLResolvesToTheCommittedSaveLine, #testConsoleSavesExportURLIsNilWithNoCommittedSaveLine, #testOpeningConsoleExportNeverReclaimsAnything"
        status: pass
      - kind: other
        ref: "grep -n 'onExport' ReclaimPromptView.swift StorageView.swift (neither handler is a bare dismissal)"
        status: pass
    human_judgment: true
    rationale: "Automated tests prove the destination URL and that the destructive path never fires; whether the actual browser-opening UX feels calm and unambiguous to a user is a judgment call no unit test proves."
  - id: D3
    description: "MC-03: the card's divergence badge unions into the existing rank-1 status rung without bypassing higher-ranked statuses"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift#testDivergedLineYieldsTheBadgeThroughTheRealStatusPath, #testNonDivergedLineYieldsNoBadge, #testDisposedForkStopsRaisingTheBadge"
        status: pass
    human_judgment: false
  - id: D4
    description: "MC-04: the D-37 Save row reports real SaveReadinessCase state instead of always the empty state"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift#testReadinessSaveRowReportsRealStateForAGameWithSavedProgress, #testReadinessSaveRowReportsEmptyStateOnlyWhenGenuinelyEmpty, #testReadinessSaveRowReportsTwoVersionsForADivergedLine"
        status: pass
    human_judgment: false
  - id: D5
    description: "MC-05: OnlyCopyEscalationPanel has a real, correctly-gated call site (never escalates offline/no-failure-signal states)"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift#testOfflineConditionRendersNoEscalatedPanel, #testReachableWithNoFailureSignalRendersNoEscalatedPanel"
        status: pass
    human_judgment: true
    rationale: "The panel cannot yet be proven to fire for a genuine unfixable failure in production, because SaveUploadLane has no wired failure classifier (WR-04, recorded in WINDOWS.md) -- a human must confirm this is an acceptable, disclosed scope boundary rather than a hidden gap."
  - id: D6
    description: "MC-06: ConflictComparisonSheet is reachable from ReadinessSheetView for a genuine fork and its choose/keep-both actions perform real, append-only SaveConflictResolver mutations"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift#testConflictSidesReflectTheRealCommittedHeads, #testResolvingChoosesASideAndDisposesTheFork"
        status: pass
    human_judgment: false
  - id: D7
    description: "No regression: full Unit test plan and Rendering test plan remain green, and reachability-sweep.sh reports no zero-caller user-facing symbol under Playstead/Saves/"
    verification:
      - kind: integration
        ref: "xcodebuild test-without-building -testPlan Unit (499/499, 0 failures); -testPlan Rendering (46/46, 0 failures, no snapshot drift); scripts/ci/reachability-sweep.sh (no user-facing Saves/ symbol)"
        status: pass
    human_judgment: false

duration: 95min
completed: 2026-09-05
status: complete
---

# Phase 4 Plan 16: MC-01..MC-06 Gap Closure Summary

**Six Mac-side wiring defects (real only-copy counts, a working export escape hatch, the divergence badge, the readiness Save row, the escalated panel, and the comparison sheet) all get real production call sites, backed by a single shared `SaveStore`/`SaveOutbox`/`SaveConflictResolver` in `AppEnvironment`, and 18 new wiring tests that drive the production construction path instead of constructing the leaf components in isolation.**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-09-05T09:20:00Z (approx.)
- **Completed:** 2026-09-05T10:55:00Z (approx.)
- **Tasks:** 3
- **Files modified:** 9 (2 created, 7 modified) + 1 review annotation

## Accomplishments

- **MC-01:** `AppEnvironment.onlyOnThisMacCount(forAssetSetID:)` reads real per-game only-copy counts from `SaveStore`'s committed `durability` column (a `queued`, in-flight-upload revision still counts — the count reads committed state, never a pending upload's assumed outcome) and threads them through `reclaimCandidateRows()` and `storageSnapshot().onlyOnThisMacCounts`, reaching both `ReclaimPromptView` and `StorageView`. `ReclaimCandidateRow.onlyOnThisMacCount` and `StorageView.onlyOnThisMacCounts` lost their zero/empty defaults entirely.
- **MC-02:** the interruptive sheet's default "Export saves…" button now calls `AppEnvironment.openConsoleSavesExport(forAssetSetIDs:)`, which opens plan 04-10's console `/saves/:id` export surface in the browser for the game's committed save line — never a second export mechanism. Choosing export now also clears the deferred destructive selection so it can never fire later (the exact bug CR-01/MC-02 described).
- **MC-03:** `LibraryStatus.forSaveState(conflicted:)` is unioned into the card grid's status composition in `LibraryShellView`, gated by `AppEnvironment.hasUnacknowledgedSaveDivergence(assetSetID:)` — the existing rank-1 union (`LibraryStatus.highestPriority`) still wins over every lower-ranked status.
- **MC-04:** `ReadinessEngine` is constructed with a real `saveReadiness:` closure backed by `AppEnvironment.saveReadinessCase(for:)`, so the D-37 Save row reports `uploadedAndCurrent`/`localOnlyReachable`/`localOnlyExpectedOffline`/`twoVersions` instead of always the empty state.
- **MC-05:** `OnlyCopyEscalationPanel` gets a real call site in `ReadinessSheetView`, gated by a real only-copy count and `AppEnvironment.saveUploadFailureClassification()` (reachability-based; never escalates an offline queue).
- **MC-06:** `ConflictComparisonSheet` gets a real call site in `ReadinessSheetView`'s "Review versions…" remedy, replacing `SaveHistorySheet` specifically when the line has a genuine, undisposed fork. `AppEnvironment` now constructs the shared `SaveStore`/`SaveOutbox`/`SaveConflictResolver` instances (previously constructed only in tests and one ad hoc `GameRowView` instance) and exposes `conflictSides(forAssetSetID:)`, `resolveSaveDivergence(assetSetID:chosenRevisionID:)`, and `acknowledgeSaveDivergence(assetSetID:thisDeviceOrigin:)`, which perform the real, append-only `chooseSide`/`keepBoth` mutations.
- 18 new tests across `OnlyCopyWiringTests.swift` and `SaveSurfaceWiringTests.swift`, every one driving `AppEnvironment`'s production methods rather than constructing `OnlyCopyInterruptiveSheet`, `StatusSlotView`, `ReadinessEngine`, `OnlyCopyEscalationPanel`, or `ConflictComparisonSheet` directly.

## Task Commits

1. **Tasks 1–3: MC-01..MC-06 wiring** — `c223218` (fix) — combined into one commit; see Deviations for why.
2. **Review annotation** — `02322b2` (docs)

## Files Created/Modified

- `playstead-mac/Playstead/App/PlaysteadApp.swift` — `saveStore`/`saveOutbox`/`saveConflictResolver` construction; `onlyOnThisMacCount`, `saveContentKey`, `hasUnacknowledgedSaveDivergence`, `saveReadinessCase`, `saveUploadFailureClassification`, `conflictSides`, `resolveSaveDivergence`, `acknowledgeSaveDivergence`, `consoleSavesExportURL`, `openConsoleSavesExport`; `reclaimCandidateRows`/`storageSnapshot`/`readinessReport` now feed real save state
- `playstead-mac/Playstead/Library/LibraryShellView.swift` — `StorageView` construction passes `onlyOnThisMacCounts`/`onExportOnlyCopy`; card grid composition unions the divergence badge
- `playstead-mac/Playstead/Library/GameRowView.swift` — `ReclaimPromptView` construction passes `onExportOnlyCopy`
- `playstead-mac/Playstead/Library/ReclaimPromptView.swift` — `onlyOnThisMacCount` default removed; real `onExportOnlyCopy` escape hatch; pending selection cleared on export
- `playstead-mac/Playstead/Library/StorageView.swift` — `onlyOnThisMacCounts` default removed; same export/clear fix
- `playstead-mac/Playstead/Readiness/ReadinessSheetView.swift` — `OnlyCopyEscalationPanel` and `ConflictComparisonSheet` real call sites
- `playstead-mac/PlaysteadTests/SnapshotTests/StorageContractSnapshotTests.swift` — updated for the removed defaults
- `playstead-mac/PlaysteadTests/SavesTests/OnlyCopyWiringTests.swift` (new) — 8 tests, MC-01/MC-02
- `playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift` (new) — 10 tests, MC-03..MC-06
- `.planning/phases/04-persistent-save-continuity/04-REVIEW.md` — MC-01..MC-06 annotated fixed

## Decisions Made

See `key-decisions` in frontmatter — six decisions, mostly about honest scope boundaries where a fix required infrastructure (a device-name registry, `SaveUploadLane` failure classification, per-device play-time-since-split) that doesn't exist anywhere in this codebase yet, and building it would have been a new feature, not a wiring fix.

## Deviations from Plan

### Auto-fixed / Scope Adjustments

**1. [Rule 3 - Blocking] Test fixtures needed real 64-character hex digests**
- **Found during:** Task 1 (first test run)
- **Issue:** Placeholder digests like `"rom-digest-1"` fail `PathSafety.validatedDigest`/`CASManager.commit`'s format validation, crashing every test in both new files.
- **Fix:** Added a `digest(_ seed:)` helper (SHA-256 of the seed string) to both test files.
- **Files modified:** `OnlyCopyWiringTests.swift`, `SaveSurfaceWiringTests.swift`
- **Verification:** all 18 new tests pass.
- **Committed in:** `c223218`

**2. [Rule 2 - Missing Critical] `ReadinessSheetView.swift` required modification, not in the plan's declared `files_modified`**
- **Found during:** Task 3
- **Issue:** MC-05/MC-06 (added to this plan after the original review) need a real call site for `OnlyCopyEscalationPanel` and `ConflictComparisonSheet`. Neither a "game detail" view nor an "attention inbox" — the two Mac-side entry points D-53 names — exists anywhere in this codebase yet; building either from scratch would have been a new feature far outside a wiring gap-closure plan.
- **Fix:** Wired both into `ReadinessSheetView`, the closest existing per-game surface, mirroring exactly how `SaveHistorySheet` is already correctly wired into the same file (per the plan's own read_first pointer at `ReadinessSheetView.swift:73`).
- **Files modified:** `ReadinessSheetView.swift`
- **Verification:** `SaveSurfaceWiringTests.swift`'s MC-05/MC-06 tests pass; full Unit suite green.
- **Committed in:** `c223218`

**3. [Consolidation, not a rule] All three tasks landed in one commit rather than three**
- **Reason:** All six defects share one seam — `AppEnvironment`'s newly-added `SaveStore`/`saveContentKey`/`saveLine` plumbing — added once and consumed by every fix. Splitting the diff into three commits along the plan's task boundaries would have required either duplicating that shared plumbing across commits or shipping intermediate commits that reference methods not yet defined (non-compiling history). One commit per file's *actual* dependency graph was judged more honest than an artificial split that implied independence the code doesn't have.
- **Impact:** No functional impact — every commit that exists compiles and passes the full suite. Traceability is preserved via the itemized MC-01..MC-06 breakdown in this SUMMARY and in `04-REVIEW.md`'s per-item "Fixed" annotations, all pointing at the same commit hash.

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing-critical-functionality/scope), 1 disclosed consolidation.
**Impact on plan:** No scope creep beyond what MC-05/MC-06 required to get a real, honest call site. All six defects are genuinely fixed, not merely grep-satisfied — see the `human_judgment: true` rationale on D2 and D5 above for the two places a human sign-off still adds value beyond the automated proof.

## Known Stubs

None introduced by this plan. Three pre-existing, adjacent gaps were *not* closed here and are recorded in `.planning/WINDOWS.md` (not silently left unmentioned):
- `SaveUploadLane` still has no wired failure-classification output, so MC-05's four unfixable escalation reasons cannot fire yet (mac2 review WR-04, one half).
- `SaveOutbox` has no drain trigger wired, so a `SaveConflictResolver` resolution is durable locally but may not reach the server promptly (mac2 review WR-04, other half).
- `AppEnvironment.saveReadinessCase(for:)` does not compute `.serverHasNewer` (needs per-device session context this client doesn't track).
- `ReadinessSheetView`'s `saveHistorySessions` closure is still never populated from `SaveStore` (mac2 review CR-04's other half) — a non-diverged "Review versions…" still shows the history sheet's empty state.

## Issues Encountered

None beyond the digest-format fixture issue documented above (resolved).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All six MC-01..MC-06 defects fixed, tested, and annotated in `04-REVIEW.md`.
- Unit: 499/499 (481 baseline + 18 new), 0 failures. Rendering: 46/46, 0 failures, no snapshot drift.
- `scripts/ci/reachability-sweep.sh` reports no zero-caller user-facing symbol under `Playstead/Saves/`.
- Four adjacent, pre-existing gaps recorded in WINDOWS.md for future attention (not blocking): `SaveUploadLane` failure classification, `SaveOutbox` drain trigger, `.serverHasNewer` computation, and `saveHistorySessions` population.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-05*

## Self-Check: PASSED

All key-files (created and modified) verified present on disk with `[ -f ]`. Both commits (`c223218`, `02322b2`) verified present in `git log --oneline --all`. Unit test plan: 499/499, 0 failures. Rendering test plan: 46/46, 0 failures, no snapshot drift. `scripts/ci/reachability-sweep.sh` verified clean of MC-01..MC-06 symbols under `Playstead/Saves/`.
