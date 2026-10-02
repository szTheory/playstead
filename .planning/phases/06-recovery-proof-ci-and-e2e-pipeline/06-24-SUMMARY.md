---
phase: 06-recovery-proof-ci-and-e2e-pipeline
plan: 24
subsystem: recovery-evidence
tags: [postgres, bash, ci, restore, privacy]
requires:
  - phase: 06-recovery-proof-ci-and-e2e-pipeline/plan-23
    provides: Distinct filesystem and database-seed failure-stage boundaries
provides:
  - Separate source PostgreSQL connectivity and fixture-seed operation markers
  - Sanitizer and wrapper acceptance of the fixed database-connect stage
  - Exact-head hosted source diagnostic for the database-connect operation
affects: [phase-06-recovery, hosted-ci-evidence]
actuals:
  tokens: 12753
  tasks: 3
  commits: 5
plan_head_before: 2727895437bcdc12e3d3ff7b139a0c6fcce3c77c
commits: 5
tech-stack:
  added: []
  patterns: [fixed-stage recovery receipts, synthetic-only boundary contracts]
key-files:
  created:
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-24-SUMMARY.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-25-PLAN.md
  modified:
    - playstead-server/lib/mix/tasks/playstead.restore.ex
    - playstead-server/scripts/ci/recovery-fixture.sh
    - playstead-server/scripts/tests/recovery-fixture-test.sh
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/ci/tests/sanitizer-test.sh
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md
key-decisions:
  - "Keep failure attribution operation-only: source-fixture-database-connect does not establish a root cause."
  - "Preserve the exact four-field sanitized failure receipt and private command-output boundary."
  - "Keep PORT-04 and QUAL-02 open; a diagnostic failure receipt is not restore success."
patterns-established:
  - "Use one fixed marker immediately before each source fixture operation."
  - "Validate hosted restore evidence against the exact PR head and inspect only the named sanitized artifact."
requirements-completed: []
coverage:
  - id: D1
    description: "Source PostgreSQL connectivity and database seed failures have separate fixed operation markers carried through wrapper and sanitizer contracts."
    requirement: PORT-04
    verification:
      - kind: other
        ref: "bash recovery-fixture-test.sh; recovery-fixture.sh --self-test; sanitizer-test.sh; run-mac-verification.sh --self-test-contracts"
        status: pass
    human_judgment: false
  - id: D2
    description: "The exact source-code-head hosted run preserves a sanitized database-connect failure receipt while keeping Linux restore red."
    requirement: QUAL-02
    verification:
      - kind: integration
        ref: "GitHub Actions run 36971165164; sanitized linux-recovery-evidence/recovery-failure.json"
        status: fail
    human_judgment: true
    rationale: "The hosted restore remains red. The fixed stage identifies an operation boundary only and cannot demonstrate recovery success or identify the cause."
duration: 102min
completed: 2026-10-02
status: complete
source_head_sha: a662c75227b9c54a3ba66af62591dfaa407912ed
source_head_run_id: 36971165164
source_head_outcome: failed
source_head_failure_stage: source-fixture-database-connect
---

# Phase 06 Plan 24: Source Database Operation Evidence Summary

**Source connectivity and seed failures have separate fixed markers; exact-head CI isolated a red source database-connect operation without attributing a cause.**

## Performance

- **Duration:** 102 minutes
- **Started:** 2026-10-02T05:39:17Z
- **Completed:** 2026-10-02T07:20:57Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Added distinct fixed markers for the one-shot source PostgreSQL connectivity probe and the existing fixture seed SQL.
- Extended the wrapper closed enum, fake-command/static contracts, and Linux sanitizer enum for `source-fixture-database-connect`, preserving the unchanged four-field failure receipt.
- Validated completed exact-head workflow 36971165164 on source SHA `a662c75227b9c54a3ba66af62591dfaa407912ed`. Docker job `110727469629`, Mix job `110727469826`, and ordinary Mac job `110729213046` succeeded. Linux job `110727469818` failed only at `Run isolated restore fixture`; sanitization and sanitized upload succeeded.
- Inspected only the named sanitized artifact. It contained exactly one regular `recovery-failure.json` with the four expected fields and stage `source-fixture-database-connect`; the stage names the failed operation only and proves no cause.
- Added the stage-matched Plan 06-25 handoff. Its bounded connection retry is explicitly a hypothesis to test, not a diagnosed root cause.

## Task Commits

1. **Task 1 RED: database-connect ownership contract** - `b6d7acd` (`test`)
2. **Task 1 GREEN: separate database operation stages** - `aac1bcd` (`feat`)
3. **Task 2 RED: sanitizer database-connect stage contract** - `3351de8` (`test`)
4. **Task 2 GREEN: allow sanitized database-connect stage** - `a662c75` (`feat`)
5. **Task 3: hosted evidence and Plan25 handoff** - committed atomically with the summary; its commit hash is returned in the execution handoff.

**Plan metadata commit:** this summary, the hosted evidence updates, and conditional Plan 06-25 are committed atomically after the source-head receipt was validated.

## Files Created/Modified

- `playstead-server/lib/mix/tasks/playstead.restore.ex` - Added one read-only `SELECT 1` source-connect operation before the unchanged seed SQL.
- `playstead-server/scripts/ci/recovery-fixture.sh` and `playstead-server/scripts/tests/recovery-fixture-test.sh` - Added the fixed connect marker to the closed stage set and synthetic/static contracts.
- `playstead-mac/scripts/ci/sanitize-evidence.sh` and `playstead-mac/scripts/ci/tests/sanitizer-test.sh` - Added exact acceptance and negative coverage for the connect marker without expanding the receipt schema.
- `06-HOSTED-EVIDENCE.md` and `06-VERIFICATION.md` - Recorded source-head SHA, run/job outcomes, and the sanitized operation stage.
- `06-25-PLAN.md` - Stage-matched diagnostic follow-up for a bounded connection retry.

## Decisions Made

- The sanitized stage remains operation attribution only; no raw PostgreSQL output or causal explanation is included.
- The same private-output source wrapper, four-field failure schema, seed SQL, and workflow semantics remain in use.
- PORT-04, QUAL-02, entitlement, continuation, and aggregate regression gates remain open.

## Deviations from Plan

None - plan executed as scoped. The hosted restore remains red and is recorded as a diagnostic outcome, not a plan failure or requirement pass.

## Issues Encountered

The fresh exact-head Linux restore still fails at `source-fixture-database-connect`. Docker cold-start, server precommit, and ordinary Mac jobs passed; the sanitizer and upload steps also passed. The operation marker does not establish why the connection probe failed. No raw logs, raw artifacts, private fixture data, paths, or credentials were inspected.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 06-25 is stage-matched to the validated `source-fixture-database-connect` receipt and has passed independent scope review.
- The post-evidence exact-current-PR-head run is a separate merge gate and is returned to the orchestrator; it is not represented as tracked source-head evidence.
- PR #6 is not merge-ready from this red Linux restore result. PORT-04, QUAL-02, entitlement, continuation, and aggregate regression remain open.

## Self-Check: PASSED

- The Plan 06-24 source/test files, updated evidence documents, this summary, and Plan 06-25 exist.
- Task commits `b6d7acd`, `aac1bcd`, `3351de8`, and `a662c75` exist on the isolated branch.
- `source-observe` and `source-finalize` both validated run 36971165164, its exact source SHA, all applicable job/step outcomes, and only the named sanitized artifact.
- Synthetic/static checks and the embedded Plan 06-25 exact-head verifier syntax passed.

---
*Phase: 06-recovery-proof-ci-and-e2e-pipeline*
*Completed: 2026-10-02*
