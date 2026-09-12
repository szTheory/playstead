#!/usr/bin/env bash
# The live-server stage marker must name where the FIXTURE died -- and must say
# nothing at all when the fixture did not die.
#
# It was written on entering every stage and never cleared when an action
# SUCCEEDED, so after any completed action it still held that action's last
# stage. The runner reads the marker on ANY live-server layer failure, including
# one in Swift test code the fixture never touched, and prints it as the stage
# the fixture failed at. Run 34648546919 reported `FAILURE_STAGE redeem-pairing`
# for a `prepare` that had completed fine; the real failure was
# save-e2e-harness=upload-did-not-complete, in a later process entirely. A
# confident wrong answer is worse than no answer, because it is believed.
#
# This sources the REAL functions out of live-server.sh rather than restating
# them, so the test cannot pass against a copy that has drifted from what ships.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="${SCRIPT_DIR}/../live-server.sh"
[ -f "$FIXTURE" ] || { printf 'missing %s\n' "$FIXTURE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Extract the three marker functions from the shipped fixture -------------
awk '
  /^validated_marker\(\) \{$/      { inside = 1 }
  inside                            { print }
  /^\}$/ && inside && seen_clear    { exit }
  /^clear_failure_stage\(\) \{$/    { seen_clear = 1 }
' "$FIXTURE" > "$WORK/marker-functions.sh"

for fn in validated_marker write_failure_stage clear_failure_stage; do
  grep -q "^${fn}() {" "$WORK/marker-functions.sh" || {
    printf 'extraction missed %s -- live-server.sh layout changed\n' "$fn" >&2
    exit 1
  }
done

# shellcheck disable=SC1090
source "$WORK/marker-functions.sh"

ROOT="$WORK/evidence"
mkdir -m 0700 -p "$ROOT"
MARKER="$ROOT/live-server-failure-stage"
export PLAYSTEAD_LIVE_SERVER_STAGE_ROOT="$ROOT"
export PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$MARKER"

fail() { printf '%s\n' "$1" >&2; exit 1; }

# --- A failing stage records where it died -----------------------------------
stage="redeem-pairing"
write_failure_stage
[ -f "$MARKER" ] || fail "write_failure_stage left no marker"
[ "$(tr -d '\r\n' <"$MARKER")" = "redeem-pairing" ] || fail "marker holds the wrong stage"
[ "$(stat -f '%Lp' "$MARKER")" = "600" ] || fail "marker is not mode 600; the runner rejects it as invalid-mode"

# --- A successful action leaves nothing behind -------------------------------
# This is the regression under test. Without it the value above survives and is
# reported as the cause of an unrelated later failure.
clear_failure_stage
[ ! -e "$MARKER" ] || fail "clear_failure_stage left a stale marker: a later unrelated failure will inherit it"

# --- The clearer is exactly as strict as the writer --------------------------
# A clearer with weaker path checks than the writer is an arbitrary-path rm.
OUTSIDE="$WORK/outside"
mkdir -m 0700 -p "$OUTSIDE"
: >"$OUTSIDE/live-server-failure-stage"

PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$OUTSIDE/live-server-failure-stage" clear_failure_stage || true
[ -f "$OUTSIDE/live-server-failure-stage" ] || fail "cleared a marker outside the evidence root"

: >"$ROOT/some-other-file"
PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$ROOT/some-other-file" clear_failure_stage || true
[ -f "$ROOT/some-other-file" ] || fail "cleared a file whose basename is not live-server-failure-stage"

PLAYSTEAD_LIVE_SERVER_STAGE_FILE="" clear_failure_stage || true
PLAYSTEAD_LIVE_SERVER_STAGE_ROOT="" clear_failure_stage || true

# --- A stage the runner does not accept is never recorded --------------------
# `stage="complete"` is set after a successful action; it is not in the
# allowlist, so it must not reach the marker -- the runner would print
# FAILURE_STAGE invalid-token for it.
stage="complete"
write_failure_stage
[ ! -e "$MARKER" ] || fail "an unlisted stage reached the marker"

# --- The success path in the shipped trap actually calls the clearer ---------
# Sourcing the functions proves they behave; it does not prove live-server.sh
# invokes them. Without this, the fix could be reverted at the call site while
# every assertion above still passed.
grep -F 'else clear_failure_stage || true; fi' "$FIXTURE" >/dev/null || \
  fail "live-server.sh's EXIT trap no longer clears the marker on success"

printf 'live-server stage marker contract: passed\n'
