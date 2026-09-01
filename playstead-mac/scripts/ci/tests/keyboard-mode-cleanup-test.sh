#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/../run-mac-verification.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-keyboard-cleanup.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
defaults_log="$TMP_ROOT/defaults.log"
cat >"$TMP_ROOT/bin/defaults" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PLAYSTEAD_DEFAULTS_LOG:?}"
exit 0
SH
chmod +x "$TMP_ROOT/bin/defaults"

cleanup_log="$TMP_ROOT/cleanup.log"
if PATH="$TMP_ROOT/bin:$PATH" PLAYSTEAD_DEFAULTS_LOG="$defaults_log" \
  "$RUNNER" --self-test-early-keyboard-cleanup >"$cleanup_log" 2>&1; then
  printf 'early keyboard cleanup self-test unexpectedly succeeded\n' >&2
  exit 1
else
  cleanup_status=$?
fi

[ "$cleanup_status" -eq 97 ] || {
  printf 'cleanup masked the original failure: expected 97, got %s\n' "$cleanup_status" >&2
  sed -n '1,80p' "$cleanup_log" >&2
  exit 1
}
[ ! -s "$defaults_log" ] || {
  printf 'cleanup mutated keyboard defaults before capture\n' >&2
  sed -n '1,80p' "$defaults_log" >&2
  exit 1
}
if grep -F 'unbound variable' "$cleanup_log" >/dev/null; then
  printf 'cleanup referenced an uninitialized trap variable\n' >&2
  exit 1
fi

printf 'keyboard mode early-cleanup contract: passed\n'
