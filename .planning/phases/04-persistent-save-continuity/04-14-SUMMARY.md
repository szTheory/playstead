---
phase: 04-persistent-save-continuity
plan: 14
subsystem: saves
tags: [swift, macos, launch-path, wiring, gap-closure, zero-network]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-07's LaunchSavePlanner, SavePlanExecutor, SavePlanExecutorEnvironment protocol, and AdapterHost.launch's executeSavePlan seam"
  - phase: 04-persistent-save-continuity
    provides: "04-11's SaveStore.fetchHeads(saveLineID:), which the context builder consumes"
provides:
  - "LaunchSaveEnvironment: the first production SavePlanExecutorEnvironment, backed by the real CASManager -- revisionBytes never fetches over the network, captureExistingFile preserves pre-existing bytes into the CAS, quarantineCorruptRevision routes to CASManager's existing quarantine path"
  - "LaunchSaveContextBuilder: assembles a LaunchSaveContext from already-local SaveStore/CASManager facts, resolving the save line by content_key (the ROM's own sha256, per D-10) rather than assetSetID"
  - "GameRowView.play() actually calls into the launch-path save machinery -- the production Play button now builds a context, gets a plan, and passes a non-nil executeSavePlan to AdapterHost.launch, closing WINDOWS #37"
  - "GameRowView.buildSaveLaunchPlan(...): the plan-construction logic extracted to an internal, directly-testable static method so PlayPathSaveWiringTests can assert the seam is used, not just that the planner works in isolation"
  - "SaveStore.fetchRevisions(saveLineID:): every revision recorded for one line, needed to derive ancestorDigests/knownDigests"
affects: [04-VALIDATION]

actuals:
  tokens: 42000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Extracting UI-adjacent business logic (buildSaveLaunchPlan) out of a private SwiftUI method into an internal static function purely so a regression test can call it directly -- SwiftUI view methods are otherwise untestable without a UI-driving harness"
    - "Source-inspection regression tests (grep-the-source-as-a-string, mirroring ReadinessEngineTests' own precedent) to guard a specific call-site wiring fact (non-nil executeSavePlan, no second mutex) that unit tests against the extracted logic alone cannot prove by themselves"
    - "Building a synthetic target SaveBinding identical to the candidate's when restoring into emptiness, since there is no independent on-disk binding to compare against -- the compatibility gate still meaningfully hard-blocks an artifact whose size matches no medium the adapter pin declares (D-24), even though systemID/saveKind/romSHA256 match trivially by construction"

key-files:
  created:
    - playstead-mac/Playstead/Saves/LaunchSaveEnvironment.swift
    - playstead-mac/Playstead/Saves/LaunchSaveContextBuilder.swift
    - playstead-mac/PlaysteadTests/SavesTests/LaunchSaveEnvironmentTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/LaunchSaveContextBuilderTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift
  modified:
    - playstead-mac/Playstead/Library/GameRowView.swift
    - playstead-mac/Playstead/Persistence/SaveStore.swift

key-decisions:
  - "content_key is the ROM's own sha256 (first required member's digest), never assetSetID -- matching the server's own Playstead.Saves.Save moduledoc verbatim ('content_key is the ROM sha256, not asset_set_id, so a re-import cannot orphan every save'). Using assetSetID would have diverged from server semantics and silently duplicated/orphaned lines on any future re-import."
  - "The resolved save artifact path is saves/<assetSetID>/<romBaseName>.sav, where romBaseName is the materialized ROM file's own name with its extension stripped -- no production code defined this convention before this plan (SaveCapturePoller's caller decides the filename, and no production caller existed yet), so this plan establishes it, matching SavePlanExecutor's own doc comment naming that exact shape."
  - "captureExistingFile (D-21) preserves pre-existing bytes by committing them into the CAS under their own content digest, rather than synthesizing a full SaveStore revision row. Recording it as a real revision (visible in SaveHistorySheet) would require SaveStore/SaveCapturePoller changes outside this plan's declared files; the CAS commit already satisfies D-21's actual contract, which is only that the bytes are never lost. Documented as a Known Stub."
  - "The compatibility verdict's target SaveBinding is built from the same facts as the candidate rather than from an independent on-disk reading, because there is no independent on-disk binding to compare against when restoring into emptiness (the whole point of this branch). This still hard-blocks a revision whose recorded size matches no medium the adapter pin declares -- the one check that meaningfully fires given the data actually available -- while trivially clearing systemID/saveKind/romSHA256, which are equal by construction (same line, same content_key)."
  - "SaveLaunchNotice is held on a new GameRowView @State property (saveLaunchNotice) rather than rendered anywhere. No detail view with a Save section exists yet in this codebase for it to be surfaced 'inline' into (04-CONTEXT.md's own placement rule presupposes a view this plan's declared files do not build). The negative constraint (never modal, toast, or status-slot) is fully honored; the positive constraint (inline in the detail view) is deferred, honestly, to whichever plan builds that view. Documented as a Known Stub and recorded in WINDOWS.md."
  - "GameRowView.buildSaveLaunchPlan(...) is extracted as an internal static method taking every dependency as a parameter, rather than left as inline logic inside play(). play() is a private @MainActor SwiftUI method with no test-driving harness in this codebase; without the extraction, PlayPathSaveWiringTests could only prove the planner works in isolation -- exactly the blind spot that let WINDOWS #37 exist for two whole plans (04-07 built the seam, 04-13 declined to wire it, and nothing caught the gap until this plan's own analysis)."

requirements-completed: [SAVE-03]

coverage:
  - id: D1
    description: "The production Play path builds a LaunchSaveContext, asks LaunchSavePlanner.plan(context:) for a plan, and passes a non-nil executeSavePlan closure to AdapterHost.launch -- the default nil is never taken on the real Play path"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift testProductionLaunchCallSitePassesANonNilExecuteSavePlan (pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A production SavePlanExecutorEnvironment exists, backed by the real CASManager; revisionBytes never fetches over the network for a digest absent from the CAS"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/LaunchSaveEnvironmentTests.swift (8 tests, pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "LaunchSaveContextBuilder assembles a context from already-local facts only: a head absent from the CAS is reported bytesLocal:false rather than omitted; onDiskDigest is nil for both a missing and a zero-byte target; a missing save line yields a context whose plan is a no-op"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/LaunchSaveContextBuilderTests.swift (13 tests, pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "A plan that requires a write reaches SavePlanExecutor with the resolved saves/<assetSetID>/<romBaseName>.sav target path; a throwing plan aborts the launch before AdapterHost ever spawns the emulator and releases the per-assetSetID mutex; no second mutex is introduced"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift testAWriteRequiringPlanRestoresTheExactBytesAtTheResolvedTargetPath, testAThrowingExecuteSavePlanAbortsBeforeTheEmulatorSpawns, testGameRowViewSourceNeverReferencesASecondLaunchMutex (pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "CP7-SAVE-C's step 3 (clear the save directory, relaunch through Playstead, expect automatic restore with no prompt) is now performable on the production path -- the file-identity half is proven above; a real emulator resuming gameplay from the restored bytes is CP7-SAVE-C's own named blocked checkpoint (04-07/04-13), not re-litigated here"
    verification: []
    human_judgment: true
    rationale: "Requires a real installed emulator and real game bytes, consistent with CP7-SAVE-C's existing named-blocked status from 04-07/04-13. This plan makes the production call site reachable; it does not change CP7-SAVE-C's automatability."

duration: 50min
completed: 2026-09-05
status: complete
---

# Phase 4 Plan 14: Wiring the Launch-Path Save Restore Into the Play Button Summary

**Closed WINDOWS #37 by building the first production `SavePlanExecutorEnvironment` and a `LaunchSaveContextBuilder`, then wiring `GameRowView.play()` to actually call `LaunchSavePlanner`/`SavePlanExecutor` and pass a non-nil `executeSavePlan` to `AdapterHost.launch` — with a regression test that asserts the seam is used, not merely that it works in isolation.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-09-04T22:00:00Z (approx.)
- **Completed:** 2026-09-05T02:30:00Z
- **Tasks:** 2
- **Files modified:** 7 (5 created, 2 modified)

## Accomplishments

- `LaunchSaveEnvironment` (new): the first production `SavePlanExecutorEnvironment`, backed by `CASManager`. `revisionBytes(forDigest:)` throws immediately for a digest absent from the CAS rather than reaching for the network (D-43/D-F03); `captureExistingFile(at:)` preserves whatever sits at the restore target before it is overwritten by committing it into the CAS under its own digest (D-21); `quarantineCorruptRevision` routes to `CASManager.quarantine(partialAt:reason:)` (D-23).
- `LaunchSaveContextBuilder` (new): assembles a `LaunchSaveContext` from `SaveStore`/`CASManager` reads only. Resolves the save line by `content_key` (the ROM's own sha256, D-10 — never `assetSetID`), marks each head's `bytesLocal` from the CAS, hashes on-disk bytes for `onDiskDigest` (`nil` for both missing and zero-byte), populates `knownDigests`/`ancestorDigests` from every revision recorded for the line, and attaches a `SaveCompatibilityGate` verdict only when exactly one head exists. Returns a no-op context (empty `heads`) when no save line exists yet — a first-ever launch is the normal case.
- `GameRowView.play()`: now builds the context, asks `LaunchSavePlanner.plan(context:)` for a plan, and passes `executeSavePlan:` bound to a real `SavePlanExecutor`/`LaunchSaveEnvironment` pair to `AdapterHost.launch` — the exact call site WINDOWS #37 recorded as missing. The plan-construction logic lives in a new internal `GameRowView.buildSaveLaunchPlan(...)` static method rather than inline inside the private `play()`, specifically so it is directly testable.
- `PlayPathSaveWiringTests` (new, 5 tests): asserts the production call site names `executeSavePlan:` and never passes a literal `nil`; that a write-requiring plan reaches the executor with the resolved `saves/<assetSetID>/<romBaseName>.sav` target and restores the exact bytes; that a first-ever launch writes nothing; that a throwing `executeSavePlan` aborts the launch before `AdapterHost` ever spawns the emulator and releases the per-`assetSetID` mutex; and that no second mutex was introduced.
- Full `PlaysteadTests` Unit suite: 481 tests, 0 failures (was 457 before this plan; +24 new tests across the three new/extended files).

## Task Commits

1. **Task 1: A production save-plan environment and context builder** - `ccd0e7a` (feat, tdd)
2. **Task 2: Wire the Play path and prove it stays wired** - `17e4f3d` (feat, tdd)

## Files Created/Modified

- `playstead-mac/Playstead/Saves/LaunchSaveEnvironment.swift` - New: production `SavePlanExecutorEnvironment`
- `playstead-mac/Playstead/Saves/LaunchSaveContextBuilder.swift` - New: assembles `LaunchSaveContext` from local facts
- `playstead-mac/Playstead/Library/GameRowView.swift` - `play()` wired to the launch-path save machinery; new `buildSaveLaunchPlan(...)` static method; new `saveLaunchNotice` @State
- `playstead-mac/Playstead/Persistence/SaveStore.swift` - New `fetchRevisions(saveLineID:)` query
- `playstead-mac/PlaysteadTests/SavesTests/LaunchSaveEnvironmentTests.swift` - New: 8 tests
- `playstead-mac/PlaysteadTests/SavesTests/LaunchSaveContextBuilderTests.swift` - New: 13 tests
- `playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift` - New: 5 tests

## Decisions Made

See `key-decisions` in frontmatter — most notably: `content_key` is the ROM's own sha256 (matching the server's own module doc verbatim), the save artifact path convention (`saves/<assetSetID>/<romBaseName>.sav`) is established here for the first time since no production caller existed before this plan, `captureExistingFile`'s CAS-commit approach satisfies D-21's actual contract without a wider `SaveStore` schema change, the compatibility verdict's synthetic target binding still meaningfully hard-blocks an unbound artifact size, the notice is held rather than rendered pending a not-yet-built detail view, and `buildSaveLaunchPlan` is extracted specifically so a regression test can assert the seam is used.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SaveStore.swift` needed a `fetchRevisions(saveLineID:)` query, not in the plan's declared file list**
- **Found during:** Task 1
- **Issue:** The plan's task 1 file list did not name `SaveStore.swift`, but deriving `ancestorDigests` (walking a head's `parent_revision_id` chain) and `knownDigests` (every digest recorded for the line) both require reading every revision for one line — no existing query exposed this; `fetchHeads` returns only heads, `fetchAllRevisions` returns every line's revisions, and `fetchRevisions(sessionID:)` is scoped to a session, not a line.
- **Fix:** Added `fetchRevisions(saveLineID:)`, a one-line wrapper around the existing private `fetchRevisions(matching:params:)` helper — mirrors the exact shape of `fetchRevisions(sessionID:)` immediately above it.
- **Files modified:** `playstead-mac/Playstead/Persistence/SaveStore.swift`
- **Verification:** `LaunchSaveContextBuilderTests.testKnownDigestsPopulatedFromEveryRevisionRecordedForTheLine` (pass)
- **Committed in:** `ccd0e7a` (Task 1)

---

**Total deviations:** 1 auto-fixed (Rule 3, blocking). **Impact:** Necessary for D-44's fast-forward safety check to be computable at all; no scope creep — it is a one-line query addition mirroring an existing sibling method's exact shape.

## Issues Encountered

None.

## Known Stubs

- `LaunchSaveEnvironment.captureExistingFile` preserves pre-existing save bytes by committing them into the CAS under their own content digest, but does not create a `SaveStore` revision row — a pre-restore capture on the launch path is therefore durable but not yet visible in `SaveHistorySheet`. Recorded as WINDOWS #38.
- `GameRowView`'s new `saveLaunchNotice` @State property holds the plan's `SaveLaunchNotice` but nothing renders it: no detail view with a Save section exists yet anywhere in this codebase (04-CONTEXT.md's placement rule presupposes a view this plan does not build). The negative constraint (never modal/toast/status-slot) is fully honored; the positive constraint is deferred to whichever future plan builds that surface. Recorded as WINDOWS #39.
- The compatibility gate's target `SaveBinding` is synthesized from the same facts as the candidate rather than an independently-observed on-disk binding, since restoring into emptiness has nothing independent to compare against. This is not a stub in the sense of missing work — it's the honest shape of the problem given `SaveRevisionRow`'s current schema, which records `sizeBytes` but not a per-revision `romSHA256`/`mediumID`. A future schema change (recording the binding tuple on the revision itself at capture time) would let the gate do genuine cross-device binding comparison instead of same-content-key-implies-compatible.

## Threat Flags

None beyond what the plan's own `<threat_model>` (D-44, D-21, D-23, D-43/D-F03, D-65) already covers. `LaunchSaveEnvironment` and `LaunchSaveContextBuilder` are purely local, non-networked types confirmed by both a functional test (`testRevisionBytesThrowsForADigestAbsentFromTheCASRatherThanFetching`) and a source-inspection test (`testEnvironmentSourceNeverReferencesNetworkingTypes`). `GameRowView`'s new call site introduces no new network surface, auth path, or schema change.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- WINDOWS #37 is closed: `grep -n 'executeSavePlan' playstead-mac/Playstead/Library/GameRowView.swift` returns a match, and `PlayPathSaveWiringTests` guards the regression going forward.
- CP7-SAVE-C's step 3 (clear the save directory, relaunch, expect automatic restore with no prompt) is now performable on the production path — the remaining blocker is CP7-SAVE-C itself (real emulator, real commercial title), unchanged from 04-07/04-13's own honest accounting.
- Full `PlaysteadTests` Unit suite (481 tests) passes with the changes in place.
- Two new stubs recorded in WINDOWS.md (#38, #39) for a future plan to pick up: revision-row capture on the launch path, and the detail-view Save section this notice will eventually render into.
- Ready for `/gsd-verify-work` on Phase 4, or whichever plan builds the detail view that surfaces `SaveLaunchNotice`.

## Self-Check: PASSED

- `[ -f playstead-mac/Playstead/Saves/LaunchSaveEnvironment.swift ]` -> FOUND
- `[ -f playstead-mac/Playstead/Saves/LaunchSaveContextBuilder.swift ]` -> FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/LaunchSaveEnvironmentTests.swift ]` -> FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/LaunchSaveContextBuilderTests.swift ]` -> FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift ]` -> FOUND
- `git log --oneline --all | grep -q ccd0e7a` -> FOUND
- `git log --oneline --all | grep -q 17e4f3d` -> FOUND
- `xcodebuild test ... -only-testing:PlaysteadTests/LaunchSaveEnvironmentTests -only-testing:PlaysteadTests/LaunchSaveContextBuilderTests` -> PASS (19 tests, 0 failures)
- `xcodebuild test ... -only-testing:PlaysteadTests/PlayPathSaveWiringTests` -> PASS (5 tests, 0 failures)
- `xcodebuild test ... -testPlan Unit` (full plan) -> PASS (481 tests, 0 failures; baseline was 457)
- `grep -n 'executeSavePlan' playstead-mac/Playstead/Library/GameRowView.swift` -> match found
- `grep -rn 'AdapterLaunchMutex' playstead-mac/Playstead/Library/GameRowView.swift` -> no matches
- `grep -rniE 'URLSession|APIClient|http' playstead-mac/Playstead/Saves/LaunchSaveEnvironment.swift` -> no matches
- WINDOWS.md entry #37 marked `fixed` via `gsd-tools windows fixed 37`

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-05*
