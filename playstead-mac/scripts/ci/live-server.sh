#!/usr/bin/env bash
set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 1; }

[ "$#" -ge 1 ] || die "usage: live-server.sh prepare|second|verify ROOT"
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
  verify)
    python3 - "$root" "$(dirname "$PLAYSTEAD_MAC_CI_ROOT")/phoenix.log" <<'PY'
import pathlib, sqlite3, sys
root, log_path = map(pathlib.Path, sys.argv[1:])
if not root.is_dir() or not log_path.is_file():
    raise SystemExit("live-server verification inputs are missing")

lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
snapshot_success = 0
pending_snapshot = False
blob_requests = 0
for line in lines:
    if " /api/v1/blobs/" in line:
        blob_requests += 1
    if "GET /api/v1/snapshot" in line:
        pending_snapshot = True
        continue
    if pending_snapshot and "Sent 200" in line:
        snapshot_success += 1
        pending_snapshot = False
    elif pending_snapshot and any(method in line for method in ("GET /", "POST /", "PUT /", "PATCH /", "DELETE /")):
        pending_snapshot = False

if snapshot_success != 2:
    raise SystemExit(f"expected exactly two successful snapshot requests, got {snapshot_success}")
if blob_requests != 0:
    raise SystemExit(f"expected zero blob requests, got {blob_requests}")

database = root / "playstead.sqlite3"
with sqlite3.connect(database) as connection:
    cursor = connection.execute("SELECT cursor FROM sync_cursor WHERE id = 1").fetchone()
    titles = {row[0] for row in connection.execute("SELECT display_title FROM catalogue_entries")}
if not cursor or not cursor[0]:
    raise SystemExit("stored snapshot cursor is empty")
if titles != {"Playstead CI Sentinel One", "Playstead CI Sentinel Two"}:
    raise SystemExit("fresh mirror does not contain exactly both synthetic sentinels")
for name in ("objects", "partials"):
    directory = root / name
    if not directory.is_dir() or any(directory.iterdir()):
        raise SystemExit(f"{name} must exist and remain empty")
print("live-server: two snapshots, Keychain relaunch, and zero blob routes verified")
PY
    ;;
  *) die "unknown live-server action" ;;
esac
