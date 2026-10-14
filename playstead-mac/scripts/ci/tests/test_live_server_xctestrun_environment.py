"""Execute the real generated-xctestrun environment writer without Xcode."""
import os
import pathlib
import stat
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
            initial = {"TestPlan": {"Name": "LiveServer"}, "TestConfigurations": [{"Name": "LiveServer", "TestTargets": [{"BlueprintName": "PlaysteadUITests", "EnvironmentVariables": {"PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH": ""}, "TestingEnvironmentVariables": {"PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH": ""}}]}]}
            values = [str(root / "profile"), str(root / "stages"), str(root / "stage.json"), "ecto://fixture/database", "mac_ci", "4010", str(root / "ca.der"), "a" * 64, str(root / "runtime-configuration-path-longer-than-a-ca-digest-is-allowed.json"), str(root / "fixtures.json"), str(root / "playstead-gb-save-e2e.A1b2C3"), str(root / "private-readback-evidence")]
            run.write_bytes(plistlib.dumps(initial))
            good = subprocess.run([sys.executable, "-c", writers[0], str(run), *values], text=True, capture_output=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            target = plistlib.loads(run.read_bytes())["TestConfigurations"][0]["TestTargets"][0]
            self.assertEqual(target["EnvironmentVariables"]["PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256"], "a" * 64)
            self.assertEqual(target["TestingEnvironmentVariables"]["PLAYSTEAD_GB_GBC_FIXTURE_REGISTRY"], values[-3])
            self.assertEqual(target["TestingEnvironmentVariables"]["PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT"], values[-2])
            for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
                self.assertEqual(target[key]["PLAYSTEAD_GB_GBC_SAVE_EVIDENCE_DIRECTORY"], values[-1])
                self.assertEqual(target[key]["PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH"], "")
            relative = values.copy()
            relative[-1] = "relative-output"
            rejected = subprocess.run([sys.executable, "-c", writers[0], str(run), *relative], text=True, capture_output=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("path is not absolute", rejected.stderr)
            values[7] = "invalid-digest"
            bad = subprocess.run([sys.executable, "-c", writers[0], str(run), *values], text=True, capture_output=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("CA digest is invalid", bad.stderr)


    def test_full_shell_materializer_supplies_private_game_evidence_output(self):
        body = SCRIPT.read_text().split("materialize_live_server_xctestrun() {", 1)[1].split("\nrestore_keyboard_mode() {", 1)[0]
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            products = root / "DerivedData/Build/Products"
            products.mkdir(parents=True)
            raw = root / "raw"
            raw.mkdir(mode=0o700)
            run = products / "LiveServer.xctestrun"
            initial = {"TestPlan": {"Name": "LiveServer"}, "TestConfigurations": [{"Name": "LiveServer", "TestTargets": [{"BlueprintName": "PlaysteadUITests", "EnvironmentVariables": {"PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH": ""}, "TestingEnvironmentVariables": {"PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH": ""}}]}]}
            run.write_bytes(plistlib.dumps(initial))
            env = dict(os.environ, DERIVED_DATA=str(root / "DerivedData"), FOUR_LAYER_RAW=str(raw),
                       MAC_ROOT=str(ROOT / "playstead-mac"), PLAYSTEAD_MAC_CI_ROOT=str(root / "app"),
                       PLAYSTEAD_LIVE_SERVER_STAGE_ROOT=str(root / "app"),
                       PLAYSTEAD_LIVE_SERVER_STAGE_FILE=str(root / "stage"),
                       MAC_CI_DATABASE_URL="ecto://fixture/database", MIX_ENV="mac_ci", PORT="4010",
                       LIVE_SERVER_CA_DER=str(root / "ca.der"), PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256="a" * 64,
                       LIVE_SERVER_RUNTIME_CONFIG=str(root / "runtime.json"),
                       PLAYSTEAD_GB_GBC_FIXTURE_REGISTRY=str(root / "fixtures.json"),
                       PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT=str(root / "playstead-gb-save-e2e.A1b2C3"))
            command = "set -euo pipefail\ndie() { printf '%s\\n' \"$*\" >&2; exit 1; }\nmaterialize_live_server_xctestrun() {" + body + "\nmaterialize_live_server_xctestrun\n"
            result = subprocess.run(["/bin/bash", "-c", command], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = plistlib.loads(run.read_bytes())["TestConfigurations"][0]["TestTargets"][0]
            output = raw / "gb-gbc-readback"
            self.assertTrue(output.is_dir())
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
            for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
                self.assertEqual(target[key]["PLAYSTEAD_GB_GBC_SAVE_EVIDENCE_DIRECTORY"], str(output))
                self.assertEqual(target[key]["PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH"], "")


if __name__ == "__main__":
    unittest.main()
