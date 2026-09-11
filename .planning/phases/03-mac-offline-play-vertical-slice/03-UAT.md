---
status: partial
phase: 03-mac-offline-play-vertical-slice
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md, 03-06-SUMMARY.md, 03-07-SUMMARY.md, 03-08-SUMMARY.md, 03-09-SUMMARY.md, 03-10-SUMMARY.md, 03-12-SUMMARY.md
started: 2026-08-31T00:00:00Z
updated: 2026-09-11T00:00:00Z
---

## Current Test

[testing paused — 5 items outstanding: 3 blocked (items 7, 8, 9), 2 partial (item 10's live VoiceOver pass and item 13's real-BIOS-bytes acceptance remain operator-verified). 03-12-PLAN.md closed the notarization gap (items 14-16 now pass); notarization is no longer an outstanding item. 03-14-PLAN.md closed item 4's availability-search gap (now pass). This annotation and the Summary footer below are recomputed by `scripts/check-uat-tally.sh` from this file's own per-item results, not hand-maintained — item 11 is `pass`, not blocked, contrary to a stale pre-03-14 version of this line.]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running server. Clear ephemeral state (temp DBs, caches, lock files). Start playstead-server from scratch. Server boots without errors, the three new curation migrations apply cleanly, and a primary query (console homepage or GET /api/v1/capabilities) returns live data.
result: pass
source: automated
evidence: |
  playstead-server/scripts/compose-smoke.sh --fresh, run 2026-08-31 in an isolated
  compose project (COMPOSE_PROJECT_NAME=playstead-uatsmoke, ports 18080/18443) so the
  owner's real playstead-server_* volumes were never touched. All assertions passed:
  volumes destroyed -> stack up -> all three services healthy -> /healthz 200,
  /api/v1/capabilities 200 -> single-use setup token banner (49 chars) -> /setup 200 ->
  /app/blobs writable, /app/inbox listable-but-not-writable (:ro bind mount),
  /app/exports writable -> marker row -> down + up -> healthy -> /healthz 200,
  /api/v1/capabilities 200 -> playstead_db volume survived with 1 marker row -> SUCCESS.
  Already wired into CI as the `compose-smoke` job (.github/workflows/ci.yml), gated by a
  dorny/paths-filter on the deployment surface — recurring value, no per-release human step.

### 2. Catalogue renders from a live paired server before any download
expected: On a normal interactive Mac session with a live paired server, launch the Mac app. At least one catalogue entry fetched from /api/v1/snapshot renders in the library without any bytes of that game having been downloaded first.
result: pass
source: automated
evidence: |
  Closed by hosted six-job verification run 33702909968 at 548121ea35f8ac4a7cf6242c6fd7889a37c48ac2, the live-server layer
  green, with every identifier below discovered, executed, non-skipped and passed.
  https://github.com/szTheory/playstead/actions/runs/33702909968
  Exact covering tests:
  - `LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch`
  Evidence boundary: Public pairing and /api/v1/snapshot render, fresh mirror, Keychain relaunch, and zero blob routes only; no real game bytes.
coverage_id: 03-03/D1

### 3. Library shell matches the locked UI spec
expected: The library shows its canonical 8-step navigation order, one status vocabulary matching 03-UI-SPEC.md's locked ladder table, honest empty states (first-run banner, zero-import invitation, per-shelf empty explanations), and card geometry/typography that never uses cover art or title-derived color.
result: pass
source: automated
evidence: |
  Closed by hosted six-job verification run 33702909968 at 548121ea35f8ac4a7cf6242c6fd7889a37c48ac2, the rendering layer
  green, with every identifier below discovered, executed, non-skipped and passed.
  https://github.com/szTheory/playstead/actions/runs/33702909968
  Exact covering tests:
  - `LibraryContractSnapshotTests/testCardAndStatusVisualContract`
  - `LibraryContractSnapshotTests/testSemanticContractOracles`
  - `LibraryContractSnapshotTests/testFiveCurationShelfVisualContract`
  Evidence boundary: Locked card geometry, status vocabulary, navigation order, honest empty states, and curation visual/semantic contract only.
coverage_id: 03-06/D2

### 4. Find any game by system, availability, and free-text search (web console)
expected: From the web console you can reach any imported game by system, by availability, and by free-text search. (Note: the availability dimension is deliberately incomplete this plan — see 03-05 key-decisions.)
result: pass
source: automated
evidence: |
  Clause-by-clause coverage (03-14, LIBR-02 gap closure — see
  03-14-SUMMARY.md for the full mapping this evidence block summarizes):

  - "reach any imported game by system": covered pre-existing by
    `test/playstead_web/live/library_live_test.exs` — "toggling a
    system chip and an availability chip each narrow the set, and a
    pressed chip carries aria-pressed" (system-chip half).
  - "by availability": the console's six-value filter genuinely
    discriminates over device-reported facts, proven end to end across
    both codebases:
    - Mac client actually builds and enqueues a real per-game report
      matching the server's accepted wire shape:
      `playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift`
      (all cases) and
      `playstead-mac/PlaysteadTests/CacheTests/AvailabilityVocabularyContractTests.swift`.
    - The server stores exactly what a device sends:
      `test/playstead_web/controllers/api/v1/availability_controller_test.exs`
      — "PUT devices/me/availability stores the reported facts".
    - All six filter values discriminate the browse set, no
      pass-through: `test/playstead_web/live/library_live_test.exs` —
      "each of the six values narrows the set to exactly its own asset
      set, excluding every other".
  - "by free-text search": covered pre-existing by
    `test/playstead_web/live/library_live_test.exs` — "searching a
    distinctive substring narrows the rendered set to the matching
    entries only".
  - The parenthetical note ("the availability dimension is deliberately
    incomplete this plan") is now stale and resolved by 03-13/03-14 —
    the dimension is complete as of this report.

  Commands run this session: `cd playstead-mac && xcodebuild test
  -scheme Playstead -destination 'platform=macOS'
  -only-testing:PlaysteadTests/AvailabilityReporterTests
  -only-testing:PlaysteadTests/AvailabilityVocabularyContractTests`
  (16 tests, 0 failures) and `cd playstead-server && mix test` (1065
  tests, 0 failures).
coverage_id: 03-05/D3, 03-13/D1, 03-13/D2

### 5. Downloads / quota / reclaim / storage click-through
expected: Against a live paired server on an interactive Mac session, click through DownloadsView, QuotaSettingsView, ReclaimPromptView, and StorageView. Visual fidelity, motion timing, and VoiceOver behavior match the spec; the queue/quota/reclaim/storage flows behave as described.
result: pass
source: automated
evidence: |
  Closed by hosted six-job verification run 33702909968 at 548121ea35f8ac4a7cf6242c6fd7889a37c48ac2, the rendering and ui layers
  green, with every identifier below discovered, executed, non-skipped and passed.
  https://github.com/szTheory/playstead/actions/runs/33702909968
  Exact covering tests:
  - `StorageContractSnapshotTests/testDownloadsQuotaReclaimAndStorageVisualContract`
  - `StorageContractSnapshotTests/testStorageMotionAndReducedMotionContract`
  - `StorageInteractionTests/testDownloadsPauseResumeFlow`
  - `StorageInteractionTests/testQuotaEditAndFocusRestoration`
  - `StorageInteractionTests/testReclaimPromptPostMutationPreservesCanonicalRows`
  - `StorageInteractionTests/testStorageInventoryPostMutationPreservesCanonicalRows`
  - `StorageInteractionTests/testStorageInventoryProtectsPinnedCopy`
  - `SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit`
  Evidence boundary: Visual, motion and reduced-motion, interaction, focus restoration, and machine-checkable live semantics/audits only; experiential VoiceOver remains blocked.
coverage_id: 03-07/D6

### 6. Curation shelf views and drag reorder by hand
expected: The five shelf views (Favorites, Collections, CollectionDetail, Queue, Continue/Recent) match 03-UI-SPEC.md's spacing/typography/status vocabulary, and the SwiftUI drag-to-reorder gesture works by hand. Play-session recording never delays or fails a launch, delivers idempotently after the fact, and each session is individually deletable.
result: pass
source: automated
evidence: |
  Closed by hosted six-job verification run 33702909968 at 548121ea35f8ac4a7cf6242c6fd7889a37c48ac2, the rendering, ui and unit layers
  green, with every identifier below discovered, executed, non-skipped and passed.
  https://github.com/szTheory/playstead/actions/runs/33702909968
  Exact covering tests:
  - `LibraryContractSnapshotTests/testFiveCurationShelfVisualContract`
  - `CurationInteractionTests/testContinueShelfRendersHonestEmptyFixture`
  - `CurationInteractionTests/testFavoritesShelfRendersExactSeededCard`
  - `CurationInteractionTests/testCollectionsShelfRendersExactSeededRoute`
  - `CurationInteractionTests/testQueueShelfRendersHonestEmptyFixture`
  - `CurationInteractionTests/testRecentShelfRendersHonestEmptyFixture`
  - `CurationInteractionTests/testDragReorderSurvivesRelaunch`
  - `CurationInteractionTests/testKeyboardReorderRetainsFocusAndSurvivesRelaunch`
  - `PlaySessionTests/test_launchSucceedsIndependentlyOfPlaySessionRecording`
  - `PlaySessionTests/test_offlineSession_isDeliveredAfterReachabilityReturns`
  - `PlaySessionTests/test_sameSessionIdentifierPostedTwice_resultsInOneServerSideEffect`
  - `PlaySessionTests/test_userDeletion_enqueuesDeleteIntentAndRemovesFromRecent`
  Evidence boundary: Shelf visuals, drag and keyboard reorder durability, launch independence, delivery idempotency, and individual deletion only.
coverage_id: 03-08/D3

### 7. Play a game end to end with the real emulator, offline
expected: With the real pinned emulator installed and a real downloaded game, network disabled: pressing Play starts the emulator, the game runs, and quitting returns to the library. An install-digest mismatch refuses to launch; exits classify into clean/crashed/killed per the pin.
result: blocked
blocked_by: third-party
reason: "Requires the pinned emulator installed locally plus a real downloaded game. Automatable on a self-hosted Mac runner with the emulator installed; the game bytes cannot ship in CI."
coverage_id: 03-03/D5

### 8. Controller connect / disconnect recovery on real hardware
expected: With a real game controller, unplug and reconnect it mid-use. Recovery is non-modal and never strands keyboard or pointer input.
result: blocked
blocked_by: physical-device
reason: "Requires physical game controller hardware. 03-SPIKE-REPORT.md probe 5 recorded this as unproven for the same reason."
coverage_id: 03-01/D4

### 9. Controller lifecycle: live-test, assign, remap, reset
expected: On real controller hardware: connect, live-test inputs, assign, remap bindings, and reset to defaults all work as designed.
result: blocked
blocked_by: physical-device
reason: "Requires physical game controller hardware. Logic is fully tested against the injectable ControllerInputSource; only real-hardware behavior is unverified."
coverage_id: 03-10/D1

### 10. Directional-pad / shoulder navigation and accessibility floor
expected: Every Mac surface is navigable by d-pad/shoulder buttons and by keyboard alone, and a live VoiceOver pass reads each surface sensibly (per docs/ACCESSIBILITY.md).
result: partial

#### Automated keyboard/live-tree record
result: pass
source: automated
evidence: |
  Closed by hosted six-job verification run 33702909968 at 548121ea35f8ac4a7cf6242c6fd7889a37c48ac2, the ui layer green.
  https://github.com/szTheory/playstead/actions/runs/33702909968
  Exact covering test:
  - `SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit`
  Evidence boundary: Keyboard-only navigation over every D-18 surface and
  machine-checkable live-tree labels, roles, state, hierarchy, focus, and audits only.

#### Blocked physical-controller/experiential record
result: blocked
blocked_by: physical-device-and-experiential-review
reason: "Physical controller d-pad/shoulder behavior needs real controller hardware, and experiential VoiceOver pronunciation, rotor behavior, sentence quality, and comprehension are human judgment. Both remain blocked and unclaimed; the automated record above must not be read as covering them."
coverage_id: 03-10/D2

### 11. Web console keyboard + screen-reader walkthrough
expected: A full experiential keyboard and VoiceOver walkthrough of the web console: every toggle exposes aria-pressed, every card's accessible name combines title/system/status, no state is conveyed by color alone, and the whole console is reachable by keyboard.
result: pass
source: automated
evidence: |
  Closed by test/playstead_web/browser/keyboard_reachability_test.exs (new, 16 features,
  all passing). Drives real Tab keypresses through chromedriver across the four Phase 3
  library surfaces and asserts, per screen: every rendered control is reached by sequential
  focus navigation; every focusable control has a non-empty accessible name (aria-label →
  aria-labelledby → <label> → text/value/title/alt); no interactive control is removed from
  the focus order with tabindex="-1"; and the Tab-focused control matches :focus-visible and
  draws an actual ring (outline or box-shadow), not a color-only cue.
  Each feature carries a non-vacuity guard (10-27 real focusables per screen were verified).
  The markup-level half of this checkpoint was already covered by library_live_test.exs.
  Residual human judgment: VoiceOver *sentence quality* (does the announcement read well),
  which is subjective and deliberately not automated.
coverage_id: 03-05/D7

### 12. Reduced-motion behavior on status transitions
expected: With prefers-reduced-motion enabled, the download progress fill is retained while status-change transitions become instant/crossfade.
result: pass
source: automated
evidence: |
  Closed by test/playstead_web/browser/reduced_motion_test.exs (new, 3 features, all passing).
  Launches a second Chrome session with --force-prefers-reduced-motion and asserts against
  the real shipped stylesheet: status-change glyph transitions are 0.15s normally and 0s under
  reduced motion, for all three transitioning ladder states (downloading/verified/pinned); and
  an element carrying its own information-bearing transition still computes 0.3s under reduced
  motion, proving the media query is scoped rather than a blanket `* { transition: none }`
  reset that would silently kill the download progress fill D-16 requires be retained.
  Both directions assert matchMedia() explicitly, so neither session can pass vacuously.
  app.css:334 previously had zero test coverage.
coverage_id: 03-05/D8

### 13. Drag-in BIOS validation with managed storage
expected: Dragging a BIOS file in validates it against a real reference digest, stores it in managed storage, and no acquisition path is offered anywhere in the UI.
result: partial
source: automated
evidence: |
  Gap A from 03-VERIFICATION.md closed by 03-11-PLAN.md. A real, two-source-cited
  reference for the pinned gba system (16384-byte length, SHA-256
  fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570) is pinned at
  .planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json and wired
  into PlaysteadApp's composition root via BiosReferences.production. The wiring
  and the rejection-discrimination half of this item are proven automatically:
  BiosProductionReferenceTests (3/3 passing) —
  - testProductionReferenceSetIsNonEmptyAndWellFormed
  - testProductionLiteralsMatchThePinFile
  - testStoreBuiltFromProductionReferencesReachesTheDigestComparison
  Run summary: "Test Suite 'BiosProductionReferenceTests' passed ... Executed 3
  tests, with 0 failures (0 unexpected)". BiosTests (22/22 passing, including the
  new discriminator, concurrency, and interruption-safety tests added by
  03-11-PLAN.md Tasks 2 and 3) confirms no regression.
  Remaining operator step: acceptance of real, legally-owned BIOS bytes has not
  been exercised in this environment. Cross-check a real file in one command via
  scripts/verify-bios-reference.sh <path> once you have one.
coverage_id: 03-09/D2

### 14. Notarized release pipeline, relaunch, and orphan prevention
expected: The Developer-ID-signed, notarized hardened-runtime release build launches; Gatekeeper accepts it without a user override; quitting prevents orphan emulator processes; relaunch after an application restart works with zero network calls; support documentation matches actual behavior.
result: pass
source: automated
evidence: |
  Closed by 03-12-PLAN.md Task 3 against a real notarized artifact (submission
  8465f74d-5468-4b73-9885-fb0ea1dafcdd, status Accepted, run 2026-09-11). See
  .planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md
  for the full transcript. `spctl --assess --type execute --verbose` accepted
  the build with source=Notarized Developer ID (no user override). RelaunchTests
  (2/2) ran against the exported notarized artifact and passed. The
  launch/exit/relaunch cycle (open -> pgrep confirms running -> osascript quit
  -> pgrep confirms exited -> reopen -> pgrep confirms running) completed with
  no FATAL, proving clean exit and no orphaned emulator process holds the save
  file open. Covering command: scripts/verify-notarized-release.sh.
coverage_id: 03-10/D3

### 15. Signing / notarization scripts run end to end
expected: With a real Developer ID Application certificate and PLAYSTEAD_TEAM_ID / PLAYSTEAD_DEV_ID_APP set, build-release.sh and sign-and-notarize.sh run end to end; the local dev-signed build/test succeeds with hardened runtime and sandbox disabled.
result: pass
source: automated
evidence: |
  scripts/verify-notarized-release.sh ran build-release.sh (archive + export
  succeeded), then sign-and-notarize.sh with PLAYSTEAD_REQUIRE_NOTARIZATION=1
  (strict mode) against the real Developer ID Application identity
  "Developer ID Application: Johnathan Bryan (6CH9Y797RU)". Hardened runtime
  (flags=0x10000(runtime)), non-sandboxed entitlement (app-sandbox=false), and
  no-nested-bundle were all asserted and held. notarytool submit --wait
  returned status: Accepted; stapler staple succeeded; spctl named
  source=Notarized Developer ID. Full verbatim transcript in
  .planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md.
  Covering command: scripts/verify-notarized-release.sh.
coverage_id: 03-03/D6

### 16. Notarization posture decision (PLAY-05)
expected: Notarized launch and Keychain access from a notarized build are DEFERRED (no paid Apple Developer Program membership this run). Confirm this is an acceptable interim state and that plan 03-10 closes the gap before PLAY-05 is promised to end users.
result: pass
source: automated
evidence: |
  The 2026-08-30 deferral was lifted on 2026-09-11: the owner enrolled in the
  Apple Developer Program, installed a Developer ID Application certificate
  and a notarytool credential profile, and answered the 03-12-PLAN.md Task 2
  blocking-human checkpoint "enrolled" after all three confirmation commands
  (security find-identity, xcrun notarytool history, and
  scripts/verify-notarized-release.sh --preflight-only) succeeded. Task 3 then
  produced and verified a genuinely notarized artifact (see items 14 and 15).
  PLAY-05 is no longer deferred.
coverage_id: 03-01/D3

### 17. Adapter pin file is complete and single-valued
expected: 03-ADAPTER-PIN.json pins exactly one (system, emulator, version, sha256) tuple and the adapter's launch/config-injection/save/exit contracts
result: pass
source: automated
coverage_id: 03-01/D1

### 18. Spike report records all seven D-01 probes
expected: 03-SPIKE-REPORT.md records a pass/fail/deferred verdict with evidence for all seven D-01 probes and the exact macOS build tested
result: pass
source: automated
coverage_id: 03-01/D2

### 19. Range GET serves 206 with correct headers
expected: GET /api/v1/blobs/:sha256 serves a single satisfiable Range as 206 with quoted ETag, Accept-Ranges, and Content-Range; LocalDisk's range clause reads positionally instead of loading the whole object
result: pass
source: automated
coverage_id: 03-02/D1

### 20. Frozen Range contract complete
expected: If-Range match/mismatch, 416 with Content-Range and registered problem+json code, HEAD mirrors GET headers with no body, multi-range/malformed/suffix/foreign-unit headers collapse to full 200, single-byte edge range and clamped over-long range both correct, zero-length blob handled
result: pass
source: automated
coverage_id: 03-02/D2

### 21. Transfer capability advertises range-resume
expected: transfer capability namespace advertises range-resume via max version 1.1.0, with the frozen /api/v1/capabilities envelope shape provably unchanged and version-skew negotiation degrading to compatible_with_limits, never incompatible
result: pass
source: automated
coverage_id: 03-02/D3

### 22. Xcode file-system-synchronized source groups
expected: Xcode project uses file-system-synchronized source groups — adding a new Swift file across all three tasks required zero project.pbxproj edits
result: pass
source: automated
coverage_id: 03-03/D2

### 23. Content-addressed cache writes only after verification
expected: Downloading one blob writes it into a content-addressed cache only after full-stream SHA-256 verification; interrupted/resumed/200-instead-of-206/416/digest-mismatch/zero-byte cases all behave per D-18
result: pass
source: automated
coverage_id: 03-03/D3

### 24. Launch directory materialization never hard-links
expected: Launch directory materialization clones/copies (never hard-links); writing into a materialized file leaves the source cache object's digest unchanged; PreflightChecker makes zero network calls
result: pass
source: automated
coverage_id: 03-03/D4

### 25. Favorites ride the journal/snapshot/idempotency spine
expected: Favorites ride the change-journal/snapshot/idempotency spine end to end: schema, scoped context, curation entity kind, snapshot branch, idempotent REST intent
result: pass
source: automated
coverage_id: 03-04/D1

### 26. Fractional-index ordering for collections and queue
expected: Collections and the play queue are ordered by fractional index, insertable between any two neighbours, rebalanceable without visible reordering, and capped at 500/5000/500
result: pass
source: automated
coverage_id: 03-04/D2

### 27. Play sessions, Recent, and Continue are honest derivations
expected: Play sessions, Recent, and Continue are honest derivations of coarse recorded sessions; dismissals are reversible by play; nothing on this path blocks a launch
result: pass
source: automated
coverage_id: 03-04/D3

### 28. Curation is scoped to the owning user
expected: Every curation query and mutation is scoped to the owning user; a request naming another user's row or neighbour returns 404, never that user's data
result: pass
source: automated
coverage_id: 03-04/D4

### 29. Five curation shelves render from context functions
expected: All five curation shelves (Continue, Favorites, Collections, Queue, Recent) render on Home from Playstead.Curation context functions, with no curation query written inside the LiveView
result: pass
source: automated
coverage_id: 03-05/D1

### 30. Console mutations match equivalent API calls
expected: Favoriting, enqueueing, reordering, and creating a collection from the console produce the same rows and journal entries the equivalent API calls would
result: pass
source: automated
coverage_id: 03-05/D2

### 31. Empty systems and empty shelves behave honestly
expected: A system with zero assets is hidden until show-all-systems is activated, and the control states the hidden count; an empty curation shelf is hidden from Home while its sidebar entry remains with a one-line explainer
result: pass
source: automated
coverage_id: 03-05/D4

### 32. Status slot implements the full D-13 priority ladder
expected: The single status-slot component implements the full D-13 priority ladder — one indicator per card, a distinct glyph/shape/color per rank, an accessible-name sentence, and a list-view text label
result: pass
source: automated
coverage_id: 03-05/D5

### 33. 500-asset library renders via LiveView stream
expected: A library of 500 asset sets renders through a LiveView stream with fixed row heights and no loading skeleton
result: pass
source: automated
coverage_id: 03-05/D6

### 34. Local read model converges via snapshot/journal/cursor
expected: The Mac's local read model converges with the server through the snapshot/journal/cursor recovery spine alone: empty-store bootstrap, cursor-resumed changes paging, cursor-expired full reset with no duplicates, idempotent replay, unknown-entity-kind forward compatibility, and a transport failure leaving the stored cursor and read model byte-identical
result: pass
source: automated
coverage_id: 03-06/D1

### 35. Offline search/filter across a large library
expected: A user can find anything in a large library by search (display title and original filename, diacritic-insensitive), system, or availability, from keyboard or pointer; controller narrows via chips only; a search matching nothing explains itself; the library renders its full local entry count and a last-synced indicator with every network request stubbed to fail; zero-entry systems hidden behind a count-labeled control
result: pass
source: automated
coverage_id: 03-06/D3

### 36. Enqueue covers every manifest member and collection
expected: Choosing a game enqueues every manifest member in order; a repeat enqueue is a no-op; a collection enqueues every member of every game in the collection's order; a single-member game behaves identically to a many-member game
result: pass
source: automated
coverage_id: 03-07/D1

### 37. Availability states derived at read time
expected: The six availability states are derived at read time from queue rows, partial presence, cache presence, and the pin flag — never a stored column — and reproduce identically after deleting and rebuilding the local database from the on-disk cache; the card never receives safe-to-evict
result: pass
source: automated
coverage_id: 03-07/D2

### 38. DownloadCoordinator single-transfer scheduling
expected: DownloadCoordinator drives exactly one transfer at a time through the existing DownloadEngine, selecting by pin priority then queue position, recording the cache object and verify record on completion, re-enqueueing with an incremented attempt count on a digest mismatch, and treating offline as a normal state that resumes on its own
result: pass
source: automated
coverage_id: 03-07/D3

### 39. Quota and free-space floor bound capacity
expected: Capacity is bounded by a quota and a free-space floor with the floor winning when both would be crossed, pinning means never-evict and download-first, and hitting a limit pauses the item and surfaces a reclaim prompt rather than deleting anything
result: pass
source: automated
coverage_id: 03-07/D4

### 40. Manual reclaim is LRU-ordered and conservative
expected: Manual reclaim is LRU-ordered, excludes anything not fully verified or pinned, excludes any object with no server-side record (reporting it separately as unreferenced), only frees a shared object when every referencing game is selected, states the exact byte total before anything happens, and never removes a game's library row
result: pass
source: automated
coverage_id: 03-07/D5

### 41. Durable per-row idempotent offline outbox
expected: A favorite applies to the local read model immediately, survives an app restart while unsent, sends exactly once when reachable, reverts and surfaces a problem code on permanent rejection, and reconciles through the journal without duplicating
result: pass
source: automated
coverage_id: 03-08/D1

### 42. Offline collections, queue, and dismissals
expected: Collections, the play queue, and Continue dismissals all work offline; a drag reorder settles to exactly one intent naming the moved item and its two neighbours; an offline reorder and a concurrent remote addition both survive; FractionalPosition matches the server's own base-36 encoding
result: pass
source: automated
coverage_id: 03-08/D2

### 43. Adapter install/select with pin-sourced capability card
expected: Install or select the pinned adapter with an honest, pin-sourced capability card
result: pass
source: automated
coverage_id: 03-09/D1

### 44. Readiness engine: six checks, zero network
expected: Readiness engine: six checks, ordered severity, a remedy each, zero network
result: pass
source: automated
coverage_id: 03-09/D3

## Defects Found During Verification

- id: D-03-EXPORTS-OWNERSHIP
  found_by: "compose-smoke CI job, first run on a Linux runner (2026-08-31)"
  phase_origin: 02 (PORT-02 export)
  severity: major
  truth: "A self-hoster who clones the repo and runs `docker compose up` can write exports."
  symptom: "[compose-smoke] FAIL: /app/exports is not writable inside the app container"
  root_cause: |
    docker-compose.yml bind-mounts ./exports over /app/exports. A bind mount carries the
    HOST directory's ownership into the container and discards the image's own chown, so
    the Dockerfile's `chown nobody /app/exports` had no effect. Because ./exports is not
    tracked in git, Docker created it root-owned on a fresh clone, and the app — running
    as `nobody` — could not write any export. Named volumes (/app/blobs) are unaffected:
    Docker seeds a fresh named volume from the image path, ownership included.
  why_missed: |
    Invisible on macOS — Docker Desktop's VirtioFS translates UIDs, so bind-mount
    ownership never bites. Fatal on Linux, which is where self-hosters deploy. The local
    run of this same script also masked it by creating ./exports as the host user first.
    CI had never run before today (the repo had no git remote), so nothing had ever
    executed this path on Linux.
  fix: |
    rel/entrypoint.sh runs as root only long enough to chown the export path, then drops
    to nobody via setpriv (already present in the Debian runner image) before exec'ing the
    release. `USER nobody` was removed from the Dockerfile so the entrypoint can do this;
    the server process itself still runs as nobody.
  regression_guards: |
    compose-smoke.sh now asserts PID 1 runs as uid 65534 by reading /proc/1/status — not
    via `docker compose exec`, which starts a fresh process as the image's default user
    (now root) and would report root regardless. All writability probes were switched to
    `exec --user nobody` for the same reason: with USER removed, a bare exec runs as root
    and every one of those probes would have passed vacuously.
  status: fixed

## Summary

total: 44
passed: 39
issues: 0
pending: 0
skipped: 0
blocked: 3
partial: 2

## Gaps

[none yet]
