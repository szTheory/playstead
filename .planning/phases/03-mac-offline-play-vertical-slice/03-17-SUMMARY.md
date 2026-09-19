---
phase: 03-mac-offline-play-vertical-slice
plan: 17
subsystem: mac-ui-test-controller-feasibility
tags: [macos, xctest, iohid, gamecontroller, ci]
status: blocked
plan_head_before: d4e86d4e38483060af9ea9f5cbb0809ff919bb5a
commits: 6
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
  commits: 6
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

### Final hosted feasibility result

**Named failing stage:** `ui-test-runner/signing-provisioning-profile`.

After the UAT policy artifacts were normalized without changing their findings, signed CI run `35462542190` passed static guards, 714 unit tests, and 45 rendering tests, then failed before UI test identification with `PlaysteadUITests-Runner encountered an error` (xcode 65). The sanitized artifact contains no UI result because the runner never launched. The repository harness's exact signing configuration is ad-hoc (`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=`); a local reproduction with that configuration fails explicitly: `"PlaysteadUITests" requires a provisioning profile.` The virtual-device entitlement is therefore not qualified on this runner.

No signing, Gatekeeper, entitlement, or validator bypass was attempted. Making this work requires a separately authorized hosted signing/provisioning design, not a Plan 03-17 test-only code adjustment. Task 2 and downstream controller work remain stopped. Escalate G-03-8, G-03-9, and G-03-10 for replanning around either an OS-supported, provisioned automation environment or an explicit human-needed disposition.

### Approved UAT policy normalization

The hosted run first exposed stale Phase 3 policy metadata unrelated to the HID code. With explicit approval, only the following derived-policy fields were restored: top-level UAT status `diagnosed -> partial` (`7227934`); item 8/9 `result: issue -> blocked` (`bae951d`); and Summary counts `issue: 4 -> 2`, `blocked: 0 -> 2` (`bdfdf0a`). All test prose, evidence, reasons, verdicts, and validator code remain unchanged. `bash scripts/check-uat-tally.sh` now reports Phase 3 mechanically as `total=49 blocked=2, issue=2, pass=45`.

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
