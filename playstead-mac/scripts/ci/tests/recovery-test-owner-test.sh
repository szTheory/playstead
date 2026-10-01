#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CANON_TMP="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
TMP_ROOT="$(TMPDIR="$CANON_TMP" mktemp -d "$CANON_TMP/playstead-test-owner.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
SANDBOX="$TMP_ROOT/ci"
BIN="$TMP_ROOT/bin"
mkdir -m 700 -p "$SANDBOX" "$BIN" "$TMP_ROOT/handoff"
cp "$SOURCE_ROOT/recovery-test-owner.sh" "$SANDBOX/recovery-test-owner.sh"
chmod 700 "$SANDBOX/recovery-test-owner.sh"
cat >"$SANDBOX/recovery-e2e.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --validate-only ] && printf '%s\n' RECOVERY_HANDOFF_VALID
SH
cat >"$SANDBOX/recovery-browser-trust.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = check ] && printf '%s\n' 'RECOVERY_BROWSER_TRUST stage=browser_trust outcome=trusted'
SH
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env python3
import json,os,pathlib,sys
state=pathlib.Path(os.environ["FAKE_DOCKER_STATE"])
try: s=json.loads(state.read_text())
except Exception: s={"reset_count":0,"password":""}
args=sys.argv[1:]
with pathlib.Path(os.environ["FAKE_DOCKER_TRACE"]).open("a") as trace: trace.write(args[0]+" "+str(args[1] if len(args)>1 else "")+"\n")
if args[:1]==["ps"]:
    print("abcdef123456\nbcdefa123456\ncdefab123456")
elif args[:1]==["inspect"]:
    project="playstead-restore-proof-123"
    services=[]
    specs={"app":[("playstead-restore-proof-123_blobs","/app/blobs"),("playstead-restore-proof-123_caddy_data","/caddy_data")],"db":[("playstead-restore-proof-123_db","/var/lib/postgresql/data")],"caddy":[("playstead-restore-proof-123_caddy_data","/data"),("playstead-restore-proof-123_caddy_config","/config")]}
    for i,(name,mounts) in enumerate(specs.items()):
        services.append({"Id":(args[i+1]+"0"*64)[:64],"State":{"Running":True},"Config":{"Labels":{"com.docker.compose.project":project,"com.docker.compose.service":name},"Env":["DATABASE_URL=ecto://playstead_restore:private@db/playstead_restore"] if name=="app" else []},"NetworkSettings":{"Networks":{project+"_default":{}},"Ports":{}},"Mounts":[{"Type":"volume","Name":volume,"Destination":destination} for volume,destination in mounts]})
    if os.environ.get("FAKE_BAD_TOPOLOGY"): services[0]["NetworkSettings"]["Networks"]={"canonical_default":{}}
    print(json.dumps(services))
elif args[:2]==["exec","-i"] and "eval" in args:
    code=args[args.index("eval")+1]
    payload=sys.stdin.buffer.read()
    with pathlib.Path(os.environ["FAKE_DOCKER_TRACE"]).open("a") as trace: trace.write("eval="+("approval" if "Pairing.approve" in code else "reset" if "reset_owner_password" in code else "auth" if "RECOVERY_OWNER_AUTH_VALID" in code else "owner" if "get_owner()" in code else "unknown")+"\n")
    if "Pairing.approve" in code:
        data=json.loads(payload)
        assert data["email"]=="seed-owner@example.invalid" and len(data["password"])>=24
        assert data["display_code"]=="BCDF-GHJK"
        assert "inserted_at>=^lower" in code and "r.expires_at>^now" in code and 'r.status=="pending"' in code
        assert "case candidates do\n      [request]" in code
        s["approval_count"]=s.get("approval_count",0)+1; state.write_text(json.dumps(s))
        print("RECOVERY_TEST_OWNER_APPROVAL=approved")
    elif "reset_owner_password" in code:
        data=json.loads(payload)
        assert set(data)=={"email","password"} and data["email"]=="seed-owner@example.invalid" and len(data["password"])>=24
        assert "/reset/" in code and "reset_password_with_token" in code
        assert "{:ok,{user,_}}" in code
        s["reset_count"]+=1; s["password"]=data["password"]; state.write_text(json.dumps(s))
        print("RECOVERY_TEST_OWNER_RESULT:"+json.dumps({"email":data["email"],"password":data["password"]}))
    elif "RECOVERY_OWNER_AUTH_VALID" in code:
        data=json.loads(payload)
        with pathlib.Path(os.environ["FAKE_DOCKER_TRACE"]).open("a") as trace: trace.write("auth_email="+str(data.get("email")=="seed-owner@example.invalid").lower()+" auth_password="+str(data.get("password")==s.get("password")).lower()+"\n")
        if data.get("email")=="seed-owner@example.invalid" and data.get("password")==s.get("password") and s["password"]:
            print("RECOVERY_OWNER_AUTH_VALID")
        else: sys.exit(2)
    elif "get_owner()" in code:
        if s.get("owner_exists",True): print("RECOVERY_TEST_OWNER_EMAIL:seed-owner@example.invalid")
        else: sys.exit(2)
    else: sys.exit(2)
else: sys.exit(90)
SH
chmod 700 "$BIN/docker" "$SANDBOX/recovery-e2e.sh" "$SANDBOX/recovery-browser-trust.sh"
python3 - "$TMP_ROOT/handoff" <<'PY'
import datetime,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); correlation="3f8d70fd-3e69-4f52-a263-8470997a59c5"
receipt={"schema":"playstead.restore-receipt.v1","state":"verified","correlation_id":correlation,"target":{"project":"playstead-restore-proof-123","network":"playstead-restore-proof-123_default","volumes":["playstead-restore-proof-123_db","playstead-restore-proof-123_blobs"],"ports":{"https":18443}},"chain_ids":["opaque"],"stages":["chain","preflight","database","cas","manifest","api"],"verified_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
handoff={"schema":"playstead.restore-handoff.v1","correlation_id":correlation,"project":"playstead-restore-proof-123","url":"https://localhost:18443","receipt_path":str(p/"restore-receipt.json"),"ca_path":str(p/"caddy-root-ca.pem")}
(p/"restore-receipt.json").write_text(json.dumps(receipt)); (p/"caddy-root-ca.pem").write_text("fake ca"); (p/"server-handoff.json").write_text(json.dumps(handoff))
PY
chmod 600 "$TMP_ROOT/handoff/restore-receipt.json" "$TMP_ROOT/handoff/caddy-root-ca.pem" "$TMP_ROOT/handoff/server-handoff.json"
STATE="$TMP_ROOT/docker-state.json"
export FAKE_DOCKER_STATE="$STATE"
export FAKE_DOCKER_TRACE="$TMP_ROOT/docker-trace"
HANDOFF="$TMP_ROOT/handoff/server-handoff.json"

if ! out=$(PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SANDBOX/recovery-test-owner.sh" prepare); then
  [ ! -e "$FAKE_DOCKER_TRACE" ] || cat "$FAKE_DOCKER_TRACE" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
[[ "$out" == 'RECOVERY_TEST_OWNER stage=complete outcome=prepared' ]]
python3 - "$TMP_ROOT/handoff/test-owner.json" "$STATE" <<'PY'
import json,os,pathlib,stat,sys
p=pathlib.Path(sys.argv[1]); r=json.loads(p.read_text()); s=json.loads(pathlib.Path(sys.argv[2]).read_text())
assert set(r)=={"schema","correlation_id","test_only","email","password","state"}
assert r["schema"]=="playstead.recovery-test-owner.v1" and r["test_only"] is True and r["state"]=="ready"
assert stat.S_IMODE(p.stat().st_mode)==0o600 and s["reset_count"]==1
r["state"]="pending"; p.write_text(json.dumps(r)); p.chmod(0o600)
PY
out=$(PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SANDBOX/recovery-test-owner.sh" prepare)
[[ "$out" == 'RECOVERY_TEST_OWNER stage=complete outcome=reused' ]]
out=$(PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SANDBOX/recovery-test-owner.sh" check)
[[ "$out" == 'RECOVERY_TEST_OWNER stage=complete outcome=ready' ]]
python3 - "$STATE" <<'PY'
import json,pathlib,sys
assert json.loads(pathlib.Path(sys.argv[1]).read_text())["reset_count"]==1
PY

# Wrong network identity is rejected before the reset RPC boundary.
if FAKE_BAD_TOPOLOGY=1 PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SANDBOX/recovery-test-owner.sh" prepare >"$TMP_ROOT/refusal.out" 2>/dev/null; then
  printf '%s\n' 'FAIL: wrong isolated network was accepted' >&2; exit 1
fi
rg -q '^RECOVERY_TEST_OWNER stage=target_scope outcome=blocked$' "$TMP_ROOT/refusal.out"
! rg -q 'seed-owner|password|localhost|18443|fake ca' "$TMP_ROOT/refusal.out"
python3 - "$STATE" <<'PY'
import json,pathlib,sys
assert json.loads(pathlib.Path(sys.argv[1]).read_text())["reset_count"]==1
PY

# A malformed record is refused before contacting Docker or changing auth.
record="$TMP_ROOT/handoff/test-owner.json"
printf '%s\n' '{"schema":"wrong"}' >"$record"
chmod 600 "$record"
: >"$FAKE_DOCKER_TRACE"
if PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SANDBOX/recovery-test-owner.sh" check >"$TMP_ROOT/malformed.out" 2>/dev/null; then
  printf '%s\n' 'FAIL: malformed credential record was accepted' >&2; exit 1
fi
rg -q '^RECOVERY_TEST_OWNER stage=owner_record outcome=blocked$' "$TMP_ROOT/malformed.out"
[ ! -s "$FAKE_DOCKER_TRACE" ]
python3 - "$record" "$STATE" <<'PY'
import json,pathlib,sys
s=json.loads(pathlib.Path(sys.argv[2]).read_text())
r={"schema":"playstead.recovery-test-owner.v1","correlation_id":"3f8d70fd-3e69-4f52-a263-8470997a59c5","test_only":True,"email":"seed-owner@example.invalid","password":s["password"],"state":"ready"}
pathlib.Path(sys.argv[1]).write_text(json.dumps(r))
PY
chmod 600 "$record"

# Opt-in approval consumes one fresh, exact request code through the production
# Pairing.approve/2 boundary; the mode refuses to run without explicit opt-in.
mkdir -m 700 "$TMP_ROOT/runner"
mkdir -m 700 "$TMP_ROOT/runner/profile"
printf '%s' 'https://localhost:18443' >"$TMP_ROOT/runner/profile/recovery-target.url"
chmod 600 "$TMP_ROOT/runner/profile/recovery-target.url"
python3 - "$TMP_ROOT/runner/profile/recovery-approval-request.json" <<'PY'
import datetime,json,pathlib,sys
now=datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
pathlib.Path(sys.argv[1]).write_text(json.dumps({"schema":"playstead.recovery-test-approval.v1","display_code":"BCDF-GHJK","requested_at":now}))
PY
chmod 600 "$TMP_ROOT/runner/profile/recovery-approval-request.json"
if PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SANDBOX/recovery-test-owner.sh" approve-once "$TMP_ROOT/runner/profile" >"$TMP_ROOT/approval-disabled.out" 2>&1; then
  printf '%s\n' 'FAIL: approval helper ran without the explicit test opt-in' >&2; exit 1
fi
rg -q '^RECOVERY_TEST_OWNER stage=approval_driver outcome=disabled$' "$TMP_ROOT/approval-disabled.out"
if ! out=$(PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL=1 PATH="$BIN:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" "$SANDBOX/recovery-test-owner.sh" approve-once "$TMP_ROOT/runner/profile" 2>"$TMP_ROOT/approval.err"); then
  cat "$FAKE_DOCKER_TRACE" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
[[ "$out" == 'RECOVERY_TEST_OWNER stage=approval_driver outcome=approved' ]]
rg -q '^approval_driver=test_owner$' "$TMP_ROOT/approval.err"
! printf '%s\n' "$out" | rg -q 'seed-owner|password|BCDF-GHJK|localhost|18443'
! rg -q 'seed-owner|password|BCDF-GHJK|localhost|18443' "$TMP_ROOT/approval.err"
python3 - "$STATE" <<'PY'
import json,pathlib,sys
s=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert s["reset_count"]==1 and s["approval_count"]==1
PY

printf '%s\n' 'recovery test-owner contract passed'
