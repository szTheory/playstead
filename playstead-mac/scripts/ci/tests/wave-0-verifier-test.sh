#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/../run-mac-verification.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-wave0-tests.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

expect_pass() {
  local name="$1"
  shift
  if "$@" >"$TMP_ROOT/${name}.out" 2>"$TMP_ROOT/${name}.err"; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s unexpectedly failed\n' "$name" >&2
    cat "$TMP_ROOT/${name}.err" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

expect_fail() {
  local name="$1"
  shift
  if "$@" >"$TMP_ROOT/${name}.out" 2>"$TMP_ROOT/${name}.err"; then
    printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

write_result_fixture() {
  local path="$1"
  local status="${2:-passed}"
  local skipped="${3:-false}"
  local execution_count="${4:-1}"
  local source="${5:-github-hosted}"
  cat >"$path" <<JSON
{
  "schema_version": 1,
  "source": "$source",
  "run": {
    "workflow": "ci",
    "event": "pull_request",
    "ref": "refs/pull/42/merge",
    "head_sha": "0123456789abcdef0123456789abcdef01234567",
    "run_id": "9001"
  },
  "canaries": [
    {
      "identifier": "PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner",
      "discovered": true,
      "execution_count": $execution_count,
      "skipped": $skipped,
      "outcome": "$status"
    },
    {
      "identifier": "PlaysteadUITests.HostedRunnerCanaryTests/testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls",
      "discovered": true,
      "execution_count": 1,
      "skipped": false,
      "outcome": "passed"
    },
    {
      "identifier": "PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice",
      "discovered": true,
      "execution_count": 1,
      "skipped": false,
      "outcome": "passed"
    },
    {
      "identifier": "PlaysteadTests.SnapshotHarnessCanaryTests/testIntentionalMismatchProducesReviewableTriplet",
      "discovered": true,
      "execution_count": 1,
      "skipped": false,
      "outcome": "passed"
    },
    {
      "identifier": "native.postgresql17-phoenix-health",
      "discovered": true,
      "execution_count": 1,
      "skipped": false,
      "outcome": "passed"
    }
  ],
  "fingerprint": {
    "runner_image": "macos-26",
    "runner_image_version": "20260831.1",
    "architecture": "arm64",
    "macos": "26.6.2",
    "macos_build": "25G83",
    "xcode": ["Xcode 26.6", "Build version 17F113"]
  },
  "native_health": {
    "postgresql_major": 17,
    "phoenix_healthy": true,
    "loopback_only": true,
    "cleanup_complete": true
  },
  "snapshot_triplets": ["actual.png", "diff.png", "reference.png"],
  "snapshot_calibration": {"mutation_failed": true, "noise_passed": true},
  "linux_jobs": {"test": "success", "compose_smoke": "success"}
}
JSON
}

write_run_fixture() {
  local path="$1"
  local status="${2:-completed}"
  local conclusion="${3:-success}"
  cat >"$path" <<JSON
{
  "databaseId": 9001,
  "workflowName": "ci",
  "event": "pull_request",
  "headBranch": "feature/mac-ci",
  "headSha": "0123456789abcdef0123456789abcdef01234567",
  "status": "$status",
  "conclusion": "$conclusion",
  "url": "https://github.example.invalid/runs/9001"
}
JSON
}

verify_result() {
  "$VERIFIER" --verify-result "$1" \
    --required-canary PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner \
    --expected-workflow ci \
    --expected-event pull_request \
    --expected-ref refs/pull/42/merge \
    --expected-sha 0123456789abcdef0123456789abcdef01234567 \
    --expected-run-id 9001
}

verify_run() {
  "$VERIFIER" --validate-hosted-run "$1" \
    --expected-workflow ci \
    --expected-event pull_request \
    --expected-ref feature/mac-ci \
    --expected-sha 0123456789abcdef0123456789abcdef01234567 \
    --expected-run-id 9001
}

verify_task2_result() {
  "$VERIFIER" --verify-result "$1" \
    --required-canary PlaysteadUITests.HostedRunnerCanaryTests/testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls \
    --required-canary PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice \
    --expected-workflow ci \
    --expected-event pull_request \
    --expected-ref refs/pull/42/merge \
    --expected-sha 0123456789abcdef0123456789abcdef01234567 \
    --expected-run-id 9001
}

verify_task3_result() {
  "$VERIFIER" --verify-result "$1" \
    --required-canary PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner \
    --required-canary PlaysteadUITests.HostedRunnerCanaryTests/testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls \
    --required-canary PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice \
    --required-canary PlaysteadTests.SnapshotHarnessCanaryTests/testIntentionalMismatchProducesReviewableTriplet \
    --required-canary native.postgresql17-phoenix-health \
    --expected-workflow ci \
    --expected-event pull_request \
    --expected-ref refs/pull/42/merge \
    --expected-sha 0123456789abcdef0123456789abcdef01234567 \
    --expected-run-id 9001
}

valid_result="$TMP_ROOT/valid-result.json"
write_result_fixture "$valid_result"
expect_pass result_valid verify_result "$valid_result"

for variant in missing skipped failed zero local; do
  fixture="$TMP_ROOT/result-${variant}.json"
  case "$variant" in
    missing) printf '{"schema_version":1,"source":"github-hosted","run":{},"canaries":[]}' >"$fixture" ;;
    skipped) write_result_fixture "$fixture" passed true 1 ;;
    failed) write_result_fixture "$fixture" failed false 1 ;;
    zero) write_result_fixture "$fixture" passed false 0 ;;
    local) write_result_fixture "$fixture" passed false 1 local ;;
  esac
  expect_fail "result_${variant}" verify_result "$fixture"
done

wrong_sha="$TMP_ROOT/result-wrong-sha.json"
write_result_fixture "$wrong_sha"
python3 - "$wrong_sha" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["run"]["head_sha"] = "ffffffffffffffffffffffffffffffffffffffff"
json.dump(d, open(p, "w"))
PY
expect_fail result_wrong_sha verify_result "$wrong_sha"
expect_fail result_malformed verify_result /dev/null

expect_pass task2_valid verify_task2_result "$valid_result"
for identifier in \
  PlaysteadUITests.HostedRunnerCanaryTests/testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls \
  PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice
do
  fixture="$TMP_ROOT/task2-skipped-$(basename "$identifier").json"
  cp "$valid_result" "$fixture"
  python3 - "$fixture" "$identifier" <<'PY'
import json, sys
p, identifier = sys.argv[1:]
d = json.load(open(p))
for record in d["canaries"]:
    if record["identifier"] == identifier:
        record["skipped"] = True
json.dump(d, open(p, "w"))
PY
  expect_fail "task2_skipped_$(basename "$identifier")" verify_task2_result "$fixture"
done

expect_pass task3_valid verify_task3_result "$valid_result"
for status_variant in missing skipped failed; do
for identifier in \
  PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner \
  PlaysteadUITests.HostedRunnerCanaryTests/testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls \
  PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice \
  PlaysteadTests.SnapshotHarnessCanaryTests/testIntentionalMismatchProducesReviewableTriplet \
  native.postgresql17-phoenix-health
do
  fixture="$TMP_ROOT/task3-${status_variant}-$(basename "$identifier").json"
  cp "$valid_result" "$fixture"
  python3 - "$fixture" "$identifier" "$status_variant" <<'PY'
import json, sys
p, identifier, variant = sys.argv[1:]
d = json.load(open(p))
if variant == "missing":
    d["canaries"] = [record for record in d["canaries"] if record["identifier"] != identifier]
else:
    for record in d["canaries"]:
        if record["identifier"] == identifier:
            if variant == "skipped": record["skipped"] = True
            elif variant == "failed": record["outcome"] = "failed"
json.dump(d, open(p, "w"))
PY
  expect_fail "task3_${status_variant}_$(basename "$identifier")" verify_task3_result "$fixture"
done
done

for variant in native_missing native_postgres native_health native_loopback linux_test linux_compose snapshot_triplet snapshot_calibration fingerprint cleanup secret_key; do
  fixture="$TMP_ROOT/task3-${variant}.json"
  cp "$valid_result" "$fixture"
  python3 - "$fixture" "$variant" <<'PY'
import json, sys
p, variant = sys.argv[1:]
d = json.load(open(p))
if variant == "native_missing": del d["native_health"]
elif variant == "native_postgres": d["native_health"]["postgresql_major"] = 16
elif variant == "native_health": d["native_health"]["phoenix_healthy"] = False
elif variant == "native_loopback": d["native_health"]["loopback_only"] = False
elif variant == "linux_test": d["linux_jobs"]["test"] = "failure"
elif variant == "linux_compose": d["linux_jobs"]["compose_smoke"] = "failure"
elif variant == "snapshot_triplet": d["snapshot_triplets"] = ["reference.png", "actual.png"]
elif variant == "snapshot_calibration": d["snapshot_calibration"]["noise_passed"] = False
elif variant == "fingerprint": d["fingerprint"]["architecture"] = "x86_64"
elif variant == "cleanup": d["native_health"]["cleanup_complete"] = False
elif variant == "secret_key": d["native_health"]["database_url"] = "redacted-but-forbidden"
json.dump(d, open(p, "w"))
PY
  expect_fail "task3_${variant}" verify_task3_result "$fixture"
done

valid_run="$TMP_ROOT/valid-run.json"
write_run_fixture "$valid_run"
expect_pass hosted_run_valid verify_run "$valid_run"

for variant in queued failed wrong_id wrong_sha wrong_event wrong_ref; do
  fixture="$TMP_ROOT/run-${variant}.json"
  write_run_fixture "$fixture"
  python3 - "$fixture" "$variant" <<'PY'
import json, sys
p, variant = sys.argv[1:]
d = json.load(open(p))
if variant == "queued": d["status"] = "queued"
elif variant == "failed": d["conclusion"] = "failure"
elif variant == "wrong_id": d["databaseId"] = 9002
elif variant == "wrong_sha": d["headSha"] = "f" * 40
elif variant == "wrong_event": d["event"] = "workflow_dispatch"
elif variant == "wrong_ref": d["headBranch"] = "main"
json.dump(d, open(p, "w"))
PY
  expect_fail "hosted_${variant}" verify_run "$fixture"
done

if (( FAIL_COUNT > 0 )); then
  printf '%d verifier contract tests failed (%d passed)\n' "$FAIL_COUNT" "$PASS_COUNT" >&2
  exit 1
fi

printf 'wave-0 verifier contract: %d checks passed\n' "$PASS_COUNT"
