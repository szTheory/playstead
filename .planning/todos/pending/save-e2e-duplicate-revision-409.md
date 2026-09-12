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

---

## Update 2026-09-12 — the premise above is now stale, the mechanism is not

`SaveEndToEndTests` no longer "fails every run". It is green in three
consecutive hosted runs — 34676636969 (6.36s), 34707257044 (6.20s) and
34714449202 on main — and it is now a `--required-test`, so the fail-open
described in "Why CI is green anyway" is closed: the layer result does depend
on it.

What changed in between, and what it does and does not explain:

1. **The second writer was found.** This note's hypothesis — "a previous
   test's app instance whose upload lane is still draining against the same
   shared Phoenix" — was close. The actual second writer was in-process: the
   harness constructed its OWN `SaveUploadLane` over the same store while the
   app drained its own lane on the reachability transition at pairing.
   `drainOnce`'s doc promises actors serialize overlapping calls, and they do
   — but two actor INSTANCES serialize nothing. Fixed by sharing the app's
   lane (351fe70). That directly removes the two-concurrent-POST condition
   this note describes, which is the best available explanation for the 409s.

2. **The one-shot `sent == 1` requirement was removed** (this note predicted
   it exactly). The harness now retries the retryable classifications and
   asserts the OUTCOME — the revision reaching `.uploaded` — rather than one
   lane object's counter.

3. **UNRESOLVED, and recorded here rather than assumed away.** Run
   34670123715 failed at `save-e2e-harness=upload-server-refused`. That was
   fixed by treating `.offlineQueue`/`.slowUpload` as retryable (09612a9),
   on the stated inference that an unreachable server at pairing time was the
   classification involved. THIS NOTE DOCUMENTS AN ALTERNATIVE THAT FIX WOULD
   NOT COVER: a duplicate-revision 409 classifies as
   `.compatibilityRejection`, one of D-40's unfixable reasons, for which
   `isRetryable` is false and the harness still reports "server refused". So
   the green runs may not be attributable to that change. The change remains
   correct on its own terms — `SaveUploadFailureClassification`'s own doc says
   `.offlineQueue` and `.slowUpload` are the product working correctly and
   must never escalate — but which classification actually fired in
   34670123715 was never captured, and the harness's fixed-literal reason
   channel deliberately cannot carry it.

**To close this todo properly:** make the harness record WHICH classification
it refused on, in a form that survives CI's evidence pipeline (file:line is
kept, assertion messages are discarded — so it needs its own assertion site
per classification, the way `recordSaveHarnessFailure` already splits its
seven reasons). Until then, three green runs are three green runs, not a
proof that the 409 path is gone.

Related: WINDOWS #67 (closed — the lane race), #71 (open — an unproven
live-server failure in the same layer).
