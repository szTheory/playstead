---
phase: 04-persistent-save-continuity
plan: 07
subsystem: saves
tags: [swift, macos, launch-path, compatibility-gate, atomic-write, zero-network]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-02's per-assetSetID AdapterLaunchMutex and widened saveDirectory atomic-placement check; 04-04/04-06's SaveStore/SaveCapturePoller two-tier capture model and denormalized save payload shape; 04-05's server-side revision DAG (context for what a restorable revision is)"
provides:
  - "AdapterSaveContract's eight additive D-24 fields (save_kind, media, size_is_medium_identity, accepts_foreign_medium, portable_across_emulators, max_artifact_bytes, proven_media, binding_fields, provenance_fields), all Optional so an older pin still decodes"
  - "SaveCompatibilityGate: a pure, zero-network three-tier (exact/same_title/incompatible) evaluator over the D-18 binding tuple, with medium_id/artifact_bytes mismatches hard-blocked with no override affordance (D-20)"
  - "LaunchSavePlanner.plan(context:): a pure (LaunchSaveContext) -> SavePlan function stating D-44's governing invariant verbatim in source -- the launch path writes save bytes only into emptiness, or over bytes that hash to a proven ancestor of a single uncontested head"
  - "SavePlanExecutor: the impure counterpart -- stage/fsync/rename/fsync-directory, pre-restore capture with abort-on-failure, always-full-rehash, quarantine-never-delete on digest mismatch"
  - "AdapterHost.launch's new optional executeSavePlan closure, invoked inside the existing per-assetSetID AdapterLaunchMutex span, right before process spawn"
  - "docs/SUPPORT-MATRIX.md's save-restore section naming sram_32k as the only proven medium"
affects: [04-08, 04-09, 04-10, 04-11, 04-12, 04-13]

actuals:
  tokens: 16800
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Pure decision / impure execution split (LaunchSavePlanner vs SavePlanExecutor), mirroring ReadinessEngine's zero-network, disk-free evaluator shape"
    - "A value-type gate (SaveCompatibilityGate) taking two SaveBinding instances (candidate revision, local target) rather than reaching into SaveStore/CASManager itself -- the caller supplies already-denormalized facts, keeping the gate testable with zero fixtures beyond plain structs"
    - "An impure type's filesystem/CAS dependencies expressed as an injected protocol (SavePlanExecutorEnvironment) rather than a direct SaveStore/CASManager import, so its test suite proves every behaviour with a fake double and no real CAS on disk"
    - "AdapterHost.launch grows a new capability via an additional optional trailing closure parameter positioned before the existing onExit trailing closure, so every pre-existing call site (five test files, one production call site) keeps compiling and behaving identically"

key-files:
  created:
    - playstead-mac/Playstead/Saves/SaveCompatibilityGate.swift
    - playstead-mac/Playstead/Saves/LaunchSavePlanner.swift
    - playstead-mac/Playstead/Saves/SavePlanExecutor.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveCompatibilityGateTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/LaunchSavePlannerTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SavePlanExecutorTests.swift
  modified:
    - playstead-mac/Playstead/Adapter/AdapterPin.swift
    - playstead-mac/Playstead/Adapter/AdapterPin.json
    - playstead-mac/Playstead/Adapter/AdapterHost.swift
    - playstead-mac/docs/SUPPORT-MATRIX.md

key-decisions:
  - "SaveCompatibilityGate.evaluate(candidate:target:) takes two plain SaveBinding value objects rather than separate LocalGameIdentity/medium-derivation types -- both the revision under consideration and the local Mac's own binding are denormalized facts the caller already has, and this shape lets every named test in area C's behaviour list (identical tuple, medium mismatch, artifact-bytes mismatch, differing provenance) be written directly without a fixture-building layer"
  - "The compatibility gate never widens on the launch path: LaunchSavePlanner only silently auto-restores on an exact verdict; same_title (a legitimate but cross-line restore per D-19's arbitration) is deliberately routed to .keep here, because D-45's silent auto-restore is safe only when the target is empty AND the match is byte-exact -- same_title's explicit-acknowledgement requirement (area C) belongs to a save-timeline action, not a silent launch-time write, and that action is out of this plan's declared files"
  - "LaunchSaveContext is a plain value type the planner's tests construct directly (onDiskDigest, heads, ancestorDigests, knownDigests, compatibilityVerdict) rather than the planner reading SaveStore/SQLite itself -- this plan's declared files list LaunchSavePlanner.swift alone, and 04-06's SaveStore already has the shape (fetchHead, tier exclusion) a future integration plan will use to construct this context from real local state"
  - "SavePlanExecutor's dependencies on capture-before-overwrite and revision-byte lookup are expressed through an injected SavePlanExecutorEnvironment protocol rather than a direct SaveCapturePoller/CASManager import -- keeps this plan's file list to exactly the three new Saves/ types plus AdapterHost, and mirrors 04-04/04-06's precedent of building a capture/restore primitive fully tested before its live production wiring"
  - "AdapterHost.launch's executeSavePlan runs inside the existing per-assetSetID AdapterLaunchMutex span (acquired before verifyInstalledDigest, released via the same defer/termination-handler discipline 04-02 already established) rather than adding a second, save-specific mutex -- one exclusion mechanism, already proven, governs both the process spawn and the save write"

requirements-completed: [SAVE-03]

coverage:
  - id: D1
    description: "AdapterSaveContract's eight additive D-24 fields decode as nil against an older five-key pin, and the shipped pin decodes them populated with sram_32k as the only proven medium"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveCompatibilityGateTests.swift testOlderPinLackingEveryNewSaveContractKeyDecodesWithNilFields, testShippedPinDecodesTheNewOptionalFieldsPopulated (pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "SaveCompatibilityGate returns exact/same_title/incompatible per D-18/D-19/D-20/D-22: identical tuples are exact; a certain same-title match on both sides widens; medium_id/artifact_bytes mismatches hard-block with no override affordance regardless of every other field; emulator/core/version differences never gate"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveCompatibilityGateTests.swift (14 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "LaunchSavePlanner.plan states and enforces D-44's governing invariant: restoring/fast-forwarding only ever happens into emptiness or over a proven ancestor of a single uncontested head; a diverged slot always yields .keep regardless of on-disk state; an incompatible or same_title verdict never silently restores"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/LaunchSavePlannerTests.swift (15 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "SavePlanExecutor writes only via stage/fsync/rename/fsync-directory, never in place; captures the current on-disk artifact before any restore/fast-forward write and aborts on capture failure; always fully re-hashes revision bytes and quarantines (never deletes) on mismatch; .fresh/.keep write nothing; the whole exercised path issues zero HTTP requests"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SavePlanExecutorTests.swift (11 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The save plan executes inside the same per-assetSetID launch mutex as the process spawn -- a second concurrent launch for the same assetSetID is refused while executeSavePlan is still running"
    requirement: "SAVE-03"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SavePlanExecutorTests.swift testExecuteSavePlanRunsInsideThePerAssetSetIDLaunchMutex (pass)"
        status: pass
    human_judgment: false
  - id: D6
    description: "A real emulator accepts a restored .sav and shows the player's actual in-game progress (the 'Continue the game' human half of SAVE-03) -- not automatable; the file-identity half is proven above"
    verification: []
    human_judgment: true
    rationale: "Blocked on checkpoint 7 (real emulator + real game bytes), consistent with the phase's named blocked checkpoint CP7-SAVE-C. This plan proves every byte-level and mutex/atomicity property automatable today; a human must observe the emulator's own Continue/Load screen on real hardware."

duration: 26min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 7: Launch-Path Save Restore -- Compatibility Gate, Pure Planner, Atomic Executor Summary

**A three-tier, zero-network `SaveCompatibilityGate` (exact/same_title/incompatible) feeding a pure `LaunchSavePlanner` that states D-44's governing invariant verbatim in source, executed by an impure `SavePlanExecutor` that never writes in place, always re-hashes, and runs inside the existing per-`assetSetID` launch mutex.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-09-04T14:46:00Z
- **Completed:** 2026-09-04T15:12:00Z
- **Tasks:** 3
- **Files modified:** 10 (6 created, 4 modified)

## Accomplishments

- `AdapterSaveContract` (D-24): eight additive fields, all `Optional` so an older pin still decodes with them `nil`; the shipped `AdapterPin.json` now declares the full GBA backup-medium table with `sram_32k` as the only `proven_media` entry, matching `docs/SUPPORT-MATRIX.md`'s new save-restore section
- `SaveCompatibilityGate` (D-18, D-19, D-20, D-22): a pure, zero-network evaluator over `SaveBinding` value objects -- `medium_id`/`artifact_bytes` mismatches are a hard block with no override affordance of any kind; `same_title` widening requires a certain `ReferenceMatch`-shaped reading on both sides against the same title group; emulator/core/version live only in a `provenance` field the gate never reads
- `LaunchSavePlanner.plan(context:)` (D-44): a pure `(LaunchSaveContext) -> SavePlan` function whose doc comment states the governing invariant verbatim -- "the launch path writes save bytes only into emptiness, or over bytes that hash to a proven ancestor of a single uncontested head" -- and whose behaviour matches it exactly, including the sharpest edge case (an on-disk digest that is a genuine ancestor of one head, but a second head also exists, still yields `.keep`)
- `SavePlanExecutor` (D-21, D-23, D-47): stage-in-directory, `fsync` the file, `rename`, `fsync` the containing directory -- the target `.sav` is never opened for writing in place. Restoring/fast-forwarding captures whatever is currently on disk as its own revision first (aborting the whole restore, untouched, on capture failure), always fully re-hashes the candidate bytes (no inode/mtime shortcut), and quarantines (never deletes) on a digest mismatch
- `AdapterHost.launch` gained an optional `executeSavePlan` closure invoked inside the same per-`assetSetID` `AdapterLaunchMutex` span the process spawn already uses (04-02) -- proven end to end with a real short-lived child process: a second concurrent launch for the same `assetSetID` is refused with `.launchInProgress` while the first's save plan is still executing
- Full `PlaysteadTests` Unit suite: 365 tests, 0 failures (was 325 before this plan; +40 new tests across the three new files)

## Task Commits

1. **Task 1: Adapter-declared save contract and the three-tier compatibility gate** - `a1bd9b2` (feat, tdd)
2. **Task 2: The pure LaunchSavePlanner and its governing invariant** - `3842717` (feat, tdd)
3. **Task 3: The impure executor -- never in place, always re-hashed, never networked** - `39df75e` (feat, tdd)

## Files Created/Modified

- `playstead-mac/Playstead/Adapter/AdapterPin.swift` - `AdapterSaveMedium` type and `AdapterSaveContract`'s eight additive `Optional` D-24 fields
- `playstead-mac/Playstead/Adapter/AdapterPin.json` - Shipped `save_contract` populated with the mGBA media table, `sram_32k` as the only proven medium
- `playstead-mac/Playstead/Saves/SaveCompatibilityGate.swift` - New: `SaveBinding`, `SaveTitleIdentity`, `SaveProvenance`, `SaveCompatibilityGate`
- `playstead-mac/Playstead/Saves/LaunchSavePlanner.swift` - New: `SaveHeadCandidate`, `LaunchSaveContext`, `SaveLaunchNotice`, `SavePlan`, `LaunchSavePlanner`
- `playstead-mac/Playstead/Saves/SavePlanExecutor.swift` - New: `SavePlanExecutorEnvironment`, `SavePlanExecutor`, `SavePlanExecutorError`
- `playstead-mac/Playstead/Adapter/AdapterHost.swift` - `launch(...)` gained the optional `executeSavePlan` closure parameter, invoked after `verifyInstalledDigest()` and before process spawn
- `playstead-mac/docs/SUPPORT-MATRIX.md` - New save-restore section
- `playstead-mac/PlaysteadTests/SavesTests/SaveCompatibilityGateTests.swift` - New: 14 tests
- `playstead-mac/PlaysteadTests/SavesTests/LaunchSavePlannerTests.swift` - New: 15 tests
- `playstead-mac/PlaysteadTests/SavesTests/SavePlanExecutorTests.swift` - New: 11 tests

## Decisions Made

See `key-decisions` in frontmatter -- five decisions covering the gate's two-`SaveBinding` shape, why `same_title` never silently restores on the launch path, why `LaunchSaveContext` is a plain value type the planner's tests construct directly rather than a SQLite-backed read, why `SavePlanExecutor`'s capture/lookup dependencies are an injected protocol rather than direct `SaveStore`/`CASManager` imports, and why `executeSavePlan` reuses the existing per-`assetSetID` mutex rather than adding a second one.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

- `LaunchSavePlanner`/`SavePlanExecutor` are not yet wired into the live Play flow (`GameRowView.play()` still calls `AdapterHost.launch` without an `executeSavePlan` closure). This plan's own declared files are the three new `Saves/` types plus `AdapterHost.swift`; constructing a real `LaunchSaveContext` from `SaveStore`'s live tables (heads, ancestry, known digests) and a real `SavePlanExecutorEnvironment` backed by `SaveCapturePoller`/`CASManager` is deferred to a later integration plan, mirroring 04-04's `SaveBytesPrefetcher` and 04-06's `SaveSessionRecovery`/live-session-wiring precedent of building and fully testing a primitive before its production call site exists. Plan 04-13 ("Prove what can be proven automatically") is the named downstream consumer of this wiring.
- `SaveStore` has no `fetchHeads` (plural) or ancestry-derivation query yet -- `LaunchSaveContext`'s `heads`/`ancestorDigests`/`knownDigests` fields are constructed by the caller today (tests, and later the live wiring plan). Deriving these from `SaveStore`'s existing `parent_revision_id` DAG is straightforward but out of this plan's declared file list (`SaveStore.swift` is not in `files_modified`).
- CP7-SAVE-C (named blocked checkpoint, carried from area C/F's research): that a real emulator (mGBA 0.10.5) actually resumes gameplay from a restored `.sav` on real hardware is a human observation, not automatable. Every byte-level, mutex, and atomicity property this plan can prove automatically is proven; "Continue the game" is not dressed up as a passing test anywhere in this plan.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers -- no new network endpoint, auth path, or schema change was introduced. `SaveCompatibilityGate`/`LaunchSavePlanner`/`SavePlanExecutor` are all purely local, non-networked types, and `AdapterHost.launch`'s new parameter is additive and defaults to a no-op for every existing call site.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The D-44 invariant is stated in source and asserted by test at every listed edge case (empty-target restore, ancestor fast-forward, diverged-with-any-on-disk-state keep, incompatible/same_title never silently restoring)
- `AdapterHost.launch`'s `executeSavePlan` seam is the exact integration point plan 04-13's "strict zero-network Play flow assertion" will drive with real `SaveStore`/`CASManager`-backed dependencies
- `SaveCompatibilityGate`'s `binding_fields`/`provenance_fields` split (read from the adapter pin, not hardcoded) is the seam SEED-019 (save states) widens later with zero client-side gate change
- Full `PlaysteadTests` Unit suite (365 tests) passes with the changes in place, including every pre-existing `AdapterHost`/`ReadinessEngine`/`Saves*` test file unchanged
- Ready for 04-08.

## Self-Check: PASSED

- `[ -f playstead-mac/Playstead/Saves/SaveCompatibilityGate.swift ]` -> FOUND
- `[ -f playstead-mac/Playstead/Saves/LaunchSavePlanner.swift ]` -> FOUND
- `[ -f playstead-mac/Playstead/Saves/SavePlanExecutor.swift ]` -> FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/SaveCompatibilityGateTests.swift ]` -> FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/LaunchSavePlannerTests.swift ]` -> FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/SavePlanExecutorTests.swift ]` -> FOUND
- `git log --oneline --all | grep -q a1bd9b2` -> FOUND
- `git log --oneline --all | grep -q 3842717` -> FOUND
- `git log --oneline --all | grep -q 39df75e` -> FOUND
- `xcodebuild test ... -only-testing:PlaysteadTests/SaveCompatibilityGateTests` -> PASS (14 tests, 0 failures)
- `xcodebuild test ... -only-testing:PlaysteadTests/LaunchSavePlannerTests` -> PASS (15 tests, 0 failures)
- `xcodebuild test ... -only-testing:PlaysteadTests/SavePlanExecutorTests` -> PASS (11 tests, 0 failures)
- `xcodebuild test ... -testPlan Unit` (full plan) -> PASS (365 tests, 0 failures)
- `grep -v '^\s*//' SaveCompatibilityGate.swift | grep -ciE 'URLSession|http|await .*client'` -> 0
- `grep -c 'sram_32k' docs/SUPPORT-MATRIX.md` -> 2 (at least 1 required)
- `grep -c 'writes save bytes only into emptiness' LaunchSavePlanner.swift` -> 1
- `grep -v '^\s*//' LaunchSavePlanner.swift | grep -ciE 'URLSession|write\(|createFile|FileHandle.*writ'` -> 0
- `grep -c 'Picked up from your' LaunchSavePlanner.swift` -> 1
- `grep -v '^\s*//' SavePlanExecutor.swift | grep -c 'fsync'` -> 2
- `grep -v '^\s*//' SavePlanExecutor.swift | grep -ciE 'inode|mtime'` -> 0
- `grep -rn 'saveDirectoryURL' SavePlanExecutor.swift` -> 1 match (doc comment naming the caller's path source)
- `grep -rn 'URLSession' LaunchSavePlanner.swift SaveCompatibilityGate.swift SavePlanExecutor.swift` -> no matches

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*
