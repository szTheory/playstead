---
phase: 03-mac-offline-play-vertical-slice
reviewed: 2026-09-11T06:00:00Z
depth: standard
scope_source: "Round 2: gap-closure diff 33a06a1..HEAD (LIBR-02); Round 1: gap-closure diff 9baa136..HEAD (BIOS/notarization)"
files_reviewed: 24
files_reviewed_list:
  - .github/workflows/ci.yml
  - playstead-mac/Playstead/App/PlaysteadApp.swift
  - playstead-mac/Playstead/Cache/AvailabilityReporter.swift
  - playstead-mac/Playstead/Cache/AvailabilityVocabulary.swift
  - playstead-mac/Playstead/Sync/CurationIntent.swift
  - playstead-mac/Playstead/Sync/Outbox.swift
  - playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/AvailabilityVocabularyContractTests.swift
  - playstead-mac/scripts/ci/run-mac-verification.sh
  - playstead-server/lib/playstead/availability.ex
  - playstead-server/lib/playstead/availability/device_report.ex
  - playstead-server/lib/playstead/availability_vocabulary.ex
  - playstead-server/lib/playstead/protocol/capabilities.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex
  - playstead-server/lib/playstead_web/live/library_live.ex
  - playstead-server/lib/playstead_web/live/library_live/status_slot.ex
  - playstead-server/lib/playstead_web/router.ex
  - playstead-server/lib/playstead_web/plugs/device_auth.ex
  - playstead-server/priv/repo/migrations/20260911000000_create_device_asset_availability.exs
  - playstead-server/test/playstead/availability_test.exs
  - playstead-server/test/playstead_web/browser/coherence_test.exs
  - playstead-server/test/playstead_web/controllers/api/v1/availability_controller_test.exs
  - playstead-server/test/playstead_web/controllers/api/v1/capabilities_controller_test.exs
  - playstead-server/test/playstead_web/live/availability_vocabulary_contract_test.exs
  - shared/availability-vocabulary.json
  - scripts/check-uat-tally.sh
findings:
  critical: 0
  warning: 3
  info: 0
  total: 3
rounds:
  - "Round 2 — LIBR-02 availability (33a06a1..HEAD)"
  - "Round 1 — BIOS / notarization (9baa136..HEAD)"
status: issues_found
---

# Phase 3 Gap-Closure Code Review Report

This file accumulates every gap-closure review round for Phase 3. Round 2 (below) is the newest; Round 1's findings are preserved verbatim underneath it, unmodified.

## Round 2 — LIBR-02 availability (33a06a1..HEAD)

**Reviewed:** 2026-09-11
**Depth:** standard
**Files Reviewed:** 25 (server + Mac + CI + shared fixture; see `files_reviewed_list` above)
**Status:** issues_found (no Critical findings; 3 Warnings, 0 Info)

### Summary

This round covers the two 03-13/03-14 gap-closure plans that build the device-reported availability read model, the frozen six-value console filter, the Mac client reporter, and the UAT-tally CI hygiene guard. I traced the claims in both SUMMARYs against the actual current source rather than trusting the narration, with particular attention to authn/authz on the new endpoint, single-sourcing of the frozen vocabulary, the elimination of the pass-through defect in `matches_availability?/3`, migration integrity, and fail-closed behavior of the new CI gates.

The core claims hold up:

- **Authn/authz on `PUT /api/v1/devices/me/availability`.** `DeviceAuth` assigns `current_device` from a real Bearer-token lookup (`Pairing.authenticate/1`) — there is no way to reach this endpoint unauthenticated or to pass a device ID via a body/query parameter. `Playstead.Availability.replace_for_device/2` filters every reported entry to asset sets owned by `device.user_id` *before* any insert (`owned_asset_set_ids/2`), and this is genuinely tested (`availability_test.exs` — "a report naming another user's asset set is rejected -- no row is written for it"), not merely claimed. `build_changeset/3` whitelists exactly five fact fields via `Map.take/2` before merging in server-derived `device_id`/`user_id`/`reported_at` — no mass-assignment path exists for a client to set `device_id`, `user_id`, or any column outside the five facts.
- **Vocabulary single-sourcing.** `Playstead.AvailabilityVocabulary`, `shared/availability-vocabulary.json`, and the Swift `AvailabilityVocabulary` enum are proven to agree exhaustively, in both directions, by two independent contract test suites (`availability_vocabulary_contract_test.exs`, `AvailabilityVocabularyContractTests.swift`), each of which includes an actual negative case (a key removed or added breaks exact-equality) rather than a merely-additive assertion. `AvailabilityVocabulary.valid?/1` is a plain binary-membership test — no `String.to_atom/1` path exists for a client-supplied filter value, confirmed by direct read of the module and its test.
- **`matches_availability?/3` is genuinely fixed.** Six explicit clauses, one per frozen vocabulary value, each delegating to `StatusSlot.rank/1`'s already-ordered ladder (`needs_attention > missing_dependency > downloading > queued > pinned/verified > server_only`), with `ready_offline` correctly matching both `:pinned` and `:verified`. The old unconditional pass-through clause is gone; the remaining catch-all (line 208) only reaches unreachable-from-the-UI paths and itself refuses anything `AvailabilityVocabulary.valid?/1` doesn't recognise, so it cannot resurrect the original defect. This is confirmed structurally sound, not merely re-arranged.
- **Migration integrity.** `unique_index(:device_asset_availability, [:device_id, :asset_set_id])` prevents duplicate per-device rows; `[:user_id, :asset_set_id]` supports the per-user merge read; all three foreign keys (`device_id`, `user_id`, `asset_set_id`) cascade `:delete_all`, so a deleted device/user/asset-set can never leave an orphaned report row; a DB-level `download_percent_range` check constraint backs the changeset-level validation.
- **`check-uat-tally.sh` and its CI wiring fail closed.** The script uses `if ! python3 ...; then STATUS=1; fi` (inverted sense — a missing `python3` binary, exit 127, is caught by the `!` and correctly treated as failure, not silently passed). The empty-glob case, missing-`## Summary` case, and zero-derived-total case are all explicit `fail()` calls with `exit 1`. The CI step has no `continue-on-error`, so a non-zero exit fails the job.
- **The new Mac test suites actually run and a zero-discovery run fails.** `run-mac-verification.sh` names both new suites explicitly via `--required-test`, and a separate `raise SystemExit(...)` guard rejects a result containing zero executed tests, independent of exit-code alone.

Three Warnings surface real, demonstrable gaps that do not rise to Critical: an unvalidated `entries` payload shape crashes into a generic 500 instead of a clean 422, the new Mac-side full-replacement outbox intent has no protection against being delivered out of enqueue order (a correctness property only this new intent kind actually needs), and one of the six "genuinely discriminating" filter values is permanently unreachable in production because no code path ever asserts it true — a fact the SUMMARY's "known stub" framing understates.

### Warnings

#### WR-04: A malformed `entries` payload shape crashes into a generic 500 instead of a clean 422

**File:** `playstead-server/lib/playstead/availability.ex:56-88` (the `is_list` guard clause boundary), `playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex:24`
**Issue:** `AvailabilityController.replace/2` does `entries = Map.get(params, "entries", [])` with no shape validation, then passes it straight to `Availability.replace_for_device/2`, whose only guard is `when is_list(entries)`. If `entries` is present but is not a list (e.g. a JSON object or a string), there is no matching function clause and Elixir raises `FunctionClauseError` — no clause in `AvailabilityController`, `Idempotency.execute/4`, or `Playstead.Availability` catches this, so it propagates out of the `Ecto.Multi.run` step inside `Idempotency.execute/4` uncaught, and is only stopped by `PlaysteadWeb.Plugs.ApiProblemHandler`'s router-level rescue, which renders a generic `500 internal_error` instead of the sibling endpoints' clean `422 validation_failed`. The same failure mode occurs one level deeper: if `entries` is a list but contains a non-map element (e.g. `["oops"]`) or a value with no `Enumerable` implementation, `normalize_entry/1`'s `Map.new(entry, fn {k, v} -> ... end)` raises `Protocol.UndefinedError` for the same reason. No test in `availability_controller_test.exs` or `availability_test.exs` exercises a non-list or non-map-element `entries` payload — every existing test sends a well-formed list of maps. This is client-facing JSON from an authenticated-but-not-necessarily-trustworthy device; a buggy or malicious client build can trigger this at will, turning what should be a routine validation error into a 500 (and a stack-trace-adjacent code path) on every occurrence.
**Fix:** Validate the shape explicitly before calling into the context, returning the same `422 :validation_failed` problem+json every other malformed-body case gets:
```elixir
def replace(conn, params) do
  case Map.get(params, "entries", []) do
    entries when is_list(entries) ->
      if Enum.all?(entries, &is_map/1) do
        # existing effect_fun / Idempotency.execute path
      else
        PlaysteadWeb.Problem.send_problem(conn, 422, :validation_failed, "Each entry must be a JSON object.")
      end

    _other ->
      PlaysteadWeb.Problem.send_problem(conn, 422, :validation_failed, "\"entries\" must be an array.")
  end
end
```

#### WR-05: `.availabilityReport` outbox entries have no protection against out-of-order delivery, unlike every other intent kind

**File:** `playstead-mac/Playstead/Sync/Outbox.swift:141-148` (`listPending`'s backoff-skip ordering), `playstead-mac/Playstead/Cache/AvailabilityReporter.swift:103-107` (`reportAll` unconditionally enqueuing a fresh row every call), `playstead-mac/Playstead/App/PlaysteadApp.swift:804` (`syncNow()` invoking `reportAll()` every sync pass)
**Issue:** `Outbox.listPending(at:)` selects due `pending` rows with `WHERE state = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= ?) ORDER BY created_at ASC` — an entry whose delivery failed and is backed off (`next_retry_at` in the future) is explicitly *skipped* by this query, so a **later-enqueued, currently-due** entry is sent before an **earlier-enqueued, currently-backed-off** one once the earlier one's backoff expires. For every other `CurationIntent` kind this is harmless, because each targets a distinct local row (`localRowID`) — reordering two `queueEnqueue` calls for different rows changes nothing about correctness. `.availabilityReport` is different: `AvailabilityReporter.reportAll()` is called on every `syncNow()` pass (`PlaysteadApp.swift:804`) and unconditionally enqueues a brand-new full-replacement row every time, with a fresh `id` and no relation to any previous report — nothing coalesces, supersedes, or cancels a still-pending prior report before enqueuing the new one. Concretely: if report A (older, e.g. "downloading 40%") transiently fails and backs off, and a later sync's report B ("verified, done") is enqueued and succeeds first, then A's backoff subsequently expires and A is delivered *after* B — the server's read model (`Playstead.Availability.replace_for_device/2` does a full replacement) now shows the stale "downloading 40%" facts even though the device has since finished and moved on, until the next `syncNow()` corrects it. This is a genuine violation of the "full replacement of current state" semantics both the Elixir moduledoc and this file's own doc comment claim. No test in `AvailabilityReporterTests.swift` exercises two `reportAll()` calls with the first backed off and the second succeeding first — `test_sameReportRetried_carriesSameIdempotencyKeyAndOneServerEffect` only retries a *single* enqueued row's delivery, which preserves the row's own `idempotencyKey` and says nothing about ordering across two distinct enqueued reports.
**Fix:** Before enqueuing a new `.availabilityReport`, delete/supersede any other still-`pending` or backed-off `outbox_entries` row of `kind = 'availability_report'` in the same transaction (there is at most one meaningful in-flight report per device at any time, since each is a full replacement of the same universal fact set) — e.g. add an `Outbox.supersedePending(kind:)` helper called from `AvailabilityReporter.reportAll()` immediately before `outbox.enqueue(...)`. Alternatively, change `listPending`'s ordering discipline so that within a single `kind`, only the newest due row for `.availabilityReport` is ever selected. Add a test that enqueues two reports, forces the first into backoff, lets the second succeed, and asserts the *second* report's facts win even after the first's backoff expires and it is (harmlessly) delivered or dropped.

#### WR-06: `missing_dependency` is one of the "six genuinely discriminating" filter values, but no code path in this codebase can ever make it true — the chip is permanently dead in production

**File:** `playstead-mac/Playstead/Cache/AvailabilityReporter.swift:140` (`missingDependency: false` — hardcoded), `playstead-server/lib/playstead_web/live/library_live.ex:188-189` (the `"missing_dependency"` filter clause)
**Issue:** 03-13-SUMMARY.md and 03-14-SUMMARY.md both frame LIBR-02 as closed because "the console now genuinely filters by all six UI-SPEC availability/readiness values ... fed by a real device." That framing is accurate for five of the six values, but `AvailabilityReporter.buildEntries` hardcodes `missingDependency: false` on every entry it ever builds (03-14-SUMMARY.md's own "Known Stubs" section discloses this as "not exercised by this plan's `<behavior>` list" and states "this does not corrupt the read model, it simply never asserts that fact from this client"). That framing understates the actual consequence: there is no other writer of `device_asset_availability.missing_dependency` anywhere in this codebase (the field is device-reported only, per `Playstead.Availability`'s moduledoc — "the server stores them per device ... the console never derives these facts itself") and no other client exists. The practical result is that the `missing_dependency` filter chip — one of the six values `03-VERIFICATION.md`'s LIBR-02 gap explicitly named as needing to "genuinely discriminate" — will show **zero results, permanently, in every real deployment**, not merely "less complete" data. This is a materially different claim than "the field defaults to false and doesn't corrupt the model": a console filter chip that can structurally never match anything is functionally equivalent to the pass-through defect this same gap-closure round set out to fix, just inverted (always-empty instead of always-everything). This was not caught by any automated test because `library_live_test.exs`'s six-value discrimination test presumably seeds a fixture with `missing_dependency: true` directly in the read model (bypassing the Mac client entirely) rather than proving the fact can ever arise from a real device report.
**Fix:** Either (a) implement a real signal for `missing_dependency` on the Mac client (e.g. a required member present in the catalogue manifest but absent from `CASManager` and not currently downloading nor queued — the actual "missing something it needs to play" condition `StatusSlot`'s accessible-name text describes), or (b) explicitly record this as a distinct, higher-visibility gap in `.planning/WINDOWS.md` and `03-VERIFICATION.md` stating that the `missing_dependency` filter chip is currently unreachable in production (not just "the field reports false"), so a future reader doesn't mistake "the chip exists and is wired" for "the chip can ever show a result."

### Findings Explicitly Not Made (verified clean)

- **No Critical findings.** No authentication bypass, no cross-user data leak (explicitly tested), no atom-exhaustion path, no SQL/command injection, and no missing rate/size limit on the reported payload (`@max_entries 5000`, tested) were found in this round's scope.
- **The pass-through defect this round exists to close is genuinely closed**, not merely rearranged — verified directly against `matches_availability?/3` and `StatusSlot.rank/1`'s ladder, both traced line-by-line.
- **The frozen vocabulary is genuinely single-sourced** across all three surfaces (Elixir module, Swift enum, shared JSON fixture), with real bidirectional negative-case tests on both the Elixir and Swift sides, independently confirmed by direct reading of both test files (not merely trusting the SUMMARY's "delete a key and watch it fail" narration).
- **`scripts/check-uat-tally.sh` fails closed** in every direction its own doc comment claims, verified by reading the actual bash/python control flow rather than trusting the SUMMARY's "corrupt-and-revert" narration.
- **The new Mac test suites are genuinely registered and a zero-discovery run is guarded against** — verified against `run-mac-verification.sh`'s `--required-test` list and its separate zero-executed-tests `SystemExit` check.
- **The migration's constraints (unique index, cascade deletes, DB-level range check) are correct and match the context module's stated invariants.**

---

## Round 1 — BIOS / notarization (9baa136..HEAD)

**Reviewed:** 2026-09-11
**Depth:** standard
**Files Reviewed:** 10 (plus `.planning/.../03-BIOS-PIN.json`, `03-NOTARIZATION-EVIDENCE.md`, and the two named docs read for content hygiene only)
**Status:** issues_found (no Critical findings; 3 Warnings, 2 Info)

### Summary

This review covers exactly the diff `9baa136..HEAD` outside `.planning/`: the two gap-closure plans that (03-11) wire a real, cited BIOS reference into `BiosStore`/`PlaysteadApp` and harden the drop path against interruption/concurrency, and (03-12) turn `sign-and-notarize.sh` into a fail-closed strict-mode release path and record a genuine notarization run.

I traced every claim in `03-11-PLAN.md`/`03-12-PLAN.md` and their SUMMARY files against the actual current file contents rather than trusting the summaries. The core security-relevant guarantees hold up under adversarial reading:

- **Trust anchor correctness.** `BiosReferences.production` and `03-BIOS-PIN.json` both carry the same 64-lowercase-hex digest and byte length (`16384` / `fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570`, independently confirmed 64 characters by direct count), the parity test (`testProductionLiteralsMatchThePinFile`) genuinely compares both fields and would fail if either side were edited alone, and `BiosStore.validateAndAccept` checks length *before* computing a digest, so the length gate cannot be bypassed by a byte-length mismatch masquerading as a digest match.
- **Empty-vs-real-reference discriminator.** The two distinct rejection strings (`"no known reference for this system yet"` vs `"this file's contents don't match a known reference"`) are real, distinct, and both covered by tests that assert the exact string, not just "something was thrown."
- **Fail-closed shell.** All five reviewed scripts use `set -euo pipefail`, capture exit codes into variables before comparing them (never `if cmd; then` on a possibly-missing binary), and the two provenance/preflight guards both include genuine negative controls that are shown to fail — this is the exact anti-pattern class this project has been bitten by before, and it is closed correctly here.
- **Prohibited-content hygiene.** No URL, download hint, acquisition path, credential, or app-specific password appears anywhere in the reviewed scripts, the pin file, or `03-NOTARIZATION-EVIDENCE.md`. The provenance URLs in `BiosReferences.swift`/`03-BIOS-PIN.json` are citations (as the plan explicitly permits), not acquisition hints, and are followed immediately by an explicit no-acquisition statement in both places.
- **Move-race handling.** The move-race fix in `BiosStore.validateAndAccept` (catch the move failure, re-check `fileExists`, treat "someone else already won" as success) is correct for the two-concurrent-identical-drops case and is proven by a real `DispatchQueue.concurrentPerform` test, not a sequential simulation.

Three Warnings surface real, demonstrable gaps that don't rise to Critical but should be tracked: an unaddressed crash window between the managed-file move and the DB insert, an insecure temp-file-name generation pattern in the newly-added notarization zip step, and a fragile fixed-sleep process-liveness check in the end-to-end release script that can produce false failures. Two Info items are minor robustness/consistency notes.

### Warnings

#### WR-01: A crash between the managed-file move and the DB insert leaves an orphaned managed file that `hasManagedBIOS` never discovers

**File:** `playstead-mac/Playstead/Adapter/BiosStore.swift:165-199`
**Issue:** `validateAndAccept` moves the validated temp file into `managedDirectory/<digest>` (line 170, or treats a losing race as success at lines 182-184) and *then* executes the `INSERT INTO bios_files ...` (lines 192-199). If the process is killed or crashes in the window between the successful move and the successful insert (e.g. the app is force-quit, or the machine loses power), the byte-correct, digest-named managed file is left on disk with no corresponding `bios_files` row. `hasManagedBIOS(forSystem:)` (line 215-220) and `managedRecord(forSystem:)` (line 222-236) both query only the database, never the filesystem, so the readiness engine will report "no managed BIOS" forever for a system that in fact has a byte-correct file sitting in managed storage. The Task 3 init-time sweep only removes `incomingPrefix`-named entries (line 90, `guard name.hasPrefix(incomingPrefix) else { continue }`), so it explicitly never touches this orphaned 64-hex file — it is neither cleaned up nor healed automatically. The only way this self-heals is if the *exact same file* is dropped again (then `fm.fileExists` at line 166 is true, the temp copy is discarded, and the insert-with-`ON CONFLICT DO NOTHING` succeeds) — a scenario that depends on the user retrying and does not happen on its own.

This is a real gap in the plan's "all-or-nothing" framing (03-11-PLAN.md's `must_haves.truths`: "An interrupted or concurrent BIOS drop leaves no partial file in managed storage, no orphaned incoming temp file, and no more than one database row per accepted digest."). It does not violate the literal wording of that truth (there is no *partial* file, and there is no more than one row — there is zero rows), but it does violate the spirit of "all-or-nothing": a caller can observe a state where the file exists but the store insists it doesn't, with no automatic recovery path and no test covering it. None of the four new concurrency/interruption tests (`testConcurrentIdenticalDropsYieldOneManagedFileAndOneRow`, `testConcurrentDistinctDropsBothSucceed`, `testStaleIncomingTempIsSweptOnNextInitAndManagedFilesSurvive`, `testRejectedCandidateLeavesManagedDirectoryUnchanged`) exercises a crash injected between the move and the insert.

**Fix:** Either (a) make the file move and the DB insert atomic with respect to crash recovery — e.g. have the init-time sweep also reconcile any 64-hex managed file that has no matching `bios_files` row by inserting the missing row (self-healing on next launch), or (b) do the insert first (using the digest as the eventual filename, which is already known before the move) and treat a present-on-disk-but-not-in-DB file as leaked garbage that a startup pass removes. Add a test that simulates the crash window (e.g. by refactoring the move+insert into an injectable seam, or by asserting the invariant directly: construct a managed file with no DB row, restart `BiosStore`, and assert either that `hasManagedBIOS` now returns true (self-healed) or that the orphan is removed).

#### WR-02: `mktemp -u` before `ditto` creates a symlink-race window for the notarization submission zip

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

#### WR-03: Fixed `sleep`-then-`pgrep` liveness checks in the launch/exit/relaunch proof are flaky, not deterministic

**File:** `playstead-mac/scripts/verify-notarized-release.sh:117-140`
**Issue:** The launch/exit/relaunch section uses `open "$APP_PATH"; sleep 3; if ! pgrep -f ...` and `osascript ... quit; sleep 2; if pgrep -f ...` with no retry/backoff. On a loaded CI/release machine, or with a slower app-startup path (e.g. cold-cache CoreData/SQLite migration, Gatekeeper's own on-first-launch notarization check taking longer than usual), 3 seconds may not be enough for the process to appear, producing a false `FATAL: notarized app failed to launch` on a build that is in fact fine — the exact "genuinely flaky gate" failure mode adjacent to (though not identical to) the fail-open patterns this phase set out to close. Symmetrically, 2 seconds may not be enough for a slow quit, producing a false `FATAL: notarized app failed to exit cleanly`.
**Fix:** Replace the fixed sleeps with a bounded polling loop (e.g. `for i in $(seq 1 20); do pgrep -f ... && break; sleep 0.5; done`) with a final check after the loop, for both the launch-detection and exit-detection points.

### Info

#### IN-01: `verify-bios-reference.sh` treats a symlink as an ordinary file, unlike `BiosStore` itself

**File:** `playstead-mac/scripts/verify-bios-reference.sh:35`
**Issue:** `[ ! -f "$CANDIDATE" ]` follows symlinks (bash's `-f` test is true for a symlink whose target is a regular file), so an operator pointing the script at a symlink gets it silently dereferenced and measured/hashed, whereas `BiosStore.validateAndAccept` explicitly refuses any symlink outright (`BiosStore.swift:120-122`). This script is documented as optional corroboration only ("Corroboration is optional; the two-source citation is not" — 03-11-PLAN.md), not the actual security gate, so this is low severity, but the inconsistency means an operator could get a `MATCH` from this script for a symlink that the real app would reject outright, which is mildly misleading.
**Fix:** Add a symlink check mirroring `BiosStore`'s (`[ -L "$CANDIDATE" ] && { echo "symbolic links are not accepted" >&2; exit 1; }`) for parity with the real acceptance path.

#### IN-02: `sign-and-notarize.sh` performs the Developer ID Application check twice on one code path

**File:** `playstead-mac/scripts/sign-and-notarize.sh:91-97` and `:99-106`
**Issue:** When `PLAYSTEAD_REQUIRE_NOTARIZATION=1` *and* `PLAYSTEAD_NOTARY_PROFILE` is set, the unconditional strict-mode check at lines 91-97 already asserts a Developer ID Application identity is present; the `if [ "$PLAYSTEAD_REQUIRE_NOTARIZATION" != "1" ]` guard at line 100 correctly skips the duplicate check for that combination, so no functional bug results, but the two blocks now express overlapping logic in two places (a change to one identity-check message could silently drift from the other). Not a behavior defect — flagged for maintainability only.
**Fix:** Consider consolidating into a single "is Developer ID identity present" boolean computed once and reused by both branches, to prevent future drift between the strict-mode and legacy messages.

### Findings Explicitly Not Made (verified clean)

- No Critical findings. No secret, app-specific password, keychain profile content, or BIOS acquisition/download/mirror/source hint was found in any of the 10 reviewed files, the pin file, or the notarization evidence file.
- The `-only-testing:` identifier bugs documented in both SUMMARY files as deviations were checked against the current script text and are correctly fixed in the shipped files (`verify-notarized-release.sh:115` now reads `PlaysteadTests/RelaunchTests`, not the `AdapterTests`-segment form that matched zero tests).
- Both fail-closed guard scripts (`bios-pin-provenance-test.sh`, `notarization-preflight-test.sh`) were checked line-by-line for the "missing command reads as clean" shape (bare `if cmd; then` on a command that could 127) and neither has it — both capture `$?` into a variable immediately with `set +e`/`set -e` bracketing before comparing.
- The digest-then-length ordering and the two-direction guard tests (both a refusal-fires and a refusal-does-not-always-fire assertion) are real and correctly structured, not vacuous.

---

_Reviewed: 2026-09-11_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
