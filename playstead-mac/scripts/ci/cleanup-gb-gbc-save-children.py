#!/usr/bin/env python3
"""Close only the pinned mGBA child launched with one private tracer profile."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import re
import signal
import shlex
import subprocess
import sys
import time
from pathlib import Path
from dataclasses import dataclass

PINNED_SHA256 = "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640"
PROC_PIDPATHINFO_MAXSIZE = 4096


@dataclass(frozen=True)
class ProcessRow:
    pid: int
    started: str
    command: str


def pid_path(pid: int) -> str | None:
    buffer = ctypes.create_string_buffer(PROC_PIDPATHINFO_MAXSIZE)
    proc_pidpath = ctypes.CDLL(None).proc_pidpath
    proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    proc_pidpath.restype = ctypes.c_int
    if proc_pidpath(pid, buffer, PROC_PIDPATHINFO_MAXSIZE) <= 0:
        return None
    return os.fsdecode(buffer.value)


def process_rows() -> list[ProcessRow]:
    output = subprocess.run(["/bin/ps", "-axo", "pid=,lstart=,command="], check=True, text=True, capture_output=True).stdout
    rows = []
    for line in output.splitlines():
        fields = line.strip().split(None, 6)
        if len(fields) == 7 and fields[0].isdigit():
            rows.append(ProcessRow(int(fields[0]), " ".join(fields[1:6]), fields[6]))
    return rows


def is_exact_launch(command: str, executable: Path, profile: Path) -> bool:
    arguments = command_arguments(command, executable)
    if arguments is None:
        return False
    if len(arguments) != 3 or arguments[0] != "-C" or not arguments[1].startswith("savegamePath="):
        return False
    save_path = Path(arguments[1].removeprefix("savegamePath=")).resolve(strict=False)
    rom_path = Path(arguments[2]).resolve(strict=False)
    profile_path = profile.resolve(strict=False)
    try:
        save_parts = save_path.relative_to(profile_path).parts
        rom_parts = rom_path.relative_to(profile_path).parts
    except ValueError:
        return False
    return (len(save_parts) == 2 and save_parts[0] == "saves"
            and re.fullmatch(r"[A-Za-z0-9_-]+", save_parts[1]) is not None
            and len(rom_parts) == 3 and rom_parts[0] == "launch"
            and rom_parts[1] == save_parts[1]
            and rom_parts[2].lower().endswith((".gb", ".gbc", ".gba")))


def command_arguments(command: str, executable: Path) -> list[str] | None:
    prefix = str(executable) + " "
    if not command.startswith(prefix):
        return None
    try:
        return shlex.split(command[len(prefix):])
    except ValueError:
        return None


def resolve_profile(path: str | Path) -> Path:
    profile = Path(path).resolve(strict=False)
    if not profile.is_dir():
        raise ValueError("refusing child cleanup: private profile directory is missing")
    return profile


def matching(rows: list[ProcessRow], executable: Path, profile: Path) -> list[ProcessRow]:
    expected_path = str(executable)
    return [row for row in rows if row.pid != os.getpid() and pid_path(row.pid) == expected_path
            and is_exact_launch(row.command, executable, profile)]


def cleanup_children(executable: Path, profile: Path, *, rows_provider=process_rows,
                     signal_sender=os.kill, sleeper=time.sleep, monotonic=time.monotonic) -> list[dict[str, object]]:
    results = []
    for target in matching(rows_provider(), executable, profile):
        pid = target.pid

        def identity_state() -> str:
            current = next((row for row in rows_provider() if row.pid == pid), None)
            if current is None:
                return "absent"
            if current.started != target.started:
                return "changed"
            current_path = pid_path(pid)
            if current_path is None:
                # proc_pidpath can lose a race with process exit after ps
                # captured the row. Recheck the PID before treating it as an
                # identity change; a reused PID or changed executable remains
                # fail-closed.
                latest = next((row for row in rows_provider() if row.pid == pid), None)
                if latest is None:
                    return "absent"
                if latest.started != target.started:
                    return "changed"
                return "changed"
            if current_path != str(executable) or not is_exact_launch(current.command, executable, profile):
                return "changed"
            return "same"

        current = next((row for row in rows_provider() if row.pid == pid), None)
        if current is None:
            results.append({"pid": pid, "path": str(executable), "started": target.started, "closed": True})
            continue
        if current.started != target.started or identity_state() != "same":
            results.append({"pid": pid, "path": str(executable), "started": target.started,
                            "closed": False, "reason": "identity_changed_before_term"})
            continue
        signal_sender(pid, signal.SIGTERM)
        deadline = monotonic() + 5
        state = identity_state()
        while monotonic() < deadline and state == "same":
            sleeper(0.1)
            state = identity_state()
        if state == "changed":
            results.append({"pid": pid, "path": str(executable), "started": target.started,
                            "closed": False, "reason": "identity_changed_before_kill"})
            continue
        if state == "same":
            if identity_state() != "same":
                results.append({"pid": pid, "path": str(executable), "started": target.started,
                                "closed": False, "reason": "identity_changed_before_kill"})
                continue
            signal_sender(pid, signal.SIGKILL)
            deadline = monotonic() + 2
            state = identity_state()
            while monotonic() < deadline and state == "same":
                sleeper(0.1)
                state = identity_state()
        closed = state == "absent"
        results.append({"pid": pid, "path": str(executable), "started": target.started, "closed": closed,
                        **({"reason": "identity_changed_after_signal"} if state == "changed" else {})})
    return results


def stale_candidates(rows: list[ProcessRow], executable: Path) -> list[int]:
    expected_path = str(executable)
    candidates = []
    run_root_pattern = re.compile(r"playstead-gb-save-e2e\.[A-Za-z0-9]{6}\Z")
    fixture_names = {"gb-mbc1-8k", "gbc-mbc5-32k", "gbc-mbc3-rtc", "aerevenadvance"}
    for row in rows:
        if pid_path(row.pid) != expected_path or not row.command.startswith(expected_path + " "):
            continue
        tokens = command_arguments(row.command, executable)
        if tokens is None or len(tokens) != 3 or not tokens[1].startswith("savegamePath="):
            continue
        save_path = Path(tokens[1].removeprefix("savegamePath=")).resolve(strict=False)
        profile = save_path.parent.parent
        task_root = profile.parent.parent
        if profile.name in {"source-profile", "target-profile"} and profile.parent.name in fixture_names \
                and run_root_pattern.fullmatch(task_root.name) \
                and is_exact_launch(row.command, executable, profile):
            candidates.append(row.pid)
    return candidates


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", required=True)
    parser.add_argument("--profile-root", required=True)
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args()
    executable = Path(args.executable).resolve(strict=False)
    try:
        profile = resolve_profile(args.profile_root)
    except ValueError as error:
        raise SystemExit(str(error))
    if not executable.exists():
        # A clean runner can have neither an installed adapter nor any child.
        # An unlinked running executable is unsafe: require exact path absence
        # in the process inventory before treating this as an empty cleanup.
        if any(pid_path(row.pid) == str(executable) for row in process_rows()):
            raise SystemExit("refusing child cleanup: missing executable has a live process")
        result = ({"kind": "preflight", "stale_children": []} if args.preflight else
                  {"kind": "cleanup", "profile_root": str(profile), "children": []})
        print(json.dumps(result, sort_keys=True))
        return 0
    if hashlib.sha256(executable.read_bytes()).hexdigest() != PINNED_SHA256:
        raise SystemExit("refusing child cleanup: managed mGBA executable digest changed")
    rows = process_rows()
    if args.preflight:
        stale = stale_candidates(rows, executable)
        print(json.dumps({"kind": "preflight", "stale_children": stale}))
        return 1 if stale else 0

    results = cleanup_children(executable, profile)
    print(json.dumps({"kind": "cleanup", "profile_root": str(profile), "children": results}, sort_keys=True))
    return 0 if all(result["closed"] for result in results) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"gb-gbc cleanup failed: {error}", file=sys.stderr)
        raise SystemExit(2)
