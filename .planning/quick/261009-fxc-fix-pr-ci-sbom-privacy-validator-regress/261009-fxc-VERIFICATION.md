---
phase: 261009-fxc-fix-pr-ci-sbom-privacy-validator-regress
verified: 2026-10-09
status: gaps_found
score: 3/7 must-haves verified
covered_files:
  - .planning/quick/261009-fxc-fix-pr-ci-sbom-privacy-validator-regress/261009-fxc-PLAN.md
  - .planning/quick/261009-fxc-fix-pr-ci-sbom-privacy-validator-regress/261009-fxc-SUMMARY.md
  - playstead-server/Dockerfile
  - playstead-server/mix.lock
  - scripts/ci/release-evidence.py
  - scripts/ci/release-supply-chain.sh
  - scripts/ci/trivy.yaml
  - scripts/tests/test_release_evidence.py
  - playstead-mac/scripts/ci/sanitize-evidence.sh
  - playstead-mac/scripts/ci/tests/sanitizer-test.sh
  - playstead-mac/scripts/ci/live-server.sh
  - playstead-mac/scripts/ci/tests/live-server-verification-test.sh
  - playstead-mac/PlaysteadUITests/LiveServerSnapshotTests.swift
  - playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift
covered_digest: "pending-final-recalculation"
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "The smoke-tested image has no HIGH/CRITICAL vulnerability with a published fix; unfixed findings remain counted and visible."
    status: partial
    reason: "The exact-head run 37983148056 confirms zero fixable and 48 unfixed HIGH/CRITICAL findings, and local contracts prove the policy. The corrected image scan scope has not yet passed on a new exact-head run."
    artifacts:
      - path: "playstead-server/Dockerfile"
        issue: "The refreshed image and fixability-aware scan require a new exact-head hosted result after the license-scope correction."
    missing:
      - "Successful exact-head hosted scan with zero fixable HIGH/CRITICAL findings and the unfixed count recorded."
  - truth: "Restricted-license policy blocks Playstead source dependencies without rejecting the Debian image's base-system packages."
    status: partial
    reason: "Run 37983148056 reports 181 restricted-license findings from the image scan while the source scan is green. The scanner-scope correction passes local contract tests but has not run in hosted CI."
    artifacts:
      - path: "scripts/ci/release-supply-chain.sh"
        issue: "The image scanner now runs vulnerability checks only; the source dependency scan retains vulnerability and license checks."
    missing:
      - "A new exact-head scan showing the image vulnerability report passes and the source license gate remains active."
  - truth: "The Mac sanitizer accepts bounded timing fields and the live-server verifier checks each caller's explicit fixture state."
    status: partial
    reason: "Sanitizer timing validation and the one-versus-two-sentinel mirror contracts pass locally. The hosted run that exposed the fixture mismatch predates the fixture correction."
    artifacts:
      - path: "playstead-mac/scripts/ci/live-server.sh"
        issue: "The new exact-head Mac verification must exercise both caller-specific sentinel expectations and the extended initial-row wait."
    missing:
      - "A green exact-head Mac verification run after the fixture correction."
  - truth: "The focused PR's required GitHub Actions checks finish green on the exact fix commit."
    status: partial
    reason: "Run 37983148056 targets exact SHA 6c4d5ed24c8b9fdb96d3d2f19e09c72767e61e7d and failed the Docker scan and Mac verification; a new corrected commit still needs hosted verification."
    artifacts:
      - path: ".github/workflows/ci.yml"
        issue: "The exact-head server, Docker and Mac jobs must complete green after the in-progress corrections are pushed."
    missing:
      - "Completed green test, Docker cold-start/scan and Mac verification jobs for the corrected full SHA."
---

# Quick Task 261009-fxc Verification Report

**Goal:** Fix the Phase 05.1 PR CI SBOM privacy-validator regression while preserving privacy checks and making supply-chain and Mac seam failures actionable.
**Verified:** 2026-10-09
**Status:** gaps_found — focused corrections are locally verified; exact-head hosted CI is still required.

## Goal Achievement

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Legitimate Trivy CycloneDX 1.7 from the smoke-tested image passes privacy validation. | ✓ VERIFIED | Run 37983148056 reached image-scan findings after CycloneDX validation; the earlier local Playstead image generated 92 components and validated successfully. |
| 2 | Host-private paths, forbidden evidence fields and the privacy sentinel are rejected without echoing their values. | ✓ VERIFIED | The release-evidence unit suite covers nested paths, Windows/UNC/POSIX paths, forbidden fields, sentinel rejection and redacted diagnostics. |
| 3 | The final image blocks every fixable HIGH/CRITICAL finding and preserves unfixed counts in digest-bound evidence. | ⚠️ PARTIAL | Unit tests prove fixable findings block and unfixable findings remain counted. Hosted run 37983148056 observed zero fixable and 48 unfixed findings, but the corrected scanner scope has not yet passed hosted CI. |
| 4 | Scan diagnostics are bounded and privacy-safe for failures and unfixed findings. | ✓ VERIFIED | Tests prove the 25-example cap, safe identifiers, fix-availability booleans, and omission of private paths, descriptions and arbitrary scanner values; hosted run 37979493239 emitted bounded package findings. |
| 5 | Restricted-license policy applies to Playstead source dependencies while the full image remains vulnerability-scanned. | ⚠️ PARTIAL | The source scan passed and the old image scan produced 181 Debian license records. The updated command scopes image scanning to vulnerabilities and preserves source dependency license scanning; local regression tests pass, pending hosted confirmation. |
| 6 | Mac failure evidence accepts bounded timing fields and each live-server caller verifies its own fixture state. | ⚠️ PARTIAL | Run 37983148056 confirms the timing sanitizer accepted and uploaded the failure artifact. Caller-specific sentinel expectations, the synthetic SQLite seam test and 20-second first-sync wait now pass locally, pending hosted Mac verification. |
| 7 | Required PR CI checks finish green on the exact fix commit. | ⚠️ PENDING | The scanner-scope and Mac fixture changes are not yet pushed; exact-head server, Docker scan and Mac results are therefore outstanding. |

**Score:** 3/7 must-haves verified

## Required Artifacts

| Artifact | Status | Evidence |
|---|---|---|
| `scripts/ci/release-evidence.py` | ✓ VERIFIED locally | Retains strict SBOM privacy checks, counts total/fixable/unfixed HIGH/CRITICAL findings, and rejects evidence with a published fix or inconsistent counts. |
| `scripts/ci/release-supply-chain.sh` | ⚠️ HOSTED CONFIRMATION PENDING | Full image vulnerability scanning remains enabled; restricted-license checks stay enabled for the Playstead source dependency scan. Scope contract tests pass. |
| `playstead-mac/scripts/ci/live-server.sh` | ⚠️ HOSTED CONFIRMATION PENDING | Requires the caller to declare `first-only` or `both`; both expectations pass synthetic SQLite tests. |
| `playstead-mac/PlaysteadUITests/LiveServerSnapshotTests.swift` and `SaveEndToEndTests.swift` | ⚠️ HOSTED CONFIRMATION PENDING | Callers declare their actual fixture sets; the initial network-backed row has a 20-second wait. |
| `scripts/tests/test_release_evidence.py` | ✓ VERIFIED | `python3 -m unittest scripts.tests.test_release_evidence -v` — 21 tests passed. |
| `playstead-mac/scripts/ci/tests/live-server-verification-test.sh` | ✓ VERIFIED | Both expected fixture variants pass and an unexpected mirror set fails. |
| `.github/workflows/ci.yml` | ⚠️ EXACT-HEAD RUN PENDING | Must pass on the final pushed SHA, including named image scan and Mac verification. |

## Behavioral Spot-Checks

| Behavior | Evidence | Status |
|---|---|---|
| Safe generated-format metadata and fail-closed privacy regressions | `python3 -m unittest scripts.tests.test_release_evidence -v` — 21 passed | ✓ PASS |
| Fixable versus unfixed HIGH/CRITICAL policy | Contract tests cover fixable failure, unfixed counts, and evidence consistency | ✓ PASS |
| Bounded scanner diagnostics and scanner scope | Unit tests plus exact image-vulnerability/source-license command contract | ✓ PASS locally |
| Sanitizer timing fields | Hosted failure artifact uploaded in run 37983148056; 35 sanitizer checks pass locally | ✓ PASS |
| Per-caller live-server mirror evidence | Synthetic SQLite contract and topology suite pass locally | ✓ PASS locally |
| Four-layer shell contracts | `run-mac-verification.sh --self-test-contracts` — 43 Python tests plus shell contracts passed | ✓ PASS locally |
| Exact-head PR CI | No run exists yet for the current unpushed changes | ⚠️ PENDING |

## Requirements Coverage

This quick task declares no roadmap requirement IDs. Its seven plan must-haves are assessed above.

## Human Verification Required

None for this CI task. The remaining scan, fixture and exact-head checks are machine-verifiable in hosted CI.

## Gaps Summary

The original CycloneDX privacy regression, bounded diagnostic path, Debian fixability policy and timing-field sanitizer have evidence. The last hosted run exposed two remaining issues: the image license scan was applying application policy to Debian base packages, and the shared Mac verifier expected two sentinels from a one-sentinel test profile. Both are corrected with local regression coverage. Push these focused changes, then keep the quick task open until the exact final SHA passes the server, Docker build/cold-start/scan and Mac verification gates.

---

_Verifier: gsd-verifier_
