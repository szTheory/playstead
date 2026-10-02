#!/usr/bin/env bash
# Parser-only contract test for the Plan 05-11 -> Plan 05-12 recovery handoff.
# These JSON fixtures are deliberately not restore or known-playable evidence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVER="${SCRIPT_DIR}/../prove-recovery-known-playable.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-recovery-prepare-handoff.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/docker" <<'EOF'
#!/usr/bin/env bash
[ "$1" = info ] || exit 99
exit 0
EOF
cat >"$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PLAYSTEAD_TEST_CURL_LOG"
exit 0
EOF
chmod 700 "$BIN_DIR/docker" "$BIN_DIR/curl"

make_fixture() {
  local fixture="$1"
  local correlation="2f8d70fd-3e69-4f52-a263-8470997a59c5"
  mkdir -p "$fixture"
  python3 - "$fixture" "$correlation" <<'PY'
import datetime as dt, json, pathlib, sys
root, correlation = map(pathlib.Path, sys.argv[1:2]) if False else (pathlib.Path(sys.argv[1]), sys.argv[2])
receipt = {
  "schema": "playstead.restore-receipt.v1",
  "state": "verified",
  "correlation_id": correlation,
  "target": {
    "project": "playstead-restore-proof-123",
    "network": "playstead-restore-proof-123_default",
    "volumes": ["playstead-restore-proof-123_db", "playstead-restore-proof-123_blobs"],
    "ports": {"http": 18080, "https": 18443},
  },
  "chain_ids": ["fixture-only"],
  "stages": ["chain", "preflight", "database", "cas", "manifest", "api"],
  "verified_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
}
handoff = {
  "schema": "playstead.restore-handoff.v1",
  "correlation_id": correlation,
  "project": "playstead-restore-proof-123",
  "url": "https://localhost:18443",
  "receipt_path": str(root / "restore-receipt.json"),
  "ca_path": str(root / "caddy-root-ca.pem"),
}
(root / "restore-receipt.json").write_text(json.dumps(receipt), encoding="utf-8")
(root / "caddy-root-ca.pem").write_text("fixture CA only; not a certificate\n", encoding="utf-8")
(root / "server-handoff.json").write_text(json.dumps(handoff), encoding="utf-8")
PY
  chmod 600 "$fixture/server-handoff.json"
}

run_prepare() {
  local fixture="$1" profile="$2" output="$3"
  PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="$fixture/server-handoff.json" \
    PLAYSTEAD_TEST_CURL_LOG="$TMP_ROOT/curl.log" \
    PATH="$BIN_DIR:$PATH" \
    "$PROVER" --prepare --fixture --no-human-observation --profile-root "$profile" --output "$output"
}

assert_refuses_without_profile_or_contact() {
  local name="$1" fixture="$2"
  local profile="$TMP_ROOT/$name-profile" output="$TMP_ROOT/$name-output.json"
  : >"$TMP_ROOT/curl.log"
  if run_prepare "$fixture" "$profile" "$output" >"$TMP_ROOT/$name.out" 2>"$TMP_ROOT/$name.err"; then
    printf 'FAIL: %s handoff was accepted\n' "$name" >&2
    exit 1
  fi
  if [ -e "$profile" ] || [ -e "$output" ]; then
    printf 'FAIL: %s created a profile or pending receipt before validation\n' "$name" >&2
    exit 1
  fi
  if [ -s "$TMP_ROOT/curl.log" ]; then
    printf 'FAIL: %s contacted the supplied target before refusing\n' "$name" >&2
    exit 1
  fi
}

# A Plan 05-11-shaped, restricted fixture is accepted only as parser validation.
valid="$TMP_ROOT/valid"
make_fixture "$valid"
: >"$TMP_ROOT/curl.log"
run_prepare "$valid" "$TMP_ROOT/valid-profile" "$TMP_ROOT/valid-pending.json" >/dev/null
[ -d "$TMP_ROOT/valid-profile" ] && [ -f "$TMP_ROOT/valid-pending.json" ] || {
  printf 'FAIL: valid parser fixture did not create the pending clean-profile receipt\n' >&2; exit 1;
}

for case_name in failed pending malformed incomplete correlation_mismatch target_mismatch non_isolated secret_bearing stale wrong_mode missing_ca missing_receipt; do
  fixture="$TMP_ROOT/$case_name"
  make_fixture "$fixture"
  case "$case_name" in
    failed) python3 - "$fixture/restore-receipt.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["state"]="failed"; p.write_text(json.dumps(d))
PY
      ;;
    pending) python3 - "$fixture/restore-receipt.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["state"]="pending"; p.write_text(json.dumps(d))
PY
      ;;
    malformed) printf '{not-json' >"$fixture/server-handoff.json" ;;
    incomplete) python3 - "$fixture/restore-receipt.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["stages"].remove("api"); p.write_text(json.dumps(d))
PY
      ;;
    correlation_mismatch) python3 - "$fixture/server-handoff.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["correlation_id"]="a02264ce-5024-4d57-a8da-b796a5181bd5"; p.write_text(json.dumps(d))
PY
      ;;
    target_mismatch) python3 - "$fixture/server-handoff.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["url"]="https://localhost:18444"; p.write_text(json.dumps(d))
PY
      ;;
    non_isolated) python3 - "$fixture/server-handoff.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["project"]="playstead"; p.write_text(json.dumps(d))
PY
      ;;
    secret_bearing) python3 - "$fixture/server-handoff.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["credential"]="must-not-be-accepted"; p.write_text(json.dumps(d))
PY
      ;;
    stale) python3 - "$fixture/restore-receipt.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["verified_at"]="2000-01-01T00:00:00Z"; p.write_text(json.dumps(d))
PY
      ;;
    wrong_mode) chmod 644 "$fixture/server-handoff.json" ;;
    missing_ca) rm "$fixture/caddy-root-ca.pem" ;;
    missing_receipt) rm "$fixture/restore-receipt.json" ;;
  esac
  assert_refuses_without_profile_or_contact "$case_name" "$fixture"
done

release_guide="$SCRIPT_DIR/../../../docs/RELEASE.md"
if ! grep -Fq 'exit 0 is verified recovery' "$release_guide" ||
   ! grep -Fq 'exit 77 is an' "$release_guide" ||
   ! grep -Fq 'unmet Docker precondition' "$release_guide" ||
   ! grep -Fq 'any other exit is failure' "$release_guide" ||
   ! grep -Fq 'parser fixture is validation mechanics only' -i "$release_guide" ||
   ! grep -Fq 'the only human observation gate' "$release_guide"; then
  printf 'FAIL: RELEASE.md does not preserve verified, skipped, parser-only, and named-observation states\n' >&2
  exit 1
fi
if grep -Eqi 'parser fixture (is|provides) (verified recovery|known-playable (evidence|proof))|known-playable proof pending.*is a known-playable pass' "$release_guide"; then
  printf 'FAIL: RELEASE.md promotes a parser fixture or pending Mac receipt to proof\n' >&2
  exit 1
fi

# The recovery proof builds and launches only the signed Playstead app. It
# must never create the Gatekeeper-rejected UI-test runner, and its direct-app
# seam must retain the existing isolated live-server bootstrap.
bootstrap="$SCRIPT_DIR/../../../Playstead/UITesting/UITestBootstrap.swift"
app_entry="$SCRIPT_DIR/../../../Playstead/App/PlaysteadApp.swift"
pin_capture="$SCRIPT_DIR/../../../Playstead/Pairing/PinnedCertificateCapture.swift"
if ! grep -Fq 'PLAYSTEAD_MAC_DEV_SIGNING_IDENTITY' "$PROVER" ||
   ! grep -Fq 'PLAYSTEAD_TEAM_ID' "$PROVER" ||
   ! grep -Fq 'security find-certificate' "$PROVER" ||
   ! grep -Fq 'openssl x509' "$PROVER" ||
   ! grep -Fq 'configured_team="$actual_team"' "$PROVER" ||
   grep -Fq 'CODE_SIGN_IDENTITY=-' "$PROVER" ||
   ! grep -Fq 'xcodebuild build -project "$mac_root/Playstead.xcodeproj" -target Playstead' "$PROVER" ||
   ! grep -Fq 'recovery_bundle_id="dev.playstead.mac.recovery.direct"' "$PROVER" ||
   ! grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER="$recovery_bundle_id"' "$PROVER" ||
   ! grep -Fq 'plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist"' "$PROVER" ||
   ! grep -Fq '[ "$built_bundle_id" = "$recovery_bundle_id" ]' "$PROVER" ||
   ! grep -Fq 'open -n -W' "$PROVER" ||
   grep -Fq 'open -n -W -g' "$PROVER" ||
   ! grep -Fq -- '--env "PLAYSTEAD_UI_TESTING=1"' "$PROVER" ||
   ! grep -Fq -- '--env "PLAYSTEAD_UI_TEST_KEYCHAIN=$profile_root/recovery-ui.keychain-db"' "$PROVER" ||
   ! grep -Fq -- '--env "PLAYSTEAD_RECOVERY_DIRECT_PAIRING_TARGET=$target_url"' "$PROVER" ||
   ! grep -Fq -- '--env "PLAYSTEAD_RECOVERY_DIRECT_REPORT=$ui_report"' "$PROVER" ||
   ! grep -Fq -- '--env "PLAYSTEAD_RECOVERY_DIRECT_TRUST_ANCHOR=$recovery_trust_anchor"' "$PROVER" ||
   grep -Fq 'kill -TERM "$app_pid"' "$PROVER" ||
   grep -Fq '"$app_executable" >/dev/null 2>&1 &' "$PROVER" ||
   ! grep -Fq 'PLAYSTEAD_RECOVERY_DIRECT_PAIRING_TARGET' "$PROVER" ||
   ! grep -Fq 'PLAYSTEAD_RECOVERY_DIRECT_REPORT' "$PROVER" ||
   ! grep -Fq 'PLAYSTEAD_RECOVERY_DIRECT_TRUST_ANCHOR' "$PROVER" ||
   ! grep -Fq 'openssl x509 -in "$ca_cert" -outform DER -out "$recovery_trust_anchor"' "$PROVER" ||
   ! grep -Fq 'chmod 600 "$recovery_trust_anchor"' "$PROVER" ||
   ! grep -Fq 'codesign --verify --deep --strict "$app_path"' "$PROVER" ||
   grep -Fq 'PlaysteadUITests/RecoveryKnownPlayableTests/testPreparedRecoveryTargetLaunchesTheCleanMacAppAndRequestsPairing' "$PROVER" ||
   grep -Fq 'CODE_SIGN_ENTITLEMENTS=PlaysteadUITests/RecoveryUITests.entitlements' "$PROVER" ||
   ! grep -Fq 'PLAYSTEAD_RECOVERY_DIRECT_PAIRING_TARGET' "$bootstrap" ||
   ! grep -Fq 'PLAYSTEAD_RECOVERY_DIRECT_REPORT' "$bootstrap" ||
   ! grep -Fq 'PLAYSTEAD_RECOVERY_DIRECT_TRUST_ANCHOR' "$bootstrap" ||
   ! grep -Fq 'PinnedCertificateCapture.certificateData(fromRecoveryFile: rawTrustAnchorData)' "$bootstrap" ||
   ! grep -Fq 'SecCertificateCreateWithData(nil, suppliedTrustAnchorData as CFData)' "$pin_capture" ||
   ! grep -Fq 'createScopedKeychainIfNeeded' "$bootstrap" ||
   ! grep -Fq 'environment[unpairedKey] == "1"' "$bootstrap" ||
   ! grep -Fq 'containedDestinationURL(rawReport, root: root)' "$bootstrap" ||
   ! grep -Fq 'suppliedTrustAnchorData: recovery.trustAnchorData' "$app_entry" ||
   ! grep -Fq 'guard case .awaitingApproval = coordinator.state else { return }' "$app_entry" ||
   ! grep -Fq 'Task.sleep(nanoseconds: 20_000_000_000)' "$app_entry" ||
   ! grep -Fq 'NSApplication.shared.terminate(nil)' "$app_entry" ||
   ! grep -Fq 'credentials, certificate bytes, and errors' "$app_entry"; then
  printf 'FAIL: recovery proof must launch only the signed app with the isolated direct-app seam\n' >&2
  exit 1
fi

printf 'recovery-prepare-handoff: parser fixtures only; verified/failed/incomplete/mismatched/non-isolated/secret/stale/mode/missing-file checks passed\n'
