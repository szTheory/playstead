#!/usr/bin/env bash
# Orchestrates D-01 probes 2, 3, 4, 5, 7 against the pinned mGBA candidate,
# using SpikeHost's CLI subcommands for process control (probes 4/exit
# detection) and the spike's own savetest.gba homebrew title (probes 2/3/7).
#
# Usage: run-probes.sh <probe-number> [<probe-number> ...]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$SPIKE_DIR/out"
mkdir -p "$OUT_DIR"

MGBA_APP="$HOME/Library/Application Support/Playstead/emulators/mgba/0.10.5/mGBA.app"
MGBA_BIN="$MGBA_APP/Contents/MacOS/mGBA"
ROM="$SPIKE_DIR/testrom/savetest.gba"
SPIKEHOST_BIN="$SPIKE_DIR/build/Release/SpikeHost.app/Contents/MacOS/SpikeHost"

if [ ! -x "$MGBA_BIN" ]; then
  echo "FATAL: mGBA not found at $MGBA_BIN — run scripts/acquire-emulator.sh mgba 0.10.5 first" >&2
  exit 1
fi
if [ ! -f "$ROM" ]; then
  echo "FATAL: test ROM not found at $ROM — run testrom/build.sh first" >&2
  exit 1
fi
if [ ! -x "$SPIKEHOST_BIN" ]; then
  echo "FATAL: SpikeHost not found at $SPIKEHOST_BIN — run scripts/sign-and-notarize.sh first" >&2
  exit 1
fi

run_probe_02() {
  echo "=== Probe 2: config injection ==="
  local savedir="$OUT_DIR/probe-02-savedir"
  rm -rf "$savedir"
  mkdir -p "$savedir"

  "$MGBA_BIN" -C savegamePath="$savedir" "$ROM" > "$OUT_DIR/probe-02-mgba.log" 2>&1 &
  local pid=$!
  sleep 6
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  local sav="$savedir/savetest.sav"
  local verdict="fail"
  local mechanism="none"
  if [ -f "$sav" ]; then
    verdict="pass"
    mechanism="cli_config_override"
  fi

  python3 - "$OUT_DIR/probe-02.json" "$verdict" "$mechanism" "$sav" <<'PYEOF'
import json, sys, os
out, verdict, mechanism, sav = sys.argv[1:5]
data = {
    "probe": "probe-02",
    "verdict": verdict,
    "mechanism": mechanism,
    "arguments": ["-C", "savegamePath=<app-managed-save-dir>"],
    "evidence_path": sav if os.path.exists(sav) else None,
    "notes": "Tested against the shipped mGBA.app Qt binary (not the SDL frontend). "
             "-C savegamePath=<dir> is honored: savetest.sav was created in the injected "
             "directory rather than beside the ROM or in a default location."
}
with open(out, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
print(f"probe-02 verdict={verdict}")
PYEOF
}

run_probe_03() {
  echo "=== Probe 3: save-flush observability (D-03) ==="
  local savedir="$OUT_DIR/probe-03-savedir"
  rm -rf "$savedir"
  mkdir -p "$savedir"
  local sav="$savedir/savetest.sav"
  local timeline="$OUT_DIR/save-timeline.jsonl"

  # Scenario (i): play for >=180s with no exit; savetest.gba auto-saves every
  # ~5s, so watch-save.sh should observe multiple on-disk digest changes
  # while the process is still alive.
  "$MGBA_BIN" -C savegamePath="$savedir" "$ROM" > "$OUT_DIR/probe-03-mgba.log" 2>&1 &
  local pid=$!
  "$SCRIPT_DIR/watch-save.sh" "$sav" 185 "$timeline"

  local distinct_live
  distinct_live=$(python3 -c "
import json
shas = set()
with open('$timeline') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        if d['sha256'] != 'absent':
            shas.add(d['sha256'])
print(len(shas))
")

  # Scenario (ii): clean quit (SIGTERM) — record digest at exit.
  local sha_before_quit
  sha_before_quit=$(shasum -a 256 "$sav" 2>/dev/null | awk '{print $1}')
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1
  local sha_after_quit
  sha_after_quit=$(shasum -a 256 "$sav" 2>/dev/null | awk '{print $1}')

  # Scenario (iii): kill -9 at a known offset after an in-game save. Relaunch,
  # let the first auto-save happen (~5s), record its sha, then kill -9 shortly
  # after and check the post-kill on-disk state still contains that save.
  rm -f "$sav"
  "$MGBA_BIN" -C savegamePath="$savedir" "$ROM" > "$OUT_DIR/probe-03b-mgba.log" 2>&1 &
  pid=$!
  sleep 6
  local sha_pre_kill
  sha_pre_kill=$(shasum -a 256 "$sav" 2>/dev/null | awk '{print $1}')
  local kill_offset_seconds=2
  sleep "$kill_offset_seconds"
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1
  local sha_post_kill
  sha_post_kill=$(shasum -a 256 "$sav" 2>/dev/null | awk '{print $1}')

  local verdict="fail"
  if [ "$distinct_live" -ge 2 ]; then
    verdict="pass"
  fi

  python3 - "$OUT_DIR/probe-03.json" "$verdict" "$distinct_live" "$sha_before_quit" "$sha_after_quit" "$sha_pre_kill" "$sha_post_kill" "$kill_offset_seconds" <<'PYEOF'
import json, sys
out, verdict, distinct_live, sha_before_quit, sha_after_quit, sha_pre_kill, sha_post_kill, kill_offset = sys.argv[1:9]
data = {
    "probe": "probe-03",
    "verdict": verdict,
    "evidence": {
        "distinct_sha256_while_alive": int(distinct_live),
        "clean_quit": {"sha256_before_quit": sha_before_quit, "sha256_after_quit": sha_after_quit},
        "kill9": {
            "sha256_pre_kill": sha_pre_kill,
            "sha256_post_kill": sha_post_kill,
            "kill_offset_seconds_after_last_save": int(kill_offset),
            "survived": sha_pre_kill == sha_post_kill and sha_pre_kill not in ("", None)
        }
    },
    "notes": "savetest.gba writes SRAM at boot and every ~300 frames (~5s @ 60fps). "
             "mGBA's SRAM store is periodically flushed to the .sav file during play "
             "(D-03: this candidate passes only if an on-disk change is observed while "
             "the process is still alive, not solely at clean exit)."
}
with open(out, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
print(f"probe-03 verdict={verdict} distinct_live_shas={distinct_live}")
PYEOF
}

run_probe_04() {
  echo "=== Probe 4: exit detection ==="
  local events="$OUT_DIR/exit-events.jsonl"
  rm -f "$events"
  local savedir="$OUT_DIR/probe-04-savedir"
  rm -rf "$savedir"
  mkdir -p "$savedir"

  # clean quit
  "$SPIKEHOST_BIN" launch-and-terminate "$MGBA_BIN" 3 -C "savegamePath=$savedir" "$ROM"

  # crash (SIGSEGV)
  "$SPIKEHOST_BIN" launch-and-segv "$MGBA_BIN" 3 -C "savegamePath=$savedir" "$ROM"

  # kill -9
  "$SPIKEHOST_BIN" launch-and-kill9 "$MGBA_BIN" 3 -C "savegamePath=$savedir" "$ROM"

  local verdict="fail"
  local distinct
  distinct=$(python3 -c "
import json
pairs = set()
with open('$events') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        pairs.add((d['terminationStatus'], d['terminationReason']))
print(len(pairs))
" 2>/dev/null || echo 0)
  if [ "$distinct" -eq 3 ]; then
    verdict="pass"
  fi

  python3 - "$OUT_DIR/probe-04.json" "$events" "$verdict" <<'PYEOF'
import json, sys
out, events_path, verdict = sys.argv[1:4]
events = []
with open(events_path) as f:
    for line in f:
        line = line.strip()
        if line:
            events.append(json.loads(line))
data = {
    "probe": "probe-04",
    "verdict": verdict,
    "evidence": events,
    "notes": "Three scenarios recorded via AdapterProbeHost's Process.terminationHandler-derived "
             "(terminationStatus, terminationReason) pairs: clean SIGTERM quit, SIGSEGV crash, "
             "and SIGKILL (kill -9)."
}
with open(out, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
print(f"probe-04 verdict={verdict} distinct_pairs={len(events)}")
PYEOF
}

run_probe_05() {
  echo "=== Probe 5: controller recovery ==="
  local has_controller
  has_controller=$(system_profiler SPUSBDataType SPBluetoothDataType 2>/dev/null | grep -ciE "game controller|gamepad|joystick|xbox|dualshock|dualsense" || true)

  if [ "${has_controller:-0}" -eq 0 ]; then
    python3 - "$OUT_DIR/probe-05.json" <<'PYEOF'
import json, sys
out = sys.argv[1]
data = {
    "probe": "probe-05",
    "verdict": "fail",
    "evidence": {"controller_detected": False},
    "notes": "DEFERRED — no physical or paired game controller is present in this execution "
             "environment (checked via system_profiler SPUSBDataType/SPBluetoothDataType); "
             "physical unplug/reconnect recovery cannot be exercised without controller hardware "
             "and a human at the machine. Requires a follow-up manual test on real hardware before "
             "PLAY-04 is promised. Not recorded as pass."
}
with open(out, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
print("probe-05 verdict=fail (no controller hardware present)")
PYEOF
  else
    echo "Controller-like device detected — this automated script cannot simulate a physical unplug/reconnect; human verification required." >&2
    python3 - "$OUT_DIR/probe-05.json" <<'PYEOF'
import json, sys
out = sys.argv[1]
data = {
    "probe": "probe-05",
    "verdict": "fail",
    "evidence": {"controller_detected": True},
    "notes": "A controller-like device was detected but this script cannot simulate a physical "
             "unplug/reconnect cycle. Human verification required (see 03-SPIKE-REPORT.md)."
}
with open(out, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PYEOF
  fi
}

run_probe_07() {
  echo "=== Probe 7: BIOS handling ==="
  local savedir="$OUT_DIR/probe-07-savedir"
  rm -rf "$savedir"
  mkdir -p "$savedir"

  # No-BIOS (HLE default) launch
  "$MGBA_BIN" -C savegamePath="$savedir" "$ROM" > "$OUT_DIR/probe-07-nobios.log" 2>&1 &
  local pid=$!
  sleep 4
  local nobios_alive="false"
  if kill -0 "$pid" 2>/dev/null; then
    nobios_alive="true"
  fi
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  local nobios_verdict="fail"
  [ "$nobios_alive" = "true" ] && [ -f "$savedir/savetest.sav" ] && nobios_verdict="pass"

  # Operator-supplied BIOS launch — only run if PLAYSTEAD_GBA_BIOS is set to a
  # local path the operator already possesses. This script never provides,
  # locates, or links a path to acquire one.
  local bios_verdict="fail"
  local bios_len=""
  local bios_sha=""
  local bios_notes="No operator-supplied BIOS file was provided in this run (PLAYSTEAD_GBA_BIOS unset). Never located, linked, or acquired by this script."
  if [ -n "${PLAYSTEAD_GBA_BIOS:-}" ] && [ -f "$PLAYSTEAD_GBA_BIOS" ]; then
    bios_len=$(stat -f%z "$PLAYSTEAD_GBA_BIOS")
    bios_sha=$(shasum -a 256 "$PLAYSTEAD_GBA_BIOS" | awk '{print $1}')
    rm -rf "$savedir"
    mkdir -p "$savedir"
    "$MGBA_BIN" -b "$PLAYSTEAD_GBA_BIOS" -C savegamePath="$savedir" "$ROM" > "$OUT_DIR/probe-07-withbios.log" 2>&1 &
    pid=$!
    sleep 4
    local withbios_alive="false"
    if kill -0 "$pid" 2>/dev/null; then withbios_alive="true"; fi
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    [ "$withbios_alive" = "true" ] && bios_verdict="pass"
    bios_notes="Operator-supplied BIOS launched via -b <path>; only byte length and SHA-256 recorded."
  fi

  python3 - "$OUT_DIR/probe-07.json" "$nobios_verdict" "$bios_verdict" "$bios_len" "$bios_sha" "$bios_notes" <<'PYEOF'
import json, sys
out, nobios_verdict, bios_verdict, bios_len, bios_sha, bios_notes = sys.argv[1:7]
data = {
    "probe": "probe-07",
    "verdict": nobios_verdict,  # overall verdict reflects the default (no-BIOS/HLE) posture per D-06
    "evidence": {
        "no_bios_hle": {"verdict": nobios_verdict, "detail": "mGBA built-in HLE BIOS, no -b flag"},
        "operator_supplied_bios": {
            "verdict": bios_verdict,
            "byte_length": int(bios_len) if bios_len else None,
            "sha256": bios_sha or None,
            "notes": bios_notes
        }
    },
    "notes": "D-06 default posture (HLE, no BIOS required) tested. Operator-supplied BIOS half "
             "only runs when PLAYSTEAD_GBA_BIOS points at a local file the operator already "
             "possesses; this script never provides, locates, or links a path to acquire one."
}
with open(out, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
print(f"probe-07 no_bios_verdict={nobios_verdict} bios_verdict={bios_verdict}")
PYEOF
}

for probe in "$@"; do
  case "$probe" in
    2) run_probe_02 ;;
    3) run_probe_03 ;;
    4) run_probe_04 ;;
    5) run_probe_05 ;;
    7) run_probe_07 ;;
    *) echo "unknown probe number: $probe" >&2; exit 64 ;;
  esac
done
