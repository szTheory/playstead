---
phase: 04-persistent-save-continuity
plan: 22
subsystem: saves
tags: [swift, swiftui, sqlite, save-history, appenvironment]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-16's SaveHistorySheet/ConflictComparisonSheet six-state rendering surface, which had never been given real data (04-VERIFICATION.md gap)"
provides:
  - "SaveStore.markRestoredHere/restored_here_at -- the durable restore-provenance column the six-state vocabulary needed and the schema lacked"
  - "AppEnvironment.saveHistorySessions(forAssetSetID:) and SaveHistorySessionBuilder -- the real per-revision data source for SaveHistorySheet, wired at both call sites"
  - "AppEnvironment.saveRollupSummary(forAssetSetID:) -- D-36's first production caller for SaveRollup.rollup(for:), closing WINDOWS #47"
affects: [saves, readiness, library]

actuals:
  tokens: 13981
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Restore-provenance is written from the launch path's executeSavePlan closure only AFTER a successful executor.execute, mirroring the existing 'mark only after the real effect happened' shape."
    - "AppEnvironment view-model builders (saveHistorySessions, saveRollupSummary) resolve entry/line identically to the established conflictSides(forAssetSetID:) shape -- one resolution pattern, not a second one per builder."
    - "SaveHistorySessionBuilder is a pure, store-free enum (no SaveStore dependency) so every grouping/ordering/six-state rule is unit-testable without SQLite."

key-files:
  created:
    - playstead-mac/Playstead/Saves/SaveOriginNames.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveStoreTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift
  modified:
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Persistence/SaveStore.swift
    - playstead-mac/Playstead/Library/GameRowView.swift
    - playstead-mac/Playstead/Library/LibraryShellView.swift
    - playstead-mac/Playstead/Readiness/ReadinessSheetView.swift
    - playstead-mac/Playstead/Saves/SaveHistorySheet.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift
    - playstead-mac/scripts/ci/reachability-allowlist.txt

key-decisions:
  - "restored_here_at persisted via the same additive ALTER pattern as tier/origin/manifest_digest, guarded by WHERE restored_here_at IS NULL on write so immutability is enforced in storage, not just by convention."
  - "SaveHistorySessionBuilder.relativeTime(for:) is the single relative-time formatter; AppEnvironment.relativeSaveDescription(for:) now delegates to it instead of keeping a second ISO8601/RelativeDateTimeFormatter pair."
  - "SaveHistorySheet.summary defaults to nil so every pre-existing snapshot fixture renders byte-identically; only one new fixture (save-history-populated-with-summary) supplies it."

requirements-completed: [SAVE-02]

coverage:
  - id: D1
    description: "A restore or fast-forward through the real launch path leaves a durable, immutable restored-here timestamp on the matching revision; an existing install upgrades in place."
    requirement: SAVE-02
    verification:
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveStoreTests.swift#testMarkingRestoredTwiceKeepsTheFirstTimestamp"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveStoreTests.swift#testAnExistingInstallWhoseTablePredatesTheColumnStillOpensWithNilProvenance"
        status: pass
      - kind: integration
        ref: "PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift#testARestorePlanMarksTheMatchingRevisionRestoredHereAfterExecuting"
        status: pass
      - kind: integration
        ref: "PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift#testAKeepPlanMarksNoRevisionRestoredHere"
        status: pass
    human_judgment: false
  - id: D2
    description: "Opening 'Review versions…' for a game with real save history renders that history, with each row reporting durability, position, provenance and lineage from committed SaveStore data -- not the empty state (WINDOWS #43)."
    requirement: SAVE-02
    verification:
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift (16 tests, one per <behavior> bullet plus an AppEnvironment integration case)"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift#testBothReadinessSheetViewCallSitesPassARealSaveHistorySessionsClosure"
        status: pass
    human_judgment: false
  - id: D3
    description: "SaveRollup.rollup(for:) has a real production caller and the reachability allowlist is one line shorter, closing WINDOWS #47."
    verification:
      - kind: other
        ref: "scripts/ci/reachability-sweep.sh --strict (exit 0, allowlist shrunk by exactly the SaveRollup line)"
        status: pass
      - kind: automated_ui
        ref: "PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift#testPopulatedHistoryWithSummaryVisualContract"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift#testSaveRollupSummaryReturnsTheTwoVersionsHeaderForADivergedLineAndOnServerForAnUploadedNewest"
        status: pass
    human_judgment: false

duration: ~50min
completed: 2026-09-06
status: complete
---

# Phase 04 Plan 22: Real per-revision save history data, and a caller for D-36's rollup Summary

**`SaveHistorySheet` now renders real committed `SaveStore` data at both call sites via a new pure `SaveHistorySessionBuilder`, a persisted restore-provenance column makes the sixth state truthful, and `SaveRollup.rollup(for:)` gets its first production caller — closing WINDOWS #43 and #47.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-09-05T21:15:00-04:00 (approx.)
- **Completed:** 2026-09-06T01:42:00Z
- **Tasks:** 3
- **Files modified:** 13 (3 created, 10 modified)

## Accomplishments

- `save_revision.restored_here_at` added via the same additive-ALTER pattern as `tier`/`origin`/`manifest_digest`; `SaveStore.markRestoredHere(revisionID:at:)` writes it guarded by `WHERE restored_here_at IS NULL`, making provenance immutable in storage. `GameRowView.buildSaveLaunchPlan`'s `executeSavePlan` closure calls it for `.restore`/`.fastForward` plans only, after a successful execute.
- `SaveHistorySessionBuilder` (pure, store-free): groups revisions by `sessionID`, orders rows oldest-first within a group and groups most-recent-first, and derives `durability`/`isCurrent`/`isRestoredHere`/`isSeparateVersion` straight from committed row data per the six-state vocabulary. `AppEnvironment.saveHistorySessions(forAssetSetID:)` wires it to real `SaveStore` reads, and both `ReadinessSheetView` call sites (`GameRowView`, `LibraryShellView`) now pass the real closure instead of the `{ [] }` default — closing WINDOWS #43.
- `SaveOriginNames.thisDevice` is now the single definition of "This Mac"; `ReadinessSheetView` reads it instead of duplicating the literal.
- `AppEnvironment.saveRollupSummary(forAssetSetID:)` builds a `SaveRollupInput` from committed rows and calls `SaveRollup.rollup(for:)` — its first production caller. `SaveHistorySheet.summary` (optional, defaults to `nil`) renders the header/muted-line/footnote above the session list. The `SaveRollup` line is removed from `reachability-allowlist.txt`; `scripts/ci/reachability-sweep.sh --strict` now passes with the shortened allowlist, closing WINDOWS #47.
- Full Swift Unit suite: 567 tests, 0 failures (plan required ≥ 545). Rendering suite (`SaveHistoryContractSnapshotTests`): 10/10 passing, including one new fixture (`save-history-populated-with-summary`) that is the only addition — every pre-existing fixture renders byte-identically since `summary` defaults to `nil`.
- Falsification check performed manually and passed: reverting the `saveHistorySessions:`/`saveRollupSummary:` override at `LibraryShellView.swift` only turns `testBothReadinessSheetViewCallSitesPassARealSaveHistorySessionsClosure` red (2 failures); restoring the file turns it green again. This is now a permanent regression guard, not just a one-time manual check.

## Task Commits

1. **Task 1: Persist restored-here provenance** - `1c97dd2` (feat)
2. **Task 2: A real sessions builder, wired at both call sites** - `62e0db0` (feat)
3. **Task 3: Give SaveRollup a production caller and shrink the allowlist** - `24d5c34` (feat)
4. **Falsification-check regression guard** - `f1dcece` (test)

**Plan metadata:** (this commit)

## Files Created/Modified

- `playstead-mac/Playstead/Persistence/Migrations.swift` - `restored_here_at TEXT` additive ALTER
- `playstead-mac/Playstead/Persistence/SaveStore.swift` - `SaveRevisionRow.restoredHereAt`, `markRestoredHere(revisionID:at:)`, decode/insert wiring
- `playstead-mac/Playstead/Library/GameRowView.swift` - `buildSaveLaunchPlan`'s `executeSavePlan` marks provenance after a successful execute; `ReadinessSheetView` call site wired with real closures
- `playstead-mac/Playstead/Library/LibraryShellView.swift` - `ReadinessSheetView` call site wired with real closures
- `playstead-mac/Playstead/Readiness/ReadinessSheetView.swift` - `saveRollupSummary` closure parameter added, passed through to `SaveHistorySheet`; `thisDeviceOrigin` reads `SaveOriginNames.thisDevice`
- `playstead-mac/Playstead/Saves/SaveOriginNames.swift` - new: the one definition of "This Mac"
- `playstead-mac/Playstead/Saves/SaveHistorySheet.swift` - `SaveHistorySessionBuilder` (new type), `summary` optional property + rendering
- `playstead-mac/Playstead/App/PlaysteadApp.swift` - `saveHistorySessions(forAssetSetID:)`, `saveRollupSummary(forAssetSetID:)`; `relativeSaveDescription` delegates to the shared formatter
- `playstead-mac/scripts/ci/reachability-allowlist.txt` - `SaveRollup` line removed
- `playstead-mac/PlaysteadTests/SavesTests/SaveStoreTests.swift` - new: provenance immutability + pre-column-install upgrade tests
- `playstead-mac/PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift` - new: 17 tests (behavior bullets, rollup summary, falsification guard)
- `playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift` - `.restore`/`.keep` provenance-marking tests
- `playstead-mac/PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift` - one new fixture supplying `summary`

## Decisions Made

- `restored_here_at`'s upsert `COALESCE` order is `COALESCE(save_revision.restored_here_at, excluded.restored_here_at)` (existing value wins) — the opposite order from `manifest_digest`/`session_id`'s `COALESCE(excluded, existing)`, because those columns are meant to be updatable-if-missing while this one must never be overwritten once set.
- `SaveHistorySessionBuilder`'s "first row" for a group's `deviceName` is the earliest revision by `recordedAt` after ascending sort, not insertion order — deterministic and matches the plan's "ordered oldest first" contract.
- Added a permanent source-level regression test for the plan's falsification check (both `ReadinessSheetView` call sites must be wired) rather than treating the manual verification as one-off — the exact defect this plan closes was two independently-editable call sites, one of which could silently regress.

## Deviations from Plan

None - plan executed exactly as written. One minor addition beyond the plan's explicit acceptance criteria: a source-level regression test (`testBothReadinessSheetViewCallSitesPassARealSaveHistorySessionsClosure`) making the plan's manual falsification check a permanent CI guard rather than a one-time verification step (Rule 2 — missing critical regression coverage for a defect the plan explicitly calls out as easy to reintroduce).

## Issues Encountered

- `xcodebuild test-without-building` does not forward plain shell environment variables to the test host process; `PLAYSTEAD_SNAPSHOT_RECORDING=1` had to be passed as `TEST_RUNNER_PLAYSTEAD_SNAPSHOT_RECORDING=1` (xcodebuild's documented `TEST_RUNNER_` prefix convention) to record the new snapshot fixture. Not a code issue — noted here in case it recurs for future fixture additions.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ROADMAP criterion 2 (per-revision six-state save history, not a coarse per-game reading or an empty state) is now met: `SaveHistorySheet` renders real data at both surfaces that open it.
- WINDOWS #43 and #47 are closed; `.planning/WINDOWS.md` should be updated to reflect both as resolved by this plan (04-22-SUMMARY.md is the resolution reference).
- Full Swift Unit suite: 567 tests, 0 failures. Rendering suite: 10/10 passing. `reachability-sweep.sh --strict`: exit 0.
- Known-flaky tests named in this plan's `<verification>` (`AppPathsBackupExclusionTests.testExistingInstallWithStaleRootFlagIsRepairedAtInit`, `SetupWizardJourneyTest`) were not encountered as failures in this run's full-suite pass.
- Remaining phase 04 gap-closure plan 04-23 can proceed; no blockers surfaced here.

## Self-Check: PASSED

- All created files verified present on disk: `SaveOriginNames.swift`, `SaveStoreTests.swift`, `SaveHistorySessionBuilderTests.swift`.
- All task and metadata commit hashes (`1c97dd2`, `62e0db0`, `24d5c34`, `f1dcece`) verified present in `git log --oneline --all`.
- Re-ran `scripts/ci/reachability-sweep.sh --strict`: exit 0, "No unreachable production symbols found."
- Re-ran full Swift Unit suite: 567 tests, 0 failures.
- Re-ran `SaveHistoryContractSnapshotTests`: 10/10 passing.
- Falsification check re-verified: reverting `LibraryShellView.swift`'s override alone turns `testBothReadinessSheetViewCallSitesPassARealSaveHistorySessionsClosure` red; restoring it turns the suite green again (confirmed, then file restored with no residual diff).

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-06*
