---
phase: 03-mac-offline-play-vertical-slice
reviewed: 2026-08-30T00:00:00Z
depth: standard
files_reviewed: 32
files_reviewed_list:
  - playstead-mac/Playstead/Cache/CASManager.swift
  - playstead-mac/Playstead/Cache/DownloadEngine.swift
  - playstead-mac/Playstead/Cache/DownloadQueue.swift
  - playstead-mac/Playstead/Cache/DownloadCoordinator.swift
  - playstead-mac/Playstead/Cache/EvictionPlanner.swift
  - playstead-mac/Playstead/Cache/QuotaManager.swift
  - playstead-mac/Playstead/Cache/PinStore.swift
  - playstead-mac/Playstead/Cache/LaunchMaterializer.swift
  - playstead-mac/Playstead/Cache/AvailabilityState.swift
  - playstead-mac/Playstead/Cache/PreflightChecker.swift
  - playstead-mac/Playstead/Cache/Reachability.swift
  - playstead-mac/Playstead/Cache/StreamingSHA256.swift
  - playstead-mac/Playstead/App/AppPaths.swift
  - playstead-mac/Playstead/App/Playstead.entitlements
  - playstead-mac/Playstead/Persistence/SQLiteConnection.swift
  - playstead-mac/Playstead/Persistence/CatalogueStore.swift
  - playstead-mac/Playstead/Persistence/CurationStore.swift
  - playstead-mac/Playstead/Persistence/Migrations.swift
  - playstead-mac/Playstead/Net/APIClient.swift
  - playstead-mac/Playstead/Net/KeychainStore.swift
  - playstead-mac/Playstead/Net/SnapshotClient.swift
  - playstead-mac/Playstead/Sync/SyncEngine.swift
  - playstead-mac/Playstead/Sync/JournalApplier.swift
  - playstead-mac/Playstead/Sync/Outbox.swift
  - playstead-mac/Playstead/Sync/OutboxWorker.swift
  - playstead-mac/Playstead/Sync/ChangesClient.swift
  - playstead-mac/Playstead/Sync/CursorStore.swift
  - playstead-mac/Playstead/Curation/PlaySessionRecorder.swift
  - playstead-mac/Playstead/Curation/FractionalPosition.swift
  - playstead-mac/Playstead/Adapter/AdapterInstaller.swift
  - playstead-mac/Playstead/Adapter/AdapterHost.swift
  - playstead-mac/Playstead/Adapter/BiosStore.swift
  - playstead-mac/Playstead/Library/GameRowView.swift
  - playstead-server/lib/playstead/blobs/store/local_disk.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex
  - playstead-server/lib/playstead_web/router.ex
  - playstead-server/lib/playstead/curation.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/play_sessions_controller.ex
  - playstead-server/lib/playstead/sync/curation_payload.ex
  - playstead-server/lib/playstead/curation/position.ex
findings:
  critical: 2
  warning: 4
  info: 1
  total: 7
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-08-30T00:00:00Z
**Depth:** standard
**Files Reviewed:** 32 (of 184 in scope; prioritized production Swift client and Elixir server sources over tests/docs/scripts per review scope notes)
**Status:** issues_found

## Summary

Reviewed the Mac offline-play vertical slice: the Swift sync engine, content-addressed cache, download queue/coordinator, curation outbox, adapter install/launch, and the Elixir server's blob-serving and curation endpoints. Most of the reviewed code is careful and well-reasoned — parameterized SQL throughout, ownership checks on every curation mutation, atomic commit/quarantine discipline in the CAS, and a solid Range/If-Range/ETag contract on the server's blob endpoint.

However, two related **path-traversal** defects were found in the client's trust boundary between "server-declared strings" and "local filesystem paths." Both stem from the same root cause: catalogue-member fields (`sha256`, `name`) arrive from the paired server's JSON responses and are used directly as path components with no format validation, in an app that explicitly ships **without App Sandbox** (see `Playstead.entitlements`). A compromised or spoofed server (or a MITM that defeats/precedes certificate pinning, which is itself optional in this tracer plan per `APIClient`'s own doc comment) can therefore write attacker-chosen bytes to an attacker-chosen path anywhere the logged-in user can write — well outside the app's own cache directory.

Also flagged: an outbox worker liveness gap when SQLite writes intermittently fail, and an unbounded digest-mismatch retry loop with no user-facing "give up" state.

## Critical Issues

### CR-01: Path traversal via unvalidated catalogue member filename in LaunchMaterializer

**File:** `playstead-mac/Playstead/Cache/LaunchMaterializer.swift:49` (destination construction), reached from `playstead-mac/Playstead/Library/GameRowView.swift:118-124`

**Issue:** `LaunchMaterializer.materialize(assetSetID:members:)` builds each materialized file's destination as:

```swift
let destination = directory.appendingPathComponent(member.declaredName)
```

`member.declaredName` is `AssetMember.name` (`playstead-mac/Playstead/Net/SnapshotClient.swift:6-13`), an optional `String` decoded verbatim from the server's `/api/v1/snapshot` and `/api/v1/changes` JSON with **zero validation** — no check that it is a bare filename, no rejection of `/` or `..` path components. `GameRowView.play()` passes `entry.members` straight through (`member.name` → `declaredName`) with no sanitization at the call site either.

`appendingPathComponent` on a string containing `../../../` segments resolves upward out of `launch/<asset_set_id>/`. Combined with `FileManager.copyItem(at:to:)` writing the *contents of a verified cache object* to that resolved destination, a malicious or compromised paired server can cause the client to copy arbitrary (attacker-supplied, digest-verified-against-itself) file content to an arbitrary path the user can write to — e.g. `~/Library/LaunchAgents/com.evil.plist`, `~/.zshrc`, or any dotfile that executes on next login/shell start.

This is materially worse than a typical sandboxed-app bug because `Playstead.entitlements` explicitly sets `com.apple.security.app-sandbox` to `false` (documented as intentional, to allow launching a child emulator process) — there is no OS-level containment backstop for this write.

**Fix:** Reject or strip any `declaredName` that is not a single path component before it ever reaches `appendingPathComponent`:

```swift
private func safeFilename(_ declaredName: String) -> String? {
    let component = (declaredName as NSString).lastPathComponent
    guard component == declaredName,           // no directory separators
          component != "..", component != ".", // no traversal/self tokens
          !component.isEmpty
    else { return nil }
    return component
}

// in materialize(...):
guard let safeName = safeFilename(member.declaredName) else {
    throw MaterializationError.invalidDeclaredName(member.declaredName)
}
let destination = directory.appendingPathComponent(safeName)
```

Apply the same guard wherever else a server-declared member name is used to construct a filesystem path.

---

### CR-02: Unvalidated server-supplied `sha256` used directly as a filesystem path component

**File:** `playstead-mac/Playstead/App/AppPaths.swift:60-69` (`objectURL(for:)`, `partialURL(for:)`), consumed by `playstead-mac/Playstead/Cache/CASManager.swift:33-67` and `playstead-mac/Playstead/Cache/DownloadEngine.swift:149,219`

**Issue:** `AppPaths.objectURL(for: sha256)` and `partialURL(for: sha256)` splice the `sha256` string directly into path components with no validation that it is a well-formed 64-character lowercase hex digest:

```swift
func objectURL(for sha256: String) -> URL {
    let a = String(sha256.prefix(2))
    let b = String(sha256.dropFirst(2).prefix(2))
    return objects.appendingPathComponent(a).appendingPathComponent(b).appendingPathComponent(sha256)
}
func partialURL(for sha256: String) -> URL {
    partials.appendingPathComponent(sha256)
}
```

`sha256` originates from `AssetMember.sha256` (`SnapshotClient.swift:6-13`), decoded directly from the server's catalogue JSON with no format check, and flows unmodified through `CatalogueStore`, `DownloadQueue`, `DownloadCoordinator`, and into `DownloadEngine.download(sha256:...)` and `CASManager.commit(partialAt:sha256:)`. `CASManager.commit` then does:

```swift
try fm.moveItem(at: partialURL, to: dest)
```

If `sha256` contains `../` sequences (e.g. `"../../../../Library/LaunchAgents/evil"`), `dest` resolves outside `objects/`, and the downloaded (server-controlled) payload — which is only checked to hash to *that same attacker-chosen string*, so the digest check provides no real integrity backstop here — gets moved to an attacker-chosen path. The same applies to `partialURL(for:)`, which uses the raw string as a single path component with no traversal guard at all, and to `LaunchMaterializer`'s use of `cas.objectURL(for: member.sha256)` as a copy source.

This requires a compromised/malicious paired server (or a successful MITM, since certificate pinning is optional/best-effort in this tracer plan per `APIClient`'s own doc comment), but given that trust boundary is already crossed, the impact is the same class of arbitrary-file-write as CR-01, and the two should be fixed together.

**Fix:** Validate the digest format once, centrally, before it is ever used as a path component:

```swift
private static let hexDigestPattern = try! NSRegularExpression(pattern: "^[0-9a-f]{64}$")

func objectURL(for sha256: String) -> URL? {
    guard isValidDigest(sha256) else { return nil }
    let a = String(sha256.prefix(2))
    let b = String(sha256.dropFirst(2).prefix(2))
    return objects.appendingPathComponent(a).appendingPathComponent(b).appendingPathComponent(sha256)
}
```

and reject/quarantine any manifest member or download request whose `sha256` fails that check at decode/ingest time (e.g. in `CatalogueStore.upsert` or `AssetMember`'s decoding), so the invalid value never reaches the cache layer at all.

## Warnings

### WR-01: `OutboxWorker.drainOnce()` silently skips an entry on a local SQLite write failure, breaking its own ordering guarantee

**File:** `playstead-mac/Playstead/Sync/OutboxWorker.swift:60-64`

**Issue:** The module's own doc comment states drain must "stop at the first entry that must retry (rather than sending a later entry out of order while an earlier one is still outstanding)." But if `outbox.markInFlight(entry.id)` throws (a real possibility — `Outbox.markInFlight` swallows nothing, but the underlying `SQLiteConnection.execute` can throw on a busy/locked database), the loop does:

```swift
do {
    try outbox.markInFlight(entry.id)
} catch {
    continue
}
```

`continue` moves on to the *next* pending entry rather than stopping — so a later entry can be sent ahead of an earlier one that failed only to mark itself in-flight, violating the ordering invariant this type exists to guarantee, and the failed entry is left `pending` forever with no attempt-count increment or visible error.

**Fix:** Treat a local persistence failure the same as a transport failure — stop draining rather than skipping ahead:

```swift
do {
    try outbox.markInFlight(entry.id)
} catch {
    result.stoppedForRetry = true
    return result
}
```

### WR-02: Digest-mismatch downloads retry unboundedly with no terminal "give up" state

**File:** `playstead-mac/Playstead/Cache/DownloadCoordinator.swift:235-243`, `playstead-mac/Playstead/Cache/DownloadQueue.swift` (`incrementAttempt`/`attemptCount`)

**Issue:** `handleDownloadError` increments `attemptCount` and unconditionally calls `queue.resume(id:)` on every digest mismatch, forever:

```swift
try? queue.incrementAttempt(id: item.id)
try? queue.resume(id: item.id)
emit(.digestMismatchRequeued(itemID: item.id, assetSetID: item.assetSetID, sha256: item.sha256, attempt: item.attemptCount + 1))
```

`attemptCount` is tracked and surfaced in the event, but nothing ever reads it to stop retrying. If a manifest member's declared `sha256` can never actually be produced by the bytes the server serves at that URL (a genuinely corrupt/mismatched catalogue entry), this item retries indefinitely, consuming bandwidth and keeping the scheduler loop permanently busy with the same doomed item ahead of anything else at the same queue position.

**Fix:** Add a bounded attempt cap (e.g. via a `maxDigestMismatchAttempts` policy) that transitions the item to a distinct terminal/paused state and emits a "needs attention" event instead of silently resuming forever.

### WR-03: `AppPaths.excludeRootFromBackup` and directory creation failures are silently swallowed

**File:** `playstead-mac/Playstead/App/AppPaths.swift:41-56`

**Issue:** Both `createDirectoriesIfNeeded` and `excludeRootFromBackup` use `try?`, discarding any error. If cache-directory creation fails at launch (e.g. disk full, permissions), every subsequent `CASManager`/`DownloadEngine` operation that assumes these directories exist will fail with a generic, hard-to-diagnose "file not found"-shaped error rather than the actual root cause, and the "exclude from Time Machine" promise this type's own doc comment makes (`D-20`) can silently not hold with no observable signal anywhere.

**Fix:** At minimum, log the failure (even without throwing, to preserve the constructor's non-throwing shape), or surface it through a diagnosable state (`ReadinessEngine`) rather than losing it entirely.

### WR-04: `CASManager.commit` swallows a failed cleanup of a duplicate partial

**File:** `playstead-mac/Playstead/Cache/CASManager.swift:55-58`

**Issue:** When a committed object already exists at `dest`, the redundant partial is discarded via `try? fm.removeItem(at: partialURL)`. If that removal fails (permissions, file locked by another process), the stray file is left under `partials/` indefinitely with no record of it — it will never appear in `EvictionPlanner.quarantinedPartials()` (which only scans `partials/quarantine/`) and nothing else in this phase's code ever revisits `partials/` for orphaned files, so it silently occupies disk space forever.

**Fix:** Log the removal failure, or route it to `quarantine(partialAt:reason:)` instead of `try?`-and-forget, so an orphaned partial is at least discoverable.

## Info

### IN-01: `EvictionPlanner.removeQuarantined(atPath:)` accepts an arbitrary `path: String` rather than a scoped identifier

**File:** `playstead-mac/Playstead/Cache/EvictionPlanner.swift:165-168`

**Issue:** `removeQuarantined(atPath: String)` calls `FileManager.default.removeItem(atPath: path)` on whatever path string it's given, with no check that `path` actually lives under `paths.partials/quarantine/`. Every current caller sources `path` from `quarantinedPartials()`'s own directory listing, so this isn't exploitable today, but the API shape itself doesn't enforce that invariant — a future caller (or a UI regression that lets a path slip through unfiltered) could delete an arbitrary file the app process has permission to remove.

**Fix:** Accept a filename/identifier scoped to the quarantine directory (or re-derive and validate the path is a descendant of `paths.partials.appendingPathComponent("quarantine")` before deleting) rather than a free-form absolute path string.

---

_Reviewed: 2026-08-30T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
