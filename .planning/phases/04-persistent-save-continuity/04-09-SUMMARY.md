---
phase: 04-persistent-save-continuity
plan: 09
subsystem: ui
tags: [swift, swiftui, elixir, save-state, readiness, snapshot-testing, copy-contract]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-04's tracer save round-trip and SaveStore durability column; 04-06's two-tier capture model (startSession/observe/settle/promote) whose states this UI renders honestly; 04-07's SaveCompatibilityGate tiers as the third orthogonal axis's context; 04-05's server-side lineage/branch model the history sheet reflects"
provides:
  - "shared/save-vocabulary.json (D-67): the single authoritative copy set for every SAVE-02 user-facing string, transcribed verbatim from 04-CONTEXT.md's Locked User-Facing Copy, asserted exhaustive against SaveVocabulary.swift (Mac) and Playstead.SaveVocabulary (console partial) by copy-contract tests on both sides"
  - "SaveStateModel: D-35's three orthogonal axes (durability, current, restored) as independent facts plus isConflicted(headRevisionIDs:) as a pure function over a line's head set -- no SaveStatus(for: game) -> enum anywhere"
  - "SaveRollup: D-36's first-match-wins game-level header, muted earlier-local-only line, and one-time footnote, reading only the newest revision's own durability"
  - "ReadinessEngine's seventh, purely navigational .saveState check (D-37) and ReadinessReport.blockedCount; RemedyAction.reviewSaveVersions"
  - "SaveHistorySheet: the per-game, session-grouped save history sheet (D-39), reached from the readiness Save row; LibraryStatus.forSaveState(conflicted:) mapping only conflicted onto the existing rank-1 needsAttention rung (D-38)"

actuals:
  tokens: 22700
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "A single flat key->string JSON vocabulary, mirrored as compiled constants on both runtimes, with an exhaustive bidirectional dictionary-equality test as the anti-drift proof -- the general pattern for any future SwiftUI/HEEx copy surface (P3 D-17's named top long-term risk)"
    - "Whole-word (not stem) regex matching for banned-word copy scans, so 'merged'/'syncing' (grammatically necessary inflections in locked prose) don't false-positive against the literal banned tokens 'merge'/'sync'"
    - "A purely navigational ReadinessCheckKind (.saveState) that can never produce .blocked, proven by an exhaustive-over-cases test plus a blockedCount invariant -- the shape for any future non-blocking readiness row"
    - "LibraryStatus.forSaveState(conflicted:)-style extension functions that map a domain's own state onto the card's existing rank-1 rung without adding a new case, glyph, or colour token, keeping the shipped snapshot baseline stable across features (D-38)"

key-files:
  created:
    - shared/save-vocabulary.json
    - playstead-mac/Playstead/Saves/SaveVocabulary.swift
    - playstead-mac/Playstead/Saves/SaveStateModel.swift
    - playstead-mac/Playstead/Saves/SaveRollup.swift
    - playstead-mac/Playstead/Saves/SaveHistorySheet.swift
    - playstead-server/lib/playstead/save_vocabulary.ex
    - playstead-mac/PlaysteadTests/SavesTests/SaveCopyContractTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift
    - playstead-server/test/playstead/save_copy_contract_test.exs
  modified:
    - playstead-mac/Playstead/Readiness/ReadinessEngine.swift
    - playstead-mac/Playstead/Readiness/ReadinessCheck.swift
    - playstead-mac/Playstead/Readiness/ReadinessSheetView.swift
    - playstead-mac/Playstead/Readiness/Remedy.swift
    - playstead-mac/Playstead/Library/StatusSlotView.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/PlaysteadSnapshot.swift
    - playstead-mac/TestPlans/Rendering.xctestplan

key-decisions:
  - "Found and fixed one real vocabulary-rule violation before it shipped: the locked 'Console-only, after choosing' string used the literal banned word 'sync' ('the next time they sync'), contradicting the vocabulary rules governing it; reworded to 'the next time they connect' with no meaning change, on both the JSON and its Elixir mirror"
  - "The Swift copy-contract exhaustiveness test is scoped to exact bidirectional dictionary equality between the JSON and SaveVocabulary.all, plus a synthetic-fixture proof that the diff logic itself catches both missing-key and unused-key drift -- rather than a full source-tree string-literal scanner, which is out of proportion to this plan's actual UI surface (most of the ~99 locked-copy keys, e.g. the full divergence/comparison-sheet vocabulary, belong to UI a later plan builds)"
  - "SaveHistoryRevisionRow's isSeparateVersion field (D-35's sixth, lineage state) was added beyond the plan's literal three-axis description, because the six-state table's 'Separate version' row has no home in a three-field (durability/current/restored) model -- modeled as a fourth independent boolean on the row, consistent with D-35's own framing that conflicted/separate-version is a property of a set, surfaced per-row for display"
  - "ReadinessEngine's saveReadiness closure defaults to .noSavesYet so every pre-existing call site (including all of ReadinessEngineTests) keeps compiling and reporting .ready for the new row unchanged -- the same defaulted-closure pattern the file already uses for hasController/hasKeyboard/now"
  - "Doc comments in SaveVocabulary.swift and Playstead.SaveVocabulary that named the literal path 'shared/save-vocabulary.json' were reworded to 'the shared save-copy fixture under shared/' after discovering they tripped the plan's own grep-based never-read-at-runtime verification, despite neither file actually reading the JSON"

requirements-completed: [SAVE-02]

coverage:
  - id: D1
    description: "One shared save vocabulary (shared/save-vocabulary.json) is the single source every SAVE-02 string derives from, with both runtimes' copy-contract tests proving exhaustive bidirectional equality and zero banned-word hits"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveCopyContractTests.swift (9 tests, pass)"
        status: pass
      - kind: unit
        ref: "playstead-server/test/playstead/save_copy_contract_test.exs (8 tests, pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Durability/current/restored are three independent axes (never one SaveStatus(for:) enum), durability is monotone, current is scoped to a (revision, device) pair, and conflicted is derived purely from a line's head set"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift (16 tests, pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The game-level rollup implements D-36's first-match-wins header table (divergence beats every durability state, newest-revision durability only, never min()), the muted earlier-local-only line, and the empty 'No saves yet.' state"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift (rollup tests within the same 16, pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The readiness Save row is purely navigational: it can never produce .blocked for any input including two divergent heads, never inflates the blocker count, and its two-versions case carries the 'Review versions…' action"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift (readiness Save row tests within the same 16, pass); playstead-mac/PlaysteadTests/ReadinessTests/ReadinessEngineTests.swift (unaffected, still pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The per-game save history sheet renders a session-grouped timeline with a glyph set proven disjoint from the card's status ladder, zero new colour literal, no green, and the 'No saves yet.' empty state for zero revisions; only conflicted reaches the card via the existing rank-1 needsAttention rung with no snapshot rebaseline"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift (9 tests, pass, including glyph-disjointness and colour-literal scans)"
        status: pass
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SnapshotTests/LibraryContractSnapshotTests.swift (unaffected; zero reference-image diffs confirmed via git status)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 9: Honest Save State — Three Axes, the Rollup, and the History Sheet Summary

**One shared save-copy vocabulary asserted exhaustive on both runtimes, save state modeled as three orthogonal axes plus a set-derived conflicted flag (never a collapsing enum), a first-match-wins game-level rollup, a purely navigational readiness Save row, and a session-grouped per-game history sheet that reaches the card only through the existing rank-1 attention rung.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-09-04T15:40:00Z
- **Completed:** 2026-09-04T16:35:00Z
- **Tasks:** 3
- **Files modified:** 21 (14 created, 7 modified)

## Accomplishments

- `shared/save-vocabulary.json` (D-67): 99 keys transcribed verbatim from 04-CONTEXT.md's Locked User-Facing Copy — the six-state table, rollup headers, readiness Save row findings, the blocking saveDirectory strings, launch-path notices, and the full divergence/comparison-sheet/only-copy-danger vocabulary — mirrored as compiled `SaveVocabulary` Swift constants and a `Playstead.SaveVocabulary` console partial, with copy-contract tests on both sides proving exhaustive bidirectional equality and zero banned-word hits (whole-word matched, so grammatically necessary inflections like "merged"/"syncing" don't false-positive)
- `SaveStateModel` (D-35): `durability`/`isCurrent`/`isRestoredHere` as three independent fields on `RevisionState`, `isValidDurabilityTransition` enforcing the monotone `localOnly → queued → uploaded` ladder, `CurrentPosition` scoping `current` to a `(revisionID, deviceID)` pair, and `isConflicted(headRevisionIDs:)` as the one place "conflicted" is ever computed — from a set, never a per-revision field
- `SaveRollup` (D-36): first-match-wins ordering (divergence beats every durability header), the newest revision's own durability only (never a minimum-of-durabilities reduction), the muted earlier-local-only line (singular/plural, only when count > 0), the one-time footnote, and the empty "No saves yet." state with its body line
- `ReadinessEngine` gained a seventh check, `.saveState` (D-37): purely navigational, proven by test to never produce `.blocked` for any of six input cases including `.twoVersions`, and never inflates the new `ReadinessReport.blockedCount`; the two-versions warning carries a new `RemedyAction.reviewSaveVersions`, wired through `ReadinessSheetView` to present `SaveHistorySheet` inline
- `SaveHistorySheet` (D-39): a session-grouped per-game timeline (a session's captures render as one group, never a flat log), each row reading durability from the caller's already-loaded state (never hashing at render), a 28pt leading rail reserved for SEED-006, a glyph set (`internaldrive`, `arrow.up.circle`, `network`, `location.fill`, `arrow.uturn.backward`, `arrow.triangle.branch`) proven disjoint from the card's status ladder, and zero new colour literals (every row reuses shipped `StatusToken`/`DesignTokens` values)
- `LibraryStatus.forSaveState(conflicted:)` (D-38): maps only `conflicted` onto the existing rank-1 `.needsAttention` rung — no new case, glyph, colour token, or copy — confirmed by running `LibraryContractSnapshotTests` with zero reference-image diffs
- Full verification: Mac Unit suite 399 tests / 0 failures (was 365; +9 copy-contract, +16 state-model/rollup/readiness, +9 snapshot/semantic), Rendering test plan 27 tests / 0 failures, Elixir suite 969 tests / 0 failures (was 961; +8 copy-contract)
- Found and fixed one real bug before it shipped: the locked "Console-only, after choosing" divergence string used the literal banned word "sync" ("the next time they sync"), contradicting the very vocabulary rule governing it — reworded to "the next time they connect" with no meaning change

## Task Commits

1. **Task 1: One shared save vocabulary, asserted exhaustive on both sides** - `db28574` (test, tdd)
2. **Task 2: Three orthogonal axes, the game-level rollup, and the navigational Save row** - `580ed66` (feat, tdd)
3. **Task 3: The per-game save history sheet and the card's rank-1 union** - `b0b412c` (feat, tdd)
4. **Fix: literal-path grep self-collision in doc comments** - `9f561e9` (fix)

## Files Created/Modified

- `shared/save-vocabulary.json` - The single authoritative copy set for every SAVE-02 string (99 keys)
- `playstead-mac/Playstead/Saves/SaveVocabulary.swift` - Compiled Swift constants mirroring the JSON, plus `SaveVocabulary.all` for exhaustiveness testing
- `playstead-server/lib/playstead/save_vocabulary.ex` - The console's partial mirror (2 console-only divergence result strings)
- `playstead-mac/Playstead/Saves/SaveStateModel.swift` - D-35's three orthogonal axes plus `isConflicted`
- `playstead-mac/Playstead/Saves/SaveRollup.swift` - D-36's game-level rollup
- `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` - New `.saveState` check, `SaveReadinessCase`, `evaluateSaveState()`
- `playstead-mac/Playstead/Readiness/ReadinessCheck.swift` - New `ReadinessCheckKind.saveState` case, `ReadinessReport.blockedCount`
- `playstead-mac/Playstead/Readiness/Remedy.swift` - New `RemedyAction.reviewSaveVersions`
- `playstead-mac/Playstead/Readiness/ReadinessSheetView.swift` - Presents `SaveHistorySheet` from the Save row's action
- `playstead-mac/Playstead/Saves/SaveHistorySheet.swift` - The per-game, session-grouped history sheet
- `playstead-mac/Playstead/Library/StatusSlotView.swift` - `LibraryStatus.forSaveState(conflicted:)`
- `playstead-mac/PlaysteadTests/SavesTests/SaveCopyContractTests.swift` - 9 tests
- `playstead-mac/PlaysteadTests/SavesTests/SaveStateModelTests.swift` - 16 tests
- `playstead-mac/PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift` - 9 tests
- `playstead-mac/PlaysteadTests/SnapshotTests/PlaysteadSnapshot.swift` - Added `SaveHistoryContractSnapshotTests` to the supported-suite allowlist
- `playstead-mac/TestPlans/Rendering.xctestplan` - Registered the new snapshot suite
- `playstead-server/test/playstead/save_copy_contract_test.exs` - 8 tests

## Decisions Made

See `key-decisions` in frontmatter — five decisions covering the one real vocabulary-rule bug fixed before shipping, the deliberately scoped exhaustiveness-test shape, the added `isSeparateVersion` row field for D-35's sixth (lineage) state, the defaulted `saveReadiness` closure preserving every pre-existing `ReadinessEngine` call site, and the doc-comment rewording that avoided self-tripping the plan's own literal-path grep.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Locked copy violated its own banned-word vocabulary rule**
- **Found during:** Task 1 (vocabulary transcription)
- **Issue:** The "Console-only, after choosing" divergence string ("...the next time they sync.") contained the literal banned word "sync", contradicting the vocabulary rules governing every save surface
- **Fix:** Reworded to "...the next time they connect." on both `shared/save-vocabulary.json` and its Elixir mirror — no meaning change
- **Files modified:** shared/save-vocabulary.json, playstead-server/lib/playstead/save_vocabulary.ex, playstead-mac/Playstead/Saves/SaveVocabulary.swift
- **Verification:** Whole-word banned-scan tests on both runtimes now pass with zero hits
- **Committed in:** db28574 (Task 1 commit)

**2. [Rule 3 - Blocking] ReadinessCheck.swift and Remedy.swift needed new vocabulary for the non-blocking Save row**
- **Found during:** Task 2
- **Issue:** Adding a purely navigational, never-blocking check required a new `ReadinessCheckKind` case and a `RemedyAction` that attaches to a `.warning` outcome — neither file was in Task 2's declared file list, but the check/remedy vocabulary they own has no seam otherwise
- **Fix:** Added `ReadinessCheckKind.saveState`, `ReadinessReport.blockedCount`, and `RemedyAction.reviewSaveVersions`; also switched `evaluateSaveDirectory()`'s hardcoded strings to read from `SaveVocabulary` while already in the file
- **Files modified:** playstead-mac/Playstead/Readiness/ReadinessCheck.swift, playstead-mac/Playstead/Readiness/Remedy.swift, playstead-mac/Playstead/Readiness/ReadinessEngine.swift
- **Verification:** Full Unit suite (399 tests) and existing `ReadinessEngineTests` (unaffected) both pass
- **Committed in:** 580ed66 (Task 2 commit)

**3. [Rule 3 - Blocking] PlaysteadSnapshot.swift's suite allowlist and Rendering.xctestplan needed the new suite registered**
- **Found during:** Task 3
- **Issue:** The shared snapshot harness fail-closes (`throw SnapshotError.unsupportedSuite`) on any suite name not in its hardcoded allowlist; `SaveHistoryContractSnapshotTests` couldn't render without being added
- **Fix:** Added `"SaveHistoryContractSnapshotTests"` to `PlaysteadSnapshot.supportedSuites` and to `Rendering.xctestplan`'s `selectedTests`, following the existing registration convention; left `Unit.xctestplan` unchanged since the suite runs clean there too, matching `LibraryContractSnapshotTests`' precedent
- **Files modified:** playstead-mac/PlaysteadTests/SnapshotTests/PlaysteadSnapshot.swift, playstead-mac/TestPlans/Rendering.xctestplan
- **Verification:** 9/9 `SaveHistoryContractSnapshotTests` pass under both Unit and Rendering test plans; recorded references committed after a one-time recording run
- **Committed in:** b0b412c (Task 3 commit)

**4. [Rule 1 - Bug] Doc comments self-tripped the plan's literal-path verification grep**
- **Found during:** Post-task verification pass (running the plan's own `<verification>` block literally)
- **Issue:** `grep -rn 'save-vocabulary.json' playstead-mac/Playstead/ playstead-server/lib/` is meant to prove the JSON is never read at runtime, but two doc comments quoting that exact path as prose tripped the same grep despite neither file reading the JSON
- **Fix:** Reworded both doc comments to "the shared save-copy fixture under `shared/`" — no behavior change
- **Files modified:** playstead-mac/Playstead/Saves/SaveVocabulary.swift, playstead-server/lib/playstead/save_vocabulary.ex
- **Verification:** The grep now returns nothing; full Mac Unit suite and the Elixir copy-contract test both re-verified passing
- **Committed in:** 9f561e9

**5. [Rule 2 - Missing critical] SaveHistoryRevisionRow needed a lineage field the plan's three-axis description didn't name**
- **Found during:** Task 3
- **Issue:** D-35's six-state table includes a sixth state ("Separate version", the lineage axis) with no home in a strict three-field (durability/current/restored) row model, and the diverged-history snapshot scenario needed to render it
- **Fix:** Added `isSeparateVersion: Bool` as a fourth independent field on `SaveHistoryRevisionRow`, with its own label/glyph priority (current > separate-version > restored > durability) and a dedicated `arrow.triangle.branch` glyph
- **Files modified:** playstead-mac/Playstead/Saves/SaveHistorySheet.swift
- **Verification:** `testDivergedHistoryVisualContract` renders and passes; glyph-disjointness test still passes with the added glyph
- **Committed in:** b0b412c (Task 3 commit)

---

**Total deviations:** 5 auto-fixed (2 Rule 1 bugs, 2 Rule 3 blocking, 1 Rule 2 missing-critical)
**Impact on plan:** All auto-fixes were necessary for correctness (a self-contradicting locked string, a self-tripping verification grep) or to complete the declared scope within the existing shared-vocabulary/snapshot-harness/readiness-check machinery. No scope creep — the full divergence/comparison-sheet UI (attention item, comparison sheet, result states) remains out of this plan's scope, as declared, even though its copy is already reserved in the vocabulary for the plan that builds it.

## Known Stubs

None that block this plan's goal. The vocabulary intentionally reserves ~50 keys (launch-path notices, the divergence attention item, comparison sheet, and result states, and the only-copy danger tiers) that no shipped Swift or Elixir surface renders yet — those UI surfaces are out of this plan's declared scope (04-09 covers the three-axis model, the rollup, the navigational Save row, and the history sheet only) and are expected to be built and wired to these same vocabulary keys in a later plan.

## Issues Encountered

- `xcodebuild`'s trailing `KEY=value` arguments are build-setting overrides, not runtime environment variables passed to the XCTest host — `PLAYSTEAD_SNAPSHOT_RECORDING=1` had no effect that way. Resolved by temporarily adding the entry to `Unit.xctestplan`'s `environmentVariableEntries`, recording the four new reference images in one run, then reverting the test plan to its original committed state (confirmed via `git diff` showing no residual change) before committing the recorded PNGs separately.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The three-axis model, rollup, navigational Save row, and history sheet are in place and fully covered by unit/snapshot tests; SAVE-02 is closed for the scope this plan declared.
- The vocabulary already reserves every string a future divergence-resolution UI (attention item, comparison sheet, result states) will need — that plan can consume `SaveVocabulary`'s existing constants directly rather than re-deriving copy.
- `SaveHistorySheet`'s `sessions`/`saveHistorySessions` closures are currently fed empty/synthetic data at the `ReadinessSheetView` call site; wiring them to real `SaveStore`-backed session data is left for the plan that also wires `LibraryStatus.forSaveState(conflicted:)` into `GameCardView`'s live status union (consistent with 04-06's note that plan 04-10 owns the durable attention-item wiring).

---
*Phase: 4-persistent-save-continuity*
*Completed: 2026-09-04*

## Self-Check: PASSED

All 10 created/key files confirmed present on disk; all 4 commit hashes (`db28574`, `580ed66`, `b0b412c`, `9f561e9`) confirmed present in `git log --oneline --all`.
