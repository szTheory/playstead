#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="${SCRIPT_DIR}/run-mac-verification.sh"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-build-only.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin"
cat >"$temporary/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$FAKE_XCODEBUILD_ARGS"
SH
chmod 700 "$temporary/bin/xcodebuild"

args_file="$temporary/xcodebuild.args"
PLAYSTEAD_CI_BUILD_ROOT="$temporary/build" FAKE_XCODEBUILD_ARGS="$args_file" \
  PATH="$temporary/bin:$PATH" "$runner" --layers recovery --build-only --only-testing \
  PlaysteadUITests/GBGBCSaveContinuityTests/testGBMBC1FreshProfileGameReadback

python3 - "$args_file" <<'PY'
import pathlib, sys
args = pathlib.Path(sys.argv[1]).read_bytes().decode().split("\0")[:-1]
assert args[0] == "build-for-testing", args
assert "-testPlan" in args and args[args.index("-testPlan") + 1] == "Recovery", args
assert "-only-testing:PlaysteadUITests/GBGBCSaveContinuityTests/testGBMBC1FreshProfileGameReadback" in args, args
assert "-skip-testing:PlaysteadTests" in args, args
assert not any(arg == "test" for arg in args), args
PY

set +e
PLAYSTEAD_CI_BUILD_ROOT="$temporary/reject" PATH="$temporary/bin:$PATH" \
  "$runner" --layers unit --build-only --only-testing PlaysteadTests/SmokeTests >"$temporary/reject.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || { cat "$temporary/reject.out"; exit 1; }
rg -q -- '--build-only is supported only for the recovery layer' "$temporary/reject.out"
printf '%s\n' 'recovery build-only uses guarded cached build path and rejects other layers'
