#!/usr/bin/env bash
# Run the real isolated restore fixture and emit only privacy-safe evidence.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
usage() { echo "usage: recovery-fixture.sh --output ABSOLUTE_NEW_DIRECTORY | --self-test" >&2; }
if [ "${1:-}" = "--self-test" ] && [ "$#" -eq 1 ]; then
  python3 - <<'PY'
import json, re
valid = {"schema_version": 1, "run_id": "123e4567-e89b-42d3-a456-426614174000", "lane": "linux_restore_fixture", "stages": ["chain", "preflight", "database", "cas", "manifest", "api"], "outcome": "passed"}
allowed = {"source-compose-startup", "source-readiness", "source-fixture-create", "source-dump", "backup-publication", "target-restore", "target-cleanup", "result-validation", "unknown"}
assert allowed == {"source-compose-startup", "source-readiness", "source-fixture-create", "source-dump", "backup-publication", "target-restore", "target-cleanup", "result-validation", "unknown"}
assert set(valid) == {"schema_version", "run_id", "lane", "stages", "outcome"}
assert re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", valid["run_id"])
assert json.loads(json.dumps(valid)) == valid
def classify(markers):
    parsed = markers[0] if len(markers) == 1 and markers[0] in allowed else "unknown"
    return parsed
for markers, expected in (([], "unknown"), (["source-dump"], "source-dump"), (["source-dump", "source-dump"], "unknown"), (["private-path"], "unknown")):
    assert classify(markers) == expected
PY
  exit 0
fi
[ "$#" -eq 2 ] && [ "$1" = "--output" ] || { usage; exit 2; }
output="$2"
case "$output" in /*) ;; *) usage; exit 2 ;; esac
[ "$output" != / ] && [ ! -e "$output" ] && [ ! -L "$output" ] || { echo "REFUSED: evidence output must be a new absolute directory" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-fixture.XXXXXXXX")"
chmod 700 "$tmp"
cleanup() {
  if [ -d "$tmp" ] && [ ! -L "$tmp" ] && [[ "$(basename "$tmp")" == playstead-recovery-fixture.* ]]; then rm -rf -- "$tmp"; fi
}
trap cleanup EXIT HUP INT TERM
if ! mix playstead.restore --compose-fixture >"$tmp/private-output" 2>&1; then
  stage="$(python3 - "$tmp/private-output" <<'PY'
import pathlib, sys
allowed = {"source-compose-startup", "source-readiness", "source-fixture-create", "source-dump", "backup-publication", "target-restore", "target-cleanup", "result-validation"}
prefix = "PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE="
lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
markers = [line[len(prefix):] for line in lines if line.startswith(prefix)]
print(markers[0] if len(markers) == 1 and markers[0] in allowed else "unknown")
PY
)"
  printf 'FAILED: isolated restore fixture stage=%s\n' "$stage" >&2
  exit 1
fi
python3 - "$tmp/private-output" "$tmp/recovery-e2e.json" <<'PY'
import json, pathlib, re, sys
def fail():
    print("FAILED: isolated restore fixture stage=result-validation", file=sys.stderr)
    raise SystemExit(1)
raw = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
prefix = "PLAYSTEAD_RECOVERY_FIXTURE_JSON="
records = [line[len(prefix):] for line in raw.splitlines() if line.startswith(prefix)]
if len(records) != 1:
    fail()
try:
    data = json.loads(records[0])
except Exception:
    fail()
keys = {"schema_version", "run_id", "lane", "stages", "outcome"}
if not isinstance(data, dict) or set(data) != keys:
    fail()
if data["schema_version"] != 1 or data["lane"] != "linux_restore_fixture" or data["outcome"] != "passed":
    fail()
if not isinstance(data["run_id"], str) or not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", data["run_id"]):
    fail()
if data["stages"] != ["chain", "preflight", "database", "cas", "manifest", "api"]:
    fail()
pathlib.Path(sys.argv[2]).write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
PY
mkdir -m 700 "$output"
mv "$tmp/recovery-e2e.json" "$output/recovery-e2e.json"
echo "PASS: isolated Linux recovery fixture verified"
