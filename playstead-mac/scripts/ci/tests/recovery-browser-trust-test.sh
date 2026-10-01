#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HELPER="$SCRIPT_DIR/../recovery-browser-trust.sh"
COORDINATOR="$SCRIPT_DIR/../recovery-e2e.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/recovery-browser-trust-test.XXXXXX")"
FAILURE_CODE=local_tls_setup
cleanup() {
  local status="$1"
  if [ "$status" -ne 0 ]; then
    printf 'RECOVERY_BROWSER_TRUST_TEST code=%s\n' "$FAILURE_CODE" >&2
  fi
  if [ -n "${TLS_PID:-}" ]; then kill "$TLS_PID" 2>/dev/null || true; wait "$TLS_PID" 2>/dev/null || true; fi
  rm -rf "$ROOT" >/dev/null 2>&1 || true
}
trap 'cleanup "$?"' EXIT
mkdir -m 700 "$ROOT/bin" "$ROOT/home" "$ROOT/home/Library" "$ROOT/home/Library/Keychains" "$ROOT/target"
BIN="$ROOT/bin"
touch "$ROOT/login.keychain-db"; chmod 644 "$ROOT/login.keychain-db"

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$ROOT/ca.key" -out "$ROOT/ca.pem" -days 2 -subj '/CN=Recovery Test CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$ROOT/server.key" -out "$ROOT/server.csr" -subj '/CN=localhost' >/dev/null 2>&1
cat >"$ROOT/ext.cnf" <<'EOF'
subjectAltName=DNS:localhost
extendedKeyUsage=serverAuth
basicConstraints=CA:FALSE
EOF
openssl x509 -req -in "$ROOT/server.csr" -CA "$ROOT/ca.pem" -CAkey "$ROOT/ca.key" -CAcreateserial -out "$ROOT/server.pem" -days 2 -extfile "$ROOT/ext.cnf" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$ROOT/other.key" -out "$ROOT/other-ca.pem" -days 2 -subj '/CN=Different Test CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' >/dev/null 2>&1
FAILURE_CODE=tls_listener_ready
python3 - "$ROOT/server.pem" "$ROOT/server.key" "$ROOT/port" <<'PY' >"$ROOT/tls.out" 2>&1 &
import pathlib, socket, ssl, sys

cert, key, port_file = map(pathlib.Path, sys.argv[1:])
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain(certfile=cert, keyfile=key)
listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", 0))
listener.listen(8)
listener.settimeout(0.2)
port_file.write_text(str(listener.getsockname()[1]))
while True:
    try:
        raw, _ = listener.accept()
    except socket.timeout:
        continue
    try:
        with context.wrap_socket(raw, server_side=True):
            pass
    except (OSError, ssl.SSLError):
        raw.close()
PY
TLS_PID=$!
for _ in $(seq 1 80); do
  if [ -s "$ROOT/port" ]; then break; fi
  kill -0 "$TLS_PID" 2>/dev/null || exit 1
  sleep 0.1
done
[ -s "$ROOT/port" ] || exit 1
PORT="$(<"$ROOT/port")"
# Apple's system OpenSSL is LibreSSL 3.3 and does not implement s_client's
# -verify_hostname option. The Python client below uses the platform TLS
# library's CA and hostname verification directly, then checks the negotiated
# protocol version, so keep one strict interoperable client probe.
FAILURE_CODE=tls_python_handshake
python3 - "$PORT" "$ROOT/ca.pem" 2>/dev/null <<'PY'
import socket,ssl,sys
try:
 c=ssl.create_default_context(cafile=sys.argv[2]); c.check_hostname=True
 with socket.create_connection(("127.0.0.1",int(sys.argv[1])),timeout=3) as raw:
  with c.wrap_socket(raw,server_hostname="localhost") as tls:
   if tls.version() not in ("TLSv1.2","TLSv1.3"): raise SystemExit(1)
except Exception:
 raise SystemExit(1)
PY

FAILURE_CODE=fixture_setup
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >>"$FAKE_DOCKER_CALLS"
case "$1" in
  info) exit 0 ;;
  compose) [ "${2:-}" = version ] && exit 0; exit 91 ;;
  ps) printf '%s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'; exit 0 ;;
  inspect) python3 - "$FAKE_PROJECT" "$FAKE_PORT" <<'PY'
import json,sys
p,port=sys.argv[1:]
d={"Config":{"Labels":{"com.docker.compose.project":p,"com.docker.compose.service":"caddy"}},"State":{"Running":True},"NetworkSettings":{"Networks":{p+"_default":{}},"Ports":{"443/tcp":[{"HostIp":"127.0.0.1","HostPort":port}]}},"Mounts":[{"Type":"volume","Name":p+"_caddy_data","Destination":"/data","RW":True}]}
print(json.dumps([d]))
PY
    ;;
  exec) cat "$FAKE_LIVE_CA" ;;
  *) exit 90 ;;
esac
SH
cat >"$BIN/security" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  login-keychain) printf '"%s"\n' "$FAKE_LOGIN_KEYCHAIN" ;;
  verify-cert) [ -f "$FAKE_TRUSTED" ] && exit 0; exit 1 ;;
  add-trusted-cert)
    printf 'add\n' >>"$FAKE_CALLS"
    [ "${FAKE_TIMEOUT_ADD:-0}" = 0 ] || exit 124
    [ "${FAKE_FAIL_ADD:-0}" = 0 ] || exit 1
    : >"$FAKE_TRUSTED"
    ;;
  remove-trusted-cert)
    printf 'remove\n' >>"$FAKE_CALLS"
    rm -f "$FAKE_TRUSTED"
    ;;
  *) exit 91 ;;
esac
SH
chmod 700 "$BIN/docker" "$BIN/security"

make_handoff() {
  python3 - "$ROOT/target" "$PORT" "$ROOT/ca.pem" <<'PY'
import datetime as dt,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); port=int(sys.argv[2]); correlation="a0f8e657-b301-4aed-920a-2e1a676bf24b"
project="playstead-restore-test-123"
receipt={"schema":"playstead.restore-receipt.v1","state":"verified","correlation_id":correlation,
 "target":{"project":project,"network":project+"_default","volumes":[project+"_db",project+"_blobs"],"ports":{"https":port}},
 "chain_ids":["opaque"],"stages":["chain","preflight","database","cas","manifest","api"],
 "verified_at":dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00","Z")}
handoff={"schema":"playstead.restore-handoff.v1","correlation_id":correlation,"project":project,
 "url":f"https://localhost:{port}","receipt_path":str(root/"restore-receipt.json"),"ca_path":str(root/"caddy-root-ca.pem")}
(root/"restore-receipt.json").write_text(json.dumps(receipt)); (root/"caddy-root-ca.pem").write_bytes(pathlib.Path(sys.argv[3]).read_bytes()); (root/"server-handoff.json").write_text(json.dumps(handoff))
PY
  chmod 600 "$ROOT/target/restore-receipt.json" "$ROOT/target/caddy-root-ca.pem" "$ROOT/target/server-handoff.json"
}
make_handoff
cp "$ROOT/ca.pem" "$ROOT/live-ca.pem"
chmod 600 "$ROOT/live-ca.pem"
export PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$ROOT/target/server-handoff.json"
export FAKE_PROJECT=playstead-restore-test-123 FAKE_PORT="$PORT" FAKE_LIVE_CA="$ROOT/live-ca.pem" FAKE_LOGIN_KEYCHAIN="$ROOT/login.keychain-db"
export FAKE_TRUSTED="$ROOT/trusted" FAKE_CALLS="$ROOT/security-calls" FAKE_DOCKER_CALLS="$ROOT/docker-calls"
python3 - "$FAKE_PROJECT" <<'PY'
import subprocess,sys
r=subprocess.run(["docker","ps","--no-trunc","--filter","label=com.docker.compose.project="+sys.argv[1],"--filter","label=com.docker.compose.service=caddy","--format","{{.ID}}"],capture_output=True)
assert r.returncode==0 and len(r.stdout.strip())==64
PY

run_helper() { local result=0; "$HELPER" "$1" >"$ROOT/out" 2>"$ROOT/err" || result=$?; printf '%s' "$result" >"$ROOT/status"; }
expect_status() { [ "$(<"$ROOT/status")" = "$1" ]; }
assert_safe_output() {
  ! grep -Eq 'localhost|[0-9]{4,}|restore-test|restore-receipt|caddy-root|[0-9a-f]{64}|Recovery Test CA|Different Test CA' "$ROOT/out" "$ROOT/err" || {
    printf '%s\n' 'FAIL: helper emitted private recovery details' >&2; exit 1;
  }
  grep -Eq '^RECOVERY_BROWSER_TRUST stage=[a-z_]+ outcome=[a-z_]+$' "$ROOT/out"
}

# An invalid owner/mode handoff must fail before calling any mutation command.
FAILURE_CODE=invalid_owner_preflight
chmod 644 "$ROOT/target/server-handoff.json"
run_helper ensure; expect_status 77
assert_safe_output
[ ! -e "$FAKE_CALLS" ] || { printf '%s\n' 'FAIL: preflight rejection reached Keychain boundary' >&2; exit 1; }
chmod 600 "$ROOT/target/server-handoff.json"

# A bundle containing a valid first root and any additional certificate is rejected.
FAILURE_CODE=ca_bundle_rejection
cat "$ROOT/ca.pem" >>"$ROOT/target/caddy-root-ca.pem"
run_helper ensure; expect_status 77
assert_safe_output
[ ! -e "$FAKE_CALLS" ] || { printf '%s\n' 'FAIL: malformed CA reached Keychain boundary' >&2; exit 1; }
cp "$ROOT/ca.pem" "$ROOT/target/caddy-root-ca.pem"; chmod 600 "$ROOT/target/caddy-root-ca.pem"

# A live CA mismatch blocks before Keychain mutation.
FAILURE_CODE=ca_mismatch_rejection
cp "$ROOT/other-ca.pem" "$ROOT/live-ca.pem"; chmod 600 "$ROOT/live-ca.pem"
run_helper ensure; expect_status 77
assert_safe_output
[ ! -e "$FAKE_CALLS" ] || { printf '%s\n' 'FAIL: CA mismatch reached Keychain boundary' >&2; exit 1; }
cp "$ROOT/ca.pem" "$ROOT/live-ca.pem"; chmod 600 "$ROOT/live-ca.pem"

# First ensure adds the exact CA; subsequent checks are idempotent.
FAILURE_CODE=ca_install
run_helper ensure
expect_status 0
assert_safe_output
grep -Eq 'outcome=installed$' "$ROOT/out"
[ "$(wc -l <"$FAKE_CALLS" | tr -d ' ')" = 1 ]
run_helper ensure
expect_status 0
assert_safe_output
grep -Eq 'outcome=already_trusted$' "$ROOT/out"
[ "$(wc -l <"$FAKE_CALLS" | tr -d ' ')" = 1 ]

# Coordinator prepare/check are explicit; default mode checks silently before Xcode.
FAILURE_CODE=authorization_reconcile
env -u PLAYSTEAD_TEAM_ID "$COORDINATOR" --check-browser-trust >"$ROOT/out" 2>"$ROOT/err"
grep -Eq '^RECOVERY_BROWSER_TRUST stage=browser_trust outcome=trusted$' "$ROOT/out"
env -u PLAYSTEAD_TEAM_ID "$COORDINATOR" --prepare-browser-trust >"$ROOT/out" 2>"$ROOT/err"
grep -Eq '^RECOVERY_BROWSER_TRUST stage=browser_trust outcome=already_trusted$' "$ROOT/out"
set +e
env -u PLAYSTEAD_TEAM_ID "$COORDINATOR" >"$ROOT/out" 2>"$ROOT/err"
coordinator_status=$?
set -e
[ "$coordinator_status" = 77 ] && [ "$(wc -l <"$ROOT/out" | tr -d ' ')" = 1 ]
python3 - "$ROOT/out" <<'PY'
import json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(d)=={"schema","run_id","lane","stage","outcome"}
assert d["stage"] in ("preflight","clean_mac_ui") and d["outcome"]=="blocked"
PY

# An installation error leaves no ownership claim and does not leak stderr.
FAILURE_CODE=install_failure_rollback
rm -f "$FAKE_TRUSTED" "$ROOT/target/browser-trust-ownership.json"
export FAKE_FAIL_ADD=1
run_helper ensure; expect_status 77
assert_safe_output
[ ! -e "$ROOT/target/browser-trust-ownership.json" ]
unset FAKE_FAIL_ADD

# A timed-out authorization keeps an owned pending record that the next
# explicit ensure safely reconciles instead of requiring manual deletion.
FAILURE_CODE=authorization_reconcile
export FAKE_TIMEOUT_ADD=1
run_helper ensure; expect_status 77
assert_safe_output
grep -Eq 'outcome=authorization_required$' "$ROOT/out"
python3 - "$ROOT/target/browser-trust-ownership.json" <<'PY'
import json,pathlib,stat,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text())
assert d["state"]=="pending" and stat.S_IMODE(p.stat().st_mode)==0o600
PY
unset FAKE_TIMEOUT_ADD
run_helper ensure; expect_status 0
assert_safe_output
grep -Eq 'outcome=installed$' "$ROOT/out"

# Cleanup works after the target is offline and only consumes our exact marker.
FAILURE_CODE=owned_cleanup
run_helper ensure
expect_status 0
assert_safe_output
kill "$TLS_PID" 2>/dev/null || true; wait "$TLS_PID" 2>/dev/null || true; TLS_PID=""
run_helper remove-owned
expect_status 0
assert_safe_output
grep -Eq 'outcome=removed$' "$ROOT/out"
[ ! -e "$FAKE_TRUSTED" ] && [ ! -e "$ROOT/target/browser-trust-ownership.json" ]

printf '%s\n' 'recovery-browser-trust contracts: passed'
