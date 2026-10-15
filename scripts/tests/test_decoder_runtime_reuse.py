"""Exercise same-run decoder transport without starting a daemon or a guest."""
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("decoder_evidence", ROOT / "scripts/ci/media-decoder-evidence.py")
EVIDENCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVIDENCE)


class DecoderRuntimeReuseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.checkout = self.root / "checkout"
        scripts = self.checkout / "scripts/ci"
        scripts.mkdir(parents=True)
        for name in ("import-media-decoder-runtime.sh", "media-decoder-evidence.py", "release-evidence.py"):
            shutil.copyfile(ROOT / "scripts/ci" / name, scripts / name)
        self.script = scripts / "import-media-decoder-runtime.sh"
        self.context = self.checkout / "playstead-server/ops/media-decoder"
        self.generated = self.context / "build/generated"
        (self.generated / "packages").mkdir(parents=True)
        (self.context / "Dockerfile").write_text("FROM scratch\n")
        (self.generated / "SOURCE-PINS.json").write_text('{}\n')
        (self.generated / "packages/decoder-signing.rsa.pub").write_text("public fixture key\n")
        self.artifact = self.root / "playstead-media-decoder-runtime"
        self.artifact.mkdir()
        config = b'{"os":"linux","architecture":"amd64"}'
        self.image_id = "sha256:" + hashlib.sha256(config).hexdigest()
        with tarfile.open(self.artifact / "decoder-image.tar", "w") as archive:
            for name, data in [("config.json", config), ("manifest.json", b'[{"Config":"config.json","Layers":[]}]')]:
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        report = self.root / "report.json"
        report.write_text(json.dumps({
            "Metadata": {"ImageID": self.image_id},
            "Results": [{"Target": "runtime", "Type": "wolfi", "Packages": [{
                "Name": "python-3.15", "Version": "3.15.0-r0", "SrcName": "python-3.15",
                "SrcVersion": "3.15.0-r0", "Licenses": ["PSF-2.0"],
            }], "Vulnerabilities": [], "Licenses": []}],
        }))
        EVIDENCE.create_receipt(report, self.artifact, EVIDENCE.source_digest(self.context), self.image_id)
        shutil.copytree(self.generated, self.artifact / "generated")
        shutil.rmtree(self.generated)
        binaries = self.root / "bin"
        binaries.mkdir()
        self.calls = self.root / "calls"
        docker = binaries / "docker"
        docker.write_text('''#!/bin/sh
printf '%s\n' "$*" >>"$CALL_LOG"
case "$*" in
  "image load --input "*) exit 0 ;;
  "image inspect --format "*) printf '%s\n' "$ACTUAL_IMAGE_ID" ;;
  *) exit 91 ;;
esac
''')
        docker.chmod(0o755)
        self.env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"],
                        CALL_LOG=str(self.calls), ACTUAL_IMAGE_ID=self.image_id,
                        RUNNER_TEMP=str(self.root), GITHUB_ACTIONS="true",
                        RUNNER_OS="Linux", GITHUB_REPOSITORY="szTheory/playstead")

    def run_import(self):
        return subprocess.run(["bash", str(self.script), str(self.artifact)],
                              env=self.env, capture_output=True, text=True)

    def test_matching_archive_report_context_and_actual_image_are_reusable(self):
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.image_id)
        self.assertEqual(EVIDENCE.verify_receipt(
            self.artifact / "decoder-scan-receipt.json", self.artifact / "decoder-trivy.json",
            self.context, self.image_id)["image_id"], self.image_id)
        self.assertIn("image load --input", self.calls.read_text())

    def test_wrong_loaded_image_never_passes(self):
        self.env["ACTUAL_IMAGE_ID"] = "sha256:" + "b" * 64
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_altered_report_rejects_before_docker_load(self):
        with (self.artifact / "decoder-trivy.json").open("a") as report:
            report.write(" ")
        self.assertNotEqual(self.run_import().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_altered_source_rejects_before_docker_load(self):
        (self.context / "Dockerfile").write_text("FROM changed\n")
        self.assertNotEqual(self.run_import().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_symlink_or_private_key_rejects_before_docker_load(self):
        key = self.artifact / "generated/private.rsa"
        key.write_text("fixture-only")
        self.assertNotEqual(self.run_import().returncode, 0)
        key.unlink()
        key.symlink_to(self.artifact / "decoder-trivy.json")
        self.assertNotEqual(self.run_import().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_archive_with_another_config_rejects_before_docker_load(self):
        with tarfile.open(self.artifact / "decoder-image.tar", "w") as archive:
            data = b'[{"Config":"wrong.json"}]'
            entry = tarfile.TarInfo("manifest.json")
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
        self.assertNotEqual(self.run_import().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_local_or_wrong_repository_cannot_import(self):
        for key, value in [("GITHUB_ACTIONS", "false"), ("GITHUB_REPOSITORY", "other/repo")]:
            original = self.env[key]
            self.env[key] = value
            self.assertEqual(self.run_import().returncode, 2)
            self.env[key] = original
        self.assertFalse(self.calls.exists())

    def test_workflow_has_one_producer_and_same_run_consumers(self):
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        jobs = dict(re.findall(r"(?ms)^  ([a-z][a-z0-9-]*):\n(.*?)(?=^  [a-z][a-z0-9-]*:|\Z)", source))
        self.assertIn("Build and scan the isolated media decoder once", jobs["decoder-runtime"])
        self.assertEqual(source.count("name: Preserve the qualified public decoder runtime"), 1)
        for name in ("test", "recovery-fixture", "compose-smoke"):
            self.assertIn("needs: [decoder-runtime]", jobs[name])
            self.assertIn("import-media-decoder-runtime.sh", jobs[name])
            self.assertIn("prepare-media-decoder-image.sh", jobs[name])
            self.assertNotIn("run-id:", jobs[name])
        mac = jobs["mac-verification"]
        self.assertIn("!cancelled() && needs.decoder-runtime.result == 'success'", mac)
        self.assertIn("needs: [test, compose-smoke, decoder-runtime]", mac)
        self.assertNotIn("run-id:", mac)


if __name__ == "__main__":
    unittest.main()
