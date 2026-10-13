"""Execute the real generated-xctestrun environment writer without Xcode."""
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[4]
SCRIPT = ROOT / "playstead-mac/scripts/ci/run-mac-verification.sh"


class LiveServerXctestrunEnvironmentTests(unittest.TestCase):
    def test_named_ca_digest_remains_correct_after_registry_field_extension(self):
        chunks = re.findall(r"<<'PY'\n(.*?)\nPY", SCRIPT.read_text(), re.S)
        writers = [code for code in chunks if 'keys = (' in code and 'PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256' in code and 'environment.update(values)' in code]
        self.assertEqual(len(writers), 1)
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            run = root / "LiveServer.xctestrun"
            initial = {"TestPlan": {"Name": "LiveServer"}, "TestConfigurations": [{"Name": "LiveServer", "TestTargets": [{"BlueprintName": "PlaysteadUITests"}]}]}
            values = [str(root / "profile"), str(root / "stages"), str(root / "stage.json"), "ecto://fixture/database", "mac_ci", "4010", str(root / "ca.der"), "a" * 64, str(root / "runtime-configuration-path-longer-than-a-ca-digest-is-allowed.json"), str(root / "fixtures.json")]
            run.write_bytes(plistlib.dumps(initial))
            good = subprocess.run([sys.executable, "-c", writers[0], str(run), *values], text=True, capture_output=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            target = plistlib.loads(run.read_bytes())["TestConfigurations"][0]["TestTargets"][0]
            self.assertEqual(target["EnvironmentVariables"]["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"], "a" * 64)
            self.assertEqual(target["TestingEnvironmentVariables"]["PLAYSTEAD_GB_GBC_FIXTURE_REGISTRY"], values[-1])
            values[7] = "invalid-digest"
            bad = subprocess.run([sys.executable, "-c", writers[0], str(run), *values], text=True, capture_output=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("CA digest is invalid", bad.stderr)


if __name__ == "__main__":
    unittest.main()
