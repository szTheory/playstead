---
status: partial
phase: 03-mac-offline-play-vertical-slice
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md, 03-06-SUMMARY.md, 03-07-SUMMARY.md, 03-08-SUMMARY.md, 03-09-SUMMARY.md, 03-10-SUMMARY.md, 03-11-SUMMARY.md, 03-12-SUMMARY.md, 03-13-SUMMARY.md, 03-14-SUMMARY.md, 03-15-SUMMARY.md, 03-16-SUMMARY.md
started: 2026-08-31T00:00:00Z
updated: 2026-09-11T18:00:00Z
---

## Current Test

[testing paused — 6 items outstanding: 3 blocked (items 7, 8, 9 — real emulator + game bytes, and physical controller hardware), 3 partial (item 10's physical-controller/experiential-VoiceOver half, item 13's real-BIOS-bytes acceptance, item 45's rendered-surface half). Items 45-49 were merged from plans 03-11/03-13/03-15, whose human checkpoints had never reached this file; 46, 47, 48 and 49 were closed by new automation this session, and 48 turned out to be a real defect (see its evidence). This annotation and the Summary footer below are recomputed by `scripts/check-uat-tally.sh` from this file's own per-item results, not hand-maintained.]

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
reason: |
  Requires the pinned emulator installed locally plus a real downloaded game.
  Automation path (not yet built, needs an owner decision): a self-hosted Mac
  runner with the pinned emulator installed, driving the real AdapterHost
  against a freely-redistributable homebrew GBA ROM committed as a fixture.
  The homebrew-ROM choice is a licensing decision for the owner, not something
  to assume; commercial game bytes can never ship in CI.
coverage_id: 03-03/D5

### 8. Controller connect / disconnect recovery on real hardware
expected: With a real game controller, unplug and reconnect it mid-use. Recovery is non-modal and never strands keyboard or pointer input.
result: blocked
blocked_by: physical-device
reason: |
  Requires physical game controller hardware. 03-SPIKE-REPORT.md probe 5
  recorded this as unproven for the same reason.
  Automation path (not yet built): a virtual HID gamepad created with
  IOHIDUserDevice, which the GameController framework enumerates as a real
  controller, so connect/disconnect can be driven from a test rather than by
  hand. This is real work — a new test-only HID descriptor plus lifecycle
  plumbing — and is a plan of its own, shared with items 9 and 10.
coverage_id: 03-01/D4

### 9. Controller lifecycle: live-test, assign, remap, reset
expected: On real controller hardware: connect, live-test inputs, assign, remap bindings, and reset to defaults all work as designed.
result: blocked
blocked_by: physical-device
reason: |
  Requires physical game controller hardware. Logic is fully tested against the
  injectable ControllerInputSource; only real-hardware behavior is unverified.
  Automation path (not yet built): the same IOHIDUserDevice virtual gamepad
  item 8 names. Once a virtual device enumerates, live-test/assign/remap/reset
  are all drivable from XCUITest against the real ControllerSettingsView.
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
reason: |
  Physical controller d-pad/shoulder behavior needs real controller hardware, and experiential VoiceOver pronunciation, rotor behavior, sentence quality, and comprehension are human judgment. Both remain blocked and unclaimed; the automated record above must not be read as covering them.
  (The two phrases above are pinned verbatim by validate-phase-3-uat-evidence.py and must stay on one line each: it substring-matches the raw block, so re-wrapping them silently breaks the guard.)

  Paths to closing each, recorded so this does not stay a bare "needs
  hardware" the way items 7/8/9 did before their own entries were expanded:

  1. The controller half is closable by the same route as items 8 and 9: an
     `IOHIDUserDevice` virtual gamepad that the GameController framework
     enumerates as a real device, which would close 8, 9 and this half
     together. One plan's worth of work, not a permanent blocker.

  2. The VoiceOver half stays human judgment and there is no honest path to
     automating it. The machine-checkable floor — labels, roles, state,
     hierarchy, focus order, audits — is already closed above by
     `SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit`.
     What remains is whether the result is actually comprehensible to listen
     to, which no assertion settles.
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
  03-11-PLAN.md Tasks 2 and 3) confirms no regression. BiosTests is 25 tests as
  of this entry.
coverage_id: 03-09/D2

#### Automated no-acquisition-path record
result: pass
source: automated
evidence: |
  `BiosTests/testNoShippedBiosCopyAnywhereOffersAnAcquisitionPath` sweeps EVERY
  shipped Swift file under `Playstead/`, not the two the previous grep covered.
  This item claims no acquisition path is offered anywhere in the UI; eight
  shipped files carry user-facing BIOS copy, and the six the old grep never
  looked at include `ReadinessEngine.swift`, whose remedy text "Drop in a BIOS
  file" is the most tempting place in the app to add "...you can get one here".
  The claim was broad and the proof was narrow.

  It reads string literals rather than raw source because that is what the
  requirement is about: `BiosReferences.swift` cites three URLs in a doc comment
  as provenance for the pinned digest, which is scholarship, not an offer, and a
  raw-source grep cannot tell the two apart.

  Falsified: planting `https://example.invalid/bios` into ReadinessEngine's BIOS
  remedy leaves the OLD two-file grep GREEN and fails this sweep — the gap was
  real, not theoretical. Non-vacuity is asserted too (>=20 BIOS literals found,
  and ReadinessEngine/AdapterCapabilityCard/BiosDropTarget each still present);
  renaming ReadinessEngine's five BIOS literals away fails it with "the remedy
  copy is no longer being swept". Registered as a `--required-test` on the unit
  layer, so a zero-discovery run fails closed.

#### Blocked real-BIOS-acceptance record
result: blocked
blocked_by: legally-owned-artifact-required
reason: |
  Acceptance of real, legally-owned BIOS bytes against the PRODUCTION reference
  has never been exercised. This is not automatable, and not for want of effort:
  the pinned gba reference is a SHA-256
  (fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570), so bytes
  that satisfy it cannot be fabricated by any test — that is the entire point of
  pinning a digest. `BiosProductionReferenceTests/testStoreBuiltFromProduction\
  ReferencesReachesTheDigestComparison` proves the production set is wired and
  REJECTS a correctly-sized non-matching candidate; the accept branch against the
  production digest needs the real file and nothing else will do.

  Recorded here as an explicit sub-record rather than, as before, a sentence of
  prose at the end of the `evidence:` block, where no audit could see it.

  Path to closing it: obtain a legally-owned dump of the operator's own console
  and run `scripts/verify-bios-reference.sh <path>`, which performs exactly the
  length-then-digest comparison the store performs. Same class as items 7/8/9 —
  it needs a physical artifact, not more test code — and it must NOT be read as
  covered by the automated records above.

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

### 45. BIOS drop surface renders the exact no-blame rejection reason
expected: Drag a non-matching BIOS file onto the BIOS drop surface. The surface renders the store's exact no-blame rejection reason as explanatory copy — never a blank pane and never a generic failure string.
result: pass
source: automated
evidence: |
  Closed at BOTH layers. The logic layer was closed locally; the
  rendered-surface layer was closed by its first-ever execution on the
  hosted runner in CI run 34636187313 (2026-09-11), which is what flipped
  this item from partial to pass (see the sub-records below).
coverage_id: 03-11/D7

#### Automated store-reason record
result: pass
source: automated
evidence: |
  `playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift` (24/24 passing,
  run 2026-09-11 via `xcodebuild test -testPlan Unit`):
  - `testRejectionMessageQuotesTheStoreReasonVerbatim` — pins the exact copy
    for three distinct store errors (contents mismatch, wrong size, unknown
    system), one per line.
  - `testEveryRejectionIsDistinguishableAndNoneIsTheGenericFallback` — no
    store error falls through to the generic "This file could not be
    validated." string, none is empty, and no two distinct failures render
    identical copy.
  The pre-existing `testBiosDropTargetRejectsANonMatchingDroppedFileWithAReason`
  only asserted the reason was non-empty, which the generic fallback also
  satisfies. Evidence boundary: the reason `BiosDropTarget` produces; NOT that
  the view renders it.

#### Rendered-surface record
result: pass
source: automated
evidence: |
  EXECUTED AND PASSING on the hosted runner. CI run 34636187313, job
  "macOS 26 unit + rendering + UI + live server", UI layer:
  `ui: verified 53 required test(s) across 113 executed test(s)` then
  `ui: PASSED`. Both features of `BiosRejectionCopyTests` are registered
  as `--required-test` entries, and the layer verifier emits one
  `required test did not pass: <identifier> (<result>)` line per failing
  or undiscovered required test before it will print its summary — the
  same mechanism that failed the live-server layer in this very run for
  `SaveEndToEndTests`. The UI layer emitted no such line, so both
  features were discovered and both passed. Executed count rose 111 -> 113,
  matching the two features this plan added: a zero-discovery run would
  have failed closed rather than passed quietly.

  This is the first execution of these features anywhere. The local
  blocker recorded below was environmental, never a defect in the test,
  and the hosted runner is exactly the path it was registered for.

previously_blocked_by: xcuitest-automation-permission
reason: |
  `playstead-mac/PlaysteadUITests/BiosRejectionCopyTests.swift` (new) drives
  the real packaged app: `.storage` profile -> production readiness route ->
  production BIOS surface -> production "Choose File…" control -> reads the
  rendered copy back off `playstead.readout.bios-status` and asserts it equals
  the store's exact sentence, is non-empty, and is not the generic fallback. A
  second feature proves a refused candidate path leaves the surface untouched
  rather than fabricating a rejection. Supporting production changes:
  `AccessibilityIdentifiers.Readout.biosStatus` on the status Text, and
  `UITestBiosCandidate` (a `#if UI_TESTING` env-var seam, path-validated for
  containment/regular-file/non-symlink) because a headless XCUITest can drive
  neither a drag session nor an NSOpenPanel.
  `xcodebuild build-for-testing -testPlan UI` SUCCEEDS. Execution does not:
  every XCUITest in this environment, including pre-existing ones
  (`CurationInteractionTests` was run as a control), fails with "The test
  runner failed to initialize for UI testing. (Underlying Error: Timed out
  while enabling automation mode.)" — an interactive Accessibility/Automation
  grant this session cannot make. Registered in `TestPlans/UI.xctestplan` and
  as two `--required-test` entries in `scripts/ci/run-mac-verification.sh`, so
  the hosted six-job runner executes it and a zero-discovery run fails closed.

### 46. Availability chips under a real screen reader
expected: With a real screen reader running, walk the web console's six availability chips. Each chip's accessible name reads sensibly, its pressed state is announced (not conveyed by color alone), and every chip is reachable from the keyboard.
result: pass
source: automated
evidence: |
  Closed by `test/playstead_web/browser/availability_chip_semantics_test.exs`
  (new, 5 features, all passing; run 2026-09-11). Drives real Tab keypresses
  and reads real computed styles through chromedriver:
  - every one of the six frozen vocabulary chips is reached by sequential
    focus navigation;
  - each chip's `aria-label` equals its exact `AvailabilityVocabulary
    .accessible_name/1` sentence;
  - pressing one chip moves `aria-pressed` to it and off every other chip;
  - the pressed state is carried by two non-color channels (border-width and
    font-weight both grow) while a sibling chip keeps the unpressed treatment;
  - a focused chip draws a real outline or box-shadow ring.
  Non-vacuity observed this session: replacing `.filter-chip[aria-pressed=
  "true"]`'s `border-width`/`font-weight` rule with a color-only `color:`
  swap made "the pressed state is carried by something other than color" fail;
  restoring it returned 5/5. Checkpoint 11's walkthrough predates these chips
  (03-13 created them), so nothing had ever driven them.
  Residual human judgment: screen-reader *sentence quality* only — the same
  deliberately-unautomated residue checkpoint 11 records.
coverage_id: 03-13/D4

### 47. 500-entry library toggle re-streams without a skeleton
expected: With a 500-entry library loaded, toggle an availability or system chip. The browse list re-streams directly to its new contents — no loading skeleton and no intermediate empty frame.
result: pass
source: automated
evidence: |
  Closed by `test/playstead_web/browser/library_restream_test.exs` (new, 2
  features, all passing; run 2026-09-11). Seeds a real 500-entry library,
  then samples `#library-asset-stream`'s `childElementCount` on every
  `requestAnimationFrame` across a chip toggle — painted frames, which is
  what the checkpoint is actually about and what `Phoenix.LiveViewTest`
  structurally cannot see (it only observes settled HTML).
  Every filter change calls `stream_filtered_assets(socket, reset: true)`, so
  a clear-then-refill landing in two paints would blink the whole library
  empty; the narrowing direction (500 -> 50) and the widening direction
  (50 -> 500) are both covered.
  Asserts: no sampled frame has zero rows; no skeleton / `animate-pulse` /
  `animate-spin` / `aria-busy` element is ever painted inside the stream.
  Non-vacuity is structural, not a comment: each feature asserts the sampled
  frame counts reach BOTH 500 and 50, so a sampler that only caught one
  settled end — or never ran at all — fails rather than passing silently.
coverage_id: 03-13/D5

### 48. In-progress download uses the determinate progress indicator
expected: With a download in progress, the list-view status slot shows the existing determinate percent-bearing progress indicator — not a second, separate loading treatment.
result: pass
source: automated
evidence: |
  This checkpoint was hiding a real defect, found and fixed this session.
  `library_live.ex`'s list row passed ONLY `queued:` into `status_slot/1`, so
  `rank/1` could never reach any rung above `queued` in list view —
  `downloading` (the single rung carrying the determinate percent D-16
  requires be retained), `missing_dependency` and `needs_attention` were all
  structurally unreachable there. Meanwhile the row's own `aria-label` went
  through `StatusSlot.describe/2` with the FULL status the whole time, so a
  downloading row announced "is downloading, 42 percent complete" to a screen
  reader while its visible badge read "On server".
  Fix: a `list_status_slot/1` wrapper passing the complete ladder, mirroring
  what `GameCard` already passed in grid view.
  Guarded by two new tests in `test/playstead_web/live/library_live_test.exs`
  (39 tests in file, 0 failures; run 2026-09-11):
  - "a downloading game's list row shows the determinate percent, and its
    badge agrees with its accessible name" — asserts `data-status="downloading"`,
    the visible "Downloading — 42%" label, the matching accessible sentence,
    exactly one `data-status-slot` on the row, and no second loading treatment
    beside it (scoped to the row: the page-level flash group ships a
    permanently-rendered hidden reconnect spinner, so a document-wide refute
    could never hold).
  - "every ladder rung the grid card can show is reachable in list view too" —
    the general form of the defect, one rung per assertion line.
  Non-vacuity observed this session: reverting the production fix made both
  tests fail; restoring it returned 39/39.
coverage_id: 03-13/D6

### 49. Unchanged availability report still encodes and enqueues
expected: Trigger an availability report twice with no change to the entry list between passes. The second pass still encodes and enqueues without error (no no-op short-circuit that silently drops the report).
result: pass
source: automated
evidence: |
  Closed by two new tests in
  `playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift`
  (19/19 passing; run 2026-09-11 via `xcodebuild test -testPlan Unit`):
  - `test_secondPassOverUnchangedState_enqueuesAgainRatherThanShortCircuiting`
    — an unchanged world produces an identical entry list, the second pass
    still builds and enqueues its OWN intent (proved by a counting id
    generator reaching 2), 03-16's newest-wins supersede leaves exactly one
    report queued, and the survivor's idempotency key is the SECOND pass's —
    so supersede dropped the older report, not the newer one. That direction
    is the part an outbox count alone cannot distinguish.
  - `test_unchangedSecondPassEncodesToTheSamePayloadAsTheFirst` — two
    successive `buildEntries` passes over an unchanged world produce the same
    entry (asserted field by field, each on its own line) and the same decoded
    wire payload, with a non-vacuity guard that the compared body is a real
    populated report (verified + pinned true), not two equal empty ones.
    Written first as a BYTE comparison, which failed once in a full-suite run
    with `("142 bytes") is not equal to ("142 bytes")` — both bodies carried
    identical values in a different key order. `JSONEncoder` makes no
    key-order guarantee, so byte-identity was a claim the system does not
    provide; the neighbouring, pre-existing
    `test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture` is
    misnamed for the same reason and already compares decoded values. No
    production defect: `Outbox` derives its idempotency key from `kind` plus
    the entry id, never from body bytes.
  The pre-existing `test_sameReportRetried_...` proves ONE intent re-sent, not
  two passes enqueued — which is why 03-15 left this unclassified.
coverage_id: 03-15/D7

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

total: 49
passed: 44
issues: 0
pending: 0
skipped: 0
blocked: 3
partial: 2

## Gaps

[none yet]
