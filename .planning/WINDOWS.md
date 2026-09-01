---
schema_version: 1
open_count: 20
waived_count: 1
fixed_count: 2
total_count: 23
last_updated: 2026-09-01T12:48:01.842Z
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
| 9 | 03.5 | unrun-verify | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Task 1 exact UI-layer drag verification requires the centrally orchestrated hosted macOS runner; local app launch is prohibited by the no-password safety boundary. | open |  | 2026-09-01T06:29:58.866Z |  |
| 10 | 03.5 | unrun-verify | playstead-mac/PlaysteadUITests/CurationInteractionTests.swift |  | Task 2 full CurationInteractionTests UI-layer verification requires the centrally orchestrated hosted macOS runner; local app launch is prohibited by the no-password safety boundary. | open |  | 2026-09-01T06:29:58.948Z |  |
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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:29:58.866Z",
    "resolved_at": null
  },
  {
    "id": 10,
    "kind": "unrun-verify",
    "phase": "03.5",
    "file": "playstead-mac/PlaysteadUITests/CurationInteractionTests.swift",
    "line": null,
    "description": "Task 2 full CurationInteractionTests UI-layer verification requires the centrally orchestrated hosted macOS runner; local app launch is prohibited by the no-password safety boundary.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:29:58.948Z",
    "resolved_at": null
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
  }
]
````
