---
status: diagnosed
trigger: "Replace the remaining controller and experiential VoiceOver requirements with repeatable objective evidence so no human UAT is required."
created: 2026-09-19T16:15:00-04:00
updated: 2026-09-19T16:46:00-04:00
---

## Current Focus

hypothesis: CONFIRMED — zero-human completion is blocked by an AND-gate: Test 10 and its fail-closed validator define subjective VoiceOver comprehension as required acceptance, while the separate d-pad/shoulder clause has neither a production controller-navigation event bridge nor virtual-HID E2E coverage; the existing live accessibility suite proves only the objective keyboard/AX floor
test: validator meta-tests passed while explicitly pinning the blocked experiential record; complete source trace found no d-pad/shoulder navigation handlers; CI/test-plan trace showed the only required Test 10 identifier is the keyboard/live-tree aggregate
expecting: diagnosis complete
next_action: return root-cause report to the orchestrator; do not modify product or acceptance artifacts
bug_class: bohrbug
candidate_causes:
  - code: no production GameController input-event bridge maps d-pad/shoulders/menu to navigation actions
  - config: CI and UAT validators require only the keyboard/live-tree suite and explicitly require the physical-controller/experiential record to remain blocked
  - environment: virtual HID creation requires a missing test-runner entitlement, established by G-03-8/G-03-9
  - data: accessibility labels/roles/values can be machine-checked, but subjective comprehension has no finite expected-output dataset or objective oracle
and_gate: yes; zero-human completion requires both a real automated controller-navigation path and narrowing the accessibility acceptance boundary from subjective experience to objective semantics without claiming comprehension

## Symptoms

expected: Controller navigation and accessibility have repeatable objective acceptance evidence, with no subjective human listening checkpoint required for phase completion.
actual: The current contract retains physical-controller and experiential VoiceOver human judgment as completion gates.
errors: None reported.
reproduction: Test 10 in 03-UAT.md.
started: Discovered during UAT.

## Eliminated

- hypothesis: The existing SurfaceAccessibilityTests aggregate already proves controller navigation because it covers every Mac surface.
  evidence: The suite drives Tab, Shift-Tab, Space, arrow-key list selection, roles/labels/values/frames, focus containment/restoration, and public accessibility audits. It creates no controller, sends no HID reports, and reaches no GCController input handler.
  timestamp: 2026-09-19T16:46:00-04:00

- hypothesis: The remaining VoiceOver experience can be replaced by a speech-output assertion without narrowing the claim.
  evidence: Pronunciation, rotor usefulness, sentence quality, comprehension, and navigation intuition have no specified deterministic oracle in the contract; docs/ACCESSIBILITY.md correctly states that the live public audit does not establish them.
  timestamp: 2026-09-19T16:46:00-04:00

- hypothesis: Removing the blocked Test 10 sub-record alone would honestly produce zero-human CI.
  evidence: That would leave the unimplemented d-pad/shoulder production path unproved and would silently convert subjective comprehension from “unclaimed” to an apparent pass. Existing validators intentionally reject precisely that evidence-boundary collapse.
  timestamp: 2026-09-19T16:46:00-04:00

- hypothesis: The controller portion is only an environment limitation caused by unavailable physical hardware.
  evidence: Independent of hardware availability, production has no GCExtendedGamepad event forwarding, no shoulder navigation dispatcher, and no controller UI/E2E suite. G-03-8 additionally proved the virtual-HID runner lacks its required entitlement.
  timestamp: 2026-09-19T16:46:00-04:00

## Evidence

- timestamp: 2026-09-19T16:15:00-04:00
  checked: .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md Test 10 and gap G-03-10
  found: Test 10 expects d-pad/shoulder and keyboard navigation plus a live VoiceOver pass that reads each surface sensibly; the gap asks for objective evidence without subjective human listening.
  implication: The acceptance text itself mixes independently testable mechanics with an experiential quality judgment and must be decomposed before zero-human CI can be honest.

- timestamp: 2026-09-19T16:22:00-04:00
  checked: .planning/debug/knowledge-base.md and related G-03-8/G-03-9 diagnoses
  found: No resolved knowledge-base entry matches this gap. G-03-8 and G-03-9 independently confirmed there is no virtual-HID producer/entitlement, no production GameController input-event bridge, and no controller lifecycle UI E2E suite.
  implication: Reuse those direct findings for the controller half, but separately diagnose Test 10's accessibility oracle and contract wording.

- timestamp: 2026-09-19T16:22:00-04:00
  checked: 03-UAT.md Test 10 and 03-UI-SPEC.md Accessibility Floor
  found: The UI spec defines objective properties (reachability/operability, visible focus, accessible names, hidden decoration, non-color state, reduced motion, text scaling), but UAT Test 10 adds a live VoiceOver pass that must read every surface “sensibly”; its blocked record explicitly retains pronunciation, rotor behavior, sentence quality, and comprehension as human judgment.
  implication: The locked design floor is largely machine-testable, while “sensibly” and comprehension are not falsifiable machine oracles; retaining them in expected acceptance necessarily retains human completion gating.

- timestamp: 2026-09-19T16:34:00-04:00
  checked: production search for focusSection/onMoveCommand/GameController d-pad/shoulder handlers
  found: A few views declare SwiftUI focus sections, but there is no onMoveCommand/controller navigation dispatcher and no GCExtendedGamepad valueChangedHandler or per-element handler anywhere in production. Shoulder names exist only in the mapping vocabulary; d-pad input reaches ControllerHost.reportInput only in unit tests.
  implication: “Every Mac surface is navigable by d-pad/shoulder buttons” is not currently an automated-evidence-only gap; the claimed production navigation bridge is absent and must be implemented before it can be objectively verified.

- timestamp: 2026-09-19T16:34:00-04:00
  checked: SurfaceAccessibilityTests, UITestHarness, UI.xctestplan, and run-mac-verification.sh
  found: The UI plan selects SurfaceAccessibilityTests and CI fail-closes on testKeyboardOnlySurfaceInventoryAndLiveAudit. That suite drives real Tab/Shift-Tab/Space and audits 20 named production surfaces for roles, labels, values, finite frames, focus containment/restoration, and six public XCUITest audit categories; it sends no controller input and invokes no VoiceOver speech/rotor workflow.
  implication: Existing CI is strong objective evidence for keyboard and accessibility-tree semantics, but its evidence boundary is correctly narrower than controller navigation or experiential comprehension.

- timestamp: 2026-09-19T16:34:00-04:00
  checked: docs/ACCESSIBILITY.md and AccessibilityAuditTests.swift
  found: The docs honestly disclaim speech quality, rotor usefulness, navigation intuition, and human VoiceOver usability. The older unit audit is a declarative manifest and includes several literal/synthetic label assertions; the later live XCUITest suite is the stronger production-tree evidence.
  implication: Zero-human acceptance should rely on the live-tree suite and concrete property oracles, not promote declarative or literal checks into a subjective comprehension claim.

- timestamp: 2026-09-19T16:40:00-04:00
  checked: validate-phase-3-uat-evidence.py and its unit suite
  found: All 17 validator unit tests pass. validate_checkpoint_10 explicitly requires a blocked residual record and the exact physical-controller and experiential-VoiceOver tokens; its mutation test rejects removing either token. The validator run against the current UAT stops earlier because it still requires obsolete frontmatter status partial while UAT now says testing.
  implication: The human gate is encoded in executable policy, not only prose. Honest closure must update the validator and negative controls together, while also repairing its stale frontmatter assumption.

- timestamp: 2026-09-19T16:42:00-04:00
  checked: plan-05-surface-contract-test.sh and scripts/check-uat-tally.sh
  found: The static surface contract passes and explicitly requires docs to contain “experiential”, “VoiceOver”, and “Controller hardware itself remains unproven”. The UAT tally guard fails because the document now has four issue results but no issue summary field.
  implication: Multiple planning/CI guards preserve the old human-boundary language, and the UAT summary schema has drifted during gap capture; contract closure must update these gates rather than editing UAT prose alone.

- timestamp: 2026-09-19T16:44:00-04:00
  checked: REQUIREMENTS.md, 03-CONTEXT.md, ROADMAP.md, and 03-VERIFICATION.md
  found: QUAL-01 is already marked Complete based on objective accessibility semantics, while PLAY-04 remains Pending. D-14 and the Phase 3 plan promise d-pad focus plus shoulder cycling, but source does not implement those paths. 03-VERIFICATION still says no live NSAccessibility tree was exercised even though the hosted SurfaceAccessibilityTests now audit the live tree.
  implication: The truthful zero-human contract is to keep subjective experience outside acceptance, preserve its explicit non-claim in docs, close controller behavior only through the shared G-03-8/G-03-9 production/virtual-HID work, and refresh stale verification language to cite the live-tree evidence.

## Resolution

root_cause: Test 10 conflates three evidence classes under one completion gate. First, objective accessibility properties are already machine-verifiable and substantially covered by a hosted live XCUITest: keyboard traversal/activation, roles, labels, values, hierarchy, finite frames, focus containment/restoration, contrast, hit regions, descriptions, actions, and parent/child structure. Second, the wording “a live VoiceOver pass reads each surface sensibly” expands that floor into pronunciation, rotor usefulness, sentence quality, comprehension, and navigation intuition — subjective outcomes with no falsifiable machine oracle — and validate-phase-3-uat-evidence.py plus plan-05-surface-contract-test.sh deliberately pin that residue as a required blocker. Third, the controller half is not merely missing physical evidence: production has focusSection declarations but no GCExtendedGamepad input forwarding or d-pad/shoulder navigation dispatcher, no virtual-HID fixture/entitlement, and no fail-closed controller-navigation UI test. Consequently the keyboard/live-tree aggregate cannot honestly satisfy the current combined wording, and deleting the human checkpoint would falsely claim both comprehension and controller behavior.
fix: Not applied (diagnose-only). Honest zero-human closure requires two coordinated changes. For accessibility, rewrite Test 10/verification acceptance as an explicit property contract: every inventoried production surface has test-owned keyboard reachability and activation, correct roles/names/state/value/hierarchy, visible/contained/restored focus, non-color distinctions, public audit categories, reduced-motion behavior, and bounded text/contrast/hit regions. Treat pronunciation, rotor utility, comprehension, and navigation intuition as explicitly unclaimed/non-gating product-research questions, not “automated”; retain that limitation in docs/ACCESSIBILITY.md. Update validate-phase-3-uat-evidence.py, its mutation tests, plan-05-surface-contract-test.sh, 03-UAT.md, and stale 03-VERIFICATION.md language to require the objective evidence plus the explicit non-claim rather than a blocked human record. For controller navigation, reuse the G-03-8/G-03-9 virtual-HID architecture: implement production GameController element forwarding and explicit d-pad/shoulder/menu navigation actions, add a test-only entitled IOHIDUserDevice producer, drive the real app across an independently declared surface/action matrix, assert focus/action/sidebar changes after injected reports, and register exact required identifiers in UI.xctestplan and run-mac-verification.sh. Do not mark PLAY-04/Test 10 controller clauses complete until that suite runs non-skipped and fail-closed.
verification: Diagnosis verified by direct contract/source/test/CI tracing; 17/17 UAT-evidence validator meta-tests passing while pinning the human residue; plan-05 static surface guard passing while requiring the experiential disclaimer; current UAT validator and tally guards exposing planning-schema drift; and repository-wide negative evidence that no production d-pad/shoulder input dispatcher exists. No product tests were changed or claims broadened.
files_changed: []
