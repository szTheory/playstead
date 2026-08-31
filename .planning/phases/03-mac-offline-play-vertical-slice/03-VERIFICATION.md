---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-08-30T23:59:00Z
status: gaps_found
score: 3/5 roadmap truths verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "A user can select or install one supported Mac adapter, see its exact system/emulator/version/content/BIOS/save support, validate a locally supplied BIOS or supported open replacement, and receive a preflight remedy for each blocking readiness condition."
    status: partial
    reason: "The BIOS validation code path (BiosStore) is fully implemented and unit-tested against synthetic references, but has no production reference-digest wiring anywhere in the composition root (PlaysteadApp.swift). With no known-reference digest set supplied, BiosStore rejects every real dropped BIOS file unconditionally — the feature is present but non-functional end-to-end for a real user today. This is honestly disclosed in 03-09-SUMMARY.md's 'Known Stubs' section, not hidden, but it is a real functional gap against PLAY-03's 'recognizes an open replacement when supported' claim."
    artifacts:
      - path: "playstead-mac/Playstead/Adapter/BiosStore.swift"
        issue: "Reference{} constructor parameter (known digests) has no production default and is never supplied at any call site outside tests"
    missing:
      - "A sourced, confirmed reference SHA-256 (or open-BIOS-replacement digest) wired into BiosStore's composition root for the pinned system, or an explicit UAT/backlog item tracking this as a pre-ship blocker"
  - truth: "A user can launch one legally testable game through the supported adapter from a signed/notarized Mac build, exit safely, and relaunch it after an application or server restart."
    status: failed
    reason: "The build is dev-signed only — never actually notarized. This is a deliberate, disclosed owner decision (2026-08-30) to skip the paid Apple Developer Program for this run, not a hidden gap, but it means the roadmap's own success criterion #5 ('from a signed/notarized build') is literally unmet: 03-SPIKE-REPORT.md probes 1 and 6, and 03-10's Gatekeeper-acceptance / notarized-launch criterion, are all recorded as DEFERRED rather than passing. No probe or test in this phase exercises a genuinely notarized artifact."
    artifacts:
      - path: "playstead-mac/scripts/sign-and-notarize.sh"
        issue: "Supports notarization but was never run against a real Developer ID Application identity in this phase; only dev-signed builds were produced and tested"
    missing:
      - "A real notarized build run and the Gatekeeper-acceptance / relaunch-after-restart proof against it, once the owner enrolls in the Apple Developer Program (already an explicit action item recorded across 03-01/03-03/03-10 SUMMARYs)"
  - truth: "Two CRITICAL path-traversal defects (CR-01, CR-02) identified in 03-REVIEW.md remain unpatched in the codebase."
    status: failed
    reason: "03-REVIEW.md (committed after all 10 plans completed) found that a server-declared, unvalidated `member.declaredName` (LaunchMaterializer.swift:49) and a server-declared, unvalidated `sha256` string (AppPaths.swift objectURL/partialURL) are both spliced directly into filesystem paths with no traversal/format validation, in a non-sandboxed app, allowing a compromised/spoofed paired server to write attacker-chosen bytes to an attacker-chosen path on disk. Verified directly against the current source: LaunchMaterializer.swift:49 still does `directory.appendingPathComponent(member.declaredName)` with no `safeFilename` guard, and AppPaths.swift's `objectURL(for:)`/`partialURL(for:)` still splice `sha256` into path components with no hex-digest format check. No commit after the review (`f12e4c4`, the last commit in the repo) addresses either finding."
    artifacts:
      - path: "playstead-mac/Playstead/Cache/LaunchMaterializer.swift"
        issue: "Line 49: appendingPathComponent(member.declaredName) with zero path-traversal validation"
      - path: "playstead-mac/Playstead/App/AppPaths.swift"
        issue: "objectURL(for:)/partialURL(for:) splice unvalidated sha256 string directly into path components"
    missing:
      - "The two fixes 03-REVIEW.md already specifies (a safeFilename guard rejecting non-bare-filename declaredName values; a hex-digest format guard on sha256 before it is ever used as a path component), applied at decode/ingest time so an invalid value never reaches the cache/materialization layer"
human_verification:
  - test: "Physical game controller connect/disconnect/reconnect recovery, live input test, remap, and reset on real hardware"
    expected: "Controller lifecycle logic (ControllerHost, tested against an injectable ControllerInputSource) behaves identically against a real device — connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without a relaunch"
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 explicitly recorded this as FAIL/unproven, and 03-10-SUMMARY.md's own D1 rationale says the same — all logic is unit-tested against a simulated input source only"
  - test: "Full end-to-end launch of the pinned mGBA adapter against a live paired server, with a downloaded game and installed emulator, from a genuinely notarized build"
    expected: "Play starts the emulator, the game runs, SRAM periodically flushes (already proven via spike evidence with a dev-signed build), quitting returns to the library, and Gatekeeper accepts the app without any user override"
    why_human: "This sandboxed/headless execution environment cannot render a live interactive display session, has no paid Apple Developer Program enrollment (owner decision, 2026-08-30) to produce a real notarized build, and multiple SUMMARYs (03-03 D1/D5/D6, 03-10 D3) explicitly flag this end-to-end loop as unexercised"
  - test: "Visual/typographic fidelity and VoiceOver walkthrough of the LiveView console and the Mac library shell against 03-UI-SPEC.md"
    expected: "Spacing, color rendering, motion timing, and screen-reader sentence flow match the locked design contract on both surfaces"
    why_human: "Multiple SUMMARYs (03-05 D3/D7, 03-06 D2, 03-07 D6, 03-08 D3, 03-10 D2) explicitly state that only the markup-level/logic-level accessibility contract was automatically verified (aria attributes, accessible names, a declarative accessibility-manifest walk) — no live NSAccessibility tree or interactive rendering was exercised in this environment"
  - test: "Drag-in BIOS validation against a real, legally-sourced BIOS file or supported open replacement"
    expected: "A correct BIOS file is accepted and stored under managed storage; an incorrect one is rejected with a clear reason"
    why_human: "BiosStore has no production reference-digest wiring (see gaps above) — a human must source a real reference digest, wire it at the composition root, and confirm the drop flow works against real bytes before PLAY-03 can be considered functionally complete, not just logically correct"
---

# Phase 3: Mac Offline Play Vertical Slice Verification Report

**Phase Goal:** A newly paired Mac can browse a curated server library, download only chosen verified content, and launch one deliberately supported game offline through a tested adapter.
**Verified:** 2026-08-30T23:59:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | 03-03 (Mac snapshot read, zero bytes downloaded), 03-04 (server curation domain), 03-05 (LiveView console: 5 shelves, search, filters, collections), 03-06 (Mac sync engine + library shell), 03-08 (Mac offline curation outbox). Extensive unit/integration test coverage across both Mac (`SyncEngineTests`, `FilterTests`, `StatusLadderTests`) and server (`library_live_test.exs`, `collections_live_test.exs`) suites, all passing per SUMMARYs. |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | 03-02 (frozen Range/If-Range/206/416/HEAD server contract, tested), 03-03 (DownloadEngine resume, CAS commit-after-verify), 03-07 (DownloadQueue, AvailabilityState.derive six-state pure function, exhaustively tested). |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; game launchable only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | 03-07 (QuotaManager two-limit policy, PinStore, EvictionPlanner LRU reconstructability guarantee), 03-03/03-09 (PreflightChecker/ReadinessEngine, zero-network-call proof, CACH-04). |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ⚠️ PARTIAL | 03-09 delivers AdapterInstaller/AdapterCapabilityCard/ReadinessEngine fully tested — install/select/preflight-remedy sub-claims verified. BIOS-validation sub-claim is a real functional gap: BiosStore's known-reference digest set has **no production default anywhere in the composition root**, so real BIOS drops are unconditionally rejected today. Honestly disclosed in 03-09-SUMMARY.md's "Known Stubs," but the roadmap truth as stated is not fully met. |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a **signed/notarized** build after app or server restart | ✗ FAILED (as literally stated) | Controller lifecycle and accessibility floor are implemented and unit-tested (03-10). However the build is **dev-signed only, never notarized** — an explicit, disclosed 2026-08-30 owner decision to skip the paid Apple Developer Program for this run. 03-SPIKE-REPORT.md probes 1/6 and 03-10's Gatekeeper/notarization criterion are recorded DEFERRED, not passing. The roadmap's own wording ("signed/notarized build") is not met by a dev-signed-only build. Controller recovery on real hardware is also unproven (probe 5, FAIL/unproven) — no physical controller was ever available. |

**Score:** 3/5 roadmap truths fully verified; 1 partial (BIOS gap); 1 failed as literally worded (notarization deferred by owner decision + controller hardware unproven).

### Deferred Items (Owner-Recorded, Not Fabricated Gaps)

These are explicitly, honestly recorded as deferred by the owner/executor rather than hidden or faked — surfaced here per instructions, not treated as silent gaps:

| Item | Recorded where | Disposition |
|------|-----------------|-------------|
| Notarization (paid Apple Developer Program not enrolled) | 03-01, 03-03, 03-10 SUMMARYs; 03-SPIKE-REPORT.md probes 1/6 | Owner decision 2026-08-30. Affects PLAY-05 and roadmap SC #5's literal wording. Routed to human_verification above — not silently marked passed. |
| Physical controller hardware unproven (spike probe 5) | 03-01-SUMMARY.md D4; 03-10-SUMMARY.md D1 rationale | No hardware available in this environment. All logic unit-tested against an injectable input source. Routed to human_verification above. |
| BIOS reference digests have no production default | 03-09-SUMMARY.md "Known Stubs" | Dependency-injected with no built-in value; correctly and safely rejects everything until wired. Treated as a real functional gap above (not merely deferred) because it blocks PLAY-03 end-to-end today. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead.xcodeproj` | Real Xcode project, file-system-synchronized groups | ✓ VERIFIED | Present on disk; `project.pbxproj` uses `PBXFileSystemSynchronizedRootGroup`, confirmed by 03-03 SUMMARY and file listing. |
| `playstead-mac/Playstead/Cache/{CASManager,DownloadEngine,DownloadQueue,DownloadCoordinator,EvictionPlanner,QuotaManager,PinStore,LaunchMaterializer,PreflightChecker}.swift` | Full cache/download/preflight stack | ✓ VERIFIED (exists, substantive, wired) — but see CR-01/CR-02 below for a wiring-level *security* defect, not an absence defect | Reviewed directly in 03-REVIEW.md against 32 files; code is present, tested, and functionally wired end-to-end. |
| `playstead-mac/Playstead/Adapter/{AdapterInstaller,AdapterHost,BiosStore,AdapterCatalog,AdapterCapabilityCard}.swift` | Adapter install/select/launch/capability/BIOS stack | ⚠️ ORPHANED (BiosStore only) | AdapterInstaller/AdapterHost/AdapterCatalog fully wired and tested. `BiosStore` exists, is substantive, and is unit-tested, but has **no production caller supplying real reference digests** — functionally orphaned from the live composition root. |
| `playstead-mac/Playstead/Controller/{ControllerHost,ControllerMapping,ControllerMappingStore}.swift` | Controller lifecycle | ✓ VERIFIED (wired, tested against simulated hardware) | Registered at `AppEnvironment` construction per 03-10-SUMMARY.md; real-hardware behavior unverified (see human_verification). |
| `playstead-mac/scripts/sign-and-notarize.sh` | Signed, notarized release pipeline | ⚠️ PARTIAL | Script supports full notarization path and was hardened in 03-10 (hardened-runtime assertion, nested-bundle rejection, SIGPIPE fix), but was never run against a real Developer ID identity — only the dev-sign branch has actually executed. |
| `.planning/phases/03-mac-offline-play-vertical-slice/03-REVIEW.md` | Code review report | ✓ VERIFIED | Present; 2 critical, 4 warning, 1 info findings; `status: issues_found`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| Mac `GameRowView` → `LaunchMaterializer` | server-declared `member.declaredName` | direct pass-through to `appendingPathComponent` | ✗ **NOT SAFELY WIRED** | CR-01 in 03-REVIEW.md, confirmed unpatched by direct source read: `LaunchMaterializer.swift:49` has no filename-safety guard. A malicious/compromised paired server can write attacker-chosen bytes to an attacker-chosen filesystem path in a non-sandboxed app. |
| Mac `CatalogueStore`/`DownloadQueue` → `AppPaths.objectURL/partialURL` | server-declared `sha256` | direct pass-through to path-component construction | ✗ **NOT SAFELY WIRED** | CR-02 in 03-REVIEW.md, confirmed unpatched: `AppPaths.swift`'s `objectURL(for:)`/`partialURL(for:)` splice the raw `sha256` string into path components with no hex-digest format validation. Same class of arbitrary-file-write risk as CR-01. |
| `BiosDropTargetView` → `BiosStore` | reference digest set | dependency injection, no production default | ⚠️ HOLLOW | The UI/validation wiring is present and tested against synthetic references, but the production reference-digest value that makes it actually accept a real BIOS file was never supplied anywhere in the shipped composition root. |
| `PreflightChecker`/`ReadinessEngine` → Play button gating | readiness report → UI enable/disable | wired | ✓ VERIFIED | 03-09 `ReadinessReportView`; Play enabled only when the report has no blocking result, per SUMMARY and tests. |

### Requirements Coverage

All 15 declared requirement IDs for Phase 3 (LIBR-01 through QUAL-01) are claimed across the 10 plans' `requirements`/`requirements-completed` frontmatter, and every ID matches an entry in REQUIREMENTS.md's traceability table (all currently listed "Pending" there, since REQUIREMENTS.md itself has not yet been updated post-phase — this is expected; that document is updated at milestone completion, not per-phase, per this project's own convention observed in Phases 1–2's now-`Complete` rows).

| Requirement | Source Plan(s) | Status | Evidence |
|-------------|-----------------|--------|----------|
| LIBR-01 | 03-03, 03-06 | ✓ SATISFIED | Snapshot-only catalogue browse, zero bytes downloaded; sync engine convergence tests |
| LIBR-02 | 03-05, 03-06 | ✓ SATISFIED | Search/filter tests on both LiveView and Mac |
| LIBR-03 | 03-04, 03-08 | ✓ SATISFIED | Server curation context + Mac offline outbox, both tested |
| LIBR-04 | 03-05, 03-06 | ✓ SATISFIED | Empty-system/empty-shelf hiding behavior tested on both surfaces |
| LIBR-05 | 03-05 | ✓ SATISFIED | LiveView console parity: shelves, collections, search, from `Playstead.Curation` only |
| CACH-01 | 03-02, 03-03, 03-07 | ✓ SATISFIED | Range/resume contract frozen and tested server + client side |
| CACH-02 | 03-07 | ✓ SATISFIED | Six-state `AvailabilityState.derive` exhaustively tested |
| CACH-03 | 03-07 | ✓ SATISFIED | Quota/floor policy, pin, LRU reclaim, reconstructability guarantee tested |
| CACH-04 | 03-03, 03-09 | ✓ SATISFIED | Preflight/readiness offline-launch gating tested, zero network calls |
| PLAY-01 | 03-01, 03-09 | ✓ SATISFIED | Adapter pin, install/select, honest capability card |
| PLAY-02 | 03-09 | ✓ SATISFIED | Six-check ReadinessEngine, ordered severity, remedy per blocker |
| PLAY-03 | 03-09 | ⚠️ PARTIALLY SATISFIED | BIOS validation logic complete and tested but non-functional in production absent a reference digest (see gaps) |
| PLAY-04 | 03-10 | ⚠️ NEEDS HUMAN | Controller lifecycle fully implemented/tested against simulated hardware; real-hardware behavior unproven (no hardware available) |
| PLAY-05 | 03-01, 03-03, 03-10 | ✗ NOT FULLY SATISFIED | Notarization deferred by explicit owner decision; only dev-signed build proven |
| QUAL-01 | 03-05, 03-10 | ⚠️ NEEDS HUMAN | Accessibility floor implemented and unit-tested at the markup/logic level on both Mac and LiveView surfaces; no live screen-reader/VoiceOver session performed |

No orphaned requirements found — every ID from REQUIREMENTS.md's Phase 3 mapping appears in at least one plan's `requirements` field, and every plan's declared requirements are covered by REQUIREMENTS.md.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `playstead-mac/Playstead/Cache/LaunchMaterializer.swift` | 49 | Unvalidated server string used as filesystem path component (CR-01) | 🛑 BLOCKER | Arbitrary file write via a compromised/spoofed paired server, in a non-sandboxed app |
| `playstead-mac/Playstead/App/AppPaths.swift` | 60–69 | Unvalidated server string (`sha256`) used as filesystem path component (CR-02) | 🛑 BLOCKER | Same class of arbitrary file write; digest check provides no real integrity backstop for this specific defect |
| `playstead-mac/Playstead/Sync/OutboxWorker.swift` | 60–64 | `continue` on local persistence failure violates the module's own ordering guarantee (WR-01) | ⚠️ WARNING | A later curation intent can be sent ahead of an earlier one still pending, silently |
| `playstead-mac/Playstead/Cache/DownloadCoordinator.swift` | 235–243 | Unbounded digest-mismatch retry with no terminal give-up state (WR-02) | ⚠️ WARNING | A permanently corrupt manifest entry retries forever, consuming bandwidth |
| `playstead-mac/Playstead/App/AppPaths.swift` | 41–56 | `try?`-swallowed directory-creation/backup-exclusion errors (WR-03) | ⚠️ WARNING | Silent failure of Time-Machine-exclusion promise and downstream generic errors |
| `playstead-mac/Playstead/Cache/CASManager.swift` | 55–58 | `try?`-swallowed cleanup of duplicate partial (WR-04) | ⚠️ WARNING | Orphaned files silently accumulate disk space |
| `playstead-mac/Playstead/Adapter/BiosStore.swift` | (composition root) | No production reference-digest default supplied anywhere | ℹ️ INFO / gap | Feature present but functionally inert until wired — honestly disclosed, tracked as a gap above |

No unresolved `TBD`/`FIXME`/`XXX` debt markers with missing follow-up references were found in the phase's key files via targeted grep of the reviewed file list.

### Behavioral Spot-Checks

Not run directly by this verifier — the Mac client requires Xcode/`xcodebuild` on macOS with a full toolchain and Keychain access (already documented across every SUMMARY as unavailable/restricted in the execution sandbox: "dark wake" Keychain restriction, no interactive display session). This verifier relied on:
1. Direct source inspection of the two CR-01/CR-02 findings (confirmed unpatched by reading the actual current file contents, not by trusting the review or any SUMMARY).
2. Cross-referencing every plan's declared test files against `find playstead-mac/PlaysteadTests -name "*.swift"` (21 test files present on disk, consistent with the ~13 test files named across 03-01/03-03/03-06/03-07/03-08/03-09/03-10 SUMMARYs).
3. `git log` confirming no commit after `f12e4c4` (the code-review commit, the most recent commit in the repo) touches either flagged file — i.e., the critical findings are not silently fixed and unreported.

Step 7b: SKIPPED beyond the above (no runnable macOS entry point in this environment; server-side `mix test` claims in SUMMARYs were not independently re-run by this verifier, consistent with prior-phase verifier practice of trusting server test-run claims when file/line evidence for the code itself is directly inspectable).

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention exists in this project; the phase's own probes are `playstead-mac/spike/scripts/run-probes.sh`, producing `spike/out/probe-01.json` through `probe-07.json`. These were not re-run by this verifier (require a macOS toolchain, mGBA installation, and — for probes 1/6 — a paid notarization identity that does not exist in this environment). 03-SPIKE-REPORT.md's own recorded verdicts (2 deferred, 1 unproven/fail, 4 pass) were taken as given since they are the primary artifact this phase produces and are internally consistent with every downstream SUMMARY's own honest disclosure of the same gaps — not silently upgraded to "pass."

### Human Verification Required

See `human_verification` in frontmatter — four items: real controller hardware, a genuinely notarized end-to-end launch cycle, visual/VoiceOver fidelity review of both consoles, and BIOS validation against a real reference file once sourced.

### Gaps Summary

Three concrete gaps block a clean `passed` verdict:

1. **CR-01 and CR-02 (critical path-traversal defects) are real and unpatched.** These are the single most important finding: a compromised or spoofed paired server can write attacker-chosen bytes to an attacker-chosen filesystem path, in an app that deliberately ships without App Sandbox. This is not a hypothetical — it was found by this same phase's own code review and never fixed in a follow-up commit. Given the project's stated threat model (an untrusted/possibly-compromised self-hosted server pairing with a client that has no sandbox backstop), this must be closed before the phase can be considered to have actually achieved "launch one deliberately supported game offline through a tested adapter" safely.
2. **BIOS validation (part of PLAY-03 and roadmap SC #4) is functionally inert in production** — the code path is complete and tested, but no reference digest is wired anywhere a real user would reach, so every real BIOS drop is rejected today. Honestly disclosed by the executor, not hidden, but it is a real functional gap.
3. **PLAY-05 / roadmap SC #5's literal "signed/notarized build" wording is unmet** — the build is dev-signed only. This is an explicit, recorded 2026-08-30 owner decision to defer notarization (no paid Apple Developer Program), and controller-hardware verification is likewise deferred for lack of physical hardware. Both are correctly surfaced here as human-verification items rather than fabricated passes, per this verification's instructions — they do not represent executor dishonesty, but they do mean the roadmap truth as literally worded is not yet true.

None of these three gaps invalidate the substantial, well-tested work across the other four roadmap success criteria (library browse/curate, selective cache/resume/availability, capacity/pin/reclaim/offline-launch, and most of the adapter-readiness stack) — but per the adversarial verification stance, a clean `passed` status is not warranted while a known, owner-acknowledged critical security defect remains unpatched in the same codebase this phase just reviewed and found it in.

---

*Verified: 2026-08-30T23:59:00Z*
*Verifier: Claude (gsd-verifier)*
