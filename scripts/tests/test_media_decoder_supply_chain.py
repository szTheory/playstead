import importlib.util
import json
import pathlib
import shutil
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("media_decoder_evidence", ROOT / "scripts/ci/media-decoder-evidence.py")
EVIDENCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVIDENCE)


class DecoderSupplyChainTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.context = self.root / "context"
        self.context.mkdir()
        (self.context / "Dockerfile").write_text("FROM debian@sha256:base\n")
        self.image_id = "sha256:" + "a" * 64
        self.source_sha = EVIDENCE.source_digest(self.context)
        self.report_path = self.root / "trivy.json"
        self.report = {
            "Metadata": {"ImageID": self.image_id},
            "Results": [{"Target": "runtime OS", "Type": "wolfi", "Packages": [
                {"Name": "python-3.15", "Version": "3.15.0-r0", "SrcName": "python-3.15", "SrcVersion": "3.15.0-r0", "Licenses": ["PSF-2.0"]},
            ], "Vulnerabilities": [], "Licenses": []}],
        }
        self.report_path.write_text(json.dumps(self.report))

    def tearDown(self):
        self.temp.cleanup()

    def test_receipt_binds_policy_report_source_and_immutable_image(self):
        out = self.root / "evidence"
        receipt = EVIDENCE.create_receipt(self.report_path, out, self.source_sha, self.image_id)
        self.assertEqual(self.image_id, receipt["image_id"])
        self.assertEqual("passed", receipt["scan"]["status"])
        self.assertEqual(1, receipt["scan"]["runtime_packages"])
        self.assertEqual(self.image_id, EVIDENCE.verify_receipt(
            out / "decoder-scan-receipt.json", out / "decoder-trivy.json", self.context, self.image_id
        )["image_id"])

    def test_receipt_rejects_changed_source_and_actual_image(self):
        out = self.root / "evidence"
        EVIDENCE.create_receipt(self.report_path, out, self.source_sha, self.image_id)
        with self.assertRaisesRegex(ValueError, "source does not match"):
            (self.context / "Dockerfile").write_text("FROM debian@sha256:changed\n")
            EVIDENCE.verify_receipt(out / "decoder-scan-receipt.json", out / "decoder-trivy.json", self.context, self.image_id)
        (self.context / "Dockerfile").write_text("FROM debian@sha256:base\n")
        with self.assertRaisesRegex(ValueError, "image ID does not match"):
            EVIDENCE.verify_receipt(out / "decoder-scan-receipt.json", out / "decoder-trivy.json", self.context, "sha256:" + "b" * 64)

    def test_failed_or_empty_scan_cannot_create_receipt(self):
        self.report["Results"][0]["Vulnerabilities"] = [{"Severity": "CRITICAL", "PkgName": "libvips", "InstalledVersion": "1", "VulnerabilityID": "CVE-2099-0001"}]
        self.report_path.write_text(json.dumps(self.report))
        failed_dir = self.root / "failed"
        with self.assertRaisesRegex(ValueError, "failed policy"):
            EVIDENCE.create_receipt(self.report_path, failed_dir, self.source_sha, self.image_id)
        self.assertTrue((failed_dir / "decoder-scan-result.json").is_file())
        self.assertFalse((failed_dir / "decoder-scan-receipt.json").exists())
        self.report["Results"] = []
        self.report_path.write_text(json.dumps(self.report))
        with self.assertRaisesRegex(ValueError, "zero targets"):
            EVIDENCE.create_receipt(self.report_path, self.root / "empty", self.source_sha, self.image_id)

    def test_missing_runtime_inventory_cannot_create_receipt(self):
        self.report["Results"][0]["Packages"] = []
        self.report_path.write_text(json.dumps(self.report))
        with self.assertRaisesRegex(ValueError, "no versioned runtime package inventory with source and license identities"):
            EVIDENCE.create_receipt(self.report_path, self.root / "inventory-empty", self.source_sha, self.image_id)

    def test_runtime_package_without_source_or_license_evidence_cannot_create_receipt(self):
        self.report["Results"][0]["Packages"][0].pop("SrcName")
        self.report_path.write_text(json.dumps(self.report))
        with self.assertRaisesRegex(ValueError, "no versioned runtime package inventory with source and license identities"):
            EVIDENCE.create_receipt(self.report_path, self.root / "inventory-source-missing", self.source_sha, self.image_id)

    def test_receipt_rejects_tampered_scan_report(self):
        out = self.root / "evidence"
        EVIDENCE.create_receipt(self.report_path, out, self.source_sha, self.image_id)
        (out / "decoder-trivy.json").write_text("{}\n")
        with self.assertRaisesRegex(ValueError, "does not match"):
            EVIDENCE.verify_receipt(out / "decoder-scan-receipt.json", out / "decoder-trivy.json", self.context, self.image_id)

    def test_success_cleanup_keeps_generated_image_inputs_for_receipt_reuse(self):
        generated = self.context / "build/generated/packages"
        generated.mkdir(parents=True)
        (generated / "runtime.apk").write_bytes(b"signed runtime artifact")
        transient_cache = self.context / ".build"
        transient_cache.mkdir()
        (transient_cache / "cache.bin").write_bytes(b"task-local build cache")
        (self.context / ".dockerignore").write_text(".build\n")
        source_sha = EVIDENCE.source_digest(self.context)
        out = self.root / "reuse"
        EVIDENCE.create_receipt(self.report_path, out, source_sha, self.image_id)

        supply_chain = (ROOT / "scripts/ci/media-decoder-supply-chain.sh").read_text()
        cleanup = supply_chain.split("cleanup() {", 1)[1].split("\n}\ntrap cleanup", 1)[0]
        self.assertRegex(cleanup, r'if \[ "\$SCAN_PASSED" -ne 1 \]; then[\s\S]*?rm -rf "\$GENERATED_CONTEXT"')
        shutil.rmtree(transient_cache)
        self.assertEqual(self.image_id, EVIDENCE.verify_receipt(
            out / "decoder-scan-receipt.json", out / "decoder-trivy.json", self.context, self.image_id
        )["image_id"])

    def test_scanner_reads_only_the_exported_selected_image(self):
        source = (ROOT / "scripts/ci/media-decoder-supply-chain.sh").read_text()
        self.assertNotIn("/var/run/docker.sock", source)
        self.assertIn('docker image save --output "$RAW_DIR/decoder-image.tar" "$IMAGE_ID"', source)
        self.assertIn("--input /raw/decoder-image.tar", source)
        self.assertNotIn('-v "$REPO_ROOT:/work', source)

    def test_production_compose_requires_verified_immutable_image_reference(self):
        compose = (ROOT / "playstead-server/docker-compose.yml").read_text()
        decoder_service = compose.split("  media-decoder:\n", 1)[1].split("\n  caddy:", 1)[0]
        self.assertIn("image: ${PLAYSTEAD_MEDIA_DECODER_IMAGE:?", decoder_service)
        self.assertNotIn("build:", decoder_service)
        self.assertIn("network_mode: none", decoder_service)
        self.assertIn("mem_limit: 512m", decoder_service)

    def test_ci_prepares_decoder_before_each_consuming_linux_lane(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        test_job = workflow.split("  test:\n", 1)[1].split("\n  mac-verification:", 1)[0]
        recovery_job = workflow.split("  recovery-fixture:\n", 1)[1].split("\n  compose-smoke:", 1)[0]
        for lane, preparation, consumer in (
            (test_job, "Prepare qualified decoder before packaged parser tests", "Phase 04.7 metadata protocol and exact ExUnit guard"),
            (recovery_job, "Prepare qualified decoder for the isolated restore target", "Run isolated restore fixture"),
        ):
            self.assertGreaterEqual(lane.find(preparation), 0)
            self.assertLess(lane.find(preparation), lane.find(consumer))
            setup = lane.split(preparation, 1)[1].split(consumer, 1)[0]
            self.assertIn("prepare-media-decoder-image.sh", setup)
            self.assertIn('>> "$GITHUB_ENV"', setup)
            self.assertIn("PLAYSTEAD_MEDIA_DECODER_EVIDENCE_DIR", setup)
            self.assertIn("PLAYSTEAD_MEDIA_DECODER_IMAGE", setup)

    def test_supported_compose_paths_use_receipt_validator(self):
        smoke = (ROOT / "playstead-server/scripts/compose-smoke.sh").read_text()
        deploy = (ROOT / "playstead-server/scripts/verified-compose.sh").read_text()
        adopter = (ROOT / "playstead-server/scripts/first-adopter-compose.sh").read_text()
        self.assertIn("prepare-media-decoder-image.sh", smoke)
        self.assertIn("prepare-media-decoder-image.sh", deploy)
        self.assertIn("prepare-media-decoder-image.sh", adopter)

    def test_native_runner_requires_scanned_immutable_image_without_artifact_override(self):
        runner = (ROOT / "playstead-mac/scripts/ci/run-mac-verification.sh").read_text()
        native = runner.split("start_native_media_decoder() {", 1)[1].split("\ncleanup_native_services()", 1)[0]
        self.assertIn("prepare-media-decoder-image.sh", native)
        self.assertIn("^sha256:[0-9a-f]{64}$", native)
        self.assertNotIn("ops/media-decoder/Dockerfile", native)
        self.assertNotIn("-v \"$REPO_ROOT/playstead-server/ops/media-decoder:/", native)
        self.assertNotIn("PLAYSTEAD_MEDIA_DECODER_IMAGE", native)


if __name__ == "__main__":
    unittest.main()
