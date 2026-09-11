---
type: bug
created: 2026-09-09
resolves_phase:
source: 04.5 execute-phase — found while proving criterion 6 (04.5-04)
---

# SaveEndToEndTests always fails: a duplicate revision POST gets 409

`PlaysteadUITests.SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn`
fails every run with `save-e2e-harness=upload-did-not-complete`
(`SaveEndToEndTests.swift:167`).

## Mechanism

Two `POST /api/v1/saves/revisions` requests arrive within the same
millisecond. The first gets `201`, the second `409`. The 409 makes
`SaveUploadLane.uploadAndCommit` throw, so `drainOnce` takes its
`stoppedForRetry` path and returns `sent = 0`. `UITestBootstrap.swift:272`
requires exactly `sent == 1` — one shot, no retry — so the test fails.

Two revisions being in flight at once is itself the thing to explain:
`drainOnce` is a sequential `for` loop with `await` and the test target is
`parallelizable: false`, so neither the lane nor XCUITest should be producing
concurrency. The likely candidate is a previous test's app instance whose
upload lane is still draining against the same shared Phoenix after its class
finished, but that is a hypothesis — it has not been confirmed.

## It is NOT the 04.5 TLS move

Proven by A/B, not assumed:

| Tree | Transport | Ceremony test | SaveEndToEndTests |
|---|---|---|---|
| `bfc9778` (pre-04.5-04) | plaintext http | **failed** (expected — https-only refusal) | **failed** — same line 167, same marker, same concurrent 201/409 pair |
| `HEAD` (04.5-04) | https | **passed** | failed — identical signature |

Same `file:line`, same harness marker, same 409 pattern on both transports.
No TLS errors, handshake failures, or closed connections appear anywhere in
either `phoenix.log`. The https move neither caused nor worsened this.

Baseline logs: `/tmp/playstead-ab-plaintext/native-services/` (plaintext) and
`/tmp/playstead-ceremony-proof/https/native-services/` (https). Both are in
`/tmp` and will not survive a reboot — re-run the A/B if they are gone.

## Why CI is green anyway

`run-mac-verification.sh` names only
`PlaysteadUITests.LiveServerSnapshotTests/testPairedFreshMirror...` as the
live-server layer's required test. `SaveEndToEndTests` runs, fails, and is
ignored — the layer result does not depend on it. So this has been red for as
long as it has been broken without anyone being told. That fail-open shape is
the same class of defect 04.5-05 exists to close for the ceremony test; the
save round-trip needs the same treatment once it actually passes.

## Scope

Out of scope for 04.5. Nothing in 04.5-04's `files_modified` touches
`SaveEndToEndTests.swift`, `UITestBootstrap.swift`, `SaveUploadLane.swift`, or
the server's revision-creation path. This belongs to the Phase 4 save layer and
needs its own plan: find the second writer, then decide whether the fix is
isolation (tear the prior app down before the next class), idempotency (treat a
duplicate revision POST as success), or a retrying drain in the test harness.

It also blocks 04.5-04's must-have that "the rest of the live-server layer
still passes over https … SaveEndToEndTests … green against the same TLS
endpoint" — that criterion cannot be met by 04.5 because the test is not green
on any transport.
