"""Private continuation orchestration; only reduced receipts leave this module.

The operator's adapter owns its adjacent private fixture mapping and replay/oracle
payload. The repository supplies a fresh working directory and one action token.
Qualification and lifecycle records are attestations of that trusted local adapter;
network containment is independently checked by this parent.
"""
import errno
import json
import os
from pathlib import Path
import platform
import selectors
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import uuid

PROTOCOL = "local-continuation-adapter-v1"
ACTIONS = ("qualify", "initial-run", "continue")
CLEAN_ENV = {"PATH": "/usr/bin:/bin"}
SCRIPT_DIR = Path(__file__).resolve().parent


class Refused(Exception):
    pass


def require(condition):
    if not condition:
        raise Refused()


def opaque(value):
    try:
        require(isinstance(value, str) and str(uuid.UUID(value)) == value)
        require(uuid.UUID(value).version == 4)
    except (ValueError, AttributeError, TypeError):
        raise Refused() from None
    return value


def exact(data, keys):
    require(isinstance(data, dict) and set(data) == set(keys))


def decode(raw):
    require(isinstance(raw, bytes) and 0 < len(raw) <= 65536)

    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result)
            result[key] = value
        return result

    def nonfinite(_value):
        raise Refused()

    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=nonfinite)
    except (ValueError, UnicodeError, RecursionError):
        raise Refused() from None


def local_file(value, *, private=False, executable=False):
    require(isinstance(value, (str, Path)) and bool(str(value)))
    path = Path(value)
    require(path.is_absolute() and path.resolve(strict=True) == path)
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid())
    if private:
        require(stat.S_IMODE(info.st_mode) == 0o600 and 0 < info.st_size <= 65536)
    if executable:
        require(os.access(path, os.X_OK) and not (info.st_mode & 0o022))
    return path


def strict_json(value):
    path = local_file(value, private=True)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid())
        require(stat.S_IMODE(info.st_mode) == 0o600 and 0 < info.st_size <= 65536)
        return decode(stream.read(65537))


def validate_contract(data):
    exact(data, ("schema", "contract_id", "fixture_id", "adapter_protocol",
                 "same_host_required", "network_required", "required_actions", "oracle_requirement"))
    require(data["schema"] == "local-continuation-contract-v1")
    opaque(data["contract_id"])
    opaque(data["fixture_id"])
    require(data["adapter_protocol"] == PROTOCOL and data["same_host_required"] is True)
    require(data["network_required"] == "enforced-deny")
    require(data["required_actions"] == list(ACTIONS))
    require(data["oracle_requirement"] == "repeatable-visible-state")
    return data


def validate_receipt(data):
    exact(data, ("schema", "run_id", "lane", "stage", "outcome"))
    require(data["schema"] == "playstead.recovery-e2e-local.v1")
    opaque(data["run_id"])
    require(data["lane"] == "same_host_restored_target")
    require(data["stage"] == "complete" and data["outcome"] == "passed")


def validate_qualification(data, contract_id):
    exact(data, ("schema", "contract_id", "adapter_protocol", "outcome", "capabilities"))
    require(data["schema"] == "local-continuation-qualification-v1")
    require(data["contract_id"] == contract_id and data["adapter_protocol"] == PROTOCOL)
    require(data["outcome"] == "qualified")
    capabilities = data["capabilities"]
    flags = ("initial_run", "safe_exit", "fresh_process", "continue", "repeatable_visible_oracle", "oracle_agreement")
    exact(capabilities, (*flags, "repeat_count"))
    require(all(capabilities[key] is True for key in flags))
    require(type(capabilities["repeat_count"]) is int and 2 <= capabilities["repeat_count"] <= 1000)


class LifecycleFailure(Refused):
    def __init__(self, stage):
        self.stage = stage


def validate_action(data, contract_id, action):
    require(action in ("initial-run", "continue"))
    common = ("schema", "contract_id", "adapter_protocol", "outcome", "child_id")
    flags = ("save_transition", "safe_exit") if action == "initial-run" else (
        "fresh_process", "continue_complete", "oracle_agreement", "repeat_count")
    exact(data, (*common, *flags))
    require(data["schema"] == "local-continuation-action-v1")
    require(data["contract_id"] == contract_id and data["adapter_protocol"] == PROTOCOL)
    require(data["outcome"] == "passed")
    child_id = opaque(data["child_id"])
    checks = (("save_transition", "initial-save"), ("safe_exit", "safe-exit")) if action == "initial-run" else (
        ("fresh_process", "fresh-launch"), ("continue_complete", "continue"), ("oracle_agreement", "oracle"))
    for field, stage in checks:
        if data[field] is not True:
            raise LifecycleFailure(stage)
    if action == "continue" and not (type(data["repeat_count"]) is int and 2 <= data["repeat_count"] <= 1000):
        raise LifecycleFailure("oracle")
    return child_id


def bounded_run(command, *, timeout, cwd=None):
    """Keep raw child output in bounded memory; reap our entire process group."""
    child = subprocess.Popen(command, cwd=cwd, env=CLEAN_ENV,
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    output = bytearray()
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    try:
        while child.poll() is None or selector.get_map():
            require(time.monotonic() < deadline)
            for key, _event in selector.select(0.05):
                chunk = os.read(key.fd, 4096)
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    output.extend(chunk)
                    require(len(output) <= 65536)
        # A returned wrapper with a surviving same-group emulator is stale.
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise Refused()
        return child.returncode, bytes(output)
    finally:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait(timeout=3)
        selector.close()
        child.stdout.close()


def macos_exec_allowlist(adapter, frontends):
    """Return only the Python runtime chain and validated local executable paths."""
    candidates = {Path("/usr/bin/python3"), Path(sys.executable)}
    runtime = Path(sys.executable).resolve(strict=True)
    candidates.add(runtime)
    # Apple's /usr/bin/python3 shim and Xcode's framework Python launcher use
    # a short, fixed chain of executables. Add its adjacent Python.app binary
    # when that layout exists; never allow a general process-exec wildcard.
    if runtime.parent.name == "bin":
        launcher = runtime.parent.parent / "Resources/Python.app/Contents/MacOS/Python"
        if launcher.exists():
            candidates.add(launcher.resolve(strict=True))
    candidates.add(adapter)
    candidates.update(frontends)
    paths = []
    for path in sorted(candidates, key=str):
        require(path.is_absolute())
        info = path.stat()
        require(stat.S_ISREG(info.st_mode) and os.access(path, os.X_OK))
        require(not (stat.S_IMODE(info.st_mode) & 0o022))
        require(all(character.isalnum() or character in "/._-@" for character in str(path)))
        paths.append(path)
    return paths


class IsolationRunner:
    def __init__(self, selector):
        self.selector = selector
        if selector == "macos-seatbelt-v1":
            require(platform.system() == "Darwin" and os.access("/usr/bin/sandbox-exec", os.X_OK))
            self.boundary = ["/usr/bin/sandbox-exec", "-p", "(version 1) (allow default) (deny network*)"]
        elif selector == "linux-bwrap-v1":
            require(platform.system() == "Linux" and os.access("/usr/bin/bwrap", os.X_OK))
            self.boundary = ["/usr/bin/bwrap", "--unshare-net", "--unshare-pid", "--die-with-parent",
                             "--new-session", "--ro-bind", "/", "/", "--proc", "/proc", "--dev", "/dev"]
        else:
            raise Refused()
        require(os.access("/usr/bin/python3", os.X_OK))

    def probe(self):
        # A reachable parent-owned listener distinguishes containment from
        # ordinary offline state. Only fixed platform-specific denial exits pass.
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(2)
            listener.settimeout(0.25)
            port = listener.getsockname()[1]
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                accepted, _address = listener.accept()
                accepted.close()
            denied = [errno.EPERM, errno.EACCES]
            if self.selector == "linux-bwrap-v1":
                denied.extend((errno.ENETUNREACH, errno.EHOSTUNREACH, errno.ECONNREFUSED))
            code = ("import socket,sys\ntry:\n s=socket.socket(); s.settimeout(1); "
                    "s.connect(('127.0.0.1',int(sys.argv[1])))\n"
                    "except OSError as e:\n sys.exit(77 if e.errno in " + repr(denied) + " else 3)\n"
                    "sys.exit(2)\n")
            status, output = bounded_run(self.boundary + ["/usr/bin/python3", "-c", code, str(port)], timeout=5)
            require(status == 77 and not output)
            try:
                accepted, _address = listener.accept()
            except socket.timeout:
                return
            accepted.close()
            raise Refused()

    def run(self, action, adapter, root):
        require(action in ACTIONS)
        self.probe()  # No stand-alone action can bypass the parent probe.
        adapter = local_file(adapter, executable=True)
        root = Path(root)
        require(root.is_absolute() and root.resolve(strict=True) == root)
        info = root.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid())
        require(stat.S_IMODE(info.st_mode) == 0o700 and root.name.startswith("playstead-continuation."))
        if self.selector == "macos-seatbelt-v1":
            profile = ('(version 1) (allow default) (deny network*) (deny file-write*) '
                       '(allow file-write* (subpath (param "OWNED_ROOT"))) '
                       '(deny process-exec) (allow process-fork)')
            boundary = ["/usr/bin/sandbox-exec", "-D", "OWNED_ROOT=" + str(root)]
            frontends = []
            for name in ("continuation-libretro-frontend", "continuation-fixture-libretro-frontend"):
                candidate = adapter.parent / name
                if not (candidate.exists() or candidate.is_symlink()):
                    continue
                frontend = local_file(candidate, executable=True)
                directory_info = frontend.parent.lstat()
                require(stat.S_ISDIR(directory_info.st_mode) and directory_info.st_uid == os.getuid())
                require(not (stat.S_IMODE(directory_info.st_mode) & 0o022))
                frontends.append(frontend)
            for executable in macos_exec_allowlist(adapter, frontends):
                profile += ' (allow process-exec (literal "' + str(executable) + '"))'
            boundary.extend(("-p", profile))
        else:
            boundary = self.boundary + ["--bind", str(root), str(root)]
        status, output = bounded_run(boundary + [str(adapter), action], timeout=120, cwd=root)
        require(status == 0)
        return output


def verify_save_root(root, *, populated):
    save = root / "persistent-save"
    info = save.lstat()
    require(stat.S_ISDIR(info.st_mode) and save.resolve(strict=True) == save)
    require(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
    found = False
    for index, member in enumerate(save.rglob("*")):
        require(index < 10000)
        attributes = member.lstat()
        require(not stat.S_ISLNK(attributes.st_mode) and attributes.st_uid == os.getuid())
        require(stat.S_ISDIR(attributes.st_mode) or stat.S_ISREG(attributes.st_mode))
        if stat.S_ISREG(attributes.st_mode) and attributes.st_size > 0:
            found = True
    require(found if populated else not any(save.iterdir()))


def execute(env, *, qualify_only=False):
    """Return reduced stage/outcome/status only. Never return private inputs."""
    stage, accessed, root = "preflight", False, None
    try:
        runner = IsolationRunner(env.get("PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM", ""))
        contract = validate_contract(strict_json(env.get("PLAYSTEAD_CONTINUATION_CONTRACT", "")))
        validate_receipt(strict_json(env.get("PLAYSTEAD_RECOVERY_E2E_RECEIPT", "")))
        runner.probe()
        adapter = local_file(env.get("PLAYSTEAD_CONTINUATION_ADAPTER", ""), executable=True)
        root = Path(tempfile.mkdtemp(prefix="playstead-continuation.")).resolve()
        root.chmod(0o700)
        stage = "qualification"
        validate_qualification(decode(runner.run("qualify", adapter, root)), contract["contract_id"])
        require(not any(root.iterdir()))
        if qualify_only:
            # This branch deliberately precedes even looking up the fixture
            # environment key. Its success attests synthetic capability only.
            return "qualification", "qualified-only", 0
        shutil.rmtree(root)
        root = None
        # Only qualified adapters reach fixture path resolution. No bytes or
        # hashes are read here; the private adapter owns its fixture mapping.
        fixture = local_file(env.get("PLAYSTEAD_CONTINUATION_FIXTURE", ""))
        require(fixture.stat().st_size > 0)
        # Independent roots prevent one successful first run from making a
        # later repetition vacuous. Each adapter action is a fresh bounded
        # process group, with a new mGBA process inside the child.
        for _run in range(2):
            root = Path(tempfile.mkdtemp(prefix="playstead-continuation.")).resolve()
            root.chmod(0o700)
            (root / "persistent-save").mkdir(mode=0o700)
            verify_save_root(root, populated=False)
            stage, accessed = "initial-save", True
            first = validate_action(decode(runner.run("initial-run", adapter, root)),
                                    contract["contract_id"], "initial-run")
            verify_save_root(root, populated=True)
            stage = "continue"
            second = validate_action(decode(runner.run("continue", adapter, root)),
                                     contract["contract_id"], "continue")
            if first == second:
                raise LifecycleFailure("fresh-launch")
            verify_save_root(root, populated=True)
            shutil.rmtree(root)
            root = None
        return "oracle", "passed", 0
    except LifecycleFailure as failure:
        return failure.stage, "failed-stage" if accessed else "blocked-capability", 1 if accessed else 77
    except (Refused, OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
        return stage, "failed-stage" if accessed else "blocked-capability", 1 if accessed else 77
    finally:
        if root is not None:
            shutil.rmtree(root, ignore_errors=True)


def emit(stage, outcome):
    # Only this newly constructed public object is ever sanitizer input.
    with tempfile.TemporaryDirectory(prefix="playstead-continuation-receipt.") as value:
        root = Path(value)
        root.chmod(0o700)
        (root / "evidence").mkdir(mode=0o700)
        receipt = {"schema": "playstead.continuation-local.v1", "run_id": str(uuid.uuid4()),
                   "stage": stage, "outcome": outcome}
        (root / "evidence/continuation.json").write_text(json.dumps(receipt) + "\n")
        completed = subprocess.run([str(SCRIPT_DIR / "sanitize-evidence.sh"), "--input", str(root),
                                    "--output", str(root / "sanitized")],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        require(completed.returncode == 0)
        sanitized = decode((root / "sanitized/continuation.json").read_bytes())
        require(sanitized == receipt)
        print(json.dumps(sanitized, sort_keys=True))


def main():
    os.umask(0o077)
    def interrupted(_signum, _frame):
        raise InterruptedError()
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    if len(sys.argv) == 2 and sys.argv[1] in ("spike", "qualify-only"):
        stage, outcome, status = execute(os.environ, qualify_only=sys.argv[1] == "qualify-only")
        try:
            emit(stage, outcome)
        except (Refused, OSError, ValueError, subprocess.SubprocessError):
            return 77
        return status
    if len(sys.argv) == 3 and sys.argv[1] == "runner":
        action = sys.argv[2]
        try:
            # Fixture-bearing actions have no standalone CLI: only execute()
            # can reach them after contract, receipt and qualification checks.
            require(action == "probe")
            runner = IsolationRunner(os.environ.get("PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM", ""))
            runner.probe()
            print("CONTINUATION_ISOLATION mechanism=" + runner.selector + " outcome=qualified")
            return 0
        except (Refused, OSError, ValueError, TypeError, subprocess.SubprocessError):
            return 77
    return 77


if __name__ == "__main__":
    raise SystemExit(main())
