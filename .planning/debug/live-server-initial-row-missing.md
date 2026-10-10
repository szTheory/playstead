---
status: investigating
trigger: "Autonomously fix the hosted Mac live-server regression so the controller/CI work can move forward without repeated manual UAT."
created: 2026-10-09T21:28:09Z
updated: 2026-10-09T21:34:02Z
---

## Current Focus
<!-- OVERWRITE on each update - reflects NOW -->

bug_class: "Heisenbug-Mandelbug (hosted-only observation; deterministic fixture seam passes locally)"
reasoning_checkpoint:
  hypothesis: "The original missing-row assertion conflates snapshot persistence, List activation, and accessibility rendering; current hosted evidence cannot identify which of these is the first missing stage."
  confirming_evidence:
    - "The hosted test reaches the library surface and show-list control, but the row with the fixture's asset-set ID is absent after 20 seconds."
    - "prepare synchronously calls Import.import_single and Catalogue.get_asset_detail before writing the control ID; the new production Snapshot.read seam test returns the exact sentinel and a cursor."
    - "The uploaded artifact contains no client database or server request trace. Neither List activation nor local persistence is asserted before the failed row lookup."
  falsification_test: "On the next hosted failure, inspect distinct source-line assertions for stored cursor, exact stored sentinel, and activated List. If those all pass, missing import/persistence and List activation are eliminated, isolating the AX/render seam."
  fix_rationale: "Failure-only read-only observations preserve the original timeout and click order while making the earliest missing stage visible through the existing privacy-safe source-line diagnostics. This is instrumentation, not a claimed production fix."
  blind_spots: "No hosted execution of the new observations yet; Swift parsing checks syntax, not full XCTest compilation. Local GUI launching is explicitly prohibited without human-set opt-in and was not attempted."
  candidate_causes:
    - "fixture: the first sentinel is imported or registered after the snapshot response is created, or its relationship/asset-set identity does not match the row query."
    - "server: pairing or initial sync filters a valid imported game from the API snapshot."
    - "client: the snapshot is returned but the app fails to persist or render its row after switching to the list view."
  and_gate: "undetermined — asynchronous snapshot arrival and an early List switch could combine; no evidence yet proves either contributing condition."
next_action: "Root agent finishes observing run 37991439424 on 6506161 (which lacks these uncommitted diagnostics), then commits the instrumentation and reads the next run's live-server-tests.json assertion locations using the interpretation table below. No additional timeout or production change is justified yet."

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: "The first synthetic library item is visible in the app after pairing and initial sync, before any game bytes are downloaded."
actual: "The library surface and show-list control appear, but the row keyed by the first sentinel's asset-set ID does not appear within 20 seconds."
errors: "GitHub Actions run 37990636933, SHA 1a4178ff5e4a31f35f3e150d1332e8ff878a691c: LiveServerSnapshotTests.swift:66 XCTAssertTrue; 5 live-server tests executed, one failed."
reproduction: "Run the LiveServer verification layer with the real CI pairing/import fixture and execute testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch."
started: "Observed in run 37983148056 with a 10-second wait; increasing the wait to 20 seconds did not help in run 37990636933."

## Eliminated
<!-- APPEND only - prevents re-investigating -->

- hypothesis: "The composition root simply omits refreshing the library after initial sync."
  evidence: "AppEnvironment.syncNow awaits syncEngine.syncNow, then calls refreshCurationViewModels, whose final statement is libraryViewModel.refresh. This excludes an absent call, not a failed/cancelled sync or a stale rendered view."
  timestamp: 2026-10-09T21:34:02Z

## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-10-09T21:28:09Z
  checked: GitHub Actions run 37990636933 and sanitized artifact 11646510461
  found: "LiveServerSnapshotTests is the only failing required live-server test; it failed at XCTAssertTrue on line 66 after a 20-second wait. The other four required live-server tests passed."
  implication: "The scanner/sanitizer fixes are not implicated in this Mac failure. The missing first row is a fixture, server snapshot, or client read-model issue, not simply a too-short row wait."

- timestamp: 2026-10-09T21:31:59Z
  checked: "live-server.sh prepare -> MacCiFixture.import_sentinel! -> Snapshot.read -> SyncEngine.bootstrapFromSnapshot -> AppEnvironment.syncNow -> LibraryViewModel.refresh -> LibraryShellView.catalogueList -> GameRowView"
  found: "prepare verifies the imported title synchronously. SyncEngine commits the catalogue and cursor, then AppEnvironment refreshes the shared observable library. List activation is a separate Button action; the requested summary identifier is attached only inside GameRowView. The test has no boundary assertion before the missing-row timeout."
  implication: "The original hypothesis that the server import is missing is not supported by artifact evidence. Distinct boundary observations are required; no production behavior change is justified."

- timestamp: 2026-10-09T21:31:59Z
  checked: "New test: the prepared sentinel is in the first paired snapshot before any download; mix test test/mix/tasks/playstead_mac_ci_fixture_test.exs"
  found: "7 tests passed. The new test uses production fixture import, exact pairing approval and Snapshot.read; the snapshot contains the exact control ID/title, nonempty cursor and no continuation."
  implication: "The deterministic import-to-snapshot seam works locally. This does not prove the failing hosted app received or persisted that snapshot."

- timestamp: 2026-10-09T21:31:59Z
  checked: "LiveServerSnapshotTests failure-only diagnostic patch; xcrun swiftc -frontend -parse; git diff --check"
  found: "Syntax and whitespace checks pass. On the original row timeout, read-only SQLite observations report cursor and exact sentinel presence, and AX reports whether List is active, at distinct assertion lines. No diagnostics run on the passing path and no extra HTTP requests affect the snapshot-count proof."
  implication: "Next hosted failure can distinguish persistence, layout activation and AX row rendering without speculative sleeps or production changes. Full XCTest compile/execution remains unverified."

- timestamp: 2026-10-09T21:34:02Z
  checked: "Continuation inspection of showLibraryList, LibraryViewModel.refresh, AppEnvironment.syncNow, clickWhenHittable and storedSentinel SQL"
  found: "List activation changes layout/selection without changing search/system filters; post-sync refresh reaches the shared library. storedSentinel queries the actual catalogue_entries id/display_title columns. clickWhenHittable checks a precondition but does not assert that the action changed layout; the new line 74 supplies that missing observation. git diff --check passed. No configured debugger skills or project skill directories were present; knowledge-base history contains no matching issue."
  implication: "Instrumentation covers the presently ambiguous boundaries without an extra network request or extra delay. More deterministic tests of already-passing import/snapshot logic would not establish which hosted boundary failed."

- timestamp: 2026-10-09T21:34:02Z
  checked: "git HEAD and working-tree status"
  found: "HEAD remains 6506161, with LiveServerSnapshotTests and fixture seam test modified but uncommitted. The active run on this SHA cannot emit the new boundary assertion lines."
  implication: "Do not interpret the active run as validation of the instrumentation. Preserve it; stage diagnostics need the next commit's full XCTest compile and hosted execution."

## Next hosted artifact interpretation

Read the source at the run's exact SHA before interpreting line numbers. At the current uncommitted diagnostic revision:

| Failed assertion | Supported inference | Next focused check |
| --- | --- | --- |
| Line 72, cursor missing | Initial snapshot has not committed a cursor | Trace credential/API bootstrap and sync failure state; do not change row rendering yet |
| Line 73, sentinel missing, with cursor present | A snapshot cursor exists but the exact fixture row/title is absent | Compare fixture owner/control identity and received/persisted catalogue transaction |
| Line 74, List absent, with both database checks passing | Data is available; List activation or shell routing did not produce its surface | Inspect click/focus/layout path and whether cards remain active |
| Only line 76 (possibly line 77), all three stage assertions pass | Data and List exist after the timeout, while requested row was absent during the wait | Distinguish delayed arrival between timeout and observations, stale view refresh, and AX identity/container exposure; do not claim these observations prove data existed throughout the timeout |
| No missing-row failure | This reproduction passed | Inspect subsequent relaunch and exact two-snapshot proof; a single pass does not establish the earlier intermittent failure's root cause |

No local GUI launch or repeated full tests were performed during this continuation: the required hosted evidence is pending, prior focused tests passed, and no code changed. SBFL is inapplicable without per-test coverage or a locally reproduced failure; `rr` is not a macOS replay path. Bounded hosted observations are the useful next experiment.

## Resolution
<!-- OVERWRITE as understanding evolves -->

root_cause: pending — existing artifact cannot isolate the first missing boundary
fix: "No production fix. Added failure-only stage observations and deterministic import-to-snapshot seam coverage."
verification: "7 focused ExUnit tests passed; Swift syntax parse passed; diff whitespace check passed. Hosted stage observations and full XCTest compile pending."
files_changed:
  - playstead-mac/PlaysteadUITests/LiveServerSnapshotTests.swift
  - playstead-server/test/mix/tasks/playstead_mac_ci_fixture_test.exs

## Prevention

causal_branches:
  code: []
  config_environment: []
  and_gate: "pending"
why_not_caught: pending
recurrence_guard: pending
