#!/usr/bin/env bash
# Parser/command-boundary contract only; fake mix never invokes Docker.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
coordinator="$root/scripts/ci/recovery-fixture.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-fixture-test.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
"$coordinator" --self-test
mkdir -p "$tmp/bin"
cat >"$tmp/bin/mix" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_MODE:-pass}" = fail ]; then echo private-path; exit 1; fi
if [ "${FAKE_MODE:-pass}" = malformed ]; then echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"secret":"bad"}'; exit 0; fi
echo 'private fixture path /Users/owner/game.gba'
echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}'
EOF
chmod 700 "$tmp/bin/mix"
PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/pass"
python3 - "$tmp/pass/recovery-e2e.json" <<'PY'
import json, pathlib, sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(data)=={"schema_version","run_id","lane","stages","outcome"}
assert data["outcome"]=="passed"
PY
if [ -e "$tmp/fail" ] || FAKE_MODE=fail PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/fail" >/dev/null 2>&1; then
  echo "failed fixture must not produce evidence" >&2; exit 1
fi
if FAKE_MODE=malformed PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/malformed" >/dev/null 2>&1; then
  echo "malformed result must be refused" >&2; exit 1
fi
if "$coordinator" --output relative >/dev/null 2>&1 || "$coordinator" --output "$tmp/pass" >/dev/null 2>&1; then
  echo "unsafe evidence output must be refused" >&2; exit 1
fi
workflow="$root/../.github/workflows/ci.yml"
grep -Fq '  recovery-fixture:' "$workflow"
grep -Fq 'timeout-minutes: 35' "$workflow"
grep -Fq 'timeout 20m bash playstead-server/scripts/ci/recovery-fixture.sh --output' "$workflow"
grep -Fq 'path: ${{ runner.temp }}/recovery-sanitized/recovery-e2e.json' "$workflow"
grep -Fq 'retention-days: 7' "$workflow"
python3 - "$workflow" <<'PY'
import pathlib, sys, yaml
jobs=yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())["jobs"]
job=jobs["recovery-fixture"]
assert job["defaults"]["run"]["working-directory"] == "."
assert any(s.get("name") == "Compile recovery task and dependencies" and s.get("run") == "mix compile --warnings-as-errors" and s.get("working-directory") == "playstead-server" for s in job["steps"])
assert not job.get("needs")
PY
echo "recovery fixture coordinator contracts passed (fake command only)"
