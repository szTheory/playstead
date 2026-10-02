#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SERVER_ROOT}/.." && pwd)"
HELPER="${REPO_ROOT}/playstead-mac/scripts/ci/reliability-load.py"
TEST_FILE="test/playstead_web/browser/setup_wizard_journey_test.exs"
DRIVER_DIR="${SERVER_ROOT}/_build/chrome-for-testing/chromedriver-mac-arm64"
DRIVER="${DRIVER_DIR}/chromedriver"
CHROME_INFO="/Applications/Google Chrome.app/Contents/Info.plist"
EVIDENCE_DIR="${REPO_ROOT}/playstead-mac/.build/phase06-reliability"
RUN_RESULT="${EVIDENCE_DIR}/setup-wizard.json"
RUNS=20
DEADLINE_SECONDS=1800

usage() {
  printf '%s\n' 'Usage: repeat-setup-wizard-reliability.sh --runs 20 --deadline-seconds 1800' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runs)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      RUNS="$2"
      shift 2
      ;;
    --deadline-seconds)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      DEADLINE_SECONDS="$2"
      shift 2
      ;;
    *) usage; exit 2 ;;
  esac
done

[ "$RUNS" = 20 ] && [ "$DEADLINE_SECONDS" = 1800 ] || { usage; exit 2; }
if [ -L "${REPO_ROOT}/playstead-mac/.build" ] || { [ -e "${REPO_ROOT}/playstead-mac/.build" ] && [ ! -d "${REPO_ROOT}/playstead-mac/.build" ]; }; then
  printf '%s\n' 'setup-wizard reliability: ignored evidence parent identity is invalid' >&2
  exit 77
fi
mkdir -p "${REPO_ROOT}/playstead-mac/.build"
if [ -L "$EVIDENCE_DIR" ] || { [ -e "$EVIDENCE_DIR" ] && [ ! -d "$EVIDENCE_DIR" ]; }; then
  printf '%s\n' 'setup-wizard reliability: ignored evidence directory identity is invalid' >&2
  exit 77
fi
mkdir -p "$EVIDENCE_DIR"
chmod 700 "$EVIDENCE_DIR"
if [ -e "$RUN_RESULT" ] || [ -L "$RUN_RESULT" ]; then
  [ ! -L "$RUN_RESULT" ] && [ -f "$RUN_RESULT" ] || {
    printf '%s\n' 'setup-wizard reliability: prior result identity is invalid' >&2
    exit 77
  }
  rm "$RUN_RESULT"
fi
[ -f "$HELPER" ] && [ -f "${SERVER_ROOT}/mix.exs" ] && [ -f "${SERVER_ROOT}/${TEST_FILE}" ] || {
  printf '%s\n' 'setup-wizard reliability: project inputs are unavailable' >&2
  exit 77
}
[ -x "$DRIVER" ] && [ -f "$CHROME_INFO" ] || {
  printf '%s\n' 'setup-wizard reliability: matched Chrome and ChromeDriver are unavailable' >&2
  exit 77
}
version_record="$(python3 - "$DRIVER" "$CHROME_INFO" <<'PY'
import pathlib, plistlib, re, subprocess, sys
driver = pathlib.Path(sys.argv[1])
info = pathlib.Path(sys.argv[2])
if driver.is_symlink() or not driver.is_file() or not info.is_file():
    raise SystemExit(77)
result = subprocess.run([str(driver), "--version"], check=False, capture_output=True, text=True, timeout=5)
match = re.fullmatch(r"ChromeDriver ([0-9]+(?:\.[0-9]+){3}) \([^\r\n()]*\)\s*", result.stdout)
if result.returncode != 0 or match is None:
    raise SystemExit(77)
data = plistlib.loads(info.read_bytes())
chrome_version = data.get("CFBundleShortVersionString")
if not isinstance(chrome_version, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){3}", chrome_version):
    raise SystemExit(77)
driver_build = ".".join(match.group(1).split(".")[:3])
chrome_build = ".".join(chrome_version.split(".")[:3])
if driver_build != chrome_build:
    print("setup-wizard reliability: ChromeDriver build does not match installed Chrome", file=sys.stderr)
    raise SystemExit(77)
print(f"matched_build={chrome_build}")
PY
)" || {
  printf '%s\n' 'setup-wizard reliability: browser identity verification failed' >&2
  exit 77
}
printf 'setup-wizard reliability: %s\n' "$version_record"
fingerprint_json="$(python3 "$HELPER" fingerprint --repo-root "$REPO_ROOT")" || {
  printf '%s\n' 'setup-wizard reliability: source fingerprint could not be computed' >&2
  exit 77
}
SOURCE_HEAD="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["source_head"])' <<<"$fingerprint_json")"
SOURCE_FINGERPRINT="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["source_fingerprint"])' <<<"$fingerprint_json")"

command -v mix >/dev/null 2>&1 || { printf '%s\n' 'setup-wizard reliability: Mix is unavailable' >&2; exit 77; }
command -v pg_isready >/dev/null 2>&1 && pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1 || {
  printf '%s\n' 'setup-wizard reliability: the existing local test database is unavailable' >&2
  exit 77
}
if lsof -nP -iTCP:4002 -sTCP:LISTEN -t >/dev/null 2>&1; then
  printf '%s\n' 'setup-wizard reliability: isolated browser port 4002 is already owned' >&2
  exit 77
fi

export PATH="${DRIVER_DIR}:${PATH}"
OWNER="$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
RUN_ROOT="$(mktemp -d /private/tmp/playstead-setup-wizard-reliability.XXXXXX)"
chmod 700 "$RUN_ROOT"
printf '%s' "$OWNER" >"${RUN_ROOT}/.owner"
chmod 600 "${RUN_ROOT}/.owner"
mkdir -m 700 "${RUN_ROOT}/evidence"
STARTED_AT="$(date +%s)"
TEST_RUNNER_PID=""
PROBE_PID=""

stop_process() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 80); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  stop_process "$PROBE_PID"
  PROBE_PID=""
  stop_process "$TEST_RUNNER_PID"
  TEST_RUNNER_PID=""
  if [ -d "$RUN_ROOT" ] && [ ! -L "$RUN_ROOT" ] && [ -f "${RUN_ROOT}/.owner" ] && [ "$(cat "${RUN_ROOT}/.owner")" = "$OWNER" ]; then
    : # Keep the private run root for local diagnosis; it contains reduced evidence and private raw logs only.
  else
    printf '%s\n' 'setup-wizard reliability: run-root ownership changed; private artifacts were left untouched' >&2
    status=77
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

verify_root() {
  python3 - "$RUN_ROOT" "$OWNER" <<'PY'
import pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
marker = root / ".owner"
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) & 0o077:
    raise SystemExit(77)
if marker.is_symlink() or not marker.is_file() or stat.S_IMODE(marker.stat().st_mode) & 0o077 or marker.read_text(encoding="ascii") != sys.argv[2]:
    raise SystemExit(77)
PY
}

valid_owned_marker() {
  local iteration_root="$1"
  local marker="$2"
  python3 - "$RUN_ROOT" "$OWNER" "$iteration_root" "$marker" <<'PY'
import pathlib, stat, sys
run_root = pathlib.Path(sys.argv[1])
owner = sys.argv[2]
root = pathlib.Path(sys.argv[3])
marker = pathlib.Path(sys.argv[4])
owner_marker = root / ".owner"
if run_root.is_symlink() or root.is_symlink() or marker.is_symlink() or not marker.is_file():
    raise SystemExit(1)
if root.parent.resolve(strict=True) != run_root.resolve(strict=True) or marker.parent.resolve(strict=True) != root.resolve(strict=True):
    raise SystemExit(1)
if not root.is_dir() or stat.S_IMODE(root.stat().st_mode) & 0o077:
    raise SystemExit(1)
if owner_marker.is_symlink() or not owner_marker.is_file() or owner_marker.read_text(encoding="ascii") != owner:
    raise SystemExit(1)
if stat.S_IMODE(marker.stat().st_mode) & 0o077 or marker.read_text(encoding="ascii") != owner:
    raise SystemExit(1)
PY
}

write_owned_marker() {
  local iteration_root="$1"
  local marker="$2"
  python3 - "$RUN_ROOT" "$OWNER" "$iteration_root" "$marker" <<'PY'
import os, pathlib, stat, sys
run_root, owner, root_raw, marker_raw = sys.argv[1:]
run_root = pathlib.Path(run_root)
root = pathlib.Path(root_raw)
marker = pathlib.Path(marker_raw)
if root.is_symlink() or marker.is_symlink() or marker.exists():
    raise SystemExit(77)
if root.parent.resolve(strict=True) != run_root.resolve(strict=True) or marker.parent.resolve(strict=True) != root.resolve(strict=True):
    raise SystemExit(77)
if stat.S_IMODE(root.stat().st_mode) & 0o077 or (root / ".owner").read_text(encoding="ascii") != owner:
    raise SystemExit(77)
temporary = marker.with_name(marker.name + ".tmp")
fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
with os.fdopen(fd, "w", encoding="ascii") as stream:
    stream.write(owner)
    stream.flush()
    os.fsync(stream.fileno())
os.rename(temporary, marker)
PY
}

record_result() {
  local iteration="$1"
  local outcome="$2"
  local failure_class="$3"
  local probe_outcome="$4"
  local probe_requests="$5"
  python3 - "$RUN_ROOT" "$OWNER" "$iteration" "$outcome" "$failure_class" "$probe_outcome" "$probe_requests" <<'PY'
import json, os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) & 0o077:
    raise SystemExit(77)
if (root / ".owner").read_text(encoding="ascii") != sys.argv[2]:
    raise SystemExit(77)
iteration = int(sys.argv[3])
outcome, failure_class, probe_outcome = sys.argv[4:7]
probe_requests = int(sys.argv[7])
if outcome not in {"passed", "failed"} or failure_class not in {"passed", "assertion", "browser_session", "database", "probe", "infrastructure"}:
    raise SystemExit(77)
if probe_outcome not in {"passed", "failed", "not_started"} or probe_requests < 0:
    raise SystemExit(77)
record = {
    "iteration": iteration,
    "outcome": outcome,
    "failure_class": failure_class,
    "probe_shape": "4x2rps",
    "probe_outcome": probe_outcome,
    "probe_requests": probe_requests,
}
path = root / "evidence" / "runs.jsonl"
with path.open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(record, sort_keys=True) + "\n")
os.chmod(path, 0o600)
PY
}

probe_result() {
  local iteration_root="$1"
  python3 - "$iteration_root/probe-report.json" <<'PY'
import json, pathlib, sys
try:
    data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    print("failed 0")
    raise SystemExit(0)
required = {"schema", "probe_count", "max_requests_per_second_per_probe", "successful_requests", "last_status", "failed_requests"}
if set(data) != required or data.get("schema") != "playstead.reliability-probes.v1" or data.get("probe_count") != 4 or data.get("max_requests_per_second_per_probe") != 2:
    print("failed 0")
    raise SystemExit(0)
successful = data["successful_requests"]
statuses = data["last_status"]
failed = data["failed_requests"]
if not all(isinstance(values, list) and len(values) == 4 and all(type(item) is int and item >= 0 for item in values) for values in (successful, statuses, failed)):
    print("failed 0")
    raise SystemExit(0)
requests = sum(successful)
passed = all(value > 0 for value in successful) and all(value == 200 for value in statuses) and all(value == 0 for value in failed)
print(("passed" if passed else "failed") + " " + str(requests))
PY
}

classify_test_log() {
  local log="$1"
  local status="$2"
  python3 - "$log" "$status" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
text = re.sub(r"\x1b\[[0-9;]*m", "", text)
if "invalid session id" in text.lower() or "chrome not reachable" in text.lower() or "session deleted" in text.lower():
    print("browser_session")
elif "DBConnection.ConnectionError" in text or "Postgrex.Error" in text or "database connection" in text.lower():
    print("database")
elif int(sys.argv[2]) != 0 and re.search(r"\b1 feature, 1 failure\b", text) and re.search(
    r"(?:ExUnit\.AssertionError|Wallaby\.ExpectationNotMetError)", text
):
    print("assertion")
elif int(sys.argv[2]) == 0 and re.search(r"\b1 feature, 0 failures\b", text):
    print("passed")
else:
    print("infrastructure")
PY
}

passed=0
assertion_failures=0
infrastructure_failures=0
probe_failures=0
for iteration in $(seq 1 "$RUNS"); do
  verify_root || { printf '%s\n' 'setup-wizard reliability: run-root ownership mismatch' >&2; exit 77; }
  now="$(date +%s)"
  elapsed=$((now - STARTED_AT))
  remaining=$((DEADLINE_SECONDS - elapsed))
  if [ "$remaining" -le 0 ]; then
    printf '%s\n' 'setup-wizard reliability: 30-minute deadline reached' >&2
    exit 124
  fi

  iteration_root="${RUN_ROOT}/iteration-${iteration}"
  mkdir -m 700 "$iteration_root"
  printf '%s' "$OWNER" >"${iteration_root}/.owner"
  chmod 600 "${iteration_root}/.owner"
  mkdir -m 700 "${iteration_root}/raw" "${iteration_root}/screenshots"
  test_log="${iteration_root}/raw/test.log"
  probe_log="${iteration_root}/raw/probes.log"
  TEST_RUNNER_PID=""
  PROBE_PID=""
  test_status=0
  probe_status=0
  probe_outcome="not_started"
  probe_requests=0
  failure_class="infrastructure"
  outcome="failed"

  PLAYSTEAD_RELIABILITY_ROOT="$iteration_root" \
    PLAYSTEAD_RELIABILITY_OWNER="$OWNER" \
    python3 "$HELPER" command --timeout-seconds "$remaining" --log-path "$test_log" -- \
      env PATH="$DRIVER_DIR:$PATH" MIX_ENV=test MIX_TEST_PARTITION=0 PORT=4002 ERL_FLAGS='+S 4:4' \
        PLAYSTEAD_WALLABY_SCREENSHOT_ON_FAILURE=false \
        PLAYSTEAD_RELIABILITY_ROOT="$iteration_root" PLAYSTEAD_RELIABILITY_OWNER="$OWNER" \
        PLAYSTEAD_WALLABY_SCREENSHOT_DIR="${iteration_root}/screenshots" \
        mix test "$TEST_FILE" --max-cases 4 &
  TEST_RUNNER_PID=$!

  marker_deadline=$(( $(date +%s) + 90 ))
  journey_started=false
  while [ "$(date +%s)" -lt "$marker_deadline" ]; do
    verify_root || { printf '%s\n' 'setup-wizard reliability: run-root ownership mismatch' >&2; exit 77; }
    journey_marker="${iteration_root}/journey-started"
    if [ -f "$journey_marker" ] || [ -L "$journey_marker" ]; then
      if ! valid_owned_marker "$iteration_root" "$journey_marker"; then
        printf '%s\n' 'setup-wizard reliability: journey marker failed ownership validation' >&2
        exit 77
      fi
      journey_started=true
      break
    fi
    if ! kill -0 "$TEST_RUNNER_PID" 2>/dev/null; then
      wait "$TEST_RUNNER_PID" || test_status=$?
      TEST_RUNNER_PID=""
      break
    fi
    sleep 0.05
  done

  if [ "$journey_started" != true ] && [ -n "$TEST_RUNNER_PID" ]; then
    failure_class="infrastructure"
    stop_process "$TEST_RUNNER_PID"
    TEST_RUNNER_PID=""
  fi

  if [ "$journey_started" = true ]; then
    python3 "$HELPER" probes --root "$iteration_root" --owner "$OWNER" \
      --url http://127.0.0.1:4002/healthz --probes 4 --max-rps 2 --ready-timeout 20 \
      >"$probe_log" 2>&1 &
    PROBE_PID=$!
    probe_ready=false
    probe_deadline=$(( $(date +%s) + 25 ))
    while [ "$(date +%s)" -lt "$probe_deadline" ]; do
      verify_root || { printf '%s\n' 'setup-wizard reliability: run-root ownership mismatch' >&2; exit 77; }
      ready_marker="${iteration_root}/probes-ready"
      if [ -f "$ready_marker" ] || [ -L "$ready_marker" ]; then
        if ! valid_owned_marker "$iteration_root" "$ready_marker"; then
          printf '%s\n' 'setup-wizard reliability: probe marker failed ownership validation' >&2
          exit 77
        fi
        probe_ready=true
        break
      fi
      if ! kill -0 "$PROBE_PID" 2>/dev/null; then
        wait "$PROBE_PID" || probe_status=$?
        PROBE_PID=""
        break
      fi
      if ! kill -0 "$TEST_RUNNER_PID" 2>/dev/null; then
        wait "$TEST_RUNNER_PID" || test_status=$?
        TEST_RUNNER_PID=""
        break
      fi
      sleep 0.05
    done

    if [ "$probe_ready" = true ]; then
      journey_deadline=$((STARTED_AT + DEADLINE_SECONDS))
      while [ "$(date +%s)" -lt "$journey_deadline" ]; do
        verify_root || { printf '%s\n' 'setup-wizard reliability: run-root ownership mismatch' >&2; exit 77; }
        complete_marker="${iteration_root}/journey-complete"
        if [ -f "$complete_marker" ] || [ -L "$complete_marker" ]; then
          if ! valid_owned_marker "$iteration_root" "$complete_marker"; then
            printf '%s\n' 'setup-wizard reliability: completion marker failed ownership validation' >&2
            exit 77
          fi
          break
        fi
        if ! kill -0 "$TEST_RUNNER_PID" 2>/dev/null; then
          break
        fi
        sleep 0.05
      done
    else
      failure_class="probe"
      stop_process "$TEST_RUNNER_PID"
      TEST_RUNNER_PID=""
    fi
  fi

  if [ -n "$PROBE_PID" ]; then
    kill -TERM "$PROBE_PID" 2>/dev/null || true
    wait "$PROBE_PID" || probe_status=$?
    PROBE_PID=""
  fi
  if [ -f "${iteration_root}/probe-report.json" ]; then
    read -r probe_outcome probe_requests <<<"$(probe_result "$iteration_root")"
  fi
  if [ -f "${iteration_root}/journey-complete" ]; then
    write_owned_marker "$iteration_root" "${iteration_root}/probes-stopped"
  fi
  if [ -n "$TEST_RUNNER_PID" ]; then
    wait "$TEST_RUNNER_PID" || test_status=$?
    TEST_RUNNER_PID=""
  fi

  if [ "$failure_class" = infrastructure ]; then
    failure_class="$(classify_test_log "$test_log" "$test_status")"
  fi
  if [ "$probe_outcome" != passed ] || [ "$probe_status" -ne 0 ]; then
    if [ "$probe_outcome" != not_started ]; then
      failure_class="probe"
    fi
  fi

  if [ "$failure_class" = passed ] && [ "$test_status" -eq 0 ] && [ "$probe_outcome" = passed ] && [ "$probe_status" -eq 0 ]; then
    outcome="passed"
    passed=$((passed + 1))
  elif [ "$failure_class" = assertion ] && [ "$probe_outcome" = passed ] && [ "$probe_status" -eq 0 ]; then
    assertion_failures=$((assertion_failures + 1))
  elif [ "$failure_class" = probe ]; then
    probe_failures=$((probe_failures + 1))
  else
    case "$failure_class" in
      browser_session|database|infrastructure) ;;
      *) failure_class="infrastructure" ;;
    esac
    infrastructure_failures=$((infrastructure_failures + 1))
  fi

  record_result "$iteration" "$outcome" "$failure_class" "$probe_outcome" "$probe_requests"
  printf 'setup-wizard reliability: iteration=%s outcome=%s class=%s probes=%s requests=%s\n' \
    "$iteration" "$outcome" "$failure_class" "$probe_outcome" "$probe_requests"

  if [ "$failure_class" = infrastructure ] || [ "$failure_class" = probe ] || \
     [ "$failure_class" = browser_session ] || [ "$failure_class" = database ]; then
    printf 'setup-wizard reliability: stopped at iteration %s after a non-assertion failure\n' "$iteration" >&2
    break
  fi
done

iterations_completed=0
if [ -f "${RUN_ROOT}/evidence/runs.jsonl" ]; then
  iterations_completed="$(wc -l <"${RUN_ROOT}/evidence/runs.jsonl" | tr -d '[:space:]')"
fi
printf 'setup-wizard reliability: iterations=%s passed=%s assertion_failures=%s probe_failures=%s infrastructure_failures=%s load=4x2rps\n' \
  "$iterations_completed" "$passed" "$assertion_failures" "$probe_failures" "$infrastructure_failures"
if [ "$iterations_completed" -ne 20 ] || [ "$passed" -ne 20 ] || [ "$assertion_failures" -ne 0 ] || \
   [ "$probe_failures" -ne 0 ] || [ "$infrastructure_failures" -ne 0 ]; then
  exit 1
fi
if [ "$(($(date +%s) - STARTED_AT))" -gt "$DEADLINE_SECONDS" ]; then
  printf '%s\n' 'setup-wizard reliability: 30-minute deadline reached after the final journey' >&2
  exit 124
fi

fingerprint_after="$(python3 "$HELPER" fingerprint --repo-root "$REPO_ROOT")" || {
  printf '%s\n' 'setup-wizard reliability: final source fingerprint could not be computed' >&2
  exit 77
}
python3 - "$fingerprint_after" "$SOURCE_HEAD" "$SOURCE_FINGERPRINT" <<'PY'
import json, sys
actual = json.loads(sys.argv[1])
if actual != {"source_head": sys.argv[2], "source_fingerprint": sys.argv[3]}:
    raise SystemExit("setup-wizard reliability: source changed during repeated run")
PY

python3 - "$RUN_ROOT" "$OWNER" "$RUN_RESULT" "$SOURCE_HEAD" "$SOURCE_FINGERPRINT" "$STARTED_AT" "$version_record" <<'PY'
import json, os, pathlib, re, stat, sys, time
root = pathlib.Path(sys.argv[1])
owner, destination = sys.argv[2], pathlib.Path(sys.argv[3])
head, fingerprint, started_at, browser = sys.argv[4:]
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) != 0o700:
    raise SystemExit("setup-wizard reliability: evidence root identity changed")
marker = root / ".owner"
if marker.is_symlink() or marker.read_text(encoding="ascii") != owner:
    raise SystemExit("setup-wizard reliability: evidence owner changed")
records = [json.loads(line) for line in (root / "evidence" / "runs.jsonl").read_text(encoding="utf-8").splitlines()]
expected = [
    {"iteration": index, "outcome": "passed", "failure_class": "passed", "probe_shape": "4x2rps", "probe_outcome": "passed", "probe_requests": record["probe_requests"]}
    for index, record in enumerate(records, 1)
]
if len(records) != 20 or records != expected or any(type(record["probe_requests"]) is not int or record["probe_requests"] < 4 for record in records):
    raise SystemExit("setup-wizard reliability: final run records are incomplete or failed")
match = re.fullmatch(r"matched_build=([0-9]+(?:\.[0-9]+){2})", browser)
if match is None:
    raise SystemExit("setup-wizard reliability: browser build identity is invalid")
manifest = {
    "schema": "playstead.reliability-run.v1",
    "case": "setup-wizard-journey",
    "source_head": head,
    "source_fingerprint": fingerprint,
    "expected_runs": 20,
    "completed_runs": len(records),
    "passed_runs": sum(record["outcome"] == "passed" for record in records),
    "assertion_failures": 0,
    "probe_failures": 0,
    "infrastructure_failures": 0,
    "probe_count": 4,
    "max_requests_per_second_per_probe": 2,
    "successful_probe_requests": sum(record["probe_requests"] for record in records),
    "browser_build": match.group(1),
    "elapsed_seconds": int(time.time()) - int(started_at),
}
temporary = destination.with_name(destination.name + ".tmp")
if destination.exists() or destination.is_symlink() or temporary.exists() or temporary.is_symlink():
    raise SystemExit("setup-wizard reliability: result destination already exists")
fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(manifest, stream, sort_keys=True)
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
os.rename(temporary, destination)
PY
printf '%s\n' 'setup-wizard reliability: sanitized manifest written under ignored local build storage'
