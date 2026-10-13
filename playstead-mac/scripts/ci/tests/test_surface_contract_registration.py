"""Exercise the recurring contract gate without launching apps or services."""

from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest


CI_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = CI_ROOT.parents[2]
GUARD = "plan-05-surface-contract-test.sh"


class SurfaceContractRegistrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = (CI_ROOT / "run-mac-verification.sh").read_text()
        match = re.search(
            r"^run_contract_self_tests\(\) \{\n.*?^\}",
            cls.runner,
            re.MULTILINE | re.DOTALL,
        )
        if match is None:
            raise AssertionError("recurring contract gate is missing")
        cls.gate = match.group()

    def run_gate(self, guards):
        with tempfile.TemporaryDirectory(prefix="playstead-surface-contract-") as temporary:
            root = Path(temporary)
            (root / "tests").mkdir()
            for name, (exit_code, executable) in guards.items():
                script = root / "tests" / name
                script.write_text(
                    f"#!/usr/bin/env bash\nprintf '%s\\n' {shlex.quote('visited:' + name)}\nexit {exit_code}\n"
                )
                script.chmod(0o755 if executable else 0o644)
            shell = f"""set -euo pipefail
SCRIPT_DIR={shlex.quote(str(root))}
REPO_ROOT={shlex.quote(str(root))}
die() {{ printf '%s\\n' "$*" >&2; exit 1; }}
run_complete_hosted_self_tests() {{ return 0; }}
verify_required_uat_allowlist() {{ return 0; }}
python3() {{ return 0; }}
{self.gate}
run_contract_self_tests
"""
            return subprocess.run(
                ["bash", "-c", shell], capture_output=True, text=True, timeout=10
            )

    def test_current_guard_and_ci_entry_point_are_registered(self):
        guard = CI_ROOT / "tests" / GUARD
        self.assertTrue(guard.is_file())
        self.assertTrue(guard.stat().st_mode & 0o111, "guard must be executable")
        self.assertIn("--self-test-contracts)", self.runner)
        dispatch = self.runner[self.runner.index("--self-test-contracts)"):].splitlines()[0]
        self.assertIn("run_contract_self_tests", dispatch)
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text()
        ordinary_job = re.search(r"^  mac-verification:\n.*?(?=^  [a-zA-Z0-9_-]+:|\Z)", workflow, re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(ordinary_job)
        job = ordinary_job.group()
        gate = "run: scripts/ci/run-mac-verification.sh --self-test-contracts"
        self.assertIn(gate, job)
        build = re.search(
            r"run: scripts/ci/run-mac-verification\.sh --run-(?:unprivileged|four-layer)-verification\b", job
        )
        self.assertIsNotNone(build, "ordinary native build entry point is missing")
        self.assertLess(job.index(gate), build.start())

    def test_discovery_visits_plan_05_and_new_guards_once(self):
        result = self.run_gate({GUARD: (0, True), "new-contract.sh": (0, True)})
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in (GUARD, "new-contract.sh"):
            self.assertEqual(result.stdout.count("visited:" + name), 1)

    def test_failed_plan_05_guard_fails_gate(self):
        result = self.run_gate({GUARD: (1, True)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("contract failed: " + GUARD, result.stderr)
        self.assertNotIn("all static contract guards passed", result.stdout)

    def test_missing_plan_05_guard_fails_even_with_other_guards(self):
        result = self.run_gate({"other-contract.sh": (0, True)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or not executable", result.stderr)

    def test_empty_guard_directory_fails_gate(self):
        result = self.run_gate({})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or not executable", result.stderr)

    def test_nonexecutable_plan_05_guard_fails_gate(self):
        result = self.run_gate({GUARD: (0, False)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or not executable", result.stderr)

    def test_other_failure_remains_fatal_and_discovery_continues(self):
        result = self.run_gate({"a-failing-contract.sh": (1, True), GUARD: (0, True)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("contract failed: a-failing-contract.sh", result.stderr)
        self.assertIn("visited:" + GUARD, result.stdout)


if __name__ == "__main__":
    unittest.main()
