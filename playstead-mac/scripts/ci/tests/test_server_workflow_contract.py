"""App-free regression contract for the hosted browser gate."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[4]
WORKFLOW = ROOT / ".github/workflows/ci.yml"


def validate(source):
    test_job = source.split("  test:\n", 1)[1].split("\n  mac-verification:", 1)[0]
    prerequisite = test_job.find("- name: Verify browser prerequisites and discovery")
    chrome_setup = test_job.find("- id: chrome")
    precommit = test_job.find("run: mix precommit")
    if chrome_setup < 0 or prerequisite < 0 or precommit < 0 or not (chrome_setup < prerequisite < precommit):
        raise AssertionError("browser guard must run before mix precommit")
    if "install-chromedriver: true" not in test_job[chrome_setup:prerequisite]:
        raise AssertionError("browser setup must install ChromeDriver before validating it")
    guard = test_job[prerequisite:precommit]
    for required in (
        'test -x "$WALLABY_CHROME_BINARY"',
        'test -x "$CHROMEDRIVER_PATH"',
        '"$CHROMEDRIVER_PATH" --version',
        '>> "$GITHUB_PATH"',
        "python3 ../playstead-mac/scripts/ci/discover-browser-tests.py test/playstead_web/browser",
    ):
        if required not in guard:
            raise AssertionError(f"browser prerequisite/discovery guard missing: {required}")
    dump_setup = test_job.find("- name: Match PostgreSQL dump client to the test service")
    if dump_setup < 0 or dump_setup >= precommit:
        raise AssertionError("matching dump client must be selected before mix precommit")
    for required in ("postgres:17.2", "postgresql-client-17", "https://www.postgresql.org/media/keys/ACCC4CF8.asc", "Suites: noble-pgdg", "/usr/lib/postgresql/17/bin/pg_dump --version", 'echo /usr/lib/postgresql/17/bin >> "$GITHUB_PATH"'):
        if required not in test_job:
            raise AssertionError(f"matching dump client guard missing: {required}")
    if "wallaby_screenshots" in source or "name: wallaby-screenshots" in source:
        raise AssertionError("raw Wallaby screenshots must not be uploaded")


class ServerWorkflowContractTest(unittest.TestCase):
    def test_real_workflow_and_negative_mutations(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        validate(source)
        mutations = (
            source.replace("Suites: noble-pgdg", "Suites: wrong-pgdg", 1),
            source.replace("postgresql-client-17", "postgresql-client-16", 1),
            source.replace('echo /usr/lib/postgresql/17/bin >> "$GITHUB_PATH"', "true", 1),
            source.replace('test -x "$WALLABY_CHROME_BINARY"', "true", 1),
            source.replace("python3 ../playstead-mac/scripts/ci/discover-browser-tests.py test/playstead_web/browser", "true", 1),
            source + "\n      - uses: actions/upload-artifact@deadbeef\n        with:\n          path: playstead-server/tmp/wallaby_screenshots\n",
        )
        for index, mutated in enumerate(mutations, start=1):
            with self.subTest(mutation=index), self.assertRaises(AssertionError):
                validate(mutated)

    def test_browser_discovery_canary_rejects_zero_cases(self):
        canary = ROOT / "playstead-mac/scripts/ci/discover-browser-tests.py"
        with tempfile.TemporaryDirectory() as temporary:
            suite = pathlib.Path(temporary) / "browser"
            suite.mkdir()
            test_file = suite / "sample_test.exs"
            test_file.write_text('feature "one browser journey" do\nend\n', encoding="utf-8")
            good = subprocess.run([sys.executable, str(canary), str(suite)], capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            test_file.write_text('defmodule Empty do\nend\n', encoding="utf-8")
            empty = subprocess.run([sys.executable, str(canary), str(suite)], capture_output=True, text=True)
            self.assertNotEqual(empty.returncode, 0)


if __name__ == "__main__":
    unittest.main()
