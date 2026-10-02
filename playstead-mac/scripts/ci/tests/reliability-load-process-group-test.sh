#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 - "$SCRIPT_DIR/../reliability-load.py" <<'PY'
import importlib.util
import pathlib
import signal
import sys
from types import SimpleNamespace
from unittest import mock

source = pathlib.Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("reliability_load", source)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def check(condition, message):
    if not condition:
        raise SystemExit(message)


pgid = 4242
args = SimpleNamespace(failure_stage="")
with mock.patch.object(module.os, "killpg", side_effect=[None, PermissionError(), ProcessLookupError()]) as killpg, \
     mock.patch.object(module.time, "monotonic", side_effect=[0.0, 0.1, 0.2]), \
     mock.patch.object(module.time, "sleep"):
    module.cleanup_command_process_group(pgid, args, grace_seconds=1)
check(killpg.call_args_list == [
    mock.call(pgid, signal.SIGTERM), mock.call(pgid, 0), mock.call(pgid, 0),
], "transient EPERM did not drain without escalation")

args = SimpleNamespace(failure_stage="")
with mock.patch.object(module.os, "killpg", side_effect=[None, PermissionError()]) as killpg, \
     mock.patch.object(module.time, "monotonic", side_effect=[0.0, 0.1, 1.0]), \
     mock.patch.object(module.time, "sleep"):
    try:
        module.cleanup_command_process_group(pgid, args, grace_seconds=1)
    except PermissionError:
        pass
    else:
        raise SystemExit("persistent EPERM was accepted")
check(killpg.call_args_list == [mock.call(pgid, signal.SIGTERM), mock.call(pgid, 0)],
      "persistent EPERM escalated to SIGKILL")
check(args.failure_stage == "check-command-process-group", "persistent EPERM diagnostic stage drifted")

args = SimpleNamespace(failure_stage="")
with mock.patch.object(module.os, "killpg", side_effect=[None, None]) as killpg, \
     mock.patch.object(module.time, "monotonic", return_value=0.0):
    module.cleanup_command_process_group(pgid, args, grace_seconds=0)
check(killpg.call_args_list == [
    mock.call(pgid, signal.SIGTERM), mock.call(pgid, signal.SIGKILL),
], "owned process group did not retain bounded SIGKILL fallback")

print("reliability process-group cleanup: 3 cases passed")
PY
