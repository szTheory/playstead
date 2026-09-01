import pathlib
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "validate-phase-3-uat-evidence.py"


CHECKPOINT_TESTS = {
    2: ["LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch"],
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


def checkpoint(number, body):
    return f"### {number}. Fixture checkpoint {number}\n{body.strip()}\n"


def automated_checkpoint(number):
    tests = "\n".join(f"  - `{test}`" for test in CHECKPOINT_TESTS[number])
    return checkpoint(
        number,
        f"""
expected: fixture
result: pass
source: automated
evidence: |
  Exact covering tests:
{tests}
  Evidence boundary is limited to the named machine-checkable behavior.
coverage_id: fixture/{number}
""",
    )


def blocked_checkpoint(number, blocked_by):
    return checkpoint(
        number,
        f"""
expected: fixture
result: blocked
blocked_by: {blocked_by}
reason: \"Retained residual blocker.\"
coverage_id: fixture/{number}
""",
    )


def valid_uat():
    sections = {
        2: automated_checkpoint(2),
        3: automated_checkpoint(3),
        4: blocked_checkpoint(4, "deliberate-scope"),
        5: automated_checkpoint(5),
        6: automated_checkpoint(6),
        7: blocked_checkpoint(7, "real-emulator-game-bytes"),
        8: blocked_checkpoint(8, "physical-device"),
        9: blocked_checkpoint(9, "physical-device"),
        10: checkpoint(
            10,
            """
expected: fixture
result: blocked
#### Automated keyboard/live-tree record
result: pass
source: automated
evidence: |
  `SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit`
  Keyboard and machine-checkable live-tree labels, roles, state, hierarchy, focus, and audits only.
#### Blocked physical-controller/experiential record
result: blocked
blocked_by: physical-device-and-experiential-review
reason: "Physical controller d-pad/shoulder behavior and experiential VoiceOver pronunciation, rotor behavior, sentence quality, and comprehension remain blocked and unclaimed."
coverage_id: fixture/10
""",
        ),
        14: blocked_checkpoint(14, "release-build-signing-notarization"),
        15: blocked_checkpoint(15, "release-build-signing-notarization"),
    }
    return """---
status: partial
phase: 03-mac-offline-play-vertical-slice
---

## Tests

""" + "\n".join(sections[number] for number in sorted(sections))


def valid_roadmap():
    return """# Roadmap

## Phase 3.5: Mac Verification Automation

### Success Criteria

1. Fixture criterion.
2. Fixture criterion.
3. Fixture criterion.
4. Linux `compose-smoke` proves deployment topology; native PostgreSQL 17 plus Phoenix beside XCUITest proves Mac client/server behavior.
"""


class ValidatorTests(unittest.TestCase):
    def run_validator(self, uat=None, roadmap=None):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            uat_path = root / "03-UAT.md"
            roadmap_path = root / "ROADMAP.md"
            uat_path.write_text(valid_uat() if uat is None else uat, encoding="utf-8")
            roadmap_path.write_text(valid_roadmap() if roadmap is None else roadmap, encoding="utf-8")
            return subprocess.run(
                ["python3", str(SCRIPT), "--uat", str(uat_path), "--roadmap", str(roadmap_path)],
                text=True,
                capture_output=True,
                check=False,
            )

    def assert_rejected(self, *, uat=None, roadmap=None):
        result = self.run_validator(uat=uat, roadmap=roadmap)
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_accepts_exact_section_scoped_partial_handoff(self):
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_wrong_checkpoint_placement_for_each_automated_mapping(self):
        for number, tests in CHECKPOINT_TESTS.items():
            with self.subTest(checkpoint=number):
                source = valid_uat()
                token = f"`{tests[0]}`"
                source = source.replace(token, "`misplaced-placeholder`")
                source = source.replace(
                    f"### {14}. Fixture checkpoint {14}",
                    f"### {14}. Fixture checkpoint {14}\n{token}",
                )
                self.assert_rejected(uat=source)

    def test_rejects_missing_checkpoint_2_live_server_proof(self):
        self.assert_rejected(uat=valid_uat().replace(CHECKPOINT_TESTS[2][0], "missing-live-proof"))

    def test_rejects_missing_checkpoint_3_card_or_semantic_proof(self):
        for test in CHECKPOINT_TESTS[3]:
            with self.subTest(test=test):
                self.assert_rejected(uat=valid_uat().replace(test, "missing-library-proof", 1))

    def test_rejects_missing_checkpoint_5_or_6_mapping(self):
        for number in (5, 6):
            for test in CHECKPOINT_TESTS[number]:
                with self.subTest(checkpoint=number, test=test):
                    self.assert_rejected(uat=valid_uat().replace(test, "missing-mapping", 1))

    def test_rejects_incomplete_checkpoint_10_split(self):
        for token in (
            "#### Automated keyboard/live-tree record",
            "SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit",
            "#### Blocked physical-controller/experiential record",
            "Physical controller d-pad/shoulder behavior",
            "experiential VoiceOver pronunciation, rotor behavior, sentence quality, and comprehension",
        ):
            with self.subTest(token=token):
                self.assert_rejected(uat=valid_uat().replace(token, "removed-boundary", 1))

    def test_rejects_overbroad_or_misplaced_automated_source(self):
        self.assert_rejected(uat=valid_uat().replace("source: automated\n", "source: human\n", 1))
        self.assert_rejected(uat=valid_uat().replace("blocked_by: deliberate-scope", "source: automated\nblocked_by: deliberate-scope"))
        self.assert_rejected(uat=valid_uat().replace("blocked_by: physical-device-and-experiential-review", "source: automated\nblocked_by: physical-device-and-experiential-review"))

    def test_rejects_absent_residual_blocker(self):
        for number in (4, 7, 8, 9, 14, 15):
            with self.subTest(checkpoint=number):
                source = valid_uat().replace(f"result: blocked\nblocked_by:", "result: pass\nblocked_by:", 1 if number == 4 else 0)
                if number != 4:
                    start = source.index(f"### {number}.")
                    end = source.find("\n### ", start + 1)
                    end = len(source) if end < 0 else end
                    section = source[start:end].replace("result: blocked", "result: pass", 1)
                    source = source[:start] + section + source[end:]
                self.assert_rejected(uat=source)

    def test_rejects_non_partial_frontmatter(self):
        self.assert_rejected(uat=valid_uat().replace("status: partial", "status: complete", 1))

    def test_rejects_roadmap_topology_claim_outside_phase_3_5_or_wrong_mechanism(self):
        claim = "Linux `compose-smoke` proves deployment topology; native PostgreSQL 17 plus Phoenix beside XCUITest proves Mac client/server behavior."
        self.assert_rejected(roadmap=valid_roadmap().replace(claim, "Compose and Mac tests pass."))
        self.assert_rejected(roadmap=valid_roadmap().replace(claim, "Fixture criterion.") + "\n## Phase 4\n" + claim)


if __name__ == "__main__":
    unittest.main()
