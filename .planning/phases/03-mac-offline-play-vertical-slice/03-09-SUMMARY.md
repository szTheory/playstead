---
phase: 03-mac-offline-play-vertical-slice
plan: 09
subsystem: adapter
tags: [swift, sqlite, hdiutil, ditto, sha256, readiness, preflight, bios, xctest]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "03-01's pinned adapter (AdapterPin.swift, 03-ADAPTER-PIN.json), 03-03's PreflightChecker/CASManager/AdapterHost, 03-07's DownloadQueue/AvailabilityState/DownloadCoordinator"
provides:
  - "AdapterCatalog/AdapterDescriptor: every adapter fact (system, emulator, version, digest, save contract) sourced from AdapterPin, never restated"
  - "AdapterInstaller: HTTPS download + streaming digest verification + disk-image expansion into emulators/<emulator>/<version>/, idempotent via a unique (emulator, version) index; selectExisting() for a user-chosen build, labelled verified/unverified honestly"
  - "AdapterCapabilityCard: renders system, version, digest, accepted content, BIOS posture (with fidelity caveat), save support, and installation verification state"
  - "AdapterHost.installState: launch refuses with a typed digestMismatch instead of a failed process spawn"
  - "BiosStore: byte-length-then-digest validation against caller-supplied known references, managed copy under a digest-derived filename, no acquisition path anywhere"
  - "BiosDropTarget/BiosDropTargetView: SwiftUI drop surface wrapping BiosStore"
  - "ReadinessEngine: six zero-network checks (assets, cache verification, emulator, BIOS, controller/input, save directory), ordered by severity, every blocking result carrying a Remedy"
  - "ReadinessReportView: one row per check with its remedy button; Play enabled only when the report has no blocking result"
  - "adapter_installations and bios_files SQLite tables"
affects: [03-10]

actuals:
  tokens: 62000
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Install-idempotency via a SQLite UNIQUE(emulator, version) constraint rather than an in-process lock, so concurrent/repeat installs converge on one row regardless of actor interleaving"
    - "Untrusted-path handling for a user-dropped file: reject symlinks via readlink() (never opening the target), reject non-regular-files before any open, open read-only strictly to hash"
    - "Readiness engine composed as six pure (mostly) local checks, each producing a ReadinessCheck with an optional Remedy; the one documented disk-write exception is a genuine cache-object quarantine+redownload"

key-files:
  created:
    - playstead-mac/Playstead/Adapter/AdapterCatalog.swift
    - playstead-mac/Playstead/Adapter/AdapterInstaller.swift
    - playstead-mac/Playstead/Adapter/AdapterCapabilityCard.swift
    - playstead-mac/Playstead/Adapter/BiosStore.swift
    - playstead-mac/Playstead/Adapter/BiosDropTarget.swift
    - playstead-mac/Playstead/Readiness/ReadinessEngine.swift
    - playstead-mac/Playstead/Readiness/ReadinessCheck.swift
    - playstead-mac/Playstead/Readiness/Remedy.swift
    - playstead-mac/Playstead/Readiness/ReadinessReportView.swift
    - playstead-mac/PlaysteadTests/AdapterTests/InstallerTests.swift
    - playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift
    - playstead-mac/PlaysteadTests/ReadinessTests/ReadinessEngineTests.swift
  modified:
    - playstead-mac/Playstead/Adapter/AdapterHost.swift
    - playstead-mac/Playstead/Cache/PreflightChecker.swift
    - playstead-mac/Playstead/Persistence/Migrations.swift

key-decisions:
  - "BiosStore's known-reference digest set is caller-supplied (DI), with no built-in default — the plan 03-01 spike's BIOS probe was recorded not-run (no fixture available), so embedding a fabricated reference digest here would misrepresent evidence this project never gathered. See Known Stubs."
  - "AdapterHost.verifyInstalledDigest checks the installState verified flag before file existence, so an explicitly unverified installation reports digestMismatch rather than being masked by an unrelated missing-file error"
  - "Quarantine of a corrupted committed cache object is implemented directly in ReadinessEngine (move-aside + verify-index clear) rather than adding a new CASManager method, since CASManager.swift was outside this plan's task-3 file scope"
  - "ReadinessEngine's asset/cache split follows PreflightChecker's existing blocker reasons: 'missing' -> game-assets check, 'corrupted'/'unreadable' -> cache-verification check (the latter is what triggers quarantine+redownload)"

requirements-completed: [PLAY-01, PLAY-02, PLAY-03, CACH-04]

coverage:
  - id: D1
    description: "Install or select the pinned adapter with an honest, pin-sourced capability card"
    requirement: "PLAY-01"
    verification:
      - kind: unit
        ref: "PlaysteadTests/AdapterTests/InstallerTests.swift#testInstallWithWrongDigestLeavesNoFilesAndReturnsTypedMismatchError"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/AdapterTests/InstallerTests.swift#testSecondInstallWithExistingMatchingInstallationCreatesNoSecondDirectoryOrRecord"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/AdapterTests/InstallerTests.swift#testTwoConcurrentInstallCallsResultInExactlyOneInstallationRecord"
        status: pass
      - kind: unit
        ref: "PlaysteadTests/AdapterTests/InstallerTests.swift#testSelectingExistingInstallationWithMismatchedDigestRecordsUnverifiedAndCardRendersLabel"
        status: pass
    human_judgment: false
  - id: D2
    description: "Drag-in BIOS validation with managed storage and no acquisition path anywhere"
    requirement: "PLAY-03"
    verification:
      - kind: unit
        ref: "PlaysteadTests/AdapterTests/BiosTests.swift (16 tests: accept/reject, symlink/directory rejection, original-file immutability, idempotence, removal, source-grep)"
        status: pass
    human_judgment: true
    rationale: "BiosStore's known-reference digest set is caller-supplied and empty by production default (no fabricated evidence embedded) — a human must confirm the actual wiring/UX once a real reference digest is sourced; see Known Stubs."
  - id: D3
    description: "Readiness engine: six checks, ordered severity, a remedy each, zero network"
    requirement: "PLAY-02, CACH-04"
    verification:
      - kind: unit
        ref: "PlaysteadTests/ReadinessTests/ReadinessEngineTests.swift (18 tests covering all six checks, ordering, idempotence, quarantine/requeue, and the zero-network StubURLProtocol assertion)"
        status: pass
      - kind: other
        ref: "xcodebuild test -scheme Playstead (full suite, 160/160)"
        status: pass
    human_judgment: false

duration: 95min
completed: 2026-08-31
status: complete
---

# Phase 3 Plan 9: Mac Offline Play Vertical Slice Summary

**Adapter install/select with a pin-sourced capability card, drag-in BIOS validation with no acquisition path, and a six-check zero-network readiness engine gating Play with an actionable remedy for every blocker**

## Performance

- **Duration:** 95 min
- **Tasks:** 3
- **Files modified:** 15 (12 created, 3 modified)

## Accomplishments

- `AdapterCatalog`/`AdapterDescriptor` derive every fact the capability card states (system, emulator, version, digest, accepted content, save contract) entirely from `AdapterPin` — no adapter fact is a literal anywhere in this plan's code
- `AdapterInstaller` downloads the pinned release over HTTPS, verifies its digest while hashing, expands it into `emulators/<emulator>/<version>/` via a mounted-and-`ditto`'d disk image (quarantine attribute always intact), and records exactly one installation row per `(emulator, version)` even under concurrent install requests
- `selectExisting(appURL:)` lets a user point at a build they already have; a digest mismatch is recorded — not rejected — and the capability card labels it "unverified" honestly
- `BiosStore` validates a dropped file by exact byte length then SHA-256 digest against a caller-supplied reference set, rejecting symlinks/directories/unreadable paths before any open, and copies (never moves) an accepted file into managed storage under a digest-derived name
- `ReadinessEngine.evaluate` runs six local checks (game assets, cache verification, emulator, BIOS, controller/input, save directory), ordered by severity, with every blocking result carrying an executable `Remedy` — proven offline by a test whose `URLProtocol` stub fails any attempted request
- A genuine cache-object corruption is quarantined (moved aside, never deleted) and automatically re-enqueued for redownload, with a finding that never blames the user

## Task Commits

1. **Task 1: Install or select the pinned adapter and state its capabilities honestly** - `00ebb60` (feat)
2. **Task 2: Drag-in BIOS validation with managed storage and no acquisition path** - `7752a2c` (test) / `9326063` (feat)
3. **Task 3: The readiness engine — six checks, ordered severity, a concrete remedy each, and zero network** - `b51b2b7` (test) / `c038740` (feat)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `playstead-mac/Playstead/Adapter/AdapterCatalog.swift` - AdapterDescriptor + AdapterCatalog, sourced entirely from AdapterPin
- `playstead-mac/Playstead/Adapter/AdapterInstaller.swift` - download+verify+expand actor, idempotent/concurrency-safe install, selectExisting
- `playstead-mac/Playstead/Adapter/AdapterCapabilityCard.swift` - honest capability card + SwiftUI view
- `playstead-mac/Playstead/Adapter/AdapterHost.swift` - gains installState so launch refuses with a typed error
- `playstead-mac/Playstead/Adapter/BiosStore.swift` - length-then-digest BIOS validation, managed storage
- `playstead-mac/Playstead/Adapter/BiosDropTarget.swift` - drop-handling logic + SwiftUI drop surface
- `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` - the six-check zero-network engine
- `playstead-mac/Playstead/Readiness/ReadinessCheck.swift` - ReadinessCheckKind/Outcome/Check/RequiredMember/Report
- `playstead-mac/Playstead/Readiness/Remedy.swift` - RemedyAction + Remedy
- `playstead-mac/Playstead/Readiness/ReadinessReportView.swift` - one row per check, Play gated on readiness
- `playstead-mac/Playstead/Cache/PreflightChecker.swift` - doc comment updated for ReadinessEngine's consumption
- `playstead-mac/Playstead/Persistence/Migrations.swift` - adapter_installations, bios_files tables
- `playstead-mac/PlaysteadTests/AdapterTests/InstallerTests.swift` - 11 tests
- `playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift` - 16 tests
- `playstead-mac/PlaysteadTests/ReadinessTests/ReadinessEngineTests.swift` - 18 tests

## Decisions Made

- BIOS reference digests are dependency-injected with no production default, rather than embedding an unverified literal — see Known Stubs below.
- `AdapterHost`'s install-state verification checks the `verified` flag before file existence, so an unverified selection always reports as a digest mismatch.
- Corrupted-object quarantine is implemented in `ReadinessEngine` itself (not a new `CASManager` method), staying within this task's declared file scope.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AdapterHost checked file existence before the verified flag**
- **Found during:** Task 3's full-suite verification pass (a test written for Task 1's install-state behavior only surfaced this ordering bug once the whole suite ran together)
- **Issue:** `verifyInstalledDigest()` checked `FileManager.fileExists` before the install state's `verified` flag, so an explicitly unverified installation at a nonexistent path reported `.emulatorNotInstalled` instead of `.digestMismatch` — masking the real reason.
- **Fix:** Reordered the checks so `verified` is checked first.
- **Files modified:** `playstead-mac/Playstead/Adapter/AdapterHost.swift`
- **Verification:** `InstallerTests.testAdapterHostRefusesLaunchWhenInstallStateIsUnverified` passes; full suite green.
- **Committed in:** `c038740`

**2. [Rule 1 - Bug] Test assertion checked the wrong directory for "no files created on mismatch"**
- **Found during:** Task 3's full-suite verification pass
- **Issue:** `InstallerTests`' digest-mismatch test asserted the shared `emulators/` root was absent, but `AppPaths` creates that root eagerly on construction regardless of any install outcome — the assertion was checking a directory that always exists.
- **Fix:** Assert against this pin's own `emulator/version` subdirectory instead, the directory that actually reflects whether an install attempted anything.
- **Files modified:** `playstead-mac/PlaysteadTests/AdapterTests/InstallerTests.swift`
- **Verification:** Test passes in both standalone and full-suite runs.
- **Committed in:** `b51b2b7`

---

**Total deviations:** 2 auto-fixed (2 bugs, both surfaced only by the plan-level full-suite `<verify>` run, not by any single task's own test target)
**Impact on plan:** Both fixes are small and localized; no scope creep. The full-suite run these deviations came from is itself part of task 3's own `<verify>` block.

## Issues Encountered

None beyond the two auto-fixed deviations above.

## Known Stubs

- **`BiosStore`'s known-reference digest set has no production default.** `BiosStore.Reference` (system, expected byte length, known SHA-256 digests) is a required constructor parameter with no built-in value. Production wiring — supplying a real, confirmed reference digest for the pinned system's BIOS — is deferred: the plan 03-01 spike's BIOS probe (`spike/out/probe-07.json`) explicitly recorded the operator-supplied-BIOS half as "FAIL/not-run — no BIOS file was available in this environment," never faked. Embedding an unverified literal here would misrepresent evidence this project has not actually gathered. Until a real reference digest is sourced and wired at the app's composition root, `BiosStore` will correctly and honestly reject every dropped candidate for lack of a known reference — the safe default, not a broken one, but a real gap a future plan (03-10 or a dedicated follow-up) must close before BIOS validation is usable end-to-end. All of `BiosStore`'s other behavior (length check, digest check, managed storage, symlink/directory rejection, no-acquisition-path source grep) is fully implemented and tested against synthetic references.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The adapter install/select flow, BIOS validation, and readiness engine are all in place and fully unit-tested (160/160 in the full `xcodebuild test` suite), ready for 03-10 to wire them into the actual launch chrome and notarized build.
- Before BIOS validation is usable end-to-end, a real reference digest for the pinned system's BIOS needs to be sourced and wired into `BiosStore`'s composition (see Known Stubs).
- Wiring `ReadinessEngine`, `ReadinessReportView`, and the capability/BIOS UI into the actual Play button and settings surfaces (as opposed to the components existing and being tested standalone) is 03-10's job, per this plan's scope.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-08-31*

## Self-Check: PASSED

- All 15 key files (12 created, 3 modified) confirmed present on disk.
- All 5 commits (`00ebb60`, `7752a2c`, `9326063`, `b51b2b7`, `c038740`) confirmed in `git log`.
- `xcodebuild test -scheme Playstead` (full suite, both default-parallel and serial modes): 160/160 passing.
- Acceptance-criteria greps re-run and confirmed clean: no emulator-candidate literal or `xattr` call in `AdapterCatalog.swift`/`AdapterInstaller.swift`/`AdapterCapabilityCard.swift`; no acquisition-language match in `BiosStore.swift`/`BiosDropTarget.swift`.
