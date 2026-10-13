#!/usr/bin/env python3
"""Task-scoped read-only relay for the signed public Wolfi APK repository."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import argparse
import hashlib
import os
import tempfile

UPSTREAM = "https://packages.wolfi.dev/os"


class Handler(BaseHTTPRequestHandler):
    def _relay(self, method):
        path = self.path.split("?", 1)[0]
        prefix = f"/{self.server.token}/os/"
        if not path.startswith(prefix) or ".." in Path(path).parts:
            self.send_error(404)
            return
        rel = path.removeprefix(prefix)
        cache_file = Path(self.server.cache_dir) / hashlib.sha256(rel.encode()).hexdigest()
        try:
            if method == "GET" and cache_file.is_file():
                size = cache_file.stat().st_size
                self.send_response(200)
                self.send_header("Content-Length", str(size))
                self.end_headers()
                with cache_file.open("rb") as source:
                    while block := source.read(1024 * 1024):
                        self.wfile.write(block)
                return
            req = Request(UPSTREAM + "/" + rel, method=method,
                          headers={"User-Agent": "playstead-media-decoder-build/1"})
            with urlopen(req, timeout=60) as response:
                self.send_response(response.status)
                for name in ("Content-Type", "ETag", "Last-Modified", "Cache-Control", "Content-Length"):
                    if name in response.headers:
                        self.send_header(name, response.headers[name])
                self.end_headers()
                if method == "HEAD":
                    return
                fd, temporary = tempfile.mkstemp(dir=self.server.cache_dir, prefix=".fetch-")
                try:
                    with os.fdopen(fd, "wb") as target:
                        while block := response.read(1024 * 1024):
                            target.write(block)
                            self.wfile.write(block)
                    os.replace(temporary, cache_file)
                finally:
                    if os.path.exists(temporary):
                        os.unlink(temporary)
        except HTTPError as error:
            self.send_error(error.code)
        except (URLError, TimeoutError, OSError) as error:
            self.send_error(502, str(getattr(error, "reason", error)))

    def do_GET(self):
        self._relay("GET")

    def do_HEAD(self):
        self._relay("HEAD")

    def log_message(self, format, *args):
        print("wolfi-repo-proxy", format % args, flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--port-file")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--token", required=True)
    args = parser.parse_args()
    Path(args.cache_dir).mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    server.cache_dir = args.cache_dir
    server.token = args.token
    if args.port_file:
        Path(args.port_file).write_text(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    main()
