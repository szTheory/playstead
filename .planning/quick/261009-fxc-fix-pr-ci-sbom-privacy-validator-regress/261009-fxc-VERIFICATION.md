---
phase: 261009-fxc-fix-pr-ci-sbom-privacy-validator-regress
verified: 2026-10-10T00:18:45Z
status: passed
score: 11/11 must-haves verified
covered_files:
  - .github/workflows/ci.yml
  - .planning/debug/live-server-initial-row-missing.md
  - .planning/debug/save-e2e-hosted-failure.md
  - .planning/quick/261009-fxc-fix-pr-ci-sbom-privacy-validator-regress/261009-fxc-PLAN.md
  - .planning/quick/261009-fxc-fix-pr-ci-sbom-privacy-validator-regress/261009-fxc-SUMMARY.md
  - playstead-mac/PlaysteadUITests/CurationInteractionTests.swift
  - playstead-mac/PlaysteadUITests/LiveServerSnapshotTests.swift
  - playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift
  - playstead-mac/scripts/ci/live-server.sh
  - playstead-mac/scripts/ci/run-mac-verification.sh
  - playstead-mac/scripts/ci/sanitize-evidence.sh
  - playstead-mac/scripts/ci/tests/four-layer-topology-test.sh
  - playstead-mac/scripts/ci/tests/four-layer-verifier-test.sh
  - playstead-mac/scripts/ci/tests/live-server-verification-test.sh
  - playstead-mac/scripts/ci/tests/sanitizer-test.sh
  - playstead-server/Dockerfile
  - playstead-server/docker-compose.ci.yml
  - playstead-server/lib/mix/tasks/playstead.mac_ci_fixture.ex
  - playstead-server/mix.lock
  - playstead-server/priv/recovery/parser-fixture-inventory.json
  - playstead-server/scripts/parser-fixture-inventory.sh
  - playstead-server/scripts/tests/parser-fixture-inventory-schema-test.sh
  - playstead-server/test/mix/tasks/playstead_mac_ci_fixture_test.exs
  - scripts/ci/release-evidence.py
  - scripts/ci/release-supply-chain.sh
  - scripts/ci/trivy.yaml
  - scripts/tests/test_release_evidence.py
covered_digest: "v3:sha256:8d34e8e72a24496c98fed2bcc997135d046b35ea51430e1291ed56397dc085f2"
behavior_unverified: 0
overrides_applied: 0
gaps: []
---

# Quick Task 261009-fxc Verification Report

**Goal:** Fix the Phase 05.1 PR CI SBOM privacy-validator regression while preserving privacy checks and make the focused PR gates reliable and actionable.
**Verified:** 2026-10-10T00:18:45Z
**Status:** passed

## Goal Achievement

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Legitimate CycloneDX 1.7 generated for the smoke-tested image passes privacy validation. | ✓ VERIFIED | Exact-head run [38006269757](https://github.com/szTheory/playstead/actions/runs/38006269757) passed the tested-image scan/evidence step; the tested release-evidence artifact was uploaded. |
| 2 | Host-private paths, forbidden evidence fields, and the privacy sentinel are rejected without echoing values. | ✓ VERIFIED | Release-evidence regression suite passed locally and in server CI; it covers nested paths, forbidden fields, sentinels, and redacted failures. |
| 3 | The image blocks every fixable HIGH/CRITICAL vulnerability and keeps unfixed findings in digest-bound evidence. | ✓ VERIFIED | Run 38006269757 reported 48 HIGH/CRITICAL findings without a published fix, retained in the evidence; the scan passed, so fixable findings were 0. |
| 4 | The full image remains vulnerability-scanned, while restricted-license policy applies to Playstead source dependencies. | ✓ VERIFIED | Scanner-scope contract passed and the exact-head `Scan tested image and validate release evidence` step succeeded. |
| 5 | Scan diagnostics are bounded and exclude raw descriptions, paths, and arbitrary scanner values. | ✓ VERIFIED | Sanitizer and release-evidence tests passed; hosted scan output retained only bounded finding identifiers and fix availability. |
| 6 | GitHub Actions cache outages cannot fail the image build or release-evidence gate. | ✓ VERIFIED | The exact-head Docker image build, cold-start, scan, and evidence upload all passed with cache export configured as fail-soft. |
| 7 | Compose smoke runs parser fixtures in `MIX_ENV=test` against a ready isolated PostgreSQL service. | ✓ VERIFIED | The hosted Docker job's parser fixture inventory passed 7 properties and 42 tests before the image build and smoke. |
| 8 | Curation drag checks allow 10 seconds for post-drag evidence and emit only allowlisted failure stages. | ✓ VERIFIED | Hosted Mac UI tests passed 53 required tests; local Mac topology and four-layer contracts verify the bounded stage tokens. |
| 9 | Mac failure evidence accepts bounded timing fields and live-server tests declare their own fixture state. | ✓ VERIFIED | All hosted Mac layers passed, including 5/5 live-server tests; local sanitizer, fixture-verifier, and topology contracts passed. |
| 10 | First-only fixture setup removes only the exact second synthetic catalogue row, journals the removal, and preserves blob bytes and receipts. | ✓ VERIFIED | The exact-head live-server layer passed; the focused synthetic SQLite regression verifies refreshed snapshots, the tombstone, retained bytes, and import receipt. |
| 11 | Required PR checks pass on the exact implementation commit. | ✓ VERIFIED | Run 38006269757 completed successfully on SHA `f7e6aaca5beb19202366fab67f1624b99578c1f7`; server, Docker, and macOS jobs passed and the named image-scan step passed. |

**Score:** 11/11 must-haves verified

## Hosted Evidence

Run [38006269757](https://github.com/szTheory/playstead/actions/runs/38006269757) completed successfully on exact SHA `f7e6aaca5beb19202366fab67f1624b99578c1f7`.

| Gate | Result | Evidence |
|---|---|---|
| `mix precommit (unit + LiveView + browser + integration)` | ✓ PASS | 1,076 tests, 0 failures. |
| `docker compose cold start` | ✓ PASS | Parser-fixture inventory: 7 properties, 42 tests, 0 failures; image build, cold start, scan, and tested evidence upload passed. |
| `Scan tested image and validate release evidence` | ✓ PASS | 48 unfixed HIGH/CRITICAL findings retained; 0 fixable findings. |
| `macOS 26 unit + rendering + UI + live server` | ✓ PASS | Unit 34/665, rendering 8/45, UI 53/113, live-server 5/5 required/executed tests passed. |
| `Protected-main release attestations` | Skipped as expected | Pull request runs do not produce protected-main attestations. |

The run uploaded `tested-release-evidence` (artifact `11651333120`, SHA-256 `9a4f3f30e281d7603de4b0799e2b987c0d721c46e5939551924edf458c87413c`) and `complete-verification-evidence` (artifact `11652625228`, SHA-256 `fb38aa71f7fa12b832cf183850e5baa8ee9378922a8cf803d62c5affc49bf808`).

## Local Verification

- `python3 -m unittest scripts.tests.test_release_evidence -v` — 25 tests passed.
- `/opt/homebrew/bin/bash playstead-server/scripts/parser-fixture-inventory.sh --self-test` — 7 properties, 42 tests, 0 failures; its isolated database was removed afterward.
- `playstead-mac/scripts/ci/run-mac-verification.sh --self-test-contracts` — 43 Python tests and all static shell contracts passed.
- `actionlint`, modified shell syntax checks, CI Compose validation, and `git diff --check` passed.

## Human Verification Required

None. All task acceptance criteria are covered by deterministic local contracts or the exact-head hosted CI run.
