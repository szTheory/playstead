---
phase: 04-persistent-save-continuity
reviewed: 2026-09-05T00:00:00Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - playstead-mac/Playstead/App/PlaysteadApp.swift
  - playstead-mac/Playstead/Library/GameRowView.swift
  - playstead-mac/Playstead/Library/LibraryShellView.swift
  - playstead-mac/Playstead/Persistence/Migrations.swift
  - playstead-mac/Playstead/Persistence/SaveStore.swift
  - playstead-mac/Playstead/Readiness/ReadinessSheetView.swift
  - playstead-mac/Playstead/Saves/SaveCaptureBytesCommitter.swift
  - playstead-mac/Playstead/Saves/SaveHistorySheet.swift
  - playstead-mac/Playstead/Saves/SaveOriginNames.swift
  - playstead-mac/Playstead/Saves/SaveSessionCoordinator.swift
  - playstead-mac/Playstead/Saves/SaveSessionRecovery.swift
  - playstead-mac/Playstead/Sync/Outbox.swift
  - playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift
  - playstead-mac/PlaysteadTests/SavesTests/PlayPathSaveWiringTests.swift
  - playstead-mac/PlaysteadTests/SavesTests/SaveHistorySessionBuilderTests.swift
  - playstead-mac/PlaysteadTests/SavesTests/SaveOutboxDrainTriggerTests.swift
  - playstead-mac/PlaysteadTests/SavesTests/SaveSessionRecoveryTests.swift
  - playstead-mac/PlaysteadTests/SavesTests/SaveStoreTests.swift
  - playstead-mac/PlaysteadTests/SnapshotTests/SaveHistoryContractSnapshotTests.swift
  - playstead-mac/PlaysteadTests/SyncTests/JournalRevisionMergeTests.swift
  - playstead-mac/scripts/ci/reachability-allowlist.txt
findings:
  critical: 1
  warning: 2
  info: 1
  total: 4
status: issues_found
---

# Phase 4 Code Review: Gap-Closure Plans 04-21..04-23 (Mac)

**Reviewed:** 2026-09-05
**Depth:** standard
**Files Reviewed:** 20 (21 listed; `reachability-allowlist.txt` is a text manifest, reviewed for content accuracy rather than as source)
**Status:** issues_found

## Summary

This pass focused on reachability/wiring correctness for the three
gap-closure plans (04-21..04-23): `SaveOutboxDrainTrigger`'s three
trigger paths, the shared `SaveCaptureBytesCommitter` ordering
invariant across the live (`SaveSessionCoordinator`) and crash-recovery
(`SaveSessionRecovery`) paths, and the `restored_here_at` migration/
provenance column in `Migrations.swift`/`SaveStore.swift`.

The composition root (`PlaysteadApp.swift`) wires all three
`SaveOutboxDrainTrigger` triggers (post-enqueue, reachability-regained,
scene-active) and the crash-recovery launch task correctly, matching
their doc comments; `AppEnvironment.recoverAbandonedSaveSessionsAtLaunch()`
is idempotent by digest and guarded against re-entry within a launch.
The CAS-before-row ordering invariant holds on both `SaveSessionCoordinator`
and `SaveSessionRecovery`, including on the CAS-commit-throws path (row is
still inserted, failure recorded as a D-31 blockage, never propagated).
Prior reviews' known items (WR-01..WR-06 in `04-REVIEW-mac.md`, CR-01..CR-04
and WR-01..WR-05 in `04-REVIEW-mac2.md`) were checked against current state
and are not re-reported here except where noted.

One genuine concurrency defect was found in `SaveOutboxDrainTrigger.fire()`
that undermines the exact serialization guarantee the type exists to
provide (see CR-01 below) — this is the class of defect the review scope
asked to prioritize ("reentrant drains ... lifecycle/retain issues").
Two lower-severity issues are also reported.

## Critical Issues

### CR-01: `SaveOutboxDrainTrigger.fire()` has a TOCTOU race that lets two concurrently-invoked passes both drain, defeating its documented serialization guarantee

**File:** `playstead-mac/Playstead/Sync/SaveOutboxDrainTrigger.swift:41-61`

**Issue:** The type's own doc comment states its entire reason for existing: *"`fire()` awaits the previously started task before starting the next one ... Without this, two overlapping `fire()` calls could both read `listPending()` before either one's send completed and send the same entry twice."* The implementation does not actually achieve this under concurrent invocation:

```swift
func fire() -> Task<Int, Never> {
    let saveOutbox = self.saveOutbox
    let apiClient = self.apiClient

    lock.lock()
    let previous = _lastTask
    lock.unlock()                      // <-- lock released here

    let task = Task<Int, Never> {
        _ = await previous?.value
        return await saveOutbox.drainOnce(apiClient: apiClient)
    }

    lock.lock()
    _drainCount += 1
    _lastTask = task
    lock.unlock()                      // <-- _lastTask only updated here

    return task
}
```

The read of `_lastTask` into `previous` and the write of the new `_lastTask` happen in two *separate* locked sections. If two threads call `fire()` concurrently — genuinely possible here, since the three production trigger paths run on different threads/queues (`saveOutbox.onEnqueue` fires on whatever thread enqueued, e.g. the main thread from a UI action; `reachability.onChange` fires from `Reachability`'s own monitor queue; `applicationDidBecomeActive()` fires on the main thread from the `scenePhase` observer) — both can read the same stale `previous` before either writes `_lastTask`. Concretely:

1. Thread A calls `fire()`, reads `previous = taskX` (or `nil`), releases the lock.
2. Thread B calls `fire()` before A re-locks, also reads `previous = taskX` (same value — A hasn't written yet).
3. Both A and B construct their own `Task` awaiting the *same* `previous`, then both call `saveOutbox.drainOnce(apiClient:)` concurrently.

`SaveOutbox.drainOnce` (`Sync/Outbox.swift:384-400`) is a plain (non-actor) method with no lock of its own — it reads `listPending()`, sends over the network, then `markDone`/`markFailed`, with no "claim this entry" step comparable to `Outbox.markInFlight`. Two concurrent `drainOnce` calls can both read the same pending entry and both `await apiClient.send(...)` for it before either marks it done — exactly the double-send the type's doc comment says this design prevents. This is a real, provable violation of the documented invariant under a plausible production interleaving (a save resolution enqueued right as reachability flips online, or right as the app becomes active), not merely a theoretical race.

`testTwoOverlappingDrainPassesProduceAtMostOneSuccessfulSend` in `SaveOutboxDrainTriggerTests.swift` does not exercise this: it calls `trigger.fire()` twice synchronously from the same thread, so the two calls execute in strict program order and the lock-protected sections never actually overlap — the test cannot observe the race.

**Fix:** Perform the read of `_lastTask` and the write of the new task inside a single critical section (task *construction* is cheap and does not block, so holding the lock across it is safe):

```swift
func fire() -> Task<Int, Never> {
    let saveOutbox = self.saveOutbox
    let apiClient = self.apiClient

    lock.lock()
    let previous = _lastTask
    let task = Task<Int, Never> {
        _ = await previous?.value
        return await saveOutbox.drainOnce(apiClient: apiClient)
    }
    _drainCount += 1
    _lastTask = task
    lock.unlock()

    return task
}
```

Alternatively, route all `fire()` calls through a private serial `DispatchQueue` so the read-modify-write is atomic by construction. Either fix should be paired with a test that actually drives `fire()` from two different `DispatchQueue`s (or a `Task.detached` pair racing via a barrier) to prove the overlap is closed, since the existing single-thread test gives false confidence.

## Warnings

### WR-01: `SaveCaptureBytesCommitter`'s staged file path is keyed only by digest, so two concurrent captures with identical bytes race on the same staging file across unrelated save lines

**File:** `playstead-mac/Playstead/Saves/SaveCaptureBytesCommitter.swift:41-56`

**Issue:** The staging path is derived purely from `capture.sha256`:

```swift
let staged = try casManager.paths
    .partialURL(for: capture.sha256)
    .appendingPathExtension("save-stage")
...
try? fm.removeItem(at: staged)
try fm.copyItem(at: source, to: staged)
```

`SaveSessionCoordinator` is a per-launch actor (a fresh instance per `GameRowView.play()` call, per `AppEnvironment.makeSaveSessionCoordinator()`'s own doc comment), and `SaveSessionRecovery` is a separate actor entirely. Nothing serializes calls to `SaveCaptureBytesCommitter.commit(_:)` across two different `SaveSessionCoordinator` instances (e.g. two games played concurrently in two windows/rows) or between a live coordinator and a concurrently-running recovery replay for a *different* line. If two such captures happen to produce byte-identical content (plausible for freshly-initialized/all-zero battery saves of the same size, which is exactly the case content-addressing is designed to de-duplicate), both resolve to the same `staged` path and interleave `removeItem`/`copyItem`/`commit(partialAt:)` against that one file. Because a matching digest guarantees the underlying bytes are identical, this should not corrupt what's recorded under that digest, but it can produce spurious CAS-commit failures (recorded as a D-31 blockage) purely from the race, not from an actual problem with either capture — degrading a legitimate zero-loss capture into a needless "capture blocked" alert.

**Fix:** Make the staging filename unique per call (e.g. include a UUID or the caller's session id in the staged filename, and only the final `commit(partialAt:sha256:)` step need be digest-keyed), so two concurrent commits of the same digest never share a mutable file path:

```swift
let staged = try casManager.paths
    .partialURL(for: capture.sha256)
    .appendingPathExtension("\(UUID().uuidString).save-stage")
```

### WR-02: `GameRowView.buildSaveLaunchPlan` still constructs its own ad hoc `SaveStore` instead of `environment.saveStore`

**File:** `playstead-mac/Playstead/Library/GameRowView.swift:468-469`

**Issue:** This is the same defect `04-REVIEW-mac2.md` WR-05 already flagged ("`GameRowView.swift` constructs its own ad hoc `SaveStore`, bypassing the 'one shared store' rule"), and it is still present on the restore-plan half of the Play path:

```swift
let contextBuilder = LaunchSaveContextBuilder(
    saveStore: SaveStore(localStore: environment.localStore),
    ...
)
```

`SaveStore` happens to be a stateless wrapper (no cached state, every call re-reads/writes `localStore.connection`), so this does not currently cause an observable divergence — but it is a repeated violation of the "single shared store" composition rule this codebase otherwise enforces everywhere else in `AppEnvironment`, and it means a future `SaveStore` that adds any in-memory caching or per-instance state would silently desync this call site from `environment.saveStore`. Flagged again here (not newly discovered) because it is directly adjacent to this review's focus area and remains unresolved.

**Fix:** Pass `environment.saveStore` directly instead of constructing a second instance.

## Info

### IN-01: `ReadinessSheetView`'s `onReviewSaveVersions` is invoked after `apply(_:)` has already mutated `showsSaveHistory`/`showsConflictComparison`, but is otherwise a no-op default (`{}`) at every call site

**File:** `playstead-mac/Playstead/Readiness/ReadinessSheetView.swift:23, 183-194`

**Issue:** `apply(_:)`'s `.reviewSaveVersions` branch calls `onReviewSaveVersions()` after deciding which sheet to open, but neither production call site (`GameRowView.swift:130-150`, `LibraryShellView.swift:149-162`) ever supplies a non-default value — the property exists purely as an untested extension seam right now. Not a defect (the doc comment is honest that it is "navigational only"), but worth noting since an unused callback parameter is easy to assume is wired to something when reading the call site in isolation.

**Fix:** No action required; consider removing the parameter until a caller needs it, or adding a one-line comment at the declaration noting no production caller currently supplies a value.

---

_Reviewed: 2026-09-05_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
