---
phase: 03-mac-offline-play-vertical-slice
plan: 10
subsystem: adapter
tags: [swift, gamecontroller, sqlite, accessibility, codesign, notarization, xctest]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "03-01's pinned adapter contract and spike evidence, 03-03's AdapterHost/process registry, 03-06 through 03-08's library shell/curation/sync surfaces, 03-09's ReadinessEngine/AdapterInstaller/BiosStore"
provides:
  - "ControllerHost/ControllerMapping/ControllerMappingStore: full controller lifecycle (connect, live test, assign, remap, reset, non-modal disconnect recovery) behind an injectable ControllerInputSource, registered at application launch"
  - "AdapterHost.renderedLaunchArguments: pure, testable injection of the active controller mapping into the launch configuration through the pin's cli_config_override mechanism"
  - "MotionPreference/ProgressFillState: injectable reduced-motion duration with determinate progress fill computed independently of motion preference"
  - "AccessibilityAudit (declarative, manifest-based): walks every top-level Mac surface for unlabeled interactive elements, color-alone status distinctness, and tab-order-vs-declared-order mismatches"
  - "BiosDropTargetView keyboard-and-pointer file-chooser alternative to the drag"
  - "Hardened, fail-loud sign-and-notarize.sh (hardened-runtime assertion, nested-bundle rejection, Developer ID + notarytool submit/staple/Gatekeeper-accept path, gracefully DEFERRED without a paid membership)"
  - "RelaunchTests: closes and reopens every store and proves a previously launch-ready game stays launch-ready with zero network calls; proves a registered adapter process is terminated on application termination"
  - "docs/ACCESSIBILITY.md, docs/RELEASE.md, docs/SUPPORT-MATRIX.md"
affects: []

actuals:
  tokens: 23743
  tasks: 3
  commits: 3

tech-stack:
  added: [GameController.framework]
  patterns:
    - "Injectable hardware-facing protocol (ControllerInputSource) so connect/disconnect lifecycle logic is fully unit-tested with no physical device, mirroring this codebase's established headless-only testing precedent"
    - "AccessibilityAudit as a declarative manifest walk over real view-layer data/logic (not a live NSAccessibility tree), matching FilterChipRow's prior precedent for this test target"
    - "Motion duration and determinate progress value kept as two independently-computed types (MotionPreference vs ProgressFillState) so reduced motion can never silently remove progress information by construction"

key-files:
  created:
    - playstead-mac/Playstead/Controller/ControllerHost.swift
    - playstead-mac/Playstead/Controller/ControllerMapping.swift
    - playstead-mac/Playstead/Controller/ControllerMappingStore.swift
    - playstead-mac/Playstead/Controller/ControllerSettingsView.swift
    - playstead-mac/Playstead/Controller/ControllerTestView.swift
    - playstead-mac/Playstead/Controller/ControllerRecoveryBanner.swift
    - playstead-mac/Playstead/Design/MotionPreference.swift
    - playstead-mac/PlaysteadTests/ControllerTests/ControllerHostTests.swift
    - playstead-mac/PlaysteadTests/AccessibilityTests/AccessibilityAuditTests.swift
    - playstead-mac/PlaysteadTests/AdapterTests/RelaunchTests.swift
    - playstead-mac/docs/ACCESSIBILITY.md
    - playstead-mac/docs/RELEASE.md
    - playstead-mac/docs/SUPPORT-MATRIX.md
    - playstead-mac/.gitignore
  modified:
    - playstead-mac/Playstead/Adapter/AdapterHost.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Design/DesignTokens.swift
    - playstead-mac/Playstead/Library/GameListView.swift
    - playstead-mac/Playstead/Library/StatusSlotView.swift
    - playstead-mac/Playstead/Adapter/BiosDropTarget.swift
    - playstead-mac/Playstead/App/Info.plist
    - playstead-mac/scripts/sign-and-notarize.sh

key-decisions:
  - "Controller-mapping CLI injection uses a generic '-C input.<adapterInput>=<controllerInput>' override (mGBA's own general -C key=value mechanism, the same flag the pin already uses for savegamePath) because the pin's controller_mapping config key is recorded 'not_probed_no_hardware_available' — the wiring itself is proven and tested; whether mGBA's runtime reads that specific key name is honestly unverified pending real hardware"
  - "AppEnvironment marked @MainActor so ControllerHost/MotionPreference (both @MainActor @Observable) can be constructed at application-launch time rather than lazily inside a settings view, per D-14's 'known before the window opens' requirement"
  - "AccessibilityAudit is a declarative manifest walk over real view logic/data, not a live rendered NSAccessibility tree — this test target is headless-only (no XCUITest host), matching FilterChipRow.isSelected's pre-existing documented precedent for testing logic over a rendered tree"
  - "Info.plist gained explicit CFBundleIdentifier/CFBundleExecutable/etc. keys — GENERATE_INFOPLIST_FILE=NO means Xcode never injects them into a static plist, and their absence silently never mattered for `xcodebuild build`/`test` but broke `xcodebuild archive` the first time this plan actually exercised the release pipeline"
  - "sign-and-notarize.sh captures codesign/spctl output into a variable before grep -q rather than piping live, fixing a real SIGPIPE-vs-pipefail bug where an early grep -q match on a still-writing producer was misreported as a failure"

requirements-completed: [PLAY-04, PLAY-05, QUAL-01]

coverage:
  - id: D1
    description: "Controller lifecycle: connect, live-test, assign, remap, reset, and non-modal disconnect recovery that never strands keyboard/pointer input"
    requirement: "PLAY-04"
    verification:
      - kind: unit
        ref: "PlaysteadTests/ControllerTests/ControllerHostTests.swift (13 tests covering every <behavior> bullet plus the config-injection and store-restart acceptance criteria)"
        status: pass
      - kind: other
        ref: "xcodebuild test -scheme Playstead (full suite)"
        status: pass
    human_judgment: true
    rationale: "The plan 03-01 spike recorded controller connect/disconnect recovery as FAIL/unproven — no physical or paired controller was available in this execution environment (03-SPIKE-REPORT.md probe 5). All logic is fully tested against an injectable ControllerInputSource; whether real hardware behaves as simulated remains unverified pending physical-device testing, so a human must confirm on real hardware before PLAY-04 is claimed complete."
  - id: D2
    description: "Directional-pad/shoulder navigation model and the accessibility/motion floor across every Mac surface"
    requirement: "QUAL-01"
    verification:
      - kind: unit
        ref: "PlaysteadTests/AccessibilityTests/AccessibilityAuditTests.swift (16 tests: card/list/sidebar/shelf/readiness/controller/search/filter/BIOS-chooser labeling, status distinctness without color alone, tab-order-matches-declared-order, reduced-motion duration + determinate progress independence, docs content)"
        status: pass
      - kind: other
        ref: "xcodebuild test -scheme Playstead (full suite, 189/189)"
        status: pass
    human_judgment: true
    rationale: "The audit is an automated declarative-manifest tree-walk (this headless-only test target has no live NSAccessibility tree to inspect), not a third-party conformance assessment or a live screen-reader session — a human should still confirm the experience end-to-end with VoiceOver and a keyboard-only pass, as docs/ACCESSIBILITY.md states."
  - id: D3
    description: "Dev-signed, hardened-runtime release pipeline; relaunch survives an application restart with zero network calls; orphan prevention on quit; honest support documentation"
    requirement: "PLAY-05"
    verification:
      - kind: unit
        ref: "PlaysteadTests/AdapterTests/RelaunchTests.swift (2 tests: store-restart relaunch readiness with network stubbed to fail; registered-process termination on application termination)"
        status: pass
      - kind: other
        ref: "playstead-mac/scripts/build-release.sh + scripts/sign-and-notarize.sh run end-to-end against the dev-signing identity, producing a hardened-runtime, non-sandboxed, no-nested-bundle .app"
        status: pass
    human_judgment: true
    rationale: "Notarization is DEFERRED — requires paid Apple Developer Program enrollment (owner decision, 2026-08-30). Gatekeeper acceptance without user override and a signed-and-notarized build's actual launch/exit/quit/server-restart/relaunch cycle with the real emulator are recorded as unproven in this environment, not faked; a human must run the full cycle once a paid membership and real hardware/emulator install are available."

duration: 50min
completed: 2026-08-31
status: complete
---

# Phase 3 Plan 10: Controller Lifecycle, Accessibility Floor, and Dev-Signed Release Summary

**Full controller lifecycle behind an injectable input source, a declarative accessibility/motion audit proving no interactive element lacks a label and no status depends on color alone, and a hardened dev-signed release pipeline with a zero-network relaunch-after-restart proof — notarization and physical controller hardware both honestly recorded as unproven pending, respectively, paid Apple Developer Program enrollment and real hardware access**

## Performance

- **Duration:** ~50 min
- **Tasks:** 3
- **Files modified:** 23 (14 created, 9 modified)

## Accomplishments

- `ControllerHost` wraps the Game Controller framework behind an injectable `ControllerInputSource`, registered at `AppEnvironment` construction (application launch, never lazily inside settings) — publishing connect/disconnect/assignment state, live per-input test feedback, and a non-modal disconnect recovery banner that never disables any other control
- `ControllerMapping`/`ControllerMappingStore` persist a per-controller-product remap in the new `controller_mappings` SQLite table; reset restores and persists the default
- `AdapterHost.renderedLaunchArguments` is a pure, independently-testable method that injects the active controller mapping into the launch configuration through the pin's `cli_config_override` mechanism — proven by a test asserting the injected arguments contain the mapped values
- `MotionPreference` (moved out of `DesignTokens.swift` into its own file, now `@Observable`/injectable) exposes exactly one thing — a duration that collapses to zero under reduced motion — while `ProgressFillState` computes the determinate download fraction with no dependency on motion preference at all, so progress information is never removed
- `AccessibilityAudit` walks a declarative manifest of every top-level Mac surface's real accessible names/traits/declared order (matching this headless-only test target's established precedent), asserting zero unlabeled interactive elements, every status distinct without color alone, and tab order matching declared visual order
- `BiosDropTargetView` gains a keyboard-and-pointer "Choose File…" alternative to the drag, reaching the same `BiosDropTarget` validation path
- `scripts/sign-and-notarize.sh` now asserts the hardened-runtime flag, rejects any nested application bundle (T-03-28), and — once a paid membership is enrolled — requires a Developer ID Application identity and fails loudly unless `spctl` reports "accepted"; found and fixed a real SIGPIPE/`pipefail` bug in the process
- `RelaunchTests` closes and reopens every store against the same on-disk paths and proves a previously launch-ready game stays launch-ready with zero network requests, and proves a registered adapter process is terminated when the application termination handler runs (T-03-29)
- `docs/ACCESSIBILITY.md`, `docs/RELEASE.md`, and `docs/SUPPORT-MATRIX.md` state exactly what was proven — never broader

## Task Commits

Each task was committed atomically:

1. **Task 1: Controller lifecycle — connect, test, assign, remap, reset, and recover without stranding** - `97dfcea` (feat)
2. **Task 2: The accessibility and motion floor across every Mac surface** - `8684e67` (feat)
3. **Task 3: Notarized release, launch-exit-relaunch proof, and honest support documentation** - `191cc58` (feat)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `playstead-mac/Playstead/Controller/ControllerHost.swift` - ControllerDescriptor/ControllerConnectionState/InputPathAvailability/ControllerInputSource/GCControllerInputSource/ControllerHost
- `playstead-mac/Playstead/Controller/ControllerMapping.swift` - MappedInput/ControllerMapping, default mapping and remap/reset logic
- `playstead-mac/Playstead/Controller/ControllerMappingStore.swift` - SQLite-backed per-controller mapping persistence
- `playstead-mac/Playstead/Controller/ControllerSettingsView.swift` - assign/remap/reset UI
- `playstead-mac/Playstead/Controller/ControllerTestView.swift` - live button/axis press feedback
- `playstead-mac/Playstead/Controller/ControllerRecoveryBanner.swift` - non-modal disconnect notice
- `playstead-mac/Playstead/Design/MotionPreference.swift` - injectable reduced-motion duration + motion-independent ProgressFillState
- `playstead-mac/Playstead/Adapter/AdapterHost.swift` - renderedLaunchArguments/setControllerMapping
- `playstead-mac/Playstead/App/PlaysteadApp.swift` - @MainActor AppEnvironment gains controllerHost/controllerMappingStore/motionPreference, constructed at launch
- `playstead-mac/Playstead/Persistence/Migrations.swift` - controller_mappings table
- `playstead-mac/Playstead/Design/DesignTokens.swift` - old static MotionPreference enum removed (superseded)
- `playstead-mac/Playstead/Library/GameListView.swift` - combined accessibility element + title/system/status accessible name
- `playstead-mac/Playstead/Library/StatusSlotView.swift` - uses ProgressFillState for the determinate ring
- `playstead-mac/Playstead/Adapter/BiosDropTarget.swift` - keyboard/pointer file-chooser alternative
- `playstead-mac/Playstead/App/Info.plist` - CFBundleIdentifier and related keys required by xcodebuild archive
- `playstead-mac/scripts/sign-and-notarize.sh` - hardened-runtime/nested-bundle assertions, Developer ID + notarytool path, SIGPIPE fix
- `playstead-mac/.gitignore` - ignores build/ release output
- `playstead-mac/PlaysteadTests/ControllerTests/ControllerHostTests.swift` - 13 tests
- `playstead-mac/PlaysteadTests/AccessibilityTests/AccessibilityAuditTests.swift` - 16 tests
- `playstead-mac/PlaysteadTests/AdapterTests/RelaunchTests.swift` - 2 tests
- `playstead-mac/docs/ACCESSIBILITY.md`, `playstead-mac/docs/RELEASE.md`, `playstead-mac/docs/SUPPORT-MATRIX.md`

## Decisions Made

- Controller-mapping injection uses mGBA's own general `-C key=value` override mechanism under an `input.<adapterInput>` key, since the pin's `controller_mapping` config key was never probed against real hardware — the wiring is proven and tested; the exact key name's real-world effect is honestly unverified.
- `AppEnvironment` is now `@MainActor` so its two new `@Observable` main-actor-isolated dependencies (`ControllerHost`, `MotionPreference`) can be constructed eagerly at launch.
- `AccessibilityAudit` audits a declarative manifest built from real view logic, not a live rendered accessibility tree — this test target has no XCUITest host, matching the codebase's pre-existing `FilterChipRow.isSelected` precedent.
- Fixed `Info.plist`'s missing `CFBundleIdentifier` (and related keys) — silently harmless for `build`/`test`, but broke `xcodebuild archive` the first time the release pipeline was actually exercised in this plan.
- Fixed a SIGPIPE/`pipefail` bug in `sign-and-notarize.sh`: `codesign -dv ... | grep -q ...` could have `grep -q`'s early exit SIGPIPE the still-writing `codesign`, and `pipefail` then reported that as a failure. Now `codesign`/`spctl` output is captured into a variable first.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] BIOS drop target had no keyboard/pointer alternative to the drag**
- **Found during:** Task 2 (accessibility floor)
- **Issue:** `BiosDropTargetView` only accepted a drag — a drop target with no keyboard/pointer path excludes anyone who cannot perform a drag, violating the plan's own accessibility floor requirement.
- **Fix:** Added a "Choose File…" button opening an injectable file-chooser closure (production default: `NSOpenPanel`), reaching the same `BiosDropTarget.handle` validation path.
- **Files modified:** `playstead-mac/Playstead/Adapter/BiosDropTarget.swift`
- **Verification:** `AccessibilityAuditTests.testBiosDropTargetExposesAKeyboardReachableFileChooserControl` passes; full suite green.
- **Committed in:** `8684e67` (Task 2 commit)

**2. [Rule 2 - Missing Critical] GameListView rows had no combined accessibility element or composed accessible name**
- **Found during:** Task 2 (accessibility floor)
- **Issue:** Each list row was an `HStack` of separate `Text` elements with no `.accessibilityElement(children: .combine)` and no unified name — a screen reader would read fragmented, uncomposed fragments instead of one coherent title/system/status sentence.
- **Fix:** Added `.accessibilityElement(children: .combine)` and a composed accessible name matching `GameCardView`'s own rule.
- **Files modified:** `playstead-mac/Playstead/Library/GameListView.swift`
- **Verification:** `AccessibilityAuditTests.testGameListRowAccessibleNameContainsTitleSystemAndStatusSentence` passes.
- **Committed in:** `8684e67` (Task 2 commit)

**3. [Rule 3 - Blocking] `Info.plist` missing `CFBundleIdentifier` broke `xcodebuild archive`**
- **Found during:** Task 3 (exercising the release pipeline end-to-end for the first time)
- **Issue:** `GENERATE_INFOPLIST_FILE = NO` with a static `Info.plist` lacking `CFBundleIdentifier` never mattered for `xcodebuild build`/`test`, but `xcodebuild archive` failed with "Archive Missing Bundle Identifier."
- **Fix:** Added `CFBundleIdentifier`/`CFBundleExecutable`/`CFBundleName`/`CFBundlePackageType`/`CFBundleShortVersionString`/`CFBundleVersion`, all referencing existing build settings (never restated literals).
- **Files modified:** `playstead-mac/Playstead/App/Info.plist`
- **Verification:** `scripts/build-release.sh` now archives and exports successfully.
- **Committed in:** `191cc58` (Task 3 commit)

**4. [Rule 1 - Bug] `sign-and-notarize.sh`'s hardened-runtime/Developer-ID/Gatekeeper checks misreported success as failure**
- **Found during:** Task 3 (running the hardened script for the first time against a real dev-signed build)
- **Issue:** `codesign -dv ... | grep -q 'flags=0x10000(runtime)'` (and two similar checks) piped live into `grep -q`. `grep -q` exits on its first match without draining the rest of the stream, which can SIGPIPE the still-writing `codesign`/`spctl` process; under `set -o pipefail`, that producer's non-zero (SIGPIPE) exit status was reported as the pipeline's failure even though the match was found.
- **Fix:** Capture `codesign`/`spctl` output into a variable first, then `grep -q` against the captured string (no live pipe).
- **Files modified:** `playstead-mac/scripts/sign-and-notarize.sh`
- **Verification:** `./scripts/sign-and-notarize.sh` now runs to completion against the dev-signed build with correct pass/fail reporting at every assertion.
- **Committed in:** `191cc58` (Task 3 commit)

---

**Total deviations:** 4 auto-fixed (2 missing-critical accessibility gaps, 1 blocking release-pipeline config bug, 1 blocking script logic bug)
**Impact on plan:** All four were necessary for correctness (accessibility floor, a working release pipeline, a script that reports truthfully). No scope creep — every fix stayed within the file each deviation actually touched.

## Issues Encountered

None beyond the four auto-fixed deviations above.

## Known Stubs / Deferred Claims

- **Notarization is DEFERRED — requires paid Apple Developer Program enrollment (owner decision, 2026-08-30).** This installation has no Developer ID Application certificate and no `notarytool` credential profile. `scripts/sign-and-notarize.sh`'s notarization branch (Developer ID identity check, `notarytool submit --wait`, `stapler staple`, the Gatekeeper "accepted" assertion) is written and will run unchanged once real credentials are configured, but was never exercised in this run — the dev-signed branch was exercised instead, end-to-end, successfully.
- **Controller hardware remains unproven.** The plan 03-01 spike recorded controller connect/disconnect recovery as FAIL/unproven for lack of any physical or paired controller in the execution environment (03-SPIKE-REPORT.md probe 5). Every piece of `ControllerHost`'s logic is fully tested against an injectable `ControllerInputSource`; real hardware behavior is honestly unverified pending physical-device testing.
- **The exact real-world effect of the controller-mapping CLI injection is unverified.** The pin's `controller_mapping` config key is recorded `not_probed_no_hardware_available` — `AdapterHost.renderedLaunchArguments` injects a generic `-C input.<adapterInput>=<controllerInput>` override (mGBA's own general config-override mechanism), and a test proves the wiring is correct; whether mGBA's runtime actually reads that specific key name has never been confirmed against real hardware.
- **The accessibility audit is automated + a documented human-check recommendation, not a third-party conformance assessment.** `AccessibilityAudit` walks a declarative manifest (this test target has no XCUITest host); `docs/ACCESSIBILITY.md` states this limitation explicitly.

## User Setup Required

None - no external service configuration required. (A future paid Apple Developer Program enrollment would require setting `PLAYSTEAD_DEV_ID_APP`/`PLAYSTEAD_TEAM_ID`/`PLAYSTEAD_NOTARY_PROFILE` per `docs/RELEASE.md` — not needed for this dev-signed posture.)

## Next Phase Readiness

- The Mac offline-play vertical slice is functionally and behaviorally complete for this milestone: library, downloads, curation, sync, adapter install/BIOS/readiness, controller lifecycle, and the accessibility/motion floor are all built and tested (189/189 in the full `xcodebuild test` suite).
- Two claims remain honestly open pending resources this environment does not have: a paid Apple Developer Program membership (notarization) and real controller hardware (physical-device verification of PLAY-04). Both are documented, neither is faked, and both paths are fully built and ready to exercise the moment those resources exist.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-08-31*

## Self-Check: PASSED

- All 23 key files (14 created, 9 modified) confirmed present on disk.
- All 3 commits (`97dfcea`, `8684e67`, `191cc58`) confirmed in `git log`.
- `xcodebuild test -scheme Playstead` (full suite): 189/189 passing.
- `playstead-mac/scripts/build-release.sh` + `playstead-mac/scripts/sign-and-notarize.sh` run end-to-end against the dev-signing identity, producing a hardened-runtime, non-sandboxed, no-nested-bundle `.app`; `spctl` correctly reports "rejected" for this unnotarized build (expected and documented, not a failure).
