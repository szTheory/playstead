#!/usr/bin/env bash
set -euo pipefail

# Only the public hosted Mac job owns this guest. Cross-architecture QEMU
# uses software emulation, so Apple's unsupported nested virtualization is
# not needed. The actual scanned Linux decoder and container limits remain.
[[ "${GITHUB_ACTIONS:-}" = true && "${RUNNER_OS:-}" = macOS &&
   "${GITHUB_REPOSITORY:-}" = szTheory/playstead && "$(uname -m)" = arm64 ]] || {
  echo 'hosted decoder runtime requires the task hosted Apple Silicon runner' >&2
  exit 2
}
SCRIPT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_ROOT/.." && pwd -P)"
RUNTIME_ROOT="${RUNNER_TEMP:?}/playstead-media-runtime"
export COLIMA_HOME="$RUNTIME_ROOT/colima"
export DOCKER_CONFIG="$RUNTIME_ROOT/docker-client"
export DOCKER_HOST="unix://$COLIMA_HOME/playstead-media-ci/docker.sock"
stage=validate-action
report_failure_stage() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    printf 'hosted-decoder-stage=%s exit=%s\n' "$stage" "$status" >&2
  fi
  return "$status"
}
trap report_failure_stage EXIT

case "${1:-}" in
  start)
    [[ "$#" = 2 && "$2" = "$RUNNER_TEMP/playstead-media-decoder-runtime" ]] || exit 2
    artifact="$2"
    stage=create-owned-home
    [ ! -e "$RUNTIME_ROOT" ] || { echo 'hosted decoder runtime root already exists' >&2; exit 1; }
    mkdir -m 0700 "$RUNTIME_ROOT"
    mkdir -m 0700 "$COLIMA_HOME" "$DOCKER_CONFIG"
    context="$REPO_ROOT/playstead-server/ops/media-decoder"
    generated="$context/build/generated"
    stage=generated-context-precondition
    [ ! -e "$generated" ] || { echo 'unexpected existing generated decoder context' >&2; exit 1; }
    stage=validate-artifact
    python3 - "$artifact" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
required = [root / name for name in ("decoder-image.tar", "decoder-scan-receipt.json", "decoder-trivy.json")]
required += [root / "generated/SOURCE-PINS.json", root / "generated/packages/decoder-signing.rsa.pub"]
for path in required:
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise SystemExit("decoder runtime artifact is incomplete")
for path in root.rglob("*"):
    if path.is_symlink() or (path.is_file() and path.name.endswith(".rsa")):
        raise SystemExit("decoder runtime artifact contains an unsafe entry")
PY
    mkdir -p "$generated"
    stage=restore-public-context
    cp -R "$artifact/generated/." "$generated/"
    image_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image_id"])' "$artifact/decoder-scan-receipt.json")"
    [[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
    stage=verify-scan-custody
    python3 "$REPO_ROOT/scripts/ci/media-decoder-evidence.py" verify \
      --receipt "$artifact/decoder-scan-receipt.json" --report "$artifact/decoder-trivy.json" \
      --context "$context" --image-id "$image_id"
    stage=install-runtime
    HOMEBREW_NO_AUTO_UPDATE=1 brew install docker colima qemu
    # The separate task home and explicit socket never select another daemon.
    stage=start-owned-guest
    colima start playstead-media-ci --vm-type qemu --arch x86_64 --cpu-type max --cpu 1 --memory 2 --disk 12 \
      --mount none --ssh-config=false --activate=false
    stage=verify-daemon
    [ "$(docker info --format '{{.OSType}}/{{.Architecture}}')" = linux/x86_64 ]
    stage=load-qualified-image
    docker image load --input "$artifact/decoder-image.tar" >/dev/null
    stage=verify-image-custody
    [ "$(docker image inspect --format '{{.Id}}' "$image_id")" = "$image_id" ]
    stage=publish-owned-runtime
    printf 'DOCKER_HOST=%s\nDOCKER_CONFIG=%s\nPLAYSTEAD_MEDIA_DECODER_EVIDENCE_DIR=%s\nPLAYSTEAD_MEDIA_DECODER_IMAGE=%s\n' \
      "$DOCKER_HOST" "$DOCKER_CONFIG" "$artifact" "$image_id" >>"${GITHUB_ENV:?}"
    ;;
  cleanup)
    stage=cleanup-owned-guest
    [ "$#" = 1 ] || exit 2
    if [ -d "$COLIMA_HOME/playstead-media-ci" ]; then
      colima delete playstead-media-ci --force --data
    fi
    [ ! -e "$RUNTIME_ROOT" ] || rm -rf -- "$RUNTIME_ROOT"
    ;;
  *) exit 2 ;;
esac
