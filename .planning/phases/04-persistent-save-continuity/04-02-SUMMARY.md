---
phase: 04-persistent-save-continuity
plan: 02
subsystem: infra
tags: [swift, macos, filesystem, backup, concurrency, readiness]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "AppPaths cache-root layout, AdapterProcessRegistry's NSLock-guarded process tracking, and ReadinessEngine's six-check gate, all extended (not replaced) here"
provides:
  - "Per-directory backup exclusion with an idempotent stale-root-flag clear (D-63), so saves and the SQLite catalogue reach Time Machine for the first time"
  - "AdapterLaunchMutex, a per-assetSetID launch mutex spanning prepare -> spawn -> exit (D-65), so two mGBA instances can never open one game's .sav concurrently"
  - "A saveDirectory readiness check that proves a file can be atomically placed and replaced, not merely that a directory is nominally writable (D-42)"
affects: [04-06, 04-07, 04-12]

actuals:
  tokens: 10095
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Sibling NSLock-guarded structures added alongside an existing registry rather than modifying it (AdapterLaunchMutex next to AdapterProcessRegistry)"
    - "Fixed, well-known probe target filenames (not per-call random names) when a readiness check needs to reproduce a real collision scenario deterministically in tests"

key-files:
  created:
    - playstead-mac/PlaysteadTests/CacheTests/AppPathsBackupExclusionTests.swift
    - playstead-mac/PlaysteadTests/AdapterTests/LaunchMutexTests.swift
    - playstead-mac/PlaysteadTests/ReadinessTests/SaveDirectoryAtomicPlacementTests.swift
  modified:
    - playstead-mac/Playstead/App/AppPaths.swift
    - playstead-mac/Playstead/Adapter/AdapterHost.swift
    - playstead-mac/Playstead/Readiness/ReadinessEngine.swift
    - playstead-mac/Playstead/Library/GameRowView.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/PlaysteadTests/CurationTests/PlaySessionTests.swift
    - playstead-mac/PlaysteadTests/AdapterTests/AdapterWiringTests.swift
    - playstead-mac/PlaysteadTests/AdapterTests/AdapterPinTests.swift
    - playstead-mac/PlaysteadTests/AdapterTests/InstallerTests.swift

key-decisions:
  - "clearStaleRootBackupExclusion runs before excludeReconstructableDirectoriesFromBackup on every init, so a stale root-level true can never re-inherit onto a directory whose own flag is written in the same pass"
  - "AdapterHost.launch takes a new required assetSetID parameter (not an optional with a fallback), forcing every call site — including five existing test files — to declare the mutex key explicitly rather than deriving it implicitly from saveDir"
  - "The atomic-placement probe replaces onto a fixed well-known filename (.playstead-readiness-write-probe-target), not a fresh UUID per evaluation, because the whole point is proving REPLACE succeeds against a name that may already be occupied by an immutable .sav — a random name could never collide with anything and would prove nothing beyond isWritableFile already proved"
  - "PlaysteadApp.swift's separate saveDirectoryURL-failure fallback path (outside the plan's declared files) was also updated to the locked copy, since it renders the identical saveDirectory blocker and the plan's own <verification> step greps the whole Playstead/ tree for the retired 'Repair save directory' string"

requirements-completed: [SAVE-01, SAVE-03]

coverage:
  - id: D1
    description: "Backup exclusion applies only to objects/, partials/, launch/, emulators/, bios/; root, saves/, and playstead.sqlite3 are never excluded; a stale pre-fix root flag is cleared idempotently at every launch"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/CacheTests/AppPathsBackupExclusionTests.swift (5 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "AdapterLaunchMutex refuses a second concurrent launch of the same assetSetID with .launchInProgress while a different assetSetID proceeds unaffected; an interrupted launch releases its key; process exit releases the key regardless of AdapterExit classification"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/LaunchMutexTests.swift (7 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "saveDirectory readiness check blocks when a directory-writable-but-atomic-replace-fails case exists (an immutable file at the replace target), and carries the four locked copy strings verbatim; every outcome leaves the directory's contents unchanged"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/ReadinessTests/SaveDirectoryAtomicPlacementTests.swift (5 tests, all pass)"
        status: pass
    human_judgment: false

duration: 32min
completed: 2026-09-03
status: complete
---

# Phase 4 Plan 02: Backup Exclusion, Launch Mutex, and Save-Directory Atomicity Summary

**Fixed three shipped Mac-side defects that each independently blocked a Phase 4 success criterion: `isExcludedFromBackup` moved off the Application Support root onto the five reconstructable cache directories with an idempotent stale-flag repair (D-63), a per-`assetSetID` `AdapterLaunchMutex` now spans every launch's prepare-to-exit span (D-65), and the `saveDirectory` readiness check now proves an atomic file placement rather than mere directory writability (D-42).**

## Performance

- **Duration:** 32 min
- **Started:** 2026-09-03T23:44:42Z
- **Completed:** 2026-09-03T23:55:14Z
- **Tasks:** 3
- **Files modified:** 12

## Accomplishments
- Saves and `playstead.sqlite3` reach Time Machine for the first time on fresh installs, and existing installs are repaired automatically at the next launch — no user action required
- Two launch attempts for one game can no longer both reach process spawn; a refused second launch fails with a distinct, typed `.launchInProgress` error rather than corrupting the shared `.sav`
- The sole blocking save condition in Phase 4 now proves what launch actually needs (an atomic replace succeeds), catching an immutable existing `.sav` that the old writability check passed and the emulator then failed on

## Task Commits

1. **Task 1: Move backup exclusion off the root and onto the reconstructable directories** - `3e39dd7` (feat)
2. **Task 2: Add a per-assetSetID launch mutex spanning prepare → spawn → exit** - `7df9360` (feat)
3. **Task 3: Widen the saveDirectory readiness check to atomic placement** - `e91ad42` (feat)

## Files Created/Modified
- `playstead-mac/Playstead/App/AppPaths.swift` - Replaced `excludeRootFromBackup` with `excludeReconstructableDirectoriesFromBackup` (five managed dirs only) and `clearStaleRootBackupExclusion` (idempotent migration)
- `playstead-mac/Playstead/Adapter/AdapterHost.swift` - Added `AdapterLaunchMutex` sibling to `AdapterProcessRegistry`; wired acquire/release into `launch`, added `assetSetID` parameter and `.launchInProgress` error case
- `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` - `evaluateSaveDirectory()` now performs a probe-write + atomic replace against a fixed target name instead of `isWritableFile`; uses the four locked D-42 copy strings
- `playstead-mac/Playstead/Library/GameRowView.swift` - Updated the one production `adapterHost.launch` call site to pass `assetSetID: entry.id`
- `playstead-mac/Playstead/App/PlaysteadApp.swift` - Updated the `saveDirectoryURL`-failure fallback's blocker/remedy copy to match D-42's locked strings
- `playstead-mac/PlaysteadTests/CacheTests/AppPathsBackupExclusionTests.swift` - New: 5 tests covering fresh install, existing-install migration, and idempotent double-init
- `playstead-mac/PlaysteadTests/AdapterTests/LaunchMutexTests.swift` - New: 7 tests covering mutex primitive semantics and end-to-end `AdapterHost.launch` wiring with real short-lived child processes
- `playstead-mac/PlaysteadTests/ReadinessTests/SaveDirectoryAtomicPlacementTests.swift` - New: 5 tests covering ready, missing-directory, immutable-target-blocks, locked-copy, and no-residue behaviours
- `playstead-mac/PlaysteadTests/CurationTests/PlaySessionTests.swift`, `AdapterTests/AdapterWiringTests.swift`, `AdapterTests/AdapterPinTests.swift`, `AdapterTests/InstallerTests.swift` - Updated existing `host.launch(...)` call sites to pass the new required `assetSetID` parameter

## Decisions Made
- Clear-then-exclude ordering in `AppPaths.init`: `clearStaleRootBackupExclusion` always runs before `excludeReconstructableDirectoriesFromBackup`, so a pre-D-63 install's stale root-level `true` can never re-inherit onto a directory whose own flag this same pass is about to set
- `AdapterHost.launch` gained a required (not optional/derived) `assetSetID` parameter, forcing every call site to declare the mutex key explicitly — five test files and one production call site were updated
- The atomic-placement probe's replace target is a fixed, well-known filename rather than a fresh UUID each evaluation, since the property under test is specifically "REPLACE succeeds against a name that might already be occupied" — a random name could never collide with a pre-existing immutable file and would degenerate back into "an empty name is available", the exact weaker claim D-42 exists to replace
- Extended the fix's locked D-42 copy into `PlaysteadApp.swift`'s separate `saveDirectoryURL`-construction-failure fallback path (outside the plan's declared file list) because it renders the identical `saveDirectory` blocker, and the plan's own `<verification>` step greps the entire `Playstead/` tree for the retired "Repair save directory" string

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated a second "Repair save directory" copy site outside the plan's declared files**
- **Found during:** Task 3 (widening the saveDirectory check)
- **Issue:** `PlaysteadApp.swift`'s `readinessReport(for:)` has its own fallback `ReadinessCheck` (used when the asset-set id can't be validated as a folder name) that duplicated the old "Save directory not writable." / "Repair save directory" copy. The plan's own `<verification>` block (`grep -rn 'Repair save directory' playstead-mac/Playstead/`) would have failed if this site were left unchanged, and a user hitting this rare path would have seen stale, non-locked copy.
- **Fix:** Updated the blocker and remedy title to the same D-42 locked strings used in `ReadinessEngine.swift`.
- **Files modified:** `playstead-mac/Playstead/App/PlaysteadApp.swift`
- **Verification:** `grep -rn 'Repair save directory' playstead-mac/Playstead/` returns no hits (plan-level `<verification>` re-run, PASS)
- **Committed in:** `e91ad42` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 bug/consistency fix)
**Impact on plan:** In scope — the plan's own verification step covers the entire `Playstead/` tree, not just the three declared files, and this second site renders the identical user-facing condition. No architectural change, no scope creep.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three defects named in 04-CONTEXT.md's "Launch Path" and "Cross-Cutting" sections are closed: D-63 (backup exclusion boundary), D-65 (launch mutex), D-42 (saveDirectory atomicity)
- Full `PlaysteadTests` unit suite (288 tests) passes with the changes in place, including all pre-existing `ReadinessEngineTests` and adapter/curation tests updated for the new `launch(assetSetID:...)` signature
- D-65's launch mutex is now in place as the precondition 04-06's capture guarantees depend on; D-42's widened check is what 04-07's launch path will consume as the sole blocking save condition
- Ready for 04-03.

## Self-Check: PASSED

- `[ -f playstead-mac/Playstead/App/AppPaths.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Adapter/AdapterHost.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Readiness/ReadinessEngine.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/CacheTests/AppPathsBackupExclusionTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/AdapterTests/LaunchMutexTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/ReadinessTests/SaveDirectoryAtomicPlacementTests.swift ]` → FOUND
- `git log --oneline --all | grep -q 3e39dd7` → FOUND
- `git log --oneline --all | grep -q 7df9360` → FOUND
- `git log --oneline --all | grep -q e91ad42` → FOUND
- All plan-level `<verification>` commands re-run above: PASS (three `-only-testing` runs green with non-zero counts; both retirement greps return zero hits)
- Full `PlaysteadTests` Unit test plan: 288 tests, 0 failures

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-03*
