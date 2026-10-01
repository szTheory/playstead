---
phase: 06-recovery-proof-ci-and-e2e-pipeline
plan: 19
subsystem: ci-security
tags: [github-actions, self-hosted-runners, macos-ci, evidence]
requires: []
provides:
  - Public PR workflow without a persistent self-hosted runner path
  - Trusted-code regression coverage for runner topology
  - Updated exact-SHA evidence showing current hosted failures and open gates
affects: [06-21, phase-06-regression-gate]
actuals:
  tokens: 7252
  tasks: 2
  commits: 2
tech-stack:
  added: []
  patterns: [zero-runner inventory for public PR trust boundary, trusted-code runner topology regression guard]
key-files:
  created:
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-19-SUMMARY.md
  modified:
    - .github/workflows/ci.yml
    - playstead-mac/scripts/ci/tests/four-layer-topology-test.sh
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md
key-decisions:
  - "Treat zero registered Actions runners on this personal-user-owned public repository as the live trust boundary; the repository guard is regression coverage only."
  - "Keep entitlement blocked/not-configured and leave merge blocked until current exact-head hosted CI is green."
patterns-established:
  - "Record runner owner type and inventory count with a UTC timestamp before merge decisions."
  - "Keep sanitized historical passes distinct from current exact-head failures and failed-only retries."
requirements-completed: []
coverage:
  - id: D1
    description: Public pull-request workflow cannot select a persistent self-hosted runner.
    verification:
      - kind: other
        ref: "actionlint .github/workflows/ci.yml"
        status: pass
      - kind: other
        ref: "bash playstead-mac/scripts/ci/run-mac-verification.sh --self-test-contracts"
        status: pass
    human_judgment: false
  - id: D2
    description: Current exact-head recovery workflow passes Linux and ordinary Mac lanes.
    verification:
      - kind: integration
        ref: "GitHub Actions workflow 36920283265, SHA f978fa8268328e0c2106f1aa0b45315832ce440f"
        status: fail
    human_judgment: true
    rationale: Current Linux recovery failed twice and the ordinary Mac zero-network flow assertion failed; hosted CI must pass on the exact final SHA before merge.
duration: 13min
completed: 2026-10-01
status: complete
---

# Phase 06 Plan 19: Remove public PR self-hosted runner exposure

**Public PR CI no longer routes code to a persistent self-hosted runner; current Linux and Mac failures remain open and prevent merge.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-10-01T21:06:00Z
- **Completed:** 2026-10-01T21:19:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Removed self-hosted runner selection from the public PR workflow and constrained the topology regression guard to reviewed GitHub-hosted labels. The guard is explicitly not treated as protection against untrusted fork edits.
- Rechecked the live repository inventory at `2026-10-01T21:09:22Z`: owner type `User`, registered repository runner count `0`; runner-group enumeration does not apply to this user-owned repository.
- Recorded current attempt 1 and failed-only attempt 2 for SHA `f978fa8268328e0c2106f1aa0b45315832ce440f`. Linux recovery failed twice; ordinary Mac failed the zero-network Play-flow assertion; historical server and Docker jobs passed. Sanitized Mac evidence retains entitled status `blocked/not-configured`, `gate_passed: false`.
- Kept PORT-04, QUAL-02, entitlement, continuation qualification, and Phase 06 open. PR #6 remains draft and unmerged pending exact-head green CI.

## Task Commits

1. **Task 1: Remove public PR self-hosted runner path** - `f978fa8` (`fix(ci): remove public PR self-hosted runner path`)
2. **Task 2: Refresh hosted evidence and verification** - `dcdd3fe` (`docs(06-19): record runner security and hosted evidence`).

## Files Created/Modified

- `.github/workflows/ci.yml` - Removed self-hosted runner execution from the public workflow.
- `playstead-mac/scripts/ci/tests/four-layer-topology-test.sh` - Added trusted-code regression checks for runner labels and self-hosted invocation.
- `.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md` - Added current exact-SHA failures, runner inventory, and merge status.
- `.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md` - Corrected current gate status and linked follow-up Plan 06-21.

## Decisions Made

- Keep no runner registered for public pull-request execution. A workflow file and its tests are modifiable by fork PRs, so they cannot establish the actual runner trust boundary.
- Treat the hosted failures as blockers; do not infer a Linux cause or weaken the strict Mac assertion before Plan 06-21 adds bounded diagnostics.

## Deviations from Plan

### Plan Follow-up

**1. Hosted CI failed on the changed head**
- **Found during:** Task 2
- **Issue:** Exact-head Linux recovery failed on both initial and failed-only retry attempts; ordinary Mac also failed a strict zero-request assertion.
- **Fix:** No application behavior or assertion was changed. Documented safe sanitized status and created/identified Plan 06-21 for diagnosis.
- **Files modified:** Hosted evidence and verification documents.
- **Verification:** The Mac artifact was sanitized. A raw job log was fetched only to private temporary storage and scanned with a fixed-vocabulary classifier; it did not identify a stage. Raw log lines and the raw `failure_reason` were not displayed or added to tracked evidence. Screenshots/PNGs and fixture data were not copied.

**Total deviations:** 1 evidence-driven follow-up, with no code or assertion changes in response.
**Impact on plan:** Security objective is achieved. CI failures remain open and the owner's green-only merge condition is preserved.

## Issues Encountered

- Current workflow 36920283265 is not green on SHA `f978fa8268328e0c2106f1aa0b45315832ce440f`. Its two failed recovery lanes are handled in Plan 06-21. No app build, app launch, or XCTest was run locally.
- Entitled HID remains `blocked/not-configured`; the ordinary artifact explicitly reports `gate_passed: false`.

## User Setup Required

None for this security repair. Apple entitlement/account-holder work remains a separate prerequisite for any future entitled lane.

## Next Phase Readiness

- Plan 06-21 can diagnose both hosted failures with closed-enum failure-stage evidence, then repair only a demonstrated deterministic defect.
- Do not mark PORT-04, QUAL-02, or Phase 06 complete. Do not merge PR #6 until hosted CI is green on its exact current head.

## Self-Check: PASSED

- Task 1 security topology guard and `actionlint` passed on `f978fa8`.
- Task 2 evidence records the exact SHA, both attempts, zero-runner inventory, sanitized Mac counts, and open failures.
- The PR remains draft and unmerged; no completion claim is made for PORT-04, QUAL-02, the entitlement gate, or Phase 06.

---
*Phase: 06-recovery-proof-ci-and-e2e-pipeline*
*Completed: 2026-10-01*
