---
status: diagnosed
trigger: "Phase 03 must verify controller connect/disconnect recovery through an automated integration/E2E seam, without physical hardware UAT."
created: 2026-09-19T15:39:29Z
updated: 2026-09-19T16:04:00Z
---

## Current Focus

hypothesis: CONFIRMED — automated proof is blocked by an AND-gate: tests inject callbacks below GameController instead of creating a virtual HID; the UI-test runner lacks the entitlement required to publish one; and the recovery banner is not composed into any production surface, leaving no end-to-end recovery oracle.
test: Existing fake-based suite passed 12/12 while static tracing proved it never constructs a GCController or IOHIDUserDevice; current-process IOHID creation returned nil exactly as the missing entitlement predicts.
expecting: diagnosis complete
next_action: return root-cause report to the orchestrator; do not modify product code
bug_class: bohrbug
candidate_causes:
  - code: no virtual HID fixture/helper drives the production GCControllerInputSource boundary
  - config: a suitable integration/E2E test may exist but be omitted from Unit/UI test plans or CI required-test gates
  - environment: hosted macOS runners may forbid IOHIDUserDevice or hide it from GameController enumeration
and_gate: yes; a credible virtual-device E2E requires both producer code and the restricted test-runner entitlement, and the full non-modal UI claim also needs an observable production call site

## Symptoms

expected: Controller connect/disconnect/reconnect recovery is exercised through an automated integration seam that reaches GameController enumeration and preserves keyboard/pointer input.
actual: User requires zero human UAT; physical-controller-only evidence is not acceptable.
errors: None reported.
reproduction: Test 8 in 03-UAT.md.
started: Discovered during UAT.

## Eliminated

- hypothesis: A controller integration/E2E test already exists but is merely omitted from a test plan or CI required-test list.
  evidence: No IOHIDUserDevice or GCControllerInputSource construction exists in any test. Unit includes the whole PlaysteadTests target by default and UI explicitly lists suites, but there is no controller E2E suite to register.
  timestamp: 2026-09-19T15:58:30Z

- hypothesis: App Sandbox alone prevents the existing UI-test runner from publishing a virtual HID.
  evidence: PlaysteadUITests.entitlements explicitly disables App Sandbox. The actual creation gate is the separate com.apple.developer.hid.virtual.device entitlement named by the installed SDK header, and it is absent.
  timestamp: 2026-09-19T15:58:30Z

## Evidence

- timestamp: 2026-09-19T15:39:29Z
  checked: .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md item 8
  found: The UAT record explicitly says no virtual HID test device or lifecycle plumbing exists; current evidence is blocked on physical controller hardware.
  implication: The gap is an absent automated integration seam, not a reported runtime failure.

- timestamp: 2026-09-19T15:51:00Z
  checked: .planning/debug/knowledge-base.md
  found: No semantically or keyword-related prior controller/HID resolution exists.
  implication: There is no known-pattern shortcut; investigate the current test architecture directly.

- timestamp: 2026-09-19T15:51:00Z
  checked: playstead-mac/Playstead/Controller/ControllerHost.swift and PlaysteadTests/ControllerTests/ControllerHostTests.swift
  found: Production enumeration and notifications exist only in GCControllerInputSource; every connect/disconnect/reconnect test constructs ControllerHost(source: FakeControllerInputSource()). The fake calls captured closures directly and never creates a GCController.
  implication: Existing green tests prove ControllerHost state transitions after callbacks, but cannot prove GameController discovers a device or emits callbacks for attach/detach.

- timestamp: 2026-09-19T15:51:00Z
  checked: repository-wide IOHIDUserDevice and GCExtendedGamepad/valueChangedHandler search
  found: IOHIDUserDevice appears only in UAT planning text, not source or tests. No production or test code installs GCExtendedGamepad value handlers; reportInput is called only by unit tests despite its comment claiming production wiring.
  implication: There is neither a virtual-device producer nor a real input-event bridge; the current abstraction begins downstream of the framework boundary it needs to verify.

- timestamp: 2026-09-19T15:51:00Z
  checked: AppEnvironment composition and controller UI call sites
  found: AppEnvironment hard-codes let controllerHost = ControllerHost(), so the shipped and UI-test app do use the production GCControllerInputSource. ControllerSettingsView is reachable through ReadinessSheetView, but ControllerRecoveryBanner has no call site anywhere in the app.
  implication: A system-visible virtual HID could exercise production enumeration in an app/UI test without injecting a fake, but the promised recovery affordance itself is currently unreachable and cannot be asserted end to end.

- timestamp: 2026-09-19T15:51:00Z
  checked: Playstead and PlaysteadUITests entitlements plus xcodeproj target topology
  found: Both the app and UI-test runner explicitly disable App Sandbox; the unit and UI targets are registered in the shared scheme. No IOKit-backed HID helper/fixture target or source exists.
  implication: The repository topology does not show a sandbox/config prohibition; the missing test producer and assertions are the leading cause.

- timestamp: 2026-09-19T15:51:00Z
  checked: spectrum-based fault localization eligibility
  found: No failing controller test exists; this is a missing-coverage UAT gap, and no per-test failing spectrum is available.
  implication: SBFL is inapplicable; use deterministic boundary tracing instead.

- timestamp: 2026-09-19T15:58:30Z
  checked: installed macOS SDK IOHIDUserDevice.h and a disposable Swift runtime probe
  found: The SDK states IOHIDUserDeviceCreateWithProperties requires com.apple.developer.hid.virtual.device. The API imports successfully, but creation from the current unentitled process returns nil. Neither Playstead.entitlements nor PlaysteadUITests.entitlements grants that entitlement.
  implication: Virtual HID is a viable API seam but cannot work in the current signed test topology without a test-only entitlement; absence of App Sandbox is insufficient.

- timestamp: 2026-09-19T15:58:30Z
  checked: Unit/UI test plans and scripts/ci/run-mac-verification.sh
  found: Unit runs the PlaysteadTests target broadly, UI uses an explicit suite list, and CI has no controller integration required-test identifier. No hidden controller integration suite exists to register.
  implication: The gap is implementation plus gate wiring, not only a skipped test-plan entry.

- timestamp: 2026-09-19T16:04:00Z
  checked: xcodebuild test -testPlan Unit -only-testing:PlaysteadTests/ControllerHostTests
  found: All 12 selected tests passed with zero failures. The lifecycle cases instantiate FakeControllerInputSource and directly call simulateConnect/simulateDisconnect; the run produces no GameController enumeration or virtual HID evidence.
  implication: The suite reliably proves downstream state logic, but its success is orthogonal to the missing framework-level and E2E proof.

## Resolution

root_cause: Existing controller tests terminate at FakeControllerInputSource and directly invoke lifecycle callbacks, bypassing GCController.controllers() and GCController connect/disconnect notifications; no IOHIDUserDevice fixture exists, and the unsandboxed UI-test runner lacks the SDK-required com.apple.developer.hid.virtual.device entitlement, so it cannot publish a test gamepad. For the full E2E claim, ControllerRecoveryBanner is also unreachable because no production view composes it, while keyboard/pointer availability is currently proved only by constant booleans rather than real UI actions.
fix: Not applied (diagnose-only). Smallest credible seam is a test-only IOHIDUserDevice gamepad fixture owned by the PlaysteadUITests runner, the virtual-device entitlement on that non-distributed runner, and one UI suite that launches the real app/GCControllerInputSource, opens the reachable controller-settings surface, destroys and recreates the HID, observes connect/disconnect/reconnect, and performs actual keyboard and pointer actions during the disconnected interval. Compose the existing recovery banner into the shell if its visible non-modal affordance is part of the acceptance oracle; register the suite in UI.xctestplan and CI's required-test gate.
verification: Diagnosis verified by full source-boundary trace, installed-SDK entitlement contract, a runtime IOHID creation probe returning nil without the entitlement, test-plan/CI inspection, and 12/12 existing ControllerHostTests passing only through the fake seam.
files_changed: []
