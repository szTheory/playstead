---
status: awaiting_human_verify
trigger: "Protected-main release attestations failed after PR #9 was squash-merged. Run 38011046324 / merge commit 162f6648ff97b7c2a7e9495986fc6f2566fe0b58. The job failed at `Check downloaded tested archive and scan manifest`: `release evidence rejected: evidence fields must be exactly ['attestations', 'handoff', 'mode', 'parser_inventory', 'sbom', 'scans', 'schema_version', 'subject']`."
created: 2026-10-10T01:12:35Z
updated: 2026-10-10T01:15:46Z
---

## Current Focus

hypothesis: Confirmed: canonical evidence includes a derived verdict rejected by validate; the attestation path changes the mode while retaining that verdict.
test: Focused Python suite, source-revert reconfirmation, diff check; hosted protected-main run pending.
expecting: Protected-main revalidation passes, verified attestations produce release-ready evidence for the tested archive digest.
next_action: Review PR #10 under the existing three-check gate; after merge, confirm the protected-main release-attestation job and digest-bound release-ready artifact.
bug_class: Bohrbug
reasoning_checkpoint:
  hypothesis: "validate rejects its own canonical verdict because its accepted field set only includes raw fields; attestation finalization carries the PR verdict after mode changes."
  confirming_evidence:
    - "validate emits verdict at line 326 but exact input schema excludes it at line 251."
    - "The protected-main workflow revalidates the emitted evidence.json, and attestation finalization reads that same file before changing mode."
  falsification_test: "If the pre-fix validator accepts canonical output or finalizes canonical PR evidence with correct release verdict, this hypothesis is false."
  fix_rationale: "Accept a canonical verdict only when it equals the one derived from the current mode; validate the input before transition, then remove and recompute the verdict for release mode."
  blind_spots: "Hosted GitHub attestation issuance cannot be reproduced locally."
  candidate_causes:
    - "code: canonical output and input schemas differ; transition retains derived state."
    - "data: artifact may be malformed or corrupt in transit."
    - "environment: hosted runner may execute a different revision of the validator."
  and_gate: "yes: revalidation failure requires canonical verdict-bearing data and the validator schema mismatch; transition additionally needs a mode change with the old verdict present."

## Symptoms

expected: The protected-main workflow verifies provenance and CycloneDX attestations for the exact smoke-tested archive digest, then uploads release-ready evidence.
actual: The downloaded archive and manifest pass presence and SHA-256 checks, but evidence revalidation exits 1 before either attestation is issued.
errors: "release evidence rejected: evidence fields must be exactly ['attestations', 'handoff', 'mode', 'parser_inventory', 'sbom', 'scans', 'schema_version', 'subject']"
reproduction: Run python3 scripts/ci/release-evidence.py --input evidence.json --output revalidated.json on the tested-release-evidence artifact from run 38011046324.
started: First observed on protected-main push after PR #9 merged at 2026-10-10T00:54:44Z.

## Eliminated

- hypothesis: Artifact download or archive digest mismatch.
  evidence: Downloaded files exist and archive SHA-256 matches evidence subject before validator fails.
  timestamp: 2026-10-10T01:02:33Z

## Evidence

- timestamp: 2026-10-10T01:02:33Z
  checked: Protected-main run 38011046324 and artifact.
  found: Archive digest check succeeds; validator rejects verdict field.
  implication: Failure occurs at schema revalidation.

- timestamp: 2026-10-10T01:06:00Z
  checked: Validator and supply-chain producer at merge SHA 162f664.
  found: Producer writes validate() result with verdict; validator requires exactly eight raw fields. Attestation path mutates mode on the same record.
  implication: Canonical output cannot be revalidated or safely transitioned without handling derived verdict.

- timestamp: 2026-10-10T01:15:00Z
  checked: Three new regression tests against merge SHA 162f664.
  found: Canonical revalidation fails for both modes; PR-to-release finalization fails; forged verdict rejection has only the generic schema error.
  implication: The regression suite reproduces both failing paths before implementation and requires specific forged-verdict validation.

- timestamp: 2026-10-10T01:15:46Z
  checked: Fixed validator, attestation transition, and release evidence test suite.
  found: All 28 tests pass. Reversing the source patch restores the two exact regressions; reapplying it returns all 28 to passing. git diff --check passes.
  implication: The fix addresses the reproduced incompatibility without weakening the scan, SBOM, parser inventory, attestation, or handoff validation.

## Resolution

root_cause: Validator input schema rejects its own canonical verdict; attestation transition retains a prior mode's derived verdict.
oracle_type: derived
fix: Accept an optional canonical verdict only when it equals the mode-derived value; validate input before attestation processing, remove its old verdict during PR-to-release transition, then derive the release verdict.
verification:
  target_test: {result: pass, details: "Canonical CLI revalidation, forged verdict rejection, and PR-to-release transition tests pass."}
  mutation_check: {result: skipped, reason_if_skipped: "Stryker is not configured for this Python project."}
  no_op_deletion: {result: pass, deletion_justified_by_rca: true}
  adjacent_tests: {result: pass, suites_run: ["python3 -m unittest scripts.tests.test_release_evidence (28 tests)"]}
  revert_and_reconfirm: {result: pass, bug_returned_on_revert: true, fixed_on_reapply: true}
  guardrail_verdict: accepted
  hosted_run: pending
files_changed: [scripts/ci/release-evidence.py, scripts/tests/test_release_evidence.py]
fix_commit: aa9ee18
follow_up_pr: https://github.com/szTheory/playstead/pull/10
