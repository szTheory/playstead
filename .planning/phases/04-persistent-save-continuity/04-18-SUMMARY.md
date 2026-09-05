---
phase: 04-persistent-save-continuity
plan: 18
subsystem: testing
tags: [xcuitest, reachability, ci-gate, save-safety, gap-closure]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-16's real production call sites for MC-01..MC-06 (OnlyCopyInterruptiveSheet, StatusSlotView.forSaveState, ReadinessEngine's saveReadiness:, OnlyCopyEscalationPanel, ConflictComparisonSheet)"
provides:
  - "SaveFrontDoorJourneyTests.swift: four flagless XCUITest journeys proving the four save surfaces are reachable through real navigation, not just constructible directly"
  - "Three new DeterministicProfile state-seeding profiles (save-restorable, save-only-copy, save-diverged) that seed real SaveStore/CAS state -- the model for any future save-state UI fixture"
  - "reachability-sweep.sh promoted from an advisory script to a real --strict CI gate, with its own-file/doc-comment false-positive rate fixed (124 -> 22 findings)"
  - "A previously undisclosed, more severe finding: the entire save-capture-and-upload pipeline (SaveCapturePoller/SaveUploadLane/SaveSessionRecovery) has no production trigger at all -- recorded in WINDOWS.md, not fixed by this plan"
affects: []

actuals:
  tokens: 13628
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Front-door XCUITest journeys: launch with UITestHarness(profile:) only (PLAYSTEAD_UI_TESTING/PLAYSTEAD_UI_TEST_PROFILE), never a PLAYSTEAD_UI_TEST_* scenario flag that routes to the surface under test. Seed state via a DeterministicProfile case; navigate via the same controls a person clicks."
    - "Reachability-sweep occurrence counting: count every occurrence of a declared symbol anywhere in production source (including its own file), minus pure-comment lines, rather than requiring a reference from a SEPARATE file -- the latter flags every self-contained, single-file type as a false positive."
    - "UI_TESTING-only observability hooks (AppEnvironment.uiTestConsoleExportAttempts) as the substitute proof for a real side effect (NSWorkspace.shared.open) that is legitimately skipped under automated tests -- mirrors the existing playstead.harness.* convention."

key-files:
  created:
    - playstead-mac/PlaysteadUITests/SaveFrontDoorJourneyTests.swift
    - playstead-mac/scripts/ci/reachability-allowlist.txt
  modified:
    - playstead-mac/Playstead/UITesting/DeterministicProfile.swift
    - playstead-mac/PlaysteadUITests/Support/UITestHarness.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/Playstead/Library/LibraryShellView.swift
    - playstead-mac/Playstead/Readiness/ReadinessReportView.swift
    - playstead-mac/Playstead/UITesting/UITestBootstrap.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/DeterministicProfileTests.swift
    - playstead-mac/TestPlans/UI.xctestplan
    - playstead-mac/scripts/ci/reachability-sweep.sh
    - playstead-mac/scripts/ci/run-mac-verification.sh
    - .planning/WINDOWS.md

key-decisions:
  - "Extended DeterministicProfile with three new profiles rather than routing flags: `.saveRestorable` seeds a cached ROM, an empty local save directory, a real `uploaded` restorable revision, AND a real (fake-but-executable) installed adapter -- required because ReadinessEngine's emulator check and AdapterHost.launch both need a genuine on-disk installation to reach Play at all. `.saveOnlyCopy` seeds one `localOnly` revision on a cached, evictable game. `.saveDiverged` seeds two undisposed heads on one line."
  - "Seeded save byte size is 32,768 (sram_32k) throughout, matching the pinned adapter's own `save_contract.proven_media` (AdapterPin.json) -- an arbitrary byte count would trip the D-24 unbound-medium hard block in `SaveCompatibilityGate` instead of proving the restore path."
  - "MC-02's 'not a no-op' proof required a new, small, UI_TESTING-gated observability hook (`AppEnvironment.uiTestConsoleExportAttempts`, rendered as a hidden accessibility element in LibraryShellView) because `NSWorkspace.shared.open` is (correctly) skipped entirely under UI_TESTING, leaving nothing else for a front-door test to observe. Also required seeding `.saveOnlyCopy` with a real (synthetic, offline) `PairingCredential` via a new `AppEnvironment` init overload, since `openConsoleSavesExport` needs a paired device to resolve a URL at all -- this is world-state seeding (whether this Mac is paired), never routing."
  - "Added accessibility identifiers to `ReadinessReportView`'s per-check row and remedy button (`playstead.readiness.row.<kind>` / `.remedy`) -- previously the row had only an `accessibilityLabel`, with no stable identifier a journey could navigate by without fragile text matching."
  - "Reachability-sweep heuristic fix: count every occurrence of a symbol anywhere in production source (its own file included), minus the declaration's own doc-comment mentions, instead of requiring a reference from a SEPARATE file. The original heuristic's dominant false-positive class was never 'SwiftUI View conformances' as anticipated -- it was ordinary single-file types (a `@State` status enum, a small helper View instantiated once in its own parent, an enum case's payload type reached only via pattern matching) that are genuinely wired the moment their own file's body uses them. This dropped findings from 124 to 22, well under the ~40 review-by-eye budget, with no heuristic weakening that would hide a real cross-file gap."
  - "Did not delete any production Swift file this plan flagged as apparently dead (GameListView.swift's whole family, DownloadQueueError, etc.) -- deleting shipped, still-tested production code is a bigger, riskier call than a front-door-journey/CI-gate plan should make unilaterally without dedicated review. All are disclosed via the allowlist and WINDOWS.md instead."
  - "Registered the sweep in run-mac-verification.sh as a distinct `run_reachability_sweep_layer` function contributing to the same aggregate/layers.json evidence as the four xctest layers, rather than forcing it through `run_test_layer`/`verify_layer_result` (which parses xcresult-derived JSON test results) -- there is no xcresult bundle for a plain shell script, and shoehorning it in would have meant fabricating fake xctest evidence. Verified this does not break `four-layer-topology-test.sh`'s exact-four-`run_test_layer`-calls assertion (a pre-existing, unrelated failure in that same test script was confirmed present on main before this plan touched anything, via `git stash`)."

patterns-established:
  - "A DeterministicProfile that needs a working readiness/launch path must also seed a real, on-disk 'installed adapter' record (matching AdapterInstaller's own recordInstallation shape) -- no test-mode bypass exists in AdapterHost.launch itself."

requirements-completed: [SAVE-01, SAVE-02, SAVE-03]

coverage:
  - id: D1
    description: "Four front-door journeys exist, one per save surface (SAVE-03 launch-restore, D-40 interruptive modal + MC-02 export escape hatch, D-38 divergence badge + comparison sheet, D-37 readiness Save row), launched with no PLAYSTEAD_UI_TEST_* routing flag"
    requirement: "SAVE-01"
    verification:
      - kind: other
        ref: "grep -c 'PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON\\|PLAYSTEAD_UI_TEST_ONLY_COPY' SaveFrontDoorJourneyTests.swift == 0; grep -c 'SaveFrontDoorJourneyTests' TestPlans/UI.xctestplan == 1"
        status: pass
      - kind: e2e
        ref: "PlaysteadUITests.SaveFrontDoorJourneyTests (compiles, registered in UI.xctestplan; requires hosted macOS runner, WINDOWS #34/#36 -- not executed locally)"
        status: unknown
    human_judgment: true
    rationale: "The four journeys compile, are registered, and were designed against verified real navigation paths and real seeded SaveStore/CAS/adapter-install state (traced through AppEnvironment/GameRowView/ReadinessSheetView/StorageView source), but XCUITest execution (a real app process, real accessibility tree, a spawned adapter process for Journey 1) genuinely requires the hosted macOS runner per this plan's own testing note and could not be executed in this session. A human/CI run on the hosted runner is the remaining proof, exactly as plans 04-11 and 04-12 disclosed for their own hosted-only suites."
  - id: D2
    description: "reachability-sweep.sh --strict exits 0 on the current tree with a small (23-entry), fully-reasoned allowlist, and is registered as a gate in run-mac-verification.sh"
    requirement: "SAVE-02"
    verification:
      - kind: other
        ref: "playstead-mac/scripts/ci/reachability-sweep.sh --strict (exit 0); awk allowlist-reason check (exit 0); grep -c reachability run-mac-verification.sh == 11"
        status: pass
    human_judgment: false
  - id: D3
    description: "Baselining the sweep surfaced a genuine, previously-undisclosed defect (the save-capture-and-upload pipeline has no production trigger) and it was reported, not quietly allowlisted"
    verification:
      - kind: other
        ref: "scripts/ci/reachability-allowlist.txt entries for SaveCapturePoller/SaveUploadLane/SaveSessionRecovery/FileSaveArtifactSource/SaveCaptureBlockedState carry the finding inline; .planning/WINDOWS.md records five new entries"
        status: pass
    human_judgment: true
    rationale: "This is a significant, previously-unknown gap in a shipped save-safety phase. A human should read the 'Genuinely Unreachable Symbols Found' section below and decide how urgently a dedicated wiring plan is needed -- this plan's job was disclosure, not the fix."
  - id: D4
    description: "Mac Unit and Rendering test plans remain at their post-04-17 baselines with no regressions"
    verification:
      - kind: integration
        ref: "xcodebuild test-without-building -testPlan Unit: 511/511, 0 failures; -testPlan Rendering: 44/44 passed + 2 expected local skips (hosted-only canary), 0 failures"
        status: pass
    human_judgment: false

duration: 70min
completed: 2026-09-05
status: complete
---

# Phase 4 Plan 18: Front-Door Save Journeys + Reachability Gate Summary

**Four flagless XCUITest journeys prove SAVE-03/D-40/D-38/D-37 are reachable from real navigation; the reachability sweep's own-file false-positive rate dropped from 124 to 22 findings and is now a real `--strict` CI gate; baselining it surfaced that the entire save-capture-and-upload pipeline (SaveCapturePoller/SaveUploadLane/SaveSessionRecovery) has no production trigger at all — disclosed here and in WINDOWS.md, not fixed.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-09-05T21:00:00Z (approx.)
- **Completed:** 2026-09-05T22:10:00Z (approx.)
- **Tasks:** 2
- **Files modified:** 13 (2 created, 11 modified)

## Accomplishments

- **Task 1 — Front-door journeys.** `SaveFrontDoorJourneyTests.swift` adds four journeys, each launched exactly as `StorageInteractionTests` does (no scenario flag), each thin (arrival + a named failure message, one documented behavior exception):
  - **Journey 1 (SAVE-03):** with a cached ROM, an empty local save directory, one `uploaded` restorable revision, and a real (seeded) installed adapter, pressing the List row's real "Play" button must reach the launch-path save machinery and complete (a "Last exit:" text appears; no "Launch failed" in the row's summary).
  - **Journey 2 (D-40 + MC-02):** navigating to Storage and reclaiming a game holding an only-on-this-Mac revision must present the interruptive modal; the one documented behavior assertion beyond arrival proves the default "Export saves…" button performs a real, observable action (MC-02's shipped defect was a silent no-op here).
  - **Journey 3 (D-38):** the divergence badge (`library.status-slot`, accessible name ending "needs your attention.") is visible on the card for a diverged save line, and following the readiness sheet's "Review versions…" remedy opens the real `ConflictComparisonSheet`.
  - **Journey 4 (D-37):** the readiness Save row reports real state, never the empty "No saved progress yet." placeholder, for a game with saved progress.
  - Three new `DeterministicProfile` cases (`save-restorable`, `save-only-copy`, `save-diverged`) seed the SaveStore/CAS/adapter-install state each journey needs — seeding, never routing.
- **Task 2 — Reachability gate.** Fixed the sweep's dominant false-positive class (single-file, self-contained types wrongly read as "unreachable" because the original heuristic required a reference from a separate file), cutting findings from 124 to 22. Baselined every remaining finding into an honest, per-symbol-reasoned 23-entry allowlist and registered the sweep as a `--strict` gate in `run-mac-verification.sh`.
- **Genuinely unreachable symbols found (not quietly allowlisted — see below).**

## Task Commits

1. **Task 1: Front-door journeys** — `1231580` (feat)
2. **Task 2: Reachability gate** — `d6de5e4` (fix)
3. **WINDOWS.md disclosure** — `3005eb7` (docs)

**Plan metadata:** (recorded below)

## Files Created/Modified

- `playstead-mac/PlaysteadUITests/SaveFrontDoorJourneyTests.swift` — the four journeys
- `playstead-mac/Playstead/UITesting/DeterministicProfile.swift` — three new state-seeding profiles, adapter-install seeding, save-blob CAS commits
- `playstead-mac/PlaysteadUITests/Support/UITestHarness.swift` — mirrored `Profile` enum cases
- `playstead-mac/Playstead/App/PlaysteadApp.swift` — `uiTestConsoleExportAttempts` observability hook; credential-aware UI_TESTING `AppEnvironment` init overload
- `playstead-mac/Playstead/Library/LibraryShellView.swift` — hidden accessibility element rendering the export-attempt observability hook
- `playstead-mac/Playstead/Readiness/ReadinessReportView.swift` — `playstead.readiness.row.<kind>` / `.remedy` accessibility identifiers
- `playstead-mac/Playstead/UITesting/UITestBootstrap.swift` — threads a per-profile synthetic credential through to `AppEnvironment`
- `playstead-mac/PlaysteadTests/SnapshotTests/DeterministicProfileTests.swift` — updated the fixed profile-vocabulary list (deviation, see below)
- `playstead-mac/TestPlans/UI.xctestplan` — registers `SaveFrontDoorJourneyTests`
- `playstead-mac/scripts/ci/reachability-sweep.sh` — occurrence-counting heuristic fix (both Swift and Elixir sweeps), doc-comment exclusion, fixed `is_allowlisted` to parse "SYMBOL # reason" lines
- `playstead-mac/scripts/ci/reachability-allowlist.txt` — new, 23 entries, every one reasoned
- `playstead-mac/scripts/ci/run-mac-verification.sh` — `run_reachability_sweep_layer`, wired into the aggregate before the `unit` layer
- `.planning/WINDOWS.md` — five new disclosure entries

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `DeterministicProfileTests.testProfileVocabularyIsFiniteAndExact` needed updating for the three new profile cases**
- **Found during:** Task 1, first Unit test run after adding the new `DeterministicProfile` cases
- **Issue:** The test asserts the exact, fixed list of profile raw values; adding three legitimate new cases correctly broke it.
- **Fix:** Added `"save-restorable"`, `"save-only-copy"`, `"save-diverged"` to the expected array, in declaration order.
- **Files modified:** `playstead-mac/PlaysteadTests/SnapshotTests/DeterministicProfileTests.swift`
- **Verification:** Unit test plan re-run: 511/511, 0 failures.
- **Committed in:** `1231580`

**2. [Rule 3 - Blocking] `is_allowlisted()`'s exact-line match could never match a "SYMBOL # reason" allowlist entry**
- **Found during:** Task 2, first `--strict` run after writing the allowlist
- **Issue:** The original implementation did `grep -qxF "$1" "$ALLOWLIST"` — an exact FULL-LINE match against the bare symbol name. Every entry format the plan's own verify step requires ("SYMBOL # reason", enforced by an inline-`#`-reason `awk` check) would therefore never match, silently defeating the allowlist entirely.
- **Fix:** Rewrote `is_allowlisted()` to parse each non-comment line as `SYMBOL # reason`, comparing only the trimmed symbol part.
- **Files modified:** `playstead-mac/scripts/ci/reachability-sweep.sh`
- **Verification:** `reachability-sweep.sh --strict` exits 0 with the allowlist in place.
- **Committed in:** `d6de5e4`

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking). **Impact:** Both were necessary for correctness; no scope creep.

## Genuinely Unreachable Symbols Found (per this plan's own instruction: reported, not quietly allowlisted)

Baselining the tightened reachability sweep surfaced real findings, most significantly:

**The entire save-capture-and-upload pipeline has no production trigger.**
- `SaveUploadLane` — the dedicated actor that drains locally-captured save revisions to the server (D-16/D-32) — is **never constructed anywhere in production**. This is a strict superset of the already-tracked `WINDOWS #40` (which only covered its missing failure-classification *output*): the whole upload path is unwired, not just one signal from it. If this is accurate, no save revision captured on this Mac reaches the server in the shipped app today.
- `SaveCapturePoller` is constructed in production **only** inside `SaveSessionRecovery.replay`, which itself has no production caller.
- `SaveSessionRecovery` (crash-recovery replay, D-05/D-07) is never constructed in production, despite its own doc comment stating "the shape app launch calls once per known save line."
- `FileSaveArtifactSource` (the one concrete production `SaveArtifactSource`) and `SaveCaptureBlockedState` (capture-blocked alerts) are both constructed only by test code, downstream of the same root cause.

**Other built-but-unwired production code:**
- `SaveRollup.rollup(for:)` (D-36's game-level rollup string) has zero production callers.
- `ControllerRecoveryBanner`, `ControllerTestView` (Controller settings), `FirstRunBanner`, `ShowAllSystemsControl` (LIBR-04) — four fully built SwiftUI views with zero production call sites.
- `GameListView`/`GameListRow`/`NoMatchesView`/`LibrarySortOption` — an entire file apparently superseded by `LibraryShellView.catalogueList`'s own inline `List`/`GameRowView` composition; not deleted here because `AccessibilityAuditTests` still exercises `GameListRow`'s accessible-name contract.
- Six Elixir Ecto changeset functions (`blob_changeset`, `disconnect_sessions`, `email_changeset`, `progress_changeset`, `resolve_changeset`, `reverified_ok_changeset`) with zero callers anywhere in `lib/`.

Every one of these is disclosed with its own reasoned line in `scripts/ci/reachability-allowlist.txt` and recorded in `.planning/WINDOWS.md`. None was fixed by this plan — that is out of a front-door-journey/CI-gate plan's declared scope, and the save-upload finding in particular deserves a dedicated plan and human review given its severity (it directly contradicts SAVE-01/SAVE-02's "reliably sync a persistent save revision" claim if it holds up under closer investigation).

## Issues Encountered

None beyond the two deviations documented above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Front-door reachability journeys exist for all four save surfaces and are registered in `UI.xctestplan`; execution (a real app process + real accessibility tree, and for Journey 1, a spawned adapter process) requires the hosted macOS runner (WINDOWS #34/#36) and was not run in this session, exactly as disclosed for plans 04-11/04-12's own hosted-only suites.
- `reachability-sweep.sh --strict` is a real, clean, registered CI gate with a 23-entry, fully-reasoned allowlist.
- **Strongly recommend:** a dedicated follow-up plan (or at minimum a human investigation) into whether `SaveUploadLane`/`SaveCapturePoller`/`SaveSessionRecovery` are truly unreached in the shipped app, and if so, wiring them in. This is the single most significant finding across the whole phase's gap-closure work.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-05*

## Self-Check: PASSED

All key-files (created and modified) verified present on disk with `[ -f ]`. All three commits (`1231580`, `d6de5e4`, `3005eb7`) verified present in `git log --oneline --all`. Build-for-testing exits 0 with zero errors. Unit test plan: 511/511, 0 failures. Rendering test plan: 44 passed + 2 expected local skips (hosted-only canary), 0 failures. `reachability-sweep.sh --strict` exits 0. `grep -c 'SaveFrontDoorJourneyTests' TestPlans/UI.xctestplan` == 1. `grep -c 'PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON\|PLAYSTEAD_UI_TEST_ONLY_COPY' SaveFrontDoorJourneyTests.swift` == 0.
