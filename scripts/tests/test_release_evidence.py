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
            name: {"status": "passed", "subject_sha256": digest, "targets_discovered": 1,
                   "high_critical": 0, "fixable_high_critical": 0, "unfixed_high_critical": 0,
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


class TrivyDiagnosticContracts(unittest.TestCase):
    def test_high_severity_failure_summary_is_actionable_bounded_and_redacted(self):
        private_path = "/Users/alice/private/game.rom"
        report = {"Results": [{
            "Type": "debian",
            "Vulnerabilities": [
                {"PkgName": "openssl", "InstalledVersion": "3.0.17-1",
                 "FixedVersion": "3.0.18",
                 "VulnerabilityID": "CVE-2026-12345", "Severity": "HIGH",
                 "Description": f"host scan path: {private_path}"},
                {"PkgName": private_path, "InstalledVersion": "../../home/runner",
                 "FixedVersion": "/Users/alice/fixed-version-private",
                 "VulnerabilityID": "PRIVATE_EVIDENCE_SENTINEL", "Severity": "CRITICAL",
                 "Description": private_path},
                {"PkgName": "libsafe", "InstalledVersion": "1.2.3",
                 "VulnerabilityID": "CVE-2026-99999", "Severity": "LOW"},
            ],
            "Licenses": [{"PkgName": "libcodec", "PkgVersion": "4.5.6",
                          "Name": "GPL-3.0", "Severity": "HIGH",
                          "FilePath": private_path}],
        }]}

        summary = release_evidence.safe_trivy_diagnostics(report)
        self.assertEqual(summary["total"], 3)
        self.assertEqual(summary["fixable_vulnerabilities"], 2)
        self.assertEqual(summary["unfixed_vulnerabilities"], 0)
        self.assertEqual(summary["high_severity_licenses"], 1)
        self.assertEqual(summary["findings"], [
            {"category": "vulnerability", "package": "openssl", "version": "3.0.17-1",
             "finding": "CVE-2026-12345", "severity": "HIGH", "fix_available": True},
            {"category": "vulnerability", "package": "<redacted>", "version": "<redacted>",
             "finding": "<redacted>", "severity": "CRITICAL", "fix_available": True},
            {"category": "license", "package": "libcodec", "version": "4.5.6",
             "finding": "GPL-3.0", "severity": "HIGH", "fix_available": False},
        ])
        rendered = json.dumps(summary)
        self.assertNotIn(private_path, rendered)
        self.assertNotIn("../../home/runner", rendered)
        self.assertNotIn("/Users/alice/fixed-version-private", rendered)
        self.assertNotIn("PRIVATE_EVIDENCE_SENTINEL", rendered)
        self.assertNotIn("Description", rendered)
        self.assertNotIn("FilePath", rendered)

    def test_failure_summary_caps_finding_examples(self):
        report = {"Results": [{"Vulnerabilities": [
            {"PkgName": f"package-{index}", "InstalledVersion": "1.0.0",
             "VulnerabilityID": f"CVE-2026-{index:05d}", "Severity": "HIGH",
             "FixedVersion": "1.0.1"}
            for index in range(30)
        ]}]}
        summary = release_evidence.safe_trivy_diagnostics(report)
        self.assertEqual(summary["total"], 30)
        self.assertEqual(summary["fixable_vulnerabilities"], 30)
        self.assertEqual(len(summary["findings"]), 25)


class TrivyFixabilityPolicyContracts(unittest.TestCase):
    def test_only_high_findings_with_a_published_fix_block_the_scan(self):
        report = {"Results": [{"Vulnerabilities": [
            {"PkgName": "patched-lib", "InstalledVersion": "1.0.0",
             "FixedVersion": "1.0.1", "VulnerabilityID": "CVE-2026-11111", "Severity": "HIGH"},
            {"PkgName": "unfixed-lib", "InstalledVersion": "2.0.0",
             "FixedVersion": "", "VulnerabilityID": "CVE-2026-22222", "Severity": "CRITICAL"},
            {"PkgName": "low-lib", "InstalledVersion": "3.0.0",
             "FixedVersion": "3.0.1", "VulnerabilityID": "CVE-2026-33333", "Severity": "LOW"},
        ]}]}

        summary = release_evidence.summarize_trivy(report, "a" * 64)
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["high_critical"], 2)
        self.assertEqual(summary["fixable_high_critical"], 1)
        self.assertEqual(summary["unfixed_high_critical"], 1)

        report["Results"][0]["Vulnerabilities"].pop(0)
        summary = release_evidence.summarize_trivy(report, "a" * 64)
        self.assertEqual(summary["status"], "passed")
        self.assertEqual(summary["high_critical"], 1)
        self.assertEqual(summary["fixable_high_critical"], 0)
        self.assertEqual(summary["unfixed_high_critical"], 1)

    def test_restricted_application_license_remains_a_release_blocker(self):
        report = {"Results": [{"Licenses": [{
            "PkgName": "app-dependency", "PkgVersion": "1.0.0",
            "Name": "GPL-3.0", "Severity": "HIGH",
        }]}]}

        summary = release_evidence.summarize_trivy(report, "a" * 64)

        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["license_policy"], "failed")
        self.assertEqual(summary["prohibited_licenses"], 1)


class ReleaseScannerScopeContracts(unittest.TestCase):
    def test_container_vulnerability_and_application_license_scans_are_scoped(self):
        script = (Path(__file__).parents[1] / "ci" / "release-supply-chain.sh").read_text()
        image_scan = script.split('"$TRIVY_IMAGE" image \\\n', 1)[1].split('"$IMAGE_REF"', 1)[0]
        source_scan = script.split('"$TRIVY_IMAGE" fs \\\n', 1)[1].split("/work/playstead-server", 1)[0]

        self.assertIn("--scanners vuln --format json", image_scan)
        self.assertNotIn("--scanners vuln,license", image_scan)
        self.assertIn("--scanners vuln,license", source_scan)

    def test_evidence_preserves_unfixed_counts_and_rejects_fixable_findings(self):
        evidence = valid_evidence()
        image_scan = evidence["scans"]["image"]
        image_scan.update(high_critical=1, unfixed_high_critical=1)
        self.assertEqual(release_evidence.validate(evidence)["verdict"], "release-ready")

        image_scan.update(high_critical=1, fixable_high_critical=1, unfixed_high_critical=0)
        with self.assertRaisesRegex(ValueError, "published fix"):
            release_evidence.validate(evidence)


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
                ("fixable_high_critical", True),
                ("unfixed_high_critical", True),
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
                self.assertIn("$.components[0].properties[0].value", str(error.exception))

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

    def test_vendor_vulnerability_description_may_contain_path_examples(self):
        document = {
            "bomFormat": "CycloneDX",
            "specVersion": "1.6",
            "version": 1,
            "components": [{"type": "library", "name": "example"}],
            "vulnerabilities": [{
                "id": "CVE-2026-12345",
                "description": (
                    "A path traversal issue may let an attacker use ../ to read "
                    "a system file such as /etc/example.conf."
                ),
            }],
        }
        self.assertEqual(release_evidence.validate_cyclonedx(document), 1)

        for private_path in (
            "/home/runner/work/playstead/private-test.rom",
            r"C:\Users\runner\work\private-test.rom",
            r"\\private-host\share\private-test.rom",
        ):
            unsafe = json.loads(json.dumps(document))
            unsafe["vulnerabilities"][0]["description"] += f" Scanned local input: {private_path}"
            with self.subTest(private_path_kind="host path"):
                with self.assertRaisesRegex(ValueError, "private path or sentinel") as error:
                    release_evidence.validate_cyclonedx(unsafe)
                self.assertIn("$.vulnerabilities[0].description", str(error.exception))
                self.assertNotIn(private_path, str(error.exception))

        # A marker for project-local/private input is still rejected even in
        # vendor prose, and the diagnostic must not echo it.
        document["vulnerabilities"][0]["description"] += " PRIVATE_EVIDENCE_SENTINEL"
        with self.assertRaisesRegex(ValueError, "private path or sentinel") as error:
            release_evidence.validate_cyclonedx(document)
        self.assertIn("$.vulnerabilities[0].description", str(error.exception))
        self.assertNotIn("PRIVATE_EVIDENCE_SENTINEL", str(error.exception))

    def test_rejection_locations_are_redacted_and_structural(self):
        document = {
            "bomFormat": "CycloneDX",
            "specVersion": "1.6",
            "version": 1,
            "metadata": {"custom private key /Users/alice/secret": "PRIVATE_EVIDENCE_SENTINEL"},
            "components": [{"type": "library", "name": "example"}],
        }
        with self.assertRaisesRegex(ValueError, "forbidden evidence field") as error:
            release_evidence.validate_cyclonedx(document)
        message = str(error.exception)
        self.assertIn("$.metadata.<field>", message)
        self.assertNotIn("custom private key", message)
        self.assertNotIn("/Users/alice/secret", message)
        self.assertNotIn("PRIVATE_EVIDENCE_SENTINEL", message)

        forbidden = {
            "bomFormat": "CycloneDX",
            "specVersion": "1.6",
            "version": 1,
            "components": [{"type": "library", "name": "example", "properties": [
                {"name": "private.ownerCredential", "value": "PRIVATE_EVIDENCE_SENTINEL"},
            ]}],
        }
        with self.assertRaisesRegex(ValueError, "forbidden CycloneDX property") as error:
            release_evidence.validate_cyclonedx(forbidden)
        self.assertNotIn("private.ownerCredential", str(error.exception))
        self.assertNotIn("PRIVATE_EVIDENCE_SENTINEL", str(error.exception))
        self.assertIn("$.components[0].properties[0].name", str(error.exception))

    def test_trivy_1_7_generated_sbom_metadata_is_accepted(self):
        # Trivy 0.75 emits CycloneDX 1.7 for the tested container image.
        reference = "docker.io/library/playstead-app:ci"
        document = {
            "$schema": "http://cyclonedx.org/schema/bom-1.7.schema.json",
            "bomFormat": "CycloneDX",
            "specVersion": "1.7",
            "version": 1,
            "metadata": {
                "component": {"type": "container", "name": "playstead-app"},
                "properties": [
                    {"name": "aquasecurity:trivy:Reference", "value": reference},
                ],
            },
            "components": [{"type": "library", "name": "example", "version": "1.0"}],
        }
        self.assertEqual(release_evidence.validate_cyclonedx(document), 1)

        for private_value in (
            "/Users/alice/private/collection",
            "PRIVATE_EVIDENCE_SENTINEL",
        ):
            unsafe = json.loads(json.dumps(document))
            unsafe["metadata"]["properties"][0]["value"] = private_value
            with self.subTest(private_value="sentinel" if "SENTINEL" in private_value else "path"):
                with self.assertRaises(ValueError) as error:
                    release_evidence.validate_cyclonedx(unsafe)
                self.assertNotIn(private_value, str(error.exception))

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
