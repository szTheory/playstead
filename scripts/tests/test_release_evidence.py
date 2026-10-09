import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "ci" / "release-evidence.py"
sys.dont_write_bytecode = True
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
            name: {"status": "passed", "subject_sha256": digest, "targets_discovered": 1, "high_critical": 0,
                   "license_policy": "passed", "prohibited_licenses": 0}
            for name in ("source", "image")
        },
        "sbom": {"format": "CycloneDX", "status": "passed", "subject_sha256": digest, "components": 1},
        "parser_inventory": {"status": "passed", "subject_sha256": digest, "discovered": 7,
                             "mapped": 7, "tests_discovered": 9, "tests_passed": 9,
                             "parsers": [
                                 {"id": parser, "category": "malformed-input",
                                  "test_file": f"test/playstead/formats/{parser}_test.exs",
                                  "test_identity": "rejects malformed synthetic input", "result": "passed"}
                                 for parser in ("archive", "gba", "gb_gbc", "nes", "md", "snes", "psx_cue")
                             ]},
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


class ReleaseEvidenceNegativeContracts(unittest.TestCase):
    def run_rejected(self, evidence):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "evidence.json"
            output = Path(directory) / "checked.json"
            source.write_text(json.dumps(evidence))
            result = subprocess.run(
                [sys.executable, str(MODULE_PATH), "--input", str(source), "--output", str(output)],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertFalse(output.exists())

    def test_each_incomplete_or_private_evidence_class_is_rejected(self):
        cases = {}

        value = valid_evidence()
        value["scans"].pop("source")
        cases["missing source scan"] = value

        value = valid_evidence()
        value["unexpected"] = True
        cases["malformed closed schema"] = value

        value = valid_evidence()
        value["scans"]["image"]["status"] = "skipped"
        cases["skipped scan"] = value

        value = valid_evidence()
        value["scans"]["source"]["targets_discovered"] = 0
        cases["zero scanner discovery"] = value

        value = valid_evidence()
        value["parser_inventory"]["tests_discovered"] = 0
        value["parser_inventory"]["tests_passed"] = 0
        cases["zero fixture discovery"] = value

        value = valid_evidence()
        value["sbom"]["subject_sha256"] = "c" * 64
        cases["wrong SBOM digest"] = value

        value = valid_evidence()
        value["scans"]["image"]["high_critical"] = 1
        cases["high or critical vulnerability"] = value

        value = valid_evidence()
        value["scans"]["source"]["license_policy"] = "failed"
        value["scans"]["source"]["prohibited_licenses"] = 1
        cases["prohibited license"] = value

        value = valid_evidence()
        value["parser_inventory"]["mapped"] = 6
        cases["missing parser mapping"] = value

        value = valid_evidence()
        value.pop("sbom")
        cases["missing SBOM"] = value

        value = valid_evidence()
        value.pop("attestations")
        cases["missing attestations"] = value

        value = valid_evidence()
        value["attestations"]["provenance"]["status"] = "not-verified"
        cases["unverified provenance"] = value

        value = valid_evidence()
        value["attestations"]["sbom"]["subject_sha256"] = "d" * 64
        cases["mismatched attestation subject"] = value

        value = valid_evidence()
        value["owner_identity"] = "owner@example.invalid"
        cases["owner identity field"] = value

        value = valid_evidence()
        value["sbom"]["source"] = "PRIVATE_EVIDENCE_SENTINEL"
        cases["private data sentinel"] = value

        value = valid_evidence()
        value["sbom"]["format"] = "/Users/private/collection"
        cases["local path"] = value

        value = valid_evidence()
        value["subject"]["rom_bytes"] = "opaque"
        cases["ROM bytes"] = value

        value = valid_evidence()
        value["subject"]["save_bytes"] = "opaque"
        cases["save bytes"] = value

        for name, evidence in cases.items():
            with self.subTest(name=name):
                self.run_rejected(evidence)

    def test_pull_request_evidence_is_diagnostic_only(self):
        checked = release_evidence.validate(valid_evidence("pull-request"))
        self.assertEqual(checked["verdict"], "diagnostic-only")

    def test_verified_attestations_must_name_the_exact_archive_subject(self):
        digest = "a" * 64
        def record(predicate, subject_digest):
            return [{"verificationResult": {"statement": {
                "predicateType": predicate,
                "subject": [{"name": "release.tar", "digest": {"sha256": subject_digest}}],
            }}}]

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "input.json"
            provenance = root / "provenance.json"
            sbom = root / "sbom.json"
            output = root / "output.json"
            evidence.write_text(json.dumps(valid_evidence()))
            provenance.write_text(json.dumps(record("https://slsa.dev/provenance/v1", digest)))
            sbom.write_text(json.dumps(record("https://cyclonedx.org/bom", digest)))
            release_evidence.verify_attestation_reports(str(evidence), str(provenance), str(sbom), str(output))
            self.assertEqual(json.loads(output.read_text())["verdict"], "release-ready")

            sbom.write_text(json.dumps(record("https://cyclonedx.org/bom", "e" * 64)))
            with self.assertRaises(ValueError):
                release_evidence.verify_attestation_reports(str(evidence), str(provenance), str(sbom), str(output))


if __name__ == "__main__":
    unittest.main()
