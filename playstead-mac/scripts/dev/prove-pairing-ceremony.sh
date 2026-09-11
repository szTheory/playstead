#!/usr/bin/env bash
# One-command bootstrap proof for ROADMAP criterion 6 (PROT-01).
#
# Why this exists: the mac_ci Phoenix endpoint now terminates TLS, and the Mac
# app pairs through platform default trust evaluation -- so the run's CA has to
# be a real trusted root on this machine for the duration of the run. Installing
# a trust anchor is the one step macOS will not let a script do unattended, so
# this driver reduces the human part to a single password entry and then runs
# every proof, every assertion, and the teardown check by itself.
#
# It writes EVIDENCE.md with the decisive log lines quoted verbatim, which is
# what the plan's SUMMARY has to cite. Hand that file back, not a scrollback.
#
# This is a one-time bootstrap. Plan 04.5-05 makes the hosted runner do all of
# this on every push, fail-closed, and then nobody runs this by hand again.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HARNESS="$REPO/playstead-mac/scripts/dev/local-live-server.sh"
PG_FLAG=""
OUT="/tmp/playstead-ceremony-proof"

while [ $# -gt 0 ]; do
  case "$1" in
    --brew) PG_FLAG="--brew" ;;
    --docker) PG_FLAG="--docker" ;;
    --out) shift; [ $# -gt 0 ] || { echo "--out requires a path" >&2; exit 2; }; OUT="$1" ;;
    -h|--help)
      echo "usage: ${BASH_SOURCE[0]##*/} [--brew|--docker] [--out DIR]"
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -x "$HARNESS" ] || { echo "FATAL: $HARNESS is missing or not executable" >&2; exit 1; }

# Never run the whole thing as root. Only the two `security` calls inside
# mac-ci-tls.sh need privilege, and they ask for it themselves. Running the
# driver under sudo would build and test as root, leaving root-owned
# DerivedData and client state behind that your normal user then cannot write.
if [ "$(id -u)" -eq 0 ]; then
  cat >&2 <<'ASROOT'
FATAL: do not run this script with sudo.

Run it as your normal user:
  playstead-mac/scripts/dev/prove-pairing-ceremony.sh

It prompts for your password once and elevates only the two `security`
add/remove-trusted-cert calls that genuinely need root. Running the whole
driver as root builds and tests as root and leaves root-owned files behind.
ASROOT
  exit 1
fi

FAILURES=0
EVIDENCE="$OUT/EVIDENCE.md"

# --- sudo: prompt at most once, then hold the timestamp for the whole run -----
# mac-ci-tls.sh trust/untrust use `sudo -n` deliberately (a CI runner must never
# block on a prompt). A developer machine has no NOPASSWD entry, so `sudo -n`
# only succeeds if the timestamp is already primed. Prime it here, then refresh
# it in the background -- the runs together outlast sudo's 5-minute default, and
# a timestamp that expires mid-run makes `untrust` fail and leaves a trusted
# root behind, which is the worst outcome this script can produce.
SUDO_KEEPALIVE_PID=""
cleanup() {
  [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT

if sudo -n true 2>/dev/null; then
  echo "== sudo: already non-interactive (NOPASSWD or primed timestamp)"
else
  if [ ! -t 0 ]; then
    cat >&2 <<'NOTTY'
FATAL: sudo needs a password and this session has no terminal.

Run this script from Terminal.app (or grant scoped NOPASSWD for
/usr/bin/security add-trusted-cert, remove-trusted-cert, delete-certificate).
The trust anchor cannot be installed without one of those two.
NOTTY
    exit 1
  fi
  echo "== sudo: one password, once -- installing the run's CA as a trusted root"
  sudo -v || { echo "FATAL: sudo authentication failed" >&2; exit 1; }
fi

( while true; do sudo -n -v 2>/dev/null || exit 0; sleep 45; done ) &
SUDO_KEEPALIVE_PID=$!

# --- assertions ---------------------------------------------------------------
mkdir -p "$OUT"
: >"$EVIDENCE"

note() { printf '%s\n' "$*" >>"$EVIDENCE"; }

# require_log <label> <file>
# A missing log file must FAIL every check that reads it. Without this, a
# "count == 0" assertion is satisfied by a log that was never written -- the run
# crashed before producing it -- and a red run reports as clean. Absence of
# evidence is not evidence of a pass.
require_log() {
  local label="$1" file="$2"
  if [ -f "$file" ]; then
    return 0
  fi
  echo "  FAIL  $label (log missing: $file)"
  note "- **FAIL** ${label} — log file \`${file}\` does not exist, so this check could not be evaluated."
  FAILURES=$((FAILURES + 1))
  return 1
}

# assert_match <label> <file> <extended-regex>
# Records the first matching line verbatim, or marks the check failed.
assert_match() {
  local label="$1" file="$2" pattern="$3" line
  require_log "$label" "$file" || return 0
  line=$(grep -aEm1 "$pattern" "$file" 2>/dev/null)
  if [ -n "$line" ]; then
    echo "  PASS  $label"
    note "- **PASS** ${label}"
    note '  ```'
    note "  ${line}"
    note '  ```'
  else
    echo "  FAIL  $label"
    note "- **FAIL** ${label} -- no line matching \`${pattern}\` in \`${file}\`"
    FAILURES=$((FAILURES + 1))
  fi
}

# assert_count <label> <file> <extended-regex> <expected-count-or-min:N>
assert_count() {
  local label="$1" file="$2" pattern="$3" expect="$4" actual
  require_log "$label" "$file" || return 0
  actual=$(grep -acE "$pattern" "$file" 2>/dev/null)
  [ -n "$actual" ] || actual=0
  local ok=false
  case "$expect" in
    min:*) [ "$actual" -ge "${expect#min:}" ] && ok=true ;;
    *)     [ "$actual" -eq "$expect" ] && ok=true ;;
  esac
  if [ "$ok" = true ]; then
    echo "  PASS  $label (count=$actual)"
    note "- **PASS** ${label} — count=${actual} (expected ${expect})"
  else
    echo "  FAIL  $label (count=$actual, expected $expect)"
    note "- **FAIL** ${label} — count=${actual}, expected ${expect}, pattern \`${pattern}\`"
    FAILURES=$((FAILURES + 1))
  fi
}

# run_harness <slug> <only-testing-id>...
run_harness() {
  local slug="$1"; shift
  local work="$OUT/$slug" only=()
  local id
  for id in "$@"; do only+=(--only-testing "$id"); done
  rm -rf "$work"
  # The harness creates $WORK itself now, but create it here too so this driver
  # still works against an older harness that expects the dir to pre-exist.
  mkdir -p "$work"
  echo "== run '$slug': $*"
  # Harness stdout carries the `== tls handshake verified` proof; the xcodebuild
  # and Phoenix logs land under $work/native-services/.
  set -o pipefail
  "$HARNESS" $PG_FLAG --xcuitest "${only[@]}" "$work" 2>&1 | tee "$OUT/$slug-harness.log"
  local rc=$?
  set +o pipefail
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL  harness exited $rc"
    note "- **FAIL** run \`${slug}\`: harness exited ${rc}"
    FAILURES=$((FAILURES + 1))
  fi
  return 0
}

CEREMONY_TEST='testAHumanCanPairAFreshMacEntirelyFromInsideTheAppAgainstTheRealServer'
CEREMONY_ID="PlaysteadUITests/PairingCeremonyTests"

note "# Criterion 6 proof — PairingCeremonyTests over real TLS"
note ""
note "Produced by \`playstead-mac/scripts/dev/prove-pairing-ceremony.sh\` on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
note "Commit: $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
note ""

# --- Run 1: the criterion-6 tracer -------------------------------------------
note "## Run 1 — ceremony against the TLS-terminating mac_ci endpoint"
note ""
run_harness tracer "$CEREMONY_ID"
L="$OUT/tracer/native-services"
assert_match "tls handshake verified"        "$OUT/tracer-harness.log" '== tls handshake verified'
assert_match "ceremony test passed"          "$L/live-server.log"      "Test Case .*PairingCeremonyTests.*${CEREMONY_TEST}.* passed"
assert_match "one test, zero failures"       "$L/live-server.log"      'Executed 1 test, with 0 failures'
assert_count "no skipped/failed ceremony"    "$L/live-server.log"      'Test Case .*PairingCeremonyTests.* (skipped|failed)' 0
assert_count "server saw pairing request"    "$L/phoenix.log"          'POST /api/v1/device-pairing/requests' min:1
assert_count "server saw redeem"             "$L/phoenix.log"          'POST /api/v1/device-pairing/requests/.*/redeem' min:1
note ""

# --- Run 2: the rest of the live-server layer still passes over https ---------
note "## Run 2 — live-server layer regression over https"
note ""
run_harness https \
  PlaysteadUITests/LiveServerSnapshotTests \
  PlaysteadUITests/SaveEndToEndTests \
  PlaysteadUITests/SaveRestoreProofTests \
  "$CEREMONY_ID"
L="$OUT/https/native-services"
assert_match "four tests, zero failures"     "$L/live-server.log" 'Executed 4 tests, with 0 failures'
assert_count "no skipped/failed anywhere"    "$L/live-server.log" 'Test Case .* (skipped|failed)' 0
note ""

# --- Run 3: WR-01's Release gate did not break the ceremony -------------------
note "## Run 3 — ceremony still green with the WR-01 #if DEBUG gate in place"
note ""
run_harness wr01 "$CEREMONY_ID"
L="$OUT/wr01/native-services"
assert_match "ceremony test passed"          "$L/live-server.log" "Test Case .*PairingCeremonyTests.*${CEREMONY_TEST}.* passed"
assert_count "not zero tests"                "$L/live-server.log" 'Executed 0 tests' 0
note ""

# --- Teardown: no trust anchor may survive the run ----------------------------
note "## Teardown — the run's CA is gone from the System keychain"
note ""
if sudo -n security find-certificate -Z -c "Playstead Mac CI Root" \
     /Library/Keychains/System.keychain >/dev/null 2>&1; then
  echo "  FAIL  a 'Playstead Mac CI Root' CA is STILL trusted in the System keychain"
  note "- **FAIL** a \`Playstead Mac CI Root\` CA is still present in the System keychain."
  note "  Remove it before continuing:"
  note '  ```'
  note '  sudo security delete-certificate -c "Playstead Mac CI Root" /Library/Keychains/System.keychain'
  note '  ```'
  FAILURES=$((FAILURES + 1))
else
  echo "  PASS  no Playstead Mac CI Root left in the System keychain"
  note "- **PASS** no \`Playstead Mac CI Root\` remains in the System keychain."
fi
note ""

# --- Verdict ------------------------------------------------------------------
echo
if [ "$FAILURES" -eq 0 ]; then
  note "## Verdict: PASS — every criterion-6 check passed."
  echo "== PASS: criterion 6 proven. Evidence: $EVIDENCE"
  echo "== Next: /gsd-execute-phase 04.5 --gaps-only"
  exit 0
fi
note "## Verdict: FAIL — ${FAILURES} check(s) failed."
echo "== FAIL: $FAILURES check(s) failed. Evidence: $EVIDENCE"
echo "== Logs: $OUT/{tracer,https,wr01}/native-services/{live-server,phoenix}.log"
exit 1
