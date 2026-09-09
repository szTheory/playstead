#!/usr/bin/env bash
set -euo pipefail

action="${1:-unknown}"
stage="validate-input"
# Keep raw subprocess stderr inside the hosted runner. XCTest receives only a
# bounded stage name: no credentials, response bodies, or absolute paths.
exec 3>&2

# Raw stderr used to go straight to /dev/null so no path, credential, or
# response body could ride an XCTest assertion message into published
# evidence. That held, and cost us the diagnosis: run 34264338508 could say
# only "provision-domain" -- never which of this stage's three commands
# failed, nor why. The bytes now land in a runner-owned file that is torn
# down with the native root and never uploaded; run-mac-verification.sh
# prints a sanitized, bounded tail of it to the job log on failure. The
# XCTest channel (fd 3) is unchanged and still carries a stage name only.
fixture_diagnostic=""
diagnostic_root="${PLAYSTEAD_LIVE_SERVER_STAGE_ROOT:-}"
if [ -n "$diagnostic_root" ] && [ "${diagnostic_root#/}" != "$diagnostic_root" ] && [ -d "$diagnostic_root" ]; then
  candidate="$diagnostic_root/live-server-fixture-diagnostic"
  if (umask 077; : >>"$candidate") 2>/dev/null; then
    chmod 0600 "$candidate" 2>/dev/null || true
    fixture_diagnostic="$candidate"
  fi
fi
if [ -n "$fixture_diagnostic" ]; then
  exec 2>>"$fixture_diagnostic"
else
  exec 2>/dev/null
fi

write_failure_stage() {
  case "$stage" in
    validate-input|resolve-server-root|create-control-root|create-server-control|secure-roots) ;;
    provision-domain|request-pairing|approve-pairing|redeem-pairing|add-second-sentinel|verify-evidence) ;;
    *) return ;;
  esac

  local marker="${PLAYSTEAD_LIVE_SERVER_STAGE_FILE:-}"
  local evidence_root="${PLAYSTEAD_LIVE_SERVER_STAGE_ROOT:-}"
  [ -n "$marker" ] && [ -n "$evidence_root" ] || return
  [ "${marker#/}" != "$marker" ] && [ "${evidence_root#/}" != "$evidence_root" ] || return
  [ "$(basename "$marker")" = "live-server-failure-stage" ] || return

  local resolved_root resolved_parent temporary
  resolved_root="$(cd "$evidence_root" 2>/dev/null && pwd -P)" || return
  resolved_parent="$(cd "$(dirname "$marker")" 2>/dev/null && pwd -P)" || return
  [ "$resolved_parent" = "$resolved_root" ] || return

  temporary="${marker}.tmp.$$"
  (umask 077; printf '%s\n' "$stage" >"$temporary") || return
  chmod 0600 "$temporary" || return
  mv -f "$temporary" "$marker"
}

enter_stage() {
  stage="$1"
  write_failure_stage || true
  # A stage banner in the raw diagnostic: the sanitized tail printed on
  # failure is a tail, so without this the surviving lines can belong to an
  # earlier stage than the one the marker names.
  printf '=== stage %s ===\n' "$stage" >&2 || true
}

trap 'status=$?; if [ "$status" -ne 0 ]; then write_failure_stage || true; printf "live-server fixture failed at %s\n" "$stage" >&3; fi' EXIT
enter_stage "validate-input"

die() { exit 1; }

[ "$#" -ge 1 ] || die
root="${2:-}"
[ -n "$root" ] && [ "${root#/}" != "$root" ] || die
server_data_root="${3:-${PLAYSTEAD_MAC_CI_ROOT:-}}"
[ -n "$server_data_root" ] && [ "${server_data_root#/}" != "$server_data_root" ] || die
export PLAYSTEAD_MAC_CI_ROOT="$server_data_root"

# Each of these can fail independently on a hosted runner, and a single
# "validate-input" token cannot say which. The sub-stages stay bounded names --
# no paths, no errno text -- so the published evidence contract is unchanged.
enter_stage "resolve-server-root"
server_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../playstead-server" && pwd)"
control="$root/control"
server_control="$server_data_root/mac-client-control"

enter_stage "create-control-root"
mkdir -p "$control"

enter_stage "create-server-control"
# The runner that owns the native server root creates this directory. Accept it
# when it is already there and only fall back to creating it for a local run,
# so the fixture never has to create a directory under a root it does not own.
[ -d "$server_control" ] || mkdir -p "$server_control"

enter_stage "secure-roots"
# Only chmod what this fixture created. chmod requires ownership, not merely
# write access, so touching the runner-owned server control directory here can
# fail even where the fixture can freely write files into it.
chmod 0700 "$root" "$control"

case "$action" in
  prepare)
    first="$control/first-sentinel.json"
    server_first="$server_control/first-sentinel.json"
    request="$control/pairing-request.json"
    device_code="$control/device-code"
    handoff="$root/credential-handoff.json"

    enter_stage "provision-domain"
    (cd "$server_root" && PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture provision --output "$server_first") >/dev/null
    install -m 0600 "$server_first" "$first"
    rm -f "$server_first"

    enter_stage "request-pairing"
    python3 - "$request" "$device_code" <<'PY'
import json, os, pathlib, secrets, ssl, sys, urllib.request
request_path, code_path = map(pathlib.Path, sys.argv[1:])
device_code = secrets.token_urlsafe(32)
context = ssl.create_default_context(cafile=os.environ["PLAYSTEAD_MAC_CI_ROOT"] + "/tls/ca.pem")
body = json.dumps({
    "device_code": device_code,
    "device_name": "Playstead Hosted Mac",
    "platform": "macOS CI",
    "app_version": "1",
    "capabilities": {},
}).encode()
req = urllib.request.Request("https://127.0.0.1:4010/api/v1/device-pairing/requests", data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=10, context=context) as response:
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
    enter_stage "approve-pairing"
    (cd "$server_root" && PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture approve --request-id "$request_id" --display-code "$display_code" --device-label "Playstead Hosted Mac") >/dev/null

    enter_stage "redeem-pairing"
    python3 - "$request" "$device_code" "$handoff" <<'PY'
import json, os, pathlib, ssl, sys, urllib.request
request_path, code_path, handoff_path = map(pathlib.Path, sys.argv[1:])
request_id = json.loads(request_path.read_text())["id"]
context = ssl.create_default_context(cafile=os.environ["PLAYSTEAD_MAC_CI_ROOT"] + "/tls/ca.pem")
body = json.dumps({"device_code": code_path.read_text()}).encode()
url = f"https://127.0.0.1:4010/api/v1/device-pairing/requests/{request_id}/redeem"
req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=10, context=context) as response:
    redeemed = json.loads(response.read())
handoff = {
    "device_id": redeemed["device_id"],
    "credential": redeemed["credential"],
    "base_url": "https://127.0.0.1:4010",
}
handoff_path.write_text(json.dumps(handoff), encoding="utf-8")
os.chmod(handoff_path, 0o600)
request_path.unlink()
code_path.unlink()
PY
    ;;
  pair-provision)
    # Plan 04.5-01: the live-server pairing ceremony proof drives the real
    # `PairingView` end-to-end -- the pairing *request* is created by the
    # app under test, never by this fixture. This action only provisions
    # the owner (and the harmless first sentinel `provision!` also
    # creates), then stops; `pair-approve` runs later, once the running
    # app has actually created a pending request.
    server_first="$server_control/first-sentinel.json"
    enter_stage "provision-domain"
    (cd "$server_root" && PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture provision --output "$server_first") >/dev/null
    rm -f "$server_first"
    ;;
  pair-approve)
    # Approves the sole pending pairing request -- the one the app under
    # test just created through its own real `PairingCoordinator` -- by
    # display code alone, since the server-generated request id is never
    # surfaced to a human or to this fixture (D-08). The device label must
    # match `PairingCoordinator`'s `PLAYSTEAD_UI_TEST_PAIRING_DEVICE_NAME`
    # override, which the driving XCTest sets to this exact literal.
    display_code="${4:-}"
    [ -n "$display_code" ] || die
    enter_stage "approve-pairing"
    (cd "$server_root" && PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture approve-sole --display-code "$display_code" --device-label "Playstead Hosted Mac") >/dev/null
    ;;
  second)
    enter_stage "add-second-sentinel"
    server_second="$server_control/second-sentinel.json"
    client_second="$control/second-sentinel.json"
    (cd "$server_root" && PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture second --output "$server_second") >/dev/null
    install -m 0600 "$server_second" "$client_second"
    rm -f "$server_second"
    ;;
  verify)
    enter_stage "verify-evidence"
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
  *) die ;;
esac
stage="complete"
