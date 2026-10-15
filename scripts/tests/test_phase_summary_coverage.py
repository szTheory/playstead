import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "check-phase-summary-coverage.py"
SPEC = importlib.util.spec_from_file_location("phase_summary_coverage", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class CoverageBlockTests(unittest.TestCase):
    def test_valid_automated_coverage_passes(self):
        text = """---
coverage:
  - id: D1
    description: The fixture path is checked.
    verification:
      - kind: integration
        ref: scripts/check.sh
        status: pass
    human_judgment: false
---
"""
        self.assertEqual([], MODULE.validate_summary_text(text, "valid"))

    def test_legacy_summary_without_coverage_remains_supported(self):
        self.assertEqual([], MODULE.validate_summary_text("---\nplan: 1\n---\n", "legacy"))

    def test_empty_coverage_is_valid(self):
        self.assertEqual([], MODULE.validate_summary_text("---\ncoverage: []\n---\n", "empty"))

    def test_unsupported_kind_is_rejected(self):
        text = """---
coverage:
  - id: D1
    description: A criterion.
    verification:
      - kind: browser
        ref: test
        status: pass
    human_judgment: false
---
"""
        self.assertTrue(any("unsupported verification kind 'browser'" in e for e in MODULE.validate_summary_text(text, "bad-kind")))

    def test_non_classifier_status_is_rejected(self):
        text = """---
coverage:
  - id: D1
    description: A criterion.
    verification:
      - kind: other
        ref: test
        status: blocked
    human_judgment: false
---
"""
        self.assertTrue(any("unsupported verification status 'blocked'" in e for e in MODULE.validate_summary_text(text, "bad-status")))

    def test_missing_human_judgment_is_rejected(self):
        text = """---
coverage:
  - id: D1
    description: A criterion.
    verification:
      - kind: unit
        ref: test
        status: pass
---
"""
        self.assertTrue(any("human_judgment" in e for e in MODULE.validate_summary_text(text, "missing-flag")))

    def test_missing_verification_status_is_rejected(self):
        text = """---
coverage:
  - id: D1
    description: A criterion.
    verification:
      - kind: unit
        ref: test
    human_judgment: false
---
"""
        self.assertTrue(any("one kind, ref, and status each" in e for e in MODULE.validate_summary_text(text, "missing-status")))

    def test_human_judgment_requires_rationale(self):
        text = """---
coverage:
  - id: D1
    description: A criterion.
    verification: []
    human_judgment: true
---
"""
        self.assertTrue(any("rationale" in e for e in MODULE.validate_summary_text(text, "missing-rationale")))

    def test_coverage_header_without_entries_is_valid_and_not_auto_passed(self):
        self.assertEqual([], MODULE.validate_summary_text("---\ncoverage:\n---\n", "empty-body"))


if __name__ == "__main__":
    unittest.main()
