---
phase: 06-recovery-proof-ci-and-e2e-pipeline
plan: 21
subsystem: testing
tags: [github-actions, macos, linux, diagnostics, sanitizer]

# Dependency graph
requires:
  - phase: 06-recovery-proof-ci-and-e2e-pipeline
    provides: Existing hosted Linux restore and ordinary Mac verification lanes
provides:
  - Fixed-enum diagnostics and synthetic contracts for Mac Play-flow and Linux restore failures
  - Exact-head hosted evidence showing ordinary Mac green and Linux restore still failing
  - Scoped Linux artifact-persistence follow-up in Plan 06-22
affects: [phase-06-verification, hosted-ci, PORT-04, QUAL-02]

# Actuals (#2632)
actuals:
  tokens: 16181
  tasks: 3
  commits: 3
commits: 3
plan_head_before: 7b6524f31e67cbe428130542fd978f58cd533351

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Fixed-enum CI failure stages; raw private diagnostics stay in runner-local temporary output
    - Exact-SHA hosted evidence with first-run failures retained

key-files:
  created:
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-21-SUMMARY.md
  modified:
    - playstead-mac/Playstead/UITesting/UITestBootstrap.swift
    - playstead-mac/PlaysteadUITests/ZeroNetworkPlayFlowTests.swift
    - playstead-mac/scripts/ci/run-mac-verification.sh
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/ci/tests/sanitizer-test.sh
    - playstead-server/lib/mix/tasks/playstead.restore.ex
    - playstead-server/scripts/ci/recovery-fixture.sh
    - playstead-server/scripts/tests/recovery-fixture-test.sh
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md

key-decisions:
  - "Keep raw Mac and Mix failure details private; publish only fixed allowlisted stages."
  - "Do not infer the current Linux restore stage because no sanitized artifact was produced."
  - "Keep PORT-04, QUAL-02, entitled HID, continuation, and aggregate regression gates open."

patterns-established:
  - "A failed exact-head hosted lane remains failed even when other independent lanes pass."
  - "Sanitized evidence absence is recorded as unattributed, not reconstructed from raw runner output."

requirements-completed: []

coverage:
  - id: D1
    description: "Plan 06-21 records the current exact-head Mac pass and Linux restore failure without overclaiming the missing Linux stage."
    verification:
      - kind: other
        ref: "GitHub Actions workflow 36947656348 on cf978f4d3ece48197bf209b31cc451b73f84759e"
        status: pass
    human_judgment: true
    rationale: "The Linux gate remains red and requires the scoped follow-up before any recovery pass can be claimed."

# Metrics
duration: 3h32m
completed: 2026-10-01
status: complete
---

# Phase 06 Plan 21: Bounded Hosted Failure Diagnostics Summary

**Mac Play-flow and Linux restore diagnostics are bounded to fixed stage enums, and fresh exact-head CI confirms Mac is green while Linux remains unresolved.**

## Performance

- **Duration:** 3h32m
- **Started:** 2026-10-01T17:51:38-04:00
- **Completed:** 2026-10-01T21:23:27-04:00
- **Tasks:** 3
- **Files modified:** 10; 1 summary created

## Accomplishments

- Added a closed-schema Mac Play-flow diagnostic and sanitizer validation that emits only an allowlisted failure stage while preserving the strict zero-request assertion and cleanup behavior.
- Added fixed-enum Linux restore-stage attribution and synthetic wrapper contracts that keep raw Mix output private and suppress success receipts on failure.
- Reproduced and corrected a Mac static-guard early-return defect in `cf978f4`; fresh exact-head workflow 36947656348 passed Docker, server precommit, and ordinary Mac checks.
- Recorded the unresolved Linux failure accurately: job 110653291551 failed, sanitizer and upload were skipped, and no sanitized Linux artifact exists. Plan 06-22 is the scoped next step.
- Kept PORT-04, QUAL-02, phase aggregate completion, virtual-HID entitlement, continuation qualification, and the full regression gate open.

## Task Commits

1. **Task 1: Add fixed-enum diagnostics to the zero-network Mac Play flow** - `418fcca` (fix)
2. **Task 2: Add fixed-enum diagnostics to isolated Linux restore** - `3f2316d` (fix)
3. **Task 3: Correct the malformed-schema static guard and rerun hosted lanes** - `cf978f4` (fix)

**Plan metadata:** Included in the documentation commit for this summary and the two evidence files.

## Files Created/Modified

- `playstead-mac/Playstead/UITesting/UITestBootstrap.swift` - tracks and serializes only the closed Mac failure-stage schema.
- `playstead-mac/PlaysteadUITests/ZeroNetworkPlayFlowTests.swift` - enforces the exact result schema and strict zero-request assertion.
- `playstead-mac/scripts/ci/run-mac-verification.sh` - extracts only allowlisted stage tokens for the required test.
- `playstead-mac/scripts/ci/sanitize-evidence.sh` and `playstead-mac/scripts/ci/tests/sanitizer-test.sh` - validate bounded diagnostics and reject malformed or sentinel data.
- `playstead-server/lib/mix/tasks/playstead.restore.ex` and `playstead-server/scripts/ci/recovery-fixture.sh` - assign and expose fixed Linux restore stages while discarding raw output.
- `playstead-server/scripts/tests/recovery-fixture-test.sh` - covers allowed, malformed, missing, and duplicate stage markers plus failure cleanup.
- `06-HOSTED-EVIDENCE.md` and `06-VERIFICATION.md` - preserve exact-SHA run/job outcomes and the open Linux artifact gap.

## Decisions Made

- Publish only fixed stage enums at CI boundaries; keep arbitrary XCTest and Mix error details private.
- Treat the latest Linux failure as unattributed because no sanitized Linux artifact was produced. Do not inspect raw job output to guess its cause.
- A passing Mac lane does not compensate for a failing Linux recovery lane or close the separate entitlement and continuation gates.
- No dependencies were added, and no local app or XCTest run was performed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected a Mac static-guard closed-schema early return**
- **Found during:** Task 3 hosted rerun
- **Issue:** The first diagnostic head failed `Verify static contract guards` before app/native test layers because of a bare closed-schema early return.
- **Fix:** Corrected the guard in `cf978f4`, then passed `fail-open-test-guard-test.sh` and `run-mac-verification.sh --self-test-contracts` locally.
- **Files modified:** `playstead-mac/scripts/ci/run-mac-verification.sh`
- **Verification:** Fresh exact-head Mac ordinary job 110655090300 passed on SHA `cf978f4d3ece48197bf209b31cc451b73f84759e`.
- **Committed in:** `cf978f4`

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** The defect was isolated to a diagnostic static guard. Existing zero-network and other assertions were retained; the Linux failure remains open without an inferred cause.

## Issues Encountered

- On first Plan 06-21 run 36931486120 at SHA `3f2316d0a99ca0aff09da789dd1ea690d4bae8ab`, Docker and server precommit passed, Linux restore failed with sanitizer/upload skipped, and Mac failed at a static guard. The static defect was corrected before the fresh run.
- On fresh exact-head run 36947656348, Docker job 110653291243, server precommit job 110653291608, and ordinary Mac job 110655090300 passed. Linux restore job 110653291551 failed at `Run isolated restore fixture`; no sanitized artifact was uploaded, so the operation stage is unknown.
- The Mac artifact contained 11 files and reported reachability pass, Unit 759/759, Rendering 52/52, UI 122/122, LiveServer 6/6, and zero failed tests, accessibility issues, or layout diagnostics. Entitled status remained `blocked/not-configured`.

## User Setup Required

None - no external service configuration is required by this plan.

## Next Phase Readiness

Plan 06-22 passed plan review and targets persistence, sanitization, and upload of a fixed-enum Linux failure object. Do not merge PR #6 until all required checks are green on one exact head. Continue to hold PORT-04, QUAL-02, the phase aggregate, entitled HID, continuation, and full regression review open until their own criteria pass.

---
*Phase: 06-recovery-proof-ci-and-e2e-pipeline*
*Completed: 2026-10-01*

## Self-Check: PASSED

- Summary, hosted evidence, and verification files exist.
- Task commit hashes `418fcca`, `3f2316d`, and `cf978f4` exist in Git history.
- Diff whitespace check passed.
