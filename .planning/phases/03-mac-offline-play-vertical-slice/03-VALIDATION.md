---
phase: 3
slug: mac-offline-play-vertical-slice
# Execution owns this lifecycle. Plan 03-21 may set validated/true only after the complete evidence gate passes.
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-30
updated: 2026-09-19
---

# Phase 3 — Validation Strategy

> Pending executable contract for zero-human closure of G-03-8, G-03-9, G-03-10, and G-03-13. This file describes the automated strategy now; it does not claim the commands have passed.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Frameworks** | XCTest/XCUITest via `xcodebuild`; shell contract mutation tests; Python `unittest` evidence-policy tests |
| **Config files** | `playstead-mac/TestPlans/Unit.xctestplan`, `playstead-mac/TestPlans/UI.xctestplan`, `.github/workflows/ci.yml`, `.github/workflows/verify-hosted-evidence.yml` |
| **Focused command** | `cd playstead-mac && scripts/ci/run-mac-verification.sh --layers ui --only-testing <required identifiers>` |
| **Contract command** | `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts` |
| **Full command** | `cd playstead-mac && scripts/ci/run-mac-verification.sh --run-four-layer-verification && scripts/ci/run-mac-verification.sh --self-test-contracts && scripts/ci/tests/bios-acceptance-seam-test.sh` |
| **Final policy command** | `bash scripts/check-uat-tally.sh && python3 playstead-mac/scripts/ci/validate-phase-3-uat-evidence.py --uat .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md --roadmap .planning/ROADMAP.md` |
| **Estimated runtime** | Focused unit 1–3 min; focused packaged UI 5–15 min; complete hosted four-layer run 30–60 min |

The entitled IOHIDUserDevice seam is qualified only by the signed recurring `macos-26` CI job. A local SDK/build result cannot replace the hosted evidence command in 03-17.

---

## Sampling Rate

- **After every task commit:** Run that task's exact `<automated>` command from its PLAN.md row below.
- **After plans 03-18, 03-22, 03-23, 03-19, and 03-20:** Run `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts` in addition to the focused behavior command.
- **Before any UAT, verification, requirement, or validation status edit:** Run the full four-layer, contract, BIOS, tally, and evidence-policy commands in 03-21 Task 2.
- **Before `/gsd-verify-work`:** The complete gate must be green, every required identifier executed once and non-skipped, and this file must have been reconciled by 03-21.
- **Maximum feedback latency:** 15 minutes for a focused packaged UI task; hosted feasibility and final four-layer gates are explicit long-running exceptions and must retain their run evidence.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-17-01 | 17 | 1 | PLAY-04, QUAL-01 | T-03-17-01..03 | Test-only entitled HID enumerates/detaches/reconnects on signed hosted runner; zero discovery and skip fail | hosted XCUITest/evidence | `test -s hosted-evidence/run-record.json && test -s hosted-evidence/run-view.json && test -s hosted-evidence/complete-verification-evidence.json && playstead-mac/scripts/ci/run-mac-verification.sh --verify-hosted-run complete --run-record hosted-evidence/run-record.json --run-view hosted-evidence/run-view.json --manifest hosted-evidence/complete-verification-evidence.json` | ❌ created by task | ⬜ pending |
| 03-17-02 | 17 | 1 | PLAY-04 | T-03-17-04 | Runtime ids stay distinct while stable model keys survive reconnect/relaunch | unit | `cd playstead-mac && xcodebuild test -scheme Playstead -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -testPlan Unit -only-testing:PlaysteadTests/ControllerHostTests` | ✅ | ⬜ pending |
| 03-18-01 | 18 | 2 | PLAY-04, QUAL-01 | T-03-18-01..02 | Assigned detach is visible and non-modal; keyboard/pointer survive; unassigned detach is ignored | packaged XCUITest | `cd playstead-mac && scripts/ci/run-mac-verification.sh --layers ui --only-testing ControllerHardwareIntegrationTests/testDetachRecoveryIsNonModalAndReconnectRestoresInput ControllerHardwareIntegrationTests/testUnassignedDetachDoesNotRaiseAssignedRecovery` | ❌ created by 03-17/18 | ⬜ pending |
| 03-18-02 | 18 | 2 | QUAL-01 | T-03-18-03 | Required identifiers reject removal, skip, and zero discovery | contract mutation | `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts` | ✅ | ⬜ pending |
| 03-22-01 | 22 | 3 | PLAY-04, QUAL-01 | T-03-22-01..03 | Preserved RED oracle precedes production edits; real GameController input reaches live test | unit + packaged XCUITest | `cd playstead-mac && xcodebuild test -scheme Playstead -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -testPlan Unit -only-testing:PlaysteadTests/ControllerHostTests && scripts/ci/run-mac-verification.sh --layers ui --only-testing ControllerHardwareIntegrationTests/testProductionControllerInputReachesLiveTest` | ❌ integration test created by task | ⬜ pending |
| 03-22-02 | 22 | 3 | PLAY-04 | T-03-22-03 | Fake-source unit evidence cannot substitute for packaged input evidence | contract mutation | `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts` | ✅ | ⬜ pending |
| 03-23-01 | 23 | 4 | PLAY-04, QUAL-01 | T-03-23-01..03 | Assign/remap/reset commit atomically, refresh AdapterHost, and survive relaunch | packaged XCUITest | `cd playstead-mac && scripts/ci/run-mac-verification.sh --layers ui --only-testing ControllerHardwareIntegrationTests/testProductionControllerLifecycleAssignsTestsRemapsResetsAndPersists` | ❌ created by 03-22/23 | ⬜ pending |
| 03-23-02 | 23 | 4 | PLAY-04 | T-03-23-03 | Structured lifecycle evidence rejects missing checkpoints and fake-only substitution | contract mutation | `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts` | ✅ | ⬜ pending |
| 03-19-01 | 19 | 5 | PLAY-04, QUAL-01 | T-03-19-01..02 | Assigned d-pad/shoulder/Menu events navigate every declared production surface; unknown/unassigned input cannot | packaged XCUITest | `cd playstead-mac && scripts/ci/run-mac-verification.sh --layers ui --only-testing ControllerHardwareIntegrationTests/testControllerNavigationCoversEveryDeclaredSurfaceAndAction ControllerHardwareIntegrationTests/testUnassignedAndUnknownInputsCannotNavigate` | ❌ created by task | ⬜ pending |
| 03-19-02 | 19 | 5 | QUAL-01 | T-03-19-03..04 | Objective AX properties remain required and subjective VoiceOver qualities remain explicit non-claims | packaged XCUITest + contract | `cd playstead-mac && scripts/ci/run-mac-verification.sh --layers ui --only-testing SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit ControllerHardwareIntegrationTests/testControllerNavigationCoversEveryDeclaredSurfaceAndAction && scripts/ci/tests/plan-05-surface-contract-test.sh && scripts/ci/run-mac-verification.sh --self-test-contracts` | ✅ / task updates | ⬜ pending |
| 03-20-01 | 20 | 6 | PLAY-03 | T-03-20-01..02 | Fixed lawful synthetic candidate traverses packaged production wiring and persists exact bytes idempotently | packaged XCUITest | `cd playstead-mac && scripts/ci/run-mac-verification.sh --layers ui --only-testing BiosAcceptanceSeamTests/testFixedSyntheticReferenceAcceptsThroughPackagedAppAndPersistsExactly` | ❌ created by task | ⬜ pending |
| 03-20-02 | 20 | 6 | PLAY-03 | T-03-20-01..05 | Digest/length mutants fail without residue; production pins stay explicit; Release excludes test hooks | unit + packaged XCUITest + contract | `cd playstead-mac && xcodebuild test -scheme Playstead -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -testPlan Unit -only-testing:PlaysteadTests/BiosProductionReferenceTests -only-testing:PlaysteadTests/BiosTests && scripts/ci/run-mac-verification.sh --layers ui --only-testing BiosAcceptanceSeamTests && scripts/ci/tests/bios-acceptance-seam-test.sh && scripts/ci/run-mac-verification.sh --self-test-contracts` | ❌ seam files created by task | ⬜ pending |
| 03-21-01 | 21 | 7 | PLAY-03, PLAY-04, QUAL-01 | T-03-21-01..03 | Final evidence policy rejects missing proof and accessibility/BIOS overclaims | Python unit + shell mutation | `cd playstead-mac && python3 -m unittest discover -s scripts/ci/tests -p 'test_*.py' -q && scripts/ci/tests/plan-05-surface-contract-test.sh` | ✅ / task updates | ⬜ pending |
| 03-21-02 | 21 | 7 | PLAY-03, PLAY-04, QUAL-01 | T-03-21-01..04 | Status files change only after complete evidence; final validation is derived from executed commands | four-layer + contracts + policy | `cd playstead-mac && scripts/ci/run-mac-verification.sh --run-four-layer-verification && scripts/ci/run-mac-verification.sh --self-test-contracts && scripts/ci/tests/bios-acceptance-seam-test.sh && cd .. && bash scripts/check-uat-tally.sh && python3 playstead-mac/scripts/ci/validate-phase-3-uat-evidence.py --uat .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md --roadmap .planning/ROADMAP.md` | ✅ / task updates | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky. `File Exists` describes planning-time state, not execution success.*

---

## Wave 0 Requirements

No separate Wave 0 scaffold is required. Existing XCTest/XCUITest, shell mutation, Python policy, hosted-evidence, and four-layer runners cover the phase. Plan 03-17 is the mandatory Wave 1 feasibility tracer because the entitled virtual-HID seam must be proved on the actual signed hosted runner before dependent production work begins.

`wave_0_complete` intentionally remains `false` while this contract is pending. Plan 03-21 may set it `true` only after confirming the declared infrastructure and complete evidence command have executed successfully.

---

## Manual-Only Verifications

None — all phase-completion behaviors in this gap-closure set have automated verification.

Pronunciation, rotor usefulness, sentence quality, comprehension, navigation intuition, proprietary BIOS authenticity/legality, emulator hardware fidelity, and broader UX taste remain explicit non-gating non-claims. They are not manual completion gates and must not be inferred from the automated suite.

---

## Validation Sign-Off

- [ ] Every task row's exact automated command has executed successfully.
- [ ] The 03-17 hosted feasibility identifier executed once, non-skipped, on the signed recurring `macos-26` job.
- [ ] Sampling continuity is preserved across recovery, input, persistence, navigation, BIOS, and reconciliation waves.
- [ ] Contract mutation tests reject removal, skip, zero discovery, fake-only substitution, and evidence overclaims.
- [ ] The complete four-layer evidence manifest contains every required identifier from plans 03-17, 03-18, 03-22, 03-23, 03-19, and 03-20.
- [ ] UAT tally and final evidence policy pass after status reconciliation.
- [ ] `status: validated`, `wave_0_complete: true`, and `nyquist_compliant: true` are set by 03-21 only after every check above passes.

**Approval:** pending execution of 03-21 Task 2
