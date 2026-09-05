---
phase: 04-persistent-save-continuity
plan: 19
subsystem: saves
tags: [save-capture, save-upload, crash-recovery, wiring, gap-closure, reachability]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-14's restore-side wiring (GameRowView.buildSaveLaunchPlan -> SavePlanExecutor via AdapterHost.executeSavePlan) and its static-seam pattern"
  - phase: 04-persistent-save-continuity
    provides: "04-18's reachability baseline, which proved SaveCapturePoller/SaveSessionRecovery/SaveUploadLane/FileSaveArtifactSource/SaveCaptureBlockedState had zero production construction sites"
provides:
  - "SaveSessionCoordinator: one named, testable production type owning a play session's capture lifecycle (begin/end), driven by the real Play path"
  - "GameRowView.buildSaveCaptureCoordinator: the static seam that binds a launch's capture to the same target path its save plan restores into"
  - "AppEnvironment.recoverAbandonedSaveSessionsAtLaunch(): D-07 crash replay, run once per app launch from ProductionRootView"
  - "A live SaveUploadLane on AppEnvironment with three drain triggers (session promotion, reachability-online, launch recovery)"
  - "SaveUploadLane.classify: the server's D-22 machine codes mapped onto D-40's escalation vocabulary, feeding AppEnvironment.saveUploadFailureClassification()"
  - "SaveCapturePaths: the {saveDir}/{romBaseName}.sav and capture-directory rules stated once for the restore, capture and recovery halves"
affects: []

actuals:
  tokens: 19434
  tasks: 4
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Static-seam extraction for SwiftUI-owned wiring: any lifecycle driven from a private @MainActor View method lives in a `static func build*` on the View plus a named production type, so a test can assert the wiring without driving SwiftUI. Established by 04-14 for the restore half; applied here to the capture half."
    - "Falsification as an execution step, not a review step: after the wiring tests pass, delete the production call site and confirm a test goes red. A test that stays green was testing the component, not the wiring."
    - "A lock-guarded Sendable cell (SaveUploadClassificationCell) as the synchronously-readable window onto actor-owned state that a main-actor SwiftUI read needs and cannot `await` for."
    - "Capture blobs live outside the adapter's declared artifact directory: the adapter's `artifact_glob` owns saves/<assetSetID>/, so Playstead's own bookkeeping goes in save-captures/<assetSetID>/."

key-files:
  created:
    - playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveSessionCoordinatorTests.swift
  modified:
    - playstead-mac/Playstead/Library/GameRowView.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/Playstead/Saves/SaveUploadLane.swift
    - playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveSurfaceWiringTests.swift
    - playstead-mac/scripts/ci/reachability-allowlist.txt
    - .planning/WINDOWS.md

key-decisions:
  - "A fresh SaveSessionCoordinator per play session, not a shared singleton on AppEnvironment. D-04's 'exactly one promoted revision per session' is per-session state; a shared instance would either need session-keyed storage or would silently collapse two sessions into one promotion. AppEnvironment.makeSaveSessionCoordinator() is the factory, so the promotion-drains-uploads hook is attached in exactly one place."
  - "SaveUploadLane is constructed EAGERLY in AppEnvironment.init with the same non-optional `client` that SyncEngine and OutboxWorker already take, rather than lazily like downloadCoordinatorIfAvailable(). Both patterns exist in this file; the eager one is correct here because an unpaired client makes APIClient.send throw .notPaired before any connection is opened, which leaves the revision `queued` and retryable -- exactly D-32's required behavior -- whereas a lazy lane would have needed a self-capture inside init that Swift's definite-initialization rules forbid at the point the reachability observer is registered."
  - "begin() runs BEFORE adapterHost.launch, not after. D-04's session-start baseline check must read the artifact as the user left it -- the save plan's restore happens inside AdapterHost's own mutex span, so a begin() after launch would compare against bytes Playstead itself had just written and would never detect an out-of-band change."
  - "stop() then settle() then promote() in end(), which is the order SaveCapturePoller.start()'s own doc comment specifies. Settling before stopping would let a 1 Hz observe() land a staged capture between the settle pass and the promotion it feeds."
  - "A promoted revision parents onto the baseline row when begin() created one, otherwise onto the head read at begin. The plan said 'the head read at begin'; a baseline row IS that line's head by the time the session ends, so parenting onto the pre-baseline head would have forked the line against itself on every out-of-band change."
  - "The exit closure snapshots the wiring into a `let` (capturedSession) rather than taking a [saveCapture] capture list. Both are correct; the `let` was chosen because a capture list changes the closure's source spelling to `) { [saveCapture] exit in`, which broke 04-14's existing WINDOWS #37 regression guard. Accommodating a passing regression assertion by editing it is the wrong direction."
  - "classify() is deliberately conservative: only failures this Mac genuinely cannot resolve by retrying escalate. Transport loss, 5xx, 408/429 and an unpaired client all stay `.none`, because escalating a self-healing condition is precisely what D-40 forbids. The mapping keys off the server's machine-readable `code` (D-22's contract) with HTTP status only as the fallback for a response carrying no known code."
  - "Did not commit promoted capture bytes into the CAS. Disclosed as a new WINDOWS entry instead of expanded into -- see Deferred/Disclosed below."

patterns-established:
  - "When a plan's whole purpose is wiring, the falsification step is the acceptance test: remove the call site, watch a test fail, restore it. Recorded in this summary with the exact failure message, so a reader can tell the check was actually run rather than asserted."

requirements-completed: [SAVE-01, SAVE-02, SAVE-04]

coverage:
  - id: D1
    description: "Playing a game and quitting the emulator produces a promoted save revision in SaveStore, created by the shipped app's own code path, with no test flag set"
    requirement: "SAVE-01"
    verification:
      - kind: integration
        ref: "PlaysteadTests.PlayPathSaveWiringTests/testAFullSessionThroughTheProductionSeamPromotesARevisionIntoTheAppsSaveStore -- drives GameRowView.buildSaveCaptureCoordinator (the exact object play() builds), writes save bytes, ends, asserts exactly one promoted localOnly revision with the written bytes' digest"
        status: pass
      - kind: unit
        ref: "PlaysteadTests.SaveSessionCoordinatorTests (12 tests: baseline on out-of-band change, promotion, parenting, no-change-no-promotion, end-without-begin, double-end, double-begin, blocked capture, blockage clearing, no-reimplementation source guard)"
        status: pass
      - kind: other
        ref: "PlaysteadTests.PlayPathSaveWiringTests/testProductionPlayPathBeginsAndEndsACaptureSession -- asserts play()'s source begins the session before adapterHost.launch and ends it inside onExit before playSessionRecorder.ended. FALSIFIED: deleting the begin() call turned this test red with 'play() must open a capture session'."
        status: pass
    human_judgment: false
  - id: D2
    description: "The promoted revision is subsequently drained to the server by SaveUploadLane running in the shipped app"
    requirement: "SAVE-02"
    verification:
      - kind: other
        ref: "grep -rn 'SaveUploadLane(' playstead-mac/Playstead -> App/PlaysteadApp.swift production construction site; three drain triggers wired (SaveSessionCoordinator onPromoted, reachability.onChange online, recoverAbandonedSaveSessionsAtLaunch)"
        status: pass
      - kind: integration
        ref: "PlaysteadTests.SaveSurfaceWiringTests/testARevokedDeviceReachesTheEscalationSurfaceThroughTheRealLane and siblings -- environment.drainSaveUploads() reaches a stubbed server and its response is observed through AppEnvironment"
        status: pass
    human_judgment: true
    rationale: "A successful end-to-end upload against a live paired Playstead server was not executed in this session (no live server / paired device available locally, the same constraint WINDOWS #3/#6 record). The lane's own success path is covered by the pre-existing SaveUploadLaneTests (9 tests, unchanged and passing); what this plan adds and proves is that the shipped app constructs and triggers it. A hosted or manual run against a real server remains the final proof."
  - id: D3
    description: "An app launch that follows a crash mid-session replays the abandoned session through SaveSessionRecovery"
    requirement: "SAVE-01"
    verification:
      - kind: integration
        ref: "PlaysteadTests.PlayPathSaveWiringTests/testAppLaunchReplaysAnAbandonedSessionAndPromotesIt -- seeds exactly the staged-row-with-no-promoted-row a crashed session leaves, calls environment.recoverAbandonedSaveSessionsAtLaunch(), asserts one promoted revision with captureMethod 'recovery' and the crashed session's id"
        status: pass
      - kind: integration
        ref: "PlaysteadTests.PlayPathSaveWiringTests/testASecondRecoveryPassPromotesNothingNew -- D-07 idempotence"
        status: pass
      - kind: other
        ref: "PlaysteadTests.PlayPathSaveWiringTests/testProductionAppLaunchRunsSaveSessionRecovery -- asserts ProductionRootView's .task actually calls it"
        status: pass
    human_judgment: false
  - id: D4
    description: "The capture lifecycle lives in ONE named production type that both the Play path and the tests construct -- not duplicated inline in a SwiftUI view body"
    verification:
      - kind: other
        ref: "SaveSessionCoordinator.swift is the only capture lifecycle; play() calls buildSaveCaptureCoordinator and nothing else. SaveSessionCoordinatorTests/testTheCoordinatorReimplementsNoCaptureLogic asserts the coordinator calls poller.startSession/settle/promote and declares no settle/promote/digest/quiescence of its own."
        status: pass
    human_judgment: false
  - id: D5
    description: "SaveUploadLane's real failure classification reaches AppEnvironment.saveUploadFailureClassification(), replacing the online/offline-only stub, closing WINDOWS #40"
    requirement: "SAVE-04"
    verification:
      - kind: integration
        ref: "PlaysteadTests.SaveSurfaceWiringTests: device_revoked -> .revokedAuth (and OnlyCopyEscalation.evaluate now returns a non-nil escalation); save_binding_incompatible -> .compatibilityRejection; capability_incompatible -> .capabilitySkew; 500 -> .none; offline outranks a recorded .revokedAuth -> .offlineQueue"
        status: pass
      - kind: other
        ref: "testTheAssembledEnvironmentOwnsALiveUploadLane -- asserts the constant 'reachability.isOnline ? .none : .offlineQueue' no longer appears in PlaysteadApp.swift"
        status: pass
    human_judgment: false
  - id: D6
    description: "The reachability allowlist SHRINKS by exactly the symbols this plan wires; the sweep stays at zero findings under --strict"
    verification:
      - kind: other
        ref: "git diff --stat reachability-allowlist.txt -> 5 deletions, 0 insertions on the entry lines (the header comment was separately updated to record why); scripts/ci/reachability-sweep.sh --strict exits 0"
        status: pass
    human_judgment: false
  - id: D7
    description: "No regression in the Mac test suites"
    verification:
      - kind: integration
        ref: "xcodebuild test-without-building -testPlan Unit: 536 tests, 0 failures (baseline 511, +25 new); -testPlan Rendering: 46 executed, 2 skipped, 0 failures (baseline 44 passed + 2 expected local skips)"
        status: pass
    human_judgment: false

duration: 75min
completed: 2026-09-05
status: complete
---

# Phase 04 Plan 19: Save Capture-and-Upload Wiring Summary

The shipped app now captures a save during play, promotes exactly one revision at session end, replays a session it crashed in the middle of, and drains the result to the server — none of which the shipped binary had ever done, because `SaveCapturePoller`, `SaveSessionRecovery` and `SaveUploadLane` had no production construction site at all.

## What Was Broken

04-18's reachability baseline proved the capture-and-upload half of this phase was fully built, fully unit-tested, and completely unreachable:

- `SaveCapturePoller` was constructed in production **only** inside `SaveSessionRecovery.replay`, and `SaveSessionRecovery` itself was never constructed.
- `SaveUploadLane` — the dedicated actor whose entire job is getting a locally-captured save off this one Mac — had zero production callers.
- `FileSaveArtifactSource`, the one concrete production `SaveArtifactSource`, was constructed only by tests.
- `SaveCaptureBlockedState`, D-31's never-silent disk-full path, likewise.

So the app could **restore** a save at launch (04-14 wired that through `AdapterHost`'s `executeSavePlan` seam) but never captured one. SAVE-01 and SAVE-02 were, as shipped, unmet. Recorded as WINDOWS #44/#45/#46, with #40 covering the classification half.

## What Was Built

**`SaveSessionCoordinator`** (new, `Playstead/Saves/`) owns one play session's capture lifecycle and nothing else:

- `begin(saveLineID:targetURL:destinationDirectory:artifactRelativePath:)` reads the line's head from `SaveStore`, constructs a `SaveCapturePoller` over a `FileSaveArtifactSource` seeded with that digest, runs D-04's session-start baseline check, persists any baseline capture as a revision, and starts the 1 Hz loop.
- `end()` stops the loop, then runs D-05's unconditional `settle()` followed by D-04's `promote()`, and records the promotion as a `localOnly` revision with `captureMethod: "session"`.

It owns **no** capture logic. Quiescence detection, digesting, the durable write order, settle and promote all stay in `SaveCapturePoller` and are called. `testTheCoordinatorReimplementsNoCaptureLogic` asserts that against the source, because a second settle-then-promote implementation is the exact mistake `SaveSessionRecovery`'s own doc comment warns against.

`end()` never throws out to its caller — a capture failure is recorded through `SaveCaptureBlockedState` (D-31) so it is visible rather than silent, and can never surface to the user as "Launch failed".

**The Play path** (`GameRowView`) follows 04-14's pattern exactly: `buildSaveCaptureCoordinator` is a `static func` seam a test can drive, `play()` calls it and then `begin()` immediately before `adapterHost.launch`, and `end()` runs inside the existing `onExit` closure before `playSessionRecorder.ended(sessionID)`. A launch that throws also closes the session, so a failed launch can never leave a poll loop running for the rest of the app's life.

**App launch** (`ProductionRootView`) runs `recoverAbandonedSaveSessionsAtLaunch()` once via `.task`: for every save line, replay every session with a `staged` row and no `promoted` row. Failures are skipped, never fatal, never blocking — and replay is idempotent by digest, so a second pass adds nothing.

**The upload lane** is constructed eagerly on `AppEnvironment` and drained on three triggers: a session's promotion, the reachability-online transition (alongside the existing `OutboxDrainTrigger`, not queued behind it), and the launch recovery pass.

**`SaveUploadLane.classify`** maps the server's own D-22 machine codes onto D-40's escalation vocabulary, exposed through a lock-guarded cell the main actor can read synchronously. `saveUploadFailureClassification()` now returns `.offlineQueue` when unreachable (unchanged precedence) and the lane's real outcome otherwise, replacing a constant `.none` that made the four unfixable reasons permanently unreachable code.

## Falsification

Required by the plan and actually run, not asserted:

```
$ # deleted `await saveCapture?.begin()` from GameRowView.play()
$ xcodebuild test-without-building -only-testing:PlaysteadTests/PlayPathSaveWiringTests
PlayPathSaveWiringTests.swift:107: error:
  -[PlaysteadTests.PlayPathSaveWiringTests testProductionPlayPathBeginsAndEndsACaptureSession] :
  failed - play() must open a capture session -- SaveCapturePoller is otherwise never started in production
Executed 12 tests, with 1 failure
```

The call site was then restored and the suite re-run green. The test asserts against `play()`'s own source because `play()` is a private `@MainActor` SwiftUI method no test can drive — the same reason 04-14's `testProductionLaunchCallSitePassesANonNilExecuteSavePlan` exists.

## Deviations from Plan

**None affecting scope.** Three small in-scope judgement calls, each documented in `key-decisions` above:

1. The promoted revision parents onto the **baseline row** when `begin()` created one, rather than literally onto the pre-baseline head the plan's wording named — a baseline row *is* the line's head by session end, and parenting past it would fork the line against itself on every out-of-band change.
2. `SaveUploadLane` is constructed **eagerly** rather than lazily. The plan said to match "whatever pattern the existing optional-`apiClient` consumers use"; both patterns exist in `PlaysteadApp.swift` (`SyncEngine`/`OutboxWorker` eager, `downloadCoordinatorIfAvailable` lazy). Eager was chosen because it is correct for D-32 (an unpaired client throws before opening a connection, leaving the revision queued and retryable) and because a lazy lane would have required a `self` capture inside `init` that Swift's definite-initialization rules forbid at the point the reachability observer is registered.
3. `buildSaveLaunchPlan`'s inline `{saveDir}/{romBaseName}.sav` spelling was moved into `SaveCapturePaths.targetURL` so the restore, capture and recovery halves cannot derive different paths. Behaviour is byte-identical; 04-14's existing assertion on the resolved target path still passes unchanged.

One `PlayPathSaveWiringTests` refactor: the `AdapterHost` fixture (pin JSON, `/usr/bin/true` stand-in, `.install-verify.json` sidecar) was extracted into a `makeAdapterHost()` helper now shared by the pre-existing throwing-plan test and the new blocked-capture test. No assertion changed.

## Deferred / Disclosed (WINDOWS #49–#51)

Genuinely out of this plan's declared scope. Disclosed rather than expanded into, which is the discipline that surfaced this gap in the first place:

- **#49 — promoted capture bytes are not committed into the CAS.** A capture's bytes land in `save-captures/<assetSetID>/<digest>.sav` and are recorded as a `SaveStore` revision, but `LaunchSaveContextBuilder` derives head candidates' `bytesLocal` from `casManager.contains(blobSHA256)`, so a locally-captured revision reads as bytes-not-local at the next launch and cannot be restored from history until it has round-tripped through the server. Same-device continuity is unaffected (the live `.sav` artifact persists on disk, so the next launch's plan is a no-op `keep`/`fastForward`, not a restore). This is the mirror image of the already-tracked WINDOWS #38.
- **#50 — the blocked-capture alert has no consumer.** `SaveCaptureBlockedState` is constructed with no `SaveCaptureAlertSink` and no `SaveDirectUploadTransport`, so a D-31 blockage is durable and queryable but raises no user-visible alert and has no direct-upload escape hatch. Both seams exist and are injected; no attention surface consumes them yet.
- **#51 — the capture directory has no reclamation path.** Each session leaves one `session-<id>.staged.sav` and one `<digest>.sav`, and `QuotaManager` measures `paths.objects` only, so capture blobs count against neither the quota nor the free-space floor and are never evicted. Save artifacts are tens of KB, so this is slow growth rather than a hazard — but nothing bounds it.

The remaining category-(b) allowlist entries (`SaveRollup`, the four unwired UI components, `SnapshotClient`, the Elixir changesets) are untouched and still disclosed as WINDOWS #47/#48 — this plan removed exactly the five symbols it wired and nothing else.

## Verification

| Check | Result |
| --- | --- |
| Swift Unit | 536 tests, 0 failures (baseline 511, +25) |
| Rendering | 46 executed, 2 skipped, 0 failures (baseline 44 + 2 expected local skips) |
| `reachability-sweep.sh --strict` | exit 0 |
| Allowlist delta | exactly 5 entry removals, 0 insertions |
| Falsification | confirmed red on `begin()` removal, green on restore |

Known-flaky and not chased, per the plan's own note: `AppPathsBackupExclusionTests.testExistingInstallWithStaleRootFlagIsRepairedAtInit` and `SetupWizardJourneyTest`. Neither failed in this session's full Unit run.

## Windows Resolved

| id | what | commit |
| --- | --- | --- |
| 40 | D-40's four unfixable escalation reasons could not fire — no lane classification output | fb6ad53 |
| 44 | `SaveUploadLane` never constructed in production | fb6ad53 |
| 45 | `SaveCapturePoller` had no live, in-play capture trigger | 3691ec3 |
| 46 | `SaveSessionRecovery` never constructed despite its own doc comment naming app launch as the caller | 3691ec3 |

## Self-Check: PASSED

All created files exist on disk; all four task commits (9996f68, 3691ec3, fb6ad53, 408c245) are present in git history.
