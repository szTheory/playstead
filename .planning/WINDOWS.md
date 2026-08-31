---
schema_version: 1
open_count: 6
waived_count: 1
fixed_count: 1
total_count: 8
last_updated: 2026-08-31T10:48:44.083Z
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
| 5 | 03 | deviation | playstead-mac/Playstead/App/PlaysteadApp.swift |  | AppEnvironment does not yet construct DownloadQueue/DownloadCoordinator/QuotaManager/PinStore/EvictionPlanner as live app-wide singletons (03-07) | open |  | 2026-08-31T01:42:20.733Z |  |
| 6 | 03 | unrun-verify | playstead-mac/Playstead/Library/StorageView.swift |  | Visual/interactive click-through of DownloadsView/QuotaSettingsView/ReclaimPromptView/StorageView against a live paired server unverified in this headless session (03-07 coverage D6) | open |  | 2026-08-31T01:42:25.363Z |  |
| 7 | 03 | stub | playstead-mac/Playstead/Adapter/BiosStore.swift |  | BiosStore's known-reference digest set has no production default (DI-only, no fabricated evidence); real reference digest wiring is deferred until sourced | open |  | 2026-08-31T02:43:54.600Z |  |
| 8 | 03 | deviation | playstead-mac/Playstead/Adapter/AdapterHost.swift |  | Gatekeeper-held child hangs silently: AdapterHost.launch treats a successful Process.run() as launched, but a quarantined bundle is left suspended at _dyld_start and terminationHandler never fires — the app believes the emulator runs forever with no error surfaced. AdapterInstaller preserves quarantine per D-05. Proven experimentally (signed+quarantined HUNG; signed alone exits 0.15s). A properly notarized mGBA should pass assessment so the happy path is likely fine, but the failure shape is silent and unbounded. Fix requires a design decision: a liveness probe cannot distinguish held from idle (held task reports S not T; Mach suspend count needs task-port access the app lacks), and pre-flighting SecStaticCodeCheckValidity at install would reject the /bin/echo stand-ins both test suites depend on, so a fixture strategy must be decided alongside it. | open |  | 2026-08-31T10:48:44.083Z |  |

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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:42:20.733Z",
    "resolved_at": null
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
  }
]
````
