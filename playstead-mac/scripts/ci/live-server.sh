#!/usr/bin/env bash
set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 1; }

[ "$#" -ge 1 ] || die "usage: live-server.sh prepare|second ROOT"
action="$1"
root="${2:-}"
[ -n "$root" ] && [ "${root#/}" != "$root" ] || die "an absolute run-owned root is required"
[ -n "${PLAYSTEAD_MAC_CI_ROOT:-}" ] || die "PLAYSTEAD_MAC_CI_ROOT is required"

server_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../playstead-server" && pwd)"
control="$root/control"
mkdir -p "$control"
chmod 0700 "$root" "$control"

case "$action" in
  prepare)
    first="$control/first-sentinel.json"
    request="$control/pairing-request.json"
    device_code="$control/device-code"
    handoff="$root/credential-handoff.json"

    (cd "$server_root" && mix playstead.mac_ci_fixture provision --output "$first") >/dev/null

    python3 - "$request" "$device_code" <<'PY'
import json, os, pathlib, secrets, sys, urllib.request
request_path, code_path = map(pathlib.Path, sys.argv[1:])
device_code = secrets.token_urlsafe(32)
body = json.dumps({
    "device_code": device_code,
    "device_name": "Playstead Hosted Mac",
    "platform": "macOS CI",
    "app_version": "1",
    "capabilities": {},
}).encode()
req = urllib.request.Request("http://127.0.0.1:4010/api/v1/device-pairing/requests", data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=10) as response:
    payload = response.read()
if len(payload) > 4096:
    raise SystemExit("pairing response exceeded bound")
request_path.write_bytes(payload)
code_path.write_text(device_code, encoding="utf-8")
os.chmod(request_path, 0o600)
os.chmod(code_path, 0o600)
PY

    request_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$request")"
    display_code="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["display_code"])' "$request")"
    (cd "$server_root" && mix playstead.mac_ci_fixture approve --request-id "$request_id" --display-code "$display_code" --device-label "Playstead Hosted Mac") >/dev/null

    python3 - "$request" "$device_code" "$handoff" <<'PY'
import json, os, pathlib, sys, urllib.request
request_path, code_path, handoff_path = map(pathlib.Path, sys.argv[1:])
request_id = json.loads(request_path.read_text())["id"]
body = json.dumps({"device_code": code_path.read_text()}).encode()
url = f"http://127.0.0.1:4010/api/v1/device-pairing/requests/{request_id}/redeem"
req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=10) as response:
    redeemed = json.loads(response.read())
handoff = {
    "device_id": redeemed["device_id"],
    "credential": redeemed["credential"],
    "base_url": "http://127.0.0.1:4010",
}
handoff_path.write_text(json.dumps(handoff), encoding="utf-8")
os.chmod(handoff_path, 0o600)
request_path.unlink()
code_path.unlink()
PY
    ;;
  second)
    (cd "$server_root" && mix playstead.mac_ci_fixture second --output "$control/second-sentinel.json") >/dev/null
    ;;
  *) die "unknown live-server action" ;;
esac
