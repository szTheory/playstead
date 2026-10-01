#!/usr/bin/env bash
# Same-host join for a retained, verified restore and the clean Mac recovery UI.
# Private handoff values remain shell-local and are never printed or retained.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HANDOFF="${PLAYSTEAD_RECOVERY_RESTORE_HANDOFF:-}"
VALIDATE_ONLY=false
REPORT_VALIDATION_ONLY=""
PATCH_XCTESTRUN=false
BROWSER_TRUST_MODE=""
RUN_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
FAILED_STAGE="handoff_validation"

usage() {
  printf '%s\n' 'usage: recovery-e2e.sh [--validate-only|--validate-ui-report PATH|--patch-xctestrun|--prepare-browser-trust|--check-browser-trust]' >&2
  exit 2
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validate-only) VALIDATE_ONLY=true ;;
    --validate-ui-report) [ "$#" -gt 1 ] || usage; REPORT_VALIDATION_ONLY="$2"; shift ;;
    --patch-xctestrun) PATCH_XCTESTRUN=true ;;
    --prepare-browser-trust) [ -z "$BROWSER_TRUST_MODE" ] || usage; BROWSER_TRUST_MODE=ensure ;;
    --check-browser-trust) [ -z "$BROWSER_TRUST_MODE" ] || usage; BROWSER_TRUST_MODE=check ;;
    *) usage ;;
  esac
  shift
done

emit_local_receipt() (
  umask 077
  local evidence_root
  evidence_root="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-receipt.XXXXXX")" || exit 77
  trap 'rm -rf "$evidence_root"' EXIT
  mkdir "$evidence_root/evidence"
  python3 - "$RUN_ID" "$1" "$2" "$evidence_root/evidence/recovery-e2e.json" <<'PY'
import json,sys
with open(sys.argv[4],"w",encoding="utf-8") as output:
    json.dump({"schema":"playstead.recovery-e2e-local.v1","run_id":sys.argv[1],"lane":"same_host_restored_target","stage":sys.argv[2],"outcome":sys.argv[3]},output,sort_keys=True)
    output.write("\n")
PY
  if ! "$SCRIPT_DIR/sanitize-evidence.sh" --input "$evidence_root" --output "$evidence_root/sanitized" >/dev/null 2>&1; then
    printf '%s\n' 'BLOCKED: local recovery receipt failed evidence sanitization' >&2
    exit 77
  fi
  python3 - "$evidence_root/sanitized/recovery-e2e.json" <<'PY'
import json,pathlib,sys
print(json.dumps(json.loads(pathlib.Path(sys.argv[1]).read_text()),sort_keys=True))
PY
)

blocked() {
  emit_local_receipt "$FAILED_STAGE" blocked || exit 77
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 77
}

if [ -z "$HANDOFF" ] || [ ! -f "$HANDOFF" ]; then
  blocked 'retained local restore handoff is unavailable'
fi

# Validate the exact v1 handoff, adjacent private receipt and CA before any
# root creation, Docker target inspection, or network request. Python emits
# shell assignments only into this process; nothing is echoed to the caller.
if ! parsed_values="$(python3 - "$HANDOFF" <<'PY'
import datetime as dt, json, pathlib, re, shlex, stat, sys, urllib.parse, uuid

def refuse(): raise SystemExit(1)
def load(path):
    try:
        value=json.loads(path.read_text(encoding="utf-8"))
    except Exception: refuse()
    if not isinstance(value,dict): refuse()
    return value

handoff_path=pathlib.Path(sys.argv[1])
try:
    if stat.S_IMODE(handoff_path.stat().st_mode)!=0o600: refuse()
except OSError: refuse()
h=load(handoff_path)
if set(h)!={"schema","correlation_id","project","url","receipt_path","ca_path"}: refuse()
if h["schema"]!="playstead.restore-handoff.v1": refuse()
if not all(isinstance(h[k],str) and h[k] for k in h): refuse()
try: uuid.UUID(h["correlation_id"])
except (ValueError,AttributeError): refuse()
if not re.fullmatch(r"playstead-restore-[a-z0-9-]+",h["project"]): refuse()
receipt_path=pathlib.Path(h["receipt_path"]); ca_path=pathlib.Path(h["ca_path"])
if not receipt_path.is_absolute() or not ca_path.is_absolute(): refuse()
if receipt_path.name!="restore-receipt.json" or ca_path.name!="caddy-root-ca.pem": refuse()
if receipt_path.parent!=handoff_path.parent or ca_path.parent!=handoff_path.parent: refuse()
try:
    for p in (receipt_path,ca_path):
        if not p.is_file() or stat.S_IMODE(p.stat().st_mode)!=0o600: refuse()
except OSError: refuse()
r=load(receipt_path)
if set(r)!={"schema","state","correlation_id","target","chain_ids","stages","verified_at"}: refuse()
if r.get("schema")!="playstead.restore-receipt.v1" or r.get("state")!="verified": refuse()
if r.get("correlation_id")!=h["correlation_id"]: refuse()
if r.get("stages")!=["chain","preflight","database","cas","manifest","api"]: refuse()
if not isinstance(r.get("chain_ids"),list) or not r["chain_ids"] or not all(isinstance(x,str) and x for x in r["chain_ids"]): refuse()
target=r.get("target")
if not isinstance(target,dict) or set(target)!={"project","network","volumes","ports"}: refuse()
if target.get("project")!=h["project"] or target.get("network")!=h["project"]+"_default": refuse()
if target.get("volumes")!=[h["project"]+"_db",h["project"]+"_blobs"]: refuse()
ports=target.get("ports")
if not isinstance(ports,dict) or type(ports.get("https")) is not int or not 1<=ports["https"]<=65535: refuse()
u=urllib.parse.urlparse(h["url"])
try: port=u.port
except ValueError: refuse()
if (u.scheme,u.hostname,u.username,u.password,u.path,u.query,u.fragment,port)!=("https","localhost",None,None,"","", "",ports["https"]):
    if not (u.scheme=="https" and u.hostname=="localhost" and not u.username and not u.password and u.path in ("","/") and not u.query and not u.fragment and port==ports["https"]): refuse()
try:
    verified=dt.datetime.fromisoformat(r["verified_at"].replace("Z","+00:00"))
    now=dt.datetime.now(dt.timezone.utc)
    if verified.tzinfo is None or now-verified.astimezone(dt.timezone.utc)>dt.timedelta(hours=24) or verified>now+dt.timedelta(minutes=5): refuse()
except (TypeError,ValueError,AttributeError): refuse()
for key,value in (("target_url",h["url"]),("compose_project",h["project"]),("receipt_path",str(receipt_path)),("ca_path",str(ca_path))):
    print(key+"="+shlex.quote(value))
PY
)"; then
  blocked 'retained local handoff validation failed'
fi
eval "$parsed_values"

if [ -n "${PLAYSTEAD_RECOVERY_FIXTURE_RECORD:-}" ]; then
  FAILED_STAGE="fixture_validation"
  python3 "$SCRIPT_DIR/recovery-fixture.py" "$PLAYSTEAD_RECOVERY_FIXTURE_RECORD" "$HANDOFF" \
    >/dev/null 2>&1 || blocked 'local fixture and selected backup/restore binding is invalid'
  FAILED_STAGE="handoff_validation"
fi

patch_generated_xctestrun() {
  local derived_root="$1" private_root="$2"
  PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT="$profile_root" \
  PLAYSTEAD_RECOVERY_UI_REPORT="$ui_report" \
  PLAYSTEAD_RECOVERY_UI_TRUST_ANCHOR="$ca_path" \
  python3 - "$derived_root" "$private_root" <<'PY'
import os, pathlib, plistlib, stat, sys, urllib.parse

derived = pathlib.Path(sys.argv[1]).resolve()
private = pathlib.Path(sys.argv[2]).resolve()
products = derived / "Build" / "Products"
if not products.is_dir() or private not in derived.parents:
    raise SystemExit("recovery xctestrun roots are not isolated")
app_candidates = [
    path for path in products.rglob("Playstead.app")
    if path.is_dir() and not path.is_symlink()
]
if len(app_candidates) != 1:
    raise SystemExit("expected exactly one built Playstead application")
app_path = app_candidates[0].resolve()
if products not in app_path.parents:
    raise SystemExit("built recovery application escaped DerivedData products")
try:
    app_info = plistlib.loads((app_path / "Contents" / "Info.plist").read_bytes())
except Exception:
    raise SystemExit("built recovery application metadata is unavailable")
if app_info.get("CFBundleIdentifier") != "dev.playstead.mac":
    raise SystemExit("built recovery application bundle identity is unexpected")

values = {
    "PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT": os.environ.get("PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT", ""),
    "PLAYSTEAD_RECOVERY_UI_REPORT": os.environ.get("PLAYSTEAD_RECOVERY_UI_REPORT", ""),
    "PLAYSTEAD_RECOVERY_UI_TRUST_ANCHOR": os.environ.get("PLAYSTEAD_RECOVERY_UI_TRUST_ANCHOR", ""),
    # Keep the UI test attached to this build product. On a developer Mac a
    # same-bundle app in /Applications can otherwise win LaunchServices lookup.
    "PLAYSTEAD_RECOVERY_UI_APP_PATH": str(app_path),
}
approval_mode = os.environ.get("PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL", "")
if approval_mode:
    if approval_mode != "1":
        raise SystemExit("recovery test-owner approval opt-in is invalid")
    values["PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL"] = "1"
if any(not value or "\n" in value or "\x00" in value or len(value) > 4096 for value in values.values()):
    raise SystemExit("recovery xctestrun environment contains an invalid value")
for key in ("PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT", "PLAYSTEAD_RECOVERY_UI_REPORT"):
    path = pathlib.Path(values[key]).resolve()
    if private not in path.parents:
        raise SystemExit("recovery xctestrun private path escaped the owned root")
    values[key] = str(path)
profile = pathlib.Path(values["PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT"])
if not profile.is_dir() or stat.S_IMODE(profile.stat().st_mode) != 0o700:
    raise SystemExit("recovery xctestrun profile root is not private")
report = pathlib.Path(values["PLAYSTEAD_RECOVERY_UI_REPORT"])
if report.exists():
    raise SystemExit("recovery xctestrun report path already exists")
ca = pathlib.Path(values["PLAYSTEAD_RECOVERY_UI_TRUST_ANCHOR"])
if not ca.is_file() or stat.S_IMODE(ca.stat().st_mode) != 0o600:
    raise SystemExit("recovery xctestrun trust anchor is not private")
if pathlib.Path(values["PLAYSTEAD_RECOVERY_UI_APP_PATH"]).resolve() != app_path:
    raise SystemExit("recovery xctestrun application path is not the built product")
target_file = profile / "recovery-target.url"
if target_file.is_symlink() or not target_file.is_file() or stat.S_IMODE(target_file.stat().st_mode) != 0o600:
    raise SystemExit("recovery xctestrun target file is not private")
target_data = target_file.read_bytes()
if not target_data or len(target_data) > 4096:
    raise SystemExit("recovery xctestrun target file size is invalid")
try:
    target_value = target_data.decode("utf-8")
    parsed = urllib.parse.urlparse(target_value)
    valid_port = parsed.port is not None and 1 <= parsed.port <= 65535
except (UnicodeDecodeError, ValueError):
    raise SystemExit("recovery xctestrun target file is malformed")
if parsed.scheme != "https" or parsed.hostname != "localhost" or not valid_port or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
    raise SystemExit("recovery xctestrun target file is not local HTTPS")

matches = []
for path in products.rglob("*.xctestrun"):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
        continue
    try:
        data = plistlib.loads(path.read_bytes())
    except Exception:
        continue
    targets = [
        target
        for config in data.get("TestConfigurations", [])
        if isinstance(config, dict) and config.get("Name") == "Recovery"
        for target in config.get("TestTargets", [])
        if isinstance(target, dict) and target.get("BlueprintName") == "PlaysteadUITests"
    ]
    if data.get("TestPlan", {}).get("Name") == "Recovery" and len(targets) == 1:
        matches.append((path.resolve(), targets[0]))
if len(matches) != 1:
    raise SystemExit("expected exactly one generated Recovery UI-test xctestrun")
path, target = matches[0]
if products != path and products not in path.parents:
    raise SystemExit("generated recovery xctestrun escaped DerivedData products")
expected_target_path = "__TESTROOT__/" + app_path.relative_to(products).as_posix()
if target.get("UITargetAppPath") != expected_target_path:
    raise SystemExit("generated recovery test target does not select this build product")
if expected_target_path not in target.get("DependentProductPaths", []):
    raise SystemExit("generated recovery test dependencies omit this build product")
for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
    environment = target.setdefault(key, {})
    if not isinstance(environment, dict):
        raise SystemExit("generated recovery xctestrun environment is invalid")
    environment.update(values)

raw = path.read_bytes()
temporary = path.with_name(path.name + ".recovery.tmp")
if temporary.exists():
    raise SystemExit("generated recovery xctestrun temporary path already exists")
with temporary.open("wb") as stream:
    plistlib.dump(data, stream, fmt=plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML, sort_keys=False)
os.chmod(temporary, 0o600)
temporary.replace(path)
print(path)
PY
}

if [ "$PATCH_XCTESTRUN" = true ]; then
  patch_private_root="${PLAYSTEAD_RECOVERY_PRIVATE_ROOT:-}"
  patch_derived_root="${PLAYSTEAD_RECOVERY_DERIVED_DATA:-}"
  profile_root="${PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT:-}"
  ui_report="${PLAYSTEAD_RECOVERY_UI_REPORT:-}"
  [ -n "$patch_private_root" ] && [ -n "$patch_derived_root" ] && \
    [ -n "$profile_root" ] && [ -n "$ui_report" ] || usage
  patched_xctestrun="$(patch_generated_xctestrun "$patch_derived_root" "$patch_private_root")" || \
    blocked 'generated local test-run environment could not be prepared'
  [ -f "$patched_xctestrun" ] || blocked 'generated local test-run environment is unavailable'
  printf '%s\n' "$patched_xctestrun"
  exit 0
fi

if [ "$VALIDATE_ONLY" = true ]; then
  printf '%s\n' 'RECOVERY_HANDOFF_VALID'
  exit 0
fi

run_browser_trust() {
  local trust_mode="$1" trust_line trust_rc=0
  trust_line="$(PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" \
      "$SCRIPT_DIR/recovery-browser-trust.sh" "$trust_mode" 2>/dev/null)" || trust_rc=$?
  if [[ "$trust_line" =~ ^RECOVERY_BROWSER_TRUST\ stage=[a-z_]+\ outcome=(trusted|required|already_trusted|installed|removed|unowned|blocked|conflict|authorization_required|install_failed|reconcile_required)$ ]]; then
    [ -n "$BROWSER_TRUST_MODE" ] && printf '%s\n' "$trust_line"
    if [ "$trust_rc" -ne 0 ]; then return 1; fi
    if [ "$trust_mode" = ensure ] && [[ "$trust_line" == *'outcome=installed' || "$trust_line" == *'outcome=already_trusted' ]]; then return 0; fi
    if [ "$trust_mode" = check ] && [[ "$trust_line" == *'outcome=trusted' ]]; then return 0; fi
  fi
  return 1
}

if [ -n "$BROWSER_TRUST_MODE" ]; then
  run_browser_trust "$BROWSER_TRUST_MODE" || exit 77
  exit 0
fi
if [ -z "$REPORT_VALIDATION_ONLY" ]; then
  FAILED_STAGE="browser_trust"
  if ! run_browser_trust check; then
    blocked 'local browser trust is not prepared for the retained recovery target'
  fi
fi
FAILED_STAGE="preflight"

validate_ui_report() {
  python3 - "$1" <<'PY'
import json,pathlib,re,sys,uuid
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception: raise SystemExit(1)
expected={"clean_launch","local_ca_pairing_request","owner_approval","cursor_convergence","cache_preflight","persistent_save_transport_restore","controlled_exit","relaunch"}
order=["clean_launch","local_ca_pairing_request","owner_approval","cursor_convergence","cache_preflight","persistent_save_transport_restore","controlled_exit","relaunch"]
if not isinstance(data,dict) or set(data)!={"schema","run_id","lane","stages","outcome"}: raise SystemExit(1)
if data["schema"]!="playstead.recovery-mac-ui.v2" or data["lane"]!="restored_target": raise SystemExit(1)
try: uuid.UUID(data["run_id"])
except Exception: raise SystemExit(1)
stages=data["stages"]
if not isinstance(stages,dict) or set(stages)!=expected: raise SystemExit(1)
if any(value not in {"passed","blocked","not_run"} for value in stages.values()): raise SystemExit(1)
outcome="passed" if all(value=="passed" for value in stages.values()) else "blocked"
if data["outcome"]!=outcome: raise SystemExit(1)
first_incomplete=next((stage for stage in order if stages[stage]!="passed"),"complete")
print(outcome,first_incomplete)
PY
}

classify_xcode_failure() {
  python3 - "$1" <<'PY'
import pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8",errors="replace").lower()
checks=(
    ("code_signing",("requires a provisioning profile","provisioning profile","no signing certificate","signing certificate")),
    ("test_plan",("not a member of the specified test plan","not a member of the test plan","isn't a member","isn’t a member")),
    ("test_launch",("failed to launch","unable to launch","launch timed out","test runner failed to start")),
    ("xctest",("** test failed **","test case")),
    ("build",("** build failed **"," error:","fatal error:")),
)
for stage,needles in checks:
    if any(needle in text for needle in needles):
        print(stage)
        break
else:
    print("clean_mac_ui")
PY
}

emit_safe_ui_diagnostic() {
  python3 - "$1" "$2" "${3:-}" "${4:-}" <<'PY' >&2
import json,pathlib,re,subprocess,sys

log=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8",errors="replace")
report=pathlib.Path(sys.argv[2])
result_bundle=pathlib.Path(sys.argv[3]) if len(sys.argv)>3 and sys.argv[3] else None
approval_log=pathlib.Path(sys.argv[4]) if len(sys.argv)>4 and sys.argv[4] else None
report_state="missing"
report_stage="unknown"
if report.is_file():
    report_state="invalid"
    try:
        data=json.loads(report.read_text(encoding="utf-8"))
        stages=data.get("stages",{})
        order=["clean_launch","local_ca_pairing_request","owner_approval","cursor_convergence","cache_preflight","persistent_save_transport_restore","controlled_exit","relaunch"]
        if data.get("schema")=="playstead.recovery-mac-ui.v2" and isinstance(stages,dict) and all(key in stages for key in order):
            report_state="valid"
            report_stage=next((key for key in order if stages[key]!="passed"),"complete")
    except Exception:
        pass

markers=(
    "recovery-ui-library-not-foreground",
    "recovery-ui-fixture-launch-failed",
    "recovery-ui-fixture-download-failed",
    "recovery-ui-preflight=missing-or-invalid-prepared-target",
    "recovery-ui-keychain-not-materialized",
    "recovery-ui-target-file-not-created-restricted",
    "recovery-ui-target-url-scheme",
    "recovery-ui-target-url-host",
    "recovery-ui-target-url-port",
    "recovery-ui-target-file-content",
    "recovery-ui-library-surface-unavailable",
    "recovery-ui-list-control-unavailable",
    "recovery-ui-list-control-not-hittable",
    "recovery-ui-pairing-control-unavailable",
    "recovery-ui-pairing-control-not-hittable",
    "recovery-ui-ca-control-unavailable",
    "recovery-ui-ca-control-not-hittable",
    "recovery-ui-ca-candidate-status-unavailable",
    "recovery-ui-ca-candidate-status-idle",
    "recovery-ui-ca-candidate-status-candidate_supplied",
    "recovery-ui-ca-candidate-status-candidate_unavailable",
    "recovery-ui-ca-candidate-status-candidate_loaded",
    "recovery-ui-ca-candidate-status-candidate_invalid",
    "recovery-ui-ca-candidate-status-native_picker",
    "recovery-ui-ca-candidate-status-unknown",
    "recovery-ui-ca-test-candidate-rejected",
    "recovery-ui-ca-file-dialog-unavailable",
    "recovery-ui-ca-location-sheet-unavailable",
    "recovery-ui-ca-location-field-unavailable",
    "recovery-ui-ca-location-navigation-unconfirmed",
    "recovery-ui-ca-file-unavailable",
    "recovery-ui-ca-open-unavailable",
    "recovery-ui-ca-open-disabled",
    "recovery-ui-ca-selection-not-confirmed",
    "recovery-ui-pairing-url-control-unavailable",
    "recovery-ui-pairing-request-control-unavailable",
    "recovery-ui-pairing-request-control-not-hittable",
    "recovery-ui-pairing-target-prefill-host-inconsistent",
    "recovery-ui-pairing-request-not-confirmed",
    "recovery-ui-owner-approval-timeout",
    "recovery-ui-cursor-convergence-timeout",
    "recovery-ui-adapter-pairing-dismiss-unavailable",
    "recovery-ui-adapter-pairing-dismiss-not-hittable",
    "recovery-ui-adapter-settings-unavailable",
    "recovery-ui-adapter-settings-not-hittable",
    "recovery-ui-adapter-settings-surface-unavailable",
    "recovery-ui-adapter-pane-unavailable",
    "recovery-ui-adapter-pane-not-hittable",
    "recovery-ui-adapter-install-control-unavailable",
    "recovery-ui-adapter-install-control-not-ready",
    "recovery-ui-adapter-install-status-unavailable",
    "recovery-ui-adapter-install-timeout",
    "recovery-ui-adapter-install-failed",
    "recovery-ui-adapter-pairing-menu-unavailable",
    "recovery-ui-adapter-pairing-command-unavailable",
    "recovery-ui-adapter-cache-readout-unavailable",
    "recovery-ui-fixture-asset-identity-unavailable",
    "recovery-ui-fixture-registry-invalid",
    "recovery-ui-fixture-match-sync_pending",
    "recovery-ui-fixture-match-registry_missing",
    "recovery-ui-fixture-match-registry_invalid",
    "recovery-ui-fixture-match-game_missing",
    "recovery-ui-fixture-match-game_ambiguous",
    "recovery-ui-fixture-match-unreported",
    "recovery-ui-fixture-save-registry_unavailable",
    "recovery-ui-fixture-save-game_unmatched",
    "recovery-ui-fixture-save-line_missing",
    "recovery-ui-fixture-save-revision_missing",
    "recovery-ui-fixture-save-revision_not_uploaded",
    "recovery-ui-fixture-save-prefetch_missing_or_mismatched",
    "recovery-ui-fixture-save-unreported",
    "recovery-ui-fixture-save-restore-not_materialized",
    "recovery-ui-fixture-save-restore-save_path_unavailable",
    "recovery-ui-fixture-save-restore-materialization_unconfirmed",
    "recovery-ui-fixture-save-restore-unreported",
    "recovery-ui-pairing-target-prefill-not-applied",
    "recovery-ui-pairing-target-prefill-unavailable",
    "recovery-ui-relaunch-fixture-state-not-restored",
    "recovery-ui-relaunch-sync-timeout",
    "recovery-ui-test-owner-request-write-failed",
    "recovery-ui-cache-readout-unavailable",
    "recovery-ui-fixture-action-unavailable",
    "recovery-ui-fixture-cache-status-timeout",
    "recovery-ui-fixture-download-not-hittable",
    "recovery-ui-fixture-download-retry",
    "recovery-ui-fixture-download-timeout",
    "recovery-ui-fixture-emulator-application-unavailable",
    "recovery-ui-fixture-emulator-exit-not-clean",
    "recovery-ui-fixture-emulator-process-identity-mismatch",
    "recovery-ui-fixture-emulator-process-unreadable",
    "recovery-ui-fixture-emulator-start-unconfirmed",
    "recovery-ui-fixture-host-exit-unconfirmed",
    "recovery-ui-fixture-library-navigation-unavailable",
    "recovery-ui-fixture-library-surface-unavailable",
    "recovery-ui-fixture-normal-quit-rejected",
    "recovery-ui-fixture-normal-quit-timeout",
    "recovery-ui-fixture-pairing-dismiss-unavailable",
    "recovery-ui-fixture-play-unavailable",
    "recovery-ui-fixture-save-materialization-unconfirmed",
    "recovery-ui-pairing-command-unavailable",
    "recovery-ui-pairing-menu-unavailable",
    "recovery-ui-cache-preflight-timeout",
    "recovery-ui-cache-preflight-blocked",
    "recovery-ui-persistent-save-requires-real-session",
    "recovery-ui-controlled-exit-not-confirmed",
    "recovery-ui-relaunch-failed",
    "recovery-ui-report-write-failed",
)
marker=next((item for item in markers if item in log),"none")
pairing_failure=re.search(r"recovery-ui-pairing-request-failed-(expired|already_redeemed|not_approved|slow_down|not_found|denied|invalid_response|keychain_write_failed|transport|insecure_address|certificate_pin|certificate_trust|other)",log)
if pairing_failure:
    marker="recovery-ui-pairing-request-failed-"+pairing_failure.group(1)
prefill_failure=re.search(r"recovery-ui-pairing-target-prefill-(missing|malformed|scheme|host|port|userinfo|path|query|fragment|invalid|other|unavailable)",log)
if prefill_failure:
    marker="recovery-ui-pairing-target-prefill-"+prefill_failure.group(1)
line=f"RECOVERY_UI_DIAGNOSTIC report={report_state} stage={report_stage} marker={marker}"
marker_evidence=[log]
failure_payload_text=[]
failure_location_fields=[]
counts=re.search(r"recovery-ui-ca-file-unavailable outline-rows=(\d+) tables=(\d+) buttons=(\d+) label-match=(\d+) value-match=(\d+) identifier-match=(\d+)",log)
if counts:
    line+=" ca_file_row_counts="+",".join(counts.groups())

# xcresult summaries contain device descriptions, test names, failure text and
# private paths. Reduce them in-process to a small enum and bounded counters.
if result_bundle and result_bundle.is_dir():
    try:
        completed=subprocess.run(
            ["xcrun","xcresulttool","get","test-results","summary","--path",str(result_bundle),"--compact"],
            capture_output=True,text=True,timeout=15,check=False
        )
        summary=json.loads(completed.stdout) if completed.returncode==0 else {}
    except Exception:
        summary={}
    if isinstance(summary,dict) and summary:
        result=summary.get("result")
        result_map={"Passed":"passed","Failed":"failed","Skipped":"skipped","Expected Failure":"expected_failure","unknown":"unknown"}
        result=result_map.get(result,"unknown")
        metric_names=("totalTestCount","passedTests","failedTests","skippedTests")
        metrics=[]
        for name in metric_names:
            value=summary.get(name)
            metrics.append(str(value) if type(value) is int and 0<=value<=10000 else "unknown")
        line+=" xcresult="+result+" tests="+",".join(metrics)

        failures=summary.get("testFailures",[])
        if isinstance(failures,dict):
            failures=[failures]

        def collect_failure_payload(value, failure_context=False):
            if isinstance(value,dict):
                is_failure=(failure_context or value.get("nodeType")=="Failure Message"
                    or value.get("isAssociatedWithFailure") is True
                    or any(key in value for key in ("failureText","failureMessage","issueDescription")))
                if is_failure:
                    for key in ("message","failureText","failureMessage","issueDescription","details","title"):
                        child=value.get(key)
                        if isinstance(child,str): failure_payload_text.append(child)
                    source_values=[]
                    for key in ("fileName","filename","sourceFile","source","file","path","url"):
                        child=value.get(key)
                        if isinstance(child,str): source_values.append(child)
                    location=value.get("documentLocationInCreatingWorkspace")
                    if isinstance(location,str): source_values.append(location)
                    elif isinstance(location,dict):
                        for key in ("url","fileName","filename","path"):
                            child=location.get(key)
                            if isinstance(child,str): source_values.append(child)
                    line_value=None
                    for key in ("line","lineNumber","lineNumberInFile","startingLineNumber"):
                        child=value.get(key)
                        if type(child) is int or (isinstance(child,str) and child.isdigit()):
                            line_value=int(child)
                            break
                    for source_value in source_values:
                        failure_location_fields.append((source_value,line_value))
                for key,child in value.items():
                    collect_failure_payload(child, is_failure or key in ("testFailures","failures","failureDetails","issues"))
            elif isinstance(value,list):
                for child in value: collect_failure_payload(child,failure_context)

        collect_failure_payload(failures,True)
        failure_text=" ".join(
            item.get("failureText","") for item in failures
            if isinstance(item,dict) and isinstance(item.get("failureText", ""),str)
        ).lower()
        marker_evidence.append(failure_text)
        categories=(
            ("signing",("provisioning profile","signing certificate","code signing","codesign")),
            ("test_plan",("not a member of the specified test plan","not a member of the test plan")),
            ("timeout",("timed out","timeout")),
            ("launch",("failed to launch","unable to launch","could not launch","launch failed")),
            ("assertion",("xctassert","assertion failed","test failed","failed -")),
            ("runner",("test runner","test bundle","runner connection","test manager")),
        )
        failure_category=next((name for name,needles in categories if any(needle in failure_text for needle in needles)),"none")
        line+=" failure="+failure_category

        try:
            completed=subprocess.run(
                ["xcrun","xcresulttool","get","test-results","tests","--path",str(result_bundle),"--compact"],
                capture_output=True,text=True,timeout=15,check=False
            )
            tests=json.loads(completed.stdout) if completed.returncode==0 else {}
        except Exception:
            tests={}
        nodes=[]
        def flatten(value):
            if isinstance(value,dict):
                if isinstance(value.get("nodeType"),str):
                    nodes.append(value)
                for child in value.values():
                    flatten(child)
            elif isinstance(value,list):
                for child in value:
                    flatten(child)
        flatten(tests.get("testNodes",[]) if isinstance(tests,dict) else [])
        cases=[node for node in nodes if node.get("nodeType")=="Test Case"]
        failed=[node for node in cases if node.get("result")=="Failed"]
        details=" ".join(
            node.get("details","") for node in nodes
            if node.get("nodeType")=="Failure Message" and isinstance(node.get("details", ""),str)
        ).lower()
        marker_evidence.append(details)
        detail_state="unavailable"
        failed_ids=[
            node.get("nodeIdentifierURL") or node.get("nodeIdentifier")
            for node in failed
            if isinstance(node.get("nodeIdentifierURL") or node.get("nodeIdentifier"),str)
        ]
        if len(failed_ids)==1:
            try:
                completed=subprocess.run(
                    ["xcrun","xcresulttool","get","test-results","test-details","--path",str(result_bundle),"--test-id",failed_ids[0],"--compact"],
                    capture_output=True,text=True,timeout=15,check=False
                )
                test_details=json.loads(completed.stdout) if completed.returncode==0 else {}
                detail_state="parsed" if isinstance(test_details,dict) and test_details else "empty"
            except Exception:
                test_details={}
                detail_state="unavailable"
            # Inspect only the decoded detail tree; keep all text in process.
            def collect_failure_text(value):
                found=[]
                if isinstance(value,dict):
                    node_type=value.get("nodeType")
                    if node_type=="Failure Message":
                        found.extend(str(child) for child in value.values() if isinstance(child,(str,int,float)))
                    if value.get("isAssociatedWithFailure") is True and isinstance(value.get("title"),str):
                        found.append(value["title"])
                    for child in value.values():
                        found.extend(collect_failure_text(child))
                elif isinstance(value,list):
                    for child in value:
                        found.extend(collect_failure_text(child))
                return found
            details+=" "+" ".join(collect_failure_text(test_details)).lower()
            try:
                completed=subprocess.run(
                    ["xcrun","xcresulttool","get","test-results","activities","--path",str(result_bundle),"--test-id",failed_ids[0],"--compact"],
                    capture_output=True,text=True,timeout=15,check=False
                )
                activities=json.loads(completed.stdout) if completed.returncode==0 else {}
            except Exception:
                activities={}
            failure_activity_titles=[]
            def collect_failure_activities(value):
                if isinstance(value,dict):
                    if value.get("isAssociatedWithFailure") is True and isinstance(value.get("title"),str):
                        failure_activity_titles.append(value["title"])
                    for child in value.values():
                        collect_failure_activities(child)
                elif isinstance(value,list):
                    for child in value:
                        collect_failure_activities(child)
            collect_failure_activities(activities)
            details+=" "+" ".join(failure_activity_titles).lower()
            marker_evidence.append(details)
        failure_category=next((name for name,needles in categories if any(needle in details for needle in needles)),"none")
        error_lines=[
            line.lower() for line in log.splitlines()
            if re.search(r"\b(error|failed|failure|denied|timed out|unable|cannot|not permitted)\b",line,re.I)
        ]
        error_text=" ".join(error_lines)
        marker_evidence.append(error_text)
        log_categories=(
            ("test_plan",("not a member of the specified test plan","not a member of the test plan")),
            ("signing_profile",("requires a provisioning profile","no provisioning profile","profile is required")),
            ("signing_identity",("no signing certificate","no signing identity","identity not found")),
            ("signing_entitlement",("entitlement error","entitlement mismatch","missing required entitlement","not entitled","entitlement is not allowed")),
            ("signing_signature",("code signature invalid","signature verification failed","invalid signature","code signing failed")),
            ("timeout",("timed out","timeout")),
            ("launch",("failed to launch","unable to launch","could not launch","launch failed","application launch failure")),
            ("assertion",("xctassert","assertion failed")),
            ("accessibility",("failed to get matching snapshots","no matches found","multiple matching elements","accessibility automation")),
            ("runner",("test runner","test bundle","runner connection","test manager","test host","connection interrupted")),
        )
        log_category=next((name for name,needles in log_categories if any(needle in error_text for needle in needles)),"unclassified" if error_lines else "none")
        signing_category=next((name for name in ("profile","identity","entitlement","signature") if name in log_category),"none")
        detail_failure_nodes=sum(node.get("nodeType")=="Failure Message" for node in nodes)
        line+=" xctest_cases="+str(min(len(cases),10000))+" xctest_failed="+str(min(len(failed),10000))+" detail="+failure_category+" detail_query="+detail_state+" failure_nodes="+str(min(detail_failure_nodes,10000))+" failure_activities="+str(min(len(failure_activity_titles) if len(failed_ids)==1 else 0,10000))+" error_lines="+str(min(len(error_lines),10000))+" log_class="+log_category+" signing_class="+signing_category
        ui_source="unknown"
        ui_line="unknown"
        for basename in ("RecoveryKnownPlayableTests.swift","UITestHarness.swift","PairingView.swift"):
            match=re.search(re.escape(basename)+r":(\d+)\b",details,re.I)
            if match:
                candidate_line=int(match.group(1))
                if 1<=candidate_line<=5000:
                    ui_source=basename
                    ui_line=str(candidate_line)
                break
        line+=" ui_source="+ui_source+" line="+ui_line

# XCTest and xcresult text is private. Inspect it in memory, then reduce any
# match to an exact marker already present in the allowlist above.
marker_source="\n".join(marker_evidence)
marker_source+="\n"+"\n".join(failure_payload_text)
marker=next((item for item in markers if item in marker_source),"none")
pairing_failure=re.search(r"recovery-ui-pairing-request-failed-(expired|already_redeemed|not_approved|slow_down|not_found|denied|invalid_response|keychain_write_failed|transport|insecure_address|certificate_pin|certificate_trust|other)",marker_source)
if pairing_failure:
    marker="recovery-ui-pairing-request-failed-"+pairing_failure.group(1)
prefill_failure=re.search(r"recovery-ui-pairing-target-prefill-(missing|malformed|scheme|host|port|userinfo|path|query|fragment|invalid|other|unavailable)",marker_source)
if prefill_failure:
    marker="recovery-ui-pairing-target-prefill-"+prefill_failure.group(1)
line=re.sub(r"\bmarker=[^ ]+", "marker="+marker, line, count=1)
ui_source="unknown"
ui_line="unknown"
allowed_sources=("RecoveryKnownPlayableTests.swift","UITestHarness.swift","PairingView.swift")
source_inputs=[(value,line_value) for value,line_value in failure_location_fields]
source_inputs.extend((value,None) for value in failure_payload_text)
source_inputs.append((marker_source,None))
for source_value, explicit_line in source_inputs:
    for basename in allowed_sources:
        if not re.search(re.escape(basename),source_value,re.I):
            continue
        candidate_line=explicit_line
        if candidate_line is None:
            match=re.search(re.escape(basename)+r":(\d+)\b",source_value,re.I)
            candidate_line=int(match.group(1)) if match else None
        if candidate_line is not None and 1<=candidate_line<=5000:
            ui_source=basename
            ui_line=str(candidate_line)
            break
    if ui_source!="unknown": break
line+=" ui_source="+ui_source+" line="+ui_line
cache_blockers=re.search(r"recovery-ui-cache-preflight-blocked\s+blockers=([a-z_,]+)",marker_source)
allowed_blockers={"empty_catalogue","game_assets","cache_verification","emulator","bios","controller_and_input","save_directory","save_state"}
if cache_blockers:
    values=cache_blockers.group(1).split(",")
    if values and len(values)<=8 and all(value in allowed_blockers for value in values) and len(set(values))==len(values):
        line+=" blockers="+",".join(values)
if approval_log and approval_log.is_file():
    try:
        approval_lines=approval_log.read_text(encoding="utf-8",errors="replace").splitlines()
        if ("approval_driver=test_owner" in approval_lines
            and "RECOVERY_TEST_OWNER stage=approval_driver outcome=approved" in approval_lines):
            line+=" approval_driver=test_owner"
    except Exception:
        pass
print(line)
PY
}

emit_safe_build_diagnostic() {
  python3 - "$1" <<'PY' >&2
import pathlib,re,sys
log=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8",errors="replace").lower()
log_lines=log.splitlines()
error_indexes=[index for index,line in enumerate(log_lines) if "error:" in line or "fatal error:" in line]
errors=[log_lines[index] for index in error_indexes]
categories=(
    ("syntax",("expected ","consecutive statements","extraneous", "unterminated")),
    ("type",("cannot convert","cannot infer","ambiguous use","value of type","type has no member","no exact matches")),
    ("actor",("main actor","actor-isolated","sending value")),
    ("module",("no such module","unable to find module")),
    ("signing",("provisioning profile","signing certificate","code signing")),
)
category=next((name for name,needles in categories if any(needle in " ".join(errors) for needle in needles)),"other" if errors else "none")
source="other"
line_number="unknown"
for index in error_indexes:
    context=" ".join(log_lines[max(0,index-3):min(len(log_lines),index+4)])
    match=re.search(r"(?:^|/)([A-Za-z][A-Za-z0-9_.-]{0,100}\.swift):(\d+)(?::\d+)?",context)
    if match:
        source,line_number=match.groups()
        break
print("RECOVERY_BUILD_DIAGNOSTIC errors={} class={} source={} line={}".format(min(len(errors),10000),category,source,line_number))
PY
}

if [ -n "$REPORT_VALIDATION_ONLY" ]; then
  validate_ui_report "$REPORT_VALIDATION_ONLY"
  exit 0
fi

if [[ -n "${PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL:-}" && "${PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL}" != 1 ]]; then
  FAILED_STAGE="owner_approval"
  blocked 'explicit test-owner approval opt-in value is invalid'
fi

command -v docker >/dev/null 2>&1 || blocked 'Docker is unavailable'
docker info >/dev/null 2>&1 || blocked 'Docker daemon is unavailable'
docker compose version >/dev/null 2>&1 || blocked 'Docker Compose is unavailable'
command -v xcodebuild >/dev/null 2>&1 || blocked 'Xcode is unavailable'

# The owner supplies an already-established local team as a process-only
# override. Keep signing identity generic and allow Xcode to manage the
# per-target UI-test profile; none of these values enter a report or log.
if [ -z "${PLAYSTEAD_TEAM_ID:-}" ]; then
  blocked 'local Apple Development team override is unavailable'
fi

private_root="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-e2e.XXXXXX")"
FAILED_STAGE="clean_mac_ui"
chmod 700 "$private_root"

cleanup_owned_recovery_app() {
  local root="$1"
  python3 - "$root" >/dev/null 2>&1 <<'PY' || true
import ctypes, os, pathlib, signal, sys, time

root = pathlib.Path(sys.argv[1]).resolve()
products = root / "DerivedData" / "Build" / "Products"
if not products.is_dir():
    raise SystemExit(0)
apps = [p for p in products.rglob("Playstead.app") if p.is_dir() and not p.is_symlink()]
if len(apps) != 1:
    raise SystemExit(0)
app = apps[0].resolve()
try:
    app.relative_to(products.resolve())
    info = __import__("plistlib").loads((app / "Contents" / "Info.plist").read_bytes())
except Exception:
    raise SystemExit(0)
if info.get("CFBundleIdentifier") != "dev.playstead.mac":
    raise SystemExit(0)
executable = info.get("CFBundleExecutable")
if not isinstance(executable, str) or not executable or pathlib.Path(executable).name != executable:
    raise SystemExit(0)
expected = str((app / "Contents" / "MacOS" / executable).resolve())
if not pathlib.Path(expected).is_file():
    raise SystemExit(0)

libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
list_pids = libproc.proc_listallpids
list_pids.argtypes = (ctypes.POINTER(ctypes.c_int), ctypes.c_int)
list_pids.restype = ctypes.c_int
pid_path = libproc.proc_pidpath
pid_path.argtypes = (ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32)
pid_path.restype = ctypes.c_int

def executable_for(pid):
    buffer = ctypes.create_string_buffer(4096)
    if pid_path(pid, buffer, len(buffer)) <= 0:
        return None
    try:
        return os.path.realpath(os.fsdecode(buffer.value))
    except (OSError, ValueError):
        return None

pid_buffer = (ctypes.c_int * 65536)()
pid_count = list_pids(pid_buffer, ctypes.sizeof(pid_buffer))
if pid_count <= 0 or pid_count > len(pid_buffer):
    raise SystemExit(0)
pids = (int(pid_buffer[index]) for index in range(pid_count))

for pid in pids:
    if pid == os.getpid() or executable_for(pid) != expected:
        continue
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        continue
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline and executable_for(pid) == expected:
        time.sleep(0.05)
    # Revalidate executable identity immediately before a forced stop so a
    # recycled PID can never target an unrelated process.
    if executable_for(pid) == expected:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
PY
}

cleanup_owned_recovery_emulators() {
  [ -d "$private_root/profile/emulators" ] || return 0
  /usr/bin/xcrun swift -module-cache-path "$private_root/ModuleCache" \
    "$SCRIPT_DIR/recovery-cleanup-emulators.swift" "$private_root" >/dev/null 2>&1
}

cleanup_recovery_e2e() {
  if [ -n "${approval_pid:-}" ]; then
    kill "$approval_pid" >/dev/null 2>&1 || true
    wait "$approval_pid" >/dev/null 2>&1 || true
    approval_pid=""
  fi
  # Close an emulator while its executable and exact run root still exist.
  # A failed XCTest can otherwise orphan it before profile deletion.
  if ! cleanup_owned_recovery_emulators; then
    printf '%s\n' 'RECOVERY_CLEANUP outcome=blocked' >&2
    cleanup_owned_recovery_app "$private_root"
    return 77
  fi
  cleanup_owned_recovery_app "$private_root"
  rm -rf "$private_root"
}
trap cleanup_recovery_e2e EXIT
approval_pid=""
profile_root="$private_root/profile"
mkdir -m 700 "$profile_root"
if [ -n "${PLAYSTEAD_RECOVERY_FIXTURE_RECORD:-}" ]; then
  FAILED_STAGE="fixture_validation"
  python3 "$SCRIPT_DIR/recovery-fixture.py" "$PLAYSTEAD_RECOVERY_FIXTURE_RECORD" "$HANDOFF" "$profile_root" \
    >/dev/null 2>&1 || blocked 'private expected-fixture identity could not be staged'
  FAILED_STAGE="clean_mac_ui"
fi
python3 - "$profile_root" "$target_url" <<'PY'
import os,pathlib,stat,sys,urllib.parse

root=pathlib.Path(sys.argv[1])
value=sys.argv[2]
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode)!=0o700:
    raise SystemExit("recovery target profile root is not private")
try:
    parsed=urllib.parse.urlparse(value)
    port=parsed.port
except ValueError:
    raise SystemExit("recovery target URL is malformed")
if parsed.scheme!="https" or parsed.hostname!="localhost" or port is None or not 1<=port<=65535 or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("","/"):
    raise SystemExit("recovery target URL is not local HTTPS")
target=root/"recovery-target.url"
flags=os.O_WRONLY|os.O_CREAT|os.O_EXCL
if hasattr(os,"O_NOFOLLOW"):
    flags|=os.O_NOFOLLOW
try:
    descriptor=os.open(target,flags,0o600)
except FileExistsError:
    raise SystemExit("recovery target file already exists")
try:
    os.fchmod(descriptor,0o600)
    payload=value.encode("utf-8")
    if not payload or len(payload)>4096:
        raise SystemExit("recovery target file size is invalid")
    with os.fdopen(descriptor,"wb",closefd=False) as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
finally:
    os.close(descriptor)
attributes=target.lstat()
if not stat.S_ISREG(attributes.st_mode) or stat.S_IMODE(attributes.st_mode)!=0o600:
    raise SystemExit("recovery target file did not retain private mode")
PY
ui_report="$private_root/mac-ui-report.json"
derived_data="$private_root/DerivedData"
result_bundle="$private_root/RecoveryKnownPlayable.xcresult"
xcode_log="$private_root/xcodebuild.log"
# Seed the private checkout root from an existing Xcode cache only when every
# lockfile pin matches. Package sources are public; copying them keeps Xcode's
# working checkout private to this run without mutating the shared cache.
mkdir -m 700 "$private_root/ModuleCache"
cached_source_packages="$(python3 - "$MAC_ROOT" "$HOME/Library/Developer/Xcode/DerivedData" <<'PY'
import json, pathlib, shutil, subprocess, sys

project=pathlib.Path(sys.argv[1])
derived=pathlib.Path(sys.argv[2])
lock=project/"Playstead.xcodeproj"/"project.xcworkspace"/"xcshareddata"/"swiftpm"/"Package.resolved"
try:
    pins=json.loads(lock.read_text(encoding="utf-8")).get("pins",[])
    expected={pin["identity"].lower():pin.get("state",{}).get("revision") for pin in pins}
except Exception:
    raise SystemExit(1)
if not expected or any(not revision for revision in expected.values()):
    raise SystemExit(1)
git=shutil.which("git")
if not git:
    raise SystemExit(1)
matches=[]
for source in derived.glob("Playstead-*/SourcePackages"):
    checkouts=source/"checkouts"
    if source.is_symlink() or not checkouts.is_dir() or checkouts.is_symlink():
        continue
    valid=True
    for identity,revision in expected.items():
        checkout=checkouts/identity
        if checkout.is_symlink() or not checkout.is_dir():
            valid=False
            break
        result=subprocess.run([git,"-C",str(checkout),"rev-parse","HEAD"],capture_output=True,text=True)
        if result.returncode or result.stdout.strip()!=revision:
            valid=False
            break
    if valid:
        matches.append(source.resolve())
if matches:
    matches.sort(key=lambda path:path.stat().st_mtime,reverse=True)
    print(matches[0])
PY
)" 2>/dev/null || cached_source_packages=""
if [ -n "$cached_source_packages" ]; then
  if ! /usr/bin/ditto "$cached_source_packages" "$private_root/SourcePackages"; then
    FAILED_STAGE="package_cache"
    blocked 'verified local Swift package sources could not be staged privately'
  fi
  chmod 700 "$private_root/SourcePackages"
else
  mkdir -m 700 "$private_root/SourcePackages"
fi
if ! xcodebuild build-for-testing -project "$MAC_ROOT/Playstead.xcodeproj" -scheme Playstead \
       -testPlan Recovery \
       -only-testing:PlaysteadUITests/RecoveryKnownPlayableTests/testPreparedRecoveryTargetLaunchesTheCleanMacAppAndRequestsPairing \
       -destination 'platform=macOS' -derivedDataPath "$derived_data" \
       -clonedSourcePackagesDirPath "$private_root/SourcePackages" \
       -allowProvisioningUpdates \
       CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
       DEVELOPMENT_TEAM="$PLAYSTEAD_TEAM_ID" \
       CODE_SIGN_ENTITLEMENTS=PlaysteadUITests/RecoveryUITests.entitlements \
       MODULE_CACHE_DIR="$private_root/ModuleCache" \
       >"$xcode_log" 2>&1; then
  FAILED_STAGE="$(classify_xcode_failure "$xcode_log")"
  emit_safe_build_diagnostic "$xcode_log"
  blocked 'local recovery UI-test build failed; diagnostic details remain private'
fi
xctestrun="$(PLAYSTEAD_RECOVERY_PRIVATE_ROOT="$private_root" \
  PLAYSTEAD_RECOVERY_DERIVED_DATA="$derived_data" \
  PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT="$profile_root" \
  PLAYSTEAD_RECOVERY_UI_REPORT="$ui_report" \
  "$0" --patch-xctestrun)" || blocked 'generated local test-run environment could not be prepared'
approval_log="$private_root/test-owner-approval.log"
if [ "${PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL:-}" = 1 ]; then
  FAILED_STAGE="owner_approval"
  owner_status="$(PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$HANDOFF" \
    "$SCRIPT_DIR/recovery-test-owner.sh" check 2>/dev/null)" || \
      blocked 'explicit test-owner approval requires a prepared disposable login'
  [[ "$owner_status" == 'RECOVERY_TEST_OWNER stage=complete outcome=ready' ]] || \
    blocked 'explicit test-owner approval requires a ready disposable login'
  printf '%s\n' 'approval_driver=test_owner' >&2
  PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL=1 \
    "$SCRIPT_DIR/recovery-test-owner.sh" approve-once "$profile_root" \
    >"$approval_log" 2>&1 &
  approval_pid=$!
fi
if ! xcodebuild test-without-building -xctestrun "$xctestrun" \
       -only-testing:PlaysteadUITests/RecoveryKnownPlayableTests/testPreparedRecoveryTargetLaunchesTheCleanMacAppAndRequestsPairing \
       -destination 'platform=macOS' -resultBundlePath "$result_bundle" \
       >>"$xcode_log" 2>&1; then
  if ui_result="$(validate_ui_report "$ui_report" 2>/dev/null)"; then
    read -r ui_outcome ui_stage <<<"$ui_result"
    if [ "$ui_outcome" = blocked ]; then
      FAILED_STAGE="$ui_stage"
    else
      FAILED_STAGE="$(classify_xcode_failure "$xcode_log")"
    fi
  else
    FAILED_STAGE="$(classify_xcode_failure "$xcode_log")"
  fi
  emit_safe_ui_diagnostic "$xcode_log" "$ui_report" "$result_bundle" "$approval_log"
  blocked 'local restored-target XCTest could not start or complete; diagnostic details remain private'
fi
if ! cleanup_owned_recovery_emulators; then
  FAILED_STAGE=controlled_exit
  blocked 'owned recovery emulator cleanup did not complete'
fi
ui_result="$(validate_ui_report "$ui_report" 2>/dev/null)" || blocked 'local XCTest report is missing, incomplete, or contains non-allowlisted fields'
read -r ui_outcome ui_stage <<<"$ui_result"
if [ "$ui_outcome" != passed ]; then
  FAILED_STAGE="$ui_stage"
  if [ "${PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL:-}" = 1 ]; then
    emit_safe_ui_diagnostic "$xcode_log" "$ui_report" "$result_bundle" "$approval_log"
  fi
  blocked 'restored-target journey is waiting at a required recovery stage'
fi
if [ "${PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL:-}" = 1 ]; then
  approval_done=false
  for _attempt in $(seq 1 40); do
    if ! kill -0 "$approval_pid" >/dev/null 2>&1; then approval_done=true; break; fi
    sleep 0.1
  done
  if [ "$approval_done" != true ]; then
    kill "$approval_pid" >/dev/null 2>&1 || true
    wait "$approval_pid" >/dev/null 2>&1 || true
    approval_pid=""
    FAILED_STAGE="owner_approval"
    blocked 'test-owner approval helper did not finish after the client journey'
  fi
  approval_rc=0
  wait "$approval_pid" || approval_rc=$?
  approval_pid=""
  if [ "$approval_rc" -ne 0 ] || ! rg -q '^RECOVERY_TEST_OWNER stage=approval_driver outcome=approved$' "$approval_log"; then
    FAILED_STAGE="owner_approval"
    blocked 'test-owner approval did not match the current pairing request'
  fi
fi
recovery_result="$(emit_local_receipt complete passed)" || exit 77
if [ "${PLAYSTEAD_CONTINUATION_RUN:-}" = 1 ]; then
  continuation_receipt="$private_root/recovery-e2e-receipt.json"
  printf '%s\n' "$recovery_result" >"$continuation_receipt"
  chmod 600 "$continuation_receipt"
  continuation_status=0
  continuation_result="$(PLAYSTEAD_RECOVERY_E2E_RECEIPT="$continuation_receipt" \
    "$SCRIPT_DIR/continuation-spike.sh" 2>/dev/null)" || continuation_status=$?
  # A requested continuation gate owns the final result and exit status.
  # Never print overall recovery success ahead of a blocked/failed child.
  [ -n "$continuation_result" ] || exit 77
  printf '%s\n' "$continuation_result"
  exit "$continuation_status"
fi
printf '%s\n' "$recovery_result"
