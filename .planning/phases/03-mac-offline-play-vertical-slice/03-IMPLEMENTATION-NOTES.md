---
phase: 03-mac-offline-play-vertical-slice
created: 2026-08-31
kind: implementation-notes
status: reference
---

# Phase 03 — Implementation Notes

Agent reports from the post-review hardening session (2026-08-30/31), preserved here because
they record **decisions and root-cause analysis that the code alone does not explain** and
that would be expensive to rediscover. The code-review findings and their fixes are in
`03-REVIEW.md` and `03-REVIEW-FIX.md`; this file holds everything else.

Commit range for the whole session: `c0c8889`..`96064b6` (69 commits).

## Contents

| Section | Covers | Key commits |
|---|---|---|
| Path-traversal security fix | CR-01/CR-02, the throwing-accessor API choice over `URL?` | `56781ec` |
| Curation slice wiring | Composition root, shell navigation, outbox drain triggers | `04f28aa`..`0a9e6a2` |
| Playable loop | Archive/executable digest split, adapter surface, readiness gate | `664d95d`, `ff008c5`, `fd791c6` |
| Pairing | `pair-dev.sh`, TLS decision, Keychain service-match hazard | `42f452f`, `cf325dd` |
| Storage & quota wiring | Quota on the real download path, storage surfaces | `d5bef81`, `cdadc03`, `c42d2a9` |
| Adapter launch hang | macOS security-assessment root cause; quarantine hazard | `7e17165` |

**The single most reusable finding** is in the adapter-launch-hang section: macOS holds a
spawn of an app bundle's main executable pending a security assessment, triggered either by
`Contents/Info.plist` or by the executable's name matching the enclosing `.app`. A binary
that fails assessment is left suspended at `_dyld_start` — `Process.run()` returns success
and `terminationHandler` never fires. This is why a **quarantined** emulator would hang the
Play path silently (tracked as broken window #8).


---

# Path-traversal security fix (CR-01/CR-02)


status: all_fixed
findings_in_scope: 2
fixed: 2
skipped: 0
commit: 56781ec
verified_in: main checkout (~/projects/playstead) — no worktree


### Phase 03: security fix report — CR-01, CR-02 (path traversal)

**Commit:** `56781ec` — `fix(03): CR-01/CR-02 block path traversal from server-supplied member fields` (16 files, +636/-33)

Both findings share one root cause (server-supplied strings used as path
components) and one fix (a single validation module plus guards at both the
ingest and path-construction layers), so they are one atomic commit. Splitting
them would have produced a non-compiling intermediate: `LaunchMaterializer`
(CR-01) consumes the now-throwing `CASManager.objectURL` introduced for CR-02.

### API shape chosen, and why

The review suggested `objectURL(for:) -> URL?`. I chose **throwing accessors**
instead:

```swift
func objectURL(for sha256: String) throws -> URL
func partialURL(for sha256: String) throws -> URL
```

Reasoning:

- **The rejected value travels with the failure.** `PathSafetyError.invalidDigest(String)`
  carries the offending string to whichever layer decides what to do with it —
  a blocker reason, a log line, a propagated error. `URL?` discards exactly the
  information a security event most needs.
- **`Optional` has an unsafe escape hatch; `throws` does not.** A future call
  site can write `paths.objectURL(for: d) ?? someFallbackURL` and silently
  reintroduce a bad path. There is no `??` for `throws`; every site must make a
  visible decision (`try`, `try?` + explicit branch, or propagate).
- **It matches the existing grain.** Six of the eight production call sites were
  already inside `throws` functions (`CASManager.commit`/`remove`,
  `DownloadEngine.attemptDownload`, `LaunchMaterializer.materialize`), so they
  took a bare `try` and no restructuring. Only two are non-throwing, and both
  genuinely want a local decision rather than propagation — see below.

I considered a validated `Digest` value type. Rejected: digests round-trip
through SQLite as raw `String` columns and through `AssetMember.sha256: String?`,
so a `Digest` type would need un/re-wrapping at every persistence boundary —
a much larger, more invasive change for the same guarantee. The allowlist
predicate is the whole of the safety property; a wrapper type only moves *where*
it is enforced.

The migration is complete, not half-done: there is no remaining non-validating
path to `objects/` or `partials/` in the codebase (`grep -rn "objectURL\|partialURL" Playstead`
shows every construction site now flowing through the throwing accessors).

### What changed

### New: `playstead-mac/Playstead/App/PathSafety.swift` (new file, 118 lines)

- `PathSafety.isValidDigest(_:)` / `validatedDigest(_:)` — exactly 64 bytes, each
  in `0-9a-f`. Uppercase is rejected too, because the CAS layout is derived from
  the digest *string*, so two spellings would be two cache objects.
- `PathSafety.isSafeFilename(_:)` / `validatedFilename(_:)` — rejects empty, `.`,
  `..`, anything containing `/` or NUL, anything over 255 UTF-8 bytes, and any
  name whose own `lastPathComponent` differs from itself.
- `PathSafetyError.invalidDigest` / `.unsafeFilename`, `Equatable`, with a
  `description` that truncates the attacker-controlled value to 128 chars before
  it reaches a log.
- `PathSafety.logRejection(_:context:)` — `os.Logger`, `subsystem: dev.playstead.mac`,
  `category: path-safety`.

Both predicates are **allowlists**, not `..`/`/` blocklists. That is deliberate:
an allowlist rules out overlong UTF-8, Unicode separator look-alikes, and
percent-encoding tricks by construction, rather than one blocked sequence at a time.

### Layer 1 — ingest (primary defence)

- `playstead-mac/Playstead/Net/SnapshotClient.swift:32-92` — new
  `extension CatalogueEntry` providing `init(from:)` and
  `static validatedMembers(_:assetSetID:)`. Any member with a non-nil-but-invalid
  `sha256` or non-nil-but-unsafe `name` is dropped and logged.
  Declared in an **extension** so the synthesised memberwise initialiser survives
  for the call sites that build entries locally (`ReadinessEngine:167`, tests).
  This one chokepoint covers **both** server entry points: `SnapshotClient.fetch`
  decodes `/api/v1/snapshot`, and `JournalApplier.applyCatalogue:104` decodes the
  same `CatalogueEntry` shape out of each `/api/v1/changes` journal payload — so
  no separate change to `JournalApplier` was needed.
- `playstead-mac/Playstead/Persistence/CatalogueStore.swift:26-32` — `upsert`
  re-filters through `validatedMembers` before writing `catalogue_members`. This
  is the only chokepoint *every* write passes through, including in-process
  entries, so a hostile value can never be persisted and later read back.

**Drop-and-log, not fail-the-page**: failing the whole decode would let one
malformed member deny service to an entire catalogue. The surrounding entry
survives with its remaining members, so the affected game reads as
not-yet-cached rather than silently launching something the server did not name.
A `nil` field is not a failure — existing consumers already skip members with no
digest or no name.

### Layer 2 — path construction (backstop)

- `playstead-mac/Playstead/App/AppPaths.swift:62-89` — `objectURL(for:)` and
  `partialURL(for:)` now `throws`, validating the digest first.
- `playstead-mac/Playstead/Cache/LaunchMaterializer.swift:44-62` — **CR-01's
  actual site**. `member.declaredName` is validated with
  `PathSafety.validatedFilename` before `appendingPathComponent`, and the digest
  via the throwing `cas.objectURL`. New error case
  `MaterializationError.unsafeMember(declaredName:reason:)` (line 13). Validation
  happens *before* the source-existence check, so an unsafe member fails as
  unsafe rather than as "missing".
- `playstead-mac/Playstead/Cache/CASManager.swift:32-40,56,111` — `objectURL`
  throws; `commit` validates before the `moveItem` destination is built;
  `remove` propagates. `contains(_:)` returns `false` for a malformed digest
  (it can never name a committed object, so absence is the honest answer, not an
  error the caller must handle).
- `playstead-mac/Playstead/Cache/DownloadEngine.swift:119-123,153` — validated at
  the front door of `download(sha256:from:...)`, before the retry loop and before
  any file handling, and again in `attemptDownload` where `partialURL` is built.
- `playstead-mac/Playstead/Cache/PreflightChecker.swift:38-46` — a malformed
  digest becomes an explicit `ReadinessBlocker(reason: "invalid_digest")` rather
  than being conflated with `"missing"`. The two have very different remedies:
  "missing" means re-download, "invalid_digest" means the catalogue itself is
  untrustworthy.
- `playstead-mac/Playstead/Readiness/ReadinessEngine.swift:154-157` —
  `quarantineAndRequeue` returns early on a malformed digest. This also closed a
  second splice at line 162, where `sha256` was interpolated into the quarantine
  destination name.

### Existing tests updated, and why

**Mechanical (`try` added, no assertion weakened) — 16 call sites** across
`DownloadResumeTests`, `AvailabilityStateTests`, `MaterializationTests`,
`EvictionTests`, `ReadinessEngineTests`, `RelaunchTests`. Direct consequence of
the throwing signature; all already sat in `throws` test methods.

**Deliberate contract change — one test:**

`PlaysteadTests/CacheTests/EvictionTests.swift:183-197`
`testQuarantinedPartialsAreListedSeparatelyAndIndividuallyRemovable`

This test called `paths.partialURL(for: "bad-digest")` to obtain a path for a
malformed partial. Under the new contract that call *throws* — `partialURL` is no
longer a path factory for arbitrary strings. I did **not** delete or weaken it.
The behaviour it exercises (a partial on disk whose name is not a valid digest is
still listed by `quarantinedPartials()` and individually removable) is genuinely
worth keeping and is unchanged. I:

1. added `XCTAssertThrowsError(try paths.partialURL(for: "bad-digest"))` asserting
   the new rejection, so the test now pins *both* contracts; and
2. created the fixture file via a direct, test-local
   `paths.partials.appendingPathComponent("bad-digest")` — the test is simulating
   a bad file that already exists on disk (e.g. from an older build), which is
   exactly the case quarantine listing must still handle.

No other existing assertion was changed. No existing test encoded the unsafe
behaviour as *desired*.

### Tests added

`playstead-mac/PlaysteadTests/SecurityTests/PathTraversalTests.swift` (new, 16 cases).

The fixture places the `AppPaths` root as a **child** of the temp dir
(`tempRoot/cache`), so a successful `../` escape has somewhere observable to
land. `filesystemSnapshot()` + `assertNothingCreatedOutside(_:before:)` diff the
full recursive listing of `tempRoot` before and after each operation and fail if
anything appears outside the allowed root — i.e. the assertions are on the
**filesystem outcome**, not on a return value. Each materialization test seeds a
real committed CAS object first, so the traversal is blocked by the destination
guard and not incidentally by a missing source.

CR-01:
- `testMaterializeRejectsTraversalDeclaredNameAndWritesNothingOutsideLaunchDirectory`
  — `name: "../../../../evil.txt"`; asserts the throw, that nothing was created
  outside `paths.launch`, that `tempRoot/evil.txt` does not exist, and that the
  launch directory is empty.
- `testMaterializeRejectsDeclaredNameContainingSeparator` — `"nested/evil.txt"`.
- `testMaterializeRejectsDotAndEmptyDeclaredNames` — `""`, `"."`, `".."`, `"a/../../b"`.
- `testMaterializeAcceptsOrdinaryFilename` — negative control; a real ROM name
  with spaces and parentheses still materializes.

CR-02 (nine malformed digests: traversal, `..`, separator, non-hex, 63 chars,
65 chars, uppercase, non-hex letters, empty):
- `testObjectAndPartialURLRejectEveryMalformedDigest`
- `testObjectAndPartialURLAcceptAWellFormedDigest` — negative control; asserts the
  exact `objects/01/23/<digest>` shard layout is preserved.
- `testCommitWithTraversalDigestWritesNothingOutsideObjectsDirectory` — asserts
  nothing outside `paths.root`, `tempRoot/evil` absent, **and** the unverified
  partial still in place (refused, not moved).
- `testCASContainsAndRemoveAreSafeForMalformedDigests`
- `testPreflightReportsMalformedDigestAsAnExplicitBlocker`
- `testDownloadEngineRefusesAMalformedDigestBeforeTouchingDisk`

Ingest:
- `testDecodingDropsMembersWithATraversalName`, `...WithASeparatorInTheName`,
  `...WithAMalformedDigest`, `testDecodingKeepsWellFormedMembers`
- `testCatalogueStoreDropsUnsafeMembersOnUpsert` — three members in, only the
  clean one persisted.
- `testHostileCatalogueEntryCannotProduceAnOutOfTreeWrite` — end to end: hostile
  server JSON decoded, persisted, read back, and fed to `LaunchMaterializer`;
  asserts the member never survived ingest **and** that nothing landed outside
  `paths.launch`.

### Verification

Run in the main checkout at `~/projects/playstead/playstead-mac` (not an
isolated worktree — the task pinned that absolute path for verification, and the
build needs the project's real DerivedData/toolchain context; no concurrent
writer was active).

```
cd ~/projects/playstead/playstead-mac && \
  xcodebuild -project Playstead.xcodeproj -scheme Playstead \
    -destination 'platform=macOS' test
...
Test session results, code coverage, and logs:
	~/Library/Developer/Xcode/DerivedData/Playstead-.../Logs/Test/Test-Playstead-2026.08.31_01-44-39--0400.xcresult

** TEST SUCCEEDED **
```

- Test cases executed: **221** (205 pre-existing + 16 new). Failures: **0**
  (`grep -cE "' failed"` → 0).
- `** BUILD SUCCEEDED **` for the app target; `** TEST BUILD SUCCEEDED **` with
  zero warnings introduced.
- Staged only the 16 source/test files listed above. `.gitignore`,
  `.planning/`, and `.gsd/` were left untouched with their pre-existing
  uncommitted user changes intact (confirmed via `git status --short` after commit).

### Adjacent observation (not fixed, out of scope)

`playstead-mac/Playstead/Adapter/BiosStore.swift:186` —
`managedPath(forSHA256:)` splices a digest into a path component with no format
check, structurally identical to CR-02. It is **not** currently exploitable: that
digest is computed locally by `BiosStore.hashFile` from a user-dropped file, never
supplied by the server. Worth hardening with the same `PathSafety.validatedDigest`
call if that value ever becomes server-influenced, but changing it now was outside
the two findings in scope.

---

# Curation slice wiring

### Wiring the Phase 3 curation slice into the shipped macOS app

Resolves review finding **P4-WR-003** (`Outbox`/`OutboxWorker`/`SyncEngine` had no
production call site) and the `03-VERIFICATION.md` WR-01 ordering bug.

### Commits (branch `main`, repo `~/projects/playstead`)

| Hash | Subject |
|------|---------|
| `04f28aa` | `fix(03): stop the outbox drain on a local persistence failure` |
| `ac7ab17` | `feat(03): construct the curation/sync layer in the app's composition root` |
| `961156b` | `feat(03): make the curation shelves reachable from the library shell` |
| `0a9e6a2` | `feat(03): test the curation slice through the assembled app, not in isolation` |

Only source files were staged. `.planning/`, `.gsd/`, and the root `.gitignore`
were left untouched (their pre-existing uncommitted changes are still present).

### What was wired

### Composition root — `~/projects/playstead/playstead-mac/Playstead/App/PlaysteadApp.swift`

`AppEnvironment` now constructs, once, exactly mirroring the existing
`localStore`/`casManager`/`controllerMappingStore` pattern:

`catalogueStore`, `curationStore`, `cursorStore`, `outbox`, `syncEngine`,
`outboxWorker`, `drainTrigger`, `playSessionRecorder`, `reachability`, plus the six
view models (`libraryViewModel`, `favoritesViewModel`, `queueViewModel`,
`collectionsViewModel`, `continueViewModel`, `recentViewModel`) — each receiving the
shared store/outbox instances, never building their own.

Also added there: `toggleFavorite(assetSetID:)`, `toggleQueued(assetSetID:)`,
`refreshCurationViewModels()`, `applicationDidBecomeActive()`, `drainOutbox()`,
and `syncNow()`.

**Drain triggers (all three, per the task):**
1. after every `Outbox.enqueue` — via a new `Outbox.onEnqueue` hook;
2. on reachability regained — registered through `Reachability.onChange`, keeping the
   returned `UUID` token and calling `removeObserver(_:)` in `deinit`;
3. on `scenePhase == .active` — `PlaysteadApp` observes it and calls
   `applicationDidBecomeActive()`.

**`OutboxWorker` callbacks**, wired as its own doc comments specify:
`onEntryDelivered` → `PlaySessionRecorder.markDelivered(_:)` for a delivered
`.playSessionRecord`; `onDestructiveRejection` → `SyncEngine.forceFullResync()`.

**Sync sequencing:** `AppEnvironment.syncNow()` is a single `await`-ordered
function. `SnapshotClient` runs only when the mirror is empty *and* no cursor is
stored; otherwise `SyncEngine.syncNow()` resumes from its cursor. The two paths are
mutually exclusive by construction and cannot run concurrently against the same
stores. The state converges after one bootstrap: `SnapshotClient` populates the
catalogue, so the next pass takes the `SyncEngine` branch and commits a cursor
(asserted by `testFirstSyncBootstrapsFromSnapshotThenSyncEngineTakesOver`).

### Navigation — `~/projects/playstead/playstead-mac/Playstead/Library/LibraryShellView.swift`

Replaced the 57-line tracer stub with a `NavigationSplitView`:

- sidebar: `SidebarView`, fed `nonEmptySystemIDs` / `hasUnidentified` from the real
  catalogue via `libraryViewModel`;
- `.home` → the existing `List(entries) { GameRowView(entry:) }`, unchanged;
- `.continuePlaying` / `.favorites` / `.queue` / `.recent` → the existing shelf views,
  over `AppEnvironment`'s shared view models;
- `.collections` → `CollectionsView` beside `CollectionDetailView` in an `HSplitView`;
- `.system(id)` → `LibraryViewModel.catalogue(forSystemID:)`, which goes through the
  same `CatalogueStore.filteredQuery` path the filter chips use (pinned by
  `FilterTests`) — not a reimplementation;
- `.unidentified` → `LibraryViewModel.unidentifiedCatalogue`.

`LibraryShellView.title(for:)` is a pure static so a test can assert every section
routes to a titled surface rather than a blank pane.

### Mutation affordances — `Playstead/Library/GameRowView.swift`

Rows gained **Favorite** and **Add to Queue** buttons (with the verb-plus-subject
accessible names the UI spec's QUAL-01 floor requires, exposed as pure statics
`favoriteActionLabel`/`queueActionLabel`). Without these there is no way to
*perform* a curation mutation from the shell, so the outbox would still be
unreachable in practice. `play()` now calls `PlaySessionRecorder.began`/`ended`
around the launch, so Recent and Continue have data (the recorder swallows its own
failures, so it cannot make a launch fail).

### API changes I had to make, and why

1. **`Outbox` is no longer `final`, and gained `var onEnqueue: (@Sendable () -> Void)?`.**
   The hook is what makes "drain after every enqueue" a property of the outbox
   rather than a call-site convention that every future view model has to remember —
   a call-site convention is precisely what left this feature unreachable. Dropping
   `final` also lets the ordering regression test substitute a subclass whose
   `markInFlight` fails.

2. **New file `Playstead/Sync/OutboxDrainTrigger.swift`.** A small `Sendable` handle
   around `OutboxWorker`. The trigger closures are `@Sendable`, so capturing the
   `@MainActor` `AppEnvironment` would be a concurrency violation; they capture this
   instead. It also exposes `drainCount` / `awaitPending()`, which is how a test can
   assert the worker is genuinely running rather than merely constructed.

3. **`AppEnvironment.init` gained `paths` / `apiClient` / `reachability` parameters,
   all defaulted.** Production still calls `AppEnvironment()` and gets exactly what
   it did before; the parameters exist so a test can assemble the *real* composition
   root headlessly (temp directory, `StubURLProtocol`, hand-driven `Reachability`).
   `reachabilityToken` is a `nonisolated let` so `deinit` can read it.

4. **`CollectionsView` gained an optional `selectedCollectionID: Binding<String?>`,
   defaulted to `.constant(nil)`** via an explicit `init`. The shell's detail pane
   lives outside the view, so the selection had to be published; the default keeps
   every existing call site and test compiling and behaving as a plain list.

5. **`LibraryViewModel` gained `isUnidentified(_:)` (static), `unidentifiedCatalogue`,
   and `catalogue(forSystemID:)`.** Additive. `hasUnidentifiedEntries` now uses the
   shared predicate so the sidebar's "does this section exist" and the section's
   "what does it list" cannot drift.

No server (Elixir) code was touched.

### The WR-01 ordering bug

`OutboxWorker.drainOnce` used to `continue` when `outbox.markInFlight(entry.id)`
threw, which sent a *later* curation intent ahead of an earlier one still pending.
It now sets `result.stoppedForRetry = true` and returns, leaving both entries
`pending` in creation order for the next pass.

Regression test: `OutboxTests.testLocalPersistenceFailureStopsTheDrainInsteadOfSkippingAhead`
— two enqueued entries, `markInFlight` fails for the first, and the test asserts
`StubURLProtocol.requestLog.count == 0` (the second never goes out) and that both
entries are still pending.

Note, deliberately left alone: the earlier `continue` for an entry whose `kind` this
build does not recognise (`entry.intent == nil`). That is the documented
forward-compatibility posture — this build *cannot* send such an entry at all, and
stopping there permanently would wedge the outbox. It is not the flagged defect.

### New tests — `PlaysteadTests/CurationTests/ShellWiringTests.swift`

Constructs the real `AppEnvironment` (not hand-built components) and drives only the
paths the UI drives:

- `testFavoritingThroughTheShellReachesTheEnvironmentsOutbox`
- `testQueueingThroughTheShellReachesTheEnvironmentsOutbox`
- `testEveryCurationViewModelSharesOneStoreAndOneOutbox`
- `testEnqueueTriggersTheOutboxWorker` — asserts the entry is actually *sent*, and one
  HTTP request was made
- `testReachabilityRegainedTriggersTheOutboxWorker`
- `testBecomingActiveTriggersTheOutboxWorker`
- `testDeliveredPlaySessionIsMarkedDeliveredThroughTheWiredCallback`
- `testEverySidebarSectionRoutesToATitledSurface`
- `testSystemAndUnidentifiedSectionsFilterTheRealCatalogue`
- `testFirstSyncBootstrapsFromSnapshotThenSyncEngineTakesOver`

Plus `OutboxTests.testLocalPersistenceFailureStopsTheDrainInsteadOfSkippingAhead`.

### Verification

```
cd ~/projects/playstead/playstead-mac && \
  xcodebuild -project Playstead.xcodeproj -scheme Playstead \
  -destination 'platform=macOS' test
```
→ `** TEST SUCCEEDED **`, 205 test cases passed, 0 failures.
Clean build with no warnings.

Elixir suite not run — no server code was touched.

### Nothing blocked

Everything in the task was assembled. Two honest limitations worth recording, neither
a stub:

- `Home` renders the flat catalogue list (per the task's explicit instruction), not
  the UI spec's stacked-shelf Home. That is a deliberate scope boundary, not a gap
  in this work.
- Shelf views render titles as `Text` rather than `GameCardView` tiles; that is how
  those views were already written in plan 03-06/03-08 and I did not rewrite them.

---

# Playable loop — digest, adapter surface, readiness gate

### Playable loop — three launch-path blockers fixed

Verification: `xcodebuild -project Playstead.xcodeproj -scheme Playstead -destination 'platform=macOS' test`
→ `** TEST SUCCEEDED **`, 231 cases passed (baseline was 221; 10 new, all in `AdapterWiringTests`).
No existing assertion was weakened; three existing assertions changed only where the
digest *semantics* they encoded were the bug (detailed below).

### Commits

| Hash | Subject |
|---|---|
| `664d95d` | fix(03): separate archive and executable digests so launch verification can pass |
| `ff008c5` | feat(03): give the shipped app a real adapter install surface |
| `fd791c6` | fix(03): gate Play on the real ReadinessEngine instead of a bare cache check |

Only source files were staged. `.planning/`, `.gsd/` and the root `.gitignore` were not
touched and still carry their pre-existing uncommitted changes.

### Blocker 1 — the digest-field design

**The defect.** `AdapterPin.sha256` is the digest of the published `.dmg`.
`AdapterInstaller.install()` recorded that archive digest as the installation's `sha256`,
and `AdapterHost.reverifyLiveDigest` hashed `Contents/MacOS/mGBA` and compared it to
`pin.sha256`. Different byte streams — the comparison could never succeed, so every launch
threw `LaunchError.digestMismatch`. `selectExisting()` made the mirror-image error: it
hashed the *executable* and compared it to the *archive* digest, so it always recorded
`verified: false`, which `verifyInstalledDigest` rejects up front.

**The design chosen.** Two facts, two distinctly named fields, on both
`AdapterInstallation` and the on-disk `InstallVerifyRecord`, plus a third field naming how
the installation got here:

- `archiveSHA256: String?` — the downloaded release archive's digest. This is the **only**
  value ever compared against `AdapterPin.sha256`, and that comparison stays exactly where
  it was: in `install()`, before anything is expanded. `nil` for a user-selected install,
  which never had an archive.
- `executableSHA256: String` — the expanded executable's own digest, computed after
  expansion (or of the selected binary), recorded at install/select time.
  `verifyInstalledDigest()` re-hashes the live file and compares against **this**.
- `provenance: .pinnedRelease | .userSelected` — how the installation was acquired.

`reverifyLiveDigest(at:expected:)` now takes the expected digest as a parameter rather
than reaching for `pin.sha256`, which is what made the category error possible.

**Why this shape.** P2-CR-001's property is preserved exactly: launch genuinely re-hashes
the binary on every attempt and never trusts a cached boolean — only the value it compares
against changed, from the archive digest to the recorded executable digest. The
supply-chain check is unchanged and still happens at the one moment the archive exists.
The downloaded-install fallback path additionally re-asserts `record.archiveSHA256 ==
pin.sha256` before re-hashing, so the pin check survives a restart.

**Why `verified` was re-meant rather than kept.** `verified` used to mean "the recorded
digest equals `pin.sha256`", which for `selectExisting` was an unsatisfiable comparison.
It now means "this installation carries a usable integrity baseline". Whether a build *is*
the pinned release is `provenance`'s job, and `AdapterCapabilityCard` renders it:
a user-selected build reads "Installed, but unverified against the pinned release … Support
claims for the pinned build may not apply." The pre-existing test asserting the card says
"unverified" for a selected foreign build still passes, and I strengthened it with
`XCTAssertFalse(… contains("matches the pinned release"))`.

`AdapterPin.json` is unchanged. Adding a pinned *executable* digest to it was considered
and rejected: I have no mGBA 0.10.5 binary here to hash, and inventing that value would be
exactly the kind of decoration this task exists to remove.

**Schema.** `adapter_installations` gains `archive_sha256 TEXT` (NULL for user-selected)
and `provenance TEXT NOT NULL DEFAULT 'pinnedRelease'`, added via idempotent `ALTER`s
alongside the `CREATE TABLE`, matching the file's existing convention. The `sha256` column
now unambiguously holds the executable digest. An `.install-verify.json` written by an
older build fails to decode and is treated as unrecorded — fail-closed, forcing a
reinstall rather than trusting an ambiguous digest.

### Blocker 2 — a real adapter surface

New `Playstead/Adapter/AdapterSetupView.swift`, reachable from `LibraryShellView`'s
toolbar ("Adapter") and inline from a readiness sheet's *Install adapter* remedy. It
presents the existing, already-tested `AdapterCapabilityCard` (which was rendered
nowhere) and offers both acquisition paths — install the pinned release, or choose an
application bundle already on this Mac (`NSOpenPanel`, injectable for tests, mirroring
`BiosDropTargetView.chooseFile`).

State is honest and covers all four cases: not installed / installing / installed with the
digest re-checked on every launch / failed **with the actual reason** — digest mismatch
(naming both digests), download failure, unpack failure, or "that application does not
contain the expected program file". `AdapterSetupView.statusText` and
`AppEnvironment.describeInstallFailure` are pure and asserted directly.

`AppEnvironment` now owns the shared `AdapterCatalog` and `AdapterInstaller`, restores a
previously recorded installation on cold start (`AdapterInstaller.recordedInstallation`,
a `nonisolated` local read so the composition root can do it synchronously), and hands
every install/select result to the same `AdapterHost` the launch path uses, via a new
`AdapterHost.setInstallation(_:)` that records both the path and the executable-digest
baseline. `setInstallState(_:)` is kept and now clears the baseline, so a state handed over
without one fails closed rather than launching unverified bytes.

I read `spike/scripts/acquire-emulator.sh` for the real mechanics (pinned DMG, SHA-256
`443b490e…`, `ditto` into `emulators/mgba/0.10.5/`); the shipped code depends on nothing
in `spike/` — `AdapterInstaller.defaultExpand` already implements the same
mount/`ditto`/detach sequence.

### Blocker 3 — Play actually runs the readiness checks

`AppEnvironment.readinessReport(for:)` builds a real `ReadinessEngine` (shared
`CASManager`, a now-shared `DownloadQueue`, live adapter install state, the pin's
`biosRequired`, `BiosStore`, `ControllerHost`) and evaluates the six checks.
`GameRowView.refreshStatus()` and `play()` both route through it:

- ready → Play
- gameAssets blocking → Download (D-17: expose the action actually available)
- anything else blocking → a "What's needed" action opening `ReadinessSheetView`

`ReadinessSheetView` renders the existing `ReadinessReportView` and routes each remedy to
a surface that resolves it: `.installAdapter` → `AdapterSetupView`, `.openBiosDropTarget`
→ `BiosDropTargetView`, `.openInputSettings` → `ControllerSettingsView`,
`.repairSaveDirectory` → a real recreate-and-recheck, `.downloadMember` → the row's
download. `play()` re-evaluates before materializing anything and shows the report instead
of the old `"Launch failed: …"` string. For GBA `biosRequired == false`, so an absent BIOS
returns ready (asserted).

All engine dependencies are captured by value per evaluation, so a synchronous, entirely
local check never hops actors. No network call was added — `ReadinessEngine` is
constructed with the same local-only dependencies, and one new test fails the run if the
readiness path issues any request.

### Security posture

Kept. The asset set id is server-supplied and `GameRowView` previously spliced it straight
into the save path; it now goes through `AppEnvironment.saveDirectoryURL(forAssetSetID:)`,
which calls `PathSafety.validatedFilename` and throws. A test asserts
`"../../etc/evil"` is refused. No new unvalidated path-component splice was added
anywhere; the installer's own paths come from the pin, not from the server.

### Tests added (all against the real assembled `AppEnvironment`)

`PlaysteadTests/AdapterTests/AdapterWiringTests.swift`, following `ShellWiringTests`:

1. Selecting an adapter through the environment → the state reaches the shared
   `AdapterHost`, `verifyInstalledDigest()` succeeds, and a real process launches and exits.
2. Changing the installed executable after install → launch refuses with a
   `digestMismatch` naming the new digest (proves re-verification is still genuine).
3. `install()` with a stubbed archive → archive digest matches the pin, executable digest
   differs from it, and a real `AdapterHost` handed that installation verifies and launches.
4. A recorded installation is restored by a freshly assembled environment, with no network.
5. Files cached but no emulator → report is blocked, the emulator check carries an
   `.installAdapter` remedy, every blocking check has a remedy, and the row shows the
   blocker rather than Play. Any network request fails the test.
6. Installing through the environment clears the blocker; BIOS stays ready.
7. Missing files keep the row on Download.
8. The surface's four states and the real failure reason.
9. The capability card from the environment does not restate pinned support for a
   user-selected build.
10. `saveDirectoryURL` refuses an unsafe asset set id.

Three pre-existing tests were updated where they encoded the broken semantics, and were
strengthened rather than relaxed: `InstallerTests`' select test now asserts provenance, a
nil archive digest, the exact recorded executable digest, and that the card does **not**
claim a pinned match; `AdapterPinTests` and `PlaySessionTests` construct
`InstallVerifyRecord` with the two named fields.

One test tolerance was raised, not an assertion: the first execution of a freshly written
binary in a test process pays a one-off system security-assessment cost (~4 s measured,
over 5 s under parallel bundles), so the two launch expectations use a 60 s ceiling. Every
subsequent launch in the same process completes in well under a second.

### Still blocking a real local launch on the owner's Mac

1. **The pinned adapter has never actually been downloaded and installed here.** The
   install path is wired and its digest chain is proven against a stubbed archive, but
   `install()` against the real pin needs the 100MB+ published DMG and network access,
   which this environment does not have. The first real run is the owner clicking
   *Install the pinned adapter*; if the published artifact's digest has drifted from
   `443b490e…`, it will refuse with a named expected/actual pair rather than install
   something unverified. That refusal would be correct behaviour, but it is untested
   against the live artifact.
2. **A real GBA ROM has never been launched.** Every launch proven here uses `/bin/echo`
   standing in for the emulator. Nothing in the emulator's own runtime behaviour (window,
   input, SRAM flush) is exercised by this work.
3. **BIOS validation remains inert** — `BiosStore` still has no production reference
   digests (`references: []` at the composition root), so it correctly rejects every
   dropped file. This is unchanged by this task and does not block GBA launch
   (`biosRequired == false`), but the drop target reachable from a readiness remedy will
   reject real BIOS files until a sourced reference digest is wired. Left visibly
   unfinished rather than papered over.
4. **Controller mapping keys are still unproven** (`config_injection.keys.controller_mapping`
   is `not_probed_no_hardware_available`) and **the build is dev-signed, not notarized** —
   both pre-existing, disclosed deferrals, untouched here.
5. `AdapterSetupView` deliberately does **not** present the BIOS drop target, since that
   control cannot currently accept anything; it is reachable only from the readiness
   remedy that would genuinely require it.

---

# Pairing — script, TLS, Keychain hazard

### Pairing — delivered

### Commits

| Hash | Commit |
|---|---|
| `42f452f` | `feat(03): add dev pairing script for the Mac app` |
| `cf325dd` | `docs(03): add local-dev runbook from clean machine to launched game` |

Two new files, nothing else staged. `.planning/`, `.gsd/`, and the root
`.gitignore` were not touched. **No Swift source was modified**, so the 231-case
suite is untouched and did not need re-running.

- `~/projects/playstead/playstead-mac/scripts/pair-dev.sh`
- `~/projects/playstead/playstead-mac/docs/LOCAL-DEV.md`

### It was proven end to end, not just written

I brought up a real dev server (local Postgres was already running, `mix setup`
succeeded with zero configured secrets) and ran the actual ceremony twice:

```
Paired as device 743de594-… (credential fingerprint 06550521).
Credential stored in the login Keychain (service dev.playstead.mac, account 743de594-…).
Authenticated request to /api/v1/devices/me returned HTTP 200.
SCRIPT_EXIT=0
```

Second run, proving idempotency:

```
Removed 1 previously stored credential(s).
Paired as device 560cd7e3-… (credential fingerprint db0b01ba).
Authenticated request to /api/v1/devices/me returned HTTP 200.
```

Exactly one Keychain item remained afterward. The unreachable-server path was
also exercised and produces the intended guidance. `bash -n` is clean.

I verified the Keychain shape two ways: a Swift snippet replicating
`loadCredential()`'s exact query decoded the item into a `PairingCredential`
correctly (account, token, and `CredentialEnvelope.baseURL`), and
`security find-generic-password -g` shows
`"gena"<blob>="{"baseURL": "http://127.0.0.1:4000"}"`.

`security add-generic-password` turned out to be fully sufficient — **no Swift
`SecItemAdd` shim was needed**. `-G` sets `kSecAttrGeneric` as bytes that
`JSONDecoder` reads back cleanly.

### Corrections to your notes

1. **`/library/reference-packs` does not exist.** The route is top-level
   **`/reference-packs`** (its own `live_session`). Nav and `library_live.ex`
   both use `~p"/reference-packs"`. Documented correctly.

2. **The TLS wrinkle is already solved in-tree — your note is out of date.**
   `Playstead/App/Info.plist` *already carries* an `NSAppTransportSecurity`
   exception for `localhost` and `127.0.0.1`
   (`NSExceptionAllowsInsecureHTTPLoads`, `NSIncludesSubdomains` false), with a
   comment saying it exists precisely so the paired-device client can reach a
   plain-HTTP local dev server. ATS does **not** block the local run. This is
   why I chose loopback HTTP (below) — it needed no new work at all.

3. **A real duplicate-credential hazard you did not flag, and the reason
   "idempotent" needed more than `-U`.** `loadCredential()` queries by *service
   alone* with `kSecMatchLimitOne` and **no account predicate**. Every pairing
   returns a *new* `device_id`, i.e. a new account. `security ... -U` only
   updates same-account items, so a naive re-run leaves two items on the service
   and `loadCredential` picks an arbitrary one — I reproduced this: after adding
   a second account, the read returned the **stale** first credential. The
   script therefore purges every item on the service in a loop before writing.
   Worth knowing when the real in-app pairing UI is built: `storeCredential`
   has the same latent issue, since its `SecItemUpdate` match query is also
   account-scoped.

4. **Minor:** there is no checked-in `.xcscheme`; `Playstead` is Xcode's
   autocreated implicit scheme. It works, but `xcshareddata/` does not exist.
   The repo README documents `xcodebuild build -scheme …` (verb first); I used
   that form.

5. **Dev-path gotcha not in your notes:** `config/runtime.exs` runs in dev too,
   so `:inbox_path` defaults to the *container* path `/app/inbox`, which does
   not exist on a Mac. `Inbox.scan/1` returns empty for a missing root, so
   "Preview inbox folder" silently reports `0 files, 0 bytes`. The runbook has
   the owner export `PLAYSTEAD_INBOX_PATH`/`PLAYSTEAD_EXPORT_PATH`.

6. Confirmed true: `kSecClassGenericPassword` / `dev.playstead.mac` / account =
   `device_id` / password = credential / `kSecAttrGeneric` = `{"baseURL": …}`;
   the four-step ceremony and its response fields; the 10-min TTL and 5s poll
   interval; `.zip`/`.7z`/`.rar` as opaque blobs (magic-byte detection, not
   extension); `biosRequired == false` for GBA; the mGBA 0.10.5 pin URL and
   sha256.

### TLS approach chosen: plain HTTP on loopback (`http://127.0.0.1:4000`)

The dev server binds `127.0.0.1:4000` over plain HTTP, ATS already permits it
(see correction 2), and `curl` needs no trust configuration. So the script
defaults to it and the runbook recommends the native `mix` path over Docker.

I rejected the alternatives deliberately: writing `pinned-ca.der` would mean
inventing a capture format for a file no shipping code writes yet, and trusting
Caddy's internal root in the System keychain is an invasive machine-wide change
for a purely local run. Certificate pinning is a later phase's job; the runbook
says so and explains that the Docker/Caddy path *will* fail at the first request
until its root is trusted.

I also recommended the `mix` path over Docker for a second, independent reason:
it needs **no generated secrets at all** (`config/dev.exs` hardcodes
`secret_key_base`; every secret guard is behind `if config_env() == :prod`),
whereas Docker requires generating and pasting `SECRET_KEY_BASE` and
`POSTGRES_PASSWORD` before anything boots. Note this native path was previously
**undocumented anywhere** — `playstead-server/README.md` is a 9-line stub — so
the runbook is the first place it is written down. I derived it from config and
then confirmed it by actually booting.

### What the owner must still do by hand

1. **Provide a local PostgreSQL** on `localhost:5432` as `postgres`/`postgres`.
   The compose `db` service has no published port and does not serve the dev
   path.
2. **Run the `/setup` wizard** and save the recovery codes (shown once).
   Caveat: my test DB already had owners from a prior tracer run, so the setup
   banner did not print for me — on a genuinely clean DB it does. `mix ecto.reset`
   if `/setup` 404s.
3. **Unzip ROMs before importing.** Nothing automates this.
4. **Click Approve at `/devices`** during the pairing script's 10-minute window,
   after checking the code matches. This is the one genuinely manual step in the
   ceremony, and deliberately so (D-07 forbids auto-approval).
5. **Possibly click "Always Allow"** on a Keychain access dialog the first time
   the app reads the credential. The script writes with `-A` (null ACL) to avoid
   this, but I could not fully confirm app-side behavior — see below.
6. Everything under "What is still unproven" in the runbook: the real mGBA DMG
   download, launching an actual ROM, and controller hardware.

### Caveats on my own verification

- **The app itself was never launched against this credential.** I verified the
  Keychain item is readable by a Swift program using `loadCredential()`'s exact
  query, and that the token authenticates (HTTP 200). I did not build and run
  the app.
- Late in testing, `SecItemCopyMatching` from a freshly compiled unsigned Swift
  binary began hanging — including on a probe item that had read fine minutes
  earlier — which I attribute to a queued GUI Keychain prompt in this headless
  session rather than to the item. The `security` CLI kept reading it fine. The
  earlier successful decode is the real evidence; flagging it because it is the
  most likely place the owner hits an unexpected dialog.
- I left behind, deliberately: a **working credential** in the login Keychain
  for device `560cd7e3-…`, and two test devices plus some pairing rows in the
  `playstead_dev` database. The owner can revoke the stale ones at `/devices`.
  The dev server I started has been stopped.

---

# Storage and quota wiring

### Storage / download-management wiring

### Commits (all Swift-only, under `playstead-mac/`)

| Hash | Title |
|---|---|
| `d5bef81` | feat(03): enforce the cache quota on the real download path |
| `cdadc03` | feat(03): reach the downloads and storage surfaces from the library shell |
| `c42d2a9` | fix(03): surface the queue path's blocked-capacity reason |

`.planning/`, `.gsd/` and the root `.gitignore` were never staged; their pre-existing
uncommitted changes are untouched. No `git add -A`, no `git commit -a`.

### Inherited vs. added

**Inherited** (the interrupted agent's uncommitted work, kept — it was coherent and built):

- `DownloadCoordinator`, `QuotaManager`, `PinStore`, `EvictionPlanner` constructed as
  shared instances on `AppEnvironment`.
- `AppEnvironment` helpers: `pendingDownloadBytes`, `quotaVerdict(forDownloading:)`,
  `canRaiseQuota`, `raiseQuota(toCover:)`, `setQuota`, `storageSnapshot`,
  `reclaimCandidateRows`, `reclaim(gameIDs:)`, `togglePin`, `downloadRows`, the
  queue pause/resume/cancel/reorder methods, `downloadCoordinatorIfAvailable`.
- `QuotaManager.usedBytes()`.
- `GameRowView`: the Pin button, `quotaBlock` state, the `ReclaimPromptView` sheet, and
  a first cut of the quota gate inside `download()`.

**Correction to the briefing.** It said `StorageView` had 3 call sites and the quota
gate was unbound. Both were off. Grep showed `StorageView` had **zero** production call
sites (only doc-comment mentions and test references); `ReclaimPromptView` was the one
genuinely reached surface (`GameRowView:124`); and the gate *was* already spliced into
`GameRowView.download()` — but only inside a private view method, where no test could
reach it. So the real gap was reachability and testability, not the guard itself.

**Added by me:**

1. `AppEnvironment.attemptDownload(for:) -> DownloadAttempt` — the whole of the row's
   download attempt moved out of the view onto a seam. `GameRowView.download()` now just
   calls it and maps the result to row status, so the shipped path and the tested path
   are literally the same code. `makeDownloadEngine()` now honours the existing
   `downloadSessionOverride`, which is what lets a test observe whether a connection was
   opened at all.
2. `LibraryShellView.ShellSurface` (`adapter` / `downloads` / `storage`) with a pure
   `title(for:)`, replacing the single-purpose adapter sheet. Toolbar affordances, not
   new sidebar rows, per the frozen D-14 navigation contract and the `ff008c5` adapter
   precedent. `DownloadsView`, `StorageView` and `QuotaSettingsView` are now reachable.
3. Surfaced `lastBlockedDownload` (see "Fixed while here").
4. `PlaysteadTests/CacheTests/StorageShellWiringTests.swift` — 13 tests.

### How quota enforcement is now reached on the real download path

`GameRowView` Download button → `AppEnvironment.attemptDownload(for:)` →
`quotaVerdict(forDownloading:)` → `QuotaManager.verdict(forAdditional:)` on the app's
**shared** `QuotaManager`. The gate runs before the first connection: a blocked verdict
returns `.blocked(verdict)` without constructing a transfer, and the row raises
`ReclaimPromptView`. Only members not already in the CAS are counted, so a re-download of
cached content costs nothing.

The queue path is enforced independently: `DownloadCoordinator`'s injected `quotaCheck`
closure is wired to the same `QuotaManager` and its `isPinned` to the same `PinStore`, so
both paths agree. `AppEnvironment.quotaReason(_:)` turns a blocked verdict into the
message the coordinator's `.blocked` event carries.

Security posture from `56781ec` preserved: digests still flow through
`PathSafety.validatedDigest` before becoming URL path components, on the row path
(`attemptDownload`) and the coordinator path (`blobURL`) alike. No new unvalidated
path-component splices.

### Tests

13 new cases in `StorageShellWiringTests`, all asserting through the real assembled
`AppEnvironment` (temp dir + `StubURLProtocol`), following `ShellWiringTests`. The load-bearing pair:

- `testOverQuotaDownloadIsRefusedWithoutOpeningAConnection` — over-quota attempt returns
  `.blocked(.quota)` with the exact shortfall, **and `StubURLProtocol.requestLog` is
  empty** and the CAS stays empty. The refusal is real, not merely reported.
- `testWithinQuotaDownloadActuallyTransfersAndCommits` — the same download under a
  fitting quota *does* open a connection and *does* commit into the app's own CAS. Without
  this, the test above would pass against a gate that blocked everything.

Plus: already-cached bytes count against the next verdict; a zero-cost download passes a
zero-headroom quota; raising the quota from the prompt persists and unblocks the retry; a
floor-blocked verdict offers no quota raise and does not widen the quota; reclaiming frees
real bytes (object actually deleted) and unblocks the download; pinning removes a game
from every candidate list and deletes nothing; the storage snapshot reports exactly the
figure the gate uses, with real titles; the quota stepper governs the next download; the
downloads surface renders the real queue with real titles and its buttons mutate it.

### Verification

```
cd ~/projects/playstead/playstead-mac && xcodebuild -project Playstead.xcodeproj \
  -scheme Playstead -destination 'platform=macOS' test
```

**251 cases executed — 250 passed, 1 failed.** All 13 new cases pass.

The single failure is **`AdapterWiringTests.testInstallResultVerifiesAndLaunchesThroughARealAdapterHost()`**,
which times out at 60s. **It is pre-existing and not mine.** I verified this by running
that suite in a clean `git worktree` at `HEAD` (`73a485f`) with none of my changes
present: it fails there identically, at the same 60s timeout, while its eight sibling
tests pass. It touches no code I changed.

So the run ends `** TEST FAILED **`, not `** TEST SUCCEEDED **` — but on account of that
one inherited failure only. I did not weaken any existing assertion to get green.

Note: the briefing's "baseline is 231 cases" is stale — `HEAD` declares 239 test
functions, of which 238 execute.

### Fixed while here

`AppEnvironment.lastBlockedDownload` was written from the coordinator's `.blocked` event
and **read by nothing** — state that looked wired but did nothing, the exact failure mode
this task exists to correct. When the scheduler refused an item the item simply stopped
with no reason visible anywhere. It now renders on the Downloads surface with a route to
the storage surface (`c42d2a9`).

### Left unfinished / worth knowing

1. **`EvictionPlanner.plan(for:)` does not exclude pinned games.** Only `candidates()`
   does. This is not a live bug — the UI reaches reclaim exclusively through candidate
   lists, which exclude pins, and my test asserts that containment — but a future caller
   passing an arbitrary id set could evict a pinned game. I did not add a filter, because
   changing the semantics of an explicit user selection is a design call, not wiring, and
   the constraint was to wire rather than rewrite. Flagging it rather than silently
   changing it.
2. **The floor limb of the gate is not covered end-to-end.** `QuotaManager`'s
   `freeSpaceProvider` is injectable, but `AppEnvironment` constructs the real one and
   exposes no seam, so a test on real hardware can only trip the *quota*. I tested the
   floor's user-visible consequences purely (`canRaiseQuota`/`raiseQuota` refuse to widen
   the quota on a floor block). Genuinely exercising the floor through the assembled
   environment would need a free-space seam on `AppEnvironment.init` — a deliberate
   choice I left to you rather than widening the composition root unasked.
3. **Coordinator progress republishing is untested.** `downloadProgressByAssetSet` is fed
   by the coordinator's event stream and consumed by `downloadRows()`, but asserting it
   needs a live scheduler run against the stub; my queue test deliberately goes offline to
   stay deterministic. The plumbing is real and used; it is the *test* that is missing.

---

# Adapter launch hang — root cause

### `testInstallResultVerifiesAndLaunchesThroughARealAdapterHost` — 60s hang

**Verdict: test-fixture defect, proven.** The app's install/verify/launch code is
not implicated. A genuine production hazard was found alongside it; it is
described at the end and was *not* changed.

### Root cause

macOS routes a spawn of a file it recognises as an **application bundle's main
executable** through a security assessment before it releases the child. It
applies that recognition when the bundle carries a `Contents/Info.plist` and —
absent one — when the executable's own name matches the enclosing `.app`'s.

A plain copy of `/bin/echo` fails that assessment: its signature is only valid at
its platform path. The failure mode is silent and unbounded — `Process.run()`
succeeds, the child is left **suspended at `_dyld_start`**, and
`terminationHandler` never fires.

The failing test's fixture pin declares `Contents/MacOS/Stand-In` inside
`Stand-In.app`. Name matches bundle → assessment runs → child never released.

### Evidence

**1. The children never exit and are still on the machine.** `ps` showed orphaned
stand-ins parented to `launchd`, hours after their test hosts died — every one
from the install path:

```
jon 73906 ... 2:40AM 0:00.00 /var/folders/.../fixture-emulators/fixture/0.0.1/Stand-In.app/Contents/MacOS/Stand-In /tmp/rom.gba
```

**2. They are suspended before their first instruction.** `sample` on a live one:

```
Call graph:
    796 Thread_...: Main Thread
      796 _dyld_start  (in dyld) + 0
Parent Process:  launchd [1]
Physical footprint: 96K
```

So `run()` did succeed; the process was created and then never allowed to
execute. Nothing for `terminationHandler` to fire on.

**3. Controlled matrix** — standalone Swift program, copied `/bin/echo` spawned
via Foundation `Process`, identical to the code under test. Run both inside and
outside my tool sandbox with identical results, so not a harness artifact:

| bundle / executable layout | `Info.plist` | signed | result |
|---|---|---|---|
| `Stand-In.app/Contents/MacOS/Stand-In` | no | no | **HUNG** |
| `Stand-In.app/Contents/MacOS/Stand-In` | yes | no | **HUNG** |
| `Stand-In.app/Contents/MacOS/mGBA` | yes | no | **HUNG** |
| `Stand-In.app/Contents/MacOS/mGBA` | no | no | EXITED 0.11s |
| `Stand-In/Contents/MacOS/Stand-In` (not `.app`) | no | no | EXITED 0.10s |
| `Stand-In.app/Contents/MacOS/Stand-In` | no | **ad-hoc** | EXITED 0.15s |
| `Stand-In.app/Contents/MacOS/Stand-In` | yes | **ad-hoc** | EXITED 0.16s |

Two independent knobs each fix it — make the file not look like a bundle main
executable, or make its signature valid where it lives. That isolates the cause
to the assessment, and to nothing in the project's code.

**4. Why the sibling passed — luck, not correctness.** The real pin's
`executable_relative_path` is `Contents/MacOS/mGBA`, placed inside a bundle the
test names `Stand-In.app`, with no `Info.plist`. Name ≠ bundle → row 4 → runs.
`testSelectingAnAdapterThroughTheEnvironment…` was passing because of what its
executable happened to be *named*, not because the select path is sound.

**5. Ruled out.** The archive/executable digest split (`664d95d`),
`setInstallation`, `AdapterInstallState`, recorded executable paths, `0755`
permissions, and quarantine attributes are all uninvolved — every one of them is
held constant across HUNG and EXITED rows above. `verifyInstalledDigest()` also
provably passed in the failing run: had it thrown, the test would have reported
the error rather than timing out.

### What I changed

`playstead-mac/PlaysteadTests/AdapterTests/AdapterWiringTests.swift` only.

- Both fixtures (`makeRunnableAdapterBundle` and the failing test's
  `archiveExpander`) now share one helper, `installStandInExecutable`, which
  copies `/bin/echo`, chmods `0755` as before, and then ad-hoc re-signs the copy.
  It throws `StandInSigningFailure` if `codesign` fails rather than proceeding to
  a fixture that can only hang.
- `firstLaunchTimeout` 60s → 15s.

**Why this is not lowering the bar.** No assertion was weakened, removed, or
skipped; the test still drives install → verify → launch → exit callback and
still requires the callback to fire. Signing raises fidelity: it gives the
stand-in the property the real pinned `mGBA.app` already has (a signature valid
where it lives), so the test now exercises the app-bundle main-executable launch
path *for the right reason*. It also removes the latent trap in the sibling test,
which was launchable only by naming coincidence. The digest split from `664d95d`
and `App/PathSafety.swift` from `56781ec` are untouched.

The timeout reduction is a tightening, not a loosening. The 60s ceiling was
justified in a comment as absorbing a "one-off security-assessment cost measured
at ~4s". That was a misdiagnosis: an unsigned stand-in is *never* released, so
the wait was unbounded and the ceiling only decided how long the suite hung
before failing. With the cause removed, launches take ~0.2s, so 15s fails fast
if this ever returns.

### Commit

`7e17165` — `fix(03): re-sign stand-in adapter binaries so launches actually exit`
(1 file changed, 62 insertions, 23 deletions). Nothing under `.planning/`,
`.gsd/`, or the root `.gitignore` was staged or touched.

### Verification

Target test: **0.172s**, was a 60s timeout.

```
** TEST SUCCEEDED **
Test case 'AdapterWiringTests.testARecordedInstallationIsRestoredByAFreshlyAssembledEnvironment()' passed (0.027 seconds)
Test case 'AdapterWiringTests.testCapabilityCardFromTheEnvironmentDoesNotRestatePinnedSupportForAUserSelectedBuild()' passed (0.023 seconds)
Test case 'AdapterWiringTests.testInstallingTheAdapterThroughTheEnvironmentClearsTheReadinessBlocker()' passed (0.045 seconds)
Test case 'AdapterWiringTests.testInstallResultVerifiesAndLaunchesThroughARealAdapterHost()' passed (0.172 seconds)
Test case 'AdapterWiringTests.testLaunchStillRefusesWhenTheInstalledExecutableIsChangedAfterInstall()' passed (0.077 seconds)
Test case 'AdapterWiringTests.testMissingRequiredFilesKeepTheRowOnDownloadRatherThanTheReadinessSheet()' passed (0.011 seconds)
Test case 'AdapterWiringTests.testPlayIsBlockedByTheEmulatorCheckWithAnInstallRemedyWhenNoAdapterIsInstalled()' passed (0.010 seconds)
Test case 'AdapterWiringTests.testSaveDirectoryRefusesAnAssetSetIdThatIsNotASafeFilename()' passed (0.008 seconds)
Test case 'AdapterWiringTests.testSelectingAnAdapterThroughTheEnvironmentMakesLaunchVerificationSucceedAndActuallyLaunch()' passed (0.195 seconds)
Test case 'AdapterWiringTests.testTheAdapterSurfaceStatesEachInstallStateHonestly()' passed (0.012 seconds)
```

Full suite — `xcodebuild -project Playstead.xcodeproj -scheme Playstead -destination 'platform=macOS' test`:

```
EXIT=0
** TEST SUCCEEDED **
passed on: 251
failed on: 0
```

### Open production risk — found, NOT fixed, recommend follow-up

The investigation surfaced a real hazard that is adjacent to this bug but is not
its cause, and I did not change production code for it.

A **quarantined** app-bundle main executable exhibits the same silent infinite
hang, even when signed:

| case | result |
|---|---|
| signed, `com.apple.quarantine` set | **HUNG** (12s cap, no exit) |
| signed, no quarantine | EXITED status=0 in 0.15s |

This matters because `AdapterInstaller` deliberately preserves quarantine (D-05,
correctly — `defaultExpand` uses `ditto` precisely to keep the xattr). A
genuinely notarised mGBA should pass Gatekeeper and run; my probe used an ad-hoc
signature, which Gatekeeper rejects. But the failure shape when assessment does
*not* pass — unsigned, corrupt, revoked notarisation, or a user selecting a
broken bundle — is the worst possible one:

`AdapterHost.launch` treats a successful `proc.run()` as "launched". A child held
by the assessment never runs and never terminates, so `onExit` never fires and
the app believes the emulator is running forever, with no error surfaced.

I did not fix this because it is out of scope for the reported bug and every
candidate fix is a real design change:

- A liveness probe after `run()` cannot distinguish "held" from "idle emulator" —
  the held task reports `S` in `ps`, not `T`, and reading its Mach suspend count
  needs task-port access the app does not have.
- Pre-flighting `SecStaticCodeCheckValidity` at install/select time is precise
  and fits the existing posture, but it would reject the `/bin/echo` stand-ins
  the suite depends on (`AdapterWiringTests` and `PlaySessionTests`), so it needs
  a fixture strategy decided alongside it.

Recommend tracking as its own item against the launch/exit contract.

### Environment note

Mid-investigation I `SIGKILL`ed a stuck `xcodebuild`, which left a `SecurityAgent`
keychain-authorisation prompt open. That blocks `SecItemCopyMatching`, which
wedges `xcodebuild` at `GatherProvisioningInputs` — confirmed by sampling the
stack. Killing the `SecurityAgent` process cleared it. Unrelated to the bug, but
worth knowing if a build ever appears to hang before compiling.
