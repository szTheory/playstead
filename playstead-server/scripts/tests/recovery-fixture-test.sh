#!/usr/bin/env bash
# Parser/command-boundary contract only; fake mix never invokes Docker.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
coordinator="$root/scripts/ci/recovery-fixture.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-fixture-test.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
"$coordinator" --self-test
python3 - "$root/lib/mix/tasks/playstead.restore.ex" <<'PY'
import pathlib, sys
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
  unknown-marker) echo 'PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=private-path'; exit 1 ;;
  sentinels) echo 'private path /Users/private/game.gba token=must-not-print'; exit 1 ;;
esac
if [ "${FAKE_MODE:-pass}" = malformed ]; then echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"secret":"bad"}'; exit 0; fi
echo 'private fixture path /Users/owner/game.gba'
echo 'PLAYSTEAD_RECOVERY_FIXTURE_JSON={"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}'
EOF
chmod 700 "$tmp/bin/mix"
allowed_stages=(source-compose-startup source-readiness source-fixture-create source-dump backup-publication target-restore target-cleanup result-validation)
TMPDIR="$tmp" PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/pass"
python3 - "$tmp/pass/recovery-e2e.json" <<'PY'
import json, pathlib, sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(data)=={"schema_version","run_id","lane","stages","outcome"}
assert data["outcome"]=="passed"
PY
for mode in fail missing-marker duplicate-marker unknown-marker sentinels; do
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
  [ ! -e "$tmp/fail-$mode" ] || { echo "failure emitted evidence ($mode)" >&2; exit 1; }
done
for stage in "${allowed_stages[@]}"; do
  output="$tmp/stage-$stage.out"
  if TMPDIR="$tmp" FAKE_MODE="stage-$stage" PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/stage-$stage" >"$output" 2>&1; then
    echo "failure stage fixture unexpectedly passed ($stage)" >&2; exit 1
  fi
  grep -Fx "FAILED: isolated restore fixture stage=$stage" "$output" >/dev/null || {
    echo "allowed stage was not preserved by the wrapper parser ($stage)" >&2; exit 1;
  }
  [ ! -e "$tmp/stage-$stage" ] || { echo "stage failure emitted evidence ($stage)" >&2; exit 1; }
done
if TMPDIR="$tmp" FAKE_MODE=malformed PATH="$tmp/bin:$PATH" "$coordinator" --output "$tmp/malformed" >"$tmp/malformed.out" 2>&1; then
  echo "malformed result must be refused" >&2; exit 1
fi
grep -Fx 'FAILED: isolated restore fixture stage=result-validation' "$tmp/malformed.out" >/dev/null
[ ! -e "$tmp/malformed" ]
if grep -F 'PLAYSTEAD_RECOVERY_FIXTURE_JSON=' "$tmp/malformed.out" >/dev/null; then
  echo "malformed pass receipt escaped the private-output boundary" >&2; exit 1
fi
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
