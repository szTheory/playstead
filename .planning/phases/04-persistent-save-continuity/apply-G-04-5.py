#!/usr/bin/env python3
"""G-04-5: widen the LiveServer topology contract to admit Phase 4's two save proofs.

Run from the repo root:    python3 .planning/phases/04-persistent-save-continuity/apply-G-04-5.py

Why this is a script and not a patch: the assistant is sandbox-blocked from editing CI
contract files directly, which is the correct protection -- a model quietly widening a
gate so CI turns green is the failure mode worth preventing. Applying this is your
decision. Read it first; it changes exactly two anchored regions and refuses to guess.
"""
import pathlib
import sys

TARGET = pathlib.Path("playstead-mac/scripts/ci/tests/four-layer-topology-test.sh")

OLD_SET = '''expected_live = {
    "HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner()",
    "LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch()",
}'''

NEW_SET = '''# The LiveServer layer is the scarcest one in the matrix: a single serial
# target against a real running server. Its budget is deliberately small
# and every addition is a considered widening, never an incidental one.
#
# Phase 4 added the two save entries below. They earn their place because
# SAVE-03's continuation claim -- that a save captured on one Mac is
# restored byte-identically and still plays -- cannot be proven by any
# cheaper layer: it needs a real upload, a real journal return, and a real
# restore into a launch directory. Everything else about the save
# subsystem is proven in Unit or Rendering and must stay there.
expected_live = {
    "HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner()",
    "LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch()",
    "SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn()",
    "SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir()",
}'''

OLD_MSG = '    raise SystemExit("LiveServer must select exactly the launch canary and Plan 08 pairing proof")'

NEW_MSG = '''    raise SystemExit(
        "LiveServer must select exactly the launch canary, the Plan 08 pairing proof, "
        "and the two Phase 4 save round-trip/restore proofs"
    )'''


def main() -> int:
    if not TARGET.exists():
        print(f"error: {TARGET} not found -- run this from the repo root", file=sys.stderr)
        return 1

    source = TARGET.read_text(encoding="utf-8")

    if "SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn()" in source:
        print("already applied; nothing to do")
        return 0

    for label, anchor in (("test set", OLD_SET), ("failure message", OLD_MSG)):
        count = source.count(anchor)
        if count != 1:
            print(
                f"error: expected exactly 1 occurrence of the {label} anchor, found {count}.\n"
                "The file has drifted -- edit it by hand rather than letting this guess.",
                file=sys.stderr,
            )
            return 1

    updated = source.replace(OLD_SET, NEW_SET, 1).replace(OLD_MSG, NEW_MSG, 1)
    TARGET.write_text(updated, encoding="utf-8")
    print(f"applied to {TARGET}")
    print("now verify:  bash playstead-mac/scripts/ci/tests/four-layer-topology-test.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
