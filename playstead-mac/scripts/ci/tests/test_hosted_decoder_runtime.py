"""Guard same-run image custody and task-owned hosted guest cleanup."""
import os
import json
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
            owned = root / "playstead-media-runtime/c/media"
            owned.mkdir(parents=True)
            unrelated = root / "unrelated-profile"
            unrelated.mkdir()
            calls = root / "calls"
            env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"], RUNNER_TEMP=str(root),
                       GITHUB_ACTIONS="true", RUNNER_OS="macOS", GITHUB_REPOSITORY="szTheory/playstead", CALL_LOG=str(calls))
            result = subprocess.run([str(HELPER), "cleanup"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), ["delete", "media", "--force", "--data"])
            self.assertFalse((root / "playstead-media-runtime").exists())
            self.assertTrue(unrelated.is_dir())

    def test_recipe_keeps_the_actual_scanned_container_and_software_emulation(self):
        helper = HELPER.read_text()
        for token in ["--vm-type qemu --arch x86_64", "--cpu 1 --memory 2 --disk 12",
                      'export DOCKER_HOST="unix://$COLIMA_HOME/media/docker.sock"',
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
        self.assertLess(mac.index("Qualify the owned decoder runtime before native checks"),
                        mac.index("Run no-HID ordinary native layers"))
        self.assertIn("timeout-minutes: 15", mac)
        self.assertIn("--mount none --ssh-config=false --activate=false", helper)
        runner = RUNNER.read_text()
        self.assertIn('hosted-decoder-runtime.sh" start', runner)
        for token in ["--read-only --user 11001:11001 --cap-drop ALL", "--pids-limit 32 --memory 512m", "--security-opt no-new-privileges:true"]:
            self.assertIn(token, runner)

    def test_reported_hosted_ssh_socket_path_fits_the_macos_limit(self):
        root = pathlib.Path("/Users/runner/work/_temp/playstead-media-runtime")
        old = root / "colima/_lima/colima-playstead-media-ci/ssh.sock.1234567890123456"
        self.assertEqual(len(os.fsencode(old)), 113)
        helper = HELPER.read_text()
        home = re.search(r'export COLIMA_HOME="\$RUNTIME_ROOT/([^"\n]+)"', helper).group(1)
        profile = re.search(r"colima start ([a-z0-9-]+) --vm-type", helper).group(1)
        current = root / home / "_lima" / ("colima-" + profile) / "ssh.sock.1234567890123456"
        self.assertLess(len(os.fsencode(current)), 104)
        self.assertIn('export DOCKER_HOST="unix://$COLIMA_HOME/' + profile + '/docker.sock"', helper)
        self.assertIn('unix://$RUNNER_TEMP/playstead-media-runtime/' + home + '/' + profile + '/docker.sock', RUNNER.read_text())

    def test_overlong_owned_socket_fails_before_creating_runtime_or_starting_vm(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            binaries = root / "bin"
            binaries.mkdir()
            (binaries / "uname").write_text("#!/bin/sh\nprintf 'arm64\\n'\n")
            (binaries / "uname").chmod(0o755)
            long_root = root / ("x" * 100)
            long_root.mkdir()
            env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"], RUNNER_TEMP=str(long_root),
                       GITHUB_ACTIONS="true", RUNNER_OS="macOS", GITHUB_REPOSITORY="szTheory/playstead")
            result = subprocess.run([str(HELPER), "start", str(long_root / "playstead-media-decoder-runtime")],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("hosted-decoder-stage=validate-socket-path exit=1", result.stderr)
            self.assertNotIn(str(root), result.stderr)
            self.assertFalse((long_root / "playstead-media-runtime").exists())

    def test_cross_arch_guest_agent_must_be_installed_before_vm_start(self):
        helper = HELPER.read_text()
        self.assertIn("brew install docker colima qemu lima-additional-guestagents", helper)
        self.assertIn('LIMA_HOME="$COLIMA_HOME/_lima" limactl info', helper)
        self.assertLess(helper.index("stage=verify-guest-agent"), helper.index("stage=start-owned-guest"))
        validation = re.search(r'stage=verify-guest-agent\n.*?<<\x27PY\x27\n(.*?)\nPY', helper, re.S).group(1)
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            binary = root / "lima-guestagent.Linux-x86_64.gz"
            binary.write_bytes(b"fixture-agent")
            cases = [
                ({"guestAgents": {"x86_64": {"location": str(binary)}}}, 0),
                ({"guestAgents": {"aarch64": {"location": str(binary)}}}, 1),
                ({"guestAgents": {"x86_64": {"location": str(root / "missing")}}}, 1),
                ({"guestAgents": {"x86_64": {}}}, 1),
                ([], 1),
            ]
            for info, expected in cases:
                with self.subTest(info=info):
                    receipt = root / "info.json"
                    receipt.write_text(json.dumps(info))
                    result = subprocess.run(["python3", "-c", validation, str(receipt)],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertNotIn(str(root), result.stderr)

    def test_owned_store_keeps_config_digest_and_rejects_mismatched_runtime(self):
        helper = HELPER.read_text()
        self.assertIn('cat >"$COLIMA_HOME/media/colima.yaml"', helper)
        # Colima Config.Empty() is true without Runtime. Its start command
        # discards all configured Docker settings for such an empty profile.
        self.assertIn("runtime: docker\ndocker:", helper)
        self.assertIn("containerd-snapshotter: false\n  storage-driver: overlay2", helper)
        self.assertLess(helper.index("stage=configure-owned-image-store"), helper.index("stage=start-owned-guest"))
        # Execute the production load/publication boundary. A different store
        # or ID must fail before it can publish a runtime for the native tests.
        boundary = "stage=verify-daemon" + helper.split("stage=verify-daemon", 1)[1].split("    ;;", 1)[0]
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            docker = root / "docker"
            docker.write_text('''#!/bin/sh
printf '%s\\n' "$*" >>"$CALL_LOG"
case "$*" in
  "info --format {{.OSType}}/{{.Architecture}}") printf 'linux/x86_64\\n' ;;
  "info --format {{.Driver}}") printf '%s\\n' "$TEST_DRIVER" ;;
  "image load --input "*) exit 0 ;;
  "image inspect --format "*) printf '%s\\n' "$TEST_IMAGE_ID" ;;
  *) exit 29 ;;
esac
''')
            docker.chmod(0o755)
            image_id = "sha256:" + "a" * 64
            for driver, actual_id, succeeds, loaded in [
                ("overlay2", image_id, True, True),
                ("overlayfs", image_id, False, False),
                ("overlay2", "sha256:" + "b" * 64, False, True),
            ]:
                with self.subTest(driver=driver, actual_id=actual_id):
                    calls, exported = root / "calls", root / "github-env"
                    calls.unlink(missing_ok=True)
                    exported.unlink(missing_ok=True)
                    env = dict(os.environ, PATH=str(root) + ":" + os.environ["PATH"], CALL_LOG=str(calls),
                               TEST_DRIVER=driver, TEST_IMAGE_ID=actual_id, GITHUB_ENV=str(exported),
                               DOCKER_HOST="unix://owned/docker.sock", DOCKER_CONFIG=str(root / "client"),
                               image_id=image_id, artifact=str(root / "artifact"))
                    result = subprocess.run(["/bin/bash", "-eu", "-c", boundary], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, succeeds, result.stderr)
                    self.assertEqual("image load --input" in calls.read_text(), loaded)
                    self.assertEqual(exported.exists(), succeeds)
                    if succeeds:
                        self.assertIn("PLAYSTEAD_MEDIA_DECODER_IMAGE=" + image_id, exported.read_text())

    def test_failed_setup_reports_only_its_finite_stage_and_keeps_exit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            binaries = root / "bin"
            binaries.mkdir()
            (binaries / "uname").write_text("#!/bin/sh\nprintf 'arm64\\n'\n")
            (binaries / "uname").chmod(0o755)
            env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"], RUNNER_TEMP=str(root),
                       GITHUB_ACTIONS="true", RUNNER_OS="macOS", GITHUB_REPOSITORY="szTheory/playstead")
            result = subprocess.run([str(HELPER), "start", str(root / "wrong-artifact")],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("hosted-decoder-stage=validate-action exit=2", result.stderr)
            self.assertNotIn(str(root), result.stderr)
            self.assertFalse((root / "playstead-media-runtime").exists())

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
