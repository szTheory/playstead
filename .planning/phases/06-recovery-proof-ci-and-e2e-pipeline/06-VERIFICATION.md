---
phase: 06-recovery-proof-ci-and-e2e-pipeline
status: gaps_found
verified: 2026-10-01T21:09:22Z
requirements: [PORT-04, QUAL-02]
execution: inline-codex-skill-fallback
gaps:
  - truth: Hosted recovery lanes have current passing integration evidence.
    status: fail
    reason: Historical workflow 36910091796 passed on SHA 631edf9665ace49c91a02bdebcbd49dbc0f0e6ba, but current SHA f978fa8268328e0c2106f1aa0b45315832ce440f failed Linux recovery and ordinary Mac in workflow 36920283265; its failed-only Linux retry also failed.
    artifacts: [.github/workflows/ci.yml, playstead-mac/TestPlans/LiveServer.xctestplan, 06-HOSTED-EVIDENCE.md]
    missing: []
  - truth: The cross-phase regression gate is green.
    status: fail
    reason: Current exact-head hosted recovery CI is failing on both Linux and ordinary Mac. The aggregate gate also remains open because entitlement and deterministic continuation are unresolved and the broader requirement review is incomplete.
    missing: [Passing exact-head Linux recovery, Passing exact-head ordinary Mac, Entitled virtual-HID pass, Qualified continuation evidence, Full regression-gate review]
  - truth: The private continuation adapter proves a repeatable visible resumed state.
    status: blocked
    reason: Actual same-host qualification refused; deterministic replay and repeated oracle agreement are not established.
    artifacts: [playstead-mac/scripts/ci/continuation_protocol.py]
    missing: [Empirical private adapter replay and oracle qualification]
---

# Phase 06 Verification

**Verdict: gaps found.** Historical Linux recovery and ordinary Mac jobs passed on
`631edf9665ace49c91a02bdebcbd49dbc0f0e6ba` in workflow 36910091796. Current
security-repair head `f978fa8268328e0c2106f1aa0b45315832ce440f` failed both lanes
in workflow 36920283265, and the failed-only Linux retry also failed. PR #6 stays
draft and unmerged pending green hosted CI on its exact head. The Phase 06
aggregate and PORT-04/QUAL-02 remain open; entitlement is blocked/not-configured,
deterministic continuation remains unqualified, and full requirement review is
incomplete.

## Goal and requirement mapping

| Boundary | Implementation / observed evidence | Result |
|---|---|---|
| SC1: independent Linux restore lane | Dedicated bounded CI job; historical hosted receipt passed all six stages (`chain`, `preflight`, `database`, `cas`, `manifest`, `api`) and sanitizer upload | Historical pass on SHA `631edf9`; current SHA `f978fa8` failed twice; open |
| SC2: native pairing, convergence, cache/preflight and save transport | Hosted ordinary Mac reachability, Unit, Rendering, UI and LiveServer selections passed; actual same-host clean-client recovery also passed | Hosted ordinary lane passed; entitlement remains a separate open lane |
| SC3: fixture-specific continuation spike | Strict protocol, independently checked network denial, actual local qualification refusal, lifecycle/oracle negative corpus | Gate verified; actual continuation capability blocked |
| PORT-04 | Existing legal fixture, production restored target, exact download/save materialization, graceful emulator exit and app relaunch exercised; historical hosted restore receipt exists | Partial; no in-game resumed-state oracle pass, current hosted Linux failure, and full requirement closure remains open |
| QUAL-02 | Sanitizer, CI wiring, focused suites, historical hosted pass, and current hosted failure evidence present | Partial; current Mac/Linux CI failures, entitlement, continuation, and remaining release-quality gate review are open |

Requirements originally belong to Phase 05 and are extended by these plans.
Their unchecked canonical REQUIREMENTS.md status is retained. Earlier 06-01/02
summary completion lists do not establish whole-requirement closure.

## Fresh evidence from this execution

- Current repository Actions runner inventory checked at `2026-10-01T21:09:22Z`: owner type `User`, repository runner count `0`; runner-group enumeration is not applicable to this personal-user-owned repository. No runner, secrets, branch settings, or dependencies were changed. The topology script is a trusted-code regression check, not a security boundary against fork PR workflow edits.
- Current pushed SHA `f978fa8268328e0c2106f1aa0b45315832ce440f`, workflow [36920283265](https://github.com/szTheory/playstead/actions/runs/36920283265): attempt 1 server precommit job `110564318056` passed, Docker job `110564318702` passed, Linux recovery job `110564318328` failed, ordinary Mac job `110567365139` failed. Failed-only retry attempt 2 failed Linux recovery job `110579269830`; the original Mac failure remains failed and was not rerun. No current exact-head recovery pass is claimed.
- The sanitized Mac artifact reports Unit 759/759, Rendering 52/52, UI 121/122 (one failed), and LiveServer 6/6. The one failing test is `ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()` at `XCTAssertNil` line 53. Entitled status is `blocked/not-configured`, `gate_passed: false`. A raw job log was fetched only to private temporary storage and scanned with a fixed-vocabulary classifier; it did not identify a trusted stage. No raw log lines, raw `failure_reason`, screenshots/PNGs, or fixture data were displayed or copied into tracked evidence. Linux's underlying restore stage remains unknown. Plan 06-21 is the follow-up for bounded diagnosis and an evidence-based repair.
- Phase 06, PORT-04, and QUAL-02 remain open. PR #6 stays draft and unmerged until hosted checks pass on the exact head.

- Plan 06-09 completed against reviewed branch `phase06/hosted-evidence-20261001`, draft PR #6, exact SHA `631edf9665ace49c91a02bdebcbd49dbc0f0e6ba`. Hosted workflow [36910091796](https://github.com/szTheory/playstead/actions/runs/36910091796) completed successfully: Linux recovery `110530300591`, server `mix precommit` `110530300895`, Docker cold-start `110530300975`, and ordinary Mac `110532872266` passed. The entitlement job `110530302434` was skipped/not configured.
- Sanitized Linux evidence reports all six recovery stages passed. The 11-file ordinary Mac artifact reports reachability passed; Unit 759, Rendering 52, UI 122, and LiveServer 6, all with zero failures, accessibility audit issues, or layout diagnostics. The entitled artifact explicitly has `gate_passed: false` and `status: blocked/not-configured`. Details and artifact names are in `06-HOSTED-EVIDENCE.md`.

- Plan 06-12's refreshed reliability: APFS **20/20** (280 seconds), Wallaby
  **20/20** (100 seconds), and live save classification **10/10** (538 seconds)
  on HEAD `1de3e954166eaf0a52fe0e4a950b46756139884d`, fingerprint
  `feef0ddbf59b7f66bf56884a607a8f997c94919a58d9f1f77725b4b65738f7c8`.
  The save result retained the distinct transient 503 and true duplicate 409
  classes with 20 unique opaque correlation UUIDs. Earlier failures remain
  classified in `06-RELIABILITY-EVIDENCE.md`.

- Latest ordinary no-HID verification on the same HEAD and fingerprint passed:
  reachability; Unit **759/759** (51 required); Rendering **52/52** (8 required);
  UI **122/122** (60 required); LiveServer **6/6** (all required). The focused
  list-row and Collections screenshots are included in Rendering. The separate
  virtual-gamepad entitlement lane did not run and remains
  `blocked/not-configured`.

- Actual final `.local/run-recovery.sh`: exit 0, `stage=complete outcome=passed`.
  The dedicated serial Recovery plan ran the real clean Mac against the retained
  restored target. It covered clean launch, private-CA pairing, exact-request
  automatic approval, cursor convergence, production adapter install/download,
  cache readiness, exact persistent-save materialization, normal emulator quit,
  app exit and relaunch. The final public receipt passed the sanitizer.
- Native running-app inventory after cleanup: **zero mGBA instances**.
- Actual `.local/run-continuation.py` using that fresh receipt: exit 77,
  `stage=qualification outcome=blocked-capability`. Reaching qualification
  requires the real parent network-denial probe to pass. No fixture-bearing
  replay action was reached.
- `run-mac-verification.sh --self-test-contracts`: exit 0, **all static contract
  guards passed**, including 47 validator tests, test-plan registration, AX-value
  semantics, fail-open guard, recovery helpers and continuation corpus.
- `sanitizer-test.sh`: **65 positive/negative checks passed**.
- `continuation-spike-test.sh`: passed, including the real sanitizer on success
  and oracle failure, refusal on sanitizer failure, and coordinator propagation.
- `recovery-e2e-test.sh`: passed, including **11 fixture validation tests**.
- Focused server restore and blob-controller suite with bounded scheduler/case
  concurrency: **47 tests, zero failures**.
- Focused Mac `SaveHistorySessionBuilderTests`, `StorageShellWiringTests` and
  `ReadinessEngineTests`: rebuilt and passed after stale source assertions were
  corrected. The full recovery XCTest and shared harness also type-check with
  warnings as errors, and the actual signed build/UI run passed.
- Linux wrapper fake-command contracts, scoped shell syntax and whitespace
  checks passed. Fake commands do not substitute for the Linux integration job.

## Historical regression failures — superseded for the ordinary local lane

The configured full Mac Unit regression first exposed an obsolete two-call-site
save-history assertion. A rebuilt run then exposed an obsolete storage-navigation
assertion. Both were updated to check the current production wiring, with
nonempty/exact-shape checks, and their focused rerun passed.

The full rebuilt Mac run still failed 14 visual snapshot cases across conflict
comparison, library, only-copy and save-history surfaces. The working tree also
contains extensive pre-existing UI/design changes. Their intended baselines need
review; no blind snapshot replacement or unrelated UI rollback was performed.

The first full server run encountered PostgreSQL connection exhaustion and
reported 349 failures. A bounded rerun (`ERL_FLAGS='+S 4:4'`, `--max-cases 4`)
removed connection exhaustion but still reported **185 features, 13 properties,
1154 tests, 189 failures**. Browser cases failed with `invalid session id`.
Additional failures were old setup/library color-token assertions and the
backup correlation test's `database_snapshot_unavailable` result. The latter
needs investigation around the SQL sandbox/snapshot boundary; a cause is not
asserted and its backup expectation was not weakened.

Plan 06-18 later passed the complete ordinary no-HID local wrapper on its own
recorded fingerprint, resolving the local Mac snapshot/UI failures. Plan 06-12
later passed its selected APFS, Wallaby, and save reliability gates on a
separate fingerprint. These historical full-server failures are retained as
diagnosis and are not recounted as current failures or as current full-gate
passes. Local raw logs remain in ignored private storage; only categories and
counts are recorded here.

## Review and privacy

See `06-REVIEW.md`. Four defects were corrected and checked: hosted/private test
selection, aborted emulator cleanup, XCTest guard/AX conventions and rejection
of an oracle failure receipt. An explicit foreground-state check precedes the
toolbar interaction after one rerun reported a non-hittable List control.

Fixture/account/signing state stays ignored and local. Exact target guards bind
automatic approval to this disposable clone and fresh request. Original ROM/save
sources and the canonical deployment were not mutated by the recovery journey.
No raw XCTest results, credentials, CA or fixture hashes enter public evidence.
The shared dirty checkout remains unstaged and uncommitted; the user-authorized
isolated branch and draft PR #6 contain the reviewable source change set.

## Next work

1. Plan 06-09 is complete; do not rerun it unless its hosted jobs or exact-SHA
   evidence become stale.
2. Keep the entitled virtual-HID lane separate until a matching profile and
   runner configuration produce a real pass.
3. Resolve the adapter's supported script-loading path, then qualify the
   existing private fixture's deterministic replay and repeated visible
   resumed-state oracle before claiming automated in-game continuation.
4. Revisit the full regression gate and remaining PORT-04/QUAL-02 evidence only
   after the entitlement and continuation prerequisites have changed.

Reuse the established fixture registry, local launchers and disposable-owner
authorization. Do not restart Team ID discovery, request a new ROM or require
personal login. The Apple Virtual HID wait remains separate and must not be
polled as part of this work.
