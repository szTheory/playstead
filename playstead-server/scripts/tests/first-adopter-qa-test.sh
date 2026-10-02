#!/usr/bin/env bash
set -euo pipefail

server="$(cd "$(dirname "$0")/../.." && pwd -P)"
grep -Fq 'default_sni {$CADDY_SITE_ADDRESS:localhost}' "$server/Caddyfile"
grep -Fq 'protocols tls1.2 tls1.3' "$server/Caddyfile"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-qa-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/fake-bin"
mkdir -p "$fake_bin" "$tmp/data/inbox" "$tmp/data/exports" "$tmp/data/backups" "$tmp/private"
config="$tmp/private/first-adopter.env"
ca="$tmp/private/caddy-root.crt"
touch "$ca"
chmod 600 "$ca"
cat > "$config" <<EOF
POSTGRES_USER=playstead_owner
POSTGRES_PASSWORD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
POSTGRES_DB=playstead_owner
DATABASE_URL=ecto://playstead_owner:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@db/playstead_owner
SECRET_KEY_BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
PLAYSTEAD_SETUP_TOKEN=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
PHX_HOST=192.168.10.40
PLAYSTEAD_DOMAIN=
PLAYSTEAD_CADDY_SITE_ADDRESS=192.168.10.40
PLAYSTEAD_BIND_ADDRESS=192.168.10.40
PLAYSTEAD_HTTP_PORT=8080
PLAYSTEAD_HTTPS_PORT=8443
PLAYSTEAD_INBOX_HOST_PATH=$tmp/data/inbox
PLAYSTEAD_EXPORT_HOST_PATH=$tmp/data/exports
PLAYSTEAD_BACKUP_HOST_PATH=$tmp/data/backups
EOF
chmod 600 "$config"
export FAKE_DOCKER_LOG="$tmp/docker-log"
export FAKE_CURL_LOG="$tmp/curl-log"
export FAKE_SECURITY_LOG="$tmp/security-log"
export FAKE_INSPECT_DIR="$tmp/inspect"
export FAKE_CONFIG_JSON="$tmp/compose-config.json"
export FAKE_MODE=healthy
mkdir -p "$FAKE_INSPECT_DIR"

python3 - "$server" "$tmp" <<'PY'
import json, os, pathlib, sys
server, tmp = map(pathlib.Path, sys.argv[1:])
paths={name: os.path.realpath(tmp / "data" / name) for name in ("inbox","exports","backups")}
root=os.path.realpath(server)
def bind(source,target): return {"type":"bind","source":source,"target":target}
def volume(source,target): return {"type":"volume","source":source,"target":target}
services={
 "app":{"volumes":[bind(paths["inbox"],"/app/inbox"),bind(paths["exports"],"/app/exports"),bind(paths["backups"],"/app/backups"),volume("playstead_blobs","/app/blobs"),volume("caddy_data","/caddy_data")]},
 "db":{"volumes":[volume("playstead_db","/var/lib/postgresql/data")]},
 "caddy":{"volumes":[bind(os.path.join(root,"Caddyfile"),"/etc/caddy/Caddyfile"),volume("caddy_data","/data"),volume("caddy_config","/config")]},
}
services["caddy"]["ports"]=[{"host_ip":"192.168.10.40","published":"8080","target":8080},{"host_ip":"192.168.10.40","published":"8443","target":8443}]
config={"services":services,"volumes":{name:{"name":"playstead-first-adopter_"+name} for name in ("playstead_db","playstead_blobs","caddy_data","caddy_config")},"networks":{"default":{"name":"playstead-first-adopter_default"}}}
pathlib.Path(os.environ["FAKE_CONFIG_JSON"]).write_text(json.dumps(config))
files=root+"/docker-compose.yml,"+root+"/docker-compose.backup.yml"
for service in ("app","db","caddy"):
    state={"Status":"running"}
    if service=="app": state["Health"]={"Status":"healthy"}
    if service=="app":
        mounts=[{"Type":"bind","Source":"/host_mnt"+paths["inbox"],"Destination":"/app/inbox"},{"Type":"bind","Source":"/host_mnt"+paths["exports"],"Destination":"/app/exports"},{"Type":"bind","Source":"/host_mnt"+paths["backups"],"Destination":"/app/backups"},{"Type":"volume","Name":"playstead-first-adopter_playstead_blobs","Destination":"/app/blobs"},{"Type":"volume","Name":"playstead-first-adopter_caddy_data","Destination":"/caddy_data"}]
    elif service=="db": mounts=[{"Type":"volume","Name":"playstead-first-adopter_playstead_db","Destination":"/var/lib/postgresql/data"}]
    else: mounts=[{"Type":"bind","Source":os.path.join(root,"Caddyfile"),"Destination":"/etc/caddy/Caddyfile"},{"Type":"volume","Name":"playstead-first-adopter_caddy_data","Destination":"/data"},{"Type":"volume","Name":"playstead-first-adopter_caddy_config","Destination":"/config"}]
    detail={"Config":{"Labels":{"com.docker.compose.project":"playstead-first-adopter","com.docker.compose.service":service,"com.docker.compose.project.config_files":files}},"State":state,"Mounts":mounts}
    pathlib.Path(os.environ["FAKE_INSPECT_DIR"],"id-"+service).write_text(json.dumps(detail))
PY
cp "$FAKE_CONFIG_JSON" "$tmp/compose-config-good.json"

cat > "$fake_bin/docker" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
if [ "$1" = compose ]; then
  case " $* " in *" --project-name playstead-first-adopter "*) ;; *) exit 91 ;; esac
  case " $* " in
    *" config --format json "*) cat "$FAKE_CONFIG_JSON" ;;
    *" ps -q app db caddy "*) [ "$FAKE_MODE" = stopped ] && exit 0; printf 'id-app\nid-db\nid-caddy\n' ;;
    *" ps -q app "*) [ "$FAKE_MODE" = stopped ] || printf 'id-app\n' ;;
    *" ps -q db "*) [ "$FAKE_MODE" = stopped ] || printf 'id-db\n' ;;
    *" ps -q caddy "*) [ "$FAKE_MODE" = stopped ] || printf 'id-caddy\n' ;;
    *) exit 92 ;;
  esac
elif [ "$1" = inspect ]; then
  [ "$2" = --format ] && [ "$3" = '{{json .}}' ] || exit 93
  cat "$FAKE_INSPECT_DIR/$4"
else
  exit 94
fi
SH
cat > "$fake_bin/curl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_CURL_LOG"
[ "$FAKE_MODE" != untrusted ] || exit 60
if [ "$FAKE_MODE" = http-error ]; then printf '503'; exit 0; fi
printf '200'
SH
cat > "$fake_bin/openssl" <<'SH'
#!/bin/sh
[ "$1" = x509 ] && [ "$2" = -in ] || exit 95
printf 'sha256 Fingerprint=redacted-test-fingerprint\n'
SH
cat > "$fake_bin/security" <<'SH'
#!/bin/sh
[ "$1" = verify-cert ] || exit 96
printf 'verify-cert [redacted-url]\n' >> "$FAKE_SECURITY_LOG"
[ "$FAKE_SECURITY_MODE" = trusted ]
SH
chmod +x "$fake_bin/docker" "$fake_bin/curl" "$fake_bin/openssl" "$fake_bin/security"
export PATH="$fake_bin:$PATH"
export FAKE_SECURITY_MODE=trusted

config_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" config)"
[[ "$config_output" == *"configuration_isolation=PASS"* && "$config_output" == *"profile_resource_identity=NOT_RUN"* ]]
[[ "$config_output" != *"$tmp"* && "$config_output" != *"192.168.10.40"* && "$config_output" != *"aaaaaaaa"* ]]

live_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" --ca-file "$ca" live)"
[[ "$live_output" == *"profile_resource_identity=PASS"* && "$live_output" == *"app_readiness=PASS"* ]]
[[ "$live_output" == *"https_response=PASS"* && "$live_output" == *"cli_tls_chain_validation=PASS"* && "$live_output" == *"macOS_keychain_trust=PASS evidence=automated"* ]]
[[ "$live_output" != *"$tmp"* && "$live_output" != *"192.168.10.40"* && "$live_output" != *"redacted-test-fingerprint"* ]]
grep -q -- '--project-name playstead-first-adopter' "$FAKE_DOCKER_LOG"
! grep -Eq '(^| )(up|down|run|build|rm|stop|start|restart|kill|prune|volume)( |$)' "$FAKE_DOCKER_LOG"

export FAKE_MODE=stopped
if stopped_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" --ca-file "$ca" live)"; then
  echo 'expected stopped profile to return not-run status' >&2; exit 1
else
  status=$?
  [[ "$status" -eq 3 && "$stopped_output" == *"profile_resource_identity=NOT_RUN"* ]]
fi

export FAKE_MODE=untrusted
if tls_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" --ca-file "$ca" live)"; then
  echo 'expected untrusted TLS failure' >&2; exit 1
else
  [[ "$tls_output" == *"https_response=FAIL"* && "$tls_output" == *"cli_tls_chain_validation=FAIL"* ]]
fi

export FAKE_MODE=http-error
if http_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" --ca-file "$ca" live)"; then
  echo 'expected HTTPS health failure' >&2; exit 1
else
  [[ "$http_output" == *"https_response=FAIL"* && "$http_output" == *"cli_tls_chain_validation=PASS"* ]]
fi

export FAKE_SECURITY_MODE=untrusted
if keychain_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" --ca-file "$ca" live)"; then
  echo 'expected system Keychain trust failure' >&2; exit 1
else
  [[ "$keychain_output" == *"https_response=PASS"* && "$keychain_output" == *"cli_tls_chain_validation=PASS"* && "$keychain_output" == *"macOS_keychain_trust=FAIL evidence=automated"* ]]
fi

export FAKE_SECURITY_MODE=trusted
export FAKE_MODE=healthy
python3 - "$FAKE_INSPECT_DIR/id-app" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); x=json.loads(p.read_text()); x["State"]["Health"]["Status"]="unhealthy"; p.write_text(json.dumps(x))
PY
if unhealthy_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" --ca-file "$ca" live)"; then
  echo 'expected unhealthy app failure' >&2; exit 1
else
  [[ "$unhealthy_output" == *"profile_resource_identity=PASS"* && "$unhealthy_output" == *"app_readiness=FAIL"* && "$unhealthy_output" == *"https_response=NOT_RUN"* ]]
fi

if missing_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$tmp/missing.env" config)"; then
  echo 'expected missing env failure' >&2; exit 1
else
  [[ "$missing_output" == *"configuration_isolation=FAIL"* ]]
fi

python3 - "$FAKE_CONFIG_JSON" "$tmp" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); x=json.loads(p.read_text()); x["services"]["app"]["volumes"][0]["source"]=str(pathlib.Path(sys.argv[2]) / "hostile")
p.write_text(json.dumps(x))
PY
if hostile_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" config)"; then
  echo 'expected hostile mount failure' >&2; exit 1
else
  [[ "$hostile_output" == *"resolved_compose_isolation_mismatch"* ]]
fi

cp "$tmp/compose-config-good.json" "$FAKE_CONFIG_JSON"
python3 - "$FAKE_INSPECT_DIR/id-app" "$FAKE_INSPECT_DIR/id-caddy" <<'PY'
import json, pathlib, sys
app=pathlib.Path(sys.argv[1]); value=json.loads(app.read_text()); value["State"]["Health"]["Status"]="healthy"; app.write_text(json.dumps(value))
caddy=pathlib.Path(sys.argv[2]); value=json.loads(caddy.read_text()); value["Config"]["Labels"]["com.docker.compose.project"]="hostile-project"; caddy.write_text(json.dumps(value))
PY
if label_output="$("$server/scripts/first-adopter-qa.sh" --env-file "$config" --ca-file "$ca" live)"; then
  echo 'expected hostile project label failure' >&2; exit 1
else
  [[ "$label_output" == *"profile_resource_identity=FAIL"* ]]
fi

! grep -Eq '(^| )(up|down|run|build|rm|stop|start|restart|kill|prune|volume)( |$)' "$FAKE_DOCKER_LOG"
printf 'first-adopter-qa isolated tests passed\n'
