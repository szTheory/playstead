# Deferred Items — Phase 04.5

## four-layer-topology-test.sh: stale `expected_live` set (pre-existing, out of scope for 04.5-04)

`playstead-mac/scripts/ci/tests/four-layer-topology-test.sh` asserts (around
line 109-121) that `TestPlans/LiveServer.xctestplan`'s `selectedTests` equals
a 4-item set: the launch canary, the pairing proof, and the two Phase 4 save
round-trip/restore proofs. The actual `LiveServer.xctestplan` on disk already
contains a 5th entry —
`PairingCeremonyTests/testAHumanCanPairAFreshMacEntirelyFromInsideTheAppAgainstTheRealServer()`
— which does not match the test's hardcoded `expected_live` set, so the test
fails with:

```
LiveServer must select exactly the launch canary, the Plan 08 pairing proof, and the two Phase 4 save round-trip/restore proofs
```

This mismatch predates plan 04.5-04's dispatch: `live-server.sh` (the file
04.5-04 Task 2 modifies) was not touched by this discrepancy, and the
`.xctestplan`'s 5th entry was already present before this dispatch began
(confirmed by `git show HEAD:...live-server.sh` before any edit in this
session, and by the fact that no file in 04.5-04's `files_modified` list
touches `TestPlans/LiveServer.xctestplan` or
`four-layer-topology-test.sh` itself).

Because the SystemExit inside the python heredoc aborts the script under
`set -e` before it reaches the later
`grep -c 'PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture' -eq 3`
assertion, that count assertion (also stale — the file already has 5
occurrences of the pinned string, not 3, independent of any 04.5-04 edit)
is currently unreachable and unverified either way.

**Not fixed here** per the scope boundary (04.5-04 only auto-fixes issues
directly caused by its own task's changes). Needs a follow-up plan to:
1. Update `four-layer-topology-test.sh`'s `expected_live` set to include the
   `PairingCeremonyTests` entry.
2. Re-verify (or correct) the `mac_ci_fixture` occurrence-count assertion
   against the file's actual current count (5, not 3) once the fixture
   surface it enumerates (`prepare`/`pair-provision`/`pair-approve`/`second`)
   is confirmed final.
