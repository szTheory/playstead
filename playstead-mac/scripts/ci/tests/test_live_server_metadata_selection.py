"""Run the shipped metadata fixture against a revision-aware HTTPS endpoint."""
import http.server
import json
import os
import pathlib
import ssl
import subprocess
import tempfile
import threading
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "live-server.sh"
DESCRIPTION = "Synthetic private description survives journal and snapshot reset."


class MetadataSelectionFixtureTests(unittest.TestCase):
    def run_fixture(self, *, conflict=False, mismatched_receipt=False,
                    read_status=200, description_revision=7):
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def respond(self, status, body):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())

            def do_GET(self):
                requests.append(("GET", self.path, None))
                revisions = {"title": 9}
                if description_revision is not None:
                    revisions["description"] = description_revision
                self.respond(read_status, {"asset_set_id": "synthetic-game", "revision": 11,
                                           "field_revisions": revisions})

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                requests.append(("POST", self.path, body))
                expected_revision = 0 if read_status == 404 or description_revision is None else description_revision
                if (body != {"field": "description", "value": DESCRIPTION, "base_revision": expected_revision}
                        or self.headers.get("Authorization") != "Bearer synthetic-test-credential"
                        or not self.headers.get("Idempotency-Key", "").startswith("metadata-journey-")):
                    return self.respond(422, {"type": "invalid_request"})
                if conflict:
                    return self.respond(409, {"type": "metadata_conflict"})
                self.respond(201, {"asset_set_id": "wrong-game" if mismatched_receipt else "synthetic-game",
                                   "description": DESCRIPTION, "revision": 12})

        with tempfile.TemporaryDirectory(prefix="playstead-metadata-contract-") as temporary:
            base = pathlib.Path(temporary)
            profile, server_root = base / "profile", base / "server"
            (profile / "control").mkdir(parents=True)
            tls = server_root / "tls"
            tls.mkdir(parents=True)
            certificate, key = tls / "ca.pem", tls / "key.pem"
            generated = subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1",
                "-keyout", str(key), "-out", str(certificate),
            ], capture_output=True, timeout=15)
            self.assertEqual(generated.returncode, 0, "synthetic TLS setup failed")
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(certificate, key)
            server.socket = context.wrap_socket(server.socket, server_side=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                (profile / "test-credential.json").write_text(json.dumps({
                    "base_url": f"https://127.0.0.1:{server.server_port}",
                    "credential": "synthetic-test-credential",
                }))
                (profile / "control/first-sentinel.json").write_text(json.dumps({
                    "sentinel": {"asset_set_id": "synthetic-game"},
                }))
                marker = server_root / "live-server-failure-stage"
                result = subprocess.run(
                    ["/bin/bash", str(SCRIPT), "metadata-select", str(profile), str(server_root)],
                    env=dict(os.environ, PLAYSTEAD_LIVE_SERVER_STAGE_ROOT=str(server_root),
                             PLAYSTEAD_LIVE_SERVER_STAGE_FILE=str(marker)),
                    capture_output=True, text=True, timeout=20,
                )
                receipt_path = profile / "control/metadata-receipt.json"
                receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
                mode = receipt_path.stat().st_mode & 0o777 if receipt_path.exists() else None
                stage = marker.read_text().strip() if marker.exists() else None
                self.assertNotIn("synthetic-test-credential", result.stdout + result.stderr)
                return result, requests, receipt, mode, stage
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def test_reads_description_revision_before_selecting_and_writes_private_receipt(self):
        result, requests, receipt, mode, stage = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([request[0] for request in requests], ["GET", "POST"])
        self.assertTrue(all(request[1] == "/api/v1/metadata/synthetic-game" for request in requests))
        self.assertEqual(receipt, {"asset_set_id": "synthetic-game", "description": DESCRIPTION, "revision": 12})
        self.assertEqual(mode, 0o600)
        self.assertIsNone(stage)

    def test_conflict_fails_without_a_success_receipt(self):
        result, requests, receipt, _mode, stage = self.run_fixture(conflict=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt, None)
        self.assertEqual(stage, "metadata-selection")
        self.assertEqual(len(requests), 2)

    def test_fresh_selection_uses_zero_only_after_not_found(self):
        result, requests, receipt, _mode, _stage = self.run_fixture(read_status=404)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests[-1][2]["base_revision"], 0)
        self.assertIsNotNone(receipt)

    def test_title_revision_is_not_used_for_an_unedited_description(self):
        result, requests, receipt, _mode, _stage = self.run_fixture(description_revision=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests[-1][2]["base_revision"], 0)
        self.assertIsNotNone(receipt)

    def test_authentication_failure_is_not_treated_as_an_empty_selection(self):
        result, requests, receipt, _mode, stage = self.run_fixture(read_status=401)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([request[0] for request in requests], ["GET"])
        self.assertIsNone(receipt)
        self.assertEqual(stage, "metadata-selection")

    def test_mismatched_response_identity_fails_without_a_success_receipt(self):
        result, requests, receipt, _mode, stage = self.run_fixture(mismatched_receipt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt, None)
        self.assertEqual(stage, "metadata-selection")
        self.assertEqual(len(requests), 2)


if __name__ == "__main__":
    unittest.main()
