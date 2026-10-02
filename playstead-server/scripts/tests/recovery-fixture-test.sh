#!/usr/bin/env bash
# Parser/command-boundary contract only; fake mix never invokes Docker.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
coordinator="$root/scripts/ci/recovery-fixture.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-fixture-test.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
"$coordinator" --self-test
python3 - "$root/lib/mix/tasks/playstead.restore.ex" <<'PY'
import pathlib, re, sys
source=pathlib.Path(sys.argv[1]).read_text()
start=source.index("  defp run_fixture! do")
end=source.index("  defp docker_available?")
run=source[start:end]
assert run.index("work_result =") < run.index("cleanup_result = cleanup_fixture") < run.index("case {work_result, cleanup_result}")
assert "{{:ok, correlation_id, stages}, :ok} ->\n          emit_fixture_result(correlation_id, stages)" in run
assert "{{:ok, _correlation_id, _stages}, {:error, _}} ->\n          Mix.shell().info(\"PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=target-cleanup\")" in run
assert "{{:failure, kind, reason, stacktrace, stage}, _cleanup_result} ->\n          Mix.shell().info(\"PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=#{stage}\")" in run
assert "defp cleanup_fixture" in run and "source(project, source_file, [\"down\", \"--volumes\", \"--remove-orphans\"])" in run
assert "case File.rm_rf(root) do\n        {:ok, _removed_paths} -> :ok\n        {:error, _reason, _path} -> {:error, :target_cleanup_failed}" in run
assert "_ = source(project, source_file" not in run and "case File.rm_rf(root) do" in run
filesystem_marker = re.search(r'Process\.put\(:playstead_recovery_fixture_failure_stage, "([a-z-]+)"\)\s+File\.mkdir_p!\(root\)\s+File\.write!\(source_file, source_compose\(\)\)', run)
assert filesystem_marker and filesystem_marker.group(1) == "source-fixture-filesystem-create", "filesystem fixture operations need their own failure marker"
database_marker = re.search(r'Process\.put\(:playstead_recovery_fixture_failure_stage, "([a-z-]+)"\)\s+:ok =\s+source\(project, source_file, \[\s+"exec",\s+"-T",\s+"db",\s+"psql",', run)
assert database_marker and database_marker.group(1) == "source-fixture-database-seed", "database seeding needs its own failure marker"
assert "source-fixture-create" not in run, "retired shared failure marker must not remain in the producer"
assert run.index("{{:failure, kind, reason, stacktrace, stage}") < run.index("{{:ok, _correlation_id, _stages}, {:error, _}}")
assert run.count('PLAYSTEAD_RECOVERY_FIXTURE_JSON="') == 1
assert run.index("cleanup_result = cleanup_fixture") < run.index("defp emit_fixture_result")

def outcome(work, cleanup):
    if work != "ok": return ("failed", work, 1)
    if cleanup != "ok": return ("failed", "target-cleanup", 1)
    return ("passed", None, 0)

assert outcome("ok", "ok") == ("passed", None, 0)
assert outcome("ok", "cleanup-error") == ("failed", "target-cleanup", 1)
assert outcome("source-dump", "cleanup-error") == ("failed", "source-dump", 1)
assert outcome("target-restore", "ok") == ("failed", "target-restore", 1)
print("restore task teardown and stage precedence contracts passed")
PY
mkdir -p "$tmp/bin"
cat >"$tmp/bin/mix" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_MODE:-pass}" in
  stage-*) echo "PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=${FAKE_MODE#stage-}"; exit 1 ;;
esac
case "${FAKE_MODE:-pass}" in
  fail) echo private-path-token; echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=target-restore'; exit 1 ;;
  missing-marker) echo private-path-token; exit 1 ;;
  duplicate-marker) echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=target-restore'; echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=source-dump'; exit 1 ;;
  malformed-marker) echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=target-restore private-path-token'; exit 1 ;;
  unknown-marker) echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=private-path'; exit 1 ;;
  retired-marker) echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=source-fixture-create'; exit 1 ;;
  sentinels) echo 'private path /Users/private/game.gba token=must-not-print'; exit 1 ;;
esac
case "${FAKE_MODE:-pass}" in
  malformed) echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"secret":"bad"}'; exit 0 ;;
  missing-success-marker) echo 'private fixture path /Users/owner/game.gba'; exit 0 ;;
  duplicate-success-marker)
    echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}'
    echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}'
    exit 0 ;;
  duplicate-success-key) echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"failed","outcome":"passed"}'; exit 0 ;;
esac
echo 'private fixture path /Users/owner/game.gba'
echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}'
EOF
chmod 700 "$tmp/bin/mix"
allowed_stages=(source-compose-startup source-readiness source-fixture-filesystem-create source-fixture-database-seed source-dump backup-publication target-restore target-cleanup result-validation)
TMPDIR="$tmp" PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/pass"
python3 - "$tmp/pass" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
assert sorted(path.name for path in root.iterdir())==["recovery-e2e.json"]
data=json.loads((root/"recovery-e2e.json").read_text())
assert set(data)=={"schema_version","run_id","lane","stages","outcome"}
assert data["outcome"]=="passed"
PY
for mode in fail missing-marker duplicate-marker malformed-marker unknown-marker retired-marker sentinels; do
  output="$tmp/failure-$mode.out"
  if TMPDIR="$tmp" FAKE_MODE="$mode" PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/fail-$mode" >"$output" 2>&1; then
    echo "failed fixture must not produce evidence ($mode)" >&2; exit 1
  fi
  case "$mode" in fail) expected=target-restore ;; *) expected=unknown ;; esac
  grep -Fx "FAILED: isolated restore fixture stage=$expected" "$output" >/dev/null || {
    echo "failure stage was not classified safely ($mode)" >&2; exit 1;
  }
  if grep -E 'private-path|private path|/Users/|game\.gba|must-not-print|token=' "$output" >/dev/null; then
    echo "private command output escaped ($mode)" >&2; exit 1
  fi
  if grep -F 'PLAYSTEAD_RECOVERY_FIXTURE_JSON=' "$output" >/dev/null; then
    echo "pass receipt escaped after failed command ($mode)" >&2; exit 1
  fi
  python3 - "$tmp/fail-$mode/recovery-failure.json" "$expected" <<'PY'
import json, pathlib, stat, sys
path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text())
assert set(data)=={"schema","lane","outcome","failure_stage"}
assert data=={"schema":"playstead.recovery-failure.v1","lane":"linux_restore_fixture","outcome":"failed","failure_stage":sys.argv[2]}
assert stat.S_IMODE(path.stat().st_mode)==0o600
assert stat.S_IMODE(path.parent.stat().st_mode)==0o700
assert not any(s in path.read_text() for s in ("private-path-token","private path","/Users/","game.gba","must-not-print","token="))
PY
  [ ! -e "$tmp/fail-$mode/recovery-e2e.json" ] || { echo "failure wrote the passing receipt ($mode)" >&2; exit 1; }
done
for stage in "${allowed_stages[@]}"; do
  output="$tmp/stage-$stage.out"
  if TMPDIR="$tmp" FAKE_MODE="stage-$stage" PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/stage-$stage" >"$output" 2>&1; then
    echo "failure stage fixture unexpectedly passed ($stage)" >&2; exit 1
  fi
  grep -Fx "FAILED: isolated restore fixture stage=$stage" "$output" >/dev/null || {
    echo "allowed stage was not preserved by the wrapper parser ($stage)" >&2; exit 1;
  }
  python3 - "$tmp/stage-$stage/recovery-failure.json" "$stage" <<'PY'
import json, pathlib, sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data=={"schema":"playstead.recovery-failure.v1","lane":"linux_restore_fixture","outcome":"failed","failure_stage":sys.argv[2]}
PY
  [ ! -e "$tmp/stage-$stage/recovery-e2e.json" ] || { echo "stage failure wrote the passing receipt ($stage)" >&2; exit 1; }
done
for mode in malformed missing-success-marker duplicate-success-marker duplicate-success-key; do
  output="$tmp/result-validation-$mode.out"
  if TMPDIR="$tmp" FAKE_MODE="$mode" PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/result-validation-$mode" >"$output" 2>&1; then
    echo "malformed/missing success result must be refused ($mode)" >&2; exit 1
  fi
  grep -Fx 'FAILED: isolated restore fixture stage=result-validation' "$output" >/dev/null
  python3 - "$tmp/result-validation-$mode/recovery-failure.json" <<'PY'
import json, pathlib, sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data=={"schema":"playstead.recovery-failure.v1","lane":"linux_restore_fixture","outcome":"failed","failure_stage":"result-validation"}
PY
  [ ! -e "$tmp/result-validation-$mode/recovery-e2e.json" ]
  if grep -E 'PLAYSTEAD_RECOVERY_FIXTURE_JSON=|private-path-token|private path|/Users/|game\.gba|must-not-print|token=' "$output" >/dev/null; then
    echo "malformed pass receipt escaped the private-output boundary ($mode)" >&2; exit 1
  fi
done
if find "$tmp" -maxdepth 1 -type d -name 'playstead-recovery-fixture.*' | grep . >/dev/null; then
  echo "temporary private output survived cleanup" >&2; exit 1
fi
if "$coordinator" --output relative >/dev/null 2>&1 || "$coordinator" --output "$tmp/pass" >/dev/null 2>&1; then
  echo "unsafe evidence output must be refused" >&2; exit 1
fi
workflow="$root/../.github/workflows/ci.yml"
grep -Fq '  recovery-fixture:' "$workflow"
grep -Fq 'timeout-minutes: 35' "$workflow"
grep -Fq 'timeout 20m bash playstead-server/scripts/ci/recovery-fixture.sh --output' "$workflow"
grep -Fq 'path: ${{ runner.temp }}/recovery-sanitized/recovery-*.json' "$workflow"
grep -Fq 'retention-days: 7' "$workflow"
grep -Fq 'always()' "$workflow"
python3 - "$workflow" <<'PY'
import pathlib, sys, yaml
jobs=yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())["jobs"]
job=jobs["recovery-fixture"]
assert job["defaults"]["run"]["working-directory"] == "."
assert any(s.get("name") == "Compile recovery task and dependencies" and s.get("run") == "mix compile --warnings-as-errors" and s.get("working-directory") == "playstead-server" for s in job["steps"])
assert not job.get("needs")
restore=next(s for s in job["steps"] if s.get("name") == "Run isolated restore fixture")
assert restore.get("id") == "restore"
assert 'timeout 20m bash playstead-server/scripts/ci/recovery-fixture.sh --output "$RUNNER_TEMP/recovery-input/evidence"' in restore["run"]
sanitize=next(s for s in job["steps"] if s.get("name") == "Sanitize recovery evidence")
assert sanitize.get("id") == "sanitize"
assert sanitize.get("if") == "${{ always() && (steps.restore.outcome == 'success' || steps.restore.outcome == 'failure') }}"
assert sanitize.get("env", {}).get("RESTORE_OUTCOME") == "${{ steps.restore.outcome }}"
assert 'sanitize-evidence.sh --input "$RUNNER_TEMP/recovery-input" --output "$RUNNER_TEMP/recovery-sanitized"' in sanitize["run"]
assert 'test -s "$RUNNER_TEMP/recovery-sanitized/recovery-e2e.json"' in sanitize["run"]
assert 'test -s "$RUNNER_TEMP/recovery-sanitized/recovery-failure.json"' in sanitize["run"]
upload=next(s for s in job["steps"] if s.get("name") == "Upload sanitized Linux recovery evidence")
assert upload.get("if") == "${{ always() && steps.sanitize.outcome == 'success' }}"
assert upload.get("uses") == "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"
assert upload.get("with", {}).get("path") == "${{ runner.temp }}/recovery-sanitized/recovery-*.json"
assert upload["with"].get("if-no-files-found") == "error"
assert "recovery-input" not in upload["with"]["path"]
assert not job.get("continue-on-error")
assert all(not step.get("continue-on-error") for step in job["steps"])
PY
echo "recovery fixture coordinator contracts passed (fake command only)"
