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

# Full mode must refuse before preflight or any build/sign/notary tool when no
# durable sanitized-evidence destination was explicitly supplied.
EARLY_REFUSAL_BIN="$WORK_DIR/early-refusal-bin"
EARLY_REFUSAL_MARKER="$WORK_DIR/external-tool-was-called"
mkdir -p "$EARLY_REFUSAL_BIN"
cat > "$EARLY_REFUSAL_BIN/security" <<EOF
#!/usr/bin/env bash
touch "$EARLY_REFUSAL_MARKER"
exit 99
EOF
chmod +x "$EARLY_REFUSAL_BIN/security"

MISSING_EVIDENCE_LOG="$WORK_DIR/missing-evidence.log"
set +e
PATH="$EARLY_REFUSAL_BIN:$PATH" \
  PLAYSTEAD_TEAM_ID="PLACEHOLDER_TEAM" \
  PLAYSTEAD_DEV_ID_APP="Developer ID Application: Placeholder (PLACEHOLDER_TEAM)" \
  PLAYSTEAD_NOTARY_PROFILE="placeholder-profile" \
  "$VERIFY_SCRIPT" >"$MISSING_EVIDENCE_LOG" 2>&1
MISSING_EVIDENCE_STATUS=$?
set -e

if [ "$MISSING_EVIDENCE_STATUS" -eq 0 ]; then
  printf 'notarization-preflight-test: full mode accepted a missing evidence destination\n' >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: full mode exits non-zero without --evidence-output\n'

if ! grep -q 'NO_EVIDENCE_OUTPUT' "$MISSING_EVIDENCE_LOG"; then
  printf 'notarization-preflight-test: missing evidence refusal did not name NO_EVIDENCE_OUTPUT\n' >&2
  cat "$MISSING_EVIDENCE_LOG" >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: missing evidence refusal names NO_EVIDENCE_OUTPUT\n'

if [ -e "$EARLY_REFUSAL_MARKER" ]; then
  printf 'notarization-preflight-test: external tooling ran before missing evidence refusal\n' >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: missing evidence refusal happens before external tooling\n'

# A caller-provided regular file is not proof that the sanitizer capture helper
# created this invocation. This is the exact T-03-12-03 bypass regression: the
# old recursion sentinel accepted /etc/hosts and entered external preflight.
rm -f "$EARLY_REFUSAL_MARKER"
FORGED_CAPABILITY_LOG="$WORK_DIR/forged-capability.log"
FORGED_EVIDENCE_OUTPUT="$WORK_DIR/forged-evidence.log"
set +e
PATH="$EARLY_REFUSAL_BIN:$PATH" \
  PLAYSTEAD_TEAM_ID="PLACEHOLDER_TEAM" \
  PLAYSTEAD_DEV_ID_APP="Developer ID Application: Placeholder (PLACEHOLDER_TEAM)" \
  PLAYSTEAD_NOTARY_PROFILE="placeholder-profile" \
  PLAYSTEAD_EVIDENCE_CAPTURE_ACTIVE="/etc/hosts" \
  "$VERIFY_SCRIPT" --evidence-output "$FORGED_EVIDENCE_OUTPUT" \
  >"$FORGED_CAPABILITY_LOG" 2>&1
FORGED_CAPABILITY_STATUS=$?
set -e

if [ "$FORGED_CAPABILITY_STATUS" -eq 0 ]; then
  printf 'notarization-preflight-test: forged capture sentinel was accepted\n' >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: forged capture sentinel exits non-zero\n'

if ! grep -q 'INVALID_EVIDENCE_CAPTURE_CAPABILITY' "$FORGED_CAPABILITY_LOG"; then
  printf 'notarization-preflight-test: forged capture refusal did not name INVALID_EVIDENCE_CAPTURE_CAPABILITY\n' >&2
  cat "$FORGED_CAPABILITY_LOG" >&2
  exit 1
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
printf 'ASSERT: forged capture refusal names INVALID_EVIDENCE_CAPTURE_CAPABILITY\n'

if [ -e "$EARLY_REFUSAL_MARKER" ]; then
  printf 'notarization-preflight-test: forged capture sentinel reached external tooling\n' >&2
  exit 1
fi
[ ! -e "$FORGED_EVIDENCE_OUTPUT" ] || {
  printf 'notarization-preflight-test: forged capture sentinel published evidence\n' >&2
  exit 1
}
ASSERTION_COUNT=$((ASSERTION_COUNT + 2))
printf 'ASSERT: forged capture sentinel cannot reach tools or publish evidence\n'

printf 'notarization-preflight-test: %s assertions ran\n' "$ASSERTION_COUNT"
printf 'PASS: preflight refuses to certify an unnotarized build\n'
