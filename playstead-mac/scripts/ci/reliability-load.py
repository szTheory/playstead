#!/usr/bin/env python3
"""Bounded, run-owned load helpers for Phase 06 reliability repetitions.

Only two shapes are supported: scratch-only scheduler/I/O load and four
loopback /healthz probes. This deliberately has no general URL or path mode.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import pathlib
import random
import signal
import ssl
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

MAX_WORKER_BYTES = 64 * 1024 * 1024
SCRATCH_BYTES = 16 * 1024 * 1024
BLOCK_BYTES = 4096
PROBE_INTERVAL_SECONDS = 0.5
STOP = threading.Event()


def source_snapshot(repo_root: str) -> dict[str, str]:
    """Fingerprint the dirty non-planning source snapshot used by a run."""
    root = pathlib.Path(repo_root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError("repository root identity is invalid")
    root = root.resolve(strict=True)
    head = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout.strip()
    if not re_full_commit(head):
        raise ValueError("repository revision is invalid")

    tracked = subprocess.run(
        ["git", "-C", str(root), "diff", "--binary", "HEAD", "--", ".", ":(exclude).planning/**"],
        check=True,
        capture_output=True,
        timeout=30,
    ).stdout
    untracked = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard", "-z", "--", "."],
        check=True,
        capture_output=True,
        timeout=30,
    ).stdout.split(b"\0")

    digest = hashlib.sha256()
    digest.update(tracked)
    for raw in sorted(item for item in untracked if item):
        relative = os.fsdecode(raw)
        if relative == ".planning" or relative.startswith(".planning/"):
            continue
        path = root / relative
        info = path.lstat()
        digest.update(b"\0untracked\0" + raw + b"\0")
        digest.update(f"{stat.S_IMODE(info.st_mode):04o}\0".encode("ascii"))
        if stat.S_ISLNK(info.st_mode):
            digest.update(b"symlink\0" + os.fsencode(os.readlink(path)))
        elif stat.S_ISREG(info.st_mode):
            with path.open("rb") as stream:
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
        else:
            raise ValueError("untracked source entry is not a regular file")

    return {"source_head": head, "source_fingerprint": digest.hexdigest()}


def run_fingerprint(args: argparse.Namespace) -> int:
    print(json.dumps(source_snapshot(args.repo_root), sort_keys=True))
    return 0


def re_full_commit(value: str) -> bool:
    return len(value) == 40 and all(character in "0123456789abcdef" for character in value)


def _private_manifest(path: pathlib.Path, expected_case: str) -> dict[str, object]:
    if path.is_symlink() or not path.is_file() or stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise ValueError("reliability manifest identity or permissions are invalid")
    data = json.loads(path.read_text(encoding="utf-8"))
    common = {
        "schema", "case", "source_head", "source_fingerprint", "expected_runs",
        "completed_runs", "passed_runs", "elapsed_seconds",
    }
    if not isinstance(data, dict) or data.get("schema") != "playstead.reliability-run.v1" or data.get("case") != expected_case:
        raise ValueError("reliability manifest schema or case is invalid")
    if not common.issubset(data):
        raise ValueError("reliability manifest is missing required fields")
    if not re_full_commit(str(data["source_head"])):
        raise ValueError("reliability manifest revision is invalid")
    fingerprint = data["source_fingerprint"]
    if not isinstance(fingerprint, str) or len(fingerprint) != 64 or any(c not in "0123456789abcdef" for c in fingerprint):
        raise ValueError("reliability manifest fingerprint is invalid")
    for key in ("expected_runs", "completed_runs", "passed_runs", "elapsed_seconds"):
        if type(data[key]) is not int:
            raise ValueError("reliability manifest count is invalid")
    if data["expected_runs"] != 20 or data["completed_runs"] != 20 or data["passed_runs"] != 20 or not 0 < data["elapsed_seconds"] <= 1800:
        raise ValueError("reliability manifest does not record a complete passing run")
    if expected_case == "apfs-backup-exclusion":
        required = common | {"assertion_failures", "infrastructure_failures", "load", "worker_cap_bytes"}
        if set(data) != required:
            raise ValueError("APFS reliability manifest schema drifted")
        if any(type(data[key]) is not int or data[key] != 0 for key in ("assertion_failures", "infrastructure_failures")):
            raise ValueError("APFS reliability manifest records a failure")
        if data.get("load") != "scheduler2+io2" or data.get("worker_cap_bytes") != MAX_WORKER_BYTES:
            raise ValueError("APFS reliability manifest does not match the bounded load contract")
    elif expected_case == "setup-wizard-journey":
        required = common | {
            "assertion_failures", "probe_failures", "infrastructure_failures", "probe_count",
            "max_requests_per_second_per_probe", "successful_probe_requests", "browser_build",
        }
        if set(data) != required:
            raise ValueError("setup-wizard reliability manifest schema drifted")
        if any(type(data[key]) is not int or data[key] != 0 for key in ("assertion_failures", "probe_failures", "infrastructure_failures")):
            raise ValueError("setup-wizard reliability manifest records a failure")
        if type(data.get("probe_count")) is not int or data["probe_count"] != 4 or type(data.get("max_requests_per_second_per_probe")) is not int or data["max_requests_per_second_per_probe"] != 2:
            raise ValueError("setup-wizard probe contract drifted")
        requests = data.get("successful_probe_requests")
        if type(requests) is not int or requests < 80:
            raise ValueError("setup-wizard probe evidence is incomplete")
        build = data.get("browser_build")
        if not isinstance(build, str) or len(build.split(".")) != 3 or any(not item.isdigit() for item in build.split(".")):
            raise ValueError("setup-wizard browser identity is invalid")
    return data


def validate_upstream(args: argparse.Namespace) -> int:
    current = source_snapshot(args.repo_root)
    apfs = _private_manifest(pathlib.Path(args.apfs_manifest), "apfs-backup-exclusion")
    setup = _private_manifest(pathlib.Path(args.setup_manifest), "setup-wizard-journey")
    snapshot = (current["source_head"], current["source_fingerprint"])
    if (apfs["source_head"], apfs["source_fingerprint"]) != snapshot or (setup["source_head"], setup["source_fingerprint"]) != snapshot:
        raise ValueError("bounded reliability runs do not share the current source snapshot")
    print(json.dumps({"source_head": snapshot[0], "source_fingerprint": snapshot[1], "apfs": apfs, "setup": setup}, sort_keys=True))
    return 0


def _safe_root(raw: str, owner: str) -> pathlib.Path:
    supplied = pathlib.Path(raw)
    if supplied.is_symlink():
        raise ValueError("run root must not be a symbolic link")
    root = supplied.resolve(strict=True)
    allowed = {
        pathlib.Path(tempfile.gettempdir()).resolve(),
        pathlib.Path("/private/tmp").resolve(),
        pathlib.Path("/tmp").resolve(),
    }
    if not any(root == base or base in root.parents for base in allowed):
        raise ValueError("run root is outside the temporary directory")
    if not root.is_dir() or stat.S_IMODE(root.stat().st_mode) & 0o077:
        raise ValueError("run root is not a regular owned directory")
    marker = root / ".owner"
    if marker.is_symlink() or not marker.is_file() or stat.S_IMODE(marker.stat().st_mode) & 0o077 or marker.read_text(encoding="ascii") != owner:
        raise ValueError("run root ownership marker does not match")
    return root


def _private_directory(path: pathlib.Path) -> None:
    path.mkdir(mode=0o700, parents=False, exist_ok=False)
    if path.is_symlink() or not path.is_dir():
        raise ValueError("worker directory is not a regular directory")


def _create_scratch(path: pathlib.Path, requested_size: int) -> int:
    if requested_size < 1 or requested_size > MAX_WORKER_BYTES:
        raise ValueError("scratch size exceeds the 64 MiB per-worker cap")
    flags = os.O_CREAT | os.O_EXCL | os.O_RDWR
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    try:
        os.ftruncate(fd, requested_size)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size != requested_size:
            raise ValueError("scratch file identity or size changed")
    except BaseException:
        os.close(fd)
        raise
    return fd


def _scratch_worker(root: pathlib.Path, name: str, kind: str) -> None:
    worker_dir = root / name
    _private_directory(worker_dir)
    size = SCRATCH_BYTES if kind == "io" else 1024 * 1024
    fd = _create_scratch(worker_dir / "scratch.bin", size)
    try:
        queue = collections.deque(range(64))
        sequence = 0
        rng = random.Random(name)
        while not STOP.is_set():
            if kind == "scheduler":
                # Exercise bounded task scheduling while mutating only this
                # worker's own small scratch file.
                if not queue:
                    queue.extend(range(64))
                task = queue.popleft()
                payload = (sequence.to_bytes(8, "little") + task.to_bytes(4, "little"))
                os.pwrite(fd, payload, (task * 16) % (size - len(payload)))
                sequence += 1
                if sequence % 64 == 0:
                    os.fsync(fd)
                time.sleep(0.002)
            else:
                offset = rng.randrange(0, size - BLOCK_BYTES + 1, BLOCK_BYTES)
                value = bytes([sequence & 0xFF]) * BLOCK_BYTES
                written = os.pwrite(fd, value, offset)
                if written != BLOCK_BYTES:
                    raise OSError("short write to owned scratch file")
                if sequence % 16 == 0:
                    os.fsync(fd)
                    if os.pread(fd, BLOCK_BYTES, offset) != value:
                        raise OSError("owned scratch readback mismatch")
                sequence += 1
                time.sleep(0.01)
    finally:
        os.close(fd)


def run_scratch(args: argparse.Namespace) -> int:
    root = _safe_root(args.root, args.owner)
    if args.max_bytes != MAX_WORKER_BYTES:
        raise ValueError("the per-worker scratch cap is fixed at 64 MiB")

    workers = [
        threading.Thread(target=_scratch_worker, args=(root, f"scheduler-{i}", "scheduler"), daemon=True)
        for i in range(2)
    ] + [
        threading.Thread(target=_scratch_worker, args=(root, f"io-{i}", "io"), daemon=True)
        for i in range(2)
    ]
    for worker in workers:
        worker.start()
    print("reliability-load-ready scheduler_workers=2 io_workers=2 cap_bytes=67108864", flush=True)
    while not STOP.wait(0.25):
        _safe_root(args.root, args.owner)
        for worker in workers:
            if not worker.is_alive():
                raise RuntimeError("owned scratch worker stopped unexpectedly")
    for worker in workers:
        worker.join(timeout=3)
    if any(worker.is_alive() for worker in workers):
        raise RuntimeError("owned scratch worker did not stop")
    return 0


def _probe_url(raw: str) -> urllib.parse.ParseResult:
    parsed = urllib.parse.urlparse(raw)
    allowed = {
        ("http", "127.0.0.1", 4002, "/healthz"),
        ("https", "127.0.0.1", 4010, "/healthz"),
    }
    if (parsed.scheme, parsed.hostname, parsed.port, parsed.path) not in allowed:
        raise ValueError("probe target is outside the fixed loopback health allowlist")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("probe target contains disallowed URL components")
    return parsed


def run_probes(args: argparse.Namespace) -> int:
    root = _safe_root(args.root, args.owner)
    _probe_url(args.url)
    if args.probes != 4 or args.max_rps != 2:
        raise ValueError("probe shape is fixed at four workers and at most two requests per second each")
    ssl_context = None
    if args.url.startswith("https://"):
        ca_path = pathlib.Path(args.ca_file).resolve(strict=True)
        if ca_path.is_symlink() or not ca_path.is_file() or ca_path.stat().st_size > 16_384:
            raise ValueError("run-owned CA input is not a bounded regular file")
        der = ca_path.read_bytes()
        if not der or len(der) > 16_384:
            raise ValueError("run-owned CA input size is invalid")
        pem = ssl.DER_cert_to_PEM_cert(der)
        pem_path = root / "probe-ca.pem"
        fd = os.open(pem_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w", encoding="ascii") as stream:
            stream.write(pem)
        ssl_context = ssl.create_default_context(cafile=str(pem_path))
    elif args.ca_file:
        raise ValueError("HTTP health probes must not receive a trust anchor")

    lock = threading.Lock()
    counts = [0, 0, 0, 0]
    last_status = [0, 0, 0, 0]
    failures = [0, 0, 0, 0]

    def probe(index: int) -> None:
        next_due = time.monotonic()
        while not STOP.is_set():
            wait = next_due - time.monotonic()
            if wait > 0 and STOP.wait(wait):
                break
            try:
                request = urllib.request.Request(args.url, method="GET", headers={"Accept": "application/json"})
                with urllib.request.urlopen(request, timeout=2, context=ssl_context) as response:
                    status = response.status
                    response.read(4096)
                with lock:
                    counts[index] += 1
                    last_status[index] = status
                    if status != 200:
                        failures[index] += 1
            except Exception:
                with lock:
                    failures[index] += 1
            next_due = max(next_due + PROBE_INTERVAL_SECONDS, time.monotonic())

    workers = [threading.Thread(target=probe, args=(i,), daemon=True) for i in range(4)]
    for worker in workers:
        worker.start()

    ready = root / "probes-ready"
    deadline = time.monotonic() + args.ready_timeout
    while time.monotonic() < deadline and not STOP.is_set():
        with lock:
            if all(count > 0 and last_status[i] == 200 for i, count in enumerate(counts)):
                fd = os.open(ready, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                with os.fdopen(fd, "w", encoding="ascii") as stream:
                    stream.write(args.owner)
                print("reliability-probes-ready probes=4 max_rps_per_probe=2", flush=True)
                break
        time.sleep(0.05)
    else:
        STOP.set()
        raise RuntimeError("four loopback probes did not become ready before the bound")

    while not STOP.wait(0.25):
        _safe_root(args.root, args.owner)

    for worker in workers:
        worker.join(timeout=3)
    if any(worker.is_alive() for worker in workers):
        raise RuntimeError("a loopback probe did not stop")
    report = {
        "schema": "playstead.reliability-probes.v1",
        "probe_count": 4,
        "max_requests_per_second_per_probe": 2,
        "successful_requests": counts,
        "last_status": last_status,
        "failed_requests": failures,
    }
    (root / "probe-report.json").write_text(json.dumps(report, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(root / "probe-report.json", 0o600)
    if any(count == 0 for count in counts) or any(status != 200 for status in last_status) or any(failures):
        return 1
    return 0


def cleanup_command_process_group(pgid: int, args: argparse.Namespace, grace_seconds: float = 5) -> None:
    """Stop the command's process group without escalating across EPERM.

    Xcode can briefly leave a test-manager child in the session after xcodebuild
    exits. Give that group a bounded drain window. If the OS says the caller
    cannot inspect or signal it, keep waiting for it to disappear but never
    send SIGKILL: that denial means ownership is not established.
    """
    permission_denied = False
    args.failure_stage = "signal-command-process-group"
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except PermissionError:
        permission_denied = True

    deadline = time.monotonic() + grace_seconds
    while time.monotonic() < deadline:
        try:
            args.failure_stage = "check-command-process-group"
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return
        except PermissionError:
            permission_denied = True
        time.sleep(0.1)

    if permission_denied:
        args.failure_stage = "check-command-process-group"
        raise PermissionError("command process group ownership could not be verified")

    args.failure_stage = "kill-command-process-group"
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def run_command(args: argparse.Namespace) -> int:
    import subprocess

    args.failure_stage = "validate-command"
    if args.timeout_seconds < 1 or args.timeout_seconds > 1800:
        raise ValueError("command deadline must be between 1 and 1800 seconds")
    log_path = pathlib.Path(args.log_path)
    if log_path.exists() or log_path.is_symlink():
        raise ValueError("private command log already exists")
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    args.failure_stage = "create-private-log"
    log_fd = os.open(log_path, flags, 0o600)
    with os.fdopen(log_fd, "wb") as log:
        args.failure_stage = "launch-command"
        process = subprocess.Popen(args.command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        previous_handlers = {signum: signal.getsignal(signum) for signum in (signal.SIGTERM, signal.SIGINT)}

        def terminate_child(signum: int, _frame: object) -> None:
            STOP.set()
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signum)
                except ProcessLookupError:
                    pass

        for signum in previous_handlers:
            args.failure_stage = "install-signal-handler"
            signal.signal(signum, terminate_child)
        try:
            args.failure_stage = "wait-for-command"
            status = process.wait(timeout=args.timeout_seconds)
            return status
        except subprocess.TimeoutExpired:
            args.failure_stage = "terminate-timed-out-command"
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                args.failure_stage = "kill-timed-out-command"
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            return 124
        finally:
            # The command itself may have exited while a browser or other
            # owned child remains in its new session. Reap that exact process
            # group before this run advances to another iteration.
            cleanup_command_process_group(process.pid, args)
            for signum, handler in previous_handlers.items():
                args.failure_stage = "restore-signal-handler"
                signal.signal(signum, handler)


def _stop(_signum: int, _frame: object) -> None:
    STOP.set()


def main() -> int:
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="mode", required=True)
    scratch = commands.add_parser("scratch")
    scratch.add_argument("--root", required=True)
    scratch.add_argument("--owner", required=True)
    scratch.add_argument("--max-bytes", type=int, default=MAX_WORKER_BYTES)
    scratch.set_defaults(function=run_scratch)
    probes = commands.add_parser("probes")
    probes.add_argument("--root", required=True)
    probes.add_argument("--owner", required=True)
    probes.add_argument("--url", required=True)
    probes.add_argument("--ca-file")
    probes.add_argument("--probes", type=int, default=4)
    probes.add_argument("--max-rps", type=int, default=2)
    probes.add_argument("--ready-timeout", type=int, default=20)
    probes.set_defaults(function=run_probes)
    command = commands.add_parser("command")
    command.add_argument("--timeout-seconds", type=int, required=True)
    command.add_argument("--log-path", required=True)
    command.add_argument("command", nargs=argparse.REMAINDER)
    command.set_defaults(function=run_command)
    fingerprint = commands.add_parser("fingerprint")
    fingerprint.add_argument("--repo-root", required=True)
    fingerprint.set_defaults(function=run_fingerprint)
    upstream = commands.add_parser("validate-upstream")
    upstream.add_argument("--repo-root", required=True)
    upstream.add_argument("--apfs-manifest", required=True)
    upstream.add_argument("--setup-manifest", required=True)
    upstream.set_defaults(function=validate_upstream)
    args = parser.parse_args()
    if args.mode == "command" and args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if args.mode == "command" and not args.command:
        parser.error("command mode requires a command after --")
    try:
        return args.function(args)
    except Exception as error:
        # Keep local diagnostics bounded and private; never print an exception
        # string that may contain a path, URL, or test data. The operation
        # label and exception class are fixed, local diagnostic dimensions.
        stage = getattr(args, "failure_stage", "operation")
        print(
            f"reliability-load-error kind=ownership-or-worker stage={stage} exception={type(error).__name__}",
            file=sys.stderr,
        )
        return 77


if __name__ == "__main__":
    raise SystemExit(main())
