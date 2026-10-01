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
assert set(valid) == {"schema_version", "run_id", "lane", "stages", "outcome"}
assert re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", valid["run_id"])
assert json.loads(json.dumps(valid)) == valid
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
  echo "FAILED: isolated restore fixture did not verify" >&2
  exit 1
fi
python3 - "$tmp/private-output" "$tmp/recovery-e2e.json" <<'PY'
import json, pathlib, re, sys
raw = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
prefix = "PLAYSTEAD_RECOVERY_FIXTURE_JSON="
records = [line[len(prefix):] for line in raw.splitlines() if line.startswith(prefix)]
if len(records) != 1:
    raise SystemExit("restore fixture did not emit exactly one result")
try:
    data = json.loads(records[0])
except Exception:
    raise SystemExit("restore fixture result was malformed")
keys = {"schema_version", "run_id", "lane", "stages", "outcome"}
if not isinstance(data, dict) or set(data) != keys:
    raise SystemExit("restore fixture result had unexpected fields")
if data["schema_version"] != 1 or data["lane"] != "linux_restore_fixture" or data["outcome"] != "passed":
    raise SystemExit("restore fixture result had unexpected identity")
if not isinstance(data["run_id"], str) or not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", data["run_id"]):
    raise SystemExit("restore fixture run identity was malformed")
if data["stages"] != ["chain", "preflight", "database", "cas", "manifest", "api"]:
    raise SystemExit("restore fixture stages were incomplete")
pathlib.Path(sys.argv[2]).write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
PY
mkdir -m 700 "$output"
mv "$tmp/recovery-e2e.json" "$output/recovery-e2e.json"
echo "PASS: isolated Linux recovery fixture verified"
