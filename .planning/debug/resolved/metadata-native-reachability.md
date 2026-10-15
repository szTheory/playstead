---
status: resolved
trigger: "Phase 04.7 Plan 09 packaged metadata candidate selection cannot be reached reliably"
phase: "04.7"
plan: "09"
created: "2026-10-12"
updated: "2026-10-13"
---

## Automated resolution

The entire current-source packaged journey passed on 2026-10-13: `selected-live-server.OwYAws`, `MetadataPrivateMediaJourneyTests.testPrivateMediaExportAndProviderDisclosureUsePairedProductionRoutes`, one required identity executed once, zero failures/skips, 74.347 seconds. `04.7-09-LIVE-FINAL-EVIDENCE.json` binds source and raw result lineage. Actual paired-server private PNG/JPEG/text upload and exact-byte export, provider text disclosure, preparation, two offline durable field edits, retained conflict alternatives, explicit resolution, reset/relaunch and loaded artwork passed through the production composition. No external lookup occurred.

The final run supersedes earlier reachability/decoder/fixture/revision/test-predicate failures. `gyJnRk` is retained as a failed oracle attempt; it proved loaded artwork in the AX label and subsequent real actions, but was never counted as a whole pass. `OwYAws` supplies the whole pass. No owner performed verification; `human_judgment: false`.

All foreground windows are released. Exact task app/runner inventory is empty; native service root, decoder container/network, synthetic profiles and isolated test credentials were cleaned by the wrapper. There is no pending Ready or app launch prerequisite.

Next command: `$gsd-execute-phase 4.7` for the remaining phase verification/state transition. This debug session is resolved; do not repeat the live journey without a relevant change or new failure.

## Historical checkpoint (superseded)

## Current Focus

2026-10-12 resumed execution: current-source run selected-live-server.LMF3ir reached all private uploads and image exports, then failed cover selection. Native app interaction ended in41.568 seconds and app terminated. New cause: MetadataCoordinator and Outbox used the whole selection revision when an individual field had no revision. New fields must use0. Shared MetadataSelection.revision(forField:) preserves legacy description-only revisions while direct mutation/provider reset/outbox use per-field bases. RED selected-unit.9CVFIk:2 failed tests for9vs0. GREEN selected-unit.6sa6y4:13/13 affected coordinator/outbox/journal/tracer tests,0skips. Post-fix packaged journey remains unknown and requires a new foreground window after build; earlier pending-next-action text below is historical. Root owns field fix/source evidence, subagent /root/phase_04_7_ui_coverage owns53-state fixture/action source.

hypothesis: The live journey had three independent blockers: a premature offscreen isHittable test assertion, no media decoder endpoint in native mac_ci, and a PNG fixture with a corrupt IDAT CRC. The resumed run exposed a fourth premature oracle: XCTest's checkbox `value as? String` was nil despite synthesizing the click.
test: Assert the selected game's count in the server-backed preparation review after estimation, rather than relying on the checkbox's representation. Add a supported LiveServer build-only path so compilation stops before any app launch, then use test-without-building only after a fresh Ready window.
expecting: The review says `1 games` after the checkbox action; a zero count or absent review refutes selection. The build-only path exits without starting Phoenix, decoder, or Playstead.
next_action: Wait for a fresh parent-coordinated owner Ready window, then run `PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 scripts/ci/run-mac-verification.sh --layers live-server --test-without-building --only-testing PlaysteadUITests/MetadataPrivateMediaJourneyTests/testPrivateMediaExportAndProviderDisclosureUsePairedProductionRoutes` from playstead-mac. If the sandbox rejects PostgreSQL initdb shared memory, use the previously authorized narrow escalation. Inspect candidate/receipt/custody postconditions and exact cleanup. Do not launch until the new Ready.
bug_class: Bohrbug in the test's deterministic offscreen precondition; upload rejection remains unclassified.
reasoning_checkpoint:
  hypothesis: "The test fails candidate reachability because clickWhenHittable asserts before XCTest auto-scrolls; the later image upload fails because native mac_ci has no decoder endpoint and its embedded PNG CRC is invalid."
  confirming_evidence:
    - "Raw test log reports assertion failure at line 148, then click() scrolls playstead.settings.content to the candidate."
    - "The same pattern repeats at preparation checkbox and PNG upload; subsequent preparation review and enqueue execute."
    - "runtime.exs receives no decoder socket from native mac_ci, so MediaDecoder returns decoder_unavailable for images."
    - "The embedded PNG's IDAT CRC is invalid by independent zlib calculation."
  falsification_test: "If direct XCTest click fails to persist selection, or valid authored PNG plus the isolated decoder still fails to create an original receipt, the corresponding cause is incomplete."
  fix_rationale: "Native XCTest click already performs observed scroll-to-visible; asserting the persisted result measures the action. A bounded decoder endpoint restores the production decode path; a generated PNG fixes corrupt test input."
  blind_spots: "No new packaged run has yet verified either change; image upload could have another independent failure after the decoder is supplied."
  candidate_causes:
    - "code: pre-click isHittable helper rejects a valid offscreen control"
    - "config/environment: native mac_ci runner omits the production media decoder endpoint"
    - "data: embedded test PNG has a bad IDAT CRC, rejected by production libvips"
  and_gate: "Yes for the full live journey: the test assertion fails before the click, while image upload needs both a decoder endpoint and a valid PNG."

## Symptoms

expected: Authenticated GBC disclosure/consent/search returns a suggestion; an explicit user selection reaches the real server, then preparation and private-media/correction convergence complete in the packaged Mac.
actual: Correct imported UUID, title/system, disclosure, consent and fake-provider search succeed. The suggestion selection button remains non-hittable to XCTest. Fixed swipes overscrolled; the later coordinate scroll did not visibly move the content in the saved video. UI/action state coverage remains incomplete.
errors: selected-live-server.irp04F failed at candidate reachability. Video shows selection below the viewport; a later AX attachment shows candidate above it. Do not flatten this timing/coordinate discrepancy into a confirmed product bug.
timeline: During existing Plan 09 execution. Nine earlier plans are complete; Plan 09 has committed controls/routes/contracts but no completion summary.
repro: Prepared exact wrapper selector in HANDOFF.json; no app launch until a fresh short owner Ready window. Current task app/server cleanup was reported; no background run remains.

## Evidence

- Current source: playstead-mac/Playstead/Settings/MetadataSettingsView.swift and PlaysteadUITests/MetadataPrivateMediaJourneyTests.swift.
- Current failure: playstead-mac/.build/ci/selected-live-server.irp04F/raw/live-server.log and result bundle.
- AX: /private/tmp/metadata-journey-current/140A9F41-3188-413C-AED0-51E29E212029.txt.
- Video: /private/tmp/metadata-journey-current-all/BB06E276-8FE6-4695-9C7C-6D92D7191E50.mp4; /private/tmp/metadata-journey-frame-14.png.
- AX viewport {{504,271},{732,520}}, candidate {{525,88},{114.5,24}} in late snapshot; video frames 14–17 show no visible scroll movement and candidate below the viewport. Capture times differ.
- Six exact production coordinator/API selectors passed once without skips; commit 99e1dcd and selected-unit.Nlxf4V receipt. Outbox replay/conflict tests from Plan 07 also qualify their seams.
- The 53-state paint harness is explicitly verification=false for per-state AX/action predicates. Do not claim labels or view mounting prove those states.
- An invalid four-segment Rendering selector silently executed the unrelated StorageContract target and found a pixel mismatch. This is invalid metadata evidence and exposes a needed fail-closed selector check; baseline attribution is not proved.
- Invalid Keychain service prefix was fixed. Owner explicitly approved SIGTERM only for verified UserNotificationCenter PID 29384; exit was verified. Subsequent run reached Settings without the stale crash alert. No authority to kill another system service/PID.
- Foreground interruptions are inconclusive. Owner Ready windows are availability coordination, not product UAT. Latest window has ended; do not fight Chrome or launch personal-profile apps.
- Raw `selected-live-server.irp04F/raw/live-server.log` lines 1157-1172 show the candidate pre-click `isHittable` assertion fails, then XCTest `click()` scrolls `playstead.settings.content` to visible. It proceeds to preparation review and enqueue. The same false precondition occurs for the preparation checkbox and PNG upload. Thus saved evidence contradicts product candidate unreachability; the test's premature oracle is the candidate failure.
- The late AX attachment shows an `Upload rejected` status and no media receipt. The upload is a separate unclassified failure after the click; the saved screenshot cannot establish its error source because `MetadataSettingsView.upload` catches and flattens every error.
- The native `start_native_services` launcher starts Phoenix/Postgres but never supplies `PLAYSTEAD_MEDIA_DECODER_SOCKET`; `runtime.exs` consequently sets `:media_decoder_socket` to nil. `MediaDecoder.decode` deterministically returns `:decoder_unavailable` for PNG/JPEG, which the API maps to `invalid_media` and the UI flattens to `Upload rejected`. Production Compose supplies a required isolated decoder. Docker Desktop cannot share a live Unix socket with the macOS host through its bind mount (`connect` refused; bind-mounted socket chmod returns EINVAL), so the mac_ci fixture needs a loopback-only transport while running the real isolated decoder.
- Python chunk CRC inspection found the journey PNG IDAT stored CRC `0xefbfa59b` versus calculated `0xefa2a75b`. Apple ImageIO parsed it, while the decoder invokes libvips with `--fail-on warning`. The older decoder test PNG also carried an invalid IDAT CRC; its fixture was corrected.
- An isolated decoder container bound only to host loopback accepted a valid authored PNG through the native test bridge and emitted a bounded PNG derivative. The final sidecar flags, including seccomp, were separately checked for host reachability. Docker Desktop did not publish a port from an `--internal` network, so the test bridge uses a throwaway bridge network with no secrets mounted; production Compose retains `network_mode: none` and its Unix socket.
- Deterministic checks: `MIX_ENV=test mix test test/playstead/metadata/media_decoder_test.exs --exclude packaged_media_decoder` passed 1/1 newly targeted loopback wire test (three Docker-heavy packaged tests excluded); `four-layer-verifier-test.sh` passed 78 positive/negative checks including malformed four-segment selector rejection; Bash syntax, Python compile and diff whitespace checks passed. The packaged app selector has not run since these edits.
- The journey also queried macOS `StaticText.label` for private receipts/verified SHA despite the suite's established `AXValue` contract (`UITestHarness.readableText`). Those assertions would fail after a successful upload. They now inspect `value`/`readableText` and compare the exact original digest, with direct click for subsequent offscreen controls.
- The 2026-10-12 escalated rerun reached the packaged test at 21:41:24 and the preparation checkbox click at 21:41:44. XCTest scrolled `playstead.settings.content` before clicking. The added `selection.value as? String == "1"` assertion failed because that cast returned nil; the test continued toward Estimate, but interruption prevents a valid outcome. Parent withdrew the earlier Ready after the first setup failure, so this run must remain failed/unknown and no further foreground run is authorized until a fresh window.
- After interruption, the run-owned native root and decoder container/network were absent. Narrow escalated process inventory found no task Playstead executable, UITest runner or xcodebuild; an unrelated preexisting `mix phx.server` PID 19558 was left untouched.
- The journey now tests the actual preparation action outcome (`1 games` in the server-backed estimate review) instead of assuming macOS checkbox `value` is a String. The targeted runner now supports LiveServer `--build-only` without starting native services or an app, and `--test-without-building` for a later Ready window. The mocked build-only regression, Bash syntax and diff checks passed.
- The exact `--build-only` run first failed in the default sandbox before compile (`xcodebuild` exit 74, `sandbox_apply: Operation not permitted` during SwiftPM resolution). The same build-only command passed under the authorized narrow escalation in 4.0 seconds, ending `** TEST BUILD SUCCEEDED **` at `.build/ci/selected-live-server.Ng4iCF/raw/recovery-build.log`; LiveServer `.xctestrun` refreshed at 21:45. It did not start Phoenix, PostgreSQL, decoder, UITest runner or Playstead. Follow-up exact process inventory found no task app/runner/xcodebuild, and no run-owned decoder/network/native root remained.

## Pending Verification and Hunk Ownership

- Source/test/debug edits remain unstaged and uncommitted for this nonterminal checkpoint. The parent owns phase STATE/ROADMAP/HANDOFF. The eight changed task files are listed in Resolution, plus this debug receipt. `four-layer-verifier-test.sh` contains six task lines at its final hunk (`@@ -284,6 +540,12 @@`); its earlier approximately 260-line unstaged diff predates this task and must stay out of any task commit. If terminal verification later permits a commit, stage only that final selector-guard hunk from the mixed file; preserve all owner changes and use normal hooks.
- Exact pending selector: `PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 scripts/ci/run-mac-verification.sh --layers live-server --test-without-building --only-testing PlaysteadUITests/MetadataPrivateMediaJourneyTests/testPrivateMediaExportAndProviderDisclosureUsePairedProductionRoutes` from `playstead-mac`. Build is prepared; a fresh Ready window is required before packaged launch. Allow approximately 3–6 minutes for native services and the focused journey.
- The parent asked for a fresh owner availability window after the interrupted run; Ready has not yet been relayed. Do not infer permission from the earlier withdrawn Ready or from elapsed time. No services or app remain running while waiting. Once Ready arrives, run one exact selector, signal parent when foreground app interaction finishes, and verify closure via exact process/container/profile inventory without calling the bound app getter. Preserve any failure as failed evidence and diagnose it before another run.
- Debug proof still missing: one complete current-source packaged pass with candidate selection persisted, server-backed one-game preparation review/enqueue, private original upload receipt and digest, cover selection, export digest, and explicit provider consent/search provenance. The previous invalid selector, pre-fix false-hittability run, and interrupted checkbox-value run are failures/unknown, not passing evidence. Separately, the Plan 09 53-state paint harness lacks per-state AX/action predicates and requires a follow-up executor even if this focused debug closes.

## Ownership and Continuation

Continue existing Plan 09 under $gsd-execute-phase 4.7; do not create another numbered task or replan.
Root remains on feat/dev-standup-and-uat7-closure. Baseline: /private/tmp/playstead-04.7-execution-baseline.json.
Preserve unrelated owner edits, use task-only commits with hooks, and keep STATE/ROADMAP/HANDOFF ownership with parent.
Read AGENTS.md, Phase 4.7 CONTEXT/UI-SPEC/VALIDATION/Plan09 and prior summaries before edits. Reuse existing isolated fixtures and no-HID wrapper authority; Apple/HID and unrelated recovery remain parked.

## Resolution

root_cause: "The live journey's pre-click isHittable gate fails on valid offscreen controls before XCTest auto-scrolls; native mac_ci omits the media decoder endpoint; the embedded PNG fixture has a corrupt IDAT CRC."
fix: "Use XCTest click with a persisted-selection postcondition; generate valid authored PNG bytes; start a bounded run-owned decoder via mac_ci-only loopback transport with exact cleanup; reject malformed targeted selectors before any build or app action."
verification:
  target_test: {result: pending, reason: "interrupted escalated run reached an AX-value assertion and was not an accepted test; corrected focused build-for-testing passed, while test-without-building awaits a fresh Ready window"}
  mutation_check: {result: skipped, reason: "Stryker is not configured for Swift, Elixir, Bash or Python in this repository"}
  no_op_deletion: {result: pass, deletion_justified_by_rca: true}
  adjacent_tests: {result: partial, suites_run: ["media_decoder_test.exs: mac_ci loopback protocol 1/1", "four-layer-verifier-test.sh: 78/78", "recovery-build-only-test.sh: recovery/LiveServer build-only guards pass", "focused LiveServer build-for-testing: pass"]}
  revert_and_reconfirm: {result: pending, reason: "shared working tree; saved pre-fix raw XCTest log records original failure, post-fix packaged run pending"}
  guardrail_verdict: pending
files_changed:
  - playstead-mac/PlaysteadUITests/MetadataPrivateMediaJourneyTests.swift
  - playstead-mac/scripts/ci/run-mac-verification.sh
  - playstead-mac/scripts/ci/tests/four-layer-verifier-test.sh
  - playstead-mac/scripts/ci/tests/recovery-build-only-test.sh
  - playstead-server/config/runtime.exs
  - playstead-server/lib/playstead/metadata/media_decoder.ex
  - playstead-server/ops/media-decoder/server.py
  - playstead-server/test/playstead/metadata/media_decoder_test.exs


Current startup diagnosis: selected-live-server.eyDv3B was interrupted after event-loop stalls. `/private/tmp/playstead-04.7-live-stall.sample.txt` shows SQLite transaction → MetadataStore.clearAll → NotificationCenter observer on OperationQueue.main waiting while main rendering awaits SQLite. AppEnvironment observer now uses queue:nil and schedules a MainActor Task. Current focused run selected-unit.9YAorU: 7 tests,0 failures, including testSQLiteTransactionNotificationDoesNotWaitForMainActor; startup still requires packaged current-source proof. Foreground released, exact task app/runner closed.
