---
status: diagnosed
trigger: "Phase 03 must verify the real GameController lifecycle through an automated seam, including live-test, assign, remap, and reset."
created: 2026-09-19T15:44:08Z
updated: 2026-09-19T16:06:00Z
---

## Current Focus

hypothesis: CONFIRMED — isolated leaf types and fake-source tests were mistaken for an assembled controller lifecycle: production has enumeration/assignment but no GameController input-event bridge, and the only ControllerSettingsView call site leaves live-test/remap/reset as no-op defaults
test: Static production-path trace plus the unchanged 12-test ControllerHost suite; the suite passed while demonstrably bypassing GCControllerInputSource and the production ControllerSettingsView call site
expecting: diagnosis complete
next_action: return root-cause report to the orchestrator; do not modify product code
bug_class: bohrbug
candidate_causes:
  - code: lifecycle actions may exist only behind injected ControllerHost/unit-test seams rather than production GameController events
  - config: integration/UI coverage may exist but be absent from test plans or CI gates
  - environment: GameController production behavior may require a virtual HID device unavailable to the current runner
and_gate: yes; live-test requires a real GameController input bridge plus virtual-device producer/entitlement, while remap/reset additionally require production callbacks/state composition and an XCUITest that drives those controls

## Symptoms

expected: Live-test, assign, remap, and reset are driven automatically through the production controller lifecycle and UI seams.
actual: User requires zero human UAT; injectable-source unit coverage does not prove production GameController integration.
errors: None reported.
reproduction: Test 9 in 03-UAT.md.
started: Discovered during UAT.

## Eliminated

- hypothesis: G-03-9 is only blocked by lack of a physical or virtual controller; once a GameController enumerates, the existing UI lifecycle works end to end.
  evidence: The production source never forwards element changes, ReadinessSheetView supplies only onAssign, onRemap/onReset/onOpenTestView remain no-ops, and ControllerTestView has no production call site.
  timestamp: 2026-09-19T16:06:00Z

- hypothesis: A controller lifecycle UI/E2E suite already exists but is omitted from CI or a test plan.
  evidence: UI.xctestplan contains no controller lifecycle suite; repository-wide UI-test search finds only SurfaceAccessibilityTests opening the empty controller-settings surface; CI requires only the aggregate surface inventory, not any controller behavior identifier.
  timestamp: 2026-09-19T16:06:00Z

- hypothesis: Current unit coverage proves the production composition root and UI callbacks because ControllerHostTests are app-hosted XCTest cases.
  evidence: All 12 tests passed, but they construct FakeControllerInputSource, call host.reportInput directly, mutate ControllerMapping/ControllerMappingStore directly, and never instantiate ReadinessSheetView, ControllerSettingsView, GCControllerInputSource, or an IOHID device.
  timestamp: 2026-09-19T16:06:00Z

## Evidence

- timestamp: 2026-09-19T15:50:00Z
  checked: .planning/debug/knowledge-base.md
  found: No prior resolved session matches controller lifecycle, GameController, virtual HID, remapping, or reset.
  implication: There is no resolved known-pattern shortcut; G-03-8 is related active diagnosis evidence, not a knowledge-base resolution.

- timestamp: 2026-09-19T15:50:00Z
  checked: .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md item 9 and Gaps entry G-03-9
  found: The acceptance claim explicitly requires production lifecycle and UI seams; the current record says only injectable ControllerInputSource logic is fully tested and names a future IOHIDUserDevice plus XCUITest route.
  implication: The missing artifact is automated boundary coverage, not an observed exception or flaky behavior; SBFL is inapplicable because there is no failing test spectrum.

- timestamp: 2026-09-19T15:50:00Z
  checked: .planning/debug/g-03-8-controller-automation.md
  found: G-03-8 confirmed no IOHIDUserDevice fixture, no virtual-device entitlement, and no production GCExtendedGamepad valueChangedHandler; AppEnvironment does instantiate the production GCControllerInputSource.
  implication: G-03-9 shares the upstream virtual-device prerequisite, but must separately establish the action/UI chain for live-test, assignment, remapping, and reset.

- timestamp: 2026-09-19T15:58:00Z
  checked: playstead-mac/Playstead/Controller/ControllerHost.swift and repository-wide reportInput/GCExtendedGamepad search
  found: GCControllerInputSource enumerates controllers and observes connect/disconnect only. It installs no GCExtendedGamepad valueChangedHandler or per-element handlers. ControllerHost.reportInput is called only in ControllerHostTests.
  implication: The production GameController path cannot drive ControllerHost.liveInputs, so ControllerTestView cannot provide real live-test feedback even if made reachable.

- timestamp: 2026-09-19T15:58:00Z
  checked: playstead-mac/Playstead/Readiness/ReadinessSheetView.swift and ControllerSettingsView.swift
  found: The only production ControllerSettingsView call site supplies onAssign only. onRemap, onReset, and onOpenTestView keep their default no-op closures; ControllerTestView has no call site anywhere.
  implication: Assignment can mutate ControllerHost, but remap, reset, and opening live test are dead controls in the shipped UI. This is a production wiring defect, not merely absent hardware verification.

- timestamp: 2026-09-19T15:58:00Z
  checked: production uses of ControllerMappingStore.save/reset, ControllerMapping.remapping, ControllerTestView, and ControllerRecoveryBanner
  found: No shipped production call site invokes save, reset, remapping, ControllerTestView, or ControllerRecoveryBanner. Those symbols are reached only by unit tests or remain uninstantiated.
  implication: The implementation summary's full-lifecycle claim was inferred from isolated leaf types; there is no continuous production action path for three of the four G-03-9 behaviors.

- timestamp: 2026-09-19T15:58:00Z
  checked: PlaysteadUITests/SurfaceAccessibilityTests.swift, TestPlans/UI.xctestplan, and scripts/ci/run-mac-verification.sh
  found: Existing UI automation opens controller settings only under a deterministic profile with no controller and asserts the surface exists. It does not find or operate assignment/remap/reset/live-test controls. No controller lifecycle E2E suite or required-test identifier exists.
  implication: Current UI coverage proves route reachability/accessibility inventory, not behavior. A newly added suite must be selected in UI.xctestplan and fail-closed in the CI required-test list.

- timestamp: 2026-09-19T15:58:00Z
  checked: PlaysteadUITests.entitlements and G-03-8 installed-SDK evidence
  found: The UI runner is unsandboxed but lacks com.apple.developer.hid.virtual.device; G-03-8's direct probe showed IOHIDUserDevice creation returns nil without it.
  implication: The credible E2E producer is blocked until a test-only entitlement/profile can create the virtual gamepad; this is a shared prerequisite, not the G-03-9-specific production wiring defect.

- timestamp: 2026-09-19T15:58:00Z
  checked: ControllerDescriptor identity and ControllerMappingStore key contract
  found: Production maps a GCController to a run-local id using ObjectIdentifier and a counter, while persistence is documented and tested as keyed by a stable controller product identifier. Unit tests use a fixed synthetic id and never exercise identity across app relaunch.
  implication: Even after UI callbacks are wired, production mapping persistence across application restart is not proven by the current identity scheme and should be included in the integration architecture's relaunch oracle or explicitly narrowed.

- timestamp: 2026-09-19T16:01:00Z
  checked: xcodebuild test -testPlan Unit -only-testing:PlaysteadTests/ControllerHostTests
  found: Test execution was cancelled before compilation because the project carries DEVELOPMENT_TEAM=REPLACE_WITH_YOUR_TEAM_ID and no matching Mac Development certificate exists.
  implication: This is a local signing configuration blocker, not evidence for or against the controller hypothesis; rerun with the installed team override used by project verification scripts.

- timestamp: 2026-09-19T16:06:00Z
  checked: xcodebuild test with CI's ad-hoc signing overrides, Unit plan, only PlaysteadTests/ControllerHostTests
  found: All 12 tests executed and passed in 0.055 seconds. The live-input test called ControllerHost.reportInput directly; remap/reset tests called value/store methods directly; lifecycle tests used FakeControllerInputSource callbacks.
  implication: The green suite is reliable downstream unit evidence but is orthogonal to production GameController event delivery and shipped UI action wiring, confirming the coverage-boundary diagnosis.

## Resolution

root_cause: The Phase 03 controller implementation stopped at independently testable leaf types and never assembled them into one production lifecycle. GCControllerInputSource wraps only controllers() plus connect/disconnect notifications and never installs GCExtendedGamepad input handlers, so real button/axis events cannot reach ControllerHost.reportInput/liveInputs. The sole production ControllerSettingsView call site supplies onAssign but leaves onRemap, onReset, and onOpenTestView at no-op defaults; ControllerTestView has no production caller. Existing unit tests conceal this by directly invoking reportInput, ControllerMapping.remapping, and ControllerMappingStore.save/reset through FakeControllerInputSource. Automated framework-level proof is additionally absent because there is no IOHIDUserDevice fixture and the UI-test runner lacks the SDK-required com.apple.developer.hid.virtual.device entitlement. The persisted mapping contract has a further unproven identity seam: production keys it by a run-local ObjectIdentifier/counter id while the tests use a fixed synthetic product id.
fix: Not applied (diagnose-only). Smallest credible closure is (1) extend the production ControllerInputSource/GCControllerInputSource seam to forward named GCExtendedGamepad press/release/axis events for initial and newly connected devices into ControllerHost; (2) give ReadinessSheetView owned observable mapping/test-view state and wire ControllerSettingsView.onAssign/onRemap/onReset/onOpenTestView to ControllerHost, ControllerMappingStore, refreshActiveControllerMapping, and a reachable ControllerTestView; (3) define or deliberately narrow the stable controller identity/persistence contract; (4) add a test-only IOHIDUserDevice gamepad producer in an entitled, non-distributed UI-test runner or signed helper, failing closed if creation/enumeration fails; and (5) add one production-app XCUITest journey that creates one or preferably two virtual pads, observes enumeration, opens live test, injects press/release and asserts the rendered state, assigns the other pad, remaps and observes persisted UI plus adapter-facing evidence, resets and observes defaults, then relaunches if persistence remains claimed. Select the suite in UI.xctestplan and add exact required-test identifiers to run-mac-verification.sh. Reuse G-03-8's virtual-HID fixture/entitlement work, but keep this journey's action/UI oracles distinct.
verification: Diagnosis verified by complete controller/source/view/test path tracing, repository-wide call-site searches, UI plan/CI inspection, G-03-8's SDK entitlement/runtime probe evidence, and an unchanged selected unit run with all 12 ControllerHostTests green despite bypassing every missing production seam.
files_changed: []
