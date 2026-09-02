#!/usr/bin/env python3
"""Task 3 document mutation for plan 03.5-09.

Promotes Phase 3 UAT checkpoints 2, 3, 5 and 6 to `source: automated`, splits
checkpoint 10 into its automated and still-blocked halves, and restates Phase
3.5 roadmap criterion 4 in the exact topology wording the evidence validator
requires.

Run ONLY after the hosted validator has accepted the run: the plan forbids any
documentation diff before exact evidence passes.

    apply_task3.py --run-id N --sha SHA --run-url URL --uat PATH --roadmap PATH
"""

import argparse
import datetime
import pathlib
import re
import sys

# Mirrors AUTOMATED_MAPPINGS in validate-phase-3-uat-evidence.py. The validator
# is authoritative over 03.5-09-PLAN.md's table, whose coarser names predate the
# split of the storage and curation interaction tests.
MAPPINGS = {
    2: [
        "LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch",
    ],
    3: [
        "LibraryContractSnapshotTests/testCardAndStatusVisualContract",
        "LibraryContractSnapshotTests/testSemanticContractOracles",
        "LibraryContractSnapshotTests/testFiveCurationShelfVisualContract",
    ],
    5: [
        "StorageContractSnapshotTests/testDownloadsQuotaReclaimAndStorageVisualContract",
        "StorageContractSnapshotTests/testStorageMotionAndReducedMotionContract",
        "StorageInteractionTests/testDownloadsPauseResumeFlow",
        "StorageInteractionTests/testQuotaEditAndFocusRestoration",
        "StorageInteractionTests/testReclaimPromptPostMutationPreservesCanonicalRows",
        "StorageInteractionTests/testStorageInventoryPostMutationPreservesCanonicalRows",
        "StorageInteractionTests/testStorageInventoryProtectsPinnedCopy",
        "SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit",
    ],
    6: [
        "LibraryContractSnapshotTests/testFiveCurationShelfVisualContract",
        "CurationInteractionTests/testContinueShelfRendersHonestEmptyFixture",
        "CurationInteractionTests/testFavoritesShelfRendersExactSeededCard",
        "CurationInteractionTests/testCollectionsShelfRendersExactSeededRoute",
        "CurationInteractionTests/testQueueShelfRendersHonestEmptyFixture",
        "CurationInteractionTests/testRecentShelfRendersHonestEmptyFixture",
        "CurationInteractionTests/testDragReorderSurvivesRelaunch",
        "CurationInteractionTests/testKeyboardReorderRetainsFocusAndSurvivesRelaunch",
        "PlaySessionTests/test_launchSucceedsIndependentlyOfPlaySessionRecording",
        "PlaySessionTests/test_offlineSession_isDeliveredAfterReachabilityReturns",
        "PlaySessionTests/test_sameSessionIdentifierPostedTwice_resultsInOneServerSideEffect",
        "PlaySessionTests/test_userDeletion_enqueuesDeleteIntentAndRemovesFromRecent",
    ],
}

BOUNDARIES = {
    2: "Public pairing and /api/v1/snapshot render, fresh mirror, Keychain relaunch, and zero blob routes only; no real game bytes.",
    3: "Locked card geometry, status vocabulary, navigation order, honest empty states, and curation visual/semantic contract only.",
    5: "Visual, motion and reduced-motion, interaction, focus restoration, and machine-checkable live semantics/audits only; experiential VoiceOver remains blocked.",
    6: "Shelf visuals, drag and keyboard reorder durability, launch independence, delivery idempotency, and individual deletion only.",
}

LAYER = {
    2: "the live-server layer",
    3: "the rendering layer",
    5: "the rendering and ui layers",
    6: "the rendering, ui and unit layers",
}

ROADMAP_CRITERION = (
    "Linux `compose-smoke` proves deployment topology; native PostgreSQL 17 plus Phoenix "
    "beside XCUITest proves Mac client/server behavior."
)


def evidence_block(number, run_id, sha, run_url):
    tests = "\n".join(f"  - `{name}`" for name in MAPPINGS[number])
    return f"""result: pass
source: automated
evidence: |
  Closed by hosted six-job verification run {run_id} at {sha}, {LAYER[number]}
  green, with every identifier below discovered, executed, non-skipped and passed.
  {run_url}
  Exact covering tests:
{tests}
  Evidence boundary: {BOUNDARIES[number]}
"""


def checkpoint_ten(run_id, sha, run_url):
    return f"""result: partial

#### Automated keyboard/live-tree record
result: pass
source: automated
evidence: |
  Closed by hosted six-job verification run {run_id} at {sha}, the ui layer green.
  {run_url}
  Exact covering test:
  - `SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit`
  Evidence boundary: Keyboard-only navigation over every D-18 surface and
  machine-checkable live-tree labels, roles, state, hierarchy, focus, and audits only.

#### Blocked physical-controller/experiential record
result: blocked
blocked_by: physical-device-and-experiential-review
reason: "Physical controller d-pad/shoulder behavior needs real controller hardware, and experiential VoiceOver pronunciation, rotor behavior, sentence quality, and comprehension are human judgment. Both remain blocked and unclaimed; the automated record above must not be read as covering them."
"""


def section_bounds(document, number):
    """Span of one `### N.` checkpoint body, from the line after its heading up
    to its `coverage_id:` line (exclusive)."""
    heading = re.search(rf"(?m)^### {number}\. .+$", document)
    if heading is None:
        raise SystemExit(f"checkpoint {number} heading not found")
    body_start = heading.end() + 1
    coverage = re.search(r"(?m)^coverage_id: .+$", document[body_start:])
    if coverage is None:
        raise SystemExit(f"checkpoint {number} coverage_id not found")
    return body_start, body_start + coverage.start()


def replace_body(document, number, body):
    start, end = section_bounds(document, number)
    keep = re.match(r"(?s)(expected: .*?\n)", document[start:end])
    if keep is None:
        raise SystemExit(f"checkpoint {number} has no expected: line")
    return document[:start] + keep.group(1) + body + document[end:]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--uat", required=True)
    parser.add_argument("--roadmap", required=True)
    args = parser.parse_args()

    uat_path = pathlib.Path(args.uat)
    uat = uat_path.read_text(encoding="utf-8")
    for number in (2, 3, 5, 6):
        uat = replace_body(uat, number, evidence_block(number, args.run_id, args.sha, args.run_url))
    uat = replace_body(uat, 10, checkpoint_ten(args.run_id, args.sha, args.run_url))

    today = datetime.date.today().isoformat()
    uat = re.sub(r"(?m)^updated: .+$", f'updated: "{today}T00:00:00Z"', uat, count=1)

    blocked = len(re.findall(r"(?m)^result: blocked\s*$", uat))
    uat = re.sub(
        r"(?m)^\[testing paused.*\]$",
        f"[testing paused — {blocked + 1} items outstanding: {blocked} blocked, "
        "1 deliberate scope decision]",
        uat,
        count=1,
    )
    uat_path.write_text(uat, encoding="utf-8")

    roadmap_path = pathlib.Path(args.roadmap)
    roadmap = roadmap_path.read_text(encoding="utf-8")
    criterion = re.search(r"(?m)^(?P<indent> *)4\. Linux `compose-smoke`.*$", roadmap)
    if criterion is None:
        raise SystemExit("roadmap criterion 4 not found")
    roadmap = (
        roadmap[:criterion.start()]
        + f"{criterion.group('indent')}4. {ROADMAP_CRITERION}"
        + roadmap[criterion.end():]
    )
    roadmap_path.write_text(roadmap, encoding="utf-8")

    print(f"applied: UAT checkpoints 2/3/5/6 promoted, 10 split, roadmap criterion 4 restated")
    print(f"outstanding after mutation: {blocked} blocked + 1 deliberate scope decision")
    return 0


if __name__ == "__main__":
    sys.exit(main())
