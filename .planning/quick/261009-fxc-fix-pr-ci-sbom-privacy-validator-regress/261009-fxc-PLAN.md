---
id: 261009-fxc
type: quick-full
status: in_progress
description: Fix PR CI SBOM privacy-validator regression and make the focused PR gates converge
must_haves:
  truths:
    - A legitimate CycloneDX SBOM generated for the smoke-tested container passes the privacy validator.
    - CycloneDX evidence containing host-private paths, forbidden evidence fields, or PRIVATE_EVIDENCE_SENTINEL is rejected before upload.
    - The tested image has no HIGH/CRITICAL vulnerabilities with a published fix; unfixed HIGH/CRITICAL findings remain counted in release evidence and are reported with safe identifiers.
    - The full image scan gates package vulnerabilities; restricted-license policy remains enforced for Playstead's resolved source dependencies without treating Debian base-system packages as app dependencies.
    - A failed scan reports bounded package, version, and advisory identifiers without raw descriptions, paths, or arbitrary scanner data.
    - Mac failure evidence accepts bounded test-timing fields, and each live-server caller verifies its own explicit synthetic fixture state.
    - The focused PR's required GitHub Actions checks finish green before this fix is reported complete.
  artifacts:
    - scripts/ci/release-evidence.py
    - scripts/ci/release-supply-chain.sh
    - scripts/tests/test_release_evidence.py
    - playstead-server/mix.lock
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/ci/live-server.sh
    - playstead-mac/PlaysteadUITests/LiveServerSnapshotTests.swift
    - playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift
  key_links:
    - The validator accepts normal generated CycloneDX metadata while enforcing the existing fail-closed privacy policy.
    - The unit regression suite exercises both safe acceptance and unsafe rejection through validate_cyclonedx.
    - Failed Trivy scans print only bounded safe identifiers through a tested helper; raw descriptions and paths never reach logs.
    - PR CI runs the regression suite and Docker SBOM validation on the same proposed commit.
    - The scanner command scopes license restrictions to app dependencies and still scans every container package for vulnerabilities.
    - Sanitized failure artifacts accept only validated timing telemetry and the live-server verifier requires a caller-declared sentinel set.
---

<objective>
Fix the focused Phase 05.1 PR failure in CycloneDX SBOM privacy validation while preserving its fail-closed privacy protections.

Purpose: GitHub Actions run 37951000739 passed the Docker build, cold-start smoke, and server `mix precommit`, then failed because `validate_cyclonedx -> clean(document)` rejected generated SBOM content. The validator blocks SBOM publication on failure. A generic local Trivy image did not reproduce the hosted SBOM, so the fix must be grounded in evidence from the smoke-tested target image or representative safe and unsafe CycloneDX documents.

Output: A narrowly scoped validator correction with deterministic regression tests, bounded privacy-safe image scan diagnostics, minimal compatible dependency fixes for actionable high/critical advisories, current stable runtime packages, and green required PR checks on `codex/phase-05-1-supply-chain`.
</objective>

<context>
- Work in the isolated PR worktree on `codex/phase-05-1-supply-chain`.
- Keep privacy validation failure-closed. Do not delete or broadly relax `clean`, its forbidden-field rules, local-path detection, or sentinel detection.
- Candidate implementation files are `scripts/ci/release-evidence.py` and `scripts/tests/test_release_evidence.py`. Modify `.github/workflows/ci.yml` only if evidence proves the workflow must change to expose or validate the target-image SBOM correctly.
- CycloneDX validation runs before SBOM upload; CI run 37951000739's relevant job failed at privacy validation. The other stated build, smoke, and precommit checks passed.
- No external client, SDK, or service API is being integrated; this quick task does not need an API coverage artifact.
- Run 37966953549 proves the SBOM validator and structural checks now pass. The Docker image scan correctly rejected `mint` 1.9.3 for high-severity advisories; Hex's advisory ledger marks those findings fixed in Mint 1.10.2. Update the lockfile to a compatible patched version.
- Debian's official security tracker reports several current Trixie high-severity CVEs with no stable fix yet (some are explicitly marked no-DSA/minor and fixed only in Forky). Keep the full Trivy report; block any HIGH/CRITICAL finding with a published fixed version, and record/report unfixed counts so they become blockers when Debian publishes a fix. Do not switch the stable runtime to Debian testing or suppress unfixable findings silently.
- Run 37983148056 on SHA `6c4d5ed24c8b9fdb96d3d2f19e09c72767e61e7d` proves the image has 48 unfixed HIGH/CRITICAL vulnerabilities and zero fixable ones, but the scan still fails on 181 restricted-license records from Debian image packages. The source dependency scan is green. Scope the license gate to source dependencies while retaining the complete image vulnerability scan and image SBOM.
- The same run exposes a Mac failure-evidence schema mismatch: the writer includes bounded timing fields, while the privacy sanitizer rejects them. It also shows that `SaveEndToEndTests` uses a fresh one-sentinel fixture but calls a verifier that always required both sentinels; require every verifier caller to declare its own expected sentinel set.
- Run 37983148056's `LiveServerSnapshotTests` missed the initial network-backed row within its existing 10-second element wait; give that first sync pass a 20-second hosted budget and retain the no-blob/readability assertions.
- Run 37970978972 proves the Mint/HPAX lockfile update removes the Mint dependency-audit findings and the server and Mac jobs pass. The image scan still fails with only a generic image-scan status, and the raw report is removed after the job. Add a bounded package/version/advisory-ID summary to the failure log without descriptions, paths, or arbitrary scanner data so the remaining image finding can be fixed from hosted evidence.
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Reproduce the hosted SBOM privacy failure with bounded evidence</name>
  <files>scripts/tests/test_release_evidence.py</files>
  <behavior>
    - A representative legitimate generated CycloneDX document, including the metadata that triggered the hosted failure, validates successfully.
    - Host-private POSIX/Windows paths, forbidden evidence keys, and PRIVATE_EVIDENCE_SENTINEL remain rejected, including when nested in CycloneDX properties.
    - Rejection errors do not echo private values.
  </behavior>
  <action>Inspect the failed CI step/log and obtain or reconstruct the exact CycloneDX metadata responsible for run 37951000739. Prefer the SBOM generated from the smoke-tested target image; if it is unavailable because validation prevents artifact upload, add a minimal representative fixture based on the failure trace and CycloneDX schema. Add focused failing regression cases in the existing release-evidence test module. Keep each unsafe case distinct so the reason for rejection is observable, and assert error text does not disclose the private sample. Do not change production validation in this task.</action>
  <verify>
    <automated>python3 -m unittest scripts.tests.test_release_evidence -v</automated>
  </verify>
  <done>The new safe generated-SBOM case reproduces the observed false rejection before the fix, while unsafe path, forbidden-field, and sentinel cases prove the privacy boundary remains covered.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Correct CycloneDX normalization without weakening privacy checks</name>
  <files>scripts/ci/release-evidence.py, scripts/ci/release-supply-chain.sh, scripts/tests/test_release_evidence.py</files>
  <behavior>
    - Valid metadata from the target-image CycloneDX SBOM is accepted.
    - Host-private paths, forbidden evidence fields, and PRIVATE_EVIDENCE_SENTINEL continue to fail closed.
    - Existing release-evidence validations continue to pass.
  </behavior>
  <action>Use Task 1's concrete safe/unsafe cases to make the smallest validator change that distinguishes generated CycloneDX metadata from actual private path or sentinel disclosure. Keep `clean` rejection behavior for forbidden keys and the sentinel, and keep local-path detection for untrusted values. If a field needs a narrow CycloneDX-specific normalization or URL treatment, scope it to the demonstrated field/value shape and explain why it cannot admit private paths. Do not broadly allowlist scanner output or weaken path matching. Run the complete release-evidence unit tests and the parser fixture regression script if available in the worktree.</action>
  <verify>
    <automated>python3 -m unittest scripts.tests.test_release_evidence -v</automated>
  </verify>
  <done>All release-evidence unit tests pass; safe target-image or representative SBOM metadata is accepted, and the negative privacy cases remain rejected without leaking their values.</done>
</task>

<task type="auto">
  <name>Task 3: Prove the correction through the focused PR CI run</name>
  <files>scripts/ci/release-evidence.py, scripts/ci/release-supply-chain.sh, scripts/tests/test_release_evidence.py</files>
  <behavior>
    - Scan failures emit a bounded summary of high/critical package, version, finding ID, severity, and whether a fixed version exists.
    - Evidence records total, fixable, and unfixed high/critical vulnerability counts; only fixable high/critical vulnerabilities block this stable-runtime release gate.
    - Path-like or forbidden identifiers are redacted; raw descriptions and scanner JSON are never logged.
    - Application dependency licensing remains a release gate; the image scan still covers all container package vulnerabilities.
    - Mac failure evidence accepts bounded timing telemetry and each live-server test verifies its own declared sentinel set.
    - The exact pushed commit's full required GitHub Actions checks complete successfully.
  </behavior>
  <action>Emit bounded safe summaries for failing fixable findings and for unfixed findings retained in evidence. Include only validated package name/version, finding ID, severity, and a Boolean fix-availability signal; do not log descriptions, paths, or raw Trivy JSON. Keep vulnerability scanning on the full image but apply restricted-license policy to the app dependency source scan. Accept and strictly validate the sanitizer's bounded timing fields. Make the live-server verifier require an explicit one- or two-sentinel expectation per caller; add a synthetic SQLite seam test and a bounded row-existence wait for the first network sync. Refresh the Debian stable runtime pin independently from the Hex builder tag and apply available Debian security updates. Add tests for scanner scope, counts, fail/pass behavior, fixture states, and hostile-value redaction. Commit and push only focused changes to the authorized PR branch.</action>
  <verify>
    <automated>python3 -m unittest scripts.tests.test_release_evidence -v; bash playstead-mac/scripts/ci/run-mac-verification.sh --self-test-contracts</automated>
    <hosted>After pushing, obtain the exact fix commit SHA and query the connected GitHub workflow API with `github_fetch_commit_workflow_runs({repo_full_name: "szTheory/playstead", commit_sha: "&lt;fix-commit-sha&gt;"})`. Select the PR CI run for that exact SHA and require `status: completed` and `conclusion: success`. Then query `github_fetch_workflow_run_jobs({repo_full_name: "szTheory/playstead", run_id: &lt;run-id&gt;})`; require every required job in the run to be completed successfully. Query `github_fetch_workflow_job_steps` for the Docker job and require the `Scan tested image and validate release evidence` step to have conclusion `success`. Record the run URL, run ID, SHA, required-job results, and Docker-step result in the quick summary. A missing run, pending/in-progress run, failed required job, or missing/failed named step does not pass verification; diagnose and rerun after fixes.</hosted>
  </verify>
  <done>The focused correction passes local scanner, sanitizer, Mac fixture, and topology contracts; Task 4 verifies all exact-head hosted gates.</done>
</task>

<task type="auto">
  <name>Task 4: Prove all fixes through exact-head hosted CI</name>
  <files>.github/workflows/ci.yml, scripts/ci/release-evidence.py, scripts/ci/release-supply-chain.sh, playstead-mac/scripts/ci/live-server.sh, playstead-mac/scripts/ci/sanitize-evidence.sh</files>
  <behavior>
    - The exact pushed commit's server, Docker cold-start and scan, and macOS verification gates complete successfully.
    - Mac failure artifacts remain privacy-safe if a later regression occurs.
  </behavior>
  <action>Push the focused correction and query the connected GitHub workflow API for the exact full SHA. Require the PR CI run to complete successfully, every required job to pass, and the named `Scan tested image and validate release evidence` step to pass. If a check fails, inspect the sanitized evidence and correct the observed cause; never infer that a pending or superseded run passed. Record the exact run URL, ID, SHA, and required gate outcomes in the quick summary.</action>
  <verify>
    <hosted>After pushing, query `github_fetch_commit_workflow_runs`, `github_fetch_workflow_run_jobs`, and `github_fetch_workflow_job_steps` for the exact full SHA and named Docker scan step.</hosted>
  </verify>
  <done>All required CI jobs and the named Docker scan step are green on the exact pushed SHA, with their evidence recorded in the GSD quick summary.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Container build output → release evidence validator | Generated SBOM JSON may contain untrusted strings and host-specific build metadata; it is validated before upload. |

## STRIDE Threat Register (ASVS level 1; block on high)

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261009-FXC-01 | Information disclosure | `clean` / `validate_cyclonedx` in `scripts/ci/release-evidence.py` | high | mitigate | Preserve path, forbidden-field, and sentinel rejection and prove each with focused tests before allowing the generated SBOM artifact to upload. |
| T-261009-FXC-02 | Tampering | CycloneDX validator regression tests | medium | mitigate | Exercise the exact target-image metadata and hostile values using deterministic tests so future validator changes cannot silently bypass privacy rejection. |
</threat_model>

<verification>
- Run `python3 -m unittest scripts.tests.test_release_evidence -v` from the repository root.
- Confirm unsafe path, forbidden-field, and sentinel cases fail closed, while the legitimate generated target-image SBOM validates.
- Confirm scan-failure diagnostics include only bounded safe package/version/finding identifiers, with hostile values redacted and raw descriptions/paths absent.
- Confirm all required checks for the focused PR complete green on the fix commit; preserve the run URL, run ID, and SHA in the quick summary.
</verification>

<success_criteria>
The validator accepts the legitimate generated CycloneDX SBOM that caused CI run 37951000739 to fail and continues to reject the specified privacy violations. The runtime uses current stable Debian packages; the full image vulnerability scan blocks every HIGH/CRITICAL vulnerability with a published fix, while unfixed findings remain counted and safely reported. Restricted-license review gates resolved Playstead source dependencies without treating Debian base-system packages as application dependencies. The Mac failure sanitizer preserves strictly validated timing telemetry, and every live-server test names its own expected fixture state. The focused PR CI run is green before completion is reported.
</success_criteria>

<output>
Create a GSD quick summary in this directory recording the evidence used, the exact validator/test changes, local test results, and the final PR CI run identifier and SHA.
</output>
