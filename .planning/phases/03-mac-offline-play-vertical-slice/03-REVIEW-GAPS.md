---
phase: 03-mac-offline-play-vertical-slice
reviewed: 2026-09-11T00:00:00Z
depth: standard
scope_source: gap-closure diff 9baa136..HEAD
files_reviewed: 10
files_reviewed_list:
  - playstead-mac/Playstead/Adapter/BiosReferences.swift
  - playstead-mac/Playstead/Adapter/BiosStore.swift
  - playstead-mac/Playstead/App/PlaysteadApp.swift
  - playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift
  - playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift
  - playstead-mac/scripts/verify-bios-reference.sh
  - playstead-mac/scripts/verify-notarized-release.sh
  - playstead-mac/scripts/sign-and-notarize.sh
  - playstead-mac/scripts/ci/tests/bios-pin-provenance-test.sh
  - playstead-mac/scripts/ci/tests/notarization-preflight-test.sh
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 3 Gap-Closure Code Review Report (03-11 / 03-12)

**Reviewed:** 2026-09-11
**Depth:** standard
**Files Reviewed:** 10 (plus `.planning/.../03-BIOS-PIN.json`, `03-NOTARIZATION-EVIDENCE.md`, and the two named docs read for content hygiene only)
**Status:** issues_found (no Critical findings; 3 Warnings, 2 Info)

## Summary

This review covers exactly the diff `9baa136..HEAD` outside `.planning/`: the two gap-closure plans that (03-11) wire a real, cited BIOS reference into `BiosStore`/`PlaysteadApp` and harden the drop path against interruption/concurrency, and (03-12) turn `sign-and-notarize.sh` into a fail-closed strict-mode release path and record a genuine notarization run.

I traced every claim in `03-11-PLAN.md`/`03-12-PLAN.md` and their SUMMARY files against the actual current file contents rather than trusting the summaries. The core security-relevant guarantees hold up under adversarial reading:

- **Trust anchor correctness.** `BiosReferences.production` and `03-BIOS-PIN.json` both carry the same 64-lowercase-hex digest and byte length (`16384` / `fd2547724b...36570`, independently confirmed 64 characters by direct count), the parity test (`testProductionLiteralsMatchThePinFile`) genuinely compares both fields and would fail if either side were edited alone, and `BiosStore.validateAndAccept` checks length *before* computing a digest, so the length gate cannot be bypassed by a byte-length mismatch masquerading as a digest match.
- **Empty-vs-real-reference discriminator.** The two distinct rejection strings (`"no known reference for this system yet"` vs `"this file's contents don't match a known reference"`) are real, distinct, and both covered by tests that assert the exact string, not just "something was thrown."
- **Fail-closed shell.** All five reviewed scripts use `set -euo pipefail`, capture exit codes into variables before comparing them (never `if cmd; then` on a possibly-missing binary), and the two provenance/preflight guards both include genuine negative controls that are shown to fail — this is the exact anti-pattern class this project has been bitten by before, and it is closed correctly here.
- **Prohibited-content hygiene.** No URL, download hint, acquisition path, credential, or app-specific password appears anywhere in the reviewed scripts, the pin file, or `03-NOTARIZATION-EVIDENCE.md`. The provenance URLs in `BiosReferences.swift`/`03-BIOS-PIN.json` are citations (as the plan explicitly permits), not acquisition hints, and are followed immediately by an explicit no-acquisition statement in both places.
- **Move-race handling.** The move-race fix in `BiosStore.validateAndAccept` (catch the move failure, re-check `fileExists`, treat "someone else already won" as success) is correct for the two-concurrent-identical-drops case and is proven by a real `DispatchQueue.concurrentPerform` test, not a sequential simulation.

Three Warnings surface real, demonstrable gaps that don't rise to Critical but should be tracked: an unaddressed crash window between the managed-file move and the DB insert, an insecure temp-file-name generation pattern in the newly-added notarization zip step, and a fragile fixed-sleep process-liveness check in the end-to-end release script that can produce false failures. Two Info items are minor robustness/consistency notes.

## Warnings

### WR-01: A crash between the managed-file move and the DB insert leaves an orphaned managed file that `hasManagedBIOS` never discovers

**File:** `playstead-mac/Playstead/Adapter/BiosStore.swift:165-199`
**Issue:** `validateAndAccept` moves the validated temp file into `managedDirectory/<digest>` (line 170, or treats a losing race as success at lines 182-184) and *then* executes the `INSERT INTO bios_files ...` (lines 192-199). If the process is killed or crashes in the window between the successful move and the successful insert (e.g. the app is force-quit, or the machine loses power), the byte-correct, digest-named managed file is left on disk with no corresponding `bios_files` row. `hasManagedBIOS(forSystem:)` (line 215-220) and `managedRecord(forSystem:)` (line 222-236) both query only the database, never the filesystem, so the readiness engine will report "no managed BIOS" forever for a system that in fact has a byte-correct file sitting in managed storage. The Task 3 init-time sweep only removes `incomingPrefix`-named entries (line 90, `guard name.hasPrefix(incomingPrefix) else { continue }`), so it explicitly never touches this orphaned 64-hex file — it is neither cleaned up nor healed automatically. The only way this self-heals is if the *exact same file* is dropped again (then `fm.fileExists` at line 166 is true, the temp copy is discarded, and the insert-with-`ON CONFLICT DO NOTHING` succeeds) — a scenario that depends on the user retrying and does not happen on its own.

This is a real gap in the plan's "all-or-nothing" framing (03-11-PLAN.md's `must_haves.truths`: "An interrupted or concurrent BIOS drop leaves no partial file in managed storage, no orphaned incoming temp file, and no more than one database row per accepted digest."). It does not violate the literal wording of that truth (there is no *partial* file, and there is no more than one row — there is zero rows), but it does violate the spirit of "all-or-nothing": a caller can observe a state where the file exists but the store insists it doesn't, with no automatic recovery path and no test covering it. None of the four new concurrency/interruption tests (`testConcurrentIdenticalDropsYieldOneManagedFileAndOneRow`, `testConcurrentDistinctDropsBothSucceed`, `testStaleIncomingTempIsSweptOnNextInitAndManagedFilesSurvive`, `testRejectedCandidateLeavesManagedDirectoryUnchanged`) exercises a crash injected between the move and the insert.

**Fix:** Either (a) make the file move and the DB insert atomic with respect to crash recovery — e.g. have the init-time sweep also reconcile any 64-hex managed file that has no matching `bios_files` row by inserting the missing row (self-healing on next launch), or (b) do the insert first (using the digest as the eventual filename, which is already known before the move) and treat a present-on-disk-but-not-in-DB file as leaked garbage that a startup pass removes. Add a test that simulates the crash window (e.g. by refactoring the move+insert into an injectable seam, or by asserting the invariant directly: construct a managed file with no DB row, restart `BiosStore`, and assert either that `hasManagedBIOS` now returns true (self-healed) or that the orphan is removed).

### WR-02: `mktemp -u` before `ditto` creates a symlink-race window for the notarization submission zip

**File:** `playstead-mac/scripts/sign-and-notarize.sh:113-116`
**Issue:**
```bash
NOTARIZE_ZIP="$(mktemp -u "${TMPDIR:-/tmp}"/playstead-notarize-XXXXXX).zip"
trap 'rm -f "$NOTARIZE_ZIP"' EXIT
echo "==> Creating submission archive for notarytool"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
```
`mktemp -u` only *generates* a name in the (typically world-writable, sticky-bit) shared `TMPDIR`; it does not create or reserve the file. Between the name being generated and `ditto` writing to it, any other local process/user on the same machine can pre-create a file or symlink at that exact path (the `XXXXXX` suffix from `mktemp -u` is still only 6 characters of randomness and is fully predictable once observed once, and no atomicity is provided at all since the path is never actually claimed). If an attacker pre-places a symlink at that path pointing at a file the invoking user can write, `ditto -c` will follow it and overwrite an arbitrary file the build user has write access to (classic mktemp -u / predictable-tmpfile race, CWE-377). This script runs on a developer/release machine, not attacker-controlled infrastructure, so the practical exposure is a local-multiuser scenario — but this is precisely the pattern security reviews flag, and it is newly introduced by this gap-closure plan (03-12-SUMMARY.md documents this ditto/zip step as a genuinely new fix, "Fix #2"), not carried over from an already-reviewed file.
**Fix:** Use `mktemp -d` to create a private (mode 0700), race-free temporary directory and place the zip inside it, e.g.:
```bash
NOTARIZE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/playstead-notarize.XXXXXX")"
trap 'rm -rf "$NOTARIZE_TMPDIR"' EXIT
NOTARIZE_ZIP="$NOTARIZE_TMPDIR/Playstead.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
```
`mktemp -d` creates the directory atomically with owner-only permissions, closing the race entirely.

### WR-03: Fixed `sleep`-then-`pgrep` liveness checks in the launch/exit/relaunch proof are flaky, not deterministic

**File:** `playstead-mac/scripts/verify-notarized-release.sh:117-140`
**Issue:** The launch/exit/relaunch section uses `open "$APP_PATH"; sleep 3; if ! pgrep -f ...` and `osascript ... quit; sleep 2; if pgrep -f ...` with no retry/backoff. On a loaded CI/release machine, or with a slower app-startup path (e.g. cold-cache CoreData/SQLite migration, Gatekeeper's own on-first-launch notarization check taking longer than usual), 3 seconds may not be enough for the process to appear, producing a false `FATAL: notarized app failed to launch` on a build that is in fact fine — the exact "genuinely flaky gate" failure mode adjacent to (though not identical to) the fail-open patterns this phase set out to close. Symmetrically, 2 seconds may not be enough for a slow quit, producing a false `FATAL: notarized app failed to exit cleanly`.
**Fix:** Replace the fixed sleeps with a bounded polling loop (e.g. `for i in $(seq 1 20); do pgrep -f ... && break; sleep 0.5; done`) with a final check after the loop, for both the launch-detection and exit-detection points.

## Info

### IN-01: `verify-bios-reference.sh` treats a symlink as an ordinary file, unlike `BiosStore` itself

**File:** `playstead-mac/scripts/verify-bios-reference.sh:35`
**Issue:** `[ ! -f "$CANDIDATE" ]` follows symlinks (bash's `-f` test is true for a symlink whose target is a regular file), so an operator pointing the script at a symlink gets it silently dereferenced and measured/hashed, whereas `BiosStore.validateAndAccept` explicitly refuses any symlink outright (`BiosStore.swift:120-122`). This script is documented as optional corroboration only ("Corroboration is optional; the two-source citation is not" — 03-11-PLAN.md), not the actual security gate, so this is low severity, but the inconsistency means an operator could get a `MATCH` from this script for a symlink that the real app would reject outright, which is mildly misleading.
**Fix:** Add a symlink check mirroring `BiosStore`'s (`[ -L "$CANDIDATE" ] && { echo "symbolic links are not accepted" >&2; exit 1; }`) for parity with the real acceptance path.

### IN-02: `sign-and-notarize.sh` performs the Developer ID Application check twice on one code path

**File:** `playstead-mac/scripts/sign-and-notarize.sh:91-97` and `:99-106`
**Issue:** When `PLAYSTEAD_REQUIRE_NOTARIZATION=1` *and* `PLAYSTEAD_NOTARY_PROFILE` is set, the unconditional strict-mode check at lines 91-97 already asserts a Developer ID Application identity is present; the `if [ "$PLAYSTEAD_REQUIRE_NOTARIZATION" != "1" ]` guard at line 100 correctly skips the duplicate check for that combination, so no functional bug results, but the two blocks now express overlapping logic in two places (a change to one identity-check message could silently drift from the other). Not a behavior defect — flagged for maintainability only.
**Fix:** Consider consolidating into a single "is Developer ID identity present" boolean computed once and reused by both branches, to prevent future drift between the strict-mode and legacy messages.

## Findings Explicitly Not Made (verified clean)

- No Critical findings. No secret, app-specific password, keychain profile content, or BIOS acquisition/download/mirror/source hint was found in any of the 10 reviewed files, the pin file, or the notarization evidence file.
- The `-only-testing:` identifier bugs documented in both SUMMARY files as deviations were checked against the current script text and are correctly fixed in the shipped files (`verify-notarized-release.sh:115` now reads `PlaysteadTests/RelaunchTests`, not the `AdapterTests`-segment form that matched zero tests).
- Both fail-closed guard scripts (`bios-pin-provenance-test.sh`, `notarization-preflight-test.sh`) were checked line-by-line for the "missing command reads as clean" shape (bare `if cmd; then` on a command that could 127) and neither has it — both capture `$?` into a variable immediately with `set +e`/`set -e` bracketing before comparing.
- The digest-then-length ordering and the two-direction guard tests (both a refusal-fires and a refusal-does-not-always-fire assertion) are real and correctly structured, not vacuous.

---

_Reviewed: 2026-09-11_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
