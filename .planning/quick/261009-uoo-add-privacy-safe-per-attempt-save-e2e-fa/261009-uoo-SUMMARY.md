---
id: 261009-uoo
type: quick-full
status: complete
completed: 2026-10-10
commits:
  - 410985e
  - ee561b3
  - 4117fcd
---

# 261009-uoo Summary: Save E2E Failure Diagnostics

Added immutable per-drain save upload results carrying only the pass outcome, closed failure classification, bounded HTTP status, and finite API error code. The production latest-classification cell and retry scheduling remain unchanged. The Save E2E harness now branches on the returned pass result, and writes a failure-only diagnostic. Its route status is the fixed `unavailable` token because the live fixture has no safe route correlation source.

The failed XCTest carries the finite diagnostic marker through the existing xcresult reader into `save_upload_diagnostics`. The sanitizer enforces its exact keys, finite tokens, status range, and count bound. Unknown fields (including response-body fields) and invalid status values are rejected. The product assertion still fails for the same upload conditions.

Review tightened two attribution edges before publishing: exhausted-retry failures now retain the same marker, and a pass that uploaded another queued save is reported as `sent_without_target_upload` instead of `no_pending`.

## Tasks and Commits

| Task | Commit | Evidence |
|---|---|---|
| Immutable per-pass diagnostic result | `410985e` | Added bounded result fields and regression coverage for overlapping lane drains, preserved attribution after a later successful pass, and unknown code normalization. |
| Save E2E failure artifact and sanitizer | `ee561b3` | Added failure-only diagnostic serialization, closed marker extraction, exact-schema sanitizer validation, and positive/negative fixtures. |
| Preserve diagnostics on every relevant failure branch | `4117fcd` | Added the `sent_without_target_upload` outcome to the closed schema and parser/sanitizer fixtures, and guarded that retry exhaustion, server refusal, and missing-target failures keep their marker. |

## Verification

- `cd playstead-mac && scripts/ci/tests/sanitizer-test.sh` — passed, 37 positive/negative checks, including the distinct `sent_without_target_upload` outcome.
- `cd playstead-mac && scripts/ci/tests/four-layer-topology-test.sh && scripts/ci/tests/four-layer-verifier-test.sh` — passed; four-layer verifier passed 35 positive/negative checks, including marker extraction into the structured result.
- `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts` — passed after the review corrections; all static contract guards passed, validator unit tests passed (43 tests), and the fixture verifier passed.
- `swiftc -frontend -parse` on changed Swift files — passed syntax parsing.
- Requested `xcodebuild test ... -only-testing:PlaysteadTests/SaveUploadLaneTests` — could not reach compilation or execute XCTest. Xcode attempted writes to `/Users/jon/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading` and was denied; the default DerivedData path was also denied. Redirecting DerivedData, package clones, and package cache to `/private/tmp` did not redirect SwiftPM's manifest diagnostics cache. CoreSimulator services were unavailable as well.
- Full live-server Save E2E was not run locally; therefore no real response or route status has yet been observed. The next hosted failure artifact will expose the bounded pass diagnostic; route status remains `unavailable` unless a safe correlation path is added.

## Deviations

- Added `run-mac-verification.sh` and its parser/topology fixtures because those are the existing path that turns XCTest failure data into hosted structured evidence. Without that connection, the sanitized hosted artifact would not contain the diagnostic.
- Recorded server route status as `unavailable`; no safely correlatable route status is exposed by the current live-server fixture.
- XCTest execution remains environmentally blocked by SwiftPM/Xcode cache permissions, despite the static contract, sanitizer, parser, and Swift syntax checks passing.
