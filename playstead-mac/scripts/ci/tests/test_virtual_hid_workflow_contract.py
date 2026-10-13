"""App-free trust contract for the protected Virtual HID qualification lane."""

from __future__ import annotations

import pathlib
import re
import datetime
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[4]
WORKFLOW = REPO_ROOT / ".github/workflows/virtual-hid-qualification.yml"
RUNNER = REPO_ROOT / "playstead-mac/scripts/ci/run-mac-verification.sh"
SIGNING = REPO_ROOT / "playstead-mac/scripts/ci/virtual-hid-signing.sh"
EVIDENCE = REPO_ROOT / "playstead-mac/scripts/ci/virtual-hid-evidence.py"
SANITIZER = REPO_ROOT / "playstead-mac/scripts/ci/sanitize-evidence.sh"
ENTITLED_TEST = "ControllerHardwareIntegrationTests/testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch"
ENTITLED_TEST_FULL = "PlaysteadUITests." + ENTITLED_TEST
TEAM = "ABCDE12345"
PROFILE_UUID = "11111111-2222-4333-8444-555555555555"
DECOY_UUID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
CERT_BYTES = b"fixture Apple Development certificate"
CERT_SHA1 = hashlib.sha1(CERT_BYTES).hexdigest().upper()


def workflow_policy_errors(source: str) -> list[str]:
    executable = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    errors: list[str] = []

    trigger = re.search(r"(?ms)^on:\s*\n(?P<events>.*?)(?=^[^ \t]|\Z)", executable)
    if not trigger or re.findall(r"(?m)^  ([A-Za-z_][A-Za-z0-9_-]*):", trigger["events"]) != ["workflow_dispatch"]:
        errors.append("only workflow_dispatch is allowed")
    for line in executable.splitlines():
        if re.match(r"\s*uses:\s*", line):
            if not re.search(r"uses:\s*[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}(?:\s|$)", line):
                errors.append("every action must use a full commit SHA")
                break

    required_literals = (
        "github.repository == 'szTheory/playstead'",
        "github.ref == 'refs/heads/main'",
        "runs-on: macos-26",
        "name: playstead-hid",
        "contents: read",
        "ref: ${{ github.sha }}",
        "persist-credentials: false",
        "scripts/ci/virtual-hid-signing.sh install-and-run",
        "scripts/ci/virtual-hid-signing.sh cleanup",
        "if: always()",
        "scripts/ci/virtual-hid-evidence.py",
    )
    for literal in required_literals:
        if literal not in executable:
            errors.append(f"required protected workflow setting missing: {literal}")

    cleanup = re.search(r"(?ms)^      - name: Remove temporary signing material\n(?P<step>.*?)(?=^      - name:|\Z)", executable)
    if not cleanup or "if: always()" not in cleanup["step"]:
        errors.append("signing cleanup must run on every workflow exit path")

    secret_names = {
        "PLAYSTEAD_HID_CERT_P12_BASE64",
        "PLAYSTEAD_HID_CERT_P12_PASSWORD",
        "PLAYSTEAD_HID_PROFILE_BASE64",
    }
    secret_refs = re.findall(r"\$\{\{\s*secrets\.([A-Z0-9_]+)\s*\}\}", executable)
    if sorted(secret_refs) != sorted(secret_names):
        errors.append("only the three signing secrets may be referenced, once each")

    steps = re.split(r"(?m)^      - name:", executable)
    secret_blocks = [block for block in steps if "${{ secrets." in block]
    if len(secret_blocks) != 1 or "virtual-hid-signing.sh install-and-run" not in secret_blocks[0]:
        errors.append("signing secrets must be scoped only to install-and-run")

    upload = re.search(r"(?ms)^      - name: Upload sanitized Virtual HID evidence\n(?P<step>.*?)(?=^      - name:|\Z)", executable)
    if not upload:
        errors.append("sanitized evidence upload step is required")
    else:
        step = upload["step"]
        paths = re.findall(r"(?m)^            (.+)$", step)
        expected = {
            "${{ runner.temp }}/playstead-mac-ci/entitled-virtual-gamepad/sanitized/entitled-gamepad.json",
            "${{ runner.temp }}/playstead-mac-ci/entitled-virtual-gamepad/sanitized/ui-tests.json",
            "${{ runner.temp }}/playstead-mac-ci/entitled-virtual-gamepad/sanitized/virtual-hid-manifest.json",
        }
        if set(paths) != expected:
            errors.append("upload paths must be exactly the two sanitized JSON files and manifest")
        if "failure-evidence" in step or ".xcresult" in step or "DerivedData" in step or "private/" in step:
            errors.append("raw test or signing artifacts must not be uploaded")
    return errors


def verification_invocation_errors(source: str) -> list[str]:
    expected = 'bash "${SCRIPT_DIR}/run-mac-verification.sh" --run-entitled-virtual-gamepad-verification'
    return [] if expected in source else ["exact entitled verification command is missing"]


class VirtualHIDWorkflowContractTests(unittest.TestCase):
    def test_workflow_is_manual_trusted_main_and_github_hosted(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8") if WORKFLOW.is_file() else ""
        self.assertEqual([], workflow_policy_errors(source))

    def test_workflow_rejects_triggers_ref_repo_runner_environment_and_permission_mutations(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        mutations = {
            "extra trigger": source.replace("workflow_dispatch:\n", "workflow_dispatch:\n  pull_request:\n", 1),
            "wrong ref": source.replace("refs/heads/main", "refs/heads/release", 1),
            "wrong repository": source.replace("szTheory/playstead", "attacker/playstead", 1),
            "wrong runner": source.replace("runs-on: macos-26", "runs-on: self-hosted", 1),
            "wrong environment": source.replace("name: playstead-hid", "name: another-environment", 1),
            "widened permissions": source.replace("contents: read", "contents: write", 1),
        }
        for name, candidate in mutations.items():
            with self.subTest(mutation=name):
                self.assertTrue(workflow_policy_errors(candidate))

    def test_workflow_rejects_secret_scope_cleanup_action_command_and_artifact_mutations(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        secret_scope = source.replace(
            "      - name: Checkout trusted dispatch SHA\n",
            "      - name: Checkout trusted dispatch SHA\n"
            "        env:\n"
            "          EXTRA: ${{ secrets.PLAYSTEAD_HID_CERT_P12_BASE64 }}\n",
            1,
        )
        cleanup = source.replace(
            "      - name: Remove temporary signing material\n        if: always()",
            "      - name: Remove temporary signing material\n        if: success()",
            1,
        )
        action = re.sub(r"(actions/checkout@)[0-9a-f]{40}", r"\1v4", source, count=1)
        artifact = source.replace(
            "${{ runner.temp }}/playstead-mac-ci/entitled-virtual-gamepad/sanitized/ui-tests.json",
            "playstead-mac/.build/ci/raw/virtual-gamepad.log",
            1,
        )
        for name, candidate in (
            ("secret scope", secret_scope),
            ("cleanup", cleanup),
            ("unpinned action", action),
            ("raw artifact", artifact),
        ):
            with self.subTest(mutation=name):
                self.assertTrue(workflow_policy_errors(candidate))

    def test_evidence_generator_requires_all_current_run_identity_fields(self) -> None:
        source = EVIDENCE.read_text(encoding="utf-8") if EVIDENCE.is_file() else ""
        self.assertEqual([], evidence_identity_errors(source))

    def test_evidence_generator_rejects_each_missing_identity_field(self) -> None:
        source = EVIDENCE.read_text(encoding="utf-8")
        for field in ("GITHUB_REPOSITORY", "GITHUB_WORKFLOW", "GITHUB_EVENT_NAME", "GITHUB_REF", "GITHUB_SHA", "GITHUB_RUN_ID"):
            with self.subTest(field=field):
                changed = source.replace(field, "REMOVED_" + field, 1)
                self.assertTrue(evidence_identity_errors(changed))

    def test_signing_helper_invokes_only_the_exact_entitled_verification_command(self) -> None:
        source = SIGNING.read_text(encoding="utf-8") if SIGNING.is_file() else ""
        self.assertEqual([], verification_invocation_errors(source))
        mutated = source.replace("--run-entitled-virtual-gamepad-verification", "--run-four-layer-verification", 1)
        self.assertTrue(verification_invocation_errors(mutated))

    def test_evidence_manifest_is_bounded_allowlisted_and_run_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            sanitized = root / "sanitized"
            sanitized.mkdir()
            write_sanitized_fixtures(sanitized)
            output = sanitized / "virtual-hid-manifest.json"
            result = run_evidence(sanitized, output, identity_environment())
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(
                {
                    "repository": "szTheory/playstead",
                    "workflow": "virtual-hid-qualification",
                    "event": "workflow_dispatch",
                    "ref": "refs/heads/main",
                    "sha": "0123456789abcdef0123456789abcdef01234567",
                    "run_id": "9001",
                },
                manifest["run"],
            )
            self.assertEqual(
                {"entitled-gamepad.json", "ui-tests.json"},
                set(manifest["files"]),
            )
            for name in manifest["files"]:
                self.assertEqual(hashlib.sha256((sanitized / name).read_bytes()).hexdigest(), manifest["files"][name]["sha256"])

    def test_run_manifest_composes_with_real_sanitizer_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            source = root / "run"
            evidence = source / "evidence"
            evidence.mkdir(parents=True)
            sanitized = root / "sanitized"
            write_sanitized_fixtures(evidence)

            sanitize = subprocess.run(
                ["bash", str(SANITIZER), "--input", str(source), "--output", str(sanitized)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(0, sanitize.returncode, sanitize.stdout + sanitize.stderr)
            self.assertTrue((sanitized / "manifest.json").is_file())

            output = sanitized / "virtual-hid-manifest.json"
            result = run_evidence(sanitized, output, identity_environment())
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual({"entitled-gamepad.json", "ui-tests.json"}, set(manifest["files"]))

            sanitizer_manifest = json.loads((sanitized / "manifest.json").read_text(encoding="utf-8"))
            sanitizer_manifest["files"][0]["path"] = "raw.log"
            (sanitized / "manifest.json").write_text(json.dumps(sanitizer_manifest), encoding="utf-8")
            output.unlink()
            rejected = run_evidence(sanitized, output, identity_environment())
            self.assertNotEqual(0, rejected.returncode)
            self.assertIn("sanitizer manifest file identity is invalid", rejected.stderr)

    def test_evidence_manifest_rejects_extra_fields_oversize_and_missing_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            sanitized = root / "sanitized"
            sanitized.mkdir()
            write_sanitized_fixtures(sanitized)
            env = identity_environment()

            gamepad = json.loads((sanitized / "entitled-gamepad.json").read_text())
            gamepad["private_path"] = "/private/secret"
            (sanitized / "entitled-gamepad.json").write_text(json.dumps(gamepad))
            rejected = run_evidence(sanitized, sanitized / "virtual-hid-manifest.json", env)
            self.assertNotEqual(0, rejected.returncode)
            self.assertIn("entitled gamepad evidence schema is not allowlisted", rejected.stderr)

            write_sanitized_fixtures(sanitized)
            (sanitized / "extra.log").write_text("untrusted raw output")
            rejected = run_evidence(sanitized, sanitized / "virtual-hid-manifest.json", env)
            self.assertNotEqual(0, rejected.returncode)
            self.assertIn("sanitized evidence directory contains missing or non-allowlisted files", rejected.stderr)

            (sanitized / "extra.log").unlink()
            (sanitized / "ui-tests.json").write_bytes(b" " * (256 * 1024 + 1))
            rejected = run_evidence(sanitized, sanitized / "virtual-hid-manifest.json", env)
            self.assertNotEqual(0, rejected.returncode)
            self.assertIn("sanitized evidence file size is invalid: ui-tests.json", rejected.stderr)

            write_sanitized_fixtures(sanitized)
            missing = dict(env)
            del missing["GITHUB_EVENT_NAME"]
            rejected = run_evidence(sanitized, sanitized / "virtual-hid-manifest.json", missing)
            self.assertNotEqual(0, rejected.returncode)
            self.assertIn("GitHub run identity is incomplete or malformed", rejected.stderr)


def evidence_identity_errors(source: str) -> list[str]:
    fields = (
        "GITHUB_REPOSITORY",
        "GITHUB_WORKFLOW",
        "GITHUB_EVENT_NAME",
        "GITHUB_REF",
        "GITHUB_SHA",
        "GITHUB_RUN_ID",
    )
    block = re.search(r"(?ms)^ENVIRONMENT_FIELDS\s*=\s*\((.*?)\)", source)
    if not block:
        return list(fields)
    return [field for field in fields if f'"{field}"' not in block[1]]


def identity_environment() -> dict[str, str]:
    return {
        "GITHUB_REPOSITORY": "szTheory/playstead",
        "GITHUB_WORKFLOW": "virtual-hid-qualification",
        "GITHUB_EVENT_NAME": "workflow_dispatch",
        "GITHUB_REF": "refs/heads/main",
        "GITHUB_SHA": "0123456789abcdef0123456789abcdef01234567",
        "GITHUB_RUN_ID": "9001",
    }


def write_sanitized_fixtures(root: pathlib.Path) -> None:
    gamepad = {
        "schema_version": 1,
        "lane": "virtual_gamepad",
        "test_identifier": ENTITLED_TEST_FULL,
        "status": "passed",
        "gate_passed": True,
    }
    required = {
        "identifier": ENTITLED_TEST + "()",
        "discovered": True,
        "execution_count": 1,
        "skipped": False,
        "outcome": "passed",
    }
    ui_tests = {
        "schema_version": 1,
        "layer": "ui",
        "executed_test_count": 1,
        "runner_process_error_count": 0,
        "required_tests": [required],
        "failed_test_count": 0,
        "failed_tests_truncated": False,
        "failed_tests": [],
        "failure_diagnostic_count": 0,
        "failure_diagnostics_truncated": False,
        "failure_diagnostics": [],
        "layout_diagnostic_count": 0,
        "layout_diagnostics_truncated": False,
        "layout_diagnostics": [],
        "audit_issue_count": 0,
        "audit_issues_truncated": False,
        "audit_issues": [],
        "in_test_seconds_total": 1.0,
        "timed_test_count": 1,
        "slowest_tests": [{"identifier": ENTITLED_TEST + "()", "seconds": 1.0}],
    }
    (root / "entitled-gamepad.json").write_text(json.dumps(gamepad) + "\n", encoding="utf-8")
    (root / "ui-tests.json").write_text(json.dumps(ui_tests) + "\n", encoding="utf-8")
    files = ["entitled-gamepad.json", "ui-tests.json"]
    records = [
        {"path": name, "size_bytes": (root / name).stat().st_size}
        for name in files
    ]
    (root / "manifest.json").write_text(
        json.dumps({
            "schema_version": 1,
            "file_count": len(records),
            "total_size_bytes": sum(record["size_bytes"] for record in records),
            "files": records,
        }) + "\n",
        encoding="utf-8",
    )


def run_evidence(directory: pathlib.Path, output: pathlib.Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    merged = dict(os.environ)
    merged.update(env)
    return subprocess.run(
        ["python3", str(EVIDENCE), "--sanitized-dir", str(directory), "--output", str(output)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env=merged,
    )


class VirtualHIDSigningAndRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.xcode_capture = self.root / "xcode-args"
        self.profile_files_capture = self.root / "profile-files"
        self.signing_state_capture = self.root / "signing-state"
        self.write_tool("security", SECURITY_STUB)
        self.write_tool("openssl", OPENSSL_STUB)
        self.write_tool("xcodebuild", XCODE_STUB)
        self.write_tool("xcrun", XCRUN_STUB)
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HOME": str(self.root / "home"),
            "RUNNER_TEMP": str(self.root / "runner-temp"),
            "PLAYSTEAD_CI_BUILD_ROOT": str(self.root / "build"),
            "XCODE_CAPTURE": str(self.xcode_capture),
            "PROFILE_FILES_CAPTURE": str(self.profile_files_capture),
            "SIGNING_STATE_CAPTURE": str(self.signing_state_capture),
            "FAKE_CERT_SHA1": CERT_SHA1,
            "GITHUB_ACTIONS": "true",
            "GITHUB_RUN_ID": "9001",
            "PLAYSTEAD_HID_CERT_P12_BASE64": __import__("base64").b64encode(b"fixture p12").decode(),
            "PLAYSTEAD_HID_CERT_P12_PASSWORD": "fixture-password",
            "PLAYSTEAD_HID_PROFILE_BASE64": "",
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_tool(self, name: str, content: str) -> None:
        path = self.bin / name
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def make_profile(
        self,
        root: pathlib.Path,
        *,
        app_identifier: str | None = None,
        team: str = TEAM,
        certificate: bytes = CERT_BYTES,
        hid: bool = True,
        expires: str = "2099-01-01T00:00:00Z",
        profile_uuid: str = PROFILE_UUID,
    ) -> pathlib.Path:
        root.mkdir(parents=True, exist_ok=True)
        expiration = datetime.datetime.fromisoformat(expires.replace("Z", "+00:00"))
        entitlements = {
            "application-identifier": app_identifier or f"{team}.dev.playstead.mac.PlaysteadUITests",
            "com.apple.developer.hid.virtual.device": hid,
        }
        profile = {
            "UUID": profile_uuid,
            "TeamIdentifier": [team],
            "ExpirationDate": expiration,
            "Entitlements": entitlements,
            "DeveloperCertificates": [certificate],
        }
        path = root / f"{profile_uuid}.mobileprovision"
        path.write_bytes(plistlib.dumps(profile, fmt=plistlib.FMT_XML))
        return path

    def runner_env(self, profile_root: pathlib.Path) -> dict[str, str]:
        return {
            **self.env,
            "PLAYSTEAD_VIRTUAL_HID_PROFILE_ROOT": str(profile_root),
        }

    def run_runner(self, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(RUNNER), "--run-entitled-virtual-gamepad-verification"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=env,
            timeout=30,
        )

    def test_private_override_selects_exact_validated_profile_not_default_decoy(self) -> None:
        profile_root = self.root / "private-profiles"
        self.make_profile(profile_root)
        default_root = pathlib.Path(self.env["HOME"]) / "Library/MobileDevice/Provisioning Profiles"
        self.make_profile(default_root, profile_uuid=DECOY_UUID)
        result = self.run_runner(self.runner_env(profile_root))
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        arguments = self.xcode_capture.read_text(encoding="utf-8").splitlines()
        self.assertIn(f"PROVISIONING_PROFILE_SPECIFIER={PROFILE_UUID}", arguments)
        self.assertNotIn(f"PROVISIONING_PROFILE_SPECIFIER={DECOY_UUID}", arguments)
        self.assertFalse(list(pathlib.Path(self.env["PLAYSTEAD_CI_BUILD_ROOT"]).glob("entitled-virtual-gamepad/run.*")))

    def test_private_override_rejects_wildcard_or_alternate_profile_without_default_fallback(self) -> None:
        invalid_profiles = (
            {"app_identifier": f"{TEAM}.*", "profile_uuid": PROFILE_UUID},
            {"app_identifier": f"{TEAM}.dev.attacker.mac.PlaysteadUITests", "profile_uuid": PROFILE_UUID},
            {"app_identifier": "OTHERTEAM1234.dev.playstead.mac.PlaysteadUITests", "profile_uuid": PROFILE_UUID},
        )
        for index, profile_values in enumerate(invalid_profiles):
            with self.subTest(profile=profile_values["app_identifier"]):
                self.xcode_capture.unlink(missing_ok=True)
                profile_root = self.root / f"private-invalid-{index}"
                self.make_profile(profile_root, **profile_values)
                default_root = pathlib.Path(self.env["HOME"]) / "Library/MobileDevice/Provisioning Profiles"
                self.make_profile(default_root, profile_uuid=DECOY_UUID)
                result = self.run_runner(self.runner_env(profile_root))
                self.assertEqual(77, result.returncode, result.stdout + result.stderr)
                self.assertFalse(self.xcode_capture.exists(), "invalid private profile reached Xcode")

    def test_default_lookup_behavior_still_accepts_existing_wildcard_profile(self) -> None:
        default_root = pathlib.Path(self.env["HOME"]) / "Library/MobileDevice/Provisioning Profiles"
        wildcard_uuid = "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"
        self.make_profile(default_root, app_identifier=f"{TEAM}.*", profile_uuid=wildcard_uuid)
        env = dict(self.env)
        env.pop("PLAYSTEAD_VIRTUAL_HID_PROFILE_ROOT", None)
        result = self.run_runner(env)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(f"PROVISIONING_PROFILE_SPECIFIER={wildcard_uuid}", self.xcode_capture.read_text())

    def test_signing_helper_rejects_missing_or_invalid_profile_before_xcode(self) -> None:
        profile_cases = (
            {"app_identifier": f"{TEAM}.*"},
            {"app_identifier": f"{TEAM}.dev.attacker.mac.PlaysteadUITests"},
            {"team": "OTHERTEAM1234"},
            {"hid": False},
            {"expires": "2000-01-01T00:00:00Z"},
            {"certificate": b"a different certificate"},
            {"malformed_base64": True},
            {"missing_profile": True},
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            for index, values in enumerate(profile_cases):
                with self.subTest(profile=values):
                    self.xcode_capture.unlink(missing_ok=True)
                    profile_dir = root / f"profile-{index}"
                    values = dict(values)
                    malformed_base64 = values.pop("malformed_base64", False)
                    missing_profile = values.pop("missing_profile", False)
                    profile_path = self.make_profile(profile_dir, **values)
                    profile_data = "not-base64" if malformed_base64 else (
                        "" if missing_profile else __import__("base64").b64encode(profile_path.read_bytes()).decode()
                    )
                    env = {**self.env, "PLAYSTEAD_HID_PROFILE_BASE64": profile_data}
                    result = subprocess.run(
                        ["bash", str(SIGNING), "install-and-run"],
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        check=False,
                        env=env,
                        timeout=30,
                    )
                    self.assertNotEqual(0, result.returncode)
                    self.assertFalse(self.xcode_capture.exists(), "invalid signing profile reached Xcode")
                    self.assertNotIn("fixture-password", result.stdout + result.stderr)
                    subprocess.run(["bash", str(SIGNING), "cleanup"], env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def test_signing_helper_validates_and_installs_the_exact_profile_used_by_xcode(self) -> None:
        profile_root = self.root / "input"
        profile_path = self.make_profile(profile_root)
        output_file = self.root / "github-output"
        env = {
            **self.env,
            "PLAYSTEAD_HID_PROFILE_BASE64": __import__("base64").b64encode(profile_path.read_bytes()).decode(),
            "GITHUB_OUTPUT": str(output_file),
        }
        result = subprocess.run(
            ["bash", str(SIGNING), "install-and-run"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=env,
            timeout=30,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        arguments = self.xcode_capture.read_text(encoding="utf-8").splitlines()
        self.assertIn(f"PROVISIONING_PROFILE_SPECIFIER={PROFILE_UUID}", arguments)
        self.assertEqual(
            [f"{PROFILE_UUID}.mobileprovision"],
            [pathlib.Path(line).name for line in self.profile_files_capture.read_text(encoding="utf-8").splitlines()],
        )
        signing_state = self.signing_state_capture.read_text(encoding="utf-8").splitlines()
        self.assertEqual([], [name for name in signing_state if name.startswith("PLAYSTEAD_HID_")])
        self.assertFalse(
            {"certificate.p12", "certificate.pem", "profile.mobileprovision", "profile.plist"}
            & set(signing_state)
        )
        self.assertEqual("sanitized=true", output_file.read_text(encoding="utf-8").strip())
        subprocess.run(["bash", str(SIGNING), "cleanup"], env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.assertFalse((pathlib.Path(env["HOME"]) / "Library/MobileDevice/Provisioning Profiles" / f"{PROFILE_UUID}.mobileprovision").exists())
        self.assertFalse((pathlib.Path(env["RUNNER_TEMP"]) / "playstead-virtual-hid-9001").exists())

        self.xcode_capture.unlink(missing_ok=True)
        missing = {**self.env, "PLAYSTEAD_HID_CERT_P12_BASE64": ""}
        result = subprocess.run(
            ["bash", str(SIGNING), "install-and-run"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=missing,
            timeout=30,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertNotIn("fixture-password", result.stdout + result.stderr)
        self.assertFalse(self.xcode_capture.exists())


SECURITY_STUB = textwrap.dedent(
    """\
    #!/usr/bin/env bash
    set -eu
    case "$1" in
      cms)
        shift
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-i" ]; then cat "$2"; exit 0; fi
          shift
        done
        exit 2
        ;;
      find-identity)
    printf '  1) %s "Apple Development: Fixture (%s)"\\n' "$FAKE_CERT_SHA1" "${TEAM:-ABCDE12345}"
        ;;
      list-keychains)
        if [ "${3:-}" = "-s" ]; then printf '%s\\n' "$4" >"${KEYCHAIN_LIST_CAPTURE:-/dev/null}"; else printf '"%s/Library/Keychains/login.keychain-db"\\n' "$HOME"; fi
        ;;
      create-keychain)
        keychain=""
        for argument in "$@"; do keychain="$argument"; done
        touch "$keychain"
        ;;
      delete-keychain)
        rm -f "$2"
        ;;
      *) exit 0 ;;
    esac
    """
)

OPENSSL_STUB = textwrap.dedent(
    """\
    #!/usr/bin/env bash
    set -eu
    if [ "$1" = "pkcs12" ]; then
      output=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "-out" ]; then output="$2"; shift 2; else shift; fi
      done
      printf 'fixture certificate\\n' >"$output"
      exit 0
    fi
    if [ "$1" = "x509" ] && printf '%s\\n' "$*" | grep -q fingerprint; then
      fingerprint="$(python3 -c 'import os; value=os.environ["FAKE_CERT_SHA1"]; print(":".join(value[index:index+2] for index in range(0,len(value),2)))')"
      printf 'sha1 Fingerprint=%s\\n' "$fingerprint"
      exit 0
    fi
    if [ "$1" = "x509" ]; then printf 'subject=CN=Apple Development: Fixture (ABCDE12345),OU=ABCDE12345,O=Playstead,C=US\\n'; exit 0; fi
    exit 2
    """
)

XCODE_STUB = textwrap.dedent(
    """\
    #!/usr/bin/env bash
    set -eu
    printf '%s\\n' "$@" >"$XCODE_CAPTURE"
    profile_root="${PLAYSTEAD_VIRTUAL_HID_PROFILE_ROOT:-$HOME/Library/MobileDevice/Provisioning Profiles}"
    find "$profile_root" -maxdepth 1 -type f -name '*.mobileprovision' -print >"$PROFILE_FILES_CAPTURE"
    { env | sed -n 's/=.*//p' | grep '^PLAYSTEAD_HID_' || true; find "${RUNNER_TEMP}/playstead-virtual-hid-${GITHUB_RUN_ID}" -maxdepth 1 -type f -exec basename {} \\; | sort; } >"$SIGNING_STATE_CAPTURE"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -resultBundlePath) mkdir -p "$2"; break ;;
      esac
      shift
    done
    """
)

XCRUN_STUB = textwrap.dedent(
    f"""\
    #!/usr/bin/env bash
    set -eu
    printf '%s\\n' '{{"testNodes":[{{"nodeType":"Test Case","nodeIdentifier":"{ENTITLED_TEST_FULL}()","result":"Passed","durationInSeconds":1}}]}}'
    """
)


if __name__ == "__main__":
    unittest.main()
