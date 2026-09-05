---
phase: 04-persistent-save-continuity
plan: 20
subsystem: saves
tags: [cas, eviction, save-capture, gap-closure, windows-49]
status: complete
requires:
  - 04-19 (capture wired end-to-end into the shipped Play path)
provides:
  - "Locally-captured save bytes are committed into the CAS at promotion, so `LaunchSaveContextBuilder` reports `bytesLocal: true` for them"
  - "`EvictionPlanner.unreferencedObjects()` structurally cannot offer a save blob for deletion"
affects:
  - playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift
  - playstead-mac/Playstead/Cache/EvictionPlanner.swift
  - playstead-mac/Playstead/App/PlaysteadApp.swift
  - playstead-mac/Playstead/UITesting/DeterministicProfile.swift
tech-stack:
  added: []
  patterns:
    - "Copy-then-commit into the CAS: `CASManager.commit(partialAt:)` *moves* its source, so a capture artifact that another consumer still reads is staged as a copy under `partials/` and the copy is what gets moved."
    - "Required-not-optional dependency injection as a fail-closed device: both new dependencies (`EvictionPlanner.saveStore`, `SaveSessionCoordinator.casManager`) are non-optional with no default, because a `nil` default would silently reproduce the exact defect being closed."
key-files:
  created: []
  modified:
    - playstead-mac/Playstead/Cache/EvictionPlanner.swift
    - playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/Playstead/UITesting/DeterministicProfile.swift
    - playstead-mac/PlaysteadTests/CacheTests/EvictionTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveSessionCoordinatorTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/LaunchSaveContextBuilderTests.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveQuotaInteractionTests.swift
decisions:
  - "On a CAS commit failure the revision row is still inserted and the failure is surfaced as a D-31 blockage, rather than abandoning the row. The row's `localPath` bytes are durable and uploadable, so dropping it would turn a durability improvement into save loss — strictly worse than the pre-existing `bytesLocal: false` degradation."
  - "`plan(for:)` and `candidates()` were left without a save-blob filter, documented in a comment. Both only ever select SHAs drawn from `catalogue_members WHERE required = 1`; a redundant filter would imply the invariant is doubtful."
  - "The identical hole on the crash-recovery path (`SaveSessionRecovery`) was disclosed as WINDOWS #52 rather than folded in, following the norm 04-19 established when it disclosed WINDOWS #49 rather than expanding its own scope."
metrics:
  duration: "~35 min"
  completed: 2026-09-05
actuals:
  tokens: 7300
  tasks: 3
  commits: 3
---

# Phase 04 Plan 20: Save Bytes Are Really Local Summary

Locally-captured save bytes now enter the CAS at promotion, so `LaunchSaveContextBuilder` reports `bytesLocal: true` for a save this Mac made — and save blobs are permanently off the reclaim menu, landed first so that window never existed.

## What Shipped

**Task 1 — `10783c4`** `fix(04-20): exclude save blobs from the reclaim menu`

`EvictionPlanner` takes a required `SaveStore` and `unreferencedObjects()` excludes any sha appearing as a revision `blobSHA256`. Save blobs have no catalogue member record by construction, so once task 2 put them in the CAS they would otherwise have surfaced in StorageView as removable junk — and unlike a catalogue object, a local-only save cannot be re-fetched. Both shipped construction sites updated (`PlaysteadApp.swift`, `DeterministicProfile.swift`).

This landed **before** task 2 deliberately. Reversed, there is a window in which the user's only copy of a save is offered for deletion.

**Task 2 — `de3aec1`** `feat(04-20): commit capture bytes into the CAS at promotion`

`SaveSessionCoordinator` takes a required `CASManager` and commits both the promoted and the session-start baseline capture, using the digest the poller already computed — never recomputed, so it cannot disagree with the digest the revision row records. The commit runs before `SaveStore.insertRevision`. An already-present digest is a no-op.

The non-obvious part: `CASManager.commit(partialAt:)` **moves** its source, and `capture.localPath` is the artifact `SaveUploadLane` reads bytes from. Handing it the capture directly would have broken upload for every save. A copy is staged under `partials/` and the copy is what gets moved; a dedicated test asserts the capture artifact survives.

**Task 3 — `0fe5c83`** `test(04-20): prove bytesLocal is true at the surface that had the hole`

A test through `LaunchSaveContextBuilder` — the type that actually derives `bytesLocal`. It seeds nothing by hand: a real `SaveSessionCoordinator` session captures bytes off disk, then the real builder is asked what it makes of the result. No server on either half.

## Falsification (required, and actually run)

With `commitCaptureBytes` deleted from both call sites **and the test bundle rebuilt**, the new test failed at exactly the `bytesLocal` assertion:

```
LaunchSaveContextBuilderTests.swift:131: error: XCTAssertTrue failed -
a save captured on this Mac must be restorable from history without a server round-trip
```

The call was restored and the file verified byte-identical to `de3aec1` (`git diff` empty).

**A near-miss worth recording.** The first post-restore full-suite run reported 4 failures. The cause was not the code: `xcodebuild test-without-building` ran the *stale falsified bundle*, because restoring the source does not rebuild. This is the inverse of the fail-open shape in the project's memory ("a missing command exits 127, which `if cmd` reads as clean") — here a stale artifact produced a false *red*, but the identical mechanism would produce a false *green* if the falsification and restore were ordered the other way. **`test-without-building` after any source edit is meaningless until `build-for-testing` reruns.**

## Verification

| Gate | Baseline | Result |
|---|---|---|
| Swift Unit | 536 tests | **545 executed, 0 failures** (exit 0) |
| Rendering | 46 executed / 2 skipped | **46 executed, 2 skipped, 0 failures** (exit 0) |
| `reachability-sweep.sh --strict` | exit 0, allowlist unchanged | **exit 0**, "No unreachable production symbols found", allowlist untouched |

+9 tests: 3 eviction, 5 coordinator, 1 builder. Exit codes read directly from `$?` with `set -o pipefail`, never through a pipe. The two known-flaky tests did not fire.

## Deviations from Plan

**1. [Rule 2 — Missing critical functionality] CAS commit failure still records the revision row**

- **Found during:** Task 2
- **Plan text:** "Commit before `SaveStore.insertRevision`, so a revision row never exists claiming bytes the CAS does not have," with failure "handled the same way 04-19 handles a capture failure" — and 04-19 handles a capture failure by recording no revision at all.
- **Issue:** Applied literally, a CAS commit failure would drop the promoted revision entirely. But the revision's real durability is `localPath` — the artifact `SaveUploadLane` uploads from — which is written and fsynced before the CAS is ever touched. Dropping the row would make save capture *more* fragile than it was before this plan: a regression introduced by a durability improvement, converting a `bytesLocal: false` degradation into outright save loss.
- **Fix:** Ordering preserved exactly as specified (CAS first, then insert). On failure the row is still inserted and the failure is surfaced as a D-31 blockage. The launch is unaffected either way, and the failure is never silent.
- **Files modified:** `SaveSessionCoordinator.swift`
- **Commit:** `de3aec1`
- **Test:** `testACASCommitFailureLeavesTheLaunchUnaffectedAndIsRecordedAsBlocked`

**2. [Scope boundary — disclosed, not fixed] The crash-recovery path has the identical hole**

`SaveSessionRecovery.replay` (D-07, reachable in production via `AppEnvironment.recoverAbandonedSaveSessionsAtLaunch`, wired by 04-19) records a promoted revision but holds no `CASManager`. A crash-recovered capture therefore still reads as `bytesLocal: false` — WINDOWS #49's defect reached via the second capture path.

Not folded in: the plan's `files_modified` names `SaveSessionCoordinator` only, and this phase's established norm — the one that produced *this* plan — is to disclose an adjacent hole rather than silently expand scope. Logged as **WINDOWS #52**, with the note that the fix should extract `commitCaptureBytes` into one shared spelling rather than a second copy (the plan's own prohibition against a second bytes-local mechanism applies).

## Broken-Windows Ledger

- **WINDOWS #49 → fixed** (`10783c4`, `de3aec1`)
- **WINDOWS #52 → open** (new): `SaveSessionRecovery` crash-recovery captures do not reach the CAS

Ledger counts reconciled: open 40, waived 1, fixed 11, total 52.

## Known Stubs

None introduced.

## Self-Check: PASSED

- `playstead-mac/Playstead/Cache/EvictionPlanner.swift` — FOUND, contains `saveBlobSHAs()`
- `playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift` — FOUND, `grep -n "casManager"` returns the property (line 68), the init param (87), and the commit call (259)
- `playstead-mac/PlaysteadTests/SavesTests/LaunchSaveContextBuilderTests.swift` — FOUND, contains the falsified-and-restored test
- Commits `10783c4`, `de3aec1`, `0fe5c83` — all present in `git log`
- Working tree clean for all plan files; `git diff` against `de3aec1` empty for `SaveSessionCoordinator.swift` after falsification restore
