#!/usr/bin/env bash
# A two-direction guard on `verify-notarized-release.sh --preflight-only`
# (T-03-12-01): it must refuse when no Developer ID Application identity is
# present, and — because a guard never observed passing is not a guard — it
# must also be observed passing when a stubbed identity and credential
# profile are present. Proving only the refusal direction would leave a
# script that is simply always broken indistinguishable from a script that
# is actually enforcing anything.
#
# Exit codes are captured into variables and compared explicitly, never
# tested live inside an `if cmd; then` — a missing shim command exits 127,
# which a bare `if` reads as "clean" (the fail-open shape this repo has
# already been bitten by four times).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERIFY_SCRIPT="${MAC_ROOT}/scripts/verify-notarized-release.sh"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/playstead-notarization-preflight.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

ASSERTION_COUNT=0

if [ ! -x "$VERIFY_SCRIPT" ]; then
  printf 'notarization-preflight-test: %s is missing or not executable\n' "$VERIFY_SCRIPT" >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: verify-notarized-release.sh exists and is executable\n'

# --- Direction one: no Developer ID identity available -> hard refusal. ---
NO_IDENTITY_SHIM="$WORK_DIR/no-identity-bin"
mkdir -p "$NO_IDENTITY_SHIM"
cat > "$NO_IDENTITY_SHIM/security" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "find-identity" ]; then
  echo "0 valid identities found"
  exit 0
fi
exit 127
EOF
chmod +x "$NO_IDENTITY_SHIM/security"

NO_IDENTITY_LOG="$WORK_DIR/no-identity.log"
set +e
PATH="$NO_IDENTITY_SHIM:$PATH" \
  PLAYSTEAD_TEAM_ID="PLACEHOLDER_TEAM" \
  PLAYSTEAD_DEV_ID_APP="Developer ID Application: Placeholder (PLACEHOLDER_TEAM)" \
  PLAYSTEAD_NOTARY_PROFILE="placeholder-profile" \
  "$VERIFY_SCRIPT" --preflight-only >"$NO_IDENTITY_LOG" 2>&1
NO_IDENTITY_STATUS=$?
set -e

if [ "$NO_IDENTITY_STATUS" -eq 0 ]; then
  printf 'notarization-preflight-test: preflight exited 0 with no Developer ID identity available\n' >&2
  cat "$NO_IDENTITY_LOG" >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: preflight exits non-zero with no Developer ID identity available\n'

if ! grep -q 'NO_DEVELOPER_ID_IDENTITY' "$NO_IDENTITY_LOG"; then
  printf 'notarization-preflight-test: refusal did not name NO_DEVELOPER_ID_IDENTITY\n' >&2
  cat "$NO_IDENTITY_LOG" >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: refusal stderr names NO_DEVELOPER_ID_IDENTITY\n'

# --- Direction two: stubbed identity + credential profile -> preflight
#     proceeds. This is what stops direction one from passing merely
#     because the script is broken and always fails. ---
OK_SHIM="$WORK_DIR/ok-bin"
mkdir -p "$OK_SHIM"
cat > "$OK_SHIM/security" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "find-identity" ]; then
  echo "1) 0000000000000000000000000000000000000A \"Developer ID Application: Placeholder (PLACEHOLDER_TEAM)\""
  echo "1 valid identities found"
  exit 0
fi
exit 127
EOF
chmod +x "$OK_SHIM/security"

cat > "$OK_SHIM/xcrun" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "notarytool" ] && [ "$2" = "history" ]; then
  echo "History"
  echo "--------------------------------------------------"
  exit 0
fi
exit 127
EOF
chmod +x "$OK_SHIM/xcrun"

OK_LOG="$WORK_DIR/ok.log"
set +e
PATH="$OK_SHIM:$PATH" \
  PLAYSTEAD_TEAM_ID="PLACEHOLDER_TEAM" \
  PLAYSTEAD_DEV_ID_APP="Developer ID Application: Placeholder (PLACEHOLDER_TEAM)" \
  PLAYSTEAD_NOTARY_PROFILE="placeholder-profile" \
  "$VERIFY_SCRIPT" --preflight-only >"$OK_LOG" 2>&1
OK_STATUS=$?
set -e

if [ "$OK_STATUS" -ne 0 ]; then
  printf 'notarization-preflight-test: preflight refused a stubbed identity and credential profile\n' >&2
  cat "$OK_LOG" >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: preflight exits 0 with a stubbed Developer ID identity and credential profile\n'

if [ "$ASSERTION_COUNT" -eq 0 ]; then
  printf 'notarization-preflight-test: 0 assertions ran — fail-open\n' >&2
  exit 1
fi

printf 'notarization-preflight-test: %s assertions ran\n' "$ASSERTION_COUNT"
printf 'PASS: preflight refuses to certify an unnotarized build\n'
