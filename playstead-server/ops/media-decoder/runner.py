#!/usr/bin/python3
"""Run the isolated decoder without requiring a shell in its runtime image."""

import os
import sys

os.makedirs(os.environ.get("TMPDIR", "/tmp/decoder"), mode=0o700, exist_ok=True)
args = sys.argv[1:]
if not args or args[0] == "serve":
    os.execv("/usr/bin/python3", ["/usr/bin/python3", "/opt/media-decoder/server.py"])
if args[0] == "self-test":
    os.execv("/usr/bin/python3", ["/usr/bin/python3", "/opt/media-decoder/server.py", "--self-test"])
os.execvp(args[0], args)
