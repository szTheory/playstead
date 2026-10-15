#!/usr/bin/env bash
set -euo pipefail

# Same-workflow transport only: consumers still verify the exact production
# context, strict scan policy and immutable local image before activation.
[[ "${GITHUB_ACTIONS:-}" = true && "${RUNNER_OS:-}" = Linux &&
   "${GITHUB_REPOSITORY:-}" = szTheory/playstead ]] || exit 2
[[ "$#" = 1 && "$1" = "${RUNNER_TEMP:?}/playstead-media-decoder-runtime" ]] || exit 2
artifact="$1"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
context="$REPO_ROOT/playstead-server/ops/media-decoder"
generated="$context/build/generated"
[ ! -e "$generated" ] || { echo 'unexpected existing generated decoder context' >&2; exit 1; }

image_id="$(python3 - "$artifact" <<'PY'
import hashlib, json, pathlib, re, sys, tarfile
root = pathlib.Path(sys.argv[1])
required = [root / name for name in (
    "decoder-image.tar", "decoder-scan-receipt.json", "decoder-trivy.json", "decoder-scan-result.json",
    "generated/SOURCE-PINS.json", "generated/packages/decoder-signing.rsa.pub",
)]
if root.is_symlink() or any(p.is_symlink() or not p.is_file() or p.stat().st_size == 0 for p in required):
    raise SystemExit("decoder runtime artifact is incomplete")
if any(p.is_symlink() or (p.is_file() and p.name.endswith(".rsa")) for p in root.rglob("*")):
    raise SystemExit("decoder runtime artifact contains an unsafe entry")
image_id = json.loads((root / "decoder-scan-receipt.json").read_text())["image_id"]
if not isinstance(image_id, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
    raise SystemExit("decoder runtime image ID is malformed")
with tarfile.open(root / "decoder-image.tar") as archive:
    members = archive.getmembers()
    names = [m.name for m in members]
    if len(members) > 10000 or len(set(names)) != len(names) or any(
        pathlib.PurePosixPath(m.name).is_absolute() or ".." in pathlib.PurePosixPath(m.name).parts
        or not (m.isfile() or m.isdir()) for m in members
    ):
        raise SystemExit("decoder image archive has unsafe entries")
    manifest_member = archive.getmember("manifest.json")
    if manifest_member.size > 1024 * 1024:
        raise SystemExit("decoder image manifest exceeds its bound")
    manifests = json.load(archive.extractfile(manifest_member))
    if not isinstance(manifests, list) or len(manifests) != 1:
        raise SystemExit("decoder image archive must contain exactly one image")
    config_member = archive.getmember(manifests[0]["Config"])
    if config_member.size > 1024 * 1024:
        raise SystemExit("decoder image configuration exceeds its bound")
    config_bytes = archive.extractfile(config_member).read()
    if "sha256:" + hashlib.sha256(config_bytes).hexdigest() != image_id:
        raise SystemExit("decoder image archive differs from the scanned image")
print(image_id)
PY
)"
mkdir -p "$generated"
cp -R "$artifact/generated/." "$generated/"
python3 "$REPO_ROOT/scripts/ci/media-decoder-evidence.py" verify \
  --receipt "$artifact/decoder-scan-receipt.json" --report "$artifact/decoder-trivy.json" \
  --context "$context" --image-id "$image_id" >/dev/null
docker image load --input "$artifact/decoder-image.tar" >/dev/null
[ "$(docker image inspect --format '{{.Id}}' "$image_id")" = "$image_id" ]
printf '%s\n' "$image_id"
