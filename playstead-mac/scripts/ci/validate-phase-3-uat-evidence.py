#!/usr/bin/env python3
"""Fail-closed Phase 3 UAT/roadmap evidence boundary validator."""

import argparse
import pathlib
import re
import sys


AUTOMATED_MAPPINGS = {
    2: (
        "LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch",
    ),
    3: (
        "LibraryContractSnapshotTests/testCardAndStatusVisualContract",
        "LibraryContractSnapshotTests/testSemanticContractOracles",
        "LibraryContractSnapshotTests/testFiveCurationShelfVisualContract",
    ),
    5: (
        "StorageContractSnapshotTests/testDownloadsQuotaReclaimAndStorageVisualContract",
        "StorageContractSnapshotTests/testStorageMotionAndReducedMotionContract",
        "StorageInteractionTests/testDownloadsPauseResumeFlow",
        "StorageInteractionTests/testQuotaEditAndFocusRestoration",
        "StorageInteractionTests/testReclaimPromptPostMutationPreservesCanonicalRows",
        "StorageInteractionTests/testStorageInventoryPostMutationPreservesCanonicalRows",
        "StorageInteractionTests/testStorageInventoryProtectsPinnedCopy",
        "SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit",
    ),
    6: (
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
    ),
}
BLOCKED_CHECKPOINTS = (4, 7, 8, 9, 14, 15)
ROADMAP_CRITERION = (
    "Linux `compose-smoke` proves deployment topology; native PostgreSQL 17 plus Phoenix "
    "beside XCUITest proves Mac client/server behavior."
)


class ContractError(ValueError):
    pass


def read_text(path):
    try:
        return pathlib.Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ContractError(f"cannot read {path}: {exc}") from exc


def frontmatter(document):
    match = re.match(r"\A---\n(?P<body>.*?)\n---(?:\n|\Z)", document, re.DOTALL)
    if match is None:
        raise ContractError("UAT frontmatter is missing or malformed")
    values = {}
    for line in match.group("body").splitlines():
        if ":" in line and not line.startswith((" ", "\t")):
            key, value = line.split(":", 1)
            values[key.strip()] = value.strip().strip('"')
    return values


def numbered_sections(document):
    matches = list(re.finditer(r"(?m)^### (?P<number>[1-9][0-9]*)\. .+$", document))
    sections = {}
    for index, match in enumerate(matches):
        number = int(match.group("number"))
        if number in sections:
            raise ContractError(f"duplicate checkpoint section: {number}")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(document)
        sections[number] = document[match.start():end]
    return sections


def require(condition, message):
    if not condition:
        raise ContractError(message)


def validate_automated_checkpoint(number, section):
    require(re.search(r"(?m)^result: pass\s*$", section) is not None, f"checkpoint {number} must pass")
    require(section.count("source: automated") == 1, f"checkpoint {number} needs exactly one automated source")
    require(re.search(r"(?m)^evidence: \|\s*$", section) is not None, f"checkpoint {number} evidence block missing")
    for identifier in AUTOMATED_MAPPINGS[number]:
        require(f"`{identifier}`" in section, f"checkpoint {number} mapping missing: {identifier}")
    require("Evidence boundary" in section, f"checkpoint {number} evidence boundary missing")


def validate_checkpoint_10(section):
    automated_marker = "#### Automated keyboard/live-tree record"
    blocked_marker = "#### Blocked physical-controller/experiential record"
    automated_start = section.find(automated_marker)
    blocked_start = section.find(blocked_marker)
    require(0 <= automated_start < blocked_start, "checkpoint 10 automated/blocked split is missing or out of order")
    automated = section[automated_start:blocked_start]
    blocked = section[blocked_start:]
    require(re.search(r"(?m)^result: pass\s*$", automated) is not None, "checkpoint 10 automated split must pass")
    require(automated.count("source: automated") == 1, "checkpoint 10 automated split needs one source")
    require(
        "`SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit`" in automated,
        "checkpoint 10 all-surface test mapping missing",
    )
    for token in ("Keyboard", "live-tree labels, roles, state, hierarchy, focus, and audits only"):
        require(token in automated, f"checkpoint 10 automated boundary missing: {token}")
    require(re.search(r"(?m)^result: blocked\s*$", blocked) is not None, "checkpoint 10 residual must remain blocked")
    require(re.search(r"(?m)^blocked_by: .+$", blocked) is not None, "checkpoint 10 residual blocker missing")
    require("source: automated" not in blocked, "checkpoint 10 automated source bleeds into residual record")
    for token in (
        "Physical controller d-pad/shoulder behavior",
        "experiential VoiceOver pronunciation, rotor behavior, sentence quality, and comprehension",
        "blocked",
        "unclaimed",
    ):
        require(token in blocked, f"checkpoint 10 residual boundary missing: {token}")


def validate_uat(document):
    require(frontmatter(document).get("status") == "partial", "Phase 3 UAT status must remain partial")
    sections = numbered_sections(document)
    for number in (*AUTOMATED_MAPPINGS, *BLOCKED_CHECKPOINTS, 10):
        require(number in sections, f"checkpoint section missing: {number}")
    for number in AUTOMATED_MAPPINGS:
        validate_automated_checkpoint(number, sections[number])
    for number in BLOCKED_CHECKPOINTS:
        section = sections[number]
        require(re.search(r"(?m)^result: blocked\s*$", section) is not None, f"checkpoint {number} must remain blocked")
        require(re.search(r"(?m)^blocked_by: .+$", section) is not None, f"checkpoint {number} blocked_by missing")
        require("source: automated" not in section, f"checkpoint {number} must not claim automated source")
    validate_checkpoint_10(sections[10])


def markdown_level_two_sections(document):
    matches = list(re.finditer(r"(?m)^## (?P<title>.+)$", document))
    return [
        (match.group("title"), document[match.start():(matches[index + 1].start() if index + 1 < len(matches) else len(document))])
        for index, match in enumerate(matches)
    ]


def validate_roadmap(document):
    phase_sections = [body for title, body in markdown_level_two_sections(document) if re.match(r"Phase 3\.5(?:\b|:)", title)]
    require(len(phase_sections) == 1, "Roadmap must contain exactly one Phase 3.5 section")
    phase = phase_sections[0]
    success_match = re.search(r"(?ms)^### Success Criteria\s*$\n(?P<body>.*?)(?=^### |\Z)", phase)
    require(success_match is not None, "Phase 3.5 success criteria section missing")
    criteria = success_match.group("body")
    criterion_four = re.search(r"(?ms)^4\. (?P<body>.*?)(?=^[1-9][0-9]*\. |\Z)", criteria)
    require(criterion_four is not None, "Phase 3.5 success criterion 4 missing")
    normalized = " ".join(criterion_four.group("body").split())
    require(normalized == ROADMAP_CRITERION, "Phase 3.5 success criterion 4 topology wording drifted")
    require(document.count(ROADMAP_CRITERION) == 1, "Roadmap topology claim must occur exactly once")


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--uat", required=True)
    parser.add_argument("--roadmap", required=True)
    args = parser.parse_args(argv)
    try:
        validate_uat(read_text(args.uat))
        validate_roadmap(read_text(args.roadmap))
    except ContractError as exc:
        print(f"phase-3 evidence validation failed: {exc}", file=sys.stderr)
        return 1
    print("phase-3 UAT and Roadmap evidence boundaries verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
