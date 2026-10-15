"""Actual HTTP regression for the task-scoped signed-repository relay."""
import hashlib
from concurrent.futures import ThreadPoolExecutor
import http.client
import importlib.util
import pathlib
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

# Test imports must not add bytecode to the source-bound Docker context.
sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("wolfi_proxy", ROOT / "playstead-server/ops/media-decoder/build/wolfi_repo_proxy.py")
PROXY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROXY)


class WolfiRepositoryRelayTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.body = b"signed repository index version one"
        self.upstream_requests = []
        self.concurrent_barrier = None
        owner = self

        class Upstream(BaseHTTPRequestHandler):
            def do_GET(self):
                owner.upstream_requests.append(self.path)
                body = owner.body
                if owner.concurrent_barrier is not None:
                    body = f"signed index version {len(owner.upstream_requests)}".encode()
                    owner.concurrent_barrier.wait(timeout=2)
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("ETag", '"vendor-index-identity"')
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        self.proxy = ThreadingHTTPServer(("127.0.0.1", 0), PROXY.Handler)
        self.proxy.cache_dir = self.temporary.name
        self.proxy.token = "task-test-token"
        self.patch = patch.object(PROXY, "UPSTREAM", f"http://127.0.0.1:{self.upstream.server_port}")
        self.patch.start()
        self.threads = []
        for server in (self.upstream, self.proxy):
            thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
            thread.start()
            self.threads.append(thread)

    def tearDown(self):
        for server in (self.proxy, self.upstream):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive())
        self.patch.stop()
        self.temporary.cleanup()

    def request(self, method, path="/task-test-token/os/x86_64/APKINDEX.tar.gz"):
        connection = http.client.HTTPConnection("127.0.0.1", self.proxy.server_port, timeout=2)
        try:
            connection.request(method, path)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_head_then_get_keep_the_same_body_identity_when_upstream_changes(self):
        original = self.body
        head_status, head, empty = self.request("HEAD")
        self.body = b"repository index version two"
        status, get, body = self.request("GET")
        self.assertEqual((head_status, status), (200, 200))
        self.assertEqual(empty, b"")
        self.assertEqual(body, original)
        self.assertEqual(head["ETag"], get["ETag"])
        self.assertEqual(head["Content-Length"], get["Content-Length"])
        self.assertEqual(get["ETag"], '"' + hashlib.sha256(body).hexdigest() + '"')
        self.assertEqual(self.upstream_requests, ["/x86_64/APKINDEX.tar.gz"])

    def test_get_then_cached_head_and_get_preserve_the_identity(self):
        first = self.request("GET")
        head = self.request("HEAD")
        cached = self.request("GET")
        self.assertEqual(first[1]["ETag"], head[1]["ETag"])
        self.assertEqual(first[1]["ETag"], cached[1]["ETag"])
        self.assertEqual(first[2], cached[2])
        self.assertEqual(len(self.upstream_requests), 1)

    def test_legacy_body_cache_has_matching_head_and_get_headers(self):
        cache = pathlib.Path(self.temporary.name) / hashlib.sha256(b"x86_64/APKINDEX.tar.gz").hexdigest()
        cache.write_bytes(b"legacy signed index")
        head = self.request("HEAD")
        get = self.request("GET")
        self.assertEqual(head[1]["ETag"], get[1]["ETag"])
        self.assertEqual(get[2], cache.read_bytes())
        self.assertEqual(self.upstream_requests, [])

    def test_concurrent_cold_requests_publish_one_complete_index_version(self):
        self.concurrent_barrier = threading.Barrier(2)
        with ThreadPoolExecutor(max_workers=2) as pool:
            head_future = pool.submit(self.request, "HEAD")
            get_future = pool.submit(self.request, "GET")
            head = head_future.result(timeout=4)
            get = get_future.result(timeout=4)
        self.assertEqual((head[0], get[0]), (200, 200))
        self.assertEqual(head[1]["ETag"], get[1]["ETag"])
        self.assertEqual(get[1]["ETag"], '"' + hashlib.sha256(get[2]).hexdigest() + '"')
        self.assertEqual(len(self.upstream_requests), 2)

    def test_wrong_token_and_traversal_never_reach_upstream(self):
        for path in ("/other-token/os/x86_64/APKINDEX.tar.gz", "/task-test-token/os/../private"):
            with self.subTest(path=path):
                self.assertEqual(self.request("GET", path)[0], 404)
        self.assertEqual(self.upstream_requests, [])


if __name__ == "__main__":
    unittest.main()
