#!/usr/bin/env bash
# D-07 recovery handoff. It requires a real isolated restore target and never
# invents pairing, cache, save, or in-game continuation evidence.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: prove-recovery-known-playable.sh --prepare --fixture --no-human-observation --target-url https://host:port --compose-project playstead-restore-... --restore-receipt PATH --ca-cert PATH [--profile-root PATH] [--output PATH]

The server's --fixture restore proof is deliberately temporary, not a Mac target.
Create a real target with the production restore wrapper, then start it with:
  docker compose -p <restore-identity> -f playstead-server/docker-compose.yml up -d
Pass that wrapper's restore-receipt.json, target URL, project identity, and CA.
This command creates a clean Mac profile and writes a pending receipt only.
`--prepare` loads those four values from the required
PLAYSTEAD_RECOVERY_RESTORE_HANDOFF JSON produced by a real host restore runner.
EOF
  exit 2
}

fixture=false; pending=false; record=false; verify=false; prepare=false
receipt=""; observer=""; observed_at=""; target_url=""; compose_project=""
restore_receipt=""; ca_cert=""; profile_root=""

resolve_recovery_development_signing() {
  local configured_identity="${PLAYSTEAD_MAC_DEV_SIGNING_IDENTITY:-}"
  local configured_team="${PLAYSTEAD_TEAM_ID:-}"
  local actual_team candidate identity subject
  local candidates=()

  if [ -n "$configured_identity" ] || [ -n "$configured_team" ]; then
    if [ -z "$configured_identity" ] || [ -z "$configured_team" ]; then
      echo "PREREQUISITE: set both PLAYSTEAD_MAC_DEV_SIGNING_IDENTITY and PLAYSTEAD_TEAM_ID for the recovery UI proof." >&2
      return 77
    fi
    identity="$configured_identity"
  else
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '$2 ~ /^Apple Development: / { print $2 }')
    if [ "${#candidates[@]}" -ne 1 ]; then
      echo "PREREQUISITE: recovery UI proof found zero or multiple local Apple Development identities; set PLAYSTEAD_MAC_DEV_SIGNING_IDENTITY and PLAYSTEAD_TEAM_ID explicitly." >&2
      return 77
    fi
    identity="${candidates[0]}"
  fi

  subject="$(security find-certificate -c "$identity" -p 2>/dev/null | openssl x509 -inform pem -noout -subject -nameopt RFC2253 2>/dev/null || true)"
  actual_team="$(sed -nE 's/^subject=.*OU=([^,]+).*/\1/p' <<<"$subject")"
  if [ -z "$configured_team" ]; then
    configured_team="$actual_team"
  fi
  if [[ "$identity" != Apple\ Development:* ]] ||
     [[ ! "$configured_team" =~ ^[A-Z0-9]+$ ]] ||
     [[ ! "$actual_team" =~ ^[A-Z0-9]+$ ]] ||
     [[ "$actual_team" != "$configured_team" ]]; then
    echo "PREREQUISITE: recovery UI proof requires an Apple Development certificate whose subject OU matches PLAYSTEAD_TEAM_ID." >&2
    return 77
  fi

  PLAYSTEAD_RECOVERY_DEV_SIGNING_IDENTITY="$identity"
  PLAYSTEAD_RECOVERY_DEV_SIGNING_TEAM="$configured_team"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fixture) fixture=true ;; --no-human-observation) pending=true ;; --prepare) prepare=true ;;
    --record-human-continuation) record=true ;; --verify-human-observation-receipt) verify=true ;;
    --output|--receipt|--observer|--observed-at-utc|--target-url|--compose-project|--restore-receipt|--ca-cert|--profile-root)
      [ "$#" -gt 1 ] || usage
      case "$1" in
        --output|--receipt) receipt="$2";; --observer) observer="$2";; --observed-at-utc) observed_at="$2";;
        --target-url) target_url="$2";; --compose-project) compose_project="$2";; --restore-receipt) restore_receipt="$2";;
        --ca-cert) ca_cert="$2";; --profile-root) profile_root="$2";;
      esac; shift ;;
    *) usage ;;
  esac
  shift
done
[ -n "$receipt" ] || receipt="${TMPDIR:-/tmp}/playstead-recovery-known-playable-$$.json"
[ -n "$profile_root" ] || profile_root="${TMPDIR:-/tmp}/playstead-recovery-clean-profile-$$"

# A real restore is performed by the host-owned stage runner described by
# Playstead.Recovery.Restore. It must publish this small, non-secret handoff
# after restoring DB and blobs together into the generated Compose resources.
# The old `scripts/recovery-proof.sh --restore --fixture` is deliberately not
# accepted here: it deletes its temporary target and has no service to pair.
if [ "$prepare" = true ]; then
  handoff="${PLAYSTEAD_RECOVERY_RESTORE_HANDOFF:-}"
  if [ -z "$handoff" ] || [ ! -f "$handoff" ]; then
    echo "PREREQUISITE: set PLAYSTEAD_RECOVERY_RESTORE_HANDOFF to the JSON emitted by the host restore runner." >&2
    echo "REQUIRED: that runner must restore the verified backup chain's database and blobs together into a fresh playstead-restore-* Compose project; do not use scripts/recovery-proof.sh --restore --fixture." >&2
    exit 1
  fi
  eval "$(python3 - "$handoff" <<'PY'
import datetime as dt, json, pathlib, re, shlex, stat, sys, urllib.parse, uuid

HANDOFF_KEYS = {"schema", "correlation_id", "project", "url", "receipt_path", "ca_path"}
RECEIPT_KEYS = {"schema", "state", "correlation_id", "target", "chain_ids", "stages", "verified_at"}
TARGET_KEYS = {"project", "network", "volumes", "ports"}
REQUIRED_STAGES = ["chain", "preflight", "database", "cas", "manifest", "api"]

def refuse(message):
    raise SystemExit("REFUSED: " + message)

def load_json(path, label):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        refuse("invalid " + label + " JSON")
    if not isinstance(value, dict):
        refuse(label + " must be an object")
    return value

handoff_path = pathlib.Path(sys.argv[1])
try:
    if stat.S_IMODE(handoff_path.stat().st_mode) != 0o600:
        refuse("restore handoff must have mode 0600")
except OSError:
    refuse("restore handoff is unreadable")

handoff = load_json(handoff_path, "restore handoff")
if set(handoff) != HANDOFF_KEYS:
    refuse("restore handoff contains unknown, missing, or secret-bearing fields")
if handoff["schema"] != "playstead.restore-handoff.v1":
    refuse("restore handoff schema is not supported")
if not all(isinstance(handoff[key], str) and handoff[key] for key in HANDOFF_KEYS - {"schema"}):
    refuse("restore handoff has empty or non-string values")
try:
    uuid.UUID(handoff["correlation_id"])
except (ValueError, AttributeError):
    refuse("restore handoff correlation is not an opaque UUID")
if not re.fullmatch(r"playstead-restore-[a-z0-9-]+", handoff["project"]):
    refuse("restore handoff has a non-isolated compose project")

receipt_path = pathlib.Path(handoff["receipt_path"])
ca_path = pathlib.Path(handoff["ca_path"])
if not receipt_path.is_absolute() or not ca_path.is_absolute() or not receipt_path.is_file() or not ca_path.is_file():
    refuse("restore handoff references a missing local receipt or CA")
if receipt_path.name != "restore-receipt.json" or ca_path.name != "caddy-root-ca.pem" or receipt_path.parent != ca_path.parent or receipt_path.parent != handoff_path.parent:
    refuse("restore handoff paths are not the emitted isolated target layout")

receipt = load_json(receipt_path, "restore receipt")
if set(receipt) != RECEIPT_KEYS or receipt.get("schema") != "playstead.restore-receipt.v1":
    refuse("restore receipt has an unsupported or secret-bearing shape")
if receipt.get("state") != "verified" or receipt.get("correlation_id") != handoff["correlation_id"]:
    refuse("restore receipt is not verified or does not match the handoff correlation")
if receipt.get("stages") != REQUIRED_STAGES:
    refuse("restore receipt does not contain every completed restore stage")
if not isinstance(receipt.get("chain_ids"), list) or not receipt["chain_ids"] or not all(isinstance(v, str) and v for v in receipt["chain_ids"]):
    refuse("restore receipt has no verified backup chain")
print("parser_fixture=" + ("true" if receipt["chain_ids"] == ["fixture-only"] else "false"))
target = receipt.get("target")
if not isinstance(target, dict) or set(target) != TARGET_KEYS or target.get("project") != handoff["project"]:
    refuse("restore receipt target does not match the isolated handoff project")
if target.get("network") != handoff["project"] + "_default" or target.get("volumes") != [handoff["project"] + "_db", handoff["project"] + "_blobs"]:
    refuse("restore receipt target is not an isolated Compose resource set")
ports = target.get("ports")
if not isinstance(ports, dict) or not isinstance(ports.get("https"), int) or not (1 <= ports["https"] <= 65535):
    refuse("restore receipt target lacks an HTTPS port")
url = urllib.parse.urlparse(handoff["url"])
try:
    url_port = url.port
except ValueError:
    refuse("restore handoff URL has an invalid port")
if url.scheme != "https" or url.hostname != "localhost" or url.username or url.password or url.path not in ("", "/") or url.query or url.fragment or url_port != ports["https"]:
    refuse("restore handoff URL does not match the isolated HTTPS target")
try:
    verified_at = dt.datetime.fromisoformat(receipt["verified_at"].replace("Z", "+00:00"))
    if verified_at.tzinfo is None or dt.datetime.now(dt.timezone.utc) - verified_at.astimezone(dt.timezone.utc) > dt.timedelta(hours=24) or verified_at > dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=5):
        refuse("restore receipt is stale or has an invalid verification time")
except (TypeError, ValueError, AttributeError):
    refuse("restore receipt has an invalid verification time")

for key, value in (("target_url", handoff["url"]), ("compose_project", handoff["project"]), ("restore_receipt", str(receipt_path)), ("ca_cert", str(ca_path))):
    print(key + "=" + shlex.quote(value))
PY
)"
  if ! docker info >/dev/null 2>&1; then
    echo "PREREQUISITE: Docker is unavailable. Start Docker Desktop, then rerun this command." >&2
    exit 77
  fi
fi

if [ "$record" = false ] && [ "$verify" = false ]; then
  missing=""
  [ "$fixture" = true ] || missing="$missing --fixture"
  [ "$pending" = true ] || missing="$missing --no-human-observation"
  [ -n "$target_url" ] || missing="$missing --target-url"
  [[ "$compose_project" =~ ^playstead-restore-[a-z0-9-]+$ ]] || missing="$missing --compose-project"
  [ -f "$restore_receipt" ] || missing="$missing --restore-receipt"
  [ -f "$ca_cert" ] || missing="$missing --ca-cert"
  if [ -n "$missing" ]; then
    echo "REFUSED: no real isolated restore target was supplied; missing:$missing" >&2; usage
  fi
  if ! curl --fail --silent --show-error --cacert "$ca_cert" "$target_url/healthz" >/dev/null; then
    echo "REFUSED: isolated target is unreachable at $target_url/healthz with the supplied CA." >&2
    echo "START: docker compose -p $compose_project -f playstead-server/docker-compose.yml up -d" >&2
    exit 1
  fi

  if [ "$parser_fixture" = true ]; then
    # Plan 05-12's parser-only fixture exercises this boundary without
    # fabricating a Mac execution. It can never create a known-playable pass.
    mkdir -m 700 -p "$profile_root"
    printf '%s\n' 'Parser fixture only. Not a Mac recovery profile.' >"$profile_root/README"
  else
    # A prepared handoff proves restored service data, not client use. Drive
    # the real app through clean launch, TLS pairing request, exit, and relaunch.
    command -v xcodebuild >/dev/null 2>&1 || {
      echo "PREREQUISITE: xcodebuild is unavailable; run this proof on a Mac with Xcode installed." >&2
      exit 77
    }
    resolve_recovery_development_signing || exit $?
    [ ! -e "$profile_root" ] || {
      echo "REFUSED: clean profile root already exists; choose a new --profile-root" >&2
      exit 1
    }
    mkdir -m 700 -p "$profile_root"
    printf '%s\n' 'Clean D-07 profile. Do not copy credentials or prior saves into it.' >"$profile_root/README"
    # The retained handoff CA is an input to curl already, but a direct app
    # cannot rely on system trust. Convert one owned, non-secret DER copy for
    # its recovery-only anchors-only TLS evaluation; never modify Keychain or
    # system trust settings.
    recovery_trust_anchor="$profile_root/recovery-direct-ca.der"
    openssl x509 -in "$ca_cert" -outform DER -out "$recovery_trust_anchor" || {
      echo "REFUSED: retained handoff CA could not be converted to DER." >&2
      exit 1
    }
    chmod 600 "$recovery_trust_anchor"
    ui_report="$profile_root/mac-ui-launch.json"
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    mac_root="$(cd "$script_dir/../.." && pwd)"
    build_root="$profile_root/xcode-build"
    # Keep this DEBUG recovery app distinct from an installed/running Release
    # Playstead.app. This is intentionally a stable, recovery-only identifier:
    # it is not a product identity and is verified from the built Info.plist
    # before the app is executed.
    recovery_bundle_id="dev.playstead.mac.recovery.direct"
    # Build the app target only. In particular, do not create or launch the
    # Gatekeeper-rejected PlaysteadUITests-Runner.app on this recovery path.
    xcodebuild build -project "$mac_root/Playstead.xcodeproj" -target Playstead \
      -configuration Debug SYMROOT="$build_root" OBJROOT="$build_root/obj" \
      SHARED_PRECOMPS_DIR="$build_root/precomps" \
      CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$PLAYSTEAD_RECOVERY_DEV_SIGNING_IDENTITY" \
      DEVELOPMENT_TEAM="$PLAYSTEAD_RECOVERY_DEV_SIGNING_TEAM" PROVISIONING_PROFILE_SPECIFIER= \
      PRODUCT_BUNDLE_IDENTIFIER="$recovery_bundle_id"
    app_path="$build_root/Debug/Playstead.app"
    app_executable="$app_path/Contents/MacOS/Playstead"
    [ -x "$app_executable" ] || {
      echo "REFUSED: direct recovery build did not produce Playstead.app." >&2
      exit 1
    }
    codesign --verify --deep --strict "$app_path" || {
      echo "REFUSED: direct recovery Playstead.app signature did not verify." >&2
      exit 1
    }
    built_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist" 2>/dev/null)"
    [ "$built_bundle_id" = "$recovery_bundle_id" ] || {
      echo "REFUSED: direct recovery build did not retain its isolated bundle identifier." >&2
      exit 1
    }

    # Launch only this profile-owned, uniquely identified app through
    # LaunchServices. `open -n -W` tracks the exact app-path request (not a
    # bundle-name lookup or a process-name match), so this proof never needs
    # Apple events, Accessibility permission, process termination, or the
    # XCUITest runner. The recovery view closes itself after its bounded
    # request; the report is accepted only after PairingCoordinator reaches
    # awaiting-approval.
    run_direct_launch() {
      rm -f "$ui_report"
      open -n -W \
        --env "PLAYSTEAD_UI_TESTING=1" \
        --env "PLAYSTEAD_UI_TEST_LIVE_SERVER=1" \
        --env "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED=1" \
        --env "PLAYSTEAD_UI_TEST_LIVE_ROOT=$profile_root" \
        --env "PLAYSTEAD_UI_TEST_KEYCHAIN=$profile_root/recovery-ui.keychain-db" \
        --env "PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE=dev.playstead.mac.live.$(uuidgen | tr '[:upper:]' '[:lower:]')" \
        --env "PLAYSTEAD_RECOVERY_DIRECT_PAIRING_TARGET=$target_url" \
        --env "PLAYSTEAD_RECOVERY_DIRECT_REPORT=$ui_report" \
        --env "PLAYSTEAD_RECOVERY_DIRECT_TRUST_ANCHOR=$recovery_trust_anchor" \
        "$app_path" >/dev/null 2>&1 &
      launch_request_pid=$!
      for _ in $(seq 1 250); do
        [ -f "$ui_report" ] && break
        kill -0 "$launch_request_pid" 2>/dev/null || break
        sleep 0.1
      done
      if [ ! -f "$ui_report" ]; then
        echo "REFUSED: direct recovery app did not confirm a pairing request." >&2
        exit 1
      fi
      wait "$launch_request_pid" || {
        echo "REFUSED: direct recovery LaunchServices request did not exit cleanly." >&2
        exit 1
      }
    }
    run_direct_launch
    run_direct_launch
    [ -f "$ui_report" ] || {
      echo "REFUSED: direct recovery app completed without its launch report." >&2
      exit 1
    }
  fi
fi

python3 - "$fixture" "$pending" "$record" "$verify" "$receipt" "$observer" "$observed_at" "$target_url" "$compose_project" "$restore_receipt" "$profile_root" "${ui_report:-}" "${parser_fixture:-false}" <<'PY'
import json, pathlib, re, sys, uuid
(fixture, pending, record, verify, receipt_name, observer, observed_at, target_url, compose_project, restore_receipt_name, profile_root, ui_report_name, parser_fixture) = sys.argv[1:]
fixture, pending, record, verify = [x == "true" for x in (fixture, pending, record, verify)]
receipt, profile = pathlib.Path(receipt_name), pathlib.Path(profile_root)
statement = "restore data verified; known-playable proof pending"
def load(path):
    try: return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc: raise SystemExit("invalid recovery receipt") from exc
if verify:
    data = load(receipt); needed = ("schema", "known_playable", "observer", "observed_at_utc", "fixture_identity", "continuation_result", "correlation_id", "launch_exit_relaunch", "restore_correlation_id")
    if data.get("known_playable") != "human_observed" or any(not data.get(k) for k in needed): raise SystemExit("human observation receipt is incomplete")
    if data["fixture_identity"] != "legal-homebrew-fixture-v1" or data["continuation_result"] != "continued_beyond_pre_save_point": raise SystemExit("human observation receipt has invalid fixture or continuation result")
    print(receipt)
elif record:
    if not fixture or not observer.strip() or not re.fullmatch(r".+Z", observed_at): raise SystemExit("recording requires the fixture, named observer, and UTC timestamp")
    data = load(receipt)
    if data.get("known_playable") != "pending" or data.get("statement") != statement: raise SystemExit("only the correlation-linked pending receipt may be completed")
    data.update({"known_playable":"human_observed", "observer":observer, "observed_at_utc":observed_at, "continuation_result":"continued_beyond_pre_save_point"})
    receipt.write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8"); print(receipt)
else:
    restore = load(pathlib.Path(restore_receipt_name))
    if restore.get("state") != "verified" or not restore.get("correlation_id"): raise SystemExit("restore receipt is not a verified, correlation-linked isolated restore")
    if parser_fixture == "true":
        data = {"schema":"playstead.known-playable-receipt.v1", "known_playable":"pending", "statement":statement, "fixture_identity":"legal-homebrew-fixture-v1", "correlation_id":str(uuid.uuid4()), "restore_correlation_id":restore["correlation_id"], "target_url":target_url, "compose_project":compose_project, "clean_profile_root":str(profile), "pairing":"not_run_parser_fixture", "capability_adapter_identity":"not_run_parser_fixture", "cached_bytes":"not_run_parser_fixture", "save_lineage":"not_run_parser_fixture", "launch_exit_relaunch":"not_run_parser_fixture"}
    else:
        report = load(pathlib.Path(ui_report_name))
        expected = {"schema":"playstead.recovery-mac-ui.v1", "state":"pairing_requested", "target_url":target_url, "profile_root":str(profile), "launch_exit_relaunch":"passed"}
        if any(report.get(key) != value for key, value in expected.items()): raise SystemExit("clean Mac UI report is missing or does not match the prepared target")
        if set(report) != set(expected).union({"pairing"}) or report.get("pairing") != "requested_in_app": raise SystemExit("clean Mac UI report has an unsupported or incomplete shape")
        data = {"schema":"playstead.known-playable-receipt.v1", "known_playable":"pending", "statement":statement, "fixture_identity":"legal-homebrew-fixture-v1", "correlation_id":str(uuid.uuid4()), "restore_correlation_id":restore["correlation_id"], "target_url":target_url, "compose_project":compose_project, "clean_profile_root":str(profile), "pairing":"requested_in_app; owner approval and convergence pending", "capability_adapter_identity":"not_run_pending_pairing", "cached_bytes":"not_run_pending_pairing", "save_lineage":"not_run_pending_pairing", "launch_exit_relaunch":"passed"}
    receipt.parent.mkdir(parents=True, exist_ok=True); receipt.write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
    print("target_url=" + target_url); print("compose_project=" + compose_project); print("clean_profile_root=" + str(profile)); print("receipt=" + str(receipt))
PY
