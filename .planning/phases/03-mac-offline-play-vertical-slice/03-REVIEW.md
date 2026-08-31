---
phase: 03-mac-offline-play-vertical-slice
reviewed: 2026-08-30
depth: standard
scope_source: SUMMARY.md + git-diff cross-check
diff_base: c90348e6b5b8c0a202b3e696bb106a0b97b496d1^
partitions: 6
files_reviewed: 184
findings:
  critical: 14
  warning: 33
  info: 12
  total: 59
review_completeness: amended — see 'Findings this review initially missed'
status: issues_found
files_reviewed_list:
  - playstead-mac/.gitignore
  - playstead-mac/Playstead.xcodeproj/project.pbxproj
  - playstead-mac/Playstead/Adapter/AdapterCapabilityCard.swift
  - playstead-mac/Playstead/Adapter/AdapterCatalog.swift
  - playstead-mac/Playstead/Adapter/AdapterExit.swift
  - playstead-mac/Playstead/Adapter/AdapterHost.swift
  - playstead-mac/Playstead/Adapter/AdapterInstaller.swift
  - playstead-mac/Playstead/Adapter/AdapterPin.json
  - playstead-mac/Playstead/Adapter/AdapterPin.swift
  - playstead-mac/Playstead/Adapter/BiosDropTarget.swift
  - playstead-mac/Playstead/Adapter/BiosStore.swift
  - playstead-mac/Playstead/App/AppPaths.swift
  - playstead-mac/Playstead/App/Info.plist
  - playstead-mac/Playstead/App/Playstead.entitlements
  - playstead-mac/Playstead/App/PlaysteadApp.swift
  - playstead-mac/Playstead/Cache/AvailabilityState.swift
  - playstead-mac/Playstead/Cache/CASManager.swift
  - playstead-mac/Playstead/Cache/DownloadCoordinator.swift
  - playstead-mac/Playstead/Cache/DownloadEngine.swift
  - playstead-mac/Playstead/Cache/DownloadQueue.swift
  - playstead-mac/Playstead/Cache/EvictionPlanner.swift
  - playstead-mac/Playstead/Cache/LaunchMaterializer.swift
  - playstead-mac/Playstead/Cache/PinStore.swift
  - playstead-mac/Playstead/Cache/PreflightChecker.swift
  - playstead-mac/Playstead/Cache/QuotaManager.swift
  - playstead-mac/Playstead/Cache/Reachability.swift
  - playstead-mac/Playstead/Cache/StreamingSHA256.swift
  - playstead-mac/Playstead/Controller/ControllerHost.swift
  - playstead-mac/Playstead/Controller/ControllerMapping.swift
  - playstead-mac/Playstead/Controller/ControllerMappingStore.swift
  - playstead-mac/Playstead/Controller/ControllerRecoveryBanner.swift
  - playstead-mac/Playstead/Controller/ControllerSettingsView.swift
  - playstead-mac/Playstead/Controller/ControllerTestView.swift
  - playstead-mac/Playstead/Curation/CollectionDetailView.swift
  - playstead-mac/Playstead/Curation/CollectionsView.swift
  - playstead-mac/Playstead/Curation/CollectionsViewModel.swift
  - playstead-mac/Playstead/Curation/ContinueShelfView.swift
  - playstead-mac/Playstead/Curation/ContinueViewModel.swift
  - playstead-mac/Playstead/Curation/FavoritesShelfView.swift
  - playstead-mac/Playstead/Curation/FavoritesViewModel.swift
  - playstead-mac/Playstead/Curation/FractionalPosition.swift
  - playstead-mac/Playstead/Curation/PlaySessionRecorder.swift
  - playstead-mac/Playstead/Curation/QueueShelfView.swift
  - playstead-mac/Playstead/Curation/QueueViewModel.swift
  - playstead-mac/Playstead/Curation/RecentShelfView.swift
  - playstead-mac/Playstead/Curation/RecentViewModel.swift
  - playstead-mac/Playstead/Design/DesignTokens.swift
  - playstead-mac/Playstead/Design/MotionPreference.swift
  - playstead-mac/Playstead/Design/StatusToken.swift
  - playstead-mac/Playstead/Design/SystemAccent.swift
  - playstead-mac/Playstead/Library/DownloadsView.swift
  - playstead-mac/Playstead/Library/FilterChipRow.swift
  - playstead-mac/Playstead/Library/FirstRunBanner.swift
  - playstead-mac/Playstead/Library/GameCardView.swift
  - playstead-mac/Playstead/Library/GameListView.swift
  - playstead-mac/Playstead/Library/GameRowView.swift
  - playstead-mac/Playstead/Library/LibraryShellView.swift
  - playstead-mac/Playstead/Library/LibraryViewModel.swift
  - playstead-mac/Playstead/Library/QuotaSettingsView.swift
  - playstead-mac/Playstead/Library/ReclaimPromptView.swift
  - playstead-mac/Playstead/Library/SearchField.swift
  - playstead-mac/Playstead/Library/ShelfView.swift
  - playstead-mac/Playstead/Library/ShowAllSystemsControl.swift
  - playstead-mac/Playstead/Library/SidebarView.swift
  - playstead-mac/Playstead/Library/StatusSlotView.swift
  - playstead-mac/Playstead/Library/StorageView.swift
  - playstead-mac/Playstead/Library/SystemMonogramView.swift
  - playstead-mac/Playstead/Net/APIClient.swift
  - playstead-mac/Playstead/Net/KeychainStore.swift
  - playstead-mac/Playstead/Net/SnapshotClient.swift
  - playstead-mac/Playstead/Persistence/CatalogueStore.swift
  - playstead-mac/Playstead/Persistence/CurationStore.swift
  - playstead-mac/Playstead/Persistence/LocalStore.swift
  - playstead-mac/Playstead/Persistence/Migrations.swift
  - playstead-mac/Playstead/Persistence/SQLiteConnection.swift
  - playstead-mac/Playstead/Readiness/ReadinessCheck.swift
  - playstead-mac/Playstead/Readiness/ReadinessEngine.swift
  - playstead-mac/Playstead/Readiness/ReadinessReportView.swift
  - playstead-mac/Playstead/Readiness/Remedy.swift
  - playstead-mac/Playstead/Sync/ChangesClient.swift
  - playstead-mac/Playstead/Sync/CurationIntent.swift
  - playstead-mac/Playstead/Sync/CursorStore.swift
  - playstead-mac/Playstead/Sync/JournalApplier.swift
  - playstead-mac/Playstead/Sync/Outbox.swift
  - playstead-mac/Playstead/Sync/OutboxWorker.swift
  - playstead-mac/Playstead/Sync/SyncEngine.swift
  - playstead-mac/PlaysteadTests/AccessibilityTests/AccessibilityAuditTests.swift
  - playstead-mac/PlaysteadTests/AdapterTests/AdapterPinTests.swift
  - playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift
  - playstead-mac/PlaysteadTests/AdapterTests/InstallerTests.swift
  - playstead-mac/PlaysteadTests/AdapterTests/RelaunchTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/AvailabilityStateTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/DownloadResumeTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/EvictionTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/MaterializationTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/QueueTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/QuotaTests.swift
  - playstead-mac/PlaysteadTests/CacheTests/StubURLProtocol.swift
  - playstead-mac/PlaysteadTests/ControllerTests/ControllerHostTests.swift
  - playstead-mac/PlaysteadTests/CurationTests/OrderingTests.swift
  - playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift
  - playstead-mac/PlaysteadTests/CurationTests/PlaySessionTests.swift
  - playstead-mac/PlaysteadTests/LibraryTests/FilterTests.swift
  - playstead-mac/PlaysteadTests/LibraryTests/StatusLadderTests.swift
  - playstead-mac/PlaysteadTests/ReadinessTests/ReadinessEngineTests.swift
  - playstead-mac/PlaysteadTests/SnapshotDecodeTests.swift
  - playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift
  - playstead-mac/README.md
  - playstead-mac/docs/ACCESSIBILITY.md
  - playstead-mac/docs/RELEASE.md
  - playstead-mac/docs/SUPPORT-MATRIX.md
  - playstead-mac/scripts/build-release.sh
  - playstead-mac/scripts/sign-and-notarize.sh
  - playstead-mac/spike/.gitignore
  - playstead-mac/spike/README.md
  - playstead-mac/spike/SpikeHost/Info.plist
  - playstead-mac/spike/SpikeHost/Package.swift
  - playstead-mac/spike/SpikeHost/Sources/SpikeHost/AdapterProbeHost.swift
  - playstead-mac/spike/SpikeHost/Sources/SpikeHost/KeychainProbe.swift
  - playstead-mac/spike/SpikeHost/Sources/SpikeHost/main.swift
  - playstead-mac/spike/SpikeHost/SpikeHost.entitlements
  - playstead-mac/spike/scripts/acquire-emulator.sh
  - playstead-mac/spike/scripts/run-probes.sh
  - playstead-mac/spike/scripts/sign-and-notarize.sh
  - playstead-mac/spike/scripts/watch-save.sh
  - playstead-mac/spike/testrom/.gitignore
  - playstead-mac/spike/testrom/build.sh
  - playstead-mac/spike/testrom/crt0.s
  - playstead-mac/spike/testrom/fix-header.py
  - playstead-mac/spike/testrom/linker.ld
  - playstead-mac/spike/testrom/main.c
  - playstead-mac/spike/testrom/savetest.gba
  - playstead-server/assets/css/app.css
  - playstead-server/lib/playstead/blobs.ex
  - playstead-server/lib/playstead/blobs/store.ex
  - playstead-server/lib/playstead/blobs/store/local_disk.ex
  - playstead-server/lib/playstead/curation.ex
  - playstead-server/lib/playstead/curation/collection.ex
  - playstead-server/lib/playstead/curation/collection_member.ex
  - playstead-server/lib/playstead/curation/continue_dismissal.ex
  - playstead-server/lib/playstead/curation/favorite.ex
  - playstead-server/lib/playstead/curation/play_session.ex
  - playstead-server/lib/playstead/curation/position.ex
  - playstead-server/lib/playstead/curation/queue_item.ex
  - playstead-server/lib/playstead/protocol/capabilities.ex
  - playstead-server/lib/playstead/sync/curation_payload.ex
  - playstead-server/lib/playstead/sync/entity_kind.ex
  - playstead-server/lib/playstead/sync/snapshot.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/play_sessions_controller.ex
  - playstead-server/lib/playstead_web/controllers/api/v1/snapshot_controller.ex
  - playstead-server/lib/playstead_web/endpoint.ex
  - playstead-server/lib/playstead_web/error_codes.ex
  - playstead-server/lib/playstead_web/live/collections_live.ex
  - playstead-server/lib/playstead_web/live/library_live.ex
  - playstead-server/lib/playstead_web/live/library_live/game_card.ex
  - playstead-server/lib/playstead_web/live/library_live/shelves.ex
  - playstead-server/lib/playstead_web/live/library_live/sidebar.ex
  - playstead-server/lib/playstead_web/live/library_live/status_slot.ex
  - playstead-server/lib/playstead_web/router.ex
  - playstead-server/priv/repo/migrations/20260830000000_create_curation_favorites.exs
  - playstead-server/priv/repo/migrations/20260830000001_create_curation_ordered_lists.exs
  - playstead-server/priv/repo/migrations/20260830000002_create_curation_play_sessions_and_dismissals.exs
  - playstead-server/test/playstead/blobs/store/local_disk_test.exs
  - playstead-server/test/playstead/curation/collections_test.exs
  - playstead-server/test/playstead/curation/continue_test.exs
  - playstead-server/test/playstead/curation/favorites_test.exs
  - playstead-server/test/playstead/curation/position_test.exs
  - playstead-server/test/playstead/curation/queue_test.exs
  - playstead-server/test/playstead/import/session_worker_test.exs
  - playstead-server/test/playstead/protocol/negotiation_test.exs
  - playstead-server/test/playstead/sync/change_journal_test.exs
  - playstead-server/test/playstead/sync/snapshot_test.exs
  - playstead-server/test/playstead_web/browser/coherence_test.exs
  - playstead-server/test/playstead_web/browser/palette_test.exs
  - playstead-server/test/playstead_web/controllers/api/v1/blobs_controller_test.exs
  - playstead-server/test/playstead_web/controllers/api/v1/capabilities_controller_test.exs
  - playstead-server/test/playstead_web/controllers/api/v1/curation_controller_test.exs
  - playstead-server/test/playstead_web/controllers/api/v1/play_sessions_controller_test.exs
  - playstead-server/test/playstead_web/live/collections_live_test.exs
  - playstead-server/test/playstead_web/live/library_live_test.exs
  - playstead-server/test/support/browser_screens.ex
  - playstead-server/test/support/fixtures/catalogue_fixtures.ex
---

# Phase 03 Code Review — Mac Offline Play Vertical Slice

Depth `standard`. Scope of 184 changed files exceeded the single-agent threshold, so the
review ran as six partitioned reviewers whose reports are merged below. Finding IDs are
prefixed `P1-`..`P6-` by partition and are unique across the whole report.

| Partition | Area | Files | Crit | Warn | Info |
|---|---|---:|---:|---:|---:|
| P1 | mac Cache / Net / Persistence | 20 | 3 | 5 | 3 |
| P2 | mac Adapter / Controller / Readiness / release scripts | 25 | 3 | 5 | 2 |
| P3 | mac Library / Curation / Design (UI) | 34 | 1 | 6 | 2 |
| P4 | mac Sync + XCTest suite | 28 | 3 | 7 | 2 |
| P5 | server lib (contexts, controllers, LiveViews, router) | 28 | 1 | 5 | 2 |
| P6 | server tests + migrations, spike toolchain, docs | 49 | 1 | 5 | 1 |
| **Total** | | **184** | **12** | **33** | **12** |

## ⚠ Findings this review initially missed

This report was regenerated on 2026-08-31 by six partitioned reviewers, overwriting the
previous `03-REVIEW.md` (commit `f12e4c4`). **Two CRITICAL path-traversal findings from that
earlier review were not re-discovered by any partition, and the overwrite removed the only
record of them.** They were recovered from git and are restored below. Both were confirmed
still live in the source at the time of recovery — the re-review's silence was a false
negative, not evidence of a fix.

Root cause of the miss: the partitioned reviewers were each given a directory slice and
asked to look for defects within it. CR-01/CR-02 are a *data-flow* defect — a server-supplied
string crossing from `Net/` (partition 1) into `Cache/` and `App/` path construction
(partitions 1 and 2) — and no single partition's prompt framed the trust boundary that makes
it critical. Partition-scoped review is structurally weak at cross-cutting taint flows.
Treat that as a known limitation of this report, not just of these two findings.

Both are now FIXED in commit `56781ec` (validation at ingest in `SnapshotClient`/`CatalogueStore`
plus throwing, allowlist-validated path accessors in `App/PathSafety.swift`), with 16
regression tests in `PlaysteadTests/SecurityTests/PathTraversalTests.swift` that assert on
filesystem outcome rather than return values.

### P0-CR-001 (was CR-01): Path traversal via unvalidated catalogue member filename

`Cache/LaunchMaterializer.swift:49` built its destination as
`directory.appendingPathComponent(member.declaredName)`, where `declaredName` is
`AssetMember.name` decoded verbatim from `/api/v1/snapshot` and `/api/v1/changes` with no
bare-filename check. `FileManager.copyItem` then wrote verified cache content to the resolved
path, so a compromised or spoofed paired server could write attacker-chosen bytes to an
attacker-chosen path (`~/Library/LaunchAgents/…`, `~/.zshrc`, any login-executed dotfile).
Materially worse than usual because `Playstead.entitlements` intentionally sets
`com.apple.security.app-sandbox` to `false`, so there is no OS containment backstop.

### P0-CR-002 (was CR-02): Unvalidated server-supplied `sha256` as a path component

`App/AppPaths.swift`'s `objectURL(for:)` / `partialURL(for:)` spliced the server-supplied
`sha256` straight into path components with no hex-digest format check, reached from
`CASManager`, `DownloadEngine`, `PreflightChecker`, `ReadinessEngine`, and
`LaunchMaterializer`. The digest check provides no integrity backstop here, because the
payload is only verified to hash to that same attacker-chosen string. Same arbitrary-file-write
class as P0-CR-001.

---

## Critical findings at a glance

- **P0-CR-001** Server-declared member filename spliced into a launch path — arbitrary file write (missed by this review; recovered, now fixed).
- **P0-CR-002** Server-declared `sha256` spliced into cache paths — same class (missed by this review; recovered, now fixed).
- **P1-CR-001** `DownloadCoordinator` retries permanently-failing downloads with no backoff or attempt cap.
- **P1-CR-002** `EvictionPlanner.execute` deletes CAS file and DB row non-atomically — crash leaves a false `verifiedLocal`.
- **P1-CR-003** Device-paired bearer token stored `AfterFirstUnlock` (not `...ThisDeviceOnly`) — syncs via iCloud Keychain.
- **P2-CR-001** `AdapterHost.verifyInstalledDigest()` never re-hashes the binary before launch, contrary to its own contract.
- **P2-CR-002** A validated BIOS is never passed into the emulator launch arguments, while the UI claims it is in use.
- **P2-CR-003** `refreshActiveControllerMapping()` has no production call site — controller remaps never reach the emulator.
- **P3-CR-001** `FractionalPosition.midpoint` infinite-loops on equal neighbour positions, on the main thread during drag-drop.
- **P4-CR-001** `CurationIntent.idempotencyKey` keys on row id only — distinct mutations collide and can be silently dropped.
- **P4-CR-002** `revertOptimistic` is a no-op for delete-shaped intents — a rejected delete tombstones the row forever.
- **P4-CR-003** Documented outbox backoff does not exist: `attemptCount` is written but never read; no cap, no quarantine.
- **P5-CR-001** `Position.between/2` infinite-loops on equal/misordered bounds, reachable from an unvalidated PATCH endpoint, inside an open transaction.
- **P6-CR-001** `acquire-emulator.sh` computes but never compares the download SHA-256, despite docs pinning an expected digest.

---

# Partition P1 — mac Cache / Net / Persistence


# Phase 03: Code Review Report (Partition: mac-cache-net-persistence)

**Reviewed:** 2026-08-30
**Depth:** standard
**Files Reviewed:** 19 (see `files_reviewed_list`)
**Status:** issues_found

## Summary

This partition covers the download/cache pipeline (CASManager, DownloadEngine,
DownloadCoordinator, DownloadQueue, EvictionPlanner, PreflightChecker,
QuotaManager, LaunchMaterializer, Reachability, StreamingSHA256), the
availability-derivation type, and the persistence/network layers (SQLite
wrapper, LocalStore/CatalogueStore/CurationStore/Migrations, APIClient,
KeychainStore, SnapshotClient).

Most of the code is careful and well-commented, and several of the harder
correctness properties (resumable range decisions, fractional indexing,
idempotent upserts, parameterized SQL) are implemented correctly. However,
three defects break invariants the code's own documentation calls load-
bearing: an unbounded, backoff-free retry loop for permanent download
failures; a non-atomic two-step object/row deletion that can leave a
"verified" badge pointing at bytes that no longer exist (the exact failure
mode D-21 says this product cannot afford); and a Keychain accessibility
setting that lets a device-scoped bearer token migrate off the paired device
via iCloud Keychain sync, undermining the device-pairing security model
described in the same file's comments.

## Critical Issues

### P1-CR-001: Unbounded, backoff-free retry loop for permanent download failures

**File:** `playstead-mac/Playstead/Cache/DownloadCoordinator.swift:235-243`
**Issue:**
`DownloadEngine.download` only applies exponential backoff (via `sleeper`) to
transport-level `URLError`s (`DownloadEngine.swift:127-144`). Any other
failure — `DownloadError.invalidResponse` (thrown at
`DownloadEngine.swift:176` for a non-HTTP response, and again at
`DownloadEngine.swift:208-210` for any non-200 status on a fresh request,
e.g. a 404/500 from a bad or expired blob URL) or `DownloadError.transport`
(thrown at `DownloadEngine.swift:172` for a non-`URLError` thrown by
`session.bytes(for:)`) — propagates up to
`DownloadCoordinator.runDownload` and is handled by `handleDownloadError`:

```swift
private func handleDownloadError(_ item: QueueItem, error: DownloadError) {
    guard case .digestMismatch = error else {
        try? queue.resume(id: item.id)
        return
    }
    ...
}
```

For the non-`digestMismatch` branch, the item is immediately reset to
`.waiting` with **no backoff, no attempt cap, and no user-visible event**.
`runLoop()` (`DownloadCoordinator.swift:131-152`) then immediately
re-selects the same item on its next iteration (there is no `await` that
yields meaningfully between `process()` returning and `selectNext()` running
again other than the network round trip itself). A permanently failing
resource (revoked/expired blob URL, deleted server-side object, wrong
content-type response) therefore drives a tight loop that hammers the
network indefinitely, burns CPU/battery, and never surfaces anything to the
user (no `.blocked` event is emitted for this path — only quota-blocked
items emit `.blocked`).

The same root cause also means `.digestMismatch` retries
(`DownloadCoordinator.swift:236-242`) are unbounded and backoff-free too —
`attempt_count` is incremented but never compared against any threshold
anywhere in this partition, so a permanently corrupt upstream object also
spins forever, immediately re-requesting the same broken bytes.

**Fix:** Apply the same backoff used for transport failures (or a capped
attempt count) to every non-cancellation failure path, and stop retrying
(surfacing a `.blocked`-style terminal event) once a cap is hit:

```swift
private func handleDownloadError(_ item: QueueItem, error: DownloadError) {
    guard case .digestMismatch = error else {
        if item.attemptCount >= maxAttempts {
            try? queue.pause(id: item.id)
            emit(.blocked(itemID: item.id, assetSetID: item.assetSetID, reason: "\(error)"))
            return
        }
        try? queue.incrementAttempt(id: item.id)
        try? queue.resume(id: item.id)
        // schedule resume after backoffSeconds(attempt: item.attemptCount + 1)
        return
    }
    // existing digestMismatch handling, also capped
}
```


### P1-CR-002: Non-atomic object+row deletion can leave a phantom "verified" state

**File:** `playstead-mac/Playstead/Cache/EvictionPlanner.swift:128-133`, `playstead-mac/Playstead/Cache/CASManager.swift:96-107`
**Issue:**
`EvictionPlanner.execute(_:)` deletes each reclaimed object in two
independent steps with no atomicity between them:

```swift
func execute(_ plan: EvictionPlan) throws {
    for sha in plan.objectSHAs {
        try cas.remove(sha)                                                    // 1: unlinks the file + verify-index entry
        try localStore.connection.execute("DELETE FROM cache_objects WHERE sha256 = ?;", params: [sha])  // 2: separate statement, separate "transaction"
    }
}
```

`cas.remove(sha)` (`CASManager.swift:96-107`) removes the on-disk object
file *first*, then separately clears the verify-index entry. If the process
is killed (crash, force-quit, power loss) between the file removal and the
`DELETE FROM cache_objects` statement, the `cache_objects` row survives with
the object's sha256 still present. Every reader of `AvailabilityState`
derives its cached-member set directly from `cache_objects`
(`AvailabilityInputs.cachedMemberSHAs`), so on the next launch the game
re-derives as `.verifiedLocal` or `.pinnedOffline` — "verified"/"pinned"
badges — over a file that has actually been deleted. This is precisely the
failure mode `AvailabilityState.swift`'s own doc comment calls the one thing
this product cannot afford ("a user who sees 'verified' over content that
isn't there loses the only thing this product is selling").

**Fix:** Make the two deletions atomic from the app's perspective — delete
the DB row first inside a transaction, and only remove the on-disk object
after the transaction commits (so a crash before the file is gone still
shows the correct, non-cached state), or wrap both in one
`localStore.transaction` and treat `CASManager.remove`'s file-unlink as
best-effort cleanup that a startup reconciliation pass can retry:

```swift
func execute(_ plan: EvictionPlan) throws {
    for sha in plan.objectSHAs {
        try localStore.connection.execute("DELETE FROM cache_objects WHERE sha256 = ?;", params: [sha])
        try? cas.remove(sha) // best-effort; a reconciliation sweep can catch any leftover file
    }
}
```


### P1-CR-003: Bearer token stored with `kSecAttrAccessibleAfterFirstUnlock`, allowing it to leave the paired device

**File:** `playstead-mac/Playstead/Net/KeychainStore.swift:79`
**Issue:**
`storeCredential` writes the paired-device bearer token with:

```swift
kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
```

This accessibility class permits the Keychain item to be included in
iCloud Keychain sync and unencrypted local/iTunes-style backups. The file's
own doc comment describes this credential as belonging to D-07/D-10's
*device*-pairing model — "a device id and a long-lived opaque bearer
token" scoped to one paired device. Storing it with a syncable
accessibility class means the token (and the `baseURL`/`deviceID` envelope
that identifies which server it authenticates against) can propagate to
any other Mac signed into the same iCloud account, letting that second,
never-explicitly-paired machine authenticate to the server as if it were
the originally paired device — a bypass of the device-pairing boundary the
code is designed around.

**Fix:** Use the `...ThisDeviceOnly` variant so the credential never leaves
the device it was paired on:

```swift
kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
```

## Warnings

### P1-WR-001: Keychain credential store is delete-then-add, not atomic

**File:** `playstead-mac/Playstead/Net/KeychainStore.swift:66-86`
**Issue:** `storeCredential` calls `SecItemDelete` and then `SecItemAdd` as
two independent Keychain operations. If the process is killed between the
two calls (or `SecItemAdd` fails, e.g. `errSecDuplicateItem` from a race
with another writer, or `errSecInDarkWake`), the previously stored,
working credential is gone and no new one replaces it — the app becomes
unexpectedly unpaired with no credential at all, rather than either the old
or the new one.
**Fix:** Prefer `SecItemUpdate` when an item already exists, falling back
to `SecItemAdd` only when it doesn't, so there is never a window with zero
stored credential:
```swift
let updateStatus = SecItemUpdate(deleteQuery as CFDictionary, updateAttributes as CFDictionary)
if updateStatus == errSecItemNotFound {
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    ...
}
```

### P1-WR-002: `CASManager.commit` has a TOCTOU race for concurrent same-digest commits

**File:** `playstead-mac/Playstead/Cache/CASManager.swift:49-67`
**Issue:** `commit` checks `fm.fileExists(atPath: dest.path)` and then, in a
separate step, either discards the partial or moves it into place. Two
concurrent callers committing the same digest (e.g. a future multi-transfer
engine, or a test that doesn't serialize through `DownloadCoordinator`) can
both observe `fileExists == false`, and the second `fm.moveItem` then
throws because the destination now exists — an uncaught error from a
"should always succeed for byte-identical content" path. Today's single
`DownloadCoordinator` transfer model masks this, but the type itself makes
no such guarantee and is called directly by other code (e.g. tests).
**Fix:** Treat "destination already exists" as success by checking again
right before/after the failed move, or retry-on-`fileExists` inside the
same critical section rather than relying on caller serialization:
```swift
do {
    try fm.moveItem(at: partialURL, to: dest)
} catch {
    if fm.fileExists(atPath: dest.path) {
        try? fm.removeItem(at: partialURL)
    } else {
        throw error
    }
}
```

### P1-WR-003: `LocalStore.inMemoryFallback()` force-unwraps its own safety net

**File:** `playstead-mac/Playstead/Persistence/LocalStore.swift:36-40`
**Issue:**
```swift
static func inMemoryFallback() -> LocalStore {
    let connection = (try? SQLiteConnection(path: ":memory:"))!
    ...
}
```
This function exists specifically so the app can keep running (with an
empty library) when the on-disk store fails to open. Force-unwrapping the
`try?` here means that if opening an in-memory SQLite database itself ever
fails (e.g. under extreme memory pressure — the exact condition this
fallback path is likeliest to be reached under), the app crashes instead of
degrading gracefully, defeating the purpose of the fallback.
**Fix:** Handle the failure explicitly (e.g. `fatalError` with a clear
message is at least intentional, but better: surface an in-app "cache
unavailable" state without ever crashing), or at minimum document why
`:memory:` open is assumed infallible.

### P1-WR-004: Failed/invalid HTTP responses aren't drained and leave a stray empty partial file

**File:** `playstead-mac/Playstead/Cache/DownloadEngine.swift:199-210`
**Issue:** For the `!sentRange && http.statusCode != 200` case (a fresh
request that gets a non-200 status, e.g. 404/500/403), the code reaches
`try truncatePartial(at: partialURL, fm: fm)` (creating/truncating a
partial file for a request that never even started downloading real
content) and only afterward throws `DownloadError.invalidResponse` —
without ever consuming `bytesStream` (contrast with the `(true,
.restartFromZero)` branch just above, which explicitly calls
`drain(bytesStream)` before returning). This leaves the response body
un-drained (the connection may not be cleanly reusable) and creates an
unnecessary zero-byte file on every failed fresh-download attempt.
**Fix:** Drain the stream before throwing, and avoid touching the partial
file until a response worth persisting has been confirmed:
```swift
if !sentRange && http.statusCode != 200 {
    _ = try? await drain(bytesStream)
    throw DownloadError.invalidResponse
}
```

### P1-WR-005: `SQLiteConnection` never sets a busy timeout

**File:** `playstead-mac/Playstead/Persistence/SQLiteConnection.swift:43-53`
**Issue:** `init` opens the database and sets `PRAGMA foreign_keys = ON;`
but never sets `PRAGMA busy_timeout` (or calls `sqlite3_busy_timeout`).
Every write funnels through this connection's own serial `queue`, so
intra-process contention is already serialized, but any external process
(a second app instance, a debugging tool, Time Machine local snapshot
tooling, etc.) opening the same file can trigger `SQLITE_BUSY`, which today
surfaces as a hard `SQLiteError.stepFailed`/`.stepFailed` thrown from
`execute`/`transaction` rather than a short, transparent wait-and-retry.
**Fix:** Call `sqlite3_busy_timeout(handle, 5000)` (or similar) right after
`sqlite3_open` succeeds.

## Info

### P1-IN-001: `CASError.digestAlreadyExists` is declared but never thrown

**File:** `playstead-mac/Playstead/Cache/CASManager.swift:14-16`
**Issue:** The `CASError` enum declares `case digestAlreadyExists`, but no
code in this file (or elsewhere in the reviewed partition) ever throws it —
`commit(partialAt:sha256:)` silently discards the redundant partial instead
of surfacing this case. Dead enum case.
**Fix:** Remove the unused case, or use it if a caller actually needs to
distinguish "committed fresh" from "already present."

### P1-IN-002: `LocalStore.replaceCatalogue` and `CatalogueStore.replaceAll`/`upsert` duplicate the same insert logic

**File:** `playstead-mac/Playstead/Persistence/LocalStore.swift:46-80`, `playstead-mac/Playstead/Persistence/CatalogueStore.swift:25-93`
**Issue:** Both types independently implement "delete all catalogue rows,
then re-insert every entry/member," with slightly different column lists
(`LocalStore.replaceCatalogue` never touches `search_blob`, so any full
snapshot bootstrap through this path leaves `search_blob` at its
column-default `''`, meaning `CatalogueStore.filteredQuery`'s search would
silently match nothing for entries loaded this way until the next
`CatalogueStore.upsert`). This is a correctness-adjacent quality issue best
fixed by having one canonical replace path.
**Fix:** Have `SnapshotClient`/`LocalStore.replaceCatalogue` delegate to
`CatalogueStore.replaceAll` (which does populate `search_blob` via
`upsert`) instead of maintaining a second, divergent implementation.

### P1-IN-003: `Reachability.onChange` has no way to unregister an observer

**File:** `playstead-mac/Playstead/Cache/Reachability.swift:51-55`
**Issue:** `observers` only ever grows; there is no `removeObserver`/token
API. In long-lived test suites or any future code path that constructs
short-lived subscribers against a shared `Reachability` instance, this
accumulates retained closures indefinitely.
**Fix:** Return an opaque token/`Cancellable` from `onChange` and prune the
`observers` array on cancellation.


_Reviewed: 2026-08-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

# Partition P2 — mac Adapter / Controller / Readiness / release scripts


# Partition Review: mac-adapter-controller-readiness

**Reviewed:** 2026-08-30
**Depth:** standard
**Files Reviewed:** 22 (partition file count; `files_reviewed_list` above is authoritative)
**Status:** issues_found

## Summary

This partition covers the adapter/subprocess lifecycle, adapter pin integrity verification, BIOS file handling, controller connect/disconnect, and the release signing/notarization scripts. The individual components are each well-documented and internally consistent, but cross-checking documented guarantees against actual wiring surfaced three critical gaps: (1) the "re-proves it every time" digest check does not actually re-hash the installed binary, (2) a validated BIOS is never actually injected into the emulator launch arguments despite the UI claiming "BIOS validated and in use," and (3) the controller-mapping-to-launch wiring (`refreshActiveControllerMapping`) is defined and tested in isolation but never called from any connect/disconnect/save/reset code path in the shipped app, so a user's remapped buttons never reach the emulator. Several subprocess-lifecycle and shell-script robustness issues are also noted.

## Critical Issues

### P2-CR-001: Installed-adapter digest is never re-verified against the actual binary on disk

**File:** `playstead-mac/Playstead/Adapter/AdapterHost.swift:170-206`
**Issue:** The doc comment on `InstallVerifyRecord` (lines 4-7) explicitly promises: "Recorded once at emulator install time... and re-checked on every launch by `AdapterHost.verifyInstalledDigest()`. The spike proved the binary once; the app re-proves it every time." The implementation does not do this. For the `.installed` state (line 179), `verifyInstalledDigest()` only trusts the `verified` boolean that was computed once at install/selection time (`AdapterInstaller.install()`/`selectExisting()`) and checks that a file merely *exists* at that path (line 188) — it never re-hashes the file's current bytes. For the fallback `.notInstalled`-default path (lines 194-205), it reads a cached `.install-verify.json` record and compares that cached digest to the pin, again never re-hashing the executable that's actually about to be launched. If the installed binary is modified or replaced after install (disk corruption, a bug elsewhere, or a local supply-chain attack that swaps the executable while leaving the JSON record/DB row untouched), every subsequent launch will report "verified" and launch the tampered binary. This defeats the entire stated purpose of pinning + digest verification.
**Fix:**
```swift
func verifyInstalledDigest() throws {
    let path = resolvedExecutableURL.path
    guard FileManager.default.fileExists(atPath: path) else {
        throw LaunchError.emulatorNotInstalled
    }
    let actualDigest = try StreamingSHA256.resume(from: URL(fileURLWithPath: path)).finalizeHex()
    guard actualDigest == pin.sha256 else {
        throw LaunchError.digestMismatch(expected: pin.sha256, actual: actualDigest)
    }
}
```
Note the pin's digest is presumably the archive/app-bundle digest rather than the raw executable's digest today — if so, the fix needs to hash whatever artifact the pin's `sha256` actually describes (the full `.app` bundle, matching what `AdapterInstaller.install()` hashes before expansion), not just the inner executable, so the two digests are comparable. Either way, the check must run against the live file, not a cached record.

### P2-CR-002: A validated BIOS is never actually injected into the emulator launch

**File:** `playstead-mac/Playstead/Adapter/AdapterHost.swift:130-138`, `playstead-mac/Playstead/Adapter/AdapterCatalog.swift:38`
**Issue:** `AdapterPin.json`'s `config_injection.keys.bios_path` declares the CLI shape `"-b {path}"` (AdapterPin.json:15), and `AdapterDescriptor.biosInjectionSupported` (AdapterCatalog.swift:38) is computed from it — but nothing ever uses `biosInjectionSupported` or renders the `-b {path}` argument. `AdapterHost.launch(romPath:saveDir:onExit:)` (AdapterHost.swift:213) and `renderedLaunchArguments(romPath:saveDir:)` (AdapterHost.swift:130) take no BIOS path parameter at all, and `AdapterHost` holds no reference to `BiosStore`. Meanwhile `ReadinessEngine.evaluateBIOS()` (ReadinessEngine.swift:208-226) and `AdapterCapabilityCard.biosPostureText` (AdapterCapabilityCard.swift:31-39) both tell the user "BIOS validated and in use" the moment `BiosStore.hasManagedBIOS` is true. The user is told their BIOS is in use; it is never passed to the emulator, so play always falls back to the built-in high-level implementation regardless of a validated BIOS being present. This is a user-facing false statement about product behavior, not just a missing feature.
**Fix:** Thread a `biosPath: String?` through `launch`/`renderedLaunchArguments`, and append the rendered `bios_path` key from `pin.configInjection.keys` when a managed BIOS exists:
```swift
func renderedLaunchArguments(romPath: String, saveDir: String, biosPath: String?) -> [String] {
    var args = pin.launch.renderedArguments(romPath: romPath, saveDir: saveDir)
    if let biosPath, let template = pin.configInjection.keys["bios_path"] {
        args.append(contentsOf: template
            .replacingOccurrences(of: "{path}", with: biosPath)
            .split(separator: " ").map(String.init))
    }
    ... // existing controller-mapping loop
}
```
and pass `biosStore.managedRecord(forSystem:).map { biosStore.managedPath(forSHA256: $0.sha256).path }` from the call site.

### P2-CR-003: Controller mapping is never actually connected to the adapter launch in the shipped app

**File:** `playstead-mac/Playstead/App/PlaysteadApp.swift:70-85`, `playstead-mac/Playstead/Controller/ControllerHost.swift:190-209`
**Issue:** `AppEnvironment.refreshActiveControllerMapping()` is the documented "one place that connects `ControllerHost`'s assignment to `AdapterHost`'s launch arguments" (PlaysteadApp.swift:75-77), but it is defined and never called anywhere in the non-test codebase (confirmed via project-wide search — only its own definition and its unit test reference it). `ControllerHost.handleConnect`/`handleDisconnect`/`assign` (ControllerHost.swift:171-209) have no observers wired to `AppEnvironment`, and `ControllerMappingStore.save`/`reset` (ControllerMappingStore.swift:36-59) have no callers that also call `refreshActiveControllerMapping()`. Consequently `AdapterHost.activeControllerMapping` (AdapterHost.swift:89) stays `nil` for the lifetime of a real app run, `renderedLaunchArguments` never appends the per-button `-C input.<x>=<y>` overrides (AdapterHost.swift:132-137), and any remap a user makes in `ControllerSettingsView` has no effect on the actual game — despite the settings UI (and its accessibility labels) implying the change takes effect.
**Fix:** Wire the observer at the one place `ControllerHost`'s state actually changes — e.g. have `ControllerHost` accept an optional `onAssignmentChanged: () -> Void` callback invoked from `handleConnect`, `handleDisconnect`, and `assign`, set by `AppEnvironment.init()` to call `refreshActiveControllerMapping()`; and call `refreshActiveControllerMapping()` again after every `ControllerMappingStore.save`/`reset` invoked from the settings flow.

## Warnings

### P2-WR-001: `AdapterInstaller.install()` can return a "verified" installation whose file no longer exists on disk

**File:** `playstead-mac/Playstead/Adapter/AdapterInstaller.swift:90-93`
**Issue:** `install()` short-circuits with the cached DB row (`existingInstallation()`) whenever `existing.verified` is true, without checking `FileManager.default.fileExists(atPath: existing.executablePath)`. If the user (or another process) deletes the expanded `.app` after a prior successful install, calling `install()` again reports success/"already installed" even though nothing is on disk. `AdapterHost.verifyInstalledDigest()` will eventually catch this at actual launch time, but any caller that treats `AdapterInstaller.install()`'s return value as "ready to play" (e.g. an installer-progress UI) will show a false positive in between.
**Fix:**
```swift
if let existing = existingInstallation(), existing.verified,
   FileManager.default.fileExists(atPath: existing.executablePath) {
    return existing
}
```

### P2-WR-002: TOCTOU between BIOS digest verification and the copy into managed storage

**File:** `playstead-mac/Playstead/Adapter/BiosStore.swift:81-117`
**Issue:** `validateAndAccept` checks the candidate's type/symlink status (lines 87-96), computes its digest by re-opening the file separately (`hashFile`, line 109), and only afterward copies the file (`fm.copyItem`, line 116). Between the digest computation and the copy, the file at `candidateURL` could be replaced (e.g., another process, or the same drag source being rewritten), so the bytes actually copied into managed storage — and later trusted as validated under that digest's filename — are not guaranteed to be the same bytes that were hashed.
**Fix:** Copy first into a private temp file, then hash the copy, then atomically move the temp file into `managedDirectory` under the computed digest name — never re-open `candidateURL` a second time after the initial read.

### P2-WR-003: `sign-and-notarize.sh`'s sandbox-entitlement check only confirms the key's presence, not its value

**File:** `playstead-mac/scripts/sign-and-notarize.sh:33-34`
**Issue:** The step labeled "Confirming hardened runtime and non-sandboxed entitlements" runs `codesign -d --entitlements - "$APP_PATH" | grep -A1 'com.apple.security.app-sandbox'`. This only asserts that the `com.apple.security.app-sandbox` key exists in the entitlements and prints the following line for a human to read in the log — it never programmatically checks that the value is `<false/>`. If a future regression accidentally builds with `<true/>` (sandbox enabled), which would break the ability to launch a downloaded third-party emulator per D-04's stated rationale, this script's `set -e`/`pipefail` guard will not catch it and the release will proceed to notarization/shipping.
**Fix:**
```bash
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)"
if grep -A1 'com.apple.security.app-sandbox' <<< "$ENTITLEMENTS" | grep -q '<true/>'; then
  echo "FATAL: $APP_PATH is App-Sandboxed; D-04 requires a non-sandboxed build." >&2
  exit 1
fi
```

### P2-WR-004: Disk-image mount/copy subprocesses in the installer have no timeout

**File:** `playstead-mac/Playstead/Adapter/AdapterInstaller.swift:211-250`
**Issue:** `defaultExpand`'s `hdiutil attach`, `hdiutil detach`, and `ditto` invocations call `.run()` followed by `.waitUntilExit()` with no timeout. `hdiutil attach` against a downloaded disk image can hang (e.g. an unexpected password prompt, a stuck kernel extension, or a genuinely malformed but not-corrupt-by-digest image) — the actor-isolated `AdapterInstaller.install()` call would then block indefinitely with no way for the caller to cancel or time out, effectively wedging the install flow.
**Fix:** Wrap each subprocess wait in a timeout (e.g. race `waitUntilExit()` against a `DispatchWorkItem` that force-terminates the process after N seconds and throws `AdapterInstallError.expansionFailed("timed out")`).

### P2-WR-005: Terminating child processes on app quit does not escalate or wait

**File:** `playstead-mac/Playstead/Adapter/AdapterHost.swift:45-52`
**Issue:** `AdapterProcessRegistry.terminateAll()` (invoked from `NSApplication.willTerminateNotification`) sends `SIGTERM` via `proc.terminate()` to every tracked running process but never waits for exit or escalates to `SIGKILL` if the child doesn't respond in time. The pin's own recorded evidence (`AdapterPin.json`'s `exit_detection.clean.note`) states there is "no observed graceful-quit path from an external `Process.terminate()` call" for this emulator — so this is a documented-as-plausible scenario, not a hypothetical. If the app terminates before the child fully exits (macOS does not block app termination on this notification handler), an orphaned emulator process can persist after Playstead quits.
**Fix:** After sending `terminate()`, poll `proc.isRunning` with a short deadline (e.g. 2s) and send `SIGKILL` (`kill(proc.processIdentifier, SIGKILL)`) if still running before allowing the notification handler to return.

## Info

### P2-IN-001: `apiClient` is unconditionally constructed, contradicting its doc comment

**File:** `playstead-mac/Playstead/App/PlaysteadApp.swift:27-55`
**Issue:** The type-level doc comment describes "an API client (nil until a paired credential exists)," but `init()` unconditionally assigns `self.apiClient = APIClient(keychain: KeychainStore())` (line 55) with no conditional on pairing state. The property is optional but is never actually left `nil` by this code path, which is misleading for future readers relying on the comment.
**Fix:** Either update the comment to reflect that `apiClient` is always constructed (and pairing state is tracked internally by `APIClient`), or make construction conditional on an actual paired-credential check if that's the intended behavior.

### P2-IN-002: `BiosStore.managedPath(forSHA256:)` is unused

**File:** `playstead-mac/Playstead/Adapter/BiosStore.swift:166-168`
**Issue:** No call site anywhere in the non-test codebase uses `managedPath(forSHA256:)`. Dead public API surface increases maintenance cost and, since it accepts a caller-supplied `sha256` string that is appended directly as a path component with no validation, would become a path-traversal-adjacent concern the moment a real caller passes anything other than a validated hex digest (e.g. `"../../secret"`).
**Fix:** Either remove the unused method, or if it is intended for a future BIOS-serving call site, validate the input is a well-formed hex SHA-256 string before using it as a path component.


_Reviewed: 2026-08-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

# Partition P3 — mac Library / Curation / Design (UI)


# Phase 03 (partition: mac-ui): Code Review Report

**Reviewed:** 2026-08-30
**Depth:** standard
**Files Reviewed:** 31 (files listed in `required_reading`; `GameRowView.swift`/`LibraryShellView.swift`/`LibraryViewModel.swift` also reviewed since present in the file list)
**Status:** issues_found

## Summary

This partition covers curation (Collections/Continue/Favorites/Queue/Recent), the design-token layer, and the library shell/shelf UI. The fractional-position ordering module (`FractionalPosition.swift`) is well-documented and mirrors the server algorithm carefully, but it has a real infinite-loop hazard when two neighbouring positions are equal — a case the reorder view models do not guard against before calling `between`. There is also meaningful, avoidable duplication: the "preview many moves, commit exactly one intent" reorder discipline and its SwiftUI drag handler are implemented twice nearly verbatim (Collections vs. Queue), and byte-formatting boilerplate is copy-pasted three times across the storage-related views. `GameRowView`'s async action handlers mutate `@State` from functions that are not actor-isolated, unlike the one call site in the same file that correctly hops back to `@MainActor`. `MotionPreference` registers a `NotificationCenter` block observer it never removes.

## Critical Issues

### P3-CR-001: `FractionalPosition.midpoint` infinite-loops when the two neighbouring positions are equal

**File:** `playstead-mac/Playstead/Curation/FractionalPosition.swift:129-140`

**Issue:** `midpoint(_:_:)` widens `lowInt`/`highInt` by repeatedly multiplying both by `base` until `highInt - lowInt >= 2`:

```swift
private static func midpoint(_ lowDigits: [Int], _ highDigits: [Int]) -> String {
    let len = max(max(lowDigits.count, highDigits.count), 1)
    var lowInt = padInt(lowDigits, len)
    var highInt = padInt(highDigits, len)
    var currentLen = len
    while highInt - lowInt < 2 {
        lowInt *= base
        highInt *= base
        currentLen += 1
    }
    return encode((lowInt + highInt) / 2, currentLen)
}
```

If `lowDigits == highDigits` (the two neighbours have the *same* position string), `highInt - lowInt` is `0` before the loop and stays `0` on every iteration (`0 * base == 0`), so the loop never terminates — it hangs the calling thread forever. `commitReorderMembers`/`commitReorder` call `FractionalPosition.between(beforePosition, afterPosition)` synchronously on the main thread (from a SwiftUI `List.onMove` handler), so this freezes the whole app.

This is not a purely theoretical case: `CollectionsViewModel.commitReorderMembers` and `QueueViewModel.commitReorder` derive `beforePosition`/`afterPosition` by looking up rows from `members(of:)`/`items`, which are read from the local mirror as it currently stands. If the local mirror ever contains two rows with an identical `position` (e.g., a race between two optimistic inserts computed from the same "current last" position before either write lands, or a server-recomputed position that happens to collide with an existing sibling before the journal fully converges), the very next drag-reorder gesture that lands between those two rows will hang the app with no timeout and no error path.

**Fix:** Guard against equal neighbours before/inside `midpoint`, e.g. treat equal digits as if only one bound were given, or break the loop once the two representations are provably equal and fall back to `appendAfter`:

```swift
private static func midpoint(_ lowDigits: [Int], _ highDigits: [Int]) -> String {
    guard lowDigits != highDigits else {
        // Neighbours collided (e.g., a stale/racing local mirror) — treat
        // as "insert after low" rather than hang forever computing a
        // non-existent gap.
        return appendAfter(lowDigits)
    }
    let len = max(max(lowDigits.count, highDigits.count), 1)
    var lowInt = padInt(lowDigits, len)
    var highInt = padInt(highDigits, len)
    var currentLen = len
    while highInt - lowInt < 2 {
        lowInt *= base
        highInt *= base
        currentLen += 1
    }
    return encode((lowInt + highInt) / 2, currentLen)
}
```

## Warnings

### P3-WR-001: Reorder-preview/commit logic duplicated verbatim between `CollectionsViewModel` and `QueueViewModel`

**File:** `playstead-mac/Playstead/Curation/CollectionsViewModel.swift:83-122`, `playstead-mac/Playstead/Curation/QueueViewModel.swift:49-81`

**Issue:** `beginReorderMembers`/`beginReorder`, `previewMoveMember`/`previewMove`, and `commitReorderMembers`/`commitReorder` are the same algorithm (snapshot order → mutate an in-memory array → compute before/after neighbours → call `FractionalPosition.between` → enqueue one intent) copy-pasted with only naming and collection-scoping differences. The doc comment on `QueueViewModel` even says as much ("Mirrors `CollectionsViewModel`'s reorder discipline exactly"). Any future fix to this logic (e.g., the `midpoint` collision above, or a future rebalance trigger via `needsRebalance`) has to be applied twice, and it already isn't (only one of the two call sites recomputes `existing`/`items` at the same point in the sequence, which is easy to drift further apart over time).

**Fix:** Extract a generic `ReorderSession<Row>` helper (or a free function taking `currentOrder: () -> [String]`, `positionOf: (String) -> String?`, and returning the computed `(newPosition, beforeID, afterID)` triple) that both view models call, so the ordering math exists in exactly one place.

### P3-WR-002: `move(from:to:)` drag-handler duplicated between `CollectionDetailView` and `QueueShelfView`

**File:** `playstead-mac/Playstead/Curation/CollectionDetailView.swift:37-44`, `playstead-mac/Playstead/Curation/QueueShelfView.swift:35-42`

**Issue:** Both views implement an identical `List.onMove` translation (`destination > sourceIndex ? destination - 1 : destination`) wrapped in the same `beginReorder…`/`previewMove…`/`commitReorder…`/`refresh()` sequence. This is the SwiftUI-facing half of WR-001's duplication and should be fixed together with it — e.g., a single generic `ReorderableList<Row>` view that takes a `ReorderController` protocol/closure bundle, used by both `CollectionDetailView` and `QueueShelfView`.

**Fix:** Factor the `onMove` index translation and the begin/preview/commit/refresh call sequence into one shared helper (view or function) parameterized over the view model's reorder methods.

### P3-WR-003: Byte-formatting boilerplate duplicated three times

**File:** `playstead-mac/Playstead/Library/QuotaSettingsView.swift:12-20`, `playstead-mac/Playstead/Library/ReclaimPromptView.swift:30-38`, `playstead-mac/Playstead/Library/StorageView.swift:28-36`

**Issue:** All three views declare their own private `static let formatter: ByteCountFormatter` and `static func formatBytes(_ bytes: Int) -> String` with identical bodies. This is exactly the kind of "duplicated logic that should live in one place" this review is asked to flag — any future change (e.g., switching count style, localizing, or fixing a formatting edge case) has to be made three times, and a fourth storage-related view added later will likely re-copy it again rather than discover an existing utility.

**Fix:** Move `formatBytes`/the shared `ByteCountFormatter` into a single utility (e.g., a `ByteFormatting` enum in `Design/` alongside `DesignTokens`), and have all three views call it.

### P3-WR-004: `GameRowView`'s async action handlers mutate `@State` without actor isolation

**File:** `playstead-mac/Playstead/Library/GameRowView.swift:84-141`

**Issue:** `download()` and `play()` are plain `async` instance methods (not `@MainActor`-isolated) that assign to `@State private var status` and are invoked via bare `Task { await download() }` / `Task { await play() }` from button actions. Neither method is marked `@MainActor`, and nothing in their signatures pins execution to the main actor after the first `await` (e.g. `try await engine.download(...)`, `try await adapterHost.launch(...)`). If any of those awaited calls resume off the main executor, the subsequent `status = .error(...)` / `status = .downloading` / `refreshStatus()` assignments happen off-main-thread, which is exactly the class of bug SwiftUI's runtime warns about ("Publishing changes from background threads is not allowed") and can produce dropped/late UI updates.

Notably, the same file already knows this needs explicit handling: the `adapterHost.launch` completion closure correctly wraps its state mutation in `Task { @MainActor in lastExit = exit }` (line 135), but the surrounding `play()`/`download()` bodies themselves are not similarly isolated.

**Fix:** Mark the methods `@MainActor` explicitly (simplest and consistent with the one place in the file that already does this correctly):

```swift
@MainActor
private func download() async { ... }

@MainActor
private func play() async { ... }
```

### P3-WR-005: `RecentShelfView` performs synchronous SQLite reads directly inside the view body on every render

**File:** `playstead-mac/Playstead/Curation/RecentShelfView.swift:41-63`

**Issue:** Every other shelf in this partition (`ContinueShelfView`, `FavoritesShelfView`, `QueueShelfView`) reads its list from an `@Observable` view model's cached, already-`refresh()`-ed array. `RecentShelfView.sessionsSection`, however, calls `sessionRecorder.listings()` — which runs a `SELECT ... ORDER BY started_at DESC` against the local SQLite connection — directly from the view's `body`, meaning it re-queries the database synchronously on every SwiftUI re-render of this view (e.g., any unrelated state change elsewhere on the Home screen that causes this view to be re-evaluated), rather than once per actual data change like its siblings.

**Fix:** Give `PlaySessionRecorder`-backed data the same treatment as the rest of the curation surfaces: wrap it in a small `@Observable` view model (or fold it into `RecentViewModel`) that caches `listings()` and exposes a `refresh()` called after `delete(_:)`, rather than querying from `body`.

### P3-WR-006: `MotionPreference` never removes its `NotificationCenter` observer

**File:** `playstead-mac/Playstead/Design/MotionPreference.swift:23-35`

**Issue:** `init` registers a block-based observer via `NotificationCenter.default.addObserver(forName:object:queue:using:)` and stores the returned token in `observer`, but there is no `deinit` that calls `NotificationCenter.default.removeObserver(observer)`. Because the closure captures `self` weakly, `MotionPreference` itself won't leak, but the registered observer token/closure stays registered with `NotificationCenter` for the process lifetime regardless of how many `MotionPreference` instances are created and discarded (e.g., in tests that construct one per test case) — each discarded instance leaves a permanently-registered, now-inert observer behind.

**Fix:**

```swift
deinit {
    if let observer {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

## Info

### P3-IN-001: Accessibility label has a dangling comma when a card/row has no status

**File:** `playstead-mac/Playstead/Library/GameCardView.swift:57-61`, `playstead-mac/Playstead/Library/GameListView.swift:55-60`

**Issue:** Both `accessibleLabel`/`accessibleLabel(for:)` build `"\(displayTitle), \(systemName), \(statusSentence)"`. When `statuses` is empty, `LibraryStatus.highestPriority(among:)` returns `nil` and `statusSentence` is `""`, producing a label like `"Some Game, Game Boy Advance, "` — a trailing comma-space with nothing after it, which VoiceOver will read as an awkward pause/silence rather than a clean sentence.

**Fix:** Only append the status clause when non-empty:

```swift
var accessibleLabel: String {
    let systemName = SystemRegistry.entry(for: systemID).displayName
    guard let statusSentence = LibraryStatus.highestPriority(among: statuses)?.accessibleName(title: displayTitle) else {
        return "\(displayTitle), \(systemName)"
    }
    return "\(displayTitle), \(systemName), \(statusSentence)"
}
```

### P3-IN-002: `FractionalPosition.needsRebalance`/`spaced` are unused in this partition's files

**File:** `playstead-mac/Playstead/Curation/FractionalPosition.swift:55-71`

**Issue:** Neither `CollectionsViewModel` nor `QueueViewModel` (the only two call sites of `FractionalPosition` reviewed here) ever calls `needsRebalance` or `spaced`, even though CR-001 above is precisely the scenario `needsRebalance` seems designed to detect ahead of time (before precision runs out / positions collide). If nothing outside this partition calls these either, they're dead code; if something does, it's worth cross-checking that the reorder view models are actually supposed to consult `needsRebalance` before committing a move rather than never doing so.

**Fix:** Either wire `needsRebalance` into `commitReorderMembers`/`commitReorder` as a pre-check (which would also mitigate CR-001), or remove it if genuinely unused, and confirm with the wider codebase whether `spaced` has a live caller outside this file set.


_Reviewed: 2026-08-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

# Partition P4 — mac Sync + XCTest suite


# Phase 03: Code Review Report (Partition: mac-sync-and-tests)

**Reviewed:** 2026-08-30
**Depth:** standard
**Files Reviewed:** 22 (7 required Sync/ source files were read in full; the remaining test files were read/scanned for the specific cross-cutting patterns this partition was asked to check — shared mutable state, tautological assertions, flaky timing, missing failure-path coverage)
**Status:** issues_found

## Summary

The sync spine (`ChangesClient`/`CursorStore`/`JournalApplier`/`Outbox`/`OutboxWorker`/`SyncEngine`) is well-documented and the happy paths (bootstrap, resumed paging, cursor-expired reset, idempotent replay of a *single* intent) are solid and well tested in `SyncEngineTests`/`OutboxTests`. However, three correctness gaps survive adversarial tracing of the failure paths the code itself claims to handle:

1. The idempotency-key scheme collides for two *different* intents on the same row (e.g. two successive renames or two successive moves before the first has been acknowledged), which can cause the second, distinct mutation to be silently discarded by a naive idempotency-key-keyed server.
2. `revertOptimistic` is a no-op for every delete/remove/dequeue-shaped intent, so a permanent (4xx) rejection of e.g. `collectionDelete` leaves the collection and its members tombstoned locally forever with no future sync event able to correct it — the exact "silently differs from what the server accepted" outcome the code's own doc comments say must never happen.
3. `OutboxWorker`'s documented "retry with backoff" has no actual backoff or retry-cap/poison-message handling: `attemptCount` is incremented but never read, and there is no code path in this partition that limits or slows the rate of `drainOnce()` retries for a permanently-failing entry.

Test-quality review of the shared `StubURLProtocol` fixture (used by every sync-related test class) also surfaces a real risk of cross-test flakiness from unguarded shared global mutable state.

## Critical Issues

### P4-CR-001: Idempotency key collides across two distinct intents on the same row

**File:** `playstead-mac/Playstead/Sync/CurationIntent.swift:131-155`
**Issue:** `idempotencyKey` is `"\(kind.rawValue):\(anchorID)"`, where `anchorID` for every remove/rename/delete/move-shaped intent is just the target row's own id — it does not incorporate the intent's actual content (new name, new neighbours/position, etc). If a user issues two *different* mutations of the same kind against the same row before the first has been acknowledged (e.g. rename a collection to "A", then immediately rename it again to "B" while still offline; or drag-reorder the same item twice in quick succession before the first move's request completes), both outbox entries get the **identical** `Idempotency-Key` header value despite carrying different bodies.

If entry 1 ("rename to A") is sent and the server processes it but the response is lost (a transport failure — exactly the scenario `OutboxWorker`/`markPendingForRetry` is built to handle), the client retries entry 1, it succeeds, and the row is deleted. When entry 2 ("rename to B") is later sent, it carries the *same* idempotency key value entry 1 used. Any idempotency implementation that replays the first stored response for a repeated key (the standard interpretation of an `Idempotency-Key` header, and the one this client's own doc comments describe as the expected server behavior in `test_retry_sendsTheSameIdempotencyKeyAsTheFirstAttempt`) will return entry 1's cached response for entry 2's request without ever applying "rename to B" server-side — while the client's optimistic local state already shows "B". This produces a permanent, silent client/server divergence with no future `/changes` journal entry to correct it (nothing changed server-side for the second rename, so nothing new is ever pushed).

This affects every kind whose `anchorID` is the target's own row id and whose payload can vary between successive intents on that row: `collectionRename`, `collectionMemberMove`, `queueMove` (and, less severely, `favoriteRemove`/`collectionDelete`/`collectionMemberRemove`/`queueDequeue`/`playSessionDelete`, where a second identical intent is at least idempotent in effect even though the collision is still present).

**Fix:** Fold the intent's actual mutable content into the idempotency key (or, simpler, drop the anchor-only key scheme for update-shaped intents and instead include a per-*attempt-sequence* nonce that is stable only across retries of the *same enqueued entry*, e.g. hash of the outbox row id itself rather than of the semantic target row):
```swift
// CurationIntent.swift
var idempotencyKey: String {
    // Anchor on the specific outbox entry, not just the target row, so
    // two different intents on the same row never share a key. Requires
    // threading the outbox entry's own generated id through instead of
    // computing this from the intent alone (e.g. Outbox.enqueue passes
    // entryID as part of the header instead of intent.idempotencyKey).
}
```
At minimum, add a regression test exercising "two distinct move/rename intents enqueued back-to-back on the same row, first one's response lost, second one sent" and confirm the second mutation's effect is not silently dropped.

### P4-CR-002: Permanent rejection of a delete/remove-shaped intent leaves the local row permanently, silently diverged from the server

**File:** `playstead-mac/Playstead/Sync/CurationIntent.swift:417-443`, `playstead-mac/Playstead/Sync/Outbox.swift:112-124`
**Issue:** `revertOptimistic` is a documented no-op for `favoriteRemove`, `collectionRename`, `collectionDelete`, `collectionMemberRemove`, `collectionMemberMove`, `queueDequeue`, `queueMove`, `playSessionRecord`, `playSessionDelete`. For `collectionDelete` specifically, `applyOptimistically` has already tombstoned the collection **and every one of its members** (`tombstoneCollectionMembersByCollection` + `tombstoneCollection`). If the server permanently rejects the delete (e.g. a 403, or a 404 because a concurrent operation already changed the collection's ETag/version), `Outbox.markRejected` reverts nothing — the collection and all its members stay deleted in the local read model forever. Because nothing actually changed server-side, no future `/changes` journal entry will ever arrive to correct this: the row is gone from the user's library on this device permanently, while it still exists on the server and every other device. This directly contradicts this same file's own stated invariant ("the user's library must actually match what the server accepted, never silently drift from what they asked for").

The same class of bug applies to `collectionMemberRemove`/`queueDequeue`/`favoriteRemove` (a permanently-rejected removal leaves the row tombstoned locally forever) — this is data loss, not merely UI staleness, and is more serious than the "known, bounded limitation" framing in the doc comment (which reads as scoped to cosmetic staleness of rename/move metadata, not to rows disappearing from the user's library).

**Fix:** At minimum, a permanent rejection of a delete/remove-shaped intent should trigger a re-fetch/re-apply of that specific row (or a full re-sync) rather than leaving the tombstone in place with no correction mechanism:
```swift
case .collectionDelete(let collectionID):
    // Re-materialize from the server rather than leaving a silent tombstone —
    // e.g. enqueue a single-entity refetch, or force the next syncNow() to
    // re-pull this row specifically.
    try refetchAndRestore(collectionID: collectionID)
```
If this really is an accepted, bounded limitation for v1, it should at minimum be surfaced to the user (e.g. `RejectedIntentsView` already exists for this) with copy that makes clear the collection/member/favorite may need to be manually recreated — today `revertOptimistic` silently does nothing and the row simply vanishes.

### P4-CR-003: `OutboxWorker` has no actual backoff or poison-message handling despite being documented as having one

**File:** `playstead-mac/Playstead/Sync/OutboxWorker.swift:17-27`, `playstead-mac/Playstead/Sync/Outbox.swift:101-110`
**Issue:** The doc comments on `Outbox.markPendingForRetry` ("attempt count incremented for the worker's backoff decision") and `OutboxWorker` ("A transport failure or five-hundred-class response retries with backoff") both assert a backoff mechanism exists. In fact `attemptCount` is incremented on every retry but is never read anywhere in this partition (confirmed by grep — no file references `entry.attemptCount` or `attemptCount` outside of the increment itself and one test assertion that it becomes `1`). There is no delay, no exponential backoff, and no maximum-attempt cap/poison-message quarantine: a permanently-failing entry (e.g. a 503 that never recovers, or a network that's simply down) will be retried at whatever cadence the (unknown, outside this partition) caller invokes `drainOnce()` at, forever, with no throttling and no way to stop hammering the server or to surface "this entry has failed N times and needs attention" to the user.

**Fix:** Either implement the backoff the docs claim (e.g. skip an entry whose `attemptCount` implies it isn't yet due for retry, based on an exponential delay derived from `attemptCount` and a `lastAttemptAt` timestamp not currently stored), or correct the documentation to state plainly that backoff/poison-message handling is not yet implemented and is a known gap:
```swift
// Outbox.swift — add a `next_retry_at` column and check it before returning
// a row from listPending(), computed as e.g. min(2^attemptCount * baseDelay, cap)
func listPending() -> [OutboxEntry] {
    rows(where: "state = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= ?)", ...)
}
```

## Warnings

### P4-WR-001: Unrecognized outbox `kind` silently defaults to `.favoriteAdd`

**File:** `playstead-mac/Playstead/Sync/Outbox.swift:144-147`
**Issue:** `rows(where:orderBy:)` does `kind: kind ?? .favoriteAdd` when the persisted `kind` string fails to parse into `CurationIntentKind` (e.g. a row written by a future client version with a kind this build doesn't recognise). `OutboxEntry.kind` is documented elsewhere as being meaningful even when `intent` is `nil` (e.g. `RejectedIntentsView` groups/filters by kind). Silently mislabeling an unknown kind as `favoriteAdd` will misrepresent these rows to any UI or telemetry that reads `kind` directly, and is inconsistent with the file's own stated "skip-and-count" forward-compatibility posture (which is used correctly for `intent` itself, just not for `kind`).
**Fix:** Add an `.unknown` case to `CurationIntentKind` (or make `OutboxEntry.kind` optional) rather than aliasing an unrecognised value onto an arbitrary real case.

### P4-WR-002: `CursorStore.clear()` is dead code that contradicts its own documented invariant

**File:** `playstead-mac/Playstead/Sync/CursorStore.swift:63-69`
**Issue:** The doc comment states this method is "always inside the same transaction as clearing the catalogue/curation tables so the client can never observe a cleared read model paired with a stale cursor" — but a repo-wide search shows `clear()` is never called from any production code path. `SyncEngine.bootstrapFromSnapshot()` (the only cursor-reset flow in this partition) never calls it; it simply overwrites the cursor via `cursorStore.store(...)` after the transaction that clears/repopulates the catalogue/curation tables completes. The described "clear cursor + clear tables in one transaction" invariant is therefore never actually exercised anywhere, by tests or by the app.
**Fix:** Either wire `clear()` into `bootstrapFromSnapshot()`'s transaction as documented, or delete the unused method and its now-inaccurate doc comment.

### P4-WR-003: `OutboxWorker` is never instantiated in production code within this partition

**File:** `playstead-mac/Playstead/Sync/OutboxWorker.swift` (whole file)
**Issue:** A repo-wide search for `OutboxWorker(` finds constructions only in `OutboxTests.swift` and `PlaySessionTests.swift`; no file under `playstead-mac/Playstead/` (production code) instantiates or drives it. If nothing outside this partition wires `OutboxWorker.drainOnce()` into `SyncEngine.syncNow()` or a periodic timer, enqueued outbox entries will never actually be sent by the running app — they will sit `pending` indefinitely despite `Outbox`'s doc comments describing "the next launch" as when draining happens. This may be resolved by a call site in a different partition (e.g. an app-lifecycle or coordinator file not in this review's scope) — flagging so it can be confirmed rather than assumed.
**Fix:** Confirm (outside this partition) that some call site invokes `OutboxWorker.drainOnce()` after `syncNow()` succeeds and/or on a periodic timer; if none exists, this is a P0 functional gap, not merely a warning.

### P4-WR-004: Shared, unsynchronized global mutable state in `StubURLProtocol` risks cross-test flakiness

**File:** `playstead-mac/PlaysteadTests/CacheTests/StubURLProtocol.swift:34-35, 65-77`
**Issue:** `responder` and `requestLog` are `nonisolated(unsafe) static var`s shared process-wide across every test class that uses this fixture (`SyncEngineTests`, `OutboxTests`, `OrderingTests`, `PlaySessionTests`, and the `CacheTests` suite). `startLoading()` delivers its response asynchronously via `DispatchQueue.global().async` with two `Thread.sleep(forTimeInterval: 0.02)` pauses. `reset()` (called synchronously in `setUp`/`tearDown`) does not wait for any in-flight `startLoading()` dispatch from a previous test to finish before the next test's `setUp` clears `responder`/`requestLog` and installs its own. If a previous test's async response callback fires after the next test has already reset and reconfigured `responder`, it can append a stray entry into the *new* test's `requestLog`, or invoke a `client?.urlProtocol(...)` callback against a `URLProtocol` instance whose owning `URLSessionTask` may already be torn down. This is a genuine (if usually low-probability) source of order-dependent, hard-to-reproduce test flakiness — more likely under load (slow CI) where a 20ms sleep window can be exceeded relative to test teardown speed, and outright unsafe if this test target is ever run with parallel test execution enabled (Xcode's "Execute in parallel" option), since these statics are shared across threads with no lock.
**Fix:** Either serialize completion into the calling test (e.g. an `XCTestExpectation` per stubbed request, fulfilled by the responder, that each test explicitly waits on before proceeding to assertions) or make `requestLog`/`responder` instance-scoped per test via a per-test `URLSessionConfiguration` (each test already gets its own `URLSession` from `makeSession()` — route the stub log/responder through the session's config's `protocolClasses` metadata or an associated-object keyed by session rather than a class-wide static).

### P4-WR-005: No test covers the idempotency-key collision between two distinct intents on the same row

**File:** `playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift`, `playstead-mac/PlaysteadTests/CurationTests/OrderingTests.swift`
**Issue:** Every idempotency-related test (`test_retry_sendsTheSameIdempotencyKeyAsTheFirstAttempt`, `test_sameSessionIdentifierPostedTwice_resultsInOneServerSideEffect`) verifies only that *retries of the same enqueued entry* share a key — the intended, correct behavior. None of the reorder/rename tests (`test_moveIntentPayload_namesMovedItemAndTwoNeighboursOnly`, `test_collectionCreateRenameDelete_workOffline`) exercise enqueuing two *different* mutations of the same kind against the same row before the first has been sent, which is exactly the scenario in P4-CR-001. This is a real gap given how central the idempotency-key design is to this module's correctness story.
**Fix:** Add a test that enqueues, e.g., `collectionRename(collectionID, "A")` then `collectionRename(collectionID, "B")` back-to-back (both `pending` before either is sent), drains, and asserts both requests are actually sent with either distinguishable idempotency keys or documents/exercises the current colliding-key behavior explicitly so the gap is visible in CI rather than silent.

### P4-WR-006: `JSONValue.number` stores all JSON numbers as `Double`, risking precision loss for large integers

**File:** `playstead-mac/Playstead/Sync/ChangesClient.swift:12, 24-25, 41`
**Issue:** Every numeric JSON value (regardless of whether the server encoded it as an integer) decodes into `Double`. `Double` cannot exactly represent integers outside roughly ±2^53. If any current or future payload field carries a large integer id or counter as a bare JSON number (rather than as a string, which most ids in this schema already are), round-tripping it through `JSONValue.decoded(as:)` can silently produce an off-by-a-few value. Low current risk given ids in this codebase are strings, but worth flagging since `JSONValue` is a general-purpose decode target used for forward-compatible unknown payload shapes.
**Fix:** Track raw number text (e.g. decode via `NSNumber`/a custom `Decoder` that preserves an `Int` vs `Double` distinction) if any numeric-typed id or count is ever added to a payload this client reads.

### P4-WR-007: `Outbox.enqueue` silently substitutes `"{}"` for a payload that fails UTF-8 encoding, producing an unrecoverable poison entry

**File:** `playstead-mac/Playstead/Sync/Outbox.swift:48-49`
**Issue:** `let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"`. `JSONEncoder` output is always valid UTF-8 in practice, so this fallback is effectively unreachable today — but if it were ever hit, the outbox row would durably persist `"{}"` instead of the real intent, `CurationIntentEnvelope`'s decode would fail (its `kind` field is non-optional), `Outbox.rows()` would produce `intent: nil` for that row, and `OutboxWorker.drainOnce()` would `continue` past it forever (matching the "kind this build doesn't recognise" skip path) — a silent, permanent poison entry with no path to recovery or user-visible surfacing, despite the optimistic local write for that intent having already been applied and now having no corresponding durable record to eventually send.
**Fix:** Throw instead of silently degrading:
```swift
guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
    throw OutboxError.payloadEncodingFailed
}
```

## Info

### P4-IN-001: `test_adapterHostSourceContainsNoSessionStoreReference` is a brittle structural test

**File:** `playstead-mac/PlaysteadTests/CurationTests/PlaySessionTests.swift:208-217`
**Issue:** This test locates `AdapterHost.swift` by walking up three `deletingLastPathComponent()` calls from `#filePath` and then re-descending into `Playstead/Adapter/AdapterHost.swift`. Any future reorganization of the test target's directory depth (e.g. adding a subfolder under `CurationTests/`) silently breaks this test with a `String(contentsOf:)` throw rather than a clear assertion failure describing what changed. It is a reasonable way to enforce "the launch path structurally cannot read the session store" today, but is fragile relative to a symbol-level or module-boundary check.
**Fix:** No action required now; consider replacing with a compile-time check (e.g. a lint rule or a protocol-conformance assertion) if this directory ever gets reorganized and the test starts failing for the wrong reason.

### P4-IN-002: `applyCurationTombstone` always reports "applied" even when nothing was deleted

**File:** `playstead-mac/Playstead/Sync/JournalApplier.swift:171-179`
**Issue:** `applyCurationTombstone` returns `true` unconditionally, so `JournalApplyResult.appliedCount` counts every tombstone entry as "applied" even in the (documented-as-normal) case where none of the six per-table delete attempts actually matched a row (e.g. a tombstone for an id this client never had, arriving out of order relative to its own create). This is intentional/documented and not incorrect, but it does mean `appliedCount`/`skippedCount` are not reliable "how much real work happened" metrics if anything downstream (a status indicator, telemetry) ever consumes them expecting that meaning.
**Fix:** No functional change needed; if `appliedCount` is ever surfaced to users/telemetry as a "changes applied" count, consider tracking a separate "rows actually affected" counter distinct from "entries processed without a hard error."


_Reviewed: 2026-08-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

# Partition P5 — server lib


# Phase 03: Code Review Report (Partition: server-lib)

**Reviewed:** 2026-08-30
**Depth:** standard
**Files Reviewed:** 27 (28 listed in required_reading; router.ex counted once)
**Status:** issues_found

## Summary

Reviewed the blob storage adapter, the curation context (favorites, collections,
queue, continue dismissals, play sessions), the sync snapshot/payload/entity-kind
modules, the blobs/curation/play-sessions/snapshot controllers, the router, and
the Library/Collections LiveViews. Ownership scoping for curation reads/writes is
consistently enforced (every mutation re-verifies `user_id` ownership of the
referenced asset set/collection/queue item before touching a row), and the
blob-serving endpoint correctly gates on the caller's own `source_file` rather
than the hash alone.

The standout finding is a reachable, unauthenticated-by-privilege (but
device-authenticated) denial-of-service: `Playstead.Curation.Position.between/2`
loops forever whenever its two arguments are not in strictly ascending order,
and neither `move_collection_member/4` nor `move_queue_item/3` validate that
the client-supplied `before_asset_set_id`/`after_asset_set_id` neighbours are
actually in that relative order (or distinct) before calling it — a single
crafted `PATCH .../position` request hangs the handling process forever,
holding open a database transaction/connection in the process. The dead,
unused `curation_invalid_position` error code in `PlaysteadWeb.ErrorCodes`
strongly suggests this validation was intended but never wired up.

Several other gaps are documented below: TOCTOU races on the collection/queue
caps, unvalidated client-supplied ids reaching `Repo.get`/`Repo.get_by` (which
raises `Ecto.Query.CastError` rather than returning a clean 404/422), an
unsanitized `sha256` flowing into a raw filesystem path join in the local disk
store, and a controller that silently swallows malformed datetimes instead of
rejecting them.

## Critical Issues

### P5-CR-001: `Position.between/2` infinite-loops on out-of-order or equal neighbours, reachable via the public curation move API (DoS)

**File:** `playstead-server/lib/playstead/curation/position.ex:170-183`
**Also affects:** `playstead-server/lib/playstead/curation.ex:312-338` (`move_collection_member/4`), `playstead-server/lib/playstead/curation.ex:429-454` (`move_queue_item/3`), `playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex:169-194,238-255` (`move_collection_member/2`, `move_queue_item/2`)

**Issue:**

`Position.midpoint/2` (called by `between/2`) computes:

```elixir
defp do_midpoint(low_int, high_int, len) do
  if high_int - low_int >= 2 do
    encode(div(low_int + high_int, 2), len)
  else
    do_midpoint(low_int * @base, high_int * @base, len + 1)
  end
end
```

This assumes its contract ("`low` and `high`, when both given, must be
distinct and `low < high`") always holds. It never enforces or checks it. If
`low_int >= high_int`, `high_int - low_int` is `<= 0` and multiplying both
sides by `@base` every iteration preserves that non-positive difference (or
keeps it at exactly `0` when the two values are equal) forever — the
termination condition `>= 2` can never become true. The recursion is tail
position, so it does not stack-overflow; it simply spins the calling process
at 100% CPU forever, never returning.

Nothing upstream guarantees `low < high`:

- `Curation.move_collection_member/4` resolves `before_pos`/`after_pos` from
  whatever `before_asset_set_id`/`after_asset_set_id` the client supplied
  (`resolve_member_neighbour/2`, curation.ex:730-735) — there is no check that
  the row named by `before_asset_set_id` actually sits earlier in the
  collection's order than the row named by `after_asset_set_id`, nor that the
  two ids are distinct.
- `CurationController.parse_neighbours/1` (curation_controller.ex:288-305)
  only rejects a list-shaped body; it does not reject `before_asset_set_id ==
  after_asset_set_id`, nor validate relative order (the server cannot know
  order from ids alone without querying, which `Curation` does but then
  ignores).
- `Position.needs_rebalance?/2` does **not** protect the call — for
  `low_int >= high_int` it always eventually returns `true` (its own loop
  terminates because it stops growing precision once `len >= 6`), which
  routes the request into `move_collection_member/4`'s rebalance branch. But
  rebalancing preserves relative order (`do_rebalance_collection/2` orders by
  current `position ASC`), so the two neighbours picked by id are *still* in
  the same (wrong) relative order after rebalance, and the code then calls
  `Position.between(before_pos2, after_pos2)` directly with no further
  guard — hitting the same infinite loop.

**Reproduction:** given a collection with members A (position `"3"`) and B
(position `"7"`), a device sends:

```
PATCH /api/v1/curation/collections/:id/members/:asset_set_id_of_C/position
{"before_asset_set_id": "<B>", "after_asset_set_id": "<A>"}
```

(neighbours named in the *wrong* order relative to their actual positions —
trivial for any client to construct, deliberately or by an off-by-one client
bug), or simply:

```
{"before_asset_set_id": "<A>", "after_asset_set_id": "<A>"}
```

(same id twice). Either request hangs the handling process forever inside
`Repo.transaction/1` for the rebalance path (curation.ex:323-333), pinning a
database connection from the pool for the lifetime of the hang. Repeating the
request a handful of times exhausts the Ecto connection pool for every other
tenant of the same server.

Notably, `PlaysteadWeb.ErrorCodes` already registers a
`curation_invalid_position: {422, "Curation Invalid Position"}` code
(error_codes.ex:39) that is never referenced anywhere else in the codebase —
strong evidence this exact validation was planned but never implemented.

**Fix:** Make `Position.between/2` (and `needs_rebalance?/2`) defensive, and
have `Curation` reject invalid neighbour pairs before ever reaching
`Position`:

```elixir
# Playstead.Curation.Position
def between(low, high) when is_binary(low) and is_binary(high) do
  case compare(low, high) do
    :lt -> midpoint(to_digits(low), to_digits(high))
    _ -> raise ArgumentError, "Position.between/2 requires low < high"
  end
end
```

and, more importantly, in `Playstead.Curation`:

```elixir
defp resolve_member_neighbour(collection_id, asset_set_id) do
  # ... existing fetch ...
end

defp validate_neighbour_order(nil, _after_pos), do: :ok
defp validate_neighbour_order(_before_pos, nil), do: :ok
defp validate_neighbour_order(before_pos, after_pos) do
  if before_pos < after_pos do
    :ok
  else
    {:error, {:curation_invalid_position, "Neighbours are not in order."}}
  end
end
```

called from `move_collection_member/4`/`move_queue_item/3` right after both
neighbour positions resolve, wiring the result into the already-registered
`:curation_invalid_position` error code (422) instead of ever calling
`Position.between/2` with unordered or equal bounds.

## Warnings

### P5-WR-001: TOCTOU race on collection/collection-member/queue caps

**File:** `playstead-server/lib/playstead/curation.ex:872-923`
**Issue:** `check_collection_cap/1`, `check_member_cap/2`, and
`check_queue_cap/2` all do a plain `Repo.aggregate(..., :count)` read followed
by a separate `Ecto.Multi.insert` in the caller, with no advisory lock,
`SELECT ... FOR UPDATE`, or DB-level check constraint. Two concurrent requests
from the same user's paired devices (a realistic scenario — the whole point of
multi-device sync) can both read a count just under the cap and both insert,
letting the cap be exceeded by one or more rows. This is a soft limit, not a
security boundary, but it means the documented guarantee ("Returns
`{:error, {:curation_limit_exceeded, _}}` at the N-item cap") is not actually
enforced under concurrency.
**Fix:** Either add a DB check constraint / trigger, or take a
`Repo.transaction` with an explicit per-user advisory lock
(`pg_advisory_xact_lock`) around the count-then-insert sequence for the three
capped resources.

### P5-WR-002: Client-supplied ids reach `Repo.get`/`Repo.get_by` unvalidated, risking `Ecto.Query.CastError` instead of a clean 404/422

**File:** `playstead-server/lib/playstead/curation.ex:700-726` (`verify_asset_set_ownership/2`, `verify_collection_ownership/2`, `fetch_collection_member/2`, `fetch_queue_item/2`), also `curation.ex:96,183,399,517,650` (the various `Repo.get_by(..., id: ..., user_id: ...)` lookups in `remove_favorite/2`, `delete_collection/2`, `dequeue/2`, `delete_play_session/2`, `undismiss_continue/3`)
**Issue:** Every one of these functions passes a raw, attacker-controlled path
segment (`asset_set_id`, `collection_id`, `session_id`, etc. — all
`binary_id`/UUID-typed Ecto fields) straight into `Repo.get/2` or
`Repo.get_by/2` without first validating it is a well-formed UUID. Unlike
`Ecto.Changeset.cast/3`, which returns an invalid changeset on a bad cast,
`Repo.get`/`Repo.get_by` build and execute a query whose value-casting failure
raises `Ecto.Query.CastError` at call time. A request like
`DELETE /api/v1/curation/queue/not-a-uuid` will raise instead of the intended
"not found" outcome. This likely surfaces as a generic 500 problem+json via
the router's `PlaysteadWeb.Plugs.ApiProblemHandler` rescue rather than a
correctness-appropriate 404/422, and depending on that handler's rendering, it
risks including exception details clients should never receive for what is
plain bad input, not a server fault.
**Fix:** Validate the id shape before querying, e.g.:
```elixir
defp verify_asset_set_ownership(user_id, asset_set_id) do
  with {:ok, _} <- Ecto.UUID.cast(asset_set_id),
       %AssetSet{} <- Repo.get_by(AssetSet, id: asset_set_id, user_id: user_id) do
    :ok
  else
    _ -> {:error, :not_found}
  end
end
```
or add a shared helper (`Playstead.Curation.UUID.cast_or_not_found/1`) used at
every one of these call sites.

### P5-WR-003: `LocalDisk.object_path/2` builds a filesystem path directly from an unvalidated `sha256` string

**File:** `playstead-server/lib/playstead/blobs/store/local_disk.ex:455-458`
**Issue:**
```elixir
def object_path(blob_path, sha256) do
  <<a::binary-size(2), b::binary-size(2), _rest::binary>> = sha256
  Path.join([blob_path, "objects", "sha256", a, b, sha256])
end
```
`sha256` is joined into the path in full, unsanitized. Today the only web
caller with a client-controlled `sha256` is `BlobsController`, which first
requires an exact `Repo.exists?` match against a `source_file`/`blob` join
keyed on `sha256` (blobs_controller.ex:68-74) — so in practice a value
containing path-traversal characters (`../`, embedded `/`) can never match a
real row (real values are always 64 lowercase hex characters produced by
hashing) and the request 404s before `object_path/2` is ever reached for an
attacker-chosen string. That said, `object_path/2` is a public function
(`@doc false` only, not `defp`) with no validation of its own, and any future
internal caller (or a change that weakens the current DB-gate-first
discipline) inherits a directory-traversal primitive with no defense in
depth.
**Fix:** Guard the function itself — reject any input that is not exactly 64
lowercase hex characters — rather than relying solely on the caller's DB
lookup to filter shape:
```elixir
def object_path(blob_path, sha256) when byte_size(sha256) == 64 do
  if String.match?(sha256, ~r/\A[0-9a-f]{64}\z/) do
    <<a::binary-size(2), b::binary-size(2), _rest::binary>> = sha256
    Path.join([blob_path, "objects", "sha256", a, b, sha256])
  else
    raise ArgumentError, "invalid sha256"
  end
end
```

### P5-WR-004: `PlaySessionsController` silently discards malformed `started_at`/`ended_at` instead of rejecting them

**File:** `playstead-server/lib/playstead_web/controllers/api/v1/play_sessions_controller.ex:86-93`
**Issue:**
```elixir
defp parse_datetime(str) when is_binary(str) do
  case DateTime.from_iso8601(str) do
    {:ok, dt, _offset} -> dt
    {:error, _reason} -> nil
  end
end
```
A malformed `started_at` (e.g. `"not-a-date"`) is silently converted to
`nil` before it ever reaches `PlaySession.create_changeset/2`. For
`started_at` this happens to still fail via `validate_required/2`, so the
net effect is a validation error either way (though the resulting message
will be a generic "can't be blank" rather than "invalid format", which is
misleading for debugging). For `ended_at` — which is optional — a malformed
value is dropped entirely with **no error at all**: the client believes it
recorded an end time, and the server silently stores `nil`. This masks real
client bugs and produces incorrect session data with no observable signal.
**Fix:** Distinguish "absent" from "malformed":
```elixir
defp parse_datetime(nil), do: {:ok, nil}
defp parse_datetime(str) when is_binary(str) do
  case DateTime.from_iso8601(str) do
    {:ok, dt, _offset} -> {:ok, dt}
    {:error, reason} -> {:error, reason}
  end
end
```
and surface a `422 validation_failed` when either field is present but
unparseable, instead of coercing it to `nil`.

### P5-WR-005: `move_collection_member/4`/`move_queue_item/3` read-then-write positions with no locking, allowing lost updates under concurrent moves

**File:** `playstead-server/lib/playstead/curation.ex:312-338, 429-454`
**Issue:** Both functions read the moved row's and its neighbours' current
`position` values in one query, then (usually) open a **separate**
transaction to write the new position (`reposition_member/3`,
`reposition_queue_item/3`). Two concurrent move requests for the same
collection/queue (plausible: two paired devices reordering the same list, or
a doubly-sent client retry racing itself) can both read the same stale
neighbour positions and both compute/write a position based on that snapshot,
silently discarding whichever write loses the race rather than converging on
a consistent order. This is separate from — and would remain even after
fixing — P5-CR-001.
**Fix:** Wrap the read-resolve-write sequence in a single transaction that
takes a row lock on the collection/queue's rows (e.g.
`Repo.all(query, lock: "FOR UPDATE")` on the relevant `CollectionMember`/
`QueueItem` rows) before computing the new position, so a concurrent mover
blocks until the first transaction commits rather than working from a stale
read.

## Info

### P5-IN-001: `PlaySession.create_changeset/2` never validates `ended_at` is after `started_at`

**File:** `playstead-server/lib/playstead/curation/play_session.ex:29-34`
**Issue:** The changeset only requires `:id`, `:user_id`, `:asset_set_id`,
`:started_at`; nothing prevents `ended_at < started_at` (or `ended_at ==
started_at`), which would corrupt any future duration-based analytics built
on top of "coarse play sessions."
**Fix:** Add `validate_ended_after_started/1` using
`Ecto.Changeset.validate_change/3` when both fields are present.

### P5-IN-002: Dead, unused error code `curation_invalid_position`

**File:** `playstead-server/lib/playstead_web/error_codes.ex:39`
**Issue:** `curation_invalid_position: {422, "Curation Invalid Position"}` is
registered but never referenced by any controller or context function in the
codebase (`grep` confirms zero other occurrences). This is dead
configuration, and — combined with P5-CR-001 — strong evidence the neighbour-
ordering validation it implies was planned but never implemented.
**Fix:** Wire it up as part of fixing P5-CR-001 (see that finding's suggested
fix), or remove it if the validation is intentionally deferred.


_Reviewed: 2026-08-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

# Partition P6 — server tests + migrations, spike toolchain, docs


# Phase 03: Code Review Report (Partition: server-tests-migrations-spike-docs)

**Reviewed:** 2026-08-30
**Depth:** standard
**Files Reviewed:** 39 (`playstead-mac/Playstead.xcodeproj/project.pbxproj` and `playstead-mac/spike/testrom/savetest.gba` were in the partition's stated scope but are generated/binary artifacts — not reviewed, per instructions)
**Status:** issues_found

## Summary

Reviewed three new curation migrations, thirteen Elixir test files plus two test-support modules, the full macOS D-01 spike (Swift probe host, shell orchestration scripts, and the homebrew GBA test ROM toolchain), and four spike/mac docs.

The migrations are internally consistent (binary_id keys for curation rows, correctly typed FKs matching each referenced table's actual key type, sensible unique/lookup indexes for the read paths exercised by the tests). The Elixir test suites are thorough — most curation contexts have real cross-user negative tests, idempotency tests, and property-style ordering tests, not tautologies. The one gap found is a missing authorization negative test on the play-sessions controller.

The most serious finding is in the spike's shell tooling: `acquire-emulator.sh`'s own header comment and the project's `README.md`/`SUPPORT-MATRIX.md` all describe it as "hash-verifying" the downloaded emulator archive, and `SUPPORT-MATRIX.md` even records a pinned SHA-256 for the exact version this script downloads — but the script itself only *computes and prints* the digest; it never compares it against any expected value and never fails if it doesn't match. This is a genuine documentation-contradicts-code gap and a real supply-chain verification hole, distinct from the (correctly handled) quarantine-attribute-preservation logic in the same script.

Also flagged: two schema-integrity assumptions the curation migrations leave entirely to application code (denormalized `user_id` ownership, and fractional-index position uniqueness) with no DB-level backstop; a shell-safety inconsistency in two of the five spike scripts; and a latent (currently dormant) linker/startup-code mismatch in the test ROM toolchain.

## Critical Issues

### P6-CR-001: acquire-emulator.sh claims to hash-verify the download but never checks the hash against anything

**File:** `playstead-mac/spike/scripts/acquire-emulator.sh:36-40, 74-80`
**Issue:** The script's own header comment says: "Downloads an official upstream emulator release, hash-verifies it, and expands it…", and both `playstead-mac/README.md:52-53` ("downloads, hash-verifies, and installs a candidate emulator") and `playstead-mac/docs/SUPPORT-MATRIX.md:14` (which records a pinned digest, `443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c`, for exactly the `mgba 0.10.5` download this script performs) describe hash verification as an actual gate.

In the script itself:
```bash
curl -L --fail --show-error -o "$DL_PATH" "$DOWNLOAD_URL"

echo "==> Computed SHA-256:"
SHA256=$(shasum -a 256 "$DL_PATH" | awk '{print $1}')
echo "$SHA256"
```
`$SHA256` is computed, printed, and later embedded in `acquire-manifest.json` — but it is never compared against the pinned value from `SUPPORT-MATRIX.md` (or any expected-hash argument), and the script proceeds to `hdiutil attach`, extract, and install the `.app` unconditionally regardless of what the computed hash is. A tampered release asset, a compromised GitHub release, or a MITM'd download (curl here has no cert pinning beyond system trust) would be silently accepted, installed under the app-managed emulators directory, and later launched as a real macOS process by `run-probes.sh`/the shipping adapter host. This is precisely the "download without checksum verification" gap the review brief calls out, made worse by the fact that a canonical expected hash already exists in this repository and simply isn't wired in.
**Fix:**
```bash
EXPECTED_SHA256="${3:-}"   # or: look up from a small case/version table, e.g. mgba/0.10.5 -> the SUPPORT-MATRIX.md value

curl -L --fail --show-error -o "$DL_PATH" "$DOWNLOAD_URL"

echo "==> Computed SHA-256:"
SHA256=$(shasum -a 256 "$DL_PATH" | awk '{print $1}')
echo "$SHA256"

if [ -n "$EXPECTED_SHA256" ] && [ "$SHA256" != "$EXPECTED_SHA256" ]; then
  echo "FATAL: SHA-256 mismatch for $ARCHIVE_NAME: expected $EXPECTED_SHA256, got $SHA256" >&2
  rm -f "$DL_PATH"
  exit 1
fi
```
At minimum, require and verify an expected hash argument before `hdiutil attach`/`ditto` run; do not merely log the computed value.

## Warnings

### P6-WR-001: play_sessions_controller_test.exs has no cross-user authorization negative test for DELETE

**File:** `playstead-server/test/playstead_web/controllers/api/v1/play_sessions_controller_test.exs:69-95`
**Issue:** Every other curation controller test file in this partition (`curation_controller_test.exs` for favorites/collections/queue/continue-dismiss) includes an explicit test that acting on another user's resource returns 404/not_found. `play_sessions_controller_test.exs` covers POST-for-another-user's-asset-set (`:50`) but has no equivalent test for `DELETE /api/v1/play-sessions/:id` against a session id owned by a different user. If the controller/context ever regresses to authorizing deletion by session id alone (e.g., a future refactor that looks up by id without also scoping the query by `user_id`), this test suite would not catch it — `Curation.delete_play_session/2`'s cross-user behavior is exercised nowhere at the API layer in this partition.
**Fix:** Add a test analogous to the existing POST negative case:
```elixir
test "DELETE for another user's play session returns 404", %{conn: conn} do
  {_scope, _device, token} = paired()
  other = owner_fixture()
  other_asset = asset_set_fixture(other.id)
  other_session_id = Ecto.UUID.generate()
  # seed the other user's session directly through the context, then:
  resp =
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("idempotency-key", unique_key("del"))
    |> delete(~p"/api/v1/play-sessions/#{other_session_id}")

  assert_problem(resp, 404, :not_found)
end
```

### P6-WR-002: curation migrations denormalize `user_id` with no DB-enforced ownership consistency

**File:** `playstead-server/priv/repo/migrations/20260830000001_create_curation_ordered_lists.exs:19-53`, `playstead-server/priv/repo/migrations/20260830000002_create_curation_play_sessions_and_dismissals.exs:8-37`
**Issue:** `curation_collection_members`, `curation_queue_items`, `curation_play_sessions`, and `curation_continue_dismissals` all carry both a `user_id` and a reference to a resource (`asset_set_id` and/or `collection_id`) that itself belongs to a `user_id`. The schema never enforces that the row's own `user_id` equals the owner of the referenced `asset_set`/`collection` — there is no composite FK, check constraint, or trigger; the invariant is entirely an application-layer contract (correctly tested via `{:error, :not_found}` assertions in `collections_test.exs`, `queue_test.exs`, `continue_test.exs`, `favorites_test.exs`). Any future direct-insert path (a migration-time backfill, an admin script, a different context function) that doesn't replicate that check can silently create curation rows attributing another user's asset/collection to the wrong owner, with the database accepting it happily.
**Fix:** Where the Postgres version in use supports it, add a `CHECK`-style enforcement via a small trigger, or at minimum document the invariant directly on the migration and add a regression test at the schema/changeset level (not just the context function) that a changeset with a mismatched denormalized `user_id` is rejected before insert.

### P6-WR-003: no DB-level uniqueness guard against fractional-index position collisions

**File:** `playstead-server/priv/repo/migrations/20260830000001_create_curation_ordered_lists.exs:17, 36, 53`
**Issue:** `curation_collections`, `curation_collection_members`, and `curation_queue_items` each index `position` (non-unique) but never add a unique index on `(owner_scope, position)` (e.g. `(user_id, position)` for collections/queue, `(collection_id, position)` for members). `position_test.exs` explicitly documents that `Position.between/2` is a pure function of its two bounds — "two requests targeting the identical (low, high) slot… land on the same value" (`playstead-server/test/playstead/curation/position_test.exs:35-52`) — meaning any code path that races two inserts against the same neighbour pair (or any future multi-node/multi-writer deployment, since the current single-owner-server serialization is a documented but purely in-process `ChangeJournal` advisory lock, not a DB constraint) can produce two distinct rows with an identical `position` string. Ordering for such rows becomes ambiguous (tie-broken only by whatever incidental secondary sort Postgres/Ecto happens to apply), with nothing in the schema to prevent or even flag it.
**Fix:** Add `create unique_index(:curation_collections, [:user_id, :position])` (replacing the current non-unique index) and the equivalent for `curation_collection_members` (`[:collection_id, :position]`) and `curation_queue_items` (`[:user_id, :position]`), and have the context's `move`/`add` paths retry with a new `between/2` call on a unique-constraint violation.

### P6-WR-004: run-probes.sh and watch-save.sh omit `set -e`, inconsistent with the rest of the spike

**File:** `playstead-mac/spike/scripts/run-probes.sh:7`, `playstead-mac/spike/scripts/watch-save.sh:7`
**Issue:** `acquire-emulator.sh`, `sign-and-notarize.sh`, and `testrom/build.sh` all use `set -euo pipefail`. `run-probes.sh` and `watch-save.sh` use `set -uo pipefail` — deliberately (or at least silently) omitting `-e`. Without `-e`, a command that fails for a reason not already special-cased with `|| true`/`2>/dev/null` (e.g. `mkdir -p "$OUT_DIR"` failing due to a permissions problem, or `hdiutil`-adjacent tooling failing mid-probe) does not stop the script; it continues on to compute and record a verdict from whatever partial/stale evidence exists, which for a script whose entire purpose is producing pass/fail evidence used to justify a production adapter decision is a meaningful correctness risk. No comment in either file explains why `-e` is intentionally left off (unlike, e.g., the deliberate quarantine-preservation comment in `acquire-emulator.sh`), so a reader can't tell if this is deliberate or an oversight.
**Fix:** Either add `-e` (and audit for the few spots — e.g. the `kill "$pid" 2>/dev/null` lines — that rely on non-zero exits being tolerated, which already use explicit `|| true`/`2>/dev/null`), or add an explicit comment explaining why strict mode is unsafe here.

### P6-WR-005: linker.ld maps `.data` into ROM with no crt0 RAM-copy stub

**File:** `playstead-mac/spike/testrom/linker.ld:14`, `playstead-mac/spike/testrom/crt0.s:1-42`
**Issue:** The linker script places `.data` directly into the `rom` memory region (`.data : { *(.data*) } > rom`), and `crt0.s`'s startup stub does no `.data`-copy-to-RAM or `.bss`-zeroing before branching to `main`. On real GBA hardware, ROM is read-only, so any global with a non-zero initializer placed in `.data` would load its *initial* value correctly (since it's baked into the ROM image) but any write to it at runtime would either be a no-op or fault, since the linker never relocated it to writable IWRAM/EWRAM. `main.c` today happens not to define any writable globals (the only global, `save_type_marker`, is `const` and lands in `.rodata`), so this is currently dormant, but it is a latent, silent-failure trap for the very next person who adds a plain `static int foo;` or a non-const initialized global to this test ROM — exactly the kind of change a future spike iteration (or a copy-pasted derivative) is likely to make.
**Fix:** Either add a minimal `.data`-copy loop in `crt0.s` (copying from a `__data_load_start`/`__data_start`/`__data_end` linker-provided symbol set into IWRAM) and zero `.bss`, or add a load-time-vs-run-time address split in `linker.ld` (`AT>` directive) plus the corresponding copy stub — the standard embedded-crt0 pattern. At minimum, add a comment in both files noting that writable globals are currently unsupported and why.

## Info

### P6-IN-001: fix-header.py has no argument validation

**File:** `playstead-mac/spike/testrom/fix-header.py:7`
**Issue:** `path = sys.argv[1]` will raise an unhandled `IndexError` with a raw Python traceback if the script is invoked with no arguments, rather than a clear usage message. It is only ever invoked from `build.sh` with a fixed argument today, so this is low-risk, but it's inconsistent with the shell scripts in the same directory, which all validate their arguments explicitly (e.g. `${1:?usage: ...}`).
**Fix:**
```python
if len(sys.argv) != 2:
    print("usage: fix-header.py <rom-path>", file=sys.stderr)
    sys.exit(64)
path = sys.argv[1]
```


_Reviewed: 2026-08-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
