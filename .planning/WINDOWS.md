---
schema_version: 1
open_count: 36
waived_count: 1
fixed_count: 6
total_count: 43
last_updated: 2026-09-05T14:17:20.303Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 03 | stub | playstead-mac/Playstead/Adapter/AdapterHost.swift |  | verifyInstalledDigest() expects an .install-verify.json sidecar that no plan yet writes (emulator installer is 03-08/03-09 territory) | fixed |  | 2026-08-31T00:10:31.234Z | 2026-08-31T02:44:11.180Z |
| 2 | 03 | unrun-verify | playstead-mac/scripts/sign-and-notarize.sh |  | Notarization + Developer-ID release build could not run (no Developer ID Application cert / paid Apple Developer Program in this environment); notarization deferred per 03-01 owner decision | waived | Deferred by owner 2026-08-31: local development only; no Developer ID / paid Apple Developer Program enrollment this milestone. Notarization is distribution-only and does not affect running a dev-signed build on the owner's own Mac. Revisit before distributing to other machines. | 2026-08-31T00:10:35.783Z | 2026-08-31T05:45:26.950Z |
| 3 | 03 | unrun-verify | playstead-mac/Playstead/Adapter/AdapterHost.swift |  | Task 3 human-check (notarized app, network disabled, Play launches mGBA, quit returns to library) unverified in this session — no installed emulator/downloaded ROM/Developer ID cert available | open |  | 2026-08-31T00:10:40.298Z |  |
| 4 | 03 | deviation | playstead-mac/Playstead/Library/GameCardView.swift |  | DownloadCoordinator progress percent wired but not yet consumed by LibraryViewModel/GameCardView's live rendering path (03-07) | open |  | 2026-08-31T01:42:14.870Z |  |
| 5 | 03 | deviation | playstead-mac/Playstead/App/PlaysteadApp.swift |  | AppEnvironment does not yet construct DownloadQueue/DownloadCoordinator/QuotaManager/PinStore/EvictionPlanner as live app-wide singletons (03-07) | fixed |  | 2026-08-31T01:42:20.733Z | 2026-08-31T12:46:28.600Z |
| 6 | 03 | unrun-verify | playstead-mac/Playstead/Library/StorageView.swift |  | Visual/interactive click-through of DownloadsView/QuotaSettingsView/ReclaimPromptView/StorageView against a live paired server unverified in this headless session (03-07 coverage D6) | open |  | 2026-08-31T01:42:25.363Z |  |
| 7 | 03 | stub | playstead-mac/Playstead/Adapter/BiosStore.swift |  | BiosStore's known-reference digest set has no production default (DI-only, no fabricated evidence); real reference digest wiring is deferred until sourced | open |  | 2026-08-31T02:43:54.600Z |  |
| 8 | 03 | deviation | playstead-mac/Playstead/Adapter/AdapterHost.swift |  | Gatekeeper-held child hangs silently: AdapterHost.launch treats a successful Process.run() as launched, but a quarantined bundle is left suspended at _dyld_start and terminationHandler never fires — the app believes the emulator runs forever with no error surfaced. AdapterInstaller preserves quarantine per D-05. Proven experimentally (signed+quarantined HUNG; signed alone exits 0.15s). A properly notarized mGBA should pass assessment so the happy path is likely fine, but the failure shape is silent and unbounded. Fix requires a design decision: a liveness probe cannot distinguish held from idle (held task reports S not T; Mach suspend count needs task-port access the app lacks), and pre-flighting SecStaticCodeCheckValidity at install would reject the /bin/echo stand-ins both test suites depend on, so a fixture strategy must be decided alongside it. | open |  | 2026-08-31T10:48:44.083Z |  |
| 9 | 03.5 | unrun-verify | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Task 1 exact UI-layer drag verification requires the centrally orchestrated hosted macOS runner; local app launch is prohibited by the no-password safety boundary. | fixed |  | 2026-09-01T06:29:58.866Z | 2026-09-01T18:29:36.711Z |
| 10 | 03.5 | unrun-verify | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Task 2 full CurationInteractionTests UI-layer verification requires the centrally orchestrated hosted macOS runner; local app launch is prohibited by the no-password safety boundary. | fixed |  | 2026-09-01T06:29:58.948Z | 2026-09-01T18:29:41.733Z |
| 11 | 03.5 | deviation | playstead-mac/Playstead/Library/ShelfView.swift |  | Plan path corrected from nonexistent Curation/ShelfView.swift to the production Library/ShelfView.swift location. | open |  | 2026-09-01T06:29:59.030Z |  |
| 12 | 03.5 | deviation | playstead-mac/Playstead/UITesting/DeterministicProfile.swift |  | Added compile-gated UUID-only persisted profile support required to prove process-relaunch durability without touching Plan 07 storage production files. | open |  | 2026-09-01T06:29:59.112Z |  |
| 13 | 03.5 | deviation | playstead-mac/scripts/ci/run-mac-verification.sh |  | Hosted run 33478091423 exposed an EXIT trap that referenced function-local keyboard state after scope unwind and masked the underlying early build result; fixed in a4ef343 with globally initialized guarded cleanup and pre-capture failure regression. | open |  | 2026-09-01T06:44:32.931Z |  |
| 14 | 03.5 | deviation | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Split broad hosted curation UI identity into three exact stages and changed drag to the deterministic last-row-to-first boundary after run 33481640835. | open |  | 2026-09-01T07:44:47.355Z |  |
| 15 | 03.5 | deviation | playstead-mac/Playstead/UITesting/UITestBootstrap.swift |  | Hosted run 33483731474 exposed redundant fresh-position validation on persisted reorder relaunch plus stale shelf selectors; fixed and split into nine exact curation stages. | open |  | 2026-09-01T08:14:14.831Z |  |
| 16 | 03.5 | deviation | playstead-mac/Playstead/Curation/CollectionsView.swift |  | Hosted run 33486052488 exposed Favorites collapsed-node and Collections child-text routing mismatches; fixed with exact card queries and a stable collection route button. | open |  | 2026-09-01T08:41:10.578Z |  |
| 17 | 03.5 | deviation | playstead-mac/Playstead/Library/GameCardView.swift |  | Hosted run 33488360822 exposed card identity before accessibility collapse and drag gestures on semantic content instead of List cells; fixed and split drag mutation from durability. | open |  | 2026-09-01T09:07:27.559Z |  |
| 18 | 03.5 | deviation | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Hosted run 33490616418 exposed only aggregate reorder outcomes; split route, cell ownership, drag mutation/durability, keyboard focus/effect/durability and full E2E, with a slow held drag. | open |  | 2026-09-01T09:33:08.765Z |  |
| 19 | 03.5 | deviation | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Hosted run 33495336534 proved routes and cells but no mutations: switched touch-style press-drag to macOS click-drag and removed duplicate Space after focusContainedAction. | open |  | 2026-09-01T10:33:18.230Z |  |
| 20 | 03.5 | deviation | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Hosted run 33498048537 proved focusContainedAction is focus-only; restored one Space, isolated Move Up availability/click, and held the macOS drag destination. | open |  | 2026-09-01T11:04:38.825Z |  |
| 21 | 03.5 | deviation | playstead-mac/Playstead/Curation/CollectionsViewModel.swift |  | Hosted run 33500660524 exposed an unobserved SQLite member query; refresh now publishes a member revision so optimistic reorder and bounded evidence invalidate. | open |  | 2026-09-01T11:39:10.783Z |  |
| 22 | 03.5 | deviation | playstead-mac/Playstead/Curation/CollectionDetailView.swift |  | Hosted run 33503640089 isolated keyboard focus ownership; collection and queue reorder actions now bind stable identity and focus on the final button through playsteadFocusable. | open |  | 2026-09-01T12:13:48.616Z |  |
| 23 | 03.5 | deviation | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Hosted run 33506605120 exposed app-scoped Space dispatch plus a missing combined-path activation; both keyboard paths now send one Space through the exact focused button. | open |  | 2026-09-01T12:48:01.842Z |  |
| 24 | 03.5 | deviation | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Hosted run 33510034845 exposed an impossible retained-focus assertion on a Move Up button disabled by reaching the first boundary; the keyboard proof now moves last-to-middle while preserving exact effect/order/boundary/durability checks. | open |  | 2026-09-01T13:28:24.085Z |  |
| 25 | 03.5 | deviation | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Hosted run 33513649409 lacked keyboard stage detail; curation now uses exact-target canary focus detection and bounded safe focus/effect/retention test IDs. | open |  | 2026-09-01T14:17:23.468Z |  |
| 26 | 03.5 | deviation | playstead-mac/scripts/ci/run-mac-verification.sh |  | Hosted run 33518726537 executed but did not report the three curation keyboard stage tests; all are now required evidence before any production command-model change. | open |  | 2026-09-01T14:56:43.305Z |  |
| 27 | 03.5 | deviation | playstead-mac/Playstead/Curation/CollectionDetailView.swift |  | Hosted run 33526574205 proved nested List row buttons are not ordinary Tab stops; keyboard reorder now uses exact List selection plus visible bounded commands through the existing settlement path. | open |  | 2026-09-01T16:09:38.131Z |  |
| 28 | 04 | deviation | playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex |  | Save-lane UploadSlots/RateLimiter (D-33) not yet wired into the save routes | open |  | 2026-09-04T03:18:16.081Z |  |
| 29 | 04 | stub | playstead-mac/Playstead/Sync/JournalApplier.swift |  | CacheObjectsSaveBytesPrefetcher.onPrefetchNeeded is a no-op; real byte transfer for D-43 prefetch deferred to a later downloads-lane plan | open |  | 2026-09-04T03:18:16.168Z |  |
| 30 | 04 | deviation | playstead-server/lib/playstead/export/export.ex |  | Real Playstead.Saves revision data is not yet loaded into Export.to_layout_input/1; SavesPlan/Sidecar/BagitWriter pipeline is built+tested against synthetic data only (04-08) | open |  | 2026-09-04T15:35:17.080Z |  |
| 31 | 04 | deviation | playstead-server/lib/playstead_web/live/exports_live.ex |  | No console UI control yet sets ExportRecord.saves_scope (defaults to all); field is persisted and fully threaded through Worker (04-08) | fixed |  | 2026-09-04T15:35:17.159Z | 2026-09-04T19:49:47.031Z |
| 32 | 04 | deviation | playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift |  | Comparison sheet is built and tested standalone but not yet wired into a live attention-inbox or game-detail navigation path on the Mac (server console entry point already shipped in 04-10); presentation wiring is left for a later plan | open |  | 2026-09-04T20:20:49.523Z |  |
| 33 | 04 | deviation | playstead-mac/Playstead/Sync/JournalApplier.swift |  | Divergence detection does not yet trigger an eager 32KB prefetch of both sides' artifacts (CacheObjectsSaveBytesPrefetcher.onPrefetchNeeded is still the no-op tracked by WINDOWS #29); comparing/choosing works offline only once both blobs are already locally cached by some other path | open |  | 2026-09-04T20:20:49.612Z |  |
| 34 | 04 | unrun-verify | playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift |  | UI-layer keyboard-interaction verification requires the centrally orchestrated hosted macOS runner; local execution is disabled by the project's login-Keychain launch guard (mirrors WINDOWS #9/#10 precedent) | open |  | 2026-09-04T20:20:49.696Z |  |
| 35 | 04 | deviation | playstead-mac/Playstead/Saves/OnlyCopyInterruptiveSheet.swift |  | Unpair, sign out, and delete game have no production entry point yet in this codebase; only remove-local-copy (ReclaimPromptView) and eviction (StorageView) are wired to the interruptive gate. The sheet and gate are built, tested, and reusable for whichever future plan adds those three call sites. | open |  | 2026-09-05T01:12:59.522Z |  |
| 36 | 04 | unrun-verify | playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift |  | UI-layer keyboard-interaction verification requires the centrally orchestrated hosted macOS runner; local execution is disabled by the project's login-Keychain launch guard (mirrors WINDOWS #9/#10/#34 precedent). | open |  | 2026-09-05T01:12:59.615Z |  |
| 37 | 04 | deviation | playstead-mac/Playstead/Library/GameRowView.swift |  | LaunchSavePlanner/SavePlanExecutor are still not wired into GameRowView.play() -- AdapterHost.launch's executeSavePlan closure exists (04-07) but no call site passes one; 04-07-SUMMARY.md named plan 04-13 as the downstream consumer, but 04-13's declared task scope (files_modified) is limited to the two new proof tests, the two xctestplans, and run-mac-verification.sh, so this wiring remains open | fixed |  | 2026-09-05T01:50:48.874Z | 2026-09-05T02:27:54.263Z |
| 38 | 04 | stub | playstead-mac/Playstead/Saves/LaunchSaveEnvironment.swift |  | captureExistingFile commits pre-existing save bytes into the CAS for durability but does not create a SaveStore revision row, so a pre-restore capture on the launch path is not yet visible in SaveHistorySheet (04-14) | open |  | 2026-09-05T02:28:02.845Z |  |
| 39 | 04 | stub | playstead-mac/Playstead/Library/GameRowView.swift |  | SaveLaunchNotice from the launch-path save plan is held on GameRowView's saveLaunchNotice @State but not yet rendered -- no detail view with a Save section exists yet in this codebase to surface it inline into (04-14) | open |  | 2026-09-05T02:28:02.935Z |  |
| 40 | 04 | deviation | playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift |  | OnlyCopyEscalationPanel now has a real call site (ReadinessSheetView) gated by a real only-copy count, but the four unfixable escalation reasons (revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection) still can't fire in production because SaveUploadLane has no wired failure-classification output yet (mac2 review WR-04) (04-16) | open |  | 2026-09-05T14:17:19.948Z |  |
| 41 | 04 | deviation | playstead-mac/Playstead/Readiness/ReadinessEngine.swift |  | AppEnvironment.saveReadinessCase(for:) does not compute .serverHasNewer -- distinguishing it from .localOnlyReachable needs per-device session context this client doesn't track yet; every other SaveReadinessCase, including the higher-priority .twoVersions, is computed (04-16) | open |  | 2026-09-05T14:17:20.065Z |  |
| 42 | 04 | deviation | playstead-mac/Playstead/Sync/Outbox.swift |  | AppEnvironment now constructs a shared SaveOutbox/SaveConflictResolver so MC-06's resolution path durably records locally, but no drain trigger (OutboxDrainTrigger-equivalent) is wired for SaveOutbox yet -- a resolved fork is recorded locally but may not reach the server promptly (mac2 review WR-04's other half) (04-16) | open |  | 2026-09-05T14:17:20.181Z |  |
| 43 | 04 | deviation | playstead-mac/Playstead/Readiness/ReadinessSheetView.swift |  | saveHistorySessions closure passed to ReadinessSheetView is still never populated from SaveStore (mac2 review CR-04's other half) -- SaveHistorySheet's 'Review versions...' path for a non-diverged line still renders its empty state; out of 04-16's declared MC-01..MC-06 scope | open |  | 2026-09-05T14:17:20.303Z |  |

````json
[
  {
    "id": 1,
    "kind": "stub",
    "phase": "03",
    "file": "playstead-mac/Playstead/Adapter/AdapterHost.swift",
    "line": null,
    "description": "verifyInstalledDigest() expects an .install-verify.json sidecar that no plan yet writes (emulator installer is 03-08/03-09 territory)",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-08-31T00:10:31.234Z",
    "resolved_at": "2026-08-31T02:44:11.180Z"
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "03",
    "file": "playstead-mac/scripts/sign-and-notarize.sh",
    "line": null,
    "description": "Notarization + Developer-ID release build could not run (no Developer ID Application cert / paid Apple Developer Program in this environment); notarization deferred per 03-01 owner decision",
    "status": "waived",
    "reason": "Deferred by owner 2026-08-31: local development only; no Developer ID / paid Apple Developer Program enrollment this milestone. Notarization is distribution-only and does not affect running a dev-signed build on the owner's own Mac. Revisit before distributing to other machines.",
    "recorded_at": "2026-08-31T00:10:35.783Z",
    "resolved_at": "2026-08-31T05:45:26.950Z"
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "03",
    "file": "playstead-mac/Playstead/Adapter/AdapterHost.swift",
    "line": null,
    "description": "Task 3 human-check (notarized app, network disabled, Play launches mGBA, quit returns to library) unverified in this session — no installed emulator/downloaded ROM/Developer ID cert available",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T00:10:40.298Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "03",
    "file": "playstead-mac/Playstead/Library/GameCardView.swift",
    "line": null,
    "description": "DownloadCoordinator progress percent wired but not yet consumed by LibraryViewModel/GameCardView's live rendering path (03-07)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:42:14.870Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "deviation",
    "phase": "03",
    "file": "playstead-mac/Playstead/App/PlaysteadApp.swift",
    "line": null,
    "description": "AppEnvironment does not yet construct DownloadQueue/DownloadCoordinator/QuotaManager/PinStore/EvictionPlanner as live app-wide singletons (03-07)",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-08-31T01:42:20.733Z",
    "resolved_at": "2026-08-31T12:46:28.600Z"
  },
  {
    "id": 6,
    "kind": "unrun-verify",
    "phase": "03",
    "file": "playstead-mac/Playstead/Library/StorageView.swift",
    "line": null,
    "description": "Visual/interactive click-through of DownloadsView/QuotaSettingsView/ReclaimPromptView/StorageView against a live paired server unverified in this headless session (03-07 coverage D6)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:42:25.363Z",
    "resolved_at": null
  },
  {
    "id": 7,
    "kind": "stub",
    "phase": "03",
    "file": "playstead-mac/Playstead/Adapter/BiosStore.swift",
    "line": null,
    "description": "BiosStore's known-reference digest set has no production default (DI-only, no fabricated evidence); real reference digest wiring is deferred until sourced",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:43:54.600Z",
    "resolved_at": null
  },
  {
    "id": 8,
    "kind": "deviation",
    "phase": "03",
    "file": "playstead-mac/Playstead/Adapter/AdapterHost.swift",
    "line": null,
    "description": "Gatekeeper-held child hangs silently: AdapterHost.launch treats a successful Process.run() as launched, but a quarantined bundle is left suspended at _dyld_start and terminationHandler never fires — the app believes the emulator runs forever with no error surfaced. AdapterInstaller preserves quarantine per D-05. Proven experimentally (signed+quarantined HUNG; signed alone exits 0.15s). A properly notarized mGBA should pass assessment so the happy path is likely fine, but the failure shape is silent and unbounded. Fix requires a design decision: a liveness probe cannot distinguish held from idle (held task reports S not T; Mach suspend count needs task-port access the app lacks), and pre-flighting SecStaticCodeCheckValidity at install would reject the /bin/echo stand-ins both test suites depend on, so a fixture strategy must be decided alongside it.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T10:48:44.083Z",
    "resolved_at": null
  },
  {
    "id": 9,
    "kind": "unrun-verify",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Task 1 exact UI-layer drag verification requires the centrally orchestrated hosted macOS runner; local app launch is prohibited by the no-password safety boundary.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-01T06:29:58.866Z",
    "resolved_at": "2026-09-01T18:29:36.711Z"
  },
  {
    "id": 10,
    "kind": "unrun-verify",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Task 2 full CurationInteractionTests UI-layer verification requires the centrally orchestrated hosted macOS runner; local app launch is prohibited by the no-password safety boundary.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-01T06:29:58.948Z",
    "resolved_at": "2026-09-01T18:29:41.733Z"
  },
  {
    "id": 11,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/Library/ShelfView.swift",
    "line": null,
    "description": "Plan path corrected from nonexistent Curation/ShelfView.swift to the production Library/ShelfView.swift location.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:29:59.030Z",
    "resolved_at": null
  },
  {
    "id": 12,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/UITesting/DeterministicProfile.swift",
    "line": null,
    "description": "Added compile-gated UUID-only persisted profile support required to prove process-relaunch durability without touching Plan 07 storage production files.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:29:59.112Z",
    "resolved_at": null
  },
  {
    "id": 13,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/scripts/ci/run-mac-verification.sh",
    "line": null,
    "description": "Hosted run 33478091423 exposed an EXIT trap that referenced function-local keyboard state after scope unwind and masked the underlying early build result; fixed in a4ef343 with globally initialized guarded cleanup and pre-capture failure regression.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:44:32.931Z",
    "resolved_at": null
  },
  {
    "id": 14,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Split broad hosted curation UI identity into three exact stages and changed drag to the deterministic last-row-to-first boundary after run 33481640835.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T07:44:47.355Z",
    "resolved_at": null
  },
  {
    "id": 15,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/UITesting/UITestBootstrap.swift",
    "line": null,
    "description": "Hosted run 33483731474 exposed redundant fresh-position validation on persisted reorder relaunch plus stale shelf selectors; fixed and split into nine exact curation stages.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T08:14:14.831Z",
    "resolved_at": null
  },
  {
    "id": 16,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/Curation/CollectionsView.swift",
    "line": null,
    "description": "Hosted run 33486052488 exposed Favorites collapsed-node and Collections child-text routing mismatches; fixed with exact card queries and a stable collection route button.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T08:41:10.578Z",
    "resolved_at": null
  },
  {
    "id": 17,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/Library/GameCardView.swift",
    "line": null,
    "description": "Hosted run 33488360822 exposed card identity before accessibility collapse and drag gestures on semantic content instead of List cells; fixed and split drag mutation from durability.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T09:07:27.559Z",
    "resolved_at": null
  },
  {
    "id": 18,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Hosted run 33490616418 exposed only aggregate reorder outcomes; split route, cell ownership, drag mutation/durability, keyboard focus/effect/durability and full E2E, with a slow held drag.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T09:33:08.765Z",
    "resolved_at": null
  },
  {
    "id": 19,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Hosted run 33495336534 proved routes and cells but no mutations: switched touch-style press-drag to macOS click-drag and removed duplicate Space after focusContainedAction.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T10:33:18.230Z",
    "resolved_at": null
  },
  {
    "id": 20,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Hosted run 33498048537 proved focusContainedAction is focus-only; restored one Space, isolated Move Up availability/click, and held the macOS drag destination.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T11:04:38.825Z",
    "resolved_at": null
  },
  {
    "id": 21,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/Curation/CollectionsViewModel.swift",
    "line": null,
    "description": "Hosted run 33500660524 exposed an unobserved SQLite member query; refresh now publishes a member revision so optimistic reorder and bounded evidence invalidate.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T11:39:10.783Z",
    "resolved_at": null
  },
  {
    "id": 22,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/Curation/CollectionDetailView.swift",
    "line": null,
    "description": "Hosted run 33503640089 isolated keyboard focus ownership; collection and queue reorder actions now bind stable identity and focus on the final button through playsteadFocusable.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T12:13:48.616Z",
    "resolved_at": null
  },
  {
    "id": 23,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Hosted run 33506605120 exposed app-scoped Space dispatch plus a missing combined-path activation; both keyboard paths now send one Space through the exact focused button.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T12:48:01.842Z",
    "resolved_at": null
  },
  {
    "id": 24,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Hosted run 33510034845 exposed an impossible retained-focus assertion on a Move Up button disabled by reaching the first boundary; the keyboard proof now moves last-to-middle while preserving exact effect/order/boundary/durability checks.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T13:28:24.085Z",
    "resolved_at": null
  },
  {
    "id": 25,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Hosted run 33513649409 lacked keyboard stage detail; curation now uses exact-target canary focus detection and bounded safe focus/effect/retention test IDs.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T14:17:23.468Z",
    "resolved_at": null
  },
  {
    "id": 26,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/scripts/ci/run-mac-verification.sh",
    "line": null,
    "description": "Hosted run 33518726537 executed but did not report the three curation keyboard stage tests; all are now required evidence before any production command-model change.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T14:56:43.305Z",
    "resolved_at": null
  },
  {
    "id": 27,
    "kind": "deviation",
    "phase": "03.5",
    "file": "playstead-mac/Playstead/Curation/CollectionDetailView.swift",
    "line": null,
    "description": "Hosted run 33526574205 proved nested List row buttons are not ordinary Tab stops; keyboard reorder now uses exact List selection plus visible bounded commands through the existing settlement path.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T16:09:38.131Z",
    "resolved_at": null
  },
  {
    "id": 28,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex",
    "line": null,
    "description": "Save-lane UploadSlots/RateLimiter (D-33) not yet wired into the save routes",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T03:18:16.081Z",
    "resolved_at": null
  },
  {
    "id": 29,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Sync/JournalApplier.swift",
    "line": null,
    "description": "CacheObjectsSaveBytesPrefetcher.onPrefetchNeeded is a no-op; real byte transfer for D-43 prefetch deferred to a later downloads-lane plan",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T03:18:16.168Z",
    "resolved_at": null
  },
  {
    "id": 30,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-server/lib/playstead/export/export.ex",
    "line": null,
    "description": "Real Playstead.Saves revision data is not yet loaded into Export.to_layout_input/1; SavesPlan/Sidecar/BagitWriter pipeline is built+tested against synthetic data only (04-08)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T15:35:17.080Z",
    "resolved_at": null
  },
  {
    "id": 31,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-server/lib/playstead_web/live/exports_live.ex",
    "line": null,
    "description": "No console UI control yet sets ExportRecord.saves_scope (defaults to all); field is persisted and fully threaded through Worker (04-08)",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-04T15:35:17.159Z",
    "resolved_at": "2026-09-04T19:49:47.031Z"
  },
  {
    "id": 32,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift",
    "line": null,
    "description": "Comparison sheet is built and tested standalone but not yet wired into a live attention-inbox or game-detail navigation path on the Mac (server console entry point already shipped in 04-10); presentation wiring is left for a later plan",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T20:20:49.523Z",
    "resolved_at": null
  },
  {
    "id": 33,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Sync/JournalApplier.swift",
    "line": null,
    "description": "Divergence detection does not yet trigger an eager 32KB prefetch of both sides' artifacts (CacheObjectsSaveBytesPrefetcher.onPrefetchNeeded is still the no-op tracked by WINDOWS #29); comparing/choosing works offline only once both blobs are already locally cached by some other path",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T20:20:49.612Z",
    "resolved_at": null
  },
  {
    "id": 34,
    "kind": "unrun-verify",
    "phase": "04",
    "file": "playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift",
    "line": null,
    "description": "UI-layer keyboard-interaction verification requires the centrally orchestrated hosted macOS runner; local execution is disabled by the project's login-Keychain launch guard (mirrors WINDOWS #9/#10 precedent)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T20:20:49.696Z",
    "resolved_at": null
  },
  {
    "id": 35,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/OnlyCopyInterruptiveSheet.swift",
    "line": null,
    "description": "Unpair, sign out, and delete game have no production entry point yet in this codebase; only remove-local-copy (ReclaimPromptView) and eviction (StorageView) are wired to the interruptive gate. The sheet and gate are built, tested, and reusable for whichever future plan adds those three call sites.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T01:12:59.522Z",
    "resolved_at": null
  },
  {
    "id": 36,
    "kind": "unrun-verify",
    "phase": "04",
    "file": "playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift",
    "line": null,
    "description": "UI-layer keyboard-interaction verification requires the centrally orchestrated hosted macOS runner; local execution is disabled by the project's login-Keychain launch guard (mirrors WINDOWS #9/#10/#34 precedent).",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T01:12:59.615Z",
    "resolved_at": null
  },
  {
    "id": 37,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Library/GameRowView.swift",
    "line": null,
    "description": "LaunchSavePlanner/SavePlanExecutor are still not wired into GameRowView.play() -- AdapterHost.launch's executeSavePlan closure exists (04-07) but no call site passes one; 04-07-SUMMARY.md named plan 04-13 as the downstream consumer, but 04-13's declared task scope (files_modified) is limited to the two new proof tests, the two xctestplans, and run-mac-verification.sh, so this wiring remains open",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T01:50:48.874Z",
    "resolved_at": "2026-09-05T02:27:54.263Z"
  },
  {
    "id": 38,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/LaunchSaveEnvironment.swift",
    "line": null,
    "description": "captureExistingFile commits pre-existing save bytes into the CAS for durability but does not create a SaveStore revision row, so a pre-restore capture on the launch path is not yet visible in SaveHistorySheet (04-14)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T02:28:02.845Z",
    "resolved_at": null
  },
  {
    "id": 39,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Library/GameRowView.swift",
    "line": null,
    "description": "SaveLaunchNotice from the launch-path save plan is held on GameRowView's saveLaunchNotice @State but not yet rendered -- no detail view with a Save section exists yet in this codebase to surface it inline into (04-14)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T02:28:02.935Z",
    "resolved_at": null
  },
  {
    "id": 40,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift",
    "line": null,
    "description": "OnlyCopyEscalationPanel now has a real call site (ReadinessSheetView) gated by a real only-copy count, but the four unfixable escalation reasons (revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection) still can't fire in production because SaveUploadLane has no wired failure-classification output yet (mac2 review WR-04) (04-16)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T14:17:19.948Z",
    "resolved_at": null
  },
  {
    "id": 41,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Readiness/ReadinessEngine.swift",
    "line": null,
    "description": "AppEnvironment.saveReadinessCase(for:) does not compute .serverHasNewer -- distinguishing it from .localOnlyReachable needs per-device session context this client doesn't track yet; every other SaveReadinessCase, including the higher-priority .twoVersions, is computed (04-16)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T14:17:20.065Z",
    "resolved_at": null
  },
  {
    "id": 42,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Sync/Outbox.swift",
    "line": null,
    "description": "AppEnvironment now constructs a shared SaveOutbox/SaveConflictResolver so MC-06's resolution path durably records locally, but no drain trigger (OutboxDrainTrigger-equivalent) is wired for SaveOutbox yet -- a resolved fork is recorded locally but may not reach the server promptly (mac2 review WR-04's other half) (04-16)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T14:17:20.181Z",
    "resolved_at": null
  },
  {
    "id": 43,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Readiness/ReadinessSheetView.swift",
    "line": null,
    "description": "saveHistorySessions closure passed to ReadinessSheetView is still never populated from SaveStore (mac2 review CR-04's other half) -- SaveHistorySheet's 'Review versions...' path for a non-diverged line still renders its empty state; out of 04-16's declared MC-01..MC-06 scope",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T14:17:20.303Z",
    "resolved_at": null
  }
]
````
