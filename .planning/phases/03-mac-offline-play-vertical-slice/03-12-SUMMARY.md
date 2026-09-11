---
phase: 03-mac-offline-play-vertical-slice
plan: 12
subsystem: release-signing
tags: [notarization, codesign, notarytool, gatekeeper, macos, xcodebuild]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "03-11-PLAN.md's resolved BIOS composition-root gap, and the pre-existing scripts/sign-and-notarize.sh graceful-degrade posture this plan hardened"
provides:
  - "scripts/verify-notarized-release.sh — one command running preflight, build, strict-mode sign+notarize, staple validation, Gatekeeper re-assertion, RelaunchTests, and launch/exit/relaunch"
  - "scripts/ci/tests/notarization-preflight-test.sh — two-direction fail-closed guard for the preflight refusal"
  - "PLAYSTEAD_REQUIRE_NOTARIZATION=1 strict mode in scripts/sign-and-notarize.sh"
  - "A real, verbatim-evidenced notarized-and-stapled Playstead.app build (03-NOTARIZATION-EVIDENCE.md)"
  - "PLAY-05 closed in REQUIREMENTS.md; 03-VERIFICATION.md's notarization gap resolved; 03-UAT.md items 14-16 flipped to pass"
affects: [release-process, ci-guards, phase-04-and-later-release-docs]

actuals:
  tokens: 41000
  tasks: 1
  commits: 1

tech-stack:
  added: []
  patterns:
    - "Strict-mode env flag (PLAYSTEAD_REQUIRE_NOTARIZATION=1) converts a graceful-degrade release script into a fail-closed one without touching its default (unset) behavior"
    - "Two-direction guard test pattern (proves refusal fires AND proves it isn't just always failing) applied to a real Apple-tooling preflight, not just internal logic"
    - "Distinct stderr tokens (NO_DEVELOPER_ID_IDENTITY, NO_NOTARY_PROFILE, NO_TEAM_ID, NOT_STAPLED, GATEKEEPER_REJECTED) for each release-path failure mode"

key-files:
  created:
    - .planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md
  modified:
    - playstead-mac/scripts/verify-notarized-release.sh
    - playstead-mac/scripts/sign-and-notarize.sh
    - playstead-mac/docs/RELEASE.md
    - playstead-mac/docs/SUPPORT-MATRIX.md
    - .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md
    - .planning/phases/03-mac-offline-play-vertical-slice/03-VERIFICATION.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Checkpoint answer (Task 2): 'enrolled — resolved 2026-09-10. The owner was in fact ALREADY enrolled in the Apple Developer Program (Individual, Team ID 6CH9Y797RU, agreement accepted 2026-09-05, renews 2027-09-06); the plan's assumption that enrolment had been skipped was out of date. What was genuinely missing was the Developer ID Application certificate and the notarytool credential profile. Both now exist: a Developer ID Application certificate (G2 Sub-CA, expires 2031-09-11) was issued against a locally generated CSR and imported into the login keychain alongside its private key, and an app-specific password was stored as the notarytool credential profile playstead-notary.'"
  - "Ran the full end-to-end script four times (not selectively) because each of the first three runs surfaced a genuine bug in the release path itself (Authority= chain missing from codesign -dv, notarytool rejecting a raw .app, and a wrong XCTest identifier matching zero tests) — each fix required a fresh, non-cherry-picked run per the plan's explicit prohibition on re-running selectively to get a cleaner log."
  - "DEVELOPMENT_TEAM=$PLAYSTEAD_TEAM_ID is passed as a command-line override to the RelaunchTests xcodebuild test invocation rather than editing the checked-in Xcode project's REPLACE_WITH_YOUR_TEAM_ID placeholder, preserving the documented per-operator local dev-signing posture (README.md) while unblocking this task."

requirements-completed: [PLAY-05]

coverage:
  - id: D1
    description: "scripts/verify-notarized-release.sh refuses to certify an unnotarized build (NO_DEVELOPER_ID_IDENTITY etc.) and the refusal is proven both firing and not-always-firing"
    requirement: "PLAY-05"
    verification:
      - kind: integration
        ref: "playstead-mac/scripts/ci/tests/notarization-preflight-test.sh"
        status: pass
    human_judgment: false
  - id: D2
    description: "A real Developer-ID-signed, Apple-notarized, stapled Playstead.app was produced and accepted by Gatekeeper naming a notarized source"
    requirement: "PLAY-05"
    verification:
      - kind: other
        ref: "scripts/verify-notarized-release.sh (real run, transcript in 03-NOTARIZATION-EVIDENCE.md)"
        status: pass
    human_judgment: false
  - id: D3
    description: "RelaunchTests (2/2) and the launch/exit/relaunch cycle both proven against the exact notarized, exported artifact"
    requirement: "PLAY-05"
    verification:
      - kind: unit
        ref: "PlaysteadTests/RelaunchTests (both test methods, run against build/Release/Playstead.app)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Every dependent document (SUPPORT-MATRIX.md, RELEASE.md, 03-UAT.md, 03-VERIFICATION.md, REQUIREMENTS.md) flipped together, citing the same evidence"
    requirement: "PLAY-05"
    verification:
      - kind: manual_procedural
        ref: "grep checks in this plan's <verify> block, all re-run and passing (see Deviations)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-11
status: complete
---

# Phase 3 Plan 12: Notarization Gap Closure Summary

**Real Apple notarization achieved (submission `8465f74d-5468-4b73-9885-fb0ea1dafcdd`, status Accepted) via a corrected `scripts/verify-notarized-release.sh`, closing PLAY-05 with verbatim, non-fabricated evidence.**

## Performance

- **Duration:** ~55 min (this continuation; Task 1 and the Task 2 checkpoint were completed and cleared by a prior executor)
- **Tasks:** 1 (Task 3 — Task 1 and Task 2 were already complete on entry to this continuation)
- **Files modified:** 8 (2 scripts, 4 docs/planning files, 1 requirements file, 1 new evidence file)

## Checkpoint Answer (Task 2 — recorded verbatim, per this plan's `<output>` spec)

> enrolled — resolved 2026-09-10. The owner was in fact ALREADY enrolled in the Apple Developer Program (Individual, Team ID 6CH9Y797RU, agreement accepted 2026-09-05, renews 2027-09-06); the plan's assumption that enrolment had been skipped was out of date. What was genuinely missing was the Developer ID Application certificate and the notarytool credential profile. Both now exist: a Developer ID Application certificate (G2 Sub-CA, expires 2031-09-11) was issued against a locally generated CSR and imported into the login keychain alongside its private key, and an app-specific password was stored as the notarytool credential profile `playstead-notary`.

Because the checkpoint answer was `enrolled` and the preflight
(`scripts/verify-notarized-release.sh --preflight-only`) exited 0, Task 3
ran to completion — this is **not** the "still deferred" legitimate-halt
path; PLAY-05 is genuinely closed.

## Accomplishments

- Ran `scripts/verify-notarized-release.sh` end to end for real against the owner's Developer ID Application identity: build, strict-mode sign, real `notarytool submit --wait` (Accepted), `stapler staple`/`validate`, a Gatekeeper re-assertion naming `source=Notarized Developer ID`, `RelaunchTests` against the exported notarized artifact, and a launch/exit/relaunch cycle of that same artifact.
- Recorded every piece of that run as verbatim tool output in `03-NOTARIZATION-EVIDENCE.md` — submission id and status, stapler output, three independent `spctl` confirmations, `codesign -dvvv` signature detail, and the `RelaunchTests` transcript.
- Flipped `SUPPORT-MATRIX.md`, `RELEASE.md`, `03-UAT.md` (items 14-16), `03-VERIFICATION.md` (second gaps entry now `status: resolved`, frontmatter `status: passed`, 5/5 truths), and `REQUIREMENTS.md` (`PLAY-05` checked, traceability row `Complete`) — all citing the same evidence file.
- Found and fixed three genuine, previously-undiscovered bugs in the release path while proving it for real (see Deviations) — this is exactly the value of running the real thing instead of a stub.

## Task Commits

1. **Task 1: One end-to-end release verification path that refuses to certify an unnotarized build** — `c469602` (feat) — completed by prior executor
2. **Task 2: Owner enrols in the Apple Developer Program and installs a Developer ID identity** — checkpoint cleared (`enrolled`), no code commit
3. **Task 3: Run the real notarized proof and flip every document that depends on it** — `8489257` (feat)

**Plan metadata:** committed alongside this SUMMARY

## Files Created/Modified

- `.planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md` - verbatim notarization proof
- `playstead-mac/scripts/verify-notarized-release.sh` - fixed RelaunchTests identifier, added DEVELOPMENT_TEAM override
- `playstead-mac/scripts/sign-and-notarize.sh` - fixed `codesign -dv` → `-dvvv`, added zip-before-submit
- `playstead-mac/docs/RELEASE.md` - rewritten for the notarized posture
- `playstead-mac/docs/SUPPORT-MATRIX.md` - signing/distribution posture section rewritten
- `.planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md` - items 14-16 flipped to pass
- `.planning/phases/03-mac-offline-play-vertical-slice/03-VERIFICATION.md` - notarization gap resolved, frontmatter status passed
- `.planning/REQUIREMENTS.md` - PLAY-05 checked and marked Complete

## Decisions Made

- Ran the full script four times end to end rather than patching and cherry-picking a clean tail, per the plan's explicit "do not re-run selectively to get a cleaner log" instruction — each of the first three runs surfaced a real bug that had to be fixed before the transcript could be trusted as evidence.
- Kept the `REPLACE_WITH_YOUR_TEAM_ID` placeholder in the checked-in Xcode project untouched (it is documented in README.md as an intentional per-operator placeholder) and instead passed `DEVELOPMENT_TEAM` as a one-off command-line override in the script, matching the pattern `build-release.sh` already uses for its archive step.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `codesign -dv` never printed the `Authority=` chain, so the strict-mode Developer ID check always failed on a real Developer-ID-signed build**
- **Found during:** Task 3, first real run of `scripts/verify-notarized-release.sh`
- **Issue:** `sign-and-notarize.sh` captured `codesign -dv --deep --strict "$APP_PATH"` into `CODESIGN_DETAILS` and grepped it for `Developer ID Application`. `codesign -dv` (a single `-v`) does not print the certificate `Authority=` chain at all — verified directly against the real Developer ID Application signature on this exact build (`codesign -dvvv` prints `Authority=Developer ID Application: ...`; `codesign -dv` does not). The strict-mode check therefore printed `FATAL: NO_DEVELOPER_ID_IDENTITY` even though the build genuinely was signed with a Developer ID Application identity.
- **Fix:** Changed the capture to `codesign -dvvv --deep --strict "$APP_PATH"`. Every other field this script reads from that variable (`flags=0x10000(runtime)`) is unaffected — `-dvvv` is a strict superset of `-dv`'s output.
- **Files modified:** `playstead-mac/scripts/sign-and-notarize.sh`
- **Verification:** Re-ran the full script; the strict-mode identity check now passes and the run proceeds to a genuine notarization submission.
- **Committed in:** `8489257`

**2. [Rule 3 - Blocking] `notarytool submit` rejects a raw `.app` bundle outright**
- **Found during:** Task 3, same first real run
- **Issue:** `sign-and-notarize.sh` called `xcrun notarytool submit "$APP_PATH" ...` directly on the exported `.app` directory. Apple's notary service returned: `Error: Playstead.app must be a zip archive (.zip), flat installer package (.pkg), or UDIF disk image (.dmg)`. This is a hard blocker — no submission could ever succeed with the script as written, in any environment, real credentials or not.
- **Fix:** Added a `ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"` step to wrap the app in a temporary zip before submission, with a `trap` to clean up the zip on exit. The notarization ticket is still stapled onto the original `$APP_PATH` directory (never the zip) — stapling operates on the actual distributable artifact.
- **Files modified:** `playstead-mac/scripts/sign-and-notarize.sh`
- **Verification:** Re-ran the full script; submission succeeded (id `0ff39f6a-...` on the debugging run, `8465f74d-...` on the final evidence run), both reaching `status: Accepted`.
- **Committed in:** `8489257`

**3. [Rule 1 - Bug] `-only-testing:PlaysteadTests/AdapterTests/RelaunchTests` matched zero tests (fail-open shape)**
- **Found during:** Task 3, second real run (after fix #1 and #2 landed)
- **Issue:** Both `verify-notarized-release.sh` (Task 1's own deliverable) and this plan's own `<verify>`/`<verification>` blocks used `-only-testing:PlaysteadTests/AdapterTests/RelaunchTests`. `AdapterTests` is the name of the Xcode source-group folder containing `RelaunchTests.swift` — it is not part of the XCTest `-only-testing` identifier, which is `TestTarget/TestClass[/testMethod]`. The filter silently matched zero tests, and `xcodebuild test` reported `Executed 0 tests, with 0 failures` as `** TEST SUCCEEDED **` — exactly the "0 assertions ran but exit 0" fail-open pattern this codebase has been bitten by before (`fail-open-test-guard-detector.py` exists specifically to catch this class of bug elsewhere in the repo).
- **Fix:** Corrected the identifier to `PlaysteadTests/RelaunchTests` in `verify-notarized-release.sh`. Confirmed the file `PlaysteadTests/AdapterTests/RelaunchTests.swift` declares `final class RelaunchTests: XCTestCase` with exactly two `func test...` methods, and both ran and passed after the fix (`Executed 2 tests, with 0 failures`) — full coverage, not a partial match.
- **Files modified:** `playstead-mac/scripts/verify-notarized-release.sh`
- **Note:** This plan's own `<verify>`/`<verification>` blocks in `03-12-PLAN.md` still literally read the incorrect identifier and, if run verbatim, will also match zero tests. PLAN.md was not edited (plans are execution instructions, not something the executor rewrites); this SUMMARY documents the correct identifier for anyone re-running that exact verify line by hand.
- **Verification:** `xcodebuild test -scheme Playstead -destination 'platform=macOS' DEVELOPMENT_TEAM=6CH9Y797RU -only-testing:PlaysteadTests/RelaunchTests` → `Executed 2 tests, with 0 failures (0 unexpected)`, `** TEST SUCCEEDED **`.
- **Committed in:** `8489257`

**4. [Rule 3 - Blocking] Local dev-signing team ID placeholder blocked `RelaunchTests` from building**
- **Found during:** Task 3, same run
- **Issue:** `Playstead.xcodeproj`'s `DEVELOPMENT_TEAM` build setting is the literal placeholder `REPLACE_WITH_YOUR_TEAM_ID` (intentionally generic per `README.md` — each operator substitutes their own local dev-signing team). Building the test target with Automatic signing failed: `No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "REPLACE_WITH_YOUR_TEAM_ID" with a private key was found.` This blocked `RelaunchTests` from running at all, independent of notarization.
- **Fix:** Passed `DEVELOPMENT_TEAM="$PLAYSTEAD_TEAM_ID"` (the same Team ID already required by preflight, `6CH9Y797RU`) as a command-line override to the `xcodebuild test` invocation in `verify-notarized-release.sh` — a one-off override for this single invocation, not a change to the checked-in project file. Confirmed via a quick `xcodebuild build` probe that this team ID (which now has an Xcode-auto-provisioned "Mac Development" certificate, since the Apple Developer Program enrollment landed) resolves automatic signing successfully, unlike the machine's other three "Apple Development" identities under different teams.
- **Files modified:** `playstead-mac/scripts/verify-notarized-release.sh`
- **Verification:** Build and test succeeded with the override; the checked-in `REPLACE_WITH_YOUR_TEAM_ID` placeholder is untouched.
- **Committed in:** `8489257`

**5. [Self-inflicted, no code fix needed] Stale DerivedData from concurrent debugging probes caused one transient archive failure**
- **Found during:** Task 3, between fixes #1/#2 and fix #3
- **Issue:** After fixing #1 and #2, one full-script run failed with `Command SwiftCompile failed with a nonzero exit code` on both x86_64 and arm64 slices, with no diagnostic body printed. This was traced to DerivedData corruption from earlier ad hoc `xcodebuild build` probes (run concurrently against the same DerivedData path while testing which local team ID had a valid signing identity).
- **Fix:** `rm -rf ~/Library/Developer/Xcode/DerivedData/Playstead-*` and rebuilt from clean. Not a defect in any committed file — no code change.
- **Files modified:** none
- **Committed in:** n/a (no code change; noted for the record since it explains why a full end-to-end run was repeated a fourth time)

---

**Total deviations:** 4 auto-fixed (2 Rule 1 bugs in `sign-and-notarize.sh`, 1 Rule 1 bug in the `-only-testing` identifier, 1 Rule 3 blocking local-signing fix) plus 1 self-inflicted transient build issue with no code fix.
**Impact on plan:** All four code fixes were necessary for the release path to work at all against a real Developer ID identity — this plan's entire purpose was to prove the path for real, and each fix was discovered precisely because a stub or mock would have hidden it. No scope creep: every fix is inside the two files (`sign-and-notarize.sh`, `verify-notarized-release.sh`) this plan's frontmatter already declared as `files_modified`.

## Issues Encountered

None beyond the deviations above — all were found, fixed, and re-verified within this task.

## User Setup Required

None further. The `apple-developer-program` `user_setup` block from this plan's frontmatter is now satisfied — the owner already completed enrollment, certificate installation, and credential profile creation before this continuation began (see the Task 2 checkpoint answer above).

## Next Phase Readiness

- PLAY-05 is genuinely closed with verbatim evidence — no more deferred notarization claims anywhere in the tree.
- `03-VERIFICATION.md` now reads `status: passed`, 5/5 roadmap truths, both gaps (BIOS wiring and notarization) resolved.
- Remaining open items in `03-UAT.md` (5 blocked, 2 partial) and `03-VERIFICATION.md`'s `human_verification` list (physical controller hardware, a live interactive emulator session, VoiceOver walkthrough, real BIOS-byte acceptance) are all genuinely human-only or hardware-only — none is a code gap, and none is in this plan's scope fence (Gap B / PLAY-05 only).
- `scripts/verify-notarized-release.sh` is now the durable, reusable one-command release proof for every future Mac release of this app, not a one-off script for this plan.

## Self-Check: PASSED

- `[ -f /Users/jon/projects/playstead/.planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md ]` → FOUND
- `[ -x /Users/jon/projects/playstead/playstead-mac/scripts/verify-notarized-release.sh ]` → FOUND
- `git log --oneline --all | grep 8489257` → FOUND
- `git log --oneline --all | grep c469602` → FOUND
- `grep -c 'PLAY-05.*Complete' .planning/REQUIREMENTS.md` → 1 (checked)
- `cd playstead-mac && scripts/ci/tests/notarization-preflight-test.sh` → exit 0, 4 assertions, `PASS: preflight refuses to certify an unnotarized build`
- `cd playstead-mac && scripts/verify-notarized-release.sh --preflight-only` → exit 0
- `codesign -dvvv --deep --strict build/Release/Playstead.app | grep -q 'Developer ID Application'` → exit 0
- `xcodebuild test -scheme Playstead -destination 'platform=macOS' DEVELOPMENT_TEAM=6CH9Y797RU -only-testing:PlaysteadTests/RelaunchTests` → `** TEST SUCCEEDED **`, 2/2 tests
- Full suite (`xcodebuild test -scheme Playstead -destination 'platform=macOS'`) → 629 tests, 0 failures, `** TEST SUCCEEDED **`

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-09-11*
