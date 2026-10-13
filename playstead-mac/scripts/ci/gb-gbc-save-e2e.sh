#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case_name=""
all_cases=false
local_no_hid=false
build_only=false
reuse_build=false
self_test_cleanup=""

usage() {
  printf '%s\n' 'Usage: gb-gbc-save-e2e.sh (--case gb-mbc1-8k|gbc-mbc5-32k|gbc-mbc3-rtc|aerevenadvance | --all-cases) [--local-no-hid] [--build-only|--reuse-build]'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --case)
      [ -n "${2:-}" ] || { usage >&2; exit 2; }
      [ -z "$case_name" ] && [ "$all_cases" = false ] || { printf '%s\n' 'duplicate or conflicting fixture selector' >&2; exit 2; }
      case_name="$2"
      shift 2
      ;;
    --all-cases)
      [ -z "$case_name" ] && [ "$all_cases" = false ] || { printf '%s\n' 'duplicate or conflicting fixture selector' >&2; exit 2; }
      all_cases=true
      shift
      ;;
    --local-no-hid)
      [ "$local_no_hid" = false ] || { printf '%s\n' 'duplicate --local-no-hid' >&2; exit 2; }
      local_no_hid=true
      shift
      ;;
    --build-only)
      [ "$build_only" = false ] && [ "$reuse_build" = false ] || { printf '%s\n' 'duplicate or conflicting build mode' >&2; exit 2; }
      build_only=true
      shift
      ;;
    --reuse-build)
      [ "$build_only" = false ] && [ "$reuse_build" = false ] || { printf '%s\n' 'duplicate or conflicting build mode' >&2; exit 2; }
      reuse_build=true
      shift
      ;;
    --self-test-cleanup-failure|--self-test-cleanup-interrupt)
      [ -z "$self_test_cleanup" ] || { printf '%s\n' 'duplicate cleanup self-test mode' >&2; exit 2; }
      self_test_cleanup="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unsupported argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$all_cases" = false ]; then
  [ -n "$case_name" ] || { usage >&2; exit 2; }
  [[ "$case_name" =~ ^(gb-mbc1-8k|gbc-mbc5-32k|gbc-mbc3-rtc|aerevenadvance)$ ]] || { printf 'unsupported fixture case: %s\n' "$case_name" >&2; exit 2; }
else
  case_name="all"
fi

runner="${SCRIPT_DIR}/run-mac-verification.sh"
selectors=()
case "$case_name" in
  gb-mbc1-8k) selectors=(PlaysteadUITests/GBGBCSaveContinuityTests/testGBMBC1FreshProfileGameReadback) ;;
  gbc-mbc5-32k) selectors=(PlaysteadUITests/GBGBCSaveContinuityTests/testGBCMBC5FreshProfileGameReadback) ;;
  gbc-mbc3-rtc) selectors=(PlaysteadUITests/GBGBCSaveContinuityTests/testGBCMBC3RTCFreshProfileGameReadback) ;;
  aerevenadvance) selectors=(PlaysteadUITests/GBGBCSaveContinuityTests/testAerevenAdvanceGBARestoreMenuRegression) ;;
  all)
    selectors=(
      PlaysteadUITests/GBGBCSaveContinuityTests/testGBMBC1FreshProfileGameReadback
      PlaysteadUITests/GBGBCSaveContinuityTests/testGBCMBC5FreshProfileGameReadback
      PlaysteadUITests/GBGBCSaveContinuityTests/testGBCMBC3RTCFreshProfileGameReadback
      PlaysteadUITests/GBGBCSaveContinuityTests/testAerevenAdvanceGBARestoreMenuRegression
    )
    ;;
esac
cleanup_helper="${SCRIPT_DIR}/cleanup-gb-gbc-save-children.py"
managed_executable="${HOME}/Library/Application Support/Playstead/emulators/mgba/0.10.5/mGBA.app/Contents/MacOS/mGBA"
task_root="$(mktemp -d "${TMPDIR:-/tmp}/playstead-gb-save-e2e.XXXXXX")"
run_id="${task_root##*.}"
chmod 700 "$task_root"

cleanup_task() {
  local result=$?
  trap - EXIT INT TERM
  local cleanup_result=0
  for fixture in gb-mbc1-8k gbc-mbc5-32k gbc-mbc3-rtc aerevenadvance; do
    python3 "$cleanup_helper" --executable "$managed_executable" --profile-root "$task_root/$fixture/source-profile" || cleanup_result=$?
    python3 "$cleanup_helper" --executable "$managed_executable" --profile-root "$task_root/$fixture/target-profile" || cleanup_result=$?
  done
  if [ "$cleanup_result" -eq 0 ]; then
    for fixture in gb-mbc1-8k gbc-mbc5-32k gbc-mbc3-rtc aerevenadvance; do
      local fixture_root="${SCRIPT_DIR}/../../.local/gb-gbc-spike/$fixture"
      [ "$fixture" = "aerevenadvance" ] && continue
      for phase in source target; do
        local label="playstead-gb-${phase}-${run_id}"
        rm -f "$fixture_root/${label}-oracle.json" \
          "$fixture_root/screenshots/${label}-before.png" \
          "$fixture_root/screenshots/${label}-after.png"
        if [ "$fixture" = "gbc-mbc3-rtc" ]; then
          rm -f "$fixture_root/${label}-rtc-start.json" "$fixture_root/${label}-rtc-end.json"
        fi
      done
    done
    rm -rf "$task_root"
    printf '%s\n' 'gb-gbc-save-e2e: private profile cleanup verified'
  else
    printf 'gb-gbc-save-e2e: retained private profile after failed child cleanup: %s\n' "$task_root" >&2
    result=1
  fi
  exit "$result"
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup_task EXIT

for fixture in gb-mbc1-8k gbc-mbc5-32k gbc-mbc3-rtc aerevenadvance; do
  mkdir -p "$task_root/$fixture/source-profile" "$task_root/$fixture/target-profile"
  if ! python3 "$cleanup_helper" --executable "$managed_executable" --profile-root "$task_root/$fixture/source-profile" --preflight \
    || ! python3 "$cleanup_helper" --executable "$managed_executable" --profile-root "$task_root/$fixture/target-profile" --preflight; then
    printf 'gb-gbc-save-e2e: stale task-owned mGBA child detected for %s; inspect inventory before retry\n' "$fixture" >&2
    exit 1
  fi
done
registry="${PLAYSTEAD_AEREVEN_FIXTURE_REGISTRY:-${SCRIPT_DIR}/../../.local/test-fixtures/aerevenadvance.json}"
if [ "$case_name" = "all" ] || [ "$case_name" = "aerevenadvance" ]; then
  python3 "${SCRIPT_DIR}/prepare-aereven-fixture.py" "$registry" "$task_root/aereven-fixture"
  registry="$task_root/aereven-fixture/aerevenadvance.json"
  python3 - "$registry" <<'PY'
import hashlib, json, os, pathlib, stat, sys
registry = pathlib.Path(sys.argv[1])
if registry.is_symlink() or not registry.is_file() or stat.S_IMODE(registry.stat().st_mode) != 0o600:
    raise SystemExit("aereven registry preflight failed closed")
data = json.loads(registry.read_text(encoding="utf-8"))
game, save = data.get("game", {}), data.get("persistent_save", {})
fixture_root = registry.parent.resolve()
expected = (
    (game, "de968dca9f86f1648bb2bb992d6ce4aa4007d3bf7a064b4bbfd82a96e29409ab", 5564940),
    (save, "8efc60d327e3c485e0d5bdcd93503059d1ea9f92dcd8f14813b39f689e5aa9cf", 32768),
)
if data.get("fixture_id") != "aerevenadvance" or data.get("system_id") != "gba":
    raise SystemExit("aereven registry identity rejected")
for row, digest, size in expected:
    path = pathlib.Path(row.get("path", ""))
    if path.is_symlink() or not path.is_file() or path.stat().st_size != size or row.get("size_bytes") != size:
        raise SystemExit("aereven original byte identity rejected")
    if row.get("sha256") != digest or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit("aereven original digest rejected")
    if path.parent.resolve() != fixture_root or stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise SystemExit("aereven isolated fixture path or mode rejected")
print("aereven registry and original byte lineage verified")
PY
  export PLAYSTEAD_AEREVEN_FIXTURE_REGISTRY="$registry"
fi
export PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT="$task_root"
export PLAYSTEAD_GB_GBC_SAVE_E2E_RUN_ID="$run_id"
export PLAYSTEAD_GB_GBC_SAVE_E2E_CASES="$case_name"
if [ "$self_test_cleanup" = "--self-test-cleanup-failure" ]; then
  exit 42
elif [ "$self_test_cleanup" = "--self-test-cleanup-interrupt" ]; then
  kill -INT "$$"
  sleep 10
  exit 99
fi
if [ "$local_no_hid" = true ]; then
  if [ "$build_only" = true ]; then
    PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 "$runner" --layers recovery --build-only --only-testing "${selectors[@]}"
  elif [ "$reuse_build" = true ]; then
    PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 "$runner" --layers recovery --test-without-building --only-testing "${selectors[@]}"
  else
    PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 "$runner" --layers recovery --only-testing "${selectors[@]}"
  fi
else
  if [ "$build_only" = true ]; then
    "$runner" --layers recovery --build-only --only-testing "${selectors[@]}"
  elif [ "$reuse_build" = true ]; then
    "$runner" --layers recovery --test-without-building --only-testing "${selectors[@]}"
  else
    "$runner" --layers recovery --only-testing "${selectors[@]}"
  fi
fi
