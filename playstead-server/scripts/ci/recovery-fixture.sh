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
allowed = {"source-compose-startup", "source-readiness", "source-fixture-filesystem-create", "source-fixture-database-seed", "source-dump", "backup-publication", "target-restore", "target-cleanup", "result-validation", "unknown"}
assert allowed == {"source-compose-startup", "source-readiness", "source-fixture-filesystem-create", "source-fixture-database-seed", "source-dump", "backup-publication", "target-restore", "target-cleanup", "result-validation", "unknown"}
assert set(valid) == {"schema_version", "run_id", "lane", "stages", "outcome"}
assert re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", valid["run_id"])
assert json.loads(json.dumps(valid)) == valid
def classify(markers):
    parsed = markers[0] if len(markers) == 1 and markers[0] in allowed else "unknown"
    return parsed
for markers, expected in (([], "unknown"), (["source-dump"], "source-dump"), (["source-fixture-filesystem-create"], "source-fixture-filesystem-create"), (["source-fixture-database-seed"], "source-fixture-database-seed"), (["source-fixture-create"], "unknown"), (["source-dump", "source-dump"], "unknown"), (["private-path"], "unknown")):
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

write_failure_evidence() {
  local forced_stage="${1:-}"
  python3 - "$tmp/private-output" "$output" "$forced_stage" <<'PY'
import json, os, pathlib, sys, tempfile

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
forced_stage = sys.argv[3]
allowed = {
    "source-compose-startup", "source-readiness", "source-fixture-filesystem-create",
    "source-fixture-database-seed",
    "source-dump", "backup-publication", "target-restore", "target-cleanup",
    "result-validation",
}
prefix = "PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE="
if forced_stage:
    stage = forced_stage if forced_stage == "result-validation" else "unknown"
else:
    try:
        lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        lines = []
    markers = [line[len(prefix):] for line in lines if line.startswith(prefix)]
    stage = markers[0] if len(markers) == 1 and markers[0] in allowed else "unknown"

record = {
    "schema": "playstead.recovery-failure.v1",
    "lane": "linux_restore_fixture",
    "outcome": "failed",
    "failure_stage": stage,
}
temporary = None
try:
    destination.mkdir(mode=0o700)
    os.chmod(destination, 0o700)
    descriptor, name = tempfile.mkstemp(prefix=".recovery-failure.", dir=destination)
    temporary = pathlib.Path(name)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as output_file:
        output_file.write(json.dumps(record, separators=(",", ":")) + "\n")
        output_file.flush()
        os.fsync(output_file.fileno())
    os.replace(temporary, destination / "recovery-failure.json")
    temporary = None
    directory_fd = os.open(destination, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
except OSError:
    if temporary is not None:
        try:
            temporary.unlink()
        except OSError:
            pass
    raise SystemExit("FAILED: isolated restore failure evidence could not be persisted") from None

print(stage)
PY
}

if ! mix playstead.restore --compose-fixture >"$tmp/private-output" 2>&1; then
  stage="$(write_failure_evidence)" || exit 1
  printf 'FAILED: isolated restore fixture stage=%s\n' "$stage" >&2
  exit 1
fi
if ! python3 - "$tmp/private-output" "$tmp/recovery-e2e.json" <<'PY'
import json, pathlib, re, sys

def reject_duplicate_json_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result

try:
    raw = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    prefix = "PLAYSTEAD_RECOVERY_FIXTURE_JSON="
    records = [line[len(prefix):] for line in raw.splitlines() if line.startswith(prefix)]
    if len(records) != 1:
        raise ValueError
    data = json.loads(records[0], object_pairs_hook=reject_duplicate_json_keys)
    keys = {"schema_version", "run_id", "lane", "stages", "outcome"}
    if not isinstance(data, dict) or set(data) != keys:
        raise ValueError
    if data["schema_version"] != 1 or data["lane"] != "linux_restore_fixture" or data["outcome"] != "passed":
        raise ValueError
    if not isinstance(data["run_id"], str) or not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", data["run_id"]):
        raise ValueError
    if data["stages"] != ["chain", "preflight", "database", "cas", "manifest", "api"]:
        raise ValueError
    pathlib.Path(sys.argv[2]).write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
except Exception:
    raise SystemExit(1) from None
PY
then
  stage="$(write_failure_evidence result-validation)" || exit 1
  printf 'FAILED: isolated restore fixture stage=%s\n' "$stage" >&2
  exit 1
fi
mkdir -m 700 "$output"
mv "$tmp/recovery-e2e.json" "$output/recovery-e2e.json"
echo "PASS: isolated Linux recovery fixture verified"
