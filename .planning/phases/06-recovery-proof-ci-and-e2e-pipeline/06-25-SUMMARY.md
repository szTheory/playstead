---
phase: 06-recovery-proof-ci-and-e2e-pipeline
plan: 25
subsystem: recovery-evidence
tags: [postgres, bash, ci, restore, privacy]
requires:
  - phase: 06-recovery-proof-ci-and-e2e-pipeline/plan-24
    provides: Exact source database-connect operation marker and hosted diagnostic receipt
provides:
  - Finite retry of the source PostgreSQL read-only connectivity query
  - Synthetic contracts for retry bounds, fixed delay, private output, and stage ownership
  - Successful exact source-code-head Linux recovery evidence
affects: [phase-06-recovery, hosted-ci-evidence]
actuals:
  tokens: 5019
  tasks: 3
  commits: 3
plan_head_before: e321fbe7923dbeb226f42d89508bae7553630f7e
tech-stack:
  added: []
  patterns: [bounded read-only connectivity retry, sanitized exact-head evidence]
key-files:
  created:
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-25-SUMMARY.md
  modified:
    - playstead-server/lib/mix/tasks/playstead.restore.ex
    - playstead-server/scripts/tests/recovery-fixture-test.sh
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md
key-decisions:
  - "Keep the same read-only psql SELECT 1 operation and fixed 20-attempt, 500 ms inter-attempt bound."
  - "Do not infer why the previous source connection probe failed from the later passing source-head run."
  - "Keep the source-head record separate from the post-evidence exact-current-PR-head merge gate."
patterns-established:
  - "Guard operational retries with a synthetic contract for command, fixed delay, finite termination, and private output."
  - "Record hosted source-head evidence separately from the final uncommitted merge-gate result."
requirements-completed: []
coverage:
  - id: D1
    description: "The source PostgreSQL connectivity operation retries at most 20 times with a fixed 500 ms delay while keeping command output private."
    requirement: PORT-04
    verification:
      - kind: other
        ref: "bash playstead-server/scripts/tests/recovery-fixture-test.sh; recovery-fixture.sh --self-test; sanitizer-test.sh; run-mac-verification.sh --self-test-contracts; bash -n; git diff --check"
        status: pass
    human_judgment: false
  - id: D2
    description: "The exact source-code-head hosted run validates a successful sanitized Linux recovery receipt and successful Docker, Mix, and ordinary Mac jobs."
    requirement: QUAL-02
    verification:
      - kind: integration
        ref: "GitHub Actions workflow 36983412255 on a9c5adfe72a56c88ea567ad470757fdc44e006ef; sanitized linux-recovery-evidence/recovery-e2e.json"
        status: pass
    human_judgment: true
    rationale: "The hosted source-head run does not close the separate final PR-head gate or the broader entitlement, continuation, and phase requirements."
duration: 102min
completed: 2026-10-02
status: complete
source_head_sha: a9c5adfe72a56c88ea567ad470757fdc44e006ef
source_head_run_id: 36983412255
source_head_outcome: passed
source_head_failure_stage: none
---

# Phase 06 Plan 25: Source Connection Retry and Recovery Evidence Summary

**The source database's read-only connectivity query now uses a fixed retry bound, and exact-head hosted CI passed Linux recovery with a validated sanitized success receipt.**

## Performance

- **Duration:** 102 minutes
- **Started:** 2026-10-02T07:30:00Z
- **Completed:** 2026-10-02T09:12:09Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Added a helper that retries the same private-output `psql ... SELECT 1` source connectivity operation at most 20 times with a fixed 500 ms delay between failed attempts. Exhaustion returns only a fixed error value; the `source-fixture-database-connect` marker and existing seed operation remain unchanged.
- Added static retry contracts. The targeted contract first failed as expected before implementation, then passed with all plan-approved synthetic/static checks.
- Completed exact source-head workflow 36983412255 on SHA `a9c5adfe72a56c88ea567ad470757fdc44e006ef`. Docker job `110762899299`, Mix job `110762899658`, Linux recovery job `110762899730`, and ordinary Mac job `110765032780` all succeeded.
- Validated only the named sanitized Linux artifact. It contained exactly one `recovery-e2e.json` receipt with schema version 1, lane `linux_restore_fixture`, outcome `passed`, and stages `chain`, `preflight`, `database`, `cas`, `manifest`, and `api`.
- Recorded source-code-head evidence separately from the exact-current-PR-head run required after the evidence and summary commit. No Plan 06-26 was created because the validated source-head receipt passed.

## Task Commits

1. **Task 1 RED: bounded source-connect retry contract** - `94c3539` (`test`)
2. **Task 2 GREEN: bounded source-connect retry** - `a9c5adf` (`fix`)
3. **Task 3: exact source-head evidence and summary** - committed atomically with this summary; hash returned in the execution handoff.

## Files Created/Modified

- `playstead-server/lib/mix/tasks/playstead.restore.ex` - Added the finite retry helper around the existing read-only source database query.
- `playstead-server/scripts/tests/recovery-fixture-test.sh` - Added synthetic/static retry, marker, argument, and private-output contracts.
- `06-HOSTED-EVIDENCE.md` and `06-VERIFICATION.md` - Recorded the source SHA, run/job outcomes, and sanitized Linux recovery receipt.
- `06-25-SUMMARY.md` - Recorded plan tasks, source-head receipt, open requirements, and the separate final-head merge gate.

## Decisions Made

- The retry uses the same `source/3` output-suppressing wrapper, database role/name, and `SELECT 1` query. It sleeps only between failed attempts and preserves the fixed stage/error behavior.
- A later passing restore does not establish the cause of the previous connection-stage failure or prove that the retries were needed.
- The successful source-head run does not replace the separate post-evidence exact-current-PR-head merge gate.
- PORT-04, QUAL-02, entitlement, continuation, and aggregate regression gates remain open.

## Deviations from Plan

None - plan executed as scoped.

## Issues Encountered

The ordinary hosted Mac job remained active for about 28 minutes before all four required jobs reached success. The Plan 06-25 verifier waited for terminal state and validated the completed run; no raw log or non-Linux artifact was inspected.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Source-code-head restore evidence is green on `a9c5adfe72a56c88ea567ad470757fdc44e006ef`.
- The evidence/summary documentation commit must receive its own exact-current-PR-head hosted CI observation as the final merge gate. That run is intentionally not recorded as source-head evidence here.
- PR #6 is not merge-ready until the final exact-head gate is green. The orchestrator owns merge checks and the authorized squash merge. PORT-04, QUAL-02, entitlement, continuation, and aggregate regression remain open.

## Self-Check: PASSED

- Source, contract, hosted evidence, verification, and summary files are present.
- Task commits `94c3539` and `a9c5adf` are on the isolated branch; Task 3's atomic evidence/summary commit hash will be returned in the execution handoff.
- `source-observe` and `source-finalize` passed on run 36983412255, validating its exact source SHA, all applicable job/step outcomes, and only the named sanitized artifact.
- Plan-approved synthetic/static checks passed. No local app, Xcode/XCTest, Docker, real restore, or private fixture data was used.

---
*Phase: 06-recovery-proof-ci-and-e2e-pipeline*
*Completed: 2026-10-02*
