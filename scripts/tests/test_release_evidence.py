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
            return result

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

    def test_json_booleans_are_rejected_in_every_numeric_evidence_field(self):
        cases = {}
        for field, value in (
            ("schema_version", True),
        ):
            evidence = valid_evidence()
            evidence[field] = value
            cases[f"{field} boolean"] = evidence

        for scan_name in ("source", "image"):
            for field, value in (
                ("targets_discovered", True),
                ("high_critical", True),
                # False compares equal to zero, so exercise the equality-only check.
                ("prohibited_licenses", False),
            ):
                evidence = valid_evidence()
                evidence["scans"][scan_name][field] = value
                cases[f"{scan_name} scan {field} boolean"] = evidence

        evidence = valid_evidence()
        evidence["sbom"]["components"] = True
        cases["SBOM components boolean"] = evidence

        for field in ("discovered", "mapped", "tests_discovered", "tests_passed"):
            evidence = valid_evidence()
            evidence["parser_inventory"][field] = True
            cases[f"parser inventory {field} boolean"] = evidence

        for name, evidence in cases.items():
            with self.subTest(name=name):
                self.run_rejected(evidence)

    def test_cyclonedx_version_must_be_an_integer_not_a_boolean(self):
        document = {"bomFormat": "CycloneDX", "specVersion": "1.6", "version": True,
                    "components": [{"type": "library", "name": "example"}]}
        with self.assertRaisesRegex(ValueError, "document version"):
            release_evidence.validate_cyclonedx(document)

    def test_embedded_local_paths_are_rejected_without_echoing_values(self):
        unsafe_values = {
            "POSIX": "scanner reported input at /Users/alice/private/game.rom",
            "Windows drive": "scanner reported input at C:\\Users\\Alice\\private\\game.rom",
            "UNC": r"scanner reported input at \\fileserver\private\game.rom",
            "parent traversal": "scanner reported input at ../../private/game.rom",
            "embedded Windows parent traversal": r"scanner reported input at ..\game.rom",
        }
        for kind, value in unsafe_values.items():
            ordinary = valid_evidence()
            ordinary["parser_inventory"]["parsers"][0]["test_identity"] = value
            document = {"bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
                        "components": [{"type": "library", "name": "example", "properties": [
                            {"name": "metadata", "value": {"details": [value]}}
                        ]}]}
            with self.subTest(kind=kind, location="ordinary evidence"):
                result = self.run_rejected(ordinary)
                self.assertNotIn(value, result.stderr)
            with self.subTest(kind=kind, location="nested CycloneDX"):
                with self.assertRaisesRegex(ValueError, "private path or sentinel") as error:
                    release_evidence.validate_cyclonedx(document)
                self.assertNotIn(value, str(error.exception))

    def test_safe_urls_and_descriptive_text_remain_accepted(self):
        self.assertEqual(release_evidence.clean({
            "message": "Uploaded to https://example.invalid/releases/v1/evidence.json",
            "description": "Reviewed by release automation",
            "prose": "The review covered versions .. before the current release",
        })["message"], "Uploaded to https://example.invalid/releases/v1/evidence.json")

        document = {"bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
                    "components": [{"type": "library", "name": "example", "version": "1.0",
                                    "description": "See https://example.invalid/docs/releases/v1"}]}
        self.assertEqual(release_evidence.validate_cyclonedx(document), 1)

    def test_cyclonedx_document_shape_and_privacy_are_checked_before_upload(self):
        document = {"bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
                    "components": [{"type": "library", "name": "example", "version": "1.0"}]}
        self.assertEqual(release_evidence.validate_cyclonedx(document), 1)
        for invalid in (
            {**document, "components": []},
            {**document, "bomFormat": "SPDX"},
            {**document, "components": [{"type": "file", "name": "/private/collection/game.rom"}]},
            {**document, "properties": [{"name": "private.localPath", "value": "/Users/owner/file"}]},
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    release_evidence.validate_cyclonedx(invalid)

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

    def test_malformed_attestation_shapes_are_rejected_without_tracebacks(self):
        digest = "a" * 64
        valid_statement = {
            "predicateType": "https://slsa.dev/provenance/v1",
            "subject": [{"name": "release.tar", "digest": {"sha256": digest}}],
        }
        malformed_records = (
            [None],
            [{"verificationResult": []}],
            [{"verificationResult": {"statement": []}}],
            [{"verificationResult": {"statement": {**valid_statement, "subject": [{}]}}}],
            [{"verificationResult": {"statement": {**valid_statement, "subject": [{"digest": []}]}}}],
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "input.json"
            provenance = root / "provenance.json"
            sbom = root / "sbom.json"
            output = root / "output.json"
            evidence.write_text(json.dumps(valid_evidence()))
            sbom.write_text(json.dumps([{
                "verificationResult": {"statement": {
                    "predicateType": "https://cyclonedx.org/bom",
                    "subject": [{"name": "release.tar", "digest": {"sha256": digest}}],
                }}
            }]))

            for malformed in malformed_records:
                with self.subTest(malformed=malformed):
                    provenance.write_text(json.dumps(malformed))
                    result = subprocess.run(
                        [sys.executable, str(MODULE_PATH), "--input", str(evidence), "--provenance",
                         str(provenance), "--sbom", str(sbom), "--output", str(output)],
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 1)
                    self.assertIn("release evidence rejected:", result.stderr)
                    self.assertNotIn("Traceback", result.stderr)
                    self.assertFalse(output.exists())

    def test_malformed_evidence_subject_shapes_are_rejected_without_tracebacks(self):
        for malformed_subject in (None, []):
            with self.subTest(subject=malformed_subject), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                evidence = valid_evidence()
                evidence["subject"] = malformed_subject
                source = root / "input.json"
                output = root / "output.json"
                source.write_text(json.dumps(evidence))
                result = subprocess.run(
                    [sys.executable, str(MODULE_PATH), "--input", str(source),
                     "--provenance", str(root / "provenance.json"), "--sbom", str(root / "sbom.json"),
                     "--output", str(output)],
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid evidence subject before attestation verification", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertFalse(output.exists())


class ParserInventorySchemaContract(unittest.TestCase):
    def test_boolean_schema_version_is_rejected_by_production_inventory_script(self):
        repository_root = Path(__file__).parents[2]
        regression = repository_root / "playstead-server/scripts/tests/parser-fixture-inventory-schema-test.sh"
        result = subprocess.run(
            ["bash", str(regression)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"parser inventory schema regression failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
