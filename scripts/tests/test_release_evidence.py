import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "ci" / "release-evidence.py"
SPEC = importlib.util.spec_from_file_location("release_evidence", MODULE_PATH)
release_evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_evidence)


def valid_evidence(mode="release"):
    digest = "a" * 64
    return {
        "schema_version": 1,
        "mode": mode,
        "subject": {"archive_sha256": digest, "image_id": "sha256:" + "b" * 64},
        "scans": {
            name: {"status": "passed", "subject_sha256": digest, "high_critical": 0,
                   "license_policy": "passed", "prohibited_licenses": 0}
            for name in ("source", "image")
        },
        "sbom": {"format": "CycloneDX", "status": "passed", "subject_sha256": digest, "components": 1},
        "parser_inventory": {"status": "passed", "subject_sha256": digest, "discovered": 7,
                             "mapped": 7, "tests_discovered": 9, "tests_passed": 9},
        "attestations": {
            name: {"status": "verified", "subject_sha256": digest}
            for name in ("provenance", "sbom")
        } if mode == "release" else {
            name: {"status": "not-issued", "subject_sha256": None}
            for name in ("provenance", "sbom")
        },
        "handoff": {"consumer": "Phase 05 D-11", "subject_sha256": digest, "retained_gates": ["D-07", "D-13"]},
    }


class ReleaseEvidenceHappyPath(unittest.TestCase):
    def test_consistent_release_evidence_is_bound_to_one_archive_digest(self):
        checked = release_evidence.validate(valid_evidence())
        self.assertEqual(checked["verdict"], "release-ready")
        self.assertEqual(checked["subject"]["archive_sha256"], checked["sbom"]["subject_sha256"])
        self.assertEqual(checked["subject"]["archive_sha256"], checked["attestations"]["provenance"]["subject_sha256"])


if __name__ == "__main__":
    unittest.main()
