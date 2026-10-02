---
phase: 06-recovery-proof-ci-and-e2e-pipeline
status: gaps_found
verified: 2026-10-02
requirements: [PORT-04, QUAL-02]
execution: inline-codex-skill-fallback
gaps:
  - truth: Hosted recovery lanes have current passing integration evidence.
    status: pass
    reason: Merged PR #7 commit ddd04ee06b93035711f3bdaeb8c40f86d99cdfed has a green latest attempt in workflow 37021805359, including Linux recovery, server precommit, and ordinary Mac.
    artifacts: [.github/workflows/ci.yml, playstead-mac/TestPlans/LiveServer.xctestplan, 06-HOSTED-EVIDENCE.md]
    missing: [Passing exact-current-PR-head CI after the evidence and summary commit]
  - truth: The cross-phase regression gate is green.
    status: fail
    reason: PR #7's hosted run is green, but the aggregate gate remains open because virtual-HID entitlement and broader requirement review remain incomplete. The private fixture result is narrow evidence, not a compatibility claim.
    missing: [Entitled virtual-HID pass, Full aggregate and requirement review]
  - truth: A narrow private mGBA continuation shows a visible resumed state.
    status: pass
    reason: The mGBA 0.10.5 plus private AerevenAdvance continuation passed twice with a visible state oracle; fixture rights remain unestablished for public distribution and the result does not establish broader compatibility.
    artifacts: [playstead-mac/scripts/ci/continuation_protocol.py]
    missing: [Empirical private adapter replay and oracle qualification]
---

# Phase 06 Verification

**Verdict: gaps found; Phase 06 remains open.** Latest merged evidence is PR #7
merge commit `ddd04ee06b93035711f3bdaeb8c40f86d99cdfed`, workflow
[37021805359](https://github.com/szTheory/playstead/actions/runs/37021805359),
whose latest attempt passed Linux recovery, server precommit, and ordinary Mac.
Mac results were Unit 759/759, Rendering 52/52, UI 122/122, and LiveServer
6/6. The Docker job succeeded, while its Docker build and smoke steps were
skipped by the path filter; those steps are not claimed as executed passes.
Two narrow mGBA 0.10.5 plus private AerevenAdvance continuation runs showed the
visible state oracle. The fixture remains private and the result is narrow.
Virtual-HID remains `blocked/not-configured`; aggregate/requirement review is
incomplete, so no phase or milestone completion is claimed.

Historical Linux recovery and ordinary Mac jobs passed on
`631edf9665ace49c91a02bdebcbd49dbc0f0e6ba` in workflow 36910091796. The Plan 06-24 source-code head
`a662c75227b9c54a3ba66af62591dfaa407912ed`, workflow 36971165164, passed Docker cold-start, server `mix precommit`, and ordinary Mac but failed Linux recovery at the sanitized operation stage `source-fixture-database-connect`; the cause was not established. Plan 06-25 source-code head
`a9c5adfe72a56c88ea567ad470757fdc44e006ef`, workflow 36983412255, passed all four required jobs, including a validated sanitized Linux success receipt. At that historical point an exact-current-PR-head run was pending. PR #7 is now merged and the later run above supersedes that pending status. The Phase 06 aggregate and PORT-04/QUAL-02 remain open; entitlement is blocked/not-configured, and full requirement review is incomplete.

## Goal and requirement mapping

| Boundary | Implementation / observed evidence | Result |
|---|---|---|
| SC1: independent Linux restore lane | Dedicated bounded CI job; PR #7 merged-head workflow passed Linux recovery; prior sanitized receipts passed all six stages (`chain`, `preflight`, `database`, `cas`, `manifest`, `api`) | Hosted recovery evidence current; broader phase gate open |
| SC2: native pairing, convergence, cache/preflight and save transport | PR #7 latest attempt passed ordinary Mac: Unit 759/759, Rendering 52/52, UI 122/122, LiveServer 6/6 | Ordinary Mac lane passes; virtual-HID entitlement remains separately open |
| SC3: fixture-specific continuation spike | Strict protocol, independently checked network denial, actual local qualification refusal, lifecycle/oracle negative corpus | Gate verified; actual continuation capability blocked |
| PORT-04 | Hosted Linux recovery passed on merged PR #7; narrow private mGBA 0.10.5/AerevenAdvance continuation showed visible state twice | Partial; fixture remains private, virtual-HID is blocked/not-configured, and full requirement closure remains open |
| QUAL-02 | Sanitizer, CI wiring, focused suites, and merged PR #7 hosted evidence present | Partial; aggregate/requirement review and entitled virtual-HID evidence remain open |

Requirements originally belong to Phase 05 and are extended by these plans.
Their unchecked canonical REQUIREMENTS.md status is retained. Earlier 06-01/02
summary completion lists do not establish whole-requirement closure.

## Fresh evidence from this execution

- Plan 06-22 workflow [36952647897](https://github.com/szTheory/playstead/actions/runs/36952647897) completed on `56b64e88fb55b3224206f3ef213f45eed5711586`: Docker job `110668721913`, server precommit job `110668722036`, and ordinary Mac job `110670579867` passed. Linux job `110668722059` failed only at `Run isolated restore fixture`; sanitization and upload succeeded. The only inspected artifact was the sanitized four-field `recovery-failure.json` with stage `source-fixture-create`. That marker does not distinguish filesystem source-fixture creation from PostgreSQL source-database seeding or identify a root cause. Plan 06-23 splits these operation markers.

- Plan 06-23 workflow [36961936830](https://github.com/szTheory/playstead/actions/runs/36961936830) completed on exact PR head `dbe3f3802ba1a88b877c6144492835b9a87ea338`. Docker job `110697303449`, server precommit job `110697303490`, and ordinary Mac job `110698990104` passed. Linux job `110697303338` failed only at `Run isolated restore fixture`; sanitizer and upload passed. The sole inspected artifact was `recovery-failure.json`, validated as exactly one regular file with no duplicate keys and exactly the unchanged four fields. Sanitized stage `source-fixture-database-seed` identifies only the source PostgreSQL fixture-seed boundary; no cause is inferred. Plan 06-24 narrows diagnostics within that operation. All full-phase and requirement gates remain open.

- Plan 06-24 workflow [36971165164](https://github.com/szTheory/playstead/actions/runs/36971165164) completed on exact code SHA `a662c75227b9c54a3ba66af62591dfaa407912ed`. Docker cold-start job `110727469629`, server precommit job `110727469826`, and ordinary Mac job `110729213046` passed. Linux isolated recovery job `110727469818` failed only at `Run isolated restore fixture`; sanitizer and upload passed. The only inspected artifact was one sanitized `recovery-failure.json` with exactly `schema`, `lane`, `outcome`, and `failure_stage`, no duplicate keys, and stage `source-fixture-database-connect`. That names the source PostgreSQL connection probe only; it establishes no cause. Plan 06-25 scopes a bounded retry of the same read-only query. The run remains red; PORT-04, QUAL-02, entitlement, continuation, and aggregate regression remain open.

- Plan 06-25 source-code-head workflow [36983412255](https://github.com/szTheory/playstead/actions/runs/36983412255) completed successfully on exact SHA `a9c5adfe72a56c88ea567ad470757fdc44e006ef`. Docker `110762899299`, server `mix precommit` `110762899658`, Linux recovery `110762899730`, and ordinary Mac `110765032780` all succeeded. The only downloaded artifact was the named sanitized `linux-recovery-evidence` receipt, validated as exactly one regular `recovery-e2e.json` with `schema_version: 1`, lane `linux_restore_fixture`, outcome `passed`, and stages `chain`, `preflight`, `database`, `cas`, `manifest`, and `api`. No cause is inferred for the prior connect-stage failure, and the hosted outcome does not establish that retries were required. This source-head run predates the evidence/summary commit; final exact-current-PR-head CI is a separate merge gate. PORT-04, QUAL-02, entitlement, continuation, and aggregate regression remain open.

- **Merged PR #7 current-head outcome:** merge commit
  `ddd04ee06b93035711f3bdaeb8c40f86d99cdfed`; workflow
  [37021805359](https://github.com/szTheory/playstead/actions/runs/37021805359),
  latest attempt green. Linux recovery, server precommit, and ordinary Mac
  passed. Ordinary Mac counts: Unit 759/759, Rendering 52/52, UI 122/122,
  LiveServer 6/6. The Docker job succeeded, but its Docker build and smoke
  steps were skipped by the path filter. Those skipped steps are not treated
  as executed passes. This is the current hosted evidence recorded from the
  owner-provided run summary in quick task `261002-hwa`.

- **Narrow continuation evidence:** mGBA 0.10.5 with private AerevenAdvance
  passed twice with a visible resumed-state oracle. This supports only that
  tested fixture/core/host path; it does not establish broad compatibility or
  public fixture rights. AerevenAdvance remains private.

- Plan 06-21 first hosted run [36931486120](https://github.com/szTheory/playstead/actions/runs/36931486120) was on SHA `3f2316d0a99ca0aff09da789dd1ea690d4bae8ab`: server `mix precommit` and Docker passed, Linux restore failed with sanitizer/upload skipped, and Mac failed at `Verify static contract guards` before app/native layers. Local static reproduction found a bare closed-schema early return; commit `cf978f4` corrected it. `fail-open-test-guard-test.sh` and `run-mac-verification.sh --self-test-contracts` passed locally after that correction; Linux source was unchanged and its synthetic tests had passed before the Mac-only fix.
- Fresh exact-head workflow [36947656348](https://github.com/szTheory/playstead/actions/runs/36947656348) on `cf978f4d3ece48197bf209b31cc451b73f84759e`: Docker job `110653291243`, server `mix precommit` job `110653291608`, and ordinary Mac job `110655090300` passed; Linux isolated recovery job `110653291551` failed at `Run isolated restore fixture`, with sanitizer and upload skipped. No Linux sanitized artifact exists, so its internal stage is not attributed and raw job output was not inspected.
- The exact-head sanitized Mac artifact `mac-ordinary-evidence` contained 11 files. Reachability passed; Unit 759/759, Rendering 52/52, UI 122/122, and LiveServer 6/6 passed with zero test failures, accessibility audit issues, or layout diagnostics. `entitled-gamepad.json` says `blocked/not-configured`; it does not count as a virtual-HID pass. The ordinary Mac lane is current-head green; the Linux and aggregate gates remain open.

- Current repository Actions runner inventory checked at `2026-10-01T21:09:22Z`: owner type `User`, repository runner count `0`; runner-group enumeration is not applicable to this personal-user-owned repository. No runner, secrets, branch settings, or dependencies were changed. The topology script is a trusted-code regression check, not a security boundary against fork PR workflow edits.
- At the time of this PR #6 review, pushed SHA `f978fa8268328e0c2106f1aa0b45315832ce440f`, workflow [36920283265](https://github.com/szTheory/playstead/actions/runs/36920283265): attempt 1 server precommit job `110564318056` passed, Docker job `110564318702` passed, Linux recovery job `110564318328` failed, ordinary Mac job `110567365139` failed. Failed-only retry attempt 2 failed Linux recovery job `110579269830`; the original Mac failure remained failed and was not rerun. This historical status is superseded by the merged PR #7 result recorded above.
- The older sanitized Mac artifact on SHA `f978fa8` reported Unit 759/759, Rendering 52/52, UI 121/122 (one failed), and LiveServer 6/6; the failed static guard was later reproduced locally and corrected on `cf978f4`. The prior raw job log was fetched only to private temporary storage and scanned with a fixed-vocabulary classifier; it did not identify a trusted stage. No raw log lines, raw `failure_reason`, screenshots/PNGs, or fixture data were displayed or copied into tracked evidence. Plan 06-22's `source-fixture-create` marker was superseded by Plan 06-23's `source-fixture-database-seed` operation marker. No root cause is asserted and raw job output was not inspected.
- At that point in the PR #6 review, Phase 06, PORT-04, and QUAL-02 remained open and PR #6 was draft. PR #7 has since merged; the current gates are summarized at the top of this verification record.

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
isolated branch and draft PR #6 contained the reviewable source change set at
the time of that review; PR #7 is now merged.

## Current gates and next GSD action (2026-10-02)

- Phase 06 remains open. Virtual-HID entitlement is `blocked/not-configured`;
  the aggregate regression and requirement review remain incomplete.
- PR #7 is merged and workflow 37021805359 is green on the latest attempt.
  Docker build and smoke steps were path-filter skipped, not executed.
- The private AerevenAdvance continuation evidence is narrow and does not
  change its private status or establish fixture distribution rights.
- `gsd init execute-phase 06` reports plans 06-20 and 06-22 through 06-25
  complete, with no incomplete or runnable plans. Run `$gsd-progress` to select
  the correct next action. Do not fabricate a runnable implementation plan.
