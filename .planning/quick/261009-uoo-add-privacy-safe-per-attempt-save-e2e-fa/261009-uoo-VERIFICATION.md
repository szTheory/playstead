---
phase: 261009-uoo-add-privacy-safe-per-attempt-save-e2e-fa
verified: 2026-10-10T02:21:13Z
status: human_needed
score: 2/4 must-haves verified
covered_files:
  - .planning/quick/261009-uoo-add-privacy-safe-per-attempt-save-e2e-fa/261009-uoo-PLAN.md
  - .planning/quick/261009-uoo-add-privacy-safe-per-attempt-save-e2e-fa/261009-uoo-SUMMARY.md
  - playstead-mac/Playstead/Net/APIClient.swift
  - playstead-mac/Playstead/Saves/SaveUploadLane.swift
  - playstead-mac/Playstead/UITesting/UITestBootstrap.swift
  - playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift
  - playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift
  - playstead-mac/scripts/ci/run-mac-verification.sh
  - playstead-mac/scripts/ci/sanitize-evidence.sh
  - playstead-mac/scripts/ci/tests/sanitizer-test.sh
covered_digest: "v3:sha256:851590bcacb18c459ef743036b70b773c6023da3536c39690d8ef056ba222c28"
behavior_unverified: 2
overrides_applied: 0
behavior_unverified_items:
  - truth: "A failed upload's classification, status, and API code remain attached to that exact drain pass under overlapping execution."
    test: "Run SaveUploadLaneTests/test_passDiagnosticRemainsBoundToFailureAfterLaterPassSucceeds and confirm the first failure retains its 409/server_refusal/other snapshot after a later successful drain."
    expected: "The failed result retains its own bounded fields; a queued or successful later result has no failure metadata."
    why_human: "The XCTest exists, but local xcodebuild did not reach compilation or execution because SwiftPM cache writes were denied and CoreSimulator was unavailable."
  - truth: "Upload retry behavior and the production-facing latest classification contract remain unchanged."
    test: "Run the SaveUploadLane unit tests in a supported hosted Mac runner and inspect the existing retry and classification assertions."
    expected: "Retry scheduling and decisions remain the same, while lastFailureClassification continues to set/reset as before."
    why_human: "The implementation preserves the existing branches by inspection, but runtime XCTest evidence was blocked locally."
human_verification:
  - test: "Execute the SaveUploadLane unit-test target on a supported Mac runner, including test_passDiagnosticRemainsBoundToFailureAfterLaterPassSucceeds."
    expected: "The named test and relevant retry/classification tests pass; exact pass-local fields survive a later pass."
    why_human: "Local Xcode could not access its SwiftPM manifest cache and CoreSimulator services were unavailable; hosted CI has not yet run against these commits."
  - test: "Inspect the next hosted Save E2E failure artifact, if that test fails."
    expected: "The sanitized artifact contains only the bounded pass outcome, classification, HTTP status/API code and server_route_status=unavailable; it exposes no request/response body, credentials, paths, or save metadata."
    why_human: "Hosted CI has not yet exercised the end-to-end evidence path against a live server. The current fixture has no safe route correlation source, so a concrete route status is unavailable."
---

# Phase 261009-uoo: Save E2E Failure Diagnostics Verification Report

**Phase Goal:** Add bounded failure-only evidence attributing Save E2E drain outcome, classification, HTTP/API status and safely correlated server route status to the exact upload attempt without changing retries or product classification behavior.
**Verified:** 2026-10-10T02:21:13Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | A Save E2E failure reports the closed failure classification and HTTP status/API code from the exact drain pass that produced its result. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SaveUploadDrainResult` is immutable, `Equatable`, and `Sendable`; `drainOnce` captures safe fields within its own catch path; `UITestBootstrap` branches and serializes that result. `SaveUploadLaneTests` includes an overlapping-drain regression test, but local XCTest did not execute. |
| 2 | Matching server-route status is available for the same synthetic save request when safely correlatable by the existing live-server fixture. | ✓ VERIFIED | The harness and sanitizer use the fixed `unavailable` representation. Inspection of the existing fixture shows no safe request correlation source, so the plan's conditional route-status behavior is correctly represented as unavailable; no route payload/logging was added. |
| 3 | The sanitized CI artifact retains only bounded diagnostic fields, and rejects secret-bearing or unbounded values. | ✓ VERIFIED | Exact-key/token/status/count validation exists in `sanitize-evidence.sh`; positive/negative shell fixtures exercise the schema. Ran `scripts/ci/tests/sanitizer-test.sh`: 37 checks passed. Ran `scripts/ci/run-mac-verification.sh --self-test-contracts`: all static guards and 43 validator unit tests passed. |
| 4 | Upload retry behavior and the production-facing latest classification contract remain unchanged. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Source inspection confirms retry branches and `lastFailureClassification` cell set/reset semantics remain in place; returned results are additive. Runtime assertions exist but XCTest could not run locally. |

**Score:** 2/4 truths verified (2 present, behavior-unverified)

## Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `playstead-mac/Playstead/Saves/SaveUploadLane.swift` | Immutable per-drain bounded failure result | ✓ VERIFIED | Returns outcome/classification/status/allowlisted API code from failure handling; existing latest-classification cell remains. |
| `playstead-mac/Playstead/UITesting/UITestBootstrap.swift` | Use the pass result and write failure-only diagnostic | ✓ VERIFIED | Retry and terminal branches consume `drainResult`; diagnostic written only when upload remains unsuccessful. |
| `playstead-mac/Playstead/Net/APIClient.swift` | Finite API code vocabulary | ✓ VERIFIED | Unknown codes map to fixed `other`; error title/detail/body are not copied into the per-pass value. |
| `playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift` | Validate and preserve safe failure marker | ✓ VERIFIED | Closed enums/ranges gate the fixed marker; CI reader extracts only marker fields. |
| `playstead-mac/scripts/ci/sanitize-evidence.sh` | Fail-closed exact schema and bounds | ✓ VERIFIED | Validates exact fields, finite token sets, status range, and max 50 records. |
| `playstead-mac/scripts/ci/tests/sanitizer-test.sh` | Sanitizer acceptance and rejection fixtures | ✓ VERIFIED | 37 positive/negative checks pass, including private response-body field rejection and invalid status rejection. |
| `playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift` | Deterministic attribution and normalization coverage | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Regression coverage exists for unknown codes and overlapping drains; requested XCTest execution was blocked before compilation. |
| `playstead-mac/scripts/ci/run-mac-verification.sh` | Extract bounded marker to hosted artifact | ✓ VERIFIED | Parses only a closed marker regex and emits bounded fields; fixture contract tests passed. |

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `SaveUploadLane.drainOnce` | `UITestBootstrap.runSaveEndToEnd` | returned `SaveUploadDrainResult` | WIRED | The harness reads the result for retry decisions, terminal classification and artifact writing; it no longer samples the shared classification cell after await. |
| `UITestBootstrap` | `SaveEndToEndTests` | failure-only JSON marker | WIRED | Bootstrap writes a fixed JSON object; UI test decodes it and only emits a marker when fields pass closed validation. |
| XCTest failure marker | `run-mac-verification.sh` | fixed marker regex | WIRED | The parser extracts allowed outcome/classification/status/code values and maps `unavailable` to null. |
| parser structured result | `sanitize-evidence.sh` | exact `save_upload_diagnostics` schema | WIRED | Sanitizer accepts only exact record keys and bounded values before staging. |
| synthetic save request | live-server route status | existing fixture correlation | CONDITIONAL / UNAVAILABLE | No safe correlation source exists in the current fixture; the artifact carries `unavailable` and no new server logging was introduced. |

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `SaveUploadDrainResult` | `httpStatus`, `apiCode`, `failureClassification` | Actual `APIClientError.server(APIError)` inside that pass; status and finite code only | Yes, when a server response exists | ✓ FLOWING |
| `diagnostic.json` | `drain_outcome`, `classification`, `http_status`, `api_code` | The failed pass's returned result | Yes | ✓ FLOWING |
| Hosted evidence | `save_upload_diagnostics` | Closed marker parsed from XCTest failure record | Yes when the hosted test emits the marker | ✓ FLOWING; hosted execution pending |
| `server_route_status` | fixed `unavailable` | No correlated route source in the fixture | No route status currently available | ⚠️ STATIC (conditional behavior unavailable) |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Sanitizer retains valid bounded Save E2E diagnostics and rejects hostile/unbounded fields | `cd playstead-mac && scripts/ci/tests/sanitizer-test.sh` | `evidence sanitizer: 37 positive/negative checks passed` | ✓ PASS |
| Static Mac verification contracts and validators | `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts` | All static contract guards passed; validator unit tests: 43 passed | ✓ PASS |
| Per-pass XCTest attribution | `xcodebuild test ... -only-testing:PlaysteadTests/SaveUploadLaneTests` | Could not reach compilation/execution: SwiftPM manifest cache and DerivedData writes were denied; CoreSimulator unavailable | ? SKIP — human/hosted verification needed |
| Hosted Save E2E artifact behavior | hosted CI run | No hosted run against these commits yet | ? SKIP — human/hosted verification needed |

## Probe Execution

Not applicable: this quick task declares no probe scripts or probe-based success criteria.

## Requirements Coverage

Not applicable: the quick plan declares no requirement IDs.

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| — | — | No debt markers or implementation stubs found in changed files. Matches for `placeholderID` and `mktemp` are legitimate test identifiers/temp-file setup. | ℹ️ Info | No impact. |

## Human Verification Required

### 1. Run the pass-local attribution XCTest on a supported Mac runner

**Test:** Run `SaveUploadLaneTests/test_passDiagnosticRemainsBoundToFailureAfterLaterPassSucceeds` and relevant retry/classification tests in the hosted Mac unit-test lane.
**Expected:** The originating failure retains its status/classification/API code after a later successful pass; retry scheduling and the latest classification cell keep their existing behavior.
**Why human:** The local Xcode invocation was blocked before compilation by SwiftPM cache permissions and unavailable CoreSimulator services.

### 2. Confirm the next hosted Save E2E failure artifact

**Test:** Inspect `save_upload_diagnostics` from the next hosted Save E2E failure.
**Expected:** Only the finite pass-local fields appear, with `server_route_status=unavailable` unless the fixture gains a safe correlation path; forbidden response contents and credentials remain absent.
**Why human:** Hosted CI has not run these commits against the live fixture.

## Gaps Summary

No implementation gaps were found in the code or static evidence pipeline. Two behavior-dependent claims remain unproven because XCTest could not execute locally, and hosted CI has not yet exercised the new end-to-end artifact path. Route status is deliberately `unavailable` because the existing fixture has no safe correlation source; this matches the plan's conditional requirement.

---

_Verified: 2026-10-10T02:21:13Z_  
_Verifier: the agent (gsd-verifier)_
