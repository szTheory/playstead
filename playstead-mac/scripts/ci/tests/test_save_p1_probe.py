"""Schema guard for the pinned SAVE-P1 probe report (D-02).

Loads `.planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.json`
relative to the repo root and asserts the report contract produced by
`playstead-mac/scripts/probes/save-p1-probe.swift`. A negative case per
required key proves a truncated report cannot pass this validator quietly
(T-04-01-03).
"""

import copy
import json
import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[4]
REPORT_PATH = (
    REPO_ROOT
    / ".planning"
    / "phases"
    / "04-persistent-save-continuity"
    / "04-SAVE-P1-REPORT.json"
)

REQUIRED_TOP_LEVEL_KEYS = (
    "probe_id",
    "run_id",
    "recorded_at",
    "environment",
    "mgba_observed",
    "measurements",
    "conclusions",
)

REQUIRED_ENVIRONMENT_KEYS = (
    "os_version",
    "hardware_model",
    "filesystem_type",
    "page_size",
    "artifact_bytes",
)

REQUIRED_MEASUREMENT_KEYS = (
    "inode_stability",
    "mtime_fidelity",
    "event_delivery",
    "post_death_writeback",
)


class ReportContractError(AssertionError):
    pass


def load_report():
    if not REPORT_PATH.is_file():
        raise ReportContractError(f"pinned report not found at {REPORT_PATH}")
    with REPORT_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def validate_report(report):
    """Raises ReportContractError on any schema violation. Deliberately a
    single function so both the happy-path test and every negative case
    exercise the exact same validation logic — a validator with two code
    paths could pass its own suite while diverging from what it actually
    guards."""

    if not isinstance(report, dict):
        raise ReportContractError("report must be a JSON object")

    for key in REQUIRED_TOP_LEVEL_KEYS:
        if key not in report:
            raise ReportContractError(f"missing top-level key: {key}")

    if report.get("probe_id") != "SAVE-P1":
        raise ReportContractError(f"probe_id must be 'SAVE-P1', got {report.get('probe_id')!r}")

    if not isinstance(report.get("run_id"), str) or not report["run_id"]:
        raise ReportContractError("run_id must be a non-empty string")

    if not isinstance(report.get("recorded_at"), str) or not report["recorded_at"]:
        raise ReportContractError("recorded_at must be a non-empty string")

    if not isinstance(report.get("mgba_observed"), bool):
        raise ReportContractError("mgba_observed must be a boolean")

    environment = report.get("environment")
    if not isinstance(environment, dict):
        raise ReportContractError("environment must be an object")
    for key in REQUIRED_ENVIRONMENT_KEYS:
        if key not in environment:
            raise ReportContractError(f"environment missing required key: {key}")
    if environment.get("artifact_bytes") != 32768:
        raise ReportContractError(
            f"environment.artifact_bytes must be 32768, got {environment.get('artifact_bytes')!r}"
        )

    measurements = report.get("measurements")
    if not isinstance(measurements, dict):
        raise ReportContractError("measurements must be an object")
    if set(measurements.keys()) != set(REQUIRED_MEASUREMENT_KEYS):
        raise ReportContractError(
            f"measurements must have exactly the keys {sorted(REQUIRED_MEASUREMENT_KEYS)}, "
            f"got {sorted(measurements.keys())}"
        )
    for key in REQUIRED_MEASUREMENT_KEYS:
        if key not in measurements:
            raise ReportContractError(f"measurements missing required key: {key}")

    post_death = measurements.get("post_death_writeback")
    if not isinstance(post_death, dict) or "digest_changed_after_process_death" not in post_death:
        raise ReportContractError(
            "measurements.post_death_writeback must contain digest_changed_after_process_death"
        )
    if not isinstance(post_death["digest_changed_after_process_death"], bool):
        raise ReportContractError(
            "measurements.post_death_writeback.digest_changed_after_process_death must be a boolean"
        )

    conclusions = report.get("conclusions")
    if not isinstance(conclusions, list) or not conclusions:
        raise ReportContractError("conclusions must be a non-empty list")
    for entry in conclusions:
        if not isinstance(entry, str) or not entry.strip():
            raise ReportContractError("every conclusions entry must be a non-empty string")


def delete_key(document, dotted_key):
    """Deep-copies `document` and deletes the key named by `dotted_key`
    (e.g. 'environment.artifact_bytes'), returning the mutated copy."""
    mutated = copy.deepcopy(document)
    parts = dotted_key.split(".")
    target = mutated
    for part in parts[:-1]:
        target = target[part]
    del target[parts[-1]]
    return mutated


class SaveP1ProbeReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = load_report()

    def test_report_exists_and_parses(self):
        self.assertTrue(REPORT_PATH.is_file(), f"expected pinned report at {REPORT_PATH}")
        self.assertIsInstance(self.report, dict)

    def test_report_validates_against_schema(self):
        validate_report(self.report)  # must not raise

    def test_probe_id_is_save_p1(self):
        self.assertEqual(self.report["probe_id"], "SAVE-P1")

    def test_environment_declares_apfs_or_records_actual_value(self):
        # We assert the field is present and non-empty; the probe records
        # whatever statfs() actually returns rather than asserting apfs here,
        # since the schema guard must not itself assume a filesystem.
        self.assertTrue(self.report["environment"]["filesystem_type"])

    def test_environment_artifact_bytes_is_32768(self):
        self.assertEqual(self.report["environment"]["artifact_bytes"], 32768)

    def test_measurements_has_exactly_four_keys(self):
        self.assertEqual(set(self.report["measurements"].keys()), set(REQUIRED_MEASUREMENT_KEYS))

    def test_post_death_writeback_has_digest_changed_boolean(self):
        post_death = self.report["measurements"]["post_death_writeback"]
        self.assertIn("digest_changed_after_process_death", post_death)
        self.assertIsInstance(post_death["digest_changed_after_process_death"], bool)

    def test_conclusions_is_nonempty_list_of_nonempty_strings(self):
        conclusions = self.report["conclusions"]
        self.assertIsInstance(conclusions, list)
        self.assertGreater(len(conclusions), 0)
        for entry in conclusions:
            self.assertIsInstance(entry, str)
            self.assertTrue(entry.strip())

    def test_mgba_observed_is_boolean(self):
        self.assertIsInstance(self.report["mgba_observed"], bool)

    # --- Negative cases: one per required key, proving a truncated report
    # cannot pass this same validation function. ---

    def test_rejects_missing_probe_id(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "probe_id"))

    def test_rejects_missing_run_id(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "run_id"))

    def test_rejects_missing_recorded_at(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "recorded_at"))

    def test_rejects_missing_environment(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "environment"))

    def test_rejects_missing_mgba_observed(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "mgba_observed"))

    def test_rejects_missing_measurements(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "measurements"))

    def test_rejects_missing_conclusions(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "conclusions"))

    def test_rejects_missing_environment_os_version(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "environment.os_version"))

    def test_rejects_missing_environment_hardware_model(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "environment.hardware_model"))

    def test_rejects_missing_environment_filesystem_type(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "environment.filesystem_type"))

    def test_rejects_missing_environment_page_size(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "environment.page_size"))

    def test_rejects_missing_environment_artifact_bytes(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "environment.artifact_bytes"))

    def test_rejects_missing_measurement_inode_stability(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "measurements.inode_stability"))

    def test_rejects_missing_measurement_mtime_fidelity(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "measurements.mtime_fidelity"))

    def test_rejects_missing_measurement_event_delivery(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "measurements.event_delivery"))

    def test_rejects_missing_measurement_post_death_writeback(self):
        with self.assertRaises(ReportContractError):
            validate_report(delete_key(self.report, "measurements.post_death_writeback"))

    def test_rejects_missing_post_death_digest_changed_field(self):
        with self.assertRaises(ReportContractError):
            validate_report(
                delete_key(
                    self.report,
                    "measurements.post_death_writeback.digest_changed_after_process_death",
                )
            )

    def test_rejects_wrong_probe_id(self):
        mutated = copy.deepcopy(self.report)
        mutated["probe_id"] = "NOT-SAVE-P1"
        with self.assertRaises(ReportContractError):
            validate_report(mutated)

    def test_rejects_wrong_artifact_bytes(self):
        mutated = copy.deepcopy(self.report)
        mutated["environment"]["artifact_bytes"] = 1024
        with self.assertRaises(ReportContractError):
            validate_report(mutated)

    def test_rejects_extra_measurement_key(self):
        mutated = copy.deepcopy(self.report)
        mutated["measurements"]["unexpected_extra_key"] = {}
        with self.assertRaises(ReportContractError):
            validate_report(mutated)

    def test_rejects_empty_conclusions(self):
        mutated = copy.deepcopy(self.report)
        mutated["conclusions"] = []
        with self.assertRaises(ReportContractError):
            validate_report(mutated)


if __name__ == "__main__":
    unittest.main()
