# Phase 06 Hosted Evidence

## Review target

- Draft PR: https://github.com/szTheory/playstead/pull/6
- Branch: `phase06/hosted-evidence-20261001`
- Base: `feat/dev-standup-and-uat7-closure`
- Historical passing repair commit: `631edf9665ace49c91a02bdebcbd49dbc0f0e6ba` (retained recovery cleanup return handling).
- Current pushed security repair: `f978fa8268328e0c2106f1aa0b45315832ce440f`; it removes the public PR self-hosted runner path. This isolated checkout carries the security source change, but the current CI attempts below are failing and PR #6 remains draft and unmerged.
- The source commit excludes `.planning/`, local CA/signing artifacts, local fixture/account notes, and raw test evidence. The evidence ledger is copied into this isolated review branch for the open draft PR.

The ordinary hosted workflow is the source of truth for the Mac app layers. The local no-HID runner refused to launch the app because the automated GSD guard requires a human-set `PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH` opt-in; that setting was not injected by automation.

## Current runner inventory and exact-head CI status

Runner inventory was checked at `2026-10-01T21:09:22Z` immediately before this update: repository owner type `User`; repository Actions runner count `0`. Organization/enterprise runner-group inventory is not applicable to this personal-user-owned repository. No self-hosted runner or repository/organization settings were changed. The in-repository topology check is trusted-code regression coverage only; it is not a security boundary against a public fork changing workflow and guard together.

The historical passing workflow below is not current-head proof. On current security-repair SHA `f978fa8268328e0c2106f1aa0b45315832ce440f`, workflow [36920283265](https://github.com/szTheory/playstead/actions/runs/36920283265) failed in both independent recovery lanes. Attempt 1: server `mix precommit` job `110564318056` passed; Docker cold-start job `110564318702` passed; Linux recovery job `110564318328` failed; ordinary Mac job `110567365139` failed. The failed-only retry (attempt 2) still failed Linux recovery in job `110579269830`; the Mac failure from attempt 1 remains failed and was not rerun. The successful server and Docker results belong to attempt 1 only.

The Mac failure evidence was reviewed only through the sanitized artifact: Unit 759/759, Rendering 52/52, UI 121/122 (one failed), and LiveServer 6/6. The one failing test is `ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()` at `XCTAssertNil` line 53. The same sanitized artifact reports entitled status `blocked/not-configured` with `gate_passed: false`. During diagnosis, the raw job log was fetched only into private temporary storage and scanned with a fixed-vocabulary classifier; it did not identify a trusted failure stage. No raw log lines, raw `failure_reason`, screenshot/PNG, or fixture data were displayed or copied into tracked evidence. The exact Linux restore stage remains unresolved. These outcomes remain non-passing. Follow-up Plan 06-21 owns bounded stage diagnosis and any narrowly evidenced repair. PR #6 stays draft and unmerged until hosted CI is green on the exact current head.

## Hosted runs

| Run | Reviewed SHA | Run ID / URL | Linux recovery | Mac ordinary | Docker | Entitled HID |
|---|---|---|---|---|---|---|
| Initial review | `911cfd8f1cfebde67dfd8c9641ff1b9f01dd326f` | [36896743418](https://github.com/szTheory/playstead/actions/runs/36896743418) | Failed before fixture: runner lacked `rg` | Failed static guards for the same missing tool | Passed | Skipped; runner not configured |
| Portability repair | `e5f1a0a081c442f3b9c3c61e3e8e1ef9f292eb18` | [36898163971](https://github.com/szTheory/playstead/actions/runs/36898163971) | Failed the stale retained-target assertion; corrected in `d5218c2` | Static guards passed; UI layer failed because the Cards/List switch was not hittable in the hosted window | Passed | Skipped; runner not configured |
| Picker and PostgreSQL client repair | `e19fedc7f65dcb2fba949d0c05f4c41cf6321707` | [36904947936](https://github.com/szTheory/playstead/actions/runs/36904947936) | Failed during isolated restore cleanup: `File.rm_rf/1` returns `{:ok, paths}` but cleanup matched only `:ok`; fixed in `631edf9` | Passed: reachability; Unit 759/759; Rendering 52/52; UI 122/122; LiveServer 6/6. The previously failing `SaveFrontDoorJourneyTests/testReadinessSaveRowReportsRealStateForAGameWithSavedProgress()` passed after moving the view picker into the content row | Passed | Skipped; sanitized evidence records `blocked/not-configured` |
| Recovery cleanup return fix | `631edf9665ace49c91a02bdebcbd49dbc0f0e6ba` | [36910091796](https://github.com/szTheory/playstead/actions/runs/36910091796) | Passed (job `110530300591`; sanitized `linux-recovery-evidence/recovery-e2e.json`, all six stages) | Passed (job `110532872266`; Unit 759, Rendering 52, UI 122, LiveServer 6; zero failures) | Passed (job `110530300975`) | Skipped; runner not configured |
| Public self-hosted runner removal, attempt 1 | `f978fa8268328e0c2106f1aa0b45315832ce440f` | [36920283265](https://github.com/szTheory/playstead/actions/runs/36920283265) | Failed (`110564318328`; internal stage unresolved) | Failed (`110567365139`; zero-network play-flow assertion, sanitized artifact counts below) | Passed (`110564318702`) | No entitled self-hosted job; ordinary artifact says blocked/not-configured, gate_passed false |
| Failed-only retry, attempt 2 | `f978fa8268328e0c2106f1aa0b45315832ce440f` | [36920283265](https://github.com/szTheory/playstead/actions/runs/36920283265) | Failed (`110579269830`; stage unresolved) | Original attempt-1 Mac failure remains; not rerun | Attempt-1 success retained | No entitled self-hosted job; no pass claimed |

Server `mix precommit` also passed as job `110530300895` on the same SHA.

The first run also found three Elixir files that failed `mix format --check-formatted`; those were formatted. The static Mac contract suite passed on the portability repair, including a local run with `rg` deliberately unavailable. The retained-target contract now passes locally after being aligned with the implementation's `target` path and multiline cleanup argument list.

The Linux PostgreSQL test job initially failed because Ubuntu's default `pg_dump` 16 cannot dump the PostgreSQL 17 service. The workflow now installs the official PostgreSQL 17 client from PGDG and verifies that binary before `mix precommit`; the server job and Docker cold-start passed on run `36904947936`.

The hosted Mac evidence for run `36904947936` is the sanitized artifact `mac-ordinary-evidence`; its manifest lists the four ordinary layers and reports 0 test failures, 0 accessibility audit issues, and 0 layout diagnostics. The virtual-gamepad evidence is separate and says `blocked/not-configured`; the ordinary Mac pass does not close the full regression gate.

## Certified Plan 06-09 evidence

- Final reviewed source: `631edf9665ace49c91a02bdebcbd49dbc0f0e6ba`, branch `phase06/hosted-evidence-20261001`, draft PR [#6](https://github.com/szTheory/playstead/pull/6).
- Workflow [36910091796](https://github.com/szTheory/playstead/actions/runs/36910091796) completed successfully on that exact SHA. Linux recovery job `110530300591`, server `mix precommit` job `110530300895`, Docker cold-start job `110530300975`, and ordinary Mac job `110532872266` all concluded `success`. The distinct entitled virtual-gamepad job `110530302434` was `skipped` because its runner/profile is not configured.
- Linux sanitized receipt: `linux-recovery-evidence/recovery-e2e.json`; outcome `passed`, stages `chain`, `preflight`, `database`, `cas`, `manifest`, and `api`.
- Mac sanitized artifact: `mac-ordinary-evidence` (11 files, 86,024 bytes). Reachability passed; Unit 759/759, Rendering 52/52, UI 122/122, and LiveServer 6/6 passed. The artifact reports zero failures, accessibility audit issues, and layout diagnostics. Environment: macOS 26.6.2 ARM64, Xcode 26.6 (17F113).
- Entitled artifact `entitled-gamepad.json` truthfully records `status: blocked/not-configured` and `gate_passed: false`. This is not an entitled-lane pass and does not close the aggregate regression gate.
- The exact-SHA/run/job/artifact checks for Plan 06-09 passed against GitHub's completed run record and the downloaded sanitized receipts. The broader `--verify-hosted-run complete` verifier is not claimed: it currently expects a stale ordinary-job name and its full-gate scope requires entitlement evidence, which this plan explicitly keeps separate.

The local synthetic restore fixture identified the cleanup return mismatch while using a temporary Buildx config. Later local fixture attempts hit intermittent source-database startup failures under the workstation Docker environment, so those attempts are diagnostic only and are not counted as recovery evidence. The required current Linux result remains the hosted run above.

## Remaining phase gates

- Plan 06-09's hosted Linux and ordinary Mac deliverables are complete on the exact reviewed SHA above.
- Keep the virtual-gamepad lane separately `blocked/not-configured` until an entitled runner/profile produces its own real result.
- Resolve the current Linux restore and Mac zero-network failures through Plan 06-21; do not treat the failed-only retry as a passing first attempt.
- Keep PR #6 draft and unmerged until all hosted CI checks pass on the exact head.
- `PORT-04`, `QUAL-02`, and the full regression gate remain open for their broader restore/export, entitled-device, continuation, and release-quality evidence. Do not treat this hosted ordinary-lane pass as phase completion.
