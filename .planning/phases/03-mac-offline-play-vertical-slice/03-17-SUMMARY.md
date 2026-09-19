---
phase: 03-mac-offline-play-vertical-slice
plan: 17
subsystem: mac-ui-test-controller-feasibility
tags: [macos, xctest, iohid, gamecontroller, ci]
status: blocked
plan_head_before: d4e86d4e38483060af9ea9f5cbb0809ff919bb5a
commits: 2
dependency_graph:
  requires: [03-16]
  provides: []
  affects: [03-18, 03-22]
tech_stack:
  added: [IOKit.hid]
  patterns: [finite UI-test-only virtual HID fixture, fail-closed hosted evidence]
key_files:
  created:
    - playstead-mac/PlaysteadUITests/Support/VirtualGamepad.swift
    - playstead-mac/PlaysteadUITests/ControllerHardwareIntegrationTests.swift
  modified:
    - playstead-mac/PlaysteadUITests/PlaysteadUITests.entitlements
    - playstead-mac/TestPlans/UI.xctestplan
    - playstead-mac/scripts/ci/run-mac-verification.sh
decisions:
  - "A locally unsigned UI-test runner is non-qualifying evidence; the signed macos-26 CI run remains the sole feasibility oracle."
metrics:
  duration: blocked awaiting CI static-guard repair
  completed_date: 2026-09-19
actuals:
  tokens: 2200
  tasks: 0
  commits: 2
---

# Phase 03 Plan 17: Virtual HID Feasibility Tracer Summary

Implemented the finite, UI-test-runner-only virtual gamepad and fail-closed hosted-evidence registration, but the recurring macOS 26 job stopped at an unrelated Phase 3 UAT policy guard before the hardware tracer could execute.

## Task Status

| Task | Status | Commit |
| --- | --- | --- |
| 1. Qualify one virtual gamepad on signed macOS 26 CI | Blocked before test execution | `da9415d` |
| 2. Separate runtime and persistence controller identity | Not started; hard prerequisite unmet | — |

## Delivered Tracer Surface

- Added `VirtualGamepad`, a compiled fixed HID descriptor and named, range-checked report methods confined to `PlaysteadUITests`.
- Added a no-skip XCUITest covering initial zero-controller state, invalid descriptor rejection, attach, detach, and reconnect against the production controller-settings surface.
- Added `com.apple.developer.hid.virtual.device` solely to the UI-test runner and registered the exact test in `UI.xctestplan` and the CI UI-layer required-test list.
- Extended the complete-hosted-evidence validator and its fixtures so missing, skipped, or failed tracer evidence is rejected.

## Verification Evidence

- RED: the new XCUITest initially failed to compile because `VirtualGamepad` did not exist.
- GREEN compilation: the fixture and XCUITest compile under the local macOS SDK.
- `playstead-mac/scripts/ci/run-mac-verification.sh --self-test-contracts`: all prior contract guards and 47 validator tests passed; final Phase 3 UAT policy guard failed as described below.
- Hosted run: `35461577570` reached `Verify static contract guards` and failed with `phase-3 evidence validation failed: Phase 3 UAT status must remain partial` before `Run one build and four serial test layers`; no virtual-HID discovery, execution, skip state, or result exists.

## Blocker and Escalation

**Named failing stage:** `static-contract-guard/phase-3-uat-status`.

The guard is not weakened or bypassed. `validate-phase-3-uat-evidence.py` requires the Phase 3 UAT frontmatter status to be `partial`, but `.planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md` has `status: diagnosed`, introduced in pre-existing commit `29bdb27` outside this plan's allowed files. This prevents qualification of the virtual-HID seam and therefore blocks Task 2 and downstream controller plans.

The local French macOS report that `PlaysteadUITests-Runner.app` was damaged is likewise non-qualifying diagnostic evidence: the local compile run deliberately used `CODE_SIGNING_ALLOWED=NO` and `codesign` reports that generated runner invalid. No Gatekeeper, signing, entitlement, or test guard was bypassed.

Escalate G-03-8, G-03-9, and G-03-10 only if, after the independently-owned UAT policy mismatch is resolved and CI rerun, the signed hosted runner fails HID entitlement authorization, device creation, or GameController enumeration. Those outcomes remain unmeasured here.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Current macOS SDK requires an explicit IOHIDUserDevice creation options argument**
- **Found during:** Task 1 local compilation.
- **Fix:** Passed `0` as the documented options value to `IOHIDUserDeviceCreateWithProperties`.
- **Commit:** `da9415d`.

## Deferred Issues

- The pre-existing Phase 3 UAT status mismatch must be resolved by its owning planning/policy work before this tracer can receive its required hosted-CI verdict.

## Self-Check: PASSED

- Tracer files exist and `da9415d` is present in git history.
- No production target contains `IOHIDUserDevice` or the virtual-device entitlement.
