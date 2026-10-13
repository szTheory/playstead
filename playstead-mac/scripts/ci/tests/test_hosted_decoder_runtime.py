"""Guard same-run image custody and task-owned hosted guest cleanup."""
import os
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[4]
HELPER = ROOT / "playstead-mac/scripts/ci/hosted-decoder-runtime.sh"
WORKFLOW = ROOT / ".github/workflows/ci.yml"
RUNNER = ROOT / "playstead-mac/scripts/ci/run-mac-verification.sh"


class HostedDecoderRuntimeTests(unittest.TestCase):
    def test_ordinary_local_authorization_does_not_start_a_guest(self):
        env = dict(os.environ, GITHUB_ACTIONS="false", PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH="1")
        result = subprocess.run([str(HELPER), "start", "/tmp/unused"], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("task hosted Apple Silicon runner", result.stderr)

    def test_wrong_repository_is_rejected_before_any_runtime_action(self):
        env = dict(os.environ, GITHUB_ACTIONS="true", RUNNER_OS="macOS", GITHUB_REPOSITORY="another/repository")
        result = subprocess.run([str(HELPER), "cleanup"], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_cleanup_targets_only_the_owned_profile_and_home(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            binaries = root / "bin"
            binaries.mkdir()
            (binaries / "uname").write_text("#!/bin/sh\nprintf 'arm64\\n'\n")
            (binaries / "colima").write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" >\"$CALL_LOG\"\n")
            for path in binaries.iterdir():
                path.chmod(0o755)
            owned = root / "playstead-media-runtime/colima/playstead-media-ci"
            owned.mkdir(parents=True)
            unrelated = root / "unrelated-profile"
            unrelated.mkdir()
            calls = root / "calls"
            env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"], RUNNER_TEMP=str(root),
                       GITHUB_ACTIONS="true", RUNNER_OS="macOS", GITHUB_REPOSITORY="szTheory/playstead", CALL_LOG=str(calls))
            result = subprocess.run([str(HELPER), "cleanup"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), ["delete", "playstead-media-ci", "--force", "--data"])
            self.assertFalse((root / "playstead-media-runtime").exists())
            self.assertTrue(unrelated.is_dir())

    def test_recipe_keeps_the_actual_scanned_container_and_software_emulation(self):
        helper = HELPER.read_text()
        for token in ["--vm-type qemu --arch x86_64", "--cpu 1 --memory 2 --disk 12",
                      'export DOCKER_HOST="unix://$COLIMA_HOME/playstead-media-ci/docker.sock"',
                      'media-decoder-evidence.py" verify', 'docker image load --input',
                      'docker image inspect --format', 'decoder-signing.rsa.pub', 'endswith(".rsa")']:
            self.assertIn(token, helper)
        workflow = WORKFLOW.read_text()
        mac = workflow.split("  mac-verification:\n", 1)[1].split("\n  recovery-fixture:", 1)[0]
        self.assertIn("name: media-decoder-runtime", mac)
        self.assertNotIn("run-id:", mac)
        self.assertIn("hosted-decoder-runtime.sh cleanup", mac)
        self.assertIn('docker image save --output "$runtime_artifact/decoder-image.tar" "$PLAYSTEAD_MEDIA_DECODER_IMAGE"', workflow)
        self.assertIn("ops/media-decoder/build/generated/.", workflow)
        runner = RUNNER.read_text()
        self.assertIn('hosted-decoder-runtime.sh" start', runner)
        for token in ["--read-only --user 11001:11001 --cap-drop ALL", "--pids-limit 32 --memory 512m", "--security-opt no-new-privileges:true"]:
            self.assertIn(token, runner)

    def test_native_setup_failure_stages_partial_evidence_without_losing_exit(self):
        source = RUNNER.read_text()
        body = re.search(r"stage_native_setup_failure_evidence\(\) \{\n(.*?)\n\}", source, re.S)
        self.assertIsNotNone(body)
        for sanitizer_exit in [0, 7]:
            with self.subTest(sanitizer_exit=sanitizer_exit), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary)
                scripts = root / "scripts"
                scripts.mkdir()
                calls = root / "calls"
                sanitizer = scripts / "sanitize-evidence.sh"
                sanitizer.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" >\"$CALL_LOG\"\nexit " + str(sanitizer_exit) + "\n")
                sanitizer.chmod(0o755)
                script = "stage_native_setup_failure_evidence() {\n" + body.group(1) + "\n}\n"
                script += "trap 'stage_native_setup_failure_evidence' EXIT\nexit 37\n"
                env = dict(os.environ, CALL_LOG=str(calls), UI_NO_HID="true", BUILD_ROOT=str(root),
                           FOUR_LAYER_ROOT=str(root / "four-layer"), FAILURE_EVIDENCE=str(root / "failure"), SCRIPT_DIR=str(scripts))
                result = subprocess.run(["/bin/bash", "-c", script], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 37, result.stderr)
                self.assertEqual(calls.read_text().splitlines(), ["--input", str(root / "four-layer"),
                                                                 "--output", str(root / "ordinary-failure-evidence")])


if __name__ == "__main__":
    unittest.main()
