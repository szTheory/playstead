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
mode="${FAKE_MODE:-pass}"
if [ "$mode" = fail ]; then
  echo 'private path /Users/private/Secret.gba Bearer synthetic-secret'
  exit 1
fi
if [ "$mode" = stage ]; then
  echo "PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=${FAKE_STAGE:-unknown}"
  echo 'private path /Users/private/Secret.gba Bearer synthetic-secret'
  exit 1
fi
if [ "$mode" = duplicate ]; then
  echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=target-restore'
  echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=database-dump'
  echo 'Bearer synthetic-secret /Users/private/Secret.gba'
  exit 1
fi
if [ "$mode" = unknown ]; then
  echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=private-path-Bearer-secret'
  exit 1
fi
if [ "$mode" = malformed_stage ]; then
  echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=target-restore /Users/private/Secret.gba'
  exit 1
fi
if [ "$mode" = malformed ]; then echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"secret":"bad"}'; exit 0; fi
if [ "$mode" = duplicate_receipt ]; then
  echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}'
  echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174001","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}'
  exit 0
fi
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
if TMPDIR="$tmp" FAKE_MODE=fail PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/fail" >"$tmp/fail.stdout" 2>"$tmp/fail.stderr"; then
  echo "failed fixture must not produce evidence" >&2; exit 1
fi
grep -Fx 'FAILED: isolated restore fixture stage=unknown' "$tmp/fail.stderr" >/dev/null
if [ -e "$tmp/fail" ] || grep -E 'private path|/Users/|Bearer|Secret\.gba' "$tmp/fail.stdout" "$tmp/fail.stderr" >/dev/null; then
  echo "raw failure output or a failure receipt escaped" >&2; exit 1
fi

failure_stages="compose-source-startup source-readiness source-fixture-creation database-dump backup-publication target-restore target-cleanup result-validation unknown"
for stage in $failure_stages; do
  output="$tmp/stage-$stage"
  if TMPDIR="$tmp" FAKE_MODE=stage FAKE_STAGE="$stage" PATH="$tmp/bin:$PATH" "$coordinator" --output "$output" >"$tmp/stage.stdout" 2>"$tmp/stage.stderr"; then
    echo "stage failure must return nonzero" >&2; exit 1
  fi
  grep -Fx "FAILED: isolated restore fixture stage=$stage" "$tmp/stage.stderr" >/dev/null
  if [ -e "$output" ] || grep -E 'private path|/Users/|Bearer|Secret\.gba|PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE' "$tmp/stage.stdout" "$tmp/stage.stderr" >/dev/null; then
    echo "stage failure leaked raw content or a marker" >&2; exit 1
  fi
  if find "$tmp" -maxdepth 1 -name 'playstead-recovery-fixture.*' -print -quit | grep -q .; then
    echo "private temporary root survived stage failure" >&2; exit 1
  fi
done

for malformed_mode in duplicate unknown malformed_stage; do
  output="$tmp/$malformed_mode"
  if TMPDIR="$tmp" FAKE_MODE="$malformed_mode" PATH="$tmp/bin:$PATH" "$coordinator" --output "$output" >"$tmp/$malformed_mode.stdout" 2>"$tmp/$malformed_mode.stderr"; then
    echo "malformed failure marker must return nonzero" >&2; exit 1
  fi
  grep -Fx 'FAILED: isolated restore fixture stage=unknown' "$tmp/$malformed_mode.stderr" >/dev/null
  if [ -e "$output" ] || grep -E 'private path|/Users/|Bearer|Secret\.gba|PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE' "$tmp/$malformed_mode.stdout" "$tmp/$malformed_mode.stderr" >/dev/null; then
    echo "malformed marker leaked raw content or a failure receipt" >&2; exit 1
  fi
done

for malformed_result in malformed duplicate_receipt; do
  output="$tmp/$malformed_result"
  if TMPDIR="$tmp" FAKE_MODE="$malformed_result" PATH="$tmp/bin:$PATH" "$coordinator" --output "$output" >"$tmp/$malformed_result.stdout" 2>"$tmp/$malformed_result.stderr"; then
    echo "malformed result must be refused" >&2; exit 1
  fi
  grep -Fx 'FAILED: isolated restore fixture stage=result-validation' "$tmp/$malformed_result.stderr" >/dev/null
  [ ! -e "$output/recovery-e2e.json" ] || { echo "validation failure emitted a receipt" >&2; exit 1; }
  if grep -E 'secret|/Users/|Bearer|Secret\.gba|PLAYSTEAD_RECOVERY_FIXTURE_JSON' "$tmp/$malformed_result.stdout" "$tmp/$malformed_result.stderr" >/dev/null; then
    echo "result validation leaked private content" >&2; exit 1
  fi
done
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
# Older prerequisite branches have no decoder producer. Once present, only
# its same-run runtime may precede recovery; the fixture remains independent
# of the ordinary server and Compose outcomes.
expected_needs = ["decoder-runtime"] if "decoder-runtime" in jobs else []
assert job.get("needs", []) == expected_needs
PY
echo "recovery fixture coordinator contracts passed (fake command only)"
