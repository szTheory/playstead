#!/usr/bin/env bash
#
# pair-dev.sh — perform the Playstead device-pairing ceremony by hand and
# write the resulting credential into the login Keychain where the Mac app
# reads it.
#
# The Mac app does not yet ship pairing UI (`KeychainStore.storeCredential`
# has no in-app caller), so this script stands in for it during local
# development. It drives exactly the ceremony the server implements in
# `PlaysteadWeb.Api.V1.PairingController` (D-07/D-08):
#
#   1. POST /api/v1/device-pairing/requests        -> id, display_code, poll_interval, expires_at
#   2. owner approves the displayed code at /devices in the web console
#   3. GET  /api/v1/device-pairing/requests/:id    -> status  (polled at poll_interval)
#   4. POST /api/v1/device-pairing/requests/:id/redeem  with the client-generated
#      device_code -> device_id, credential, fingerprint_prefix
#
# The credential is then stored as a kSecClassGenericPassword item matching
# what `KeychainStore.loadCredential()` queries for:
#
#   service          dev.playstead.mac
#   account          device_id
#   password data    the bearer credential
#   generic attr     {"baseURL":"<server base url>"}   (JSON, decoded as CredentialEnvelope)
#
# DEVELOPMENT ONLY. The item is added with `-A` (any application may read it
# without an ACL prompt), which is what makes an unattended dev run work but
# is not how the shipping app should ever store a credential.

set -euo pipefail

readonly KEYCHAIN_SERVICE="dev.playstead.mac"
readonly DEFAULT_SERVER="http://127.0.0.1:4000"

SERVER="$DEFAULT_SERVER"
DEVICE_LABEL="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
APP_VERSION="dev"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<USAGE
usage: $(basename "$0") [--server URL] [--label NAME]

  --server URL   Playstead server base URL (default: $DEFAULT_SERVER)
  --label NAME   device name shown in the approval queue (default: this Mac's name)
  -h, --help     show this help

Runs the device-pairing ceremony and writes the credential to the login
Keychain (service "$KEYCHAIN_SERVICE"). The credential is never printed.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --server) [ $# -ge 2 ] || die "--server needs a URL"; SERVER="$2"; shift 2 ;;
    --server=*) SERVER="${1#*=}"; shift ;;
    --label) [ $# -ge 2 ] || die "--label needs a name"; DEVICE_LABEL="$2"; shift 2 ;;
    --label=*) DEVICE_LABEL="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

SERVER="${SERVER%/}"
case "$SERVER" in
  http://*|https://*) ;;
  *) die "--server must start with http:// or https:// (got: $SERVER)" ;;
esac

command -v curl >/dev/null 2>&1 || die "curl not found on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH (install the Xcode Command Line Tools)"
command -v security >/dev/null 2>&1 || die "security(1) not found on PATH"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# Reads one top-level string/number field out of a JSON file. Prints
# nothing and returns non-zero when the key is absent, so callers can
# distinguish "field missing" from "field empty".
json_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        doc = json.load(fh)
except Exception:
    sys.exit(2)
if not isinstance(doc, dict) or sys.argv[2] not in doc:
    sys.exit(1)
value = doc[sys.argv[2]]
if value is None:
    sys.exit(1)
sys.stdout.write(str(value))
PY
}

# curl wrapper: writes the body to $2, prints the HTTP status on stdout,
# and fails with a transport-specific message when the server is unreachable.
http() {
  local method="$1" url="$2" out="$3" data="${4:-}" status curl_rc
  local -a args=(--silent --show-error --location --max-time 20
                 --write-out '%{http_code}' --output "$out"
                 -X "$method" -H 'Accept: application/json')
  if [ -n "$data" ]; then
    args+=(-H 'Content-Type: application/json' --data-binary "$data")
  fi
  set +e
  status="$(curl "${args[@]}" "$url" 2>"$WORKDIR/curl.err")"
  curl_rc=$?
  set -e
  if [ "$curl_rc" -ne 0 ]; then
    note ""
    note "Could not reach the server at $SERVER"
    note "  curl: $(tr -d '\n' <"$WORKDIR/curl.err")"
    note ""
    note "  - Is the server running?  (cd playstead-server && mix phx.server)"
    note "  - Does --server match the host and port it is bound to?"
    note "  - For an https:// server using Caddy's internal CA, the CA root must be"
    note "    trusted by this Mac, or curl will refuse the certificate. Plain-HTTP"
    note "    loopback ($DEFAULT_SERVER) needs no trust setup and is the supported"
    note "    local-development path."
    exit 1
  fi
  printf '%s' "$status"
}

# problem+json detail, when the server sent one.
problem_detail() {
  json_field "$1" detail 2>/dev/null || json_field "$1" title 2>/dev/null || printf 'no detail'
}

# --- 0. reachability ---------------------------------------------------------

note "Contacting $SERVER ..."
status="$(http GET "$SERVER/healthz" "$WORKDIR/health.json")"
if [ "$status" != "200" ]; then
  die "server answered /healthz with HTTP $status (expected 200) — is this a Playstead server?"
fi

# --- 1. create the pairing request ------------------------------------------

# D-08: the device_code is generated by the client, never by the server, and
# is the only thing that authorizes redemption. 256 bits of urandom, hex.
DEVICE_CODE="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

request_body="$(
  DEVICE_CODE="$DEVICE_CODE" DEVICE_LABEL="$DEVICE_LABEL" APP_VERSION="$APP_VERSION" \
  python3 -c 'import json, os, platform; print(json.dumps({
    "device_code": os.environ["DEVICE_CODE"],
    "device_name": os.environ["DEVICE_LABEL"],
    "platform": "macOS " + platform.mac_ver()[0],
    "app_version": os.environ["APP_VERSION"],
    "capabilities": {},
  }))'
)"

status="$(http POST "$SERVER/api/v1/device-pairing/requests" "$WORKDIR/create.json" "$request_body")"
case "$status" in
  201) ;;
  429) die "the server is rate-limiting pairing requests (HTTP 429). Wait a minute and re-run." ;;
  *)   die "creating the pairing request failed with HTTP $status: $(problem_detail "$WORKDIR/create.json")" ;;
esac

REQUEST_ID="$(json_field "$WORKDIR/create.json" id)" || die "server response had no request id"
DISPLAY_CODE="$(json_field "$WORKDIR/create.json" display_code)" || die "server response had no display code"
POLL_INTERVAL="$(json_field "$WORKDIR/create.json" poll_interval)" || POLL_INTERVAL=5
EXPIRES_AT="$(json_field "$WORKDIR/create.json" expires_at)" || EXPIRES_AT=""

case "$POLL_INTERVAL" in
  ''|*[!0-9]*) POLL_INTERVAL=5 ;;
esac
[ "$POLL_INTERVAL" -ge 1 ] 2>/dev/null || POLL_INTERVAL=5

# Absolute deadline, taken from the server's own expires_at (D-12: 10 min).
DEADLINE="$(
  EXPIRES_AT="$EXPIRES_AT" python3 -c '
import os, time, datetime
raw = os.environ.get("EXPIRES_AT", "")
try:
    text = raw.replace("Z", "+00:00")
    parsed = datetime.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    print(int(parsed.timestamp()))
except Exception:
    print(int(time.time()) + 600)
'
)"

# --- 2. show the code and wait for the owner --------------------------------

cat >&2 <<BANNER

  ┌──────────────────────────────────────────────┐
     Pairing code:  $DISPLAY_CODE
  └──────────────────────────────────────────────┘

  Approve this device in the web console:

      $SERVER/devices

  Find the request showing the code above and approve it.
  This code expires in about 10 minutes.

BANNER

note "Waiting for approval (polling every ${POLL_INTERVAL}s) ..."

APPROVED=0
while :; do
  now="$(date +%s)"
  if [ "$now" -ge "$DEADLINE" ]; then
    note ""
    die "the pairing request expired before it was approved (10-minute limit). Re-run this script to get a fresh code."
  fi

  sleep "$POLL_INTERVAL"

  status="$(http GET "$SERVER/api/v1/device-pairing/requests/$REQUEST_ID" "$WORKDIR/poll.json")"
  case "$status" in
    200) ;;
    404) die "the server no longer knows this pairing request (HTTP 404). Re-run this script." ;;
    429)
      # The server's own rate limiter; back off and keep waiting.
      note "  (server asked us to slow down; backing off)"
      sleep "$POLL_INTERVAL"
      continue
      ;;
    *) die "polling failed with HTTP $status: $(problem_detail "$WORKDIR/poll.json")" ;;
  esac

  request_status="$(json_field "$WORKDIR/poll.json" status)" || die "poll response had no status field"
  case "$request_status" in
    pending)
      printf '.' >&2
      ;;
    approved)
      note ""
      note "Approved."
      APPROVED=1
      break
      ;;
    denied)
      note ""
      die "the owner denied this pairing request. Re-run this script to ask again."
      ;;
    expired)
      note ""
      die "the pairing request expired before it was approved (10-minute limit). Re-run this script to get a fresh code."
      ;;
    redeemed)
      note ""
      die "this pairing request was already redeemed by another client. Re-run this script."
      ;;
    *)
      note ""
      die "unexpected pairing status from the server: $request_status"
      ;;
  esac
done
[ "$APPROVED" -eq 1 ] || die "internal: exited the approval loop without approval"

# --- 3. redeem --------------------------------------------------------------

redeem_body="$(DEVICE_CODE="$DEVICE_CODE" python3 -c 'import json, os; print(json.dumps({"device_code": os.environ["DEVICE_CODE"]}))')"
status="$(http POST "$SERVER/api/v1/device-pairing/requests/$REQUEST_ID/redeem" "$WORKDIR/redeem.json" "$redeem_body")"
case "$status" in
  201) ;;
  410) die "the pairing request expired before it could be redeemed. Re-run this script." ;;
  409) die "redemption refused (HTTP 409): $(problem_detail "$WORKDIR/redeem.json")" ;;
  404) die "the server no longer knows this pairing request (HTTP 404). Re-run this script." ;;
  429) die "the server is rate-limiting redemption (HTTP 429). Wait a minute and re-run." ;;
  *)   die "redemption failed with HTTP $status: $(problem_detail "$WORKDIR/redeem.json")" ;;
esac

DEVICE_ID="$(json_field "$WORKDIR/redeem.json" device_id)" || die "redeem response had no device_id"
FINGERPRINT="$(json_field "$WORKDIR/redeem.json" fingerprint_prefix)" || FINGERPRINT="(none)"
CREDENTIAL="$(json_field "$WORKDIR/redeem.json" credential)" || die "redeem response had no credential"
[ -n "$CREDENTIAL" ] || die "the server returned an empty credential"

note "Paired as device $DEVICE_ID (credential fingerprint $FINGERPRINT)."

# --- 4. write the Keychain item ---------------------------------------------

# `KeychainStore.loadCredential()` queries by service alone with
# kSecMatchLimitOne and no account predicate, so a stale item from an earlier
# pairing (which carries a *different* device_id, i.e. a different account)
# would be picked up arbitrarily instead of this one. `security ... -U` only
# updates same-account items, so purge every item on this service first —
# that is what makes re-running the script idempotent rather than
# accumulating credentials.
purged=0
while security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; do
  purged=$((purged + 1))
  [ "$purged" -lt 50 ] || die "refusing to loop forever purging old $KEYCHAIN_SERVICE keychain items"
done
[ "$purged" -eq 0 ] || note "Removed $purged previously stored credential(s)."

# The generic attribute carries KeychainStore's CredentialEnvelope, whose
# single `baseURL` key is what APIClient resolves every request path against.
ENVELOPE="$(SERVER="$SERVER" python3 -c 'import json, os; print(json.dumps({"baseURL": os.environ["SERVER"]}))')"

if ! security add-generic-password \
      -s "$KEYCHAIN_SERVICE" \
      -a "$DEVICE_ID" \
      -G "$ENVELOPE" \
      -w "$CREDENTIAL" \
      -A -U >/dev/null 2>"$WORKDIR/keychain.err"; then
  note ""
  note "Could not write the credential to the login Keychain."
  note "  security: $(tr -d '\n' <"$WORKDIR/keychain.err")"
  note ""
  note "  - Is the login keychain unlocked?  (security unlock-keychain)"
  note "  - If a dialog appeared asking to allow access, it must be approved."
  note "  - The device is now paired server-side but this Mac has no stored"
  note "    credential; revoke it at $SERVER/devices before re-running."
  exit 1
fi
CREDENTIAL=""

note "Credential stored in the login Keychain (service $KEYCHAIN_SERVICE, account $DEVICE_ID)."

# --- 5. verify: read it back, then make one authenticated request -----------

note "Verifying ..."

readback="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$DEVICE_ID" 2>/dev/null || true)"
[ -n "$readback" ] || die "the credential is not readable back from the Keychain — the app will not see it"

# Re-read the password out of the Keychain rather than reusing the in-memory
# copy, so this genuinely exercises the path the app takes.
stored_token="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$DEVICE_ID" -w 2>/dev/null || true)"
[ -n "$stored_token" ] || die "the stored credential read back empty — the app will not be able to authenticate"

auth_status="$(
  curl --silent --show-error --location --max-time 20 \
       --write-out '%{http_code}' --output "$WORKDIR/me.json" \
       -H "Authorization: Bearer $stored_token" \
       -H 'Accept: application/json' \
       "$SERVER/api/v1/devices/me" 2>/dev/null || printf '000'
)"
stored_token=""

if [ "$auth_status" = "200" ]; then
  note "Authenticated request to /api/v1/devices/me returned HTTP $auth_status."
  note ""
  note "Done. Launch the Playstead app; it will find this credential in the Keychain."
  exit 0
fi

note "Authenticated request to /api/v1/devices/me returned HTTP $auth_status (expected 200)."
case "$auth_status" in
  000) note "  The request did not complete — see the reachability notes above." ;;
  401) note "  The server rejected the stored credential. Check $SERVER/devices for a revoked device." ;;
esac
exit 1
