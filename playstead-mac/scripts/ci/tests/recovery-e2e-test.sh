#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COORDINATOR="$SCRIPT_DIR/../recovery-e2e.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-e2e-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in info) exit 0;; compose) [ "$2" = version ] && exit 0;; esac
exit 99
SH
cat >"$BIN_DIR/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$RECOVERY_XCODE_CAPTURE"
if [ "${RECOVERY_FAKE_XCODE_FAILURE:-}" = "profile" ]; then
  printf '%s\n' 'error: PlaysteadUITests requires a provisioning profile.' >&2
  exit 65
fi
case "${1:-}" in
  build-for-testing)
    python3 - "$@" <<'PY'
import pathlib, plistlib, sys
args=sys.argv[1:]
source=pathlib.Path(args[args.index("-clonedSourcePackagesDirPath")+1])
private=source.is_dir() and (source.stat().st_mode & 0o077)==0
with pathlib.Path(__import__('os').environ["RECOVERY_XCODE_CAPTURE"]).open("a") as stream:
    stream.write("source_packages_private="+str(private).lower()+"\n")
derived=pathlib.Path(args[args.index("-derivedDataPath")+1])
products=derived/"Build"/"Products"; products.mkdir(parents=True,exist_ok=True)
app=products/"Debug"/"Playstead.app"/"Contents"; app.mkdir(parents=True,exist_ok=True)
with (app/"Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleIdentifier":"dev.playstead.mac"},stream)
target={"BlueprintName":"PlaysteadUITests","UITargetAppPath":"__TESTROOT__/Debug/Playstead.app","DependentProductPaths":["__TESTROOT__/Debug/Playstead.app"]}
data={"TestPlan":{"Name":"Recovery"},"TestConfigurations":[{"Name":"Recovery","TestTargets":[target]}]}
path=products/"Playstead_123.xctestrun"
path.write_bytes(plistlib.dumps(data)); path.chmod(0o600)
PY
    exit 0
    ;;
  test-without-building)
    python3 - "$@" <<'PY'
import json, pathlib, plistlib, stat, sys, uuid
args=sys.argv[1:]
xctestrun=pathlib.Path(args[args.index("-xctestrun")+1])
data=plistlib.loads(xctestrun.read_bytes())
target=data["TestConfigurations"][0]["TestTargets"][0]
keys=("PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT","PLAYSTEAD_RECOVERY_UI_REPORT","PLAYSTEAD_RECOVERY_UI_TRUST_ANCHOR","PLAYSTEAD_RECOVERY_UI_APP_PATH")
for field in ("EnvironmentVariables","TestingEnvironmentVariables"):
 env=target[field]
 assert all(env.get(key) for key in keys)
 assert "PLAYSTEAD_RECOVERY_UI_TARGET_URL" not in env
assert all(target["EnvironmentVariables"][key]==target["TestingEnvironmentVariables"][key] for key in keys)
report=pathlib.Path(target["EnvironmentVariables"]["PLAYSTEAD_RECOVERY_UI_REPORT"])
profile=pathlib.Path(target["EnvironmentVariables"]["PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT"])
target_file=profile/"recovery-target.url"
assert target_file.is_file() and stat.S_IMODE(target_file.stat().st_mode)==0o600
assert target_file.read_text().startswith("https://localhost:")
stages={"clean_launch":"passed","local_ca_pairing_request":"passed","owner_approval":"not_run","cursor_convergence":"not_run","cache_preflight":"not_run","persistent_save_transport_restore":"not_run","controlled_exit":"passed","relaunch":"passed"}
report.write_text(json.dumps({"schema":"playstead.recovery-mac-ui.v2","run_id":str(uuid.uuid4()),"lane":"restored_target","stages":stages,"outcome":"blocked"}))
PY
    if [ "${RECOVERY_FAKE_XCODE_FAILURE:-}" = "journey" ]; then exit 65; fi
    exit 0
    ;;
  *) exit 99 ;;
esac
SH
chmod 700 "$BIN_DIR/docker" "$BIN_DIR/xcodebuild"

make_handoff() {
  local root="$1" case_name="${2:-valid}"
  mkdir -p "$root"
  python3 - "$root" "$case_name" <<'PY'
import datetime as dt,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); case=sys.argv[2]; correlation="3f8d70fd-3e69-4f52-a263-8470997a59c5"
receipt={"schema":"playstead.restore-receipt.v1","state":"verified","correlation_id":correlation,
"target":{"project":"playstead-restore-proof-123","network":"playstead-restore-proof-123_default","volumes":["playstead-restore-proof-123_db","playstead-restore-proof-123_blobs"],"ports":{"https":18443}},
"chain_ids":["chain-opaque"],"stages":["chain","preflight","database","cas","manifest","api"],
"verified_at":dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00","Z")}
handoff={"schema":"playstead.restore-handoff.v1","correlation_id":correlation,"project":"playstead-restore-proof-123","url":"https://localhost:18443","receipt_path":str(root/"restore-receipt.json"),"ca_path":str(root/"caddy-root-ca.pem")}
if case=="correlation": handoff["correlation_id"]="4f8d70fd-3e69-4f52-a263-8470997a59c5"
if case=="secret": handoff["credential"]="private"
if case=="remote": handoff["url"]="https://example.invalid:18443"
if case=="stale": receipt["verified_at"]="2000-01-01T00:00:00Z"
if case=="stage": receipt["stages"].remove("api")
(root/"restore-receipt.json").write_text(json.dumps(receipt)); (root/"caddy-root-ca.pem").write_text("test CA")
(root/"server-handoff.json").write_text(json.dumps(handoff))
PY
  chmod 600 "$root/server-handoff.json" "$root/restore-receipt.json" "$root/caddy-root-ca.pem"
}

assert_blocked_without_side_effects() {
  local name="$1" root="$2"
  if PATH="$BIN_DIR:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$root/server-handoff.json" \
      "$COORDINATOR" --validate-only >"$TMP_ROOT/$name.out" 2>"$TMP_ROOT/$name.err"; then
    printf 'FAIL: %s handoff unexpectedly passed\n' "$name" >&2; exit 1
  fi
  [ ! -e "$root/profile" ] || { printf 'FAIL: %s created a profile before validation\n' "$name" >&2; exit 1; }
  ! grep -Eq 'localhost|18443|server-handoff|restore-receipt|caddy-root|credential|chain-opaque' "$TMP_ROOT/$name.out" "$TMP_ROOT/$name.err" || {
    printf 'FAIL: %s leaked private handoff data\n' "$name" >&2; exit 1;
  }
}

for case_name in correlation secret remote stale stage; do
  root="$TMP_ROOT/$case_name"; make_handoff "$root" "$case_name"
  assert_blocked_without_side_effects "$case_name" "$root"
done

wrong_mode="$TMP_ROOT/wrong-mode"; make_handoff "$wrong_mode"; chmod 644 "$wrong_mode/server-handoff.json"
assert_blocked_without_side_effects wrong_mode "$wrong_mode"

missing="$TMP_ROOT/missing"
if PATH="$BIN_DIR:$PATH" env -u PLAYSTEAD_RECOVERY_RESTORE_HANDOFF "$COORDINATOR" --validate-only >"$TMP_ROOT/missing.out" 2>"$TMP_ROOT/missing.err"; then
  printf '%s\n' 'FAIL: missing handoff was accepted' >&2; exit 1
fi

valid="$TMP_ROOT/valid"; make_handoff "$valid"
PATH="$BIN_DIR:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$valid/server-handoff.json" \
  "$COORDINATOR" --validate-only >"$TMP_ROOT/valid.out" 2>"$TMP_ROOT/valid.err"
grep -Eq '^RECOVERY_HANDOFF_VALID$' "$TMP_ROOT/valid.out"
! grep -Eq 'localhost|18443|server-handoff|restore-receipt|caddy-root' "$TMP_ROOT/valid.out" "$TMP_ROOT/valid.err"

# Patch a generated test bundle without launching Xcode or contacting a target.
patch_root="$TMP_ROOT/xctestrun-patch"
mkdir -m 700 -p "$patch_root/profile" "$patch_root/DerivedData/Build/Products"
patch_report="$patch_root/mac-ui-report.json"
python3 - "$patch_root/profile/recovery-target.url" "$valid/server-handoff.json" <<'PY'
import json,os,pathlib,sys
target=pathlib.Path(sys.argv[1]); handoff=json.loads(pathlib.Path(sys.argv[2]).read_text())
descriptor=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(descriptor,"wb") as stream: stream.write(handoff["url"].encode())
os.chmod(target,0o600)
PY
python3 - "$patch_root/DerivedData/Build/Products/fixture.xctestrun" <<'PY'
import pathlib,plistlib,sys
target={"BlueprintName":"PlaysteadUITests","UITargetAppPath":"__TESTROOT__/Debug/Playstead.app","DependentProductPaths":["__TESTROOT__/Debug/Playstead.app"]}
data={"TestPlan":{"Name":"Recovery"},"TestConfigurations":[{"Name":"Recovery","TestTargets":[target]}]}
path=pathlib.Path(sys.argv[1]); path.write_bytes(plistlib.dumps(data)); path.chmod(0o600)
app=path.parent/"Debug"/"Playstead.app"/"Contents"; app.mkdir(parents=True)
with (app/"Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleIdentifier":"dev.playstead.mac"},stream)
PY
PATH="$BIN_DIR:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$valid/server-handoff.json" \
  PLAYSTEAD_RECOVERY_PRIVATE_ROOT="$patch_root" PLAYSTEAD_RECOVERY_DERIVED_DATA="$patch_root/DerivedData" \
  PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT="$patch_root/profile" PLAYSTEAD_RECOVERY_UI_REPORT="$patch_report" \
  "$COORDINATOR" --patch-xctestrun >"$TMP_ROOT/xctestrun-patch.out" 2>"$TMP_ROOT/xctestrun-patch.err"
python3 - "$TMP_ROOT/xctestrun-patch.out" "$patch_root/DerivedData/Build/Products/fixture.xctestrun" <<'PY'
import pathlib,sys
assert pathlib.Path(sys.argv[1]).read_text().strip()==str(pathlib.Path(sys.argv[2]).resolve())
PY
! grep -Eq 'localhost|18443|server-handoff|restore-receipt|caddy-root' "$TMP_ROOT/xctestrun-patch.out" "$TMP_ROOT/xctestrun-patch.err"
python3 - "$patch_root/DerivedData/Build/Products/fixture.xctestrun" "$patch_root" "$patch_report" "$valid/server-handoff.json" "$valid/caddy-root-ca.pem" <<'PY'
import json,pathlib,plistlib,stat,sys
path=pathlib.Path(sys.argv[1]); root=pathlib.Path(sys.argv[2]); report=pathlib.Path(sys.argv[3]); handoff=json.loads(pathlib.Path(sys.argv[4]).read_text()); ca=pathlib.Path(sys.argv[5])
target=plistlib.loads(path.read_bytes())["TestConfigurations"][0]["TestTargets"][0]
expected={"PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT":str((root/"profile").resolve()),"PLAYSTEAD_RECOVERY_UI_REPORT":str(report.resolve()),"PLAYSTEAD_RECOVERY_UI_TRUST_ANCHOR":str(ca),"PLAYSTEAD_RECOVERY_UI_APP_PATH":str((path.parent/"Debug"/"Playstead.app").resolve())}
for field in ("EnvironmentVariables","TestingEnvironmentVariables"):
 env=target[field]
 for key,value in expected.items(): assert env.get(key)==value,key
 assert "PLAYSTEAD_RECOVERY_UI_TARGET_URL" not in env
target_file=root/"profile"/"recovery-target.url"
assert target_file.is_file() and stat.S_IMODE(target_file.stat().st_mode)==0o600
assert target_file.read_text()==handoff["url"]
assert stat.S_IMODE(path.stat().st_mode)==0o600
assert all("PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL" not in target[field] for field in ("EnvironmentVariables","TestingEnvironmentVariables"))
PY
PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL=1 PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$valid/server-handoff.json" \
  PLAYSTEAD_RECOVERY_PRIVATE_ROOT="$patch_root" PLAYSTEAD_RECOVERY_DERIVED_DATA="$patch_root/DerivedData" \
  PLAYSTEAD_RECOVERY_UI_PROFILE_ROOT="$patch_root/profile" PLAYSTEAD_RECOVERY_UI_REPORT="$patch_report" \
  "$COORDINATOR" --patch-xctestrun >"$TMP_ROOT/xctestrun-approval-patch.out" 2>"$TMP_ROOT/xctestrun-approval-patch.err"
python3 - "$patch_root/DerivedData/Build/Products/fixture.xctestrun" <<'PY'
import pathlib,plistlib,sys
target=plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())["TestConfigurations"][0]["TestTargets"][0]
for field in ("EnvironmentVariables","TestingEnvironmentVariables"):
    assert target[field].get("PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL")=="1"
PY

# Validate the strict UI receipt vocabulary and fail-closed incomplete stages.
report="$TMP_ROOT/ui-report.json"
python3 - "$report" <<'PY'
import json,sys,uuid
stages={"clean_launch":"passed","local_ca_pairing_request":"passed","owner_approval":"not_run","cursor_convergence":"not_run","cache_preflight":"not_run","persistent_save_transport_restore":"not_run","controlled_exit":"passed","relaunch":"passed"}
json.dump({"schema":"playstead.recovery-mac-ui.v2","run_id":str(uuid.uuid4()),"lane":"restored_target","stages":stages,"outcome":"blocked"},open(sys.argv[1],"w"))
PY
PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$valid/server-handoff.json" "$COORDINATOR" --validate-ui-report "$report" >"$TMP_ROOT/ui-report.out"
grep -Eq '^blocked owner_approval$' "$TMP_ROOT/ui-report.out"
python3 - "$report" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); del d["stages"]["persistent_save_transport_restore"]; p.write_text(json.dumps(d))
PY
if PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$valid/server-handoff.json" "$COORDINATOR" --validate-ui-report "$report" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: missing UI stage report was accepted' >&2; exit 1
fi
python3 - "$report" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["credential"]="must-not-be-reported"; p.write_text(json.dumps(d))
PY
if PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$valid/server-handoff.json" "$COORDINATOR" --validate-ui-report "$report" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: secret-bearing UI report was accepted' >&2; exit 1
fi

# A launch failure must still dispose of the exact app owned by this private
# run, and the XCTest must register its own cleanup before asking XCTest to
# launch (which can fail after Launch Services has already started the app).
python3 - "$COORDINATOR" "$SCRIPT_DIR/../../../PlaysteadUITests/RecoveryKnownPlayableTests.swift" <<'PY'
import pathlib,sys
script=pathlib.Path(sys.argv[1]).read_text()
test=pathlib.Path(sys.argv[2]).read_text()
assert "trap cleanup_recovery_e2e EXIT" in script
assert "cleanup_owned_recovery_app \"$private_root\"" in script
assert "proc_listallpids" in script and "proc_pidpath" in script
assert "os.path.realpath(os.fsdecode(buffer.value))" in script
assert 'rm -rf "$private_root"' in script
assert "/Applications/Playstead.app" not in script
assert "expected_target_path = \"__TESTROOT__/\" + app_path.relative_to(products).as_posix()" in script
defer=test.index("defer {\n            if launched.state != .notRunning")
launch=test.index("        launched.launch()",defer)
assert defer < launch
assert "let launched = XCUIApplication()" in test
PY

assert_local_blocked_stage() {
  local name="$1" expected="$2"; shift 2
  local status
  set +e
  HOME="$TMP_ROOT/fake-home" PATH="$BIN_DIR:$PATH" PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$valid/server-handoff.json" \
    PLAYSTEAD_TEAM_ID='test-team-override' RECOVERY_XCODE_CAPTURE="$TMP_ROOT/$name-xcode.txt" \
    "$@" "$COORDINATOR" >"$TMP_ROOT/$name.out" 2>"$TMP_ROOT/$name.err"
  status=$?
  set -e
  [ "$status" = 77 ] || { printf 'FAIL: %s did not return blocked\n' "$name" >&2; exit 1; }
  python3 - "$TMP_ROOT/$name.out" "$expected" <<'PY'
import json,pathlib,sys,uuid
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(d)=={"schema","run_id","lane","stage","outcome"}
assert d["schema"]=="playstead.recovery-e2e-local.v1"
assert d["lane"]=="same_host_restored_target" and d["stage"]==sys.argv[2] and d["outcome"]=="blocked", (d.get("lane"),d.get("stage"),d.get("outcome"))
uuid.UUID(d["run_id"])
PY
  ! grep -Eq 'localhost|18443|server-handoff|restore-receipt|caddy-root|credential|chain-opaque|test-team-override' "$TMP_ROOT/$name.out" "$TMP_ROOT/$name.err" || {
    printf 'FAIL: %s leaked private recovery data\n' "$name" >&2; exit 1;
  }
}

# Headless contract runs must stop before Xcode when the retained target's
# browser trust is not prepared. The fake trust boundary and coordinator mode
# coverage live in recovery-browser-trust-test.sh.
assert_local_blocked_stage normal browser_trust
[ ! -e "$TMP_ROOT/normal-xcode.txt" ] || { printf '%s\n' 'FAIL: Xcode ran before browser trust was ready' >&2; exit 1; }

# Exercise the real reduction function independently of Docker and Xcode.
python3 - "$COORDINATOR" "$TMP_ROOT/emit-receipt.sh" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
function='emit_local_receipt() ('+source.split('emit_local_receipt() (',1)[1].split('\n\nblocked() {',1)[0]
pathlib.Path(sys.argv[2]).write_text('set -euo pipefail\nSCRIPT_DIR="$1"\nRUN_ID="3f8d70fd-3e69-4f52-a263-8470997a59c5"\n'+function+'\nemit_local_receipt "$2" "$3"\n')
PY
bash "$TMP_ROOT/emit-receipt.sh" "$SCRIPT_DIR/.." complete passed >"$TMP_ROOT/sanitized-pass.json"
python3 - "$TMP_ROOT/sanitized-pass.json" <<'PY'
import json,pathlib,sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data['schema']=='playstead.recovery-e2e-local.v1'
assert data['stage']=='complete' and data['outcome']=='passed'
PY
mkdir "$TMP_ROOT/reject-sanitizer"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP_ROOT/reject-sanitizer/sanitize-evidence.sh"
chmod 700 "$TMP_ROOT/reject-sanitizer/sanitize-evidence.sh"
if bash "$TMP_ROOT/emit-receipt.sh" "$TMP_ROOT/reject-sanitizer" complete passed >"$TMP_ROOT/rejected-receipt.out" 2>/dev/null; then
  printf '%s\n' 'FAIL: receipt bypassed sanitizer rejection' >&2; exit 1
fi
[ ! -s "$TMP_ROOT/rejected-receipt.out" ] || { printf '%s\n' 'FAIL: rejected receipt was emitted' >&2; exit 1; }

python3 "$SCRIPT_DIR/recovery-fixture-test.py"

# Every bounded fixture failure category must survive the private-log
# reduction. Unknown values still cannot enter the public diagnostic.
python3 - "$COORDINATOR" <<'PY'
import ast,pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
diagnostic=source.split("emit_safe_ui_diagnostic() {",1)[1].split("<<'PY' >&2\n",1)[1].split("\nPY\n",1)[0]
tree=ast.parse(diagnostic)
markers=next(ast.literal_eval(node.value) for node in tree.body
             if isinstance(node,ast.Assign) and any(isinstance(target,ast.Name) and target.id=="markers" for target in node.targets))
expected={"recovery-ui-fixture-download-retry"}
categories={
    "match": ("sync_pending","registry_missing","registry_invalid","game_missing","game_ambiguous","unreported"),
    "save": ("registry_unavailable","game_unmatched","line_missing","revision_missing","revision_not_uploaded","prefetch_missing_or_mismatched","unreported"),
    "save-restore": ("not_materialized","save_path_unavailable","materialization_unconfirmed","unreported"),
}
for group,values in categories.items():
    expected.update("recovery-ui-fixture-"+group+"-"+value for value in values)
assert expected.issubset(markers)
assert not any("private-canary" in marker for marker in markers)
repo=pathlib.Path(sys.argv[1]).resolve().parents[3]
pairing=(repo/"playstead-mac/Playstead/Pairing/PairingView.swift").read_text()
importer=(repo/"playstead-server/lib/playstead/import.ex").read_text()
assert '@tracer_member_role "primary"' in importer
assert 'member.role == "primary"' in pairing
assert '$0.role == "primary"' in pairing
assert 'member.role == "rom"' not in pairing and '$0.role == "rom"' not in pairing
PY

printf '%s\n' 'recovery-e2e contracts: passed'
