#!/usr/bin/env bash
set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID="${GITHUB_RUN_ID:-local}"
RUNNER_TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
WORK_ROOT="${RUNNER_TEMP_ROOT}/playstead-virtual-hid-${RUN_ID}"
STATE_FILE="${WORK_ROOT}/install-state.json"
KEYCHAIN="${WORK_ROOT}/virtual-hid.keychain-db"
P12_FILE="${WORK_ROOT}/certificate.p12"
CERT_FILE="${WORK_ROOT}/certificate.pem"
PROFILE_FILE="${WORK_ROOT}/profile.mobileprovision"
DECODED_PROFILE="${WORK_ROOT}/profile.plist"
RESOLVER_ROOT="${WORK_ROOT}/resolver-profiles"
STANDARD_PROFILE_ROOT="${HOME}/Library/MobileDevice/Provisioning Profiles"
PROFILE_UUID=""
PROFILE_TEAM=""
CERT_FINGERPRINT=""

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_clean_environment() {
  [[ "$RUN_ID" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || fail "Virtual HID run identity is invalid"
  [[ "$RUNNER_TEMP_ROOT" = /* ]] || fail "Virtual HID temporary root must be absolute"
  [[ -n "${PLAYSTEAD_HID_CERT_P12_BASE64:-}" ]] || fail "Virtual HID signing certificate input is missing"
  [[ -n "${PLAYSTEAD_HID_CERT_P12_PASSWORD:-}" ]] || fail "Virtual HID signing certificate password is missing"
  [[ -n "${PLAYSTEAD_HID_PROFILE_BASE64:-}" ]] || fail "Virtual HID provisioning profile input is missing"
  [[ ! -e "$WORK_ROOT" ]] || fail "Virtual HID temporary directory already exists"
}

decode_inputs() {
  umask 077
  mkdir -m 700 -p "$WORK_ROOT"
  python3 - "$P12_FILE" "$PROFILE_FILE" <<'PY'
import base64, binascii, os, pathlib, sys

p12_path, profile_path = map(pathlib.Path, sys.argv[1:])
for name, destination in (
    ("PLAYSTEAD_HID_CERT_P12_BASE64", p12_path),
    ("PLAYSTEAD_HID_PROFILE_BASE64", profile_path),
):
    value = os.environ.get(name, "")
    try:
        payload = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        raise SystemExit("Virtual HID signing input is malformed")
    if not payload or len(payload) > 2 * 1024 * 1024:
        raise SystemExit("Virtual HID signing input has invalid size")
    destination.write_bytes(payload)
    destination.chmod(0o600)
PY
  unset PLAYSTEAD_HID_CERT_P12_BASE64 PLAYSTEAD_HID_PROFILE_BASE64
  security cms -D -i "$PROFILE_FILE" >"$DECODED_PROFILE" 2>/dev/null || \
    fail "Virtual HID provisioning profile could not be decoded"
  chmod 600 "$DECODED_PROFILE"
  openssl pkcs12 -in "$P12_FILE" -passin env:PLAYSTEAD_HID_CERT_P12_PASSWORD \
    -clcerts -nokeys -out "$CERT_FILE" 2>/dev/null || \
    fail "Virtual HID signing certificate could not be decoded"
  chmod 600 "$CERT_FILE"
}

validate_profile() {
  local metadata
  metadata="$(python3 - "$DECODED_PROFILE" "$CERT_FILE" <<'PY'
import datetime, hashlib, json, pathlib, plistlib, re, subprocess, sys

profile_path, certificate_path = map(pathlib.Path, sys.argv[1:])
bundle_id = "dev.playstead.mac.PlaysteadUITests"
entitlement_name = "com.apple.developer.hid.virtual.device"
try:
    profile = plistlib.loads(profile_path.read_bytes())
    if not isinstance(profile, dict):
        raise ValueError
    teams = profile.get("TeamIdentifier")
    if not isinstance(teams, list) or len(teams) != 1 or not isinstance(teams[0], str):
        raise ValueError
    team = teams[0]
    if not re.fullmatch(r"[A-Z0-9]{5,15}", team):
        raise ValueError
    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise ValueError
    if entitlements.get("application-identifier") != f"{team}.{bundle_id}":
        raise ValueError
    if entitlements.get(entitlement_name) is not True:
        raise ValueError
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime.datetime):
        raise ValueError
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=datetime.timezone.utc)
    if expiration <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError
    uuid = profile.get("UUID")
    if not isinstance(uuid, str) or not re.fullmatch(
        r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-8][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}", uuid
    ):
        raise ValueError
    developer_certificates = profile.get("DeveloperCertificates")
    if not isinstance(developer_certificates, list) or not developer_certificates:
        raise ValueError
    fingerprint_result = subprocess.run(
        ["openssl", "x509", "-inform", "pem", "-in", str(certificate_path), "-noout", "-fingerprint", "-sha1"],
        check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    subject_result = subprocess.run(
        ["openssl", "x509", "-inform", "pem", "-in", str(certificate_path), "-noout", "-subject", "-nameopt", "RFC2253"],
        check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    fingerprint_match = re.search(r"([0-9A-Fa-f]{2}:){19}[0-9A-Fa-f]{2}", fingerprint_result.stdout)
    if fingerprint_result.returncode or subject_result.returncode or not fingerprint_match:
        raise ValueError
    fingerprint = fingerprint_match.group(0).replace(":", "").upper()
    matching_certificates = {
        hashlib.sha1(value).hexdigest().upper()
        for value in developer_certificates
        if isinstance(value, bytes)
    }
    if fingerprint not in matching_certificates:
        raise ValueError
    subject = subject_result.stdout
    if "Apple Development:" not in subject or not re.search(rf"(?:^|,)OU={re.escape(team)}(?:,|$)", subject):
        raise ValueError
except Exception:
    raise SystemExit("Virtual HID provisioning profile or certificate does not match the required app")
print(json.dumps({"profile_uuid": uuid, "team": team, "certificate_fingerprint": fingerprint}, sort_keys=True))
PY
)" || fail "Virtual HID provisioning profile or certificate does not match the required app"
  PROFILE_UUID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["profile_uuid"])' "$metadata")"
  PROFILE_TEAM="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["team"])' "$metadata")"
  CERT_FINGERPRINT="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["certificate_fingerprint"])' "$metadata")"
}

save_install_state() {
  mkdir -m 700 -p "$RESOLVER_ROOT" "$STANDARD_PROFILE_ROOT"
  local installed_profile="${STANDARD_PROFILE_ROOT}/${PROFILE_UUID}.mobileprovision"
  [[ ! -e "$installed_profile" ]] || fail "matching provisioning profile already exists on the runner"
  python3 - "$STATE_FILE" "$PROFILE_UUID" "$KEYCHAIN" "$installed_profile" "$RESOLVER_ROOT" <<'PY'
import json, pathlib, shlex, subprocess, sys

state_path, profile_uuid, keychain, installed_profile, resolver_root = sys.argv[1:]
result = subprocess.run(
    ["security", "list-keychains", "-d", "user"], check=False,
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
)
if result.returncode:
    raise SystemExit("Virtual HID runner keychain state could not be read")
try:
    keychains = shlex.split(result.stdout)
except ValueError:
    raise SystemExit("Virtual HID runner keychain state is malformed")
state = {
    "profile_uuid": profile_uuid,
    "keychain": keychain,
    "installed_profile": installed_profile,
    "resolver_root": resolver_root,
    "previous_keychains": keychains,
}
path = pathlib.Path(state_path)
path.write_text(json.dumps(state, sort_keys=True) + "\n", encoding="utf-8")
path.chmod(0o600)
PY
}

install_signing_material() {
  local keychain_password
  keychain_password="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  security create-keychain -p "$keychain_password" "$KEYCHAIN" >/dev/null 2>&1 || \
    fail "temporary signing keychain could not be created"
  security set-keychain-settings -lut 1800 "$KEYCHAIN" >/dev/null 2>&1 || \
    fail "temporary signing keychain settings could not be applied"
  security unlock-keychain -p "$keychain_password" "$KEYCHAIN" >/dev/null 2>&1 || \
    fail "temporary signing keychain could not be unlocked"
  security import "$P12_FILE" -k "$KEYCHAIN" -P "$PLAYSTEAD_HID_CERT_P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1 || \
    fail "Apple Development signing identity could not be imported"
  unset PLAYSTEAD_HID_CERT_P12_PASSWORD
  security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$KEYCHAIN" \
    >/dev/null 2>&1 || fail "temporary signing keychain access could not be configured"
  security list-keychains -d user -s "$KEYCHAIN" >/dev/null 2>&1 || \
    fail "temporary signing keychain could not be selected"
  local identity_output
  identity_output="$(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null)" || \
    fail "Apple Development signing identity is unavailable"
  if ! printf '%s\n' "$identity_output" | grep -Eiq "${CERT_FINGERPRINT}.*Apple Development:.*\(${PROFILE_TEAM}\)"; then
    fail "Apple Development signing identity does not match the provisioning profile"
  fi
  cp "$PROFILE_FILE" "${STANDARD_PROFILE_ROOT}/${PROFILE_UUID}.mobileprovision"
  cp "$PROFILE_FILE" "${RESOLVER_ROOT}/${PROFILE_UUID}.mobileprovision"
  chmod 600 "${STANDARD_PROFILE_ROOT}/${PROFILE_UUID}.mobileprovision" \
    "${RESOLVER_ROOT}/${PROFILE_UUID}.mobileprovision"
  [[ "$(find "$RESOLVER_ROOT" -maxdepth 1 -type f -name '*.mobileprovision' | wc -l | tr -d ' ')" = 1 ]] || \
    fail "private profile directory must contain exactly one provisioning profile"
  rm -f "$P12_FILE" "$CERT_FILE" "$PROFILE_FILE" "$DECODED_PROFILE"
}

run_qualification() {
  local status=0
  PLAYSTEAD_VIRTUAL_HID_PROFILE_ROOT="$RESOLVER_ROOT" \
    PLAYSTEAD_MAC_CI_SIGNING_MODE=development \
    PLAYSTEAD_TEAM_ID="$(python3 -c 'import json,pathlib,sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["team"])' "$STATE_FILE")" \
    bash "${SCRIPT_DIR}/run-mac-verification.sh" --run-entitled-virtual-gamepad-verification || status=$?
  local sanitized="${PLAYSTEAD_CI_BUILD_ROOT:-${SCRIPT_DIR}/../../.build/ci}/entitled-virtual-gamepad/sanitized"
  if [[ -s "${sanitized}/entitled-gamepad.json" && -s "${sanitized}/ui-tests.json" && -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'sanitized=true\n' >>"$GITHUB_OUTPUT"
  fi
  return "$status"
}

cleanup() {
  if [[ -f "$STATE_FILE" ]]; then
    local profile_uuid
    profile_uuid="$(python3 -c 'import json,pathlib,sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text()).get("profile_uuid", ""))' "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$profile_uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-8][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$ ]]; then
      local installed_profile="${STANDARD_PROFILE_ROOT}/${profile_uuid}.mobileprovision"
      rm -f "$installed_profile"
      security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
      local previous_keychains=()
      if [[ -f "${WORK_ROOT}/previous-keychains.txt" ]]; then
        while IFS= read -r keychain; do
          [[ -n "$keychain" ]] && previous_keychains+=("$keychain")
        done <"${WORK_ROOT}/previous-keychains.txt"
      fi
      if ((${#previous_keychains[@]})); then
        security list-keychains -d user -s "${previous_keychains[@]}" >/dev/null 2>&1 || true
      fi
    fi
  fi
  local build_root="${PLAYSTEAD_CI_BUILD_ROOT:-${SCRIPT_DIR}/../../.build/ci}"
  rm -rf "${build_root}/entitled-virtual-gamepad/private"
  if [[ -d "${build_root}/entitled-virtual-gamepad" ]]; then
    find "${build_root}/entitled-virtual-gamepad" -maxdepth 1 -type d -name 'run.*' \
      -exec rm -rf {} + 2>/dev/null || true
  fi
  rm -rf "$WORK_ROOT"
}

case "${1:-}" in
  install-and-run)
    require_clean_environment
    decode_inputs
    validate_profile
    save_install_state
    # Save the old keychain search list independently so cleanup can restore it
    # even if the JSON reader used by cleanup is unavailable during cancellation.
    python3 - "$STATE_FILE" <<'PY' >"${WORK_ROOT}/previous-keychains.txt"
import json, pathlib, sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for keychain in state["previous_keychains"]:
    if isinstance(keychain, str) and "\n" not in keychain:
        print(keychain)
PY
    chmod 600 "${WORK_ROOT}/previous-keychains.txt"
    install_signing_material
    run_qualification
    ;;
  cleanup)
    cleanup
    ;;
  *)
    printf 'Usage: %s {install-and-run|cleanup}\n' "$0" >&2
    exit 2
    ;;
esac
