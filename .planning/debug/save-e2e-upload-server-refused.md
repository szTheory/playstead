---
status: resolved
trigger: "PR #10 run 38012559750, macOS job 114095657015. SaveEndToEndTests failed at line 185; the matching switch case is `save-e2e: upload stopped for retry, server refused`. FAILURE_STAGE is unavailable. Sanitized artifact is at `/private/tmp/playstead-mac-failure-38012559750`. A later full CI run 38012577910 was running at dispatch; inspect its status only if already complete, and do not wait for it. This is distinct from run 37991439424's mirror mismatch unless evidence connects them."
created: 2026-10-10T01:16:49Z
updated: 2026-10-10T07:36:00Z
---

## Current Focus

hypothesis: Overlapping calls to the same SaveUploadLane reenter the actor at network awaits, both select the same queued revision, and can race its upload and idempotent commit.
test: A local overlapping-drain regression test fails against the original lane because it observes a second PUT, then passes with an in-flight Task gate. The hosted attempt's pass-local diagnostic independently confirms HTTP 409, but its sanitized API code is `other`.
expecting: Exactly one PUT and one POST for concurrent callers; both callers observe the same completed drain result.
next_action: Parent integrates the isolated PR worktree change; no further hosted CI attempt was run in this debug session.
bug_class: Actor reentrancy permits duplicate save upload work under concurrent drain triggers.

## Symptoms

expected: The required SaveEndToEnd test completes capture, uploads its revision, and verifies the synced result.
actual: Run 38012559750's required test `SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn()` failed after 6.90 seconds. The hosted log says `FAILURE_STAGE unavailable`.
errors: Hosted job log reports `FAILURE_DIAGNOSTIC ... XCTAssertTrue PlaysteadUITests/SaveEndToEndTests.swift:185`; the sanitized artifact contains one diagnostic with that assertion and line, but not its message. At the run's source commit, line 185 is `save-e2e-harness=upload-server-refused`.
reproduction: Hosted PR run 38012559750, job 114095657015, head `aa9ee18d7158a5a323f2a77c0cb233f7d6b53ced`. No local reproduction attempted.
started: This occurrence was observed 2026-10-10. Its relationship to earlier failures is not established.

## Eliminated

- hypothesis: This is the run 37991439424 mirror mismatch recurring.
  evidence: Run 38012559750 failed at SaveEndToEndTests.swift:185's upload refusal marker, while the earlier occurrence was a final mirror verification failure. They are separate symptoms with no evidence connecting them.
  timestamp: 2026-10-10

- hypothesis: Run 38012577910 can currently provide a completed comparison.
  evidence: `gh run view 38012577910 --json status,conclusion,url` returned `status=in_progress`, empty conclusion. The task explicitly says not to wait.
  timestamp: 2026-10-10

## Evidence

- timestamp: 2026-10-10
  checked: Sanitized artifact `/private/tmp/playstead-mac-failure-38012559750/live-server-tests.json`.
  found: Five tests executed; only SaveEndToEnd failed. `failure_diagnostic_count` is one, and the only diagnostic is `XCTAssertTrue` at `SaveEndToEndTests.swift:185`. No FAILURE_STAGE or classification is in the artifact.
  implication: Failure location is established, but the assertion's specific message and triggering classification are absent.

- timestamp: 2026-10-10
  checked: Hosted job log for run 38012559750, job 114095657015.
  found: The log records the required SaveEndToEnd test failed, then `live-server: FAILURE_DIAGNOSTIC ... XCTAssertTrue ...:185`, followed by `live-server: FAILURE_STAGE unavailable`. No `save-e2e-harness` detail or fixture refusal classification is printed.
  implication: The hosted channel confirms the assertion site but does not expose the cause behind the broad marker.

- timestamp: 2026-10-10
  checked: `SaveEndToEndTests.swift` and `UITestBootstrap.swift` at exact run head `aa9ee18d7158a5a323f2a77c0cb233f7d6b53ced`.
  found: Test line 185 maps `save-e2e: upload stopped for retry, server refused` to `save-e2e-harness=upload-server-refused`. In `UITestBootstrap.runSaveEndToEnd`, the branch emits this literal when a drain stopped for retry and `isRetryable(lane.lastFailureClassification)` is false. The harness reads a shared `lastFailureClassification` property while the app can also drain the same lane; that property reflects the last writer, not necessarily the harness's pass.
  implication: Source establishes the branch mechanism and a plausible cross-pass classification contamination path. It does not establish that contamination occurred in this run; a genuinely non-retryable response follows the same branch.

- timestamp: 2026-10-10
  checked: Historical pending note `.planning/todos/pending/save-e2e-duplicate-revision-409.md` and `.planning/WINDOWS.md` save-upload entries.
  found: The historical note documents that HTTP 409 classifies as `.compatibilityRejection`, a non-retryable classification, and explicitly said earlier refusal runs did not preserve which classification fired. WINDOWS describes a prior shared-classification race where the broad refusal could be misreported due to a concurrent drain. The present run does not contain the request status or classification needed to tie either explanation to this occurrence.
  implication: Both a real 409/non-retryable server outcome and classification-cell contamination remain candidates; history is not direct evidence for this run.

- timestamp: 2026-10-10
  checked: GitHub run 38012577910 status.
  found: It remained `in_progress` at inspection; no result was available. No further polling performed.
  implication: No comparison run evidence is available under the task's no-wait constraint.

- timestamp: 2026-10-10
  checked: PR #10 run 38027686751 attempt 2, macOS job 114149643085, sanitized artifact 11661624742 at `/private/tmp/playstead-attempt2-evidence-exact/live-server-tests.json`.
  found: SaveEndToEnd alone failed among five live-server tests. Its pass-local diagnostic is `stopped_for_retry`, `server_refusal`, HTTP 409, `api_code=other`; unit 666/0, rendering 45/0, and UI 113/0 passed.
  implication: This occurrence is a real 409 observed by the failing drain pass, not merely a concurrent overwrite of `lastFailureClassification`. The closed diagnostic vocabulary does not identify the exact server code.

- timestamp: 2026-10-10
  checked: `SaveUploadLane.drainOnce` and its production/harness callers at PR head `177cee5a89877c2309eae479c267c8d8b6982233`.
  found: The original actor method selects pending rows before awaiting PUT and POST; it does not guard a pass already in flight. Reachability and the Save E2E harness can call it concurrently. Swift actor reentrancy allows both passes to select the same still-queued revision. The server returns HTTP 409 for an in-flight idempotency receipt; other 409 codes remain possible without the raw response.
  implication: One actor instance alone does not serialize the full asynchronous drain pass.

- timestamp: 2026-10-10
  checked: Focused local pre-fix run of `SaveUploadLaneTests/test_overlappingDrainsShareOneUploadAndCommit` against the original lane source.
  found: The test failed because its first-PUT expectation was fulfilled a second time while the first upload was in flight. The failure is in `/private/tmp/playstead-save-lane-derived/Logs/Test/Test-Playstead-2026.10.10_03-17-14--0400.xcresult`.
  implication: The duplicate network path is reproducible without a hosted server or physical input.

- timestamp: 2026-10-10
  checked: Final isolated PR worktree fix and targeted local XCTest suite.
  found: The lane now shares one in-flight Task among overlapping callers and clears it before releasing waiters. `SaveUploadLaneTests` passed 12/12, zero failed or skipped, in `/private/tmp/playstead-save-lane-derived/Logs/Test/Test-Playstead-2026.10.10_03-34-46--0400.xcresult`.
  implication: The locally reproduced duplicate path is closed. The exact hosted 409 subcode remains unknown and no additional hosted CI run was launched.

## Resolution

root_cause: Concurrent save-upload drain calls reenter one actor at network awaits and can upload/commit the same queued revision twice. This defect is locally reproduced; the hosted 409's exact subcode was not preserved.
fix: In the isolated PR worktree, overlapping callers await one in-flight drain Task, and the Task clears itself before waiters resume. A regression test asserts one PUT and one POST.
verification: Pre-fix focused test failed on a duplicate PUT; final targeted SaveUploadLaneTests passed 12/12. No hosted CI rerun was performed in this debug session.
files_changed: [playstead-mac/Playstead/Saves/SaveUploadLane.swift, playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift, .planning/debug/save-e2e-upload-server-refused.md]

reasoning_checkpoint:
  hypothesis: A second drain reenters at the first network await, selects the same queued revision, and issues duplicate requests.
  confirming_evidence:
    - The new artifact records a pass-local 409/server-refusal result, eliminating the shared-cell overwrite as the sole cause of this occurrence.
    - The original source permits actor reentrancy across PUT/POST awaits, and two app triggers can call the same lane.
    - The focused pre-fix test observed two PUTs; the gate makes the same test and all lane tests pass.
  falsification_test: The pre-fix overlap test would observe one PUT if actor isolation had serialized the complete drain; it observed two.
  fix_rationale: Share an in-flight Task per lane so concurrent callers get the same pass outcome without selecting or sending the same revision twice.
  blind_spots: The hosted 409's exact API code and route were not retained. Local evidence proves the duplicate path, but does not establish that this was the only possible 409 cause in that hosted attempt.
  candidate_causes:
    - "confirmed code: concurrent app/harness drain passes can race the same queued revision"
    - "unresolved hosted detail: the specific 409 code/route was sanitized to other/unavailable"
  and_gate: "No additional condition is required to reproduce duplicate PUTs locally; the hosted 409 subcause is unconfirmed."
