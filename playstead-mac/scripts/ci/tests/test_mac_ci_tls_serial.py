"""Run-scoped TLS issuance must preserve an existing outer serial counter."""
import pathlib
import stat
import subprocess
import tempfile
import unittest

ISSUER = pathlib.Path(__file__).resolve().parents[1] / "mac-ci-tls.sh"


class MacCiTlsSerialTests(unittest.TestCase):
    def test_dotted_service_path_keeps_serial_under_its_owned_tls_root(self):
        with tempfile.TemporaryDirectory(prefix="playstead-tls-serial-") as temporary:
            outer = pathlib.Path(temporary)
            unrelated = outer / ".srl"
            original = b"0000000000000001\n"
            unrelated.write_bytes(original)
            service = outer / ".build/native/app"
            service.mkdir(parents=True, mode=0o700)
            result = subprocess.run(["/bin/bash", str(ISSUER), "issue", str(service)],
                                    cwd=outer, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, "run-owned TLS issuance failed")
            self.assertEqual(unrelated.read_bytes(), original,
                             "TLS issuance must not advance an outer serial counter")
            serial = service / "tls/ca.srl"
            self.assertTrue(serial.is_file())
            self.assertEqual(stat.S_IMODE(serial.stat().st_mode), 0o600)
            verify = subprocess.run(["openssl", "verify", "-CAfile", str(service / "tls/ca.pem"),
                                     str(service / "tls/server-leaf.pem")], capture_output=True)
            self.assertEqual(verify.returncode, 0, "the scoped issuer must still produce a valid chain")


if __name__ == "__main__":
    unittest.main()
