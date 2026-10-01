#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/../repeat-save-e2e-reliability.sh"

grep -F 'SIGNING_MODE="${PLAYSTEAD_MAC_CI_SIGNING_MODE:-}"' "$RUNNER" >/dev/null
grep -F '[ "${GITHUB_ACTIONS:-}" != "true" ] && [ -n "${PLAYSTEAD_TEAM_ID:-}" ]' "$RUNNER" >/dev/null
grep -F 'SIGNING_MODE="development"' "$RUNNER" >/dev/null
grep -F 'SIGNING_MODE="adhoc"' "$RUNNER" >/dev/null
grep -F 'PLAYSTEAD_MAC_CI_SIGNING_MODE="$SIGNING_MODE"' "$RUNNER" >/dev/null
grep -F 'PROVISIONING_PROFILE_SPECIFIER=' "${SCRIPT_DIR}/../run-mac-verification.sh" >/dev/null

printf '%s\n' 'save reliability signing mode: local identity selection and profile-free signing contract passed'
