---
schema_version: 1
open_count: 46
waived_count: 1
fixed_count: 22
total_count: 69
last_updated: 2026-09-11T23:23:31.870Z
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
| 30 | 04 | deviation | playstead-server/lib/playstead/export/export.ex |  | Real Playstead.Saves revision data is not yet loaded into Export.to_layout_input/1; SavesPlan/Sidecar/BagitWriter pipeline is built+tested against synthetic data only (04-08) FIXED by plan 04-21 (22d92f7/433f7e4/8e32347): Export.load_save_revisions/2 loads real save revisions at the Export context boundary; the real file is playstead-server/lib/playstead/export.ex, not export/export.ex. | fixed |  | 2026-09-04T15:35:17.080Z | 2026-09-06T02:02:52.856Z |
| 31 | 04 | deviation | playstead-server/lib/playstead_web/live/exports_live.ex |  | No console UI control yet sets ExportRecord.saves_scope (defaults to all); field is persisted and fully threaded through Worker (04-08) | fixed |  | 2026-09-04T15:35:17.159Z | 2026-09-04T19:49:47.031Z |
| 32 | 04 | deviation | playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift |  | Comparison sheet is built and tested standalone but not yet wired into a live attention-inbox or game-detail navigation path on the Mac (server console entry point already shipped in 04-10); presentation wiring is left for a later plan STALE, not fixed by 04-23: ConflictComparisonSheet was wired into ReadinessSheetView by plan 04-16 / commit c223218, which postdates this entry; 04-VERIFICATION.md confirmed the wiring directly in source. Closed with c223218 as the resolving commit. | fixed |  | 2026-09-04T20:20:49.523Z | 2026-09-06T02:02:53.323Z |
| 33 | 04 | deviation | playstead-mac/Playstead/Sync/JournalApplier.swift |  | Divergence detection does not yet trigger an eager 32KB prefetch of both sides' artifacts (CacheObjectsSaveBytesPrefetcher.onPrefetchNeeded is still the no-op tracked by WINDOWS #29); comparing/choosing works offline only once both blobs are already locally cached by some other path | open |  | 2026-09-04T20:20:49.612Z |  |
| 34 | 04 | unrun-verify | playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift |  | UI-layer keyboard-interaction verification requires the centrally orchestrated hosted macOS runner; local execution is disabled by the project's login-Keychain launch guard (mirrors WINDOWS #9/#10 precedent) | open |  | 2026-09-04T20:20:49.696Z |  |
| 35 | 04 | deviation | playstead-mac/Playstead/Saves/OnlyCopyInterruptiveSheet.swift |  | Unpair, sign out, and delete game have no production entry point yet in this codebase; only remove-local-copy (ReclaimPromptView) and eviction (StorageView) are wired to the interruptive gate. The sheet and gate are built, tested, and reusable for whichever future plan adds those three call sites. | open |  | 2026-09-05T01:12:59.522Z |  |
| 36 | 04 | unrun-verify | playstead-mac/PlaysteadUITests/OnlyCopyInterruptionTests.swift |  | UI-layer keyboard-interaction verification requires the centrally orchestrated hosted macOS runner; local execution is disabled by the project's login-Keychain launch guard (mirrors WINDOWS #9/#10/#34 precedent). | open |  | 2026-09-05T01:12:59.615Z |  |
| 37 | 04 | deviation | playstead-mac/Playstead/Library/GameRowView.swift |  | LaunchSavePlanner/SavePlanExecutor are still not wired into GameRowView.play() -- AdapterHost.launch's executeSavePlan closure exists (04-07) but no call site passes one; 04-07-SUMMARY.md named plan 04-13 as the downstream consumer, but 04-13's declared task scope (files_modified) is limited to the two new proof tests, the two xctestplans, and run-mac-verification.sh, so this wiring remains open | fixed |  | 2026-09-05T01:50:48.874Z | 2026-09-05T02:27:54.263Z |
| 38 | 04 | stub | playstead-mac/Playstead/Saves/LaunchSaveEnvironment.swift |  | captureExistingFile commits pre-existing save bytes into the CAS for durability but does not create a SaveStore revision row, so a pre-restore capture on the launch path is not yet visible in SaveHistorySheet (04-14) | open |  | 2026-09-05T02:28:02.845Z |  |
| 39 | 04 | stub | playstead-mac/Playstead/Library/GameRowView.swift |  | SaveLaunchNotice from the launch-path save plan is held on GameRowView's saveLaunchNotice @State but not yet rendered -- no detail view with a Save section exists yet in this codebase to surface it inline into (04-14) | open |  | 2026-09-05T02:28:02.935Z |  |
| 40 | 04 | deviation | playstead-mac/Playstead/Saves/OnlyCopyEscalation.swift |  | OnlyCopyEscalationPanel now has a real call site (ReadinessSheetView) gated by a real only-copy count, but the four unfixable escalation reasons (revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection) still can't fire in production because SaveUploadLane has no wired failure-classification output yet (mac2 review WR-04) (04-16) FIXED by plan 04-19 (fb6ad53). | fixed |  | 2026-09-05T14:17:19.948Z | 2026-09-05T22:18:48.497Z |
| 41 | 04 | deviation | playstead-mac/Playstead/Readiness/ReadinessEngine.swift |  | AppEnvironment.saveReadinessCase(for:) does not compute .serverHasNewer -- distinguishing it from .localOnlyReachable needs per-device session context this client doesn't track yet; every other SaveReadinessCase, including the higher-priority .twoVersions, is computed (04-16) | open |  | 2026-09-05T14:17:20.065Z |  |
| 42 | 04 | deviation | playstead-mac/Playstead/Sync/Outbox.swift |  | AppEnvironment now constructs a shared SaveOutbox/SaveConflictResolver so MC-06's resolution path durably records locally, but no drain trigger (OutboxDrainTrigger-equivalent) is wired for SaveOutbox yet -- a resolved fork is recorded locally but may not reach the server promptly (mac2 review WR-04's other half) (04-16) FIXED by plan 04-23 (5c6439c): SaveOutboxDrainTrigger wired to post-enqueue, reachability-regained, and scene-active triggers. | fixed |  | 2026-09-05T14:17:20.181Z | 2026-09-06T02:02:52.938Z |
| 43 | 04 | deviation | playstead-mac/Playstead/Readiness/ReadinessSheetView.swift |  | saveHistorySessions closure passed to ReadinessSheetView is still never populated from SaveStore (mac2 review CR-04's other half) -- SaveHistorySheet's 'Review versions...' path for a non-diverged line still renders its empty state; out of 04-16's declared MC-01..MC-06 scope FIXED by plan 04-22 (62e0db0): SaveHistorySessionBuilder wired to real SaveStore data at both ReadinessSheetView call sites. | fixed |  | 2026-09-05T14:17:20.303Z | 2026-09-06T02:02:53.019Z |
| 44 | 04 | unmet-truth | playstead-mac/Playstead/Saves/SaveUploadLane.swift |  | SaveUploadLane (the dedicated actor draining locally-captured save revisions to the server, D-16/D-32) is never constructed anywhere in production -- discovered baselining 04-18's reachability sweep. A more severe superset of the already-tracked WINDOWS #40 (which only covered its missing failure-classification output): the WHOLE upload path is unwired, not just one output of it. See 04-18-SUMMARY.md. FIXED by plan 04-19 (fb6ad53). | fixed |  | 2026-09-05T21:54:18.525Z | 2026-09-05T22:18:48.578Z |
| 45 | 04 | unmet-truth | playstead-mac/Playstead/Saves/SaveCapturePoller.swift |  | SaveCapturePoller is constructed in production ONLY inside SaveSessionRecovery.replay, which itself has no production caller -- there is no live, in-play save-capture trigger anywhere in the shipped app. Discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md. FIXED by plan 04-19 (3691ec3). | fixed |  | 2026-09-05T21:54:18.602Z | 2026-09-05T22:18:48.656Z |
| 46 | 04 | unmet-truth | playstead-mac/Playstead/Saves/SaveSessionRecovery.swift |  | SaveSessionRecovery (crash-recovery replay actor, D-05/D-07) is never constructed in production despite its own doc comment saying app launch should call it once per known save line. Discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md. FIXED by plan 04-19 (3691ec3). | fixed |  | 2026-09-05T21:54:18.681Z | 2026-09-05T22:18:48.732Z |
| 47 | 04 | unmet-truth | playstead-mac/Playstead/Saves/SaveRollup.swift |  | SaveRollup.rollup(for:) (D-36's game-level save rollup string) has zero production callers -- not reachable from any shipped UI. Discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md. FIXED by plan 04-22 (24d5c34): AppEnvironment.saveRollupSummary(forAssetSetID:) is SaveRollup.rollup(for:)'s first production caller; reachability-allowlist.txt's SaveRollup line removed. | fixed |  | 2026-09-05T21:54:18.760Z | 2026-09-06T02:02:53.099Z |
| 48 | 04 | unmet-truth | playstead-mac/Playstead/Controller/ControllerRecoveryBanner.swift |  | ControllerRecoveryBanner and ControllerTestView (Controller/) and FirstRunBanner and ShowAllSystemsControl (Library/) are fully built views with zero production call sites -- discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md and scripts/ci/reachability-allowlist.txt for the full list and per-symbol detail. | open |  | 2026-09-05T21:54:18.835Z |  |
| 49 | 04 | stub | playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift |  | A promoted capture's bytes are written to the save-captures directory and recorded as a SaveStore revision, but are NOT committed into the CAS. LaunchSaveContextBuilder derives head candidates' bytesLocal from casManager.contains(blobSHA256), so a locally-captured revision reads as bytes-not-local at the next launch and cannot be restored from history until it has round-tripped through the server. Same-device continuity still works (the live .sav artifact persists), so this is the mirror image of WINDOWS #38 rather than a break in SAVE-01's main path. Out of 04-19's declared scope (capture -> SaveStore -> upload). FIXED by plan 04-20 (10783c4 excludes save blobs from the reclaim menu; de3aec1 commits capture bytes into the CAS). | fixed |  | 2026-09-05T22:19:41.797Z | 2026-09-05T23:05:00.000Z |
| 50 | 04 | stub | playstead-mac/Playstead/Saves/SaveCaptureBlockedState.swift |  | AppEnvironment constructs SaveCaptureBlockedState with no SaveCaptureAlertSink and no SaveDirectUploadTransport, so a blocked capture (D-31) is recorded durably and is queryable, but raises no user-visible alert and has no direct-upload escape hatch in the shipped app. The seams exist and are injected; no attention surface consumes them yet. | open |  | 2026-09-05T22:19:41.878Z |  |
| 51 | 04 | deviation | playstead-mac/Playstead/Saves/SaveCapturePoller.swift |  | The save-captures directory (<root>/save-captures/<assetSetID>/) has no reclamation path: each session leaves one session-<id>.staged.sav plus one <digest>.sav promoted blob, and QuotaManager measures paths.objects only, so capture blobs count against neither the quota nor the free-space floor and are never evicted. Save artifacts are small (tens of KB), so this is slow growth rather than an immediate hazard, but nothing bounds it. | open |  | 2026-09-05T22:19:41.957Z |  |
| 52 | 04 | stub | playstead-mac/Playstead/Saves/SaveSessionRecovery.swift |  | SaveSessionRecovery.replay (D-07 crash-recovery, reachable in production via AppEnvironment.recoverAbandonedSaveSessionsAtLaunch) records a promoted revision but holds no CASManager, so a crash-recovered capture's bytes never enter the CAS and LaunchSaveContextBuilder reports bytesLocal: false for it -- the same hole 04-20 closed on the live-session path (WINDOWS #49), reached via the second capture path. Out of 04-20's declared scope (files_modified named SaveSessionCoordinator only). Fix should extract 04-20's SaveSessionCoordinator.commitCaptureBytes into one shared spelling rather than a second copy. FIXED by plan 04-23 (fd4e2b4): extracted SaveCaptureBytesCommitter, shared by SaveSessionCoordinator and SaveSessionRecovery; recovery replay commits bytes into the CAS before inserting the row. | fixed |  | 2026-09-05T22:36:11.098Z | 2026-09-06T02:02:53.188Z |
| 53 | 04 | deviation | playstead-server/lib/playstead/export.ex |  | Export.load_save_revisions/2 selects only the (battery, slot 0) save line when a content_key has more than one save line; any other lines are silently excluded from export rather than merged (v1 client only ever writes one line, so this is currently unreachable). | open |  | 2026-09-06T01:18:12.481Z |  |
| 54 | 04 | stub | playstead-mac/Playstead/Net/APIClient.swift |  | The Mac client ships no pairing ceremony, so a human cannot pair a Mac at all. Every production PairingCredential construction is a keychain READ (KeychainStore.swift:152); the only writers are UI_TESTING-gated (UITestBootstrap.swift:552, DeterministicProfile.swift:49). There is no pairing view, no code-entry surface, no URL-scheme handler. The server side is complete -- POST /api/v1/device-pairing/requests, GET /requests/:id, POST /requests/:id/redeem, plus the devices approval console -- and the client calls none of it. APIClient.swift:57 states it outright ('this tracer plan does not yet ship the pairing ceremony') and anticipates a future plan writing AppPaths.root/pinned-ca.der; until then APIClient uses default TLS trust rather than the pinned root CA. LibraryShellView.swift:474's empty state instructs the user to 'Pair with your Playstead server to see your library', naming an action that exists nowhere in the app. 03.5-08 proved pairing only through scripts/ci/live-server.sh driving the HTTP ceremony from a shell script and handing a credential to a test build -- the human path was never built. Consequence: every human checkpoint requiring a paired Mac is unperformable, CP7-SAVE-C (UAT tests 107/112/120) included, which its 'blocked_by: physical-device' reason understates. Discovered 2026-09-08 when the owner tried to run CP7-SAVE-C and had no way to pair. Worked around for the owner's Mac only, by driving the production endpoints by hand and writing the server-issued credential into the login keychain (service dev.playstead.mac, device d23b584e); the missing UI itself is unfixed. | fixed |  | 2026-09-08T17:38:16.547Z | 2026-09-09T00:51:44.258Z |
| 55 | 04 | deviation | playstead-mac/Playstead/Saves/SaveUploadLane.swift |  | SHIPPED DEFECT: save uploads 404'd against every real server, so no captured revision has ever reached a server from the shipped app. APIClient.send does credential.baseURL.appendingPathComponent(path) and the paired credential's baseURL is the server ORIGIN, so callers own the whole path. SnapshotClient (/api/v1/snapshot) and ChangesClient (/api/v1/changes) spell it correctly; SaveUploadLane spelled 'saves/uploads/<id>' and 'saves/revisions' without the /api/v1 prefix, at both of its call sites. Server routes are PUT /api/v1/saves/uploads/:command_id and POST /api/v1/saves/revisions (router.ex:285,292). Observed on the owner's machine 2026-09-08: 'PUT /saves/uploads/... Sent 404' twice in the server log while POST /api/v1/play-sessions succeeded; two captured revisions sat at durability='queued' with 0 rows in the server's save_revisions. Capture, promotion and CAS commit all work -- only the upload half was broken. Fixed 2026-09-08 by prefixing both paths; guarded by scripts/ci/tests/api-path-prefix-test.sh, verified to reject the pre-fix source. WHY CI MISSED IT: SaveEndToEndTests guarded three fixture stages with bare 'guard try runFixture(...) else { return }', so a failing stage returned from the test having asserted nothing and XCTest recorded a pass -- the end-to-end proof of this exact path was fail-open. Seven such returns existed across SaveEndToEndTests and LiveServerSnapshotTests; all seven now XCTFail, and four-layer-topology-test.sh line 199 previously PINNED the fail-open shape as required. UAT tests 106 and 117 were marked pass on that evidence and are reverted to issue. | open |  | 2026-09-08T17:49:43.371Z |  |
| 56 | 04 | deviation | playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex |  | SHIPPED DEFECT (server): the streamed save-upload route replied on the ORIGINAL conn instead of the one advanced by reading the body. Plug.Conn is immutable and body_stream/1 threads its own conn through Stream.resource, so create_upload/2 responded 200 on a conn that still believed the request body was unread. The connection was then left mid-body, and the NEXT request on it stalled until Bandit's 15s read timeout, surfacing as 'Bandit.HTTPError Read timeout' on the upload's request_id and a 502 EOF at Caddy for the following request. Because SaveUploadLane does PUT bytes then immediately POST /api/v1/saves/revisions on the same connection, the metadata commit ALWAYS died: bytes landed in save_pending_uploads, no revision ever committed, and the client's revision stayed durability='queued' forever. Size-dependent, which is why it was never noticed: reproduced deterministically at 4096 bytes -> next request 0.004s, 65536 -> 15.010s, 131072 -> 15.010s. Fixed 2026-09-08 by capturing the drained conn from body_stream/1 and replying on it; re-verified 0.0017s at both previously-broken sizes. Not reachable by ConnTest (Phoenix.ConnTest never opens a real connection), which is why the 2 existing saves_controller tests pass either way; the live-server e2e test WOULD have caught it had it not been fail-open (WINDOWS #55). Full server suite green after the fix: 1037 tests, 0 failures. | open |  | 2026-09-08T18:22:12.727Z |  |
| 57 | 04 | stub | playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift |  | Capture provenance is never recorded: save_revision.adapter_id and adapter_version are empty on every revision produced by the real Play path, though both columns exist client-side and server-side and SaveUploadLane forwards them when present. Observed on the owner's machine 2026-09-08 across all three revisions captured through the shipped app (Advance Wars 65,536 bytes; Pokemon LeafGreen 131,072 x2) -- adapter_id '', adapter_version '', capture_method 'session'. Consequence: a stored revision cannot say which emulator or which pinned adapter version produced it, so a future adapter upgrade that changes save-format behaviour leaves no way to tell affected revisions from unaffected ones. CP7-SAVE-C's own how-to-verify asks the developer to record the adapter version alongside the observations, which the app itself cannot supply. Not blocking: capture, upload, restore and byte-identity are all proven correct without it. Low severity, but it is provenance for the one artifact class this phase exists to protect. | fixed |  | 2026-09-08T18:34:29.543Z | 2026-09-08T22:15:00.000Z |
| 61 | 04 | deviation | playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift |  | SaveEndToEndTests failed once on hosted run 34281587417 (result file never written within 60s) and passed on 34285679092 with no change to any code the test exercises. The failure is intermittent and its cause is still unknown. Recorded as OPEN rather than closed by the green run: a test that fails one run in N is not fixed by the run where it passes. WINDOWS #60's failure channel and the 120s deadline mean the next occurrence will name which of the four harness steps (quiesce, pairing, upload, sync) failed, and whether it was slow or broken. Do not close without that evidence. | open |  | 2026-09-08T23:50:00.000Z |  |
| 60 | 04 | deviation | playstead-mac/Playstead/UITesting/UITestBootstrap.swift |  | CI GAP (fixed same day, 4903ec8): the save end-to-end harness swallowed every failure, on the stated grounds that the absent result file was itself the signal. It is a signal with no content -- a slow run and a broken upload both surface as 'result was never written within 60s'. Hosted run 34281587417 failed exactly this way one run after the test was promoted to required, and the evidence named only the polling assertion's file:line. Fixed by writing a sanitized reason to a sibling file and giving each known cause its own assertion site, since CI's evidence pipeline keeps file:line and discards messages. Deadline raised 60s -> 120s only alongside the diagnostic. Root cause of the underlying timeout still unknown -- the next occurrence will name it. | fixed |  | 2026-09-08T22:40:00.000Z | 2026-09-08T22:40:00.000Z |
| 58 | 04 | deviation | playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift |  | CI GAP (fixed same day, cc7640d): the phase's only end-to-end save proof had never run on a hosted runner. SaveEndToEndTests resolved its fixture environment from ProcessInfo.processInfo.environment alone; the XCTest process inherits a PATH with no Elixir toolchain, so live-server.sh's 'mix playstead.mac_ci_fixture' died with 'mix: command not found' at provision-domain on every hosted run. The sibling LiveServerSnapshotTests already merged the runner-written live-server-runtime.json (which carries the real PATH) over the inherited environment and documented exactly this hazard; SaveEndToEndTests' doc comment claimed it reused that discipline 'verbatim' and did not. Invisible because the test was fail-open until e6316d5 and because live-server.sh discarded its own stderr until 266015e. Third seam-between-plans defect of this phase after #55 and #56. Guarded by scripts/ci/tests/live-server-env-resolution-test.sh, falsified against the real pre-fix source. | fixed |  | 2026-09-08T20:58:11.764Z | 2026-09-08T20:58:25.364Z |
| 59 | 04 | deviation | playstead-mac/scripts/ci/run-mac-verification.sh |  | CI GAP (fixed same day, 266015e): the hosted UI layer's 1800s deadline sat 9% above its own observed runtime (1631s in the last green run, 50960ba), and run 34264338508 was SIGTERMed at exactly 1800s on a commit whose diff touched no file in the UI test plan. Raised to 2700s with four-layer-topology-test.sh's pinned expectation and ceiling moved with it. Recorded because the failure mode is a gate that reports red for reasons unrelated to the code under test, which trains readers to discount it. | fixed |  | 2026-09-08T20:58:18.772Z | 2026-09-08T20:58:25.464Z |
| 62 | 04.5 | unrun-verify | playstead-mac/PlaysteadUITests/PairingCeremonyTests.swift |  | PairingCeremonyTests (the live-server pairing ceremony proof) is registered in LiveServer.xctestplan and compiles, but has not been executed against a real hosted Phoenix+Postgres mac_ci server in this session; not yet promoted to run-mac-verification.sh's --required-test list per WINDOWS #58's lesson. | open |  | 2026-09-09T00:53:41.765Z |  |
| 63 | 04.5 | stub | playstead-mac/Playstead/Pairing/PinnedCertificateCapture.swift |  | PinnedCertificateCapture has no dedicated unit test — its real trust-anchor capture path only fires on a genuine TLS handshake, which StubURLProtocol never performs. Coverage is structural/code-review only until the live-server proof (window #62) is run. | open |  | 2026-09-09T00:53:50.372Z |  |
| 64 | 03 | stub | playstead-server/lib/playstead_web/live/library_live.ex |  | list-view status_slot only passes queued fact, not the full device-reported status map status_for/2 now returns | open |  | 2026-09-11T04:31:57.324Z |  |
| 65 | 03 | unrun-verify | playstead-server/lib/playstead_web/live/library_live.ex |  | 03-13 backstop truths (500-entry stress toggle, download-in-progress uses existing indicator) not exercised by a dedicated automated fixture | open |  | 2026-09-11T04:31:57.416Z |  |
| 66 | 03 | stub | playstead-mac/Playstead/Cache/AvailabilityReporter.swift |  | Live transfer percent falls back to 0 when no DownloadCoordinator exists yet at report time | open |  | 2026-09-11T05:01:21.768Z |  |
| 67 | 03 | unmet-truth | playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift |  | FLAKY: testOneSaveRoundTripsCaptureUploadAndJournalReturn fails intermittently as save-e2e-harness=upload-did-not-complete (SaveEndToEndTests.swift:177) - a single un-retried `drainOnce()` pass. CORRECTED 2026-09-11: the first diagnosis here said 'a fixed 120s poll deadline'; that was WRONG. The 120s deadline is the XCTest-side wait for the result file. The real mechanism is that the harness calls `SaveUploadLane.drainOnce()` exactly once and requires `sent == 1`, while any single error inside that pass sets `stoppedForRetry`, schedules a backoff and returns `sent == 0`. So the test asserts that a deliberately-retrying lane succeeds on its first attempt, which production never promises. Failed in runs 34648546919 and 34658266643, and PASSED on an unchanged re-run of the same commit and on runs 34641553073/34657718830 - 2 failures in 5 runs, ~40%, far too high for a timing flake and consistent with the un-retried-pass mechanism, so a green result here is not yet a reliable truth. Do NOT delete: it is the only end-to-end proof of capture->upload->journal->sync and it previously caught save uploads 404ing against every real server (e6316d5); it has 4 prior hosted-runner fix commits. Fix the deadline and the diagnostic detail, never the assertion. RESOLVED 2026-09-11 (root cause corrected TWICE before landing - see below). The real cause is a RACE, not a timeout and not a transient error: the running app drains save uploads on a reachability transition (PlaysteadApp reachability.onChange -> uploadLane.drainOnce()), which in CI fires right after pairing, exactly while this harness inserts its revision. The harness built its OWN second SaveUploadLane over the same store; drainOnce's doc comment promises 'the lane is an actor, so overlapping calls serialize' and that is true - but two actor INSTANCES serialize nothing, so whichever lane lost saw an empty pending set and reported sent=0. Run 34663361104 named it exactly (upload-nothing-pending), which is what the three-way diagnostic split was added to distinguish. Fixed by sharing the app's own lane and asserting the OUTCOME (the revision reaches .uploaded) rather than one lane object's counter. Earlier wrong diagnoses, kept deliberately: (1) 'a fixed 120s poll deadline' - wrong, that is the XCTest-side wait; (2) 'a single un-retried drainOnce pass' - a real weakness, fixed and unit-pinned, but NOT what was failing in CI. The mechanism is now pinned deterministically by SaveUploadLaneTests.test_oneTransientFailure_makesASinglePassSendNothing_thoughTheNextPassSucceeds, which reproduces it in under a second: one 503 makes a single pass report sent=0 while the very next pass succeeds against the same server. The harness now drives the lane the way production does - bounded retry, only for the retryable classification, advancing past backoff rather than sleeping. A server-refused or nothing-pending failure still fails on the first pass, so the defect class e6316d5 caught is still caught. | open |  | 2026-09-11T23:23:31.675Z |  |
| 68 | 03 | fixme | playstead-mac/scripts/ci/live-server.sh |  | FALSE DIAGNOSTIC: the live-server stage marker is written on entering each stage and never cleared when a fixture action SUCCEEDS, so any later non-fixture failure inherits the last stage entered. Run 34648546919 reported FAILURE_STAGE redeem-pairing for a prepare that had completed fine; the real failure was in the save harness. This actively misdirected the first diagnosis. Clear the marker on successful completion of each action. | open |  | 2026-09-11T23:23:31.769Z |  |
| 69 | 03.5 | fixme | .github/workflows/verify-hosted-evidence.yml |  | RE-RUN BREAKS EVIDENCE BINDING: 'gh run rerun --failed' on a ci run makes the follow-on 'verify hosted evidence' workflow fail with 'complete evidence identity mismatch: head_sha' (run 34655069813 against ci run 34648546919). Re-running a flaky job is the standard mitigation, and it trips the evidence-identity guard - so the two controls are in conflict. Decide which identity the manifest should bind to across attempts. | open |  | 2026-09-11T23:23:31.870Z |  |

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
    "description": "Real Playstead.Saves revision data is not yet loaded into Export.to_layout_input/1; SavesPlan/Sidecar/BagitWriter pipeline is built+tested against synthetic data only (04-08) FIXED by plan 04-21 (22d92f7/433f7e4/8e32347): Export.load_save_revisions/2 loads real save revisions at the Export context boundary; the real file is playstead-server/lib/playstead/export.ex, not export/export.ex.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-04T15:35:17.080Z",
    "resolved_at": "2026-09-06T02:02:52.856Z"
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
    "description": "Comparison sheet is built and tested standalone but not yet wired into a live attention-inbox or game-detail navigation path on the Mac (server console entry point already shipped in 04-10); presentation wiring is left for a later plan STALE, not fixed by 04-23: ConflictComparisonSheet was wired into ReadinessSheetView by plan 04-16 / commit c223218, which postdates this entry; 04-VERIFICATION.md confirmed the wiring directly in source. Closed with c223218 as the resolving commit.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-04T20:20:49.523Z",
    "resolved_at": "2026-09-06T02:02:53.323Z"
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
    "description": "OnlyCopyEscalationPanel now has a real call site (ReadinessSheetView) gated by a real only-copy count, but the four unfixable escalation reasons (revokedAuth/capabilitySkew/serverRefusal/compatibilityRejection) still can't fire in production because SaveUploadLane has no wired failure-classification output yet (mac2 review WR-04) (04-16) FIXED by plan 04-19 (fb6ad53).",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T14:17:19.948Z",
    "resolved_at": "2026-09-05T22:18:48.497Z"
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
    "description": "AppEnvironment now constructs a shared SaveOutbox/SaveConflictResolver so MC-06's resolution path durably records locally, but no drain trigger (OutboxDrainTrigger-equivalent) is wired for SaveOutbox yet -- a resolved fork is recorded locally but may not reach the server promptly (mac2 review WR-04's other half) (04-16) FIXED by plan 04-23 (5c6439c): SaveOutboxDrainTrigger wired to post-enqueue, reachability-regained, and scene-active triggers.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T14:17:20.181Z",
    "resolved_at": "2026-09-06T02:02:52.938Z"
  },
  {
    "id": 43,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Readiness/ReadinessSheetView.swift",
    "line": null,
    "description": "saveHistorySessions closure passed to ReadinessSheetView is still never populated from SaveStore (mac2 review CR-04's other half) -- SaveHistorySheet's 'Review versions...' path for a non-diverged line still renders its empty state; out of 04-16's declared MC-01..MC-06 scope FIXED by plan 04-22 (62e0db0): SaveHistorySessionBuilder wired to real SaveStore data at both ReadinessSheetView call sites.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T14:17:20.303Z",
    "resolved_at": "2026-09-06T02:02:53.019Z"
  },
  {
    "id": 44,
    "kind": "unmet-truth",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveUploadLane.swift",
    "line": null,
    "description": "SaveUploadLane (the dedicated actor draining locally-captured save revisions to the server, D-16/D-32) is never constructed anywhere in production -- discovered baselining 04-18's reachability sweep. A more severe superset of the already-tracked WINDOWS #40 (which only covered its missing failure-classification output): the WHOLE upload path is unwired, not just one output of it. See 04-18-SUMMARY.md. FIXED by plan 04-19 (fb6ad53).",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T21:54:18.525Z",
    "resolved_at": "2026-09-05T22:18:48.578Z"
  },
  {
    "id": 45,
    "kind": "unmet-truth",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveCapturePoller.swift",
    "line": null,
    "description": "SaveCapturePoller is constructed in production ONLY inside SaveSessionRecovery.replay, which itself has no production caller -- there is no live, in-play save-capture trigger anywhere in the shipped app. Discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md. FIXED by plan 04-19 (3691ec3).",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T21:54:18.602Z",
    "resolved_at": "2026-09-05T22:18:48.656Z"
  },
  {
    "id": 46,
    "kind": "unmet-truth",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveSessionRecovery.swift",
    "line": null,
    "description": "SaveSessionRecovery (crash-recovery replay actor, D-05/D-07) is never constructed in production despite its own doc comment saying app launch should call it once per known save line. Discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md. FIXED by plan 04-19 (3691ec3).",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T21:54:18.681Z",
    "resolved_at": "2026-09-05T22:18:48.732Z"
  },
  {
    "id": 47,
    "kind": "unmet-truth",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveRollup.swift",
    "line": null,
    "description": "SaveRollup.rollup(for:) (D-36's game-level save rollup string) has zero production callers -- not reachable from any shipped UI. Discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md. FIXED by plan 04-22 (24d5c34): AppEnvironment.saveRollupSummary(forAssetSetID:) is SaveRollup.rollup(for:)'s first production caller; reachability-allowlist.txt's SaveRollup line removed.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T21:54:18.760Z",
    "resolved_at": "2026-09-06T02:02:53.099Z"
  },
  {
    "id": 48,
    "kind": "unmet-truth",
    "phase": "04",
    "file": "playstead-mac/Playstead/Controller/ControllerRecoveryBanner.swift",
    "line": null,
    "description": "ControllerRecoveryBanner and ControllerTestView (Controller/) and FirstRunBanner and ShowAllSystemsControl (Library/) are fully built views with zero production call sites -- discovered baselining 04-18's reachability sweep. See 04-18-SUMMARY.md and scripts/ci/reachability-allowlist.txt for the full list and per-symbol detail.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T21:54:18.835Z",
    "resolved_at": null
  },
  {
    "id": 49,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift",
    "line": null,
    "description": "A promoted capture's bytes are written to the save-captures directory and recorded as a SaveStore revision, but are NOT committed into the CAS. LaunchSaveContextBuilder derives head candidates' bytesLocal from casManager.contains(blobSHA256), so a locally-captured revision reads as bytes-not-local at the next launch and cannot be restored from history until it has round-tripped through the server. Same-device continuity still works (the live .sav artifact persists), so this is the mirror image of WINDOWS #38 rather than a break in SAVE-01's main path. Out of 04-19's declared scope (capture -> SaveStore -> upload). FIXED by plan 04-20 (10783c4 excludes save blobs from the reclaim menu; de3aec1 commits capture bytes into the CAS).",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T22:19:41.797Z",
    "resolved_at": "2026-09-05T23:05:00.000Z"
  },
  {
    "id": 50,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveCaptureBlockedState.swift",
    "line": null,
    "description": "AppEnvironment constructs SaveCaptureBlockedState with no SaveCaptureAlertSink and no SaveDirectUploadTransport, so a blocked capture (D-31) is recorded durably and is queryable, but raises no user-visible alert and has no direct-upload escape hatch in the shipped app. The seams exist and are injected; no attention surface consumes them yet.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T22:19:41.878Z",
    "resolved_at": null
  },
  {
    "id": 51,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveCapturePoller.swift",
    "line": null,
    "description": "The save-captures directory (<root>/save-captures/<assetSetID>/) has no reclamation path: each session leaves one session-<id>.staged.sav plus one <digest>.sav promoted blob, and QuotaManager measures paths.objects only, so capture blobs count against neither the quota nor the free-space floor and are never evicted. Save artifacts are small (tens of KB), so this is slow growth rather than an immediate hazard, but nothing bounds it.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-05T22:19:41.957Z",
    "resolved_at": null
  },
  {
    "id": 52,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveSessionRecovery.swift",
    "line": null,
    "description": "SaveSessionRecovery.replay (D-07 crash-recovery, reachable in production via AppEnvironment.recoverAbandonedSaveSessionsAtLaunch) records a promoted revision but holds no CASManager, so a crash-recovered capture's bytes never enter the CAS and LaunchSaveContextBuilder reports bytesLocal: false for it -- the same hole 04-20 closed on the live-session path (WINDOWS #49), reached via the second capture path. Out of 04-20's declared scope (files_modified named SaveSessionCoordinator only). Fix should extract 04-20's SaveSessionCoordinator.commitCaptureBytes into one shared spelling rather than a second copy. FIXED by plan 04-23 (fd4e2b4): extracted SaveCaptureBytesCommitter, shared by SaveSessionCoordinator and SaveSessionRecovery; recovery replay commits bytes into the CAS before inserting the row.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-05T22:36:11.098Z",
    "resolved_at": "2026-09-06T02:02:53.188Z"
  },
  {
    "id": 53,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-server/lib/playstead/export.ex",
    "line": null,
    "description": "Export.load_save_revisions/2 selects only the (battery, slot 0) save line when a content_key has more than one save line; any other lines are silently excluded from export rather than merged (v1 client only ever writes one line, so this is currently unreachable).",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-06T01:18:12.481Z",
    "resolved_at": null
  },
  {
    "id": 54,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Net/APIClient.swift",
    "line": null,
    "description": "The Mac client ships no pairing ceremony, so a human cannot pair a Mac at all. Every production PairingCredential construction is a keychain READ (KeychainStore.swift:152); the only writers are UI_TESTING-gated (UITestBootstrap.swift:552, DeterministicProfile.swift:49). There is no pairing view, no code-entry surface, no URL-scheme handler. The server side is complete -- POST /api/v1/device-pairing/requests, GET /requests/:id, POST /requests/:id/redeem, plus the devices approval console -- and the client calls none of it. APIClient.swift:57 states it outright ('this tracer plan does not yet ship the pairing ceremony') and anticipates a future plan writing AppPaths.root/pinned-ca.der; until then APIClient uses default TLS trust rather than the pinned root CA. LibraryShellView.swift:474's empty state instructs the user to 'Pair with your Playstead server to see your library', naming an action that exists nowhere in the app. 03.5-08 proved pairing only through scripts/ci/live-server.sh driving the HTTP ceremony from a shell script and handing a credential to a test build -- the human path was never built. Consequence: every human checkpoint requiring a paired Mac is unperformable, CP7-SAVE-C (UAT tests 107/112/120) included, which its 'blocked_by: physical-device' reason understates. Discovered 2026-09-08 when the owner tried to run CP7-SAVE-C and had no way to pair. Worked around for the owner's Mac only, by driving the production endpoints by hand and writing the server-issued credential into the login keychain (service dev.playstead.mac, device d23b584e); the missing UI itself is unfixed.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-08T17:38:16.547Z",
    "resolved_at": "2026-09-09T00:51:44.258Z"
  },
  {
    "id": 55,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveUploadLane.swift",
    "line": null,
    "description": "SHIPPED DEFECT: save uploads 404'd against every real server, so no captured revision has ever reached a server from the shipped app. APIClient.send does credential.baseURL.appendingPathComponent(path) and the paired credential's baseURL is the server ORIGIN, so callers own the whole path. SnapshotClient (/api/v1/snapshot) and ChangesClient (/api/v1/changes) spell it correctly; SaveUploadLane spelled 'saves/uploads/<id>' and 'saves/revisions' without the /api/v1 prefix, at both of its call sites. Server routes are PUT /api/v1/saves/uploads/:command_id and POST /api/v1/saves/revisions (router.ex:285,292). Observed on the owner's machine 2026-09-08: 'PUT /saves/uploads/... Sent 404' twice in the server log while POST /api/v1/play-sessions succeeded; two captured revisions sat at durability='queued' with 0 rows in the server's save_revisions. Capture, promotion and CAS commit all work -- only the upload half was broken. Fixed 2026-09-08 by prefixing both paths; guarded by scripts/ci/tests/api-path-prefix-test.sh, verified to reject the pre-fix source. WHY CI MISSED IT: SaveEndToEndTests guarded three fixture stages with bare 'guard try runFixture(...) else { return }', so a failing stage returned from the test having asserted nothing and XCTest recorded a pass -- the end-to-end proof of this exact path was fail-open. Seven such returns existed across SaveEndToEndTests and LiveServerSnapshotTests; all seven now XCTFail, and four-layer-topology-test.sh line 199 previously PINNED the fail-open shape as required. UAT tests 106 and 117 were marked pass on that evidence and are reverted to issue.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-08T17:49:43.371Z",
    "resolved_at": null
  },
  {
    "id": 56,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex",
    "line": null,
    "description": "SHIPPED DEFECT (server): the streamed save-upload route replied on the ORIGINAL conn instead of the one advanced by reading the body. Plug.Conn is immutable and body_stream/1 threads its own conn through Stream.resource, so create_upload/2 responded 200 on a conn that still believed the request body was unread. The connection was then left mid-body, and the NEXT request on it stalled until Bandit's 15s read timeout, surfacing as 'Bandit.HTTPError Read timeout' on the upload's request_id and a 502 EOF at Caddy for the following request. Because SaveUploadLane does PUT bytes then immediately POST /api/v1/saves/revisions on the same connection, the metadata commit ALWAYS died: bytes landed in save_pending_uploads, no revision ever committed, and the client's revision stayed durability='queued' forever. Size-dependent, which is why it was never noticed: reproduced deterministically at 4096 bytes -> next request 0.004s, 65536 -> 15.010s, 131072 -> 15.010s. Fixed 2026-09-08 by capturing the drained conn from body_stream/1 and replying on it; re-verified 0.0017s at both previously-broken sizes. Not reachable by ConnTest (Phoenix.ConnTest never opens a real connection), which is why the 2 existing saves_controller tests pass either way; the live-server e2e test WOULD have caught it had it not been fail-open (WINDOWS #55). Full server suite green after the fix: 1037 tests, 0 failures.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-08T18:22:12.727Z",
    "resolved_at": null
  },
  {
    "id": 57,
    "kind": "stub",
    "phase": "04",
    "file": "playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift",
    "line": null,
    "description": "Capture provenance is never recorded: save_revision.adapter_id and adapter_version are empty on every revision produced by the real Play path, though both columns exist client-side and server-side and SaveUploadLane forwards them when present. Observed on the owner's machine 2026-09-08 across all three revisions captured through the shipped app (Advance Wars 65,536 bytes; Pokemon LeafGreen 131,072 x2) -- adapter_id '', adapter_version '', capture_method 'session'. Consequence: a stored revision cannot say which emulator or which pinned adapter version produced it, so a future adapter upgrade that changes save-format behaviour leaves no way to tell affected revisions from unaffected ones. CP7-SAVE-C's own how-to-verify asks the developer to record the adapter version alongside the observations, which the app itself cannot supply. Not blocking: capture, upload, restore and byte-identity are all proven correct without it. Low severity, but it is provenance for the one artifact class this phase exists to protect.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-08T18:34:29.543Z",
    "resolved_at": "2026-09-08T22:15:00.000Z"
  },
  {
    "id": 61,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift",
    "line": null,
    "description": "SaveEndToEndTests failed once on hosted run 34281587417 (result file never written within 60s) and passed on 34285679092 with no change to any code the test exercises. The failure is intermittent and its cause is still unknown. Recorded as OPEN rather than closed by the green run: a test that fails one run in N is not fixed by the run where it passes. WINDOWS #60's failure channel and the 120s deadline mean the next occurrence will name which of the four harness steps (quiesce, pairing, upload, sync) failed, and whether it was slow or broken. Do not close without that evidence.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-08T23:50:00.000Z",
    "resolved_at": null
  },
  {
    "id": 60,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/Playstead/UITesting/UITestBootstrap.swift",
    "line": null,
    "description": "CI GAP (fixed same day, 4903ec8): the save end-to-end harness swallowed every failure, on the stated grounds that the absent result file was itself the signal. It is a signal with no content -- a slow run and a broken upload both surface as 'result was never written within 60s'. Hosted run 34281587417 failed exactly this way one run after the test was promoted to required, and the evidence named only the polling assertion's file:line. Fixed by writing a sanitized reason to a sibling file and giving each known cause its own assertion site, since CI's evidence pipeline keeps file:line and discards messages. Deadline raised 60s -> 120s only alongside the diagnostic. Root cause of the underlying timeout still unknown -- the next occurrence will name it.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-08T22:40:00.000Z",
    "resolved_at": "2026-09-08T22:40:00.000Z"
  },
  {
    "id": 58,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift",
    "line": null,
    "description": "CI GAP (fixed same day, cc7640d): the phase's only end-to-end save proof had never run on a hosted runner. SaveEndToEndTests resolved its fixture environment from ProcessInfo.processInfo.environment alone; the XCTest process inherits a PATH with no Elixir toolchain, so live-server.sh's 'mix playstead.mac_ci_fixture' died with 'mix: command not found' at provision-domain on every hosted run. The sibling LiveServerSnapshotTests already merged the runner-written live-server-runtime.json (which carries the real PATH) over the inherited environment and documented exactly this hazard; SaveEndToEndTests' doc comment claimed it reused that discipline 'verbatim' and did not. Invisible because the test was fail-open until e6316d5 and because live-server.sh discarded its own stderr until 266015e. Third seam-between-plans defect of this phase after #55 and #56. Guarded by scripts/ci/tests/live-server-env-resolution-test.sh, falsified against the real pre-fix source.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-08T20:58:11.764Z",
    "resolved_at": "2026-09-08T20:58:25.364Z"
  },
  {
    "id": 59,
    "kind": "deviation",
    "phase": "04",
    "file": "playstead-mac/scripts/ci/run-mac-verification.sh",
    "line": null,
    "description": "CI GAP (fixed same day, 266015e): the hosted UI layer's 1800s deadline sat 9% above its own observed runtime (1631s in the last green run, 50960ba), and run 34264338508 was SIGTERMed at exactly 1800s on a commit whose diff touched no file in the UI test plan. Raised to 2700s with four-layer-topology-test.sh's pinned expectation and ceiling moved with it. Recorded because the failure mode is a gate that reports red for reasons unrelated to the code under test, which trains readers to discount it.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-08T20:58:18.772Z",
    "resolved_at": "2026-09-08T20:58:25.464Z"
  },
  {
    "id": 62,
    "kind": "unrun-verify",
    "phase": "04.5",
    "file": "playstead-mac/PlaysteadUITests/PairingCeremonyTests.swift",
    "line": null,
    "description": "PairingCeremonyTests (the live-server pairing ceremony proof) is registered in LiveServer.xctestplan and compiles, but has not been executed against a real hosted Phoenix+Postgres mac_ci server in this session; not yet promoted to run-mac-verification.sh's --required-test list per WINDOWS #58's lesson.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-09T00:53:41.765Z",
    "resolved_at": null
  },
  {
    "id": 63,
    "kind": "stub",
    "phase": "04.5",
    "file": "playstead-mac/Playstead/Pairing/PinnedCertificateCapture.swift",
    "line": null,
    "description": "PinnedCertificateCapture has no dedicated unit test — its real trust-anchor capture path only fires on a genuine TLS handshake, which StubURLProtocol never performs. Coverage is structural/code-review only until the live-server proof (window #62) is run.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-09T00:53:50.372Z",
    "resolved_at": null
  },
  {
    "id": 64,
    "kind": "stub",
    "phase": "03",
    "file": "playstead-server/lib/playstead_web/live/library_live.ex",
    "line": null,
    "description": "list-view status_slot only passes queued fact, not the full device-reported status map status_for/2 now returns",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T04:31:57.324Z",
    "resolved_at": null
  },
  {
    "id": 65,
    "kind": "unrun-verify",
    "phase": "03",
    "file": "playstead-server/lib/playstead_web/live/library_live.ex",
    "line": null,
    "description": "03-13 backstop truths (500-entry stress toggle, download-in-progress uses existing indicator) not exercised by a dedicated automated fixture",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T04:31:57.416Z",
    "resolved_at": null
  },
  {
    "id": 66,
    "kind": "stub",
    "phase": "03",
    "file": "playstead-mac/Playstead/Cache/AvailabilityReporter.swift",
    "line": null,
    "description": "Live transfer percent falls back to 0 when no DownloadCoordinator exists yet at report time",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T05:01:21.768Z",
    "resolved_at": null
  },
  {
    "id": 67,
    "kind": "unmet-truth",
    "phase": "03",
    "file": "playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift",
    "line": null,
    "description": "FLAKY: testOneSaveRoundTripsCaptureUploadAndJournalReturn fails intermittently as save-e2e-harness=upload-did-not-complete (SaveEndToEndTests.swift:177) - a fixed 120s poll deadline on the upload lane. Failed in run 34648546919, then PASSED on an unchanged re-run of the same commit, so a green result here is not yet a reliable truth. Do NOT delete: it is the only end-to-end proof of capture->upload->journal->sync and it previously caught save uploads 404ing against every real server (e6316d5); it has 4 prior hosted-runner fix commits. Fix the deadline and the diagnostic detail, never the assertion. Needs a second failing data point before fixing blind.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T23:23:31.675Z",
    "resolved_at": null
  },
  {
    "id": 68,
    "kind": "fixme",
    "phase": "03",
    "file": "playstead-mac/scripts/ci/live-server.sh",
    "line": null,
    "description": "FALSE DIAGNOSTIC: the live-server stage marker is written on entering each stage and never cleared when a fixture action SUCCEEDS, so any later non-fixture failure inherits the last stage entered. Run 34648546919 reported FAILURE_STAGE redeem-pairing for a prepare that had completed fine; the real failure was in the save harness. This actively misdirected the first diagnosis. Clear the marker on successful completion of each action.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T23:23:31.769Z",
    "resolved_at": null
  },
  {
    "id": 69,
    "kind": "fixme",
    "phase": "03.5",
    "file": ".github/workflows/verify-hosted-evidence.yml",
    "line": null,
    "description": "RE-RUN BREAKS EVIDENCE BINDING: 'gh run rerun --failed' on a ci run makes the follow-on 'verify hosted evidence' workflow fail with 'complete evidence identity mismatch: head_sha' (run 34655069813 against ci run 34648546919). Re-running a flaky job is the standard mitigation, and it trips the evidence-identity guard - so the two controls are in conflict. Decide which identity the manifest should bind to across attempts.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T23:23:31.870Z",
    "resolved_at": null
  }
]
````
