---
status: resolved
trigger: "Identify why the hosted SaveEndToEndTests failure in CI run 37991439424 occurred, or record the exact next diagnostic needed; do not change app code or wait for another run."
created: 2026-10-09T21:58:00Z
updated: 2026-10-09T22:06:05Z
---

## Current Focus
<!-- OVERWRITE on each update - reflects NOW -->

bug_class: "Shared-fixture state leakage between serial live-server tests."
reasoning_checkpoint:
  hypothesis: "The fresh SaveEndToEnd mirror included a prior test's second server-side sentinel because the tests share a persistent owner/catalogue."
  confirming_evidence:
    - "The hosted job log names the failed fixture check: `mirror sentinel set mismatch: expected=first-only rows=2 first=present second=present`, during `verify-evidence`."
    - "LiveServer.xctestplan runs LiveServerSnapshotTests before PairingCeremonyTests and SaveEndToEndTests, serially; LiveServerSnapshotTests invokes the `second` fixture action."
    - "`Playstead.MacCiFixture.provision!/0` reuses `Accounts.get_owner()` and imports Sentinel One; it has no cleanup of Sentinel Two. SaveEndToEndTests creates a fresh client run root and verifies `first-only`."
  falsification_test: "A clean isolated server catalogue with the first sentinel only should pass this mirror check; no rerun was requested because the hosted log and fixture source already identify the mismatch."
  fix_rationale: "This session was diagnosis-only. The evidence supports a test-fixture isolation mismatch; choose and verify the smallest isolation strategy in the owning GSD task."
  blind_spots: "The exact cleanup/isolation design and whether it should be applied at fixture provision, server lifecycle, or test-plan scope are not decided here. The old duplicate-revision and upload-lane race incidents are not this failure."
  candidate_causes:
    - "Shared server catalogue retains Sentinel Two after the preceding snapshot test."
  and_gate: "no — persistent Sentinel Two plus a first-only expected set is sufficient to reproduce the reported mismatch."
next_action: None — root cause is identified; implementation and verification belong to the owning CI/GSD task.

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: "SaveEndToEndTests completes the capture, upload and journal-return round trip against the hosted live server."
actual: "PlaysteadUITests.SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn failed after 5.10 seconds in run 37991439424 at commit 6506161ebd0882e002552fdf53d90482dc411e5f."
errors: "Sanitized artifact reports failure_diagnostic_count=0; raw assertion text is absent. The sibling LiveServerSnapshotTests passed."
reproduction: "Observed on the hosted macOS 26 live-server verification layer. No local replay requested or available from current evidence."
started: "Run 37991439424, 2026-10-09; exact first occurrence of this underlying cause is unknown."

## Eliminated
<!-- APPEND only - prevents re-investigating -->

- hypothesis: "The historical duplicate revision POST 409 or dual SaveUploadLane race caused this run's failure."
  evidence: "The full hosted job log prints a different failure condition: the final first-only mirror verification encountered both sentinel titles, failing during verify-evidence. That check runs after capture/upload and is independent of the earlier upload-counter assertions."
  timestamp: 2026-10-09T22:06:05Z

## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-10-09T21:58:00Z
  checked: "GitHub Actions run 37991439424 metadata, jobs and artifacts"
  found: "Linux mix precommit succeeded. The Docker job failed during setup-buildx-action before its build/smoke steps. The macOS four-layer run failed only because SaveEndToEndTests failed; LiveServerSnapshotTests passed. The run produced sanitized artifact 11646988087."
  implication: "The SaveEndToEndTests failure is independent of the Docker setup failure and is not an assertion cascade from a failed snapshot test; the passing snapshot test does leave server catalogue state used by later tests."

- timestamp: 2026-10-09T21:58:00Z
  checked: "Hosted macOS job log for run 37991439424, job 114034853589"
  found: "Live-server verification reports five required tests across five executed; SaveEndToEndTests is the only required-test failure and ran 5.10 seconds. Pairing, snapshot, restore-proof and runner-canary tests passed."
  implication: "The failure is localized to the save end-to-end test path, but the log does not name the assertion or harness stage."

- timestamp: 2026-10-09T21:58:00Z
  checked: "Existing project TODO and WINDOWS history for this test"
  found: "The same test has prior distinct failures: duplicate revision POST 409 in pending todo save-e2e-duplicate-revision-409.md; an intermittent dual SaveUploadLane race later resolved and documented in WINDOWS #67; earlier fixture timeout and cascade failures."
  implication: "These older signatures were alternatives until the full hosted log exposed the current failure's different fixture assertion; they are not the cause of this run."

- timestamp: 2026-10-09T22:06:05Z
  checked: "Full hosted macOS job log for run 37991439424 plus serial LiveServer.xctestplan, LiveServerSnapshotTests, SaveEndToEndTests, MacCiFixture and live-server.sh verify logic"
  found: "The CI log contains `mirror sentinel set mismatch: expected=first-only rows=2 first=present second=present` during the SaveEndToEnd verify-evidence stage. The serial test plan runs LiveServerSnapshotTests first; that test adds Sentinel Two to the server fixture. MacCiFixture.provision!/0 reuses the existing owner and imports Sentinel One without removing Sentinel Two. SaveEndToEndTests creates a fresh local profile, then asks live-server.sh to verify a first-only sentinel set."
  implication: "The failure is a cross-test server-catalogue isolation mismatch, not the historical duplicate-revision POST or dual-upload-lane race. The sanitized artifact's zero diagnostics concealed the cause, but the hosted job log was sufficient; no future hosted run is needed to diagnose it."

## Resolution
<!-- OVERWRITE as understanding evolves -->

root_cause: "The serial live-server suite shares one server owner/catalogue. LiveServerSnapshotTests persists Sentinel Two, while SaveEndToEndTests later uses a fresh local client profile and verifies that its mirror contains only Sentinel One. Fixture provisioning reuses the owner and does not clear the second sentinel, so the hosted verification observes both rows and fails."
fix: "Not applied in this diagnosis-only session."
oracle_type: specified
verification:
  target_test:
    result: diagnosis
    evidence: "The hosted CI job log gives the exact failing invariant and observed two-row contents; local source confirms the serialized test order, persistent sentinel action, owner reuse, and first-only expectation."
  mutation_check:
    result: skipped
    reason_if_skipped: "No code changes were authorized in this bounded diagnosis task."
