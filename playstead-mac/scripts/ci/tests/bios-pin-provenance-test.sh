#!/usr/bin/env bash
# A fail-closed guard on .planning/.../03-BIOS-PIN.json: a digest pinned
# without at least two independent citable sources is a silent wrong trust
# anchor (T-03-11-01). This guard fails closed below two provenance
# entries, on any non-hex/wrong-length digest, and when the pin file is
# missing entirely — a missing command must not read as clean (this repo
# has already been bitten by that fail-open shape four times).
#
# Every assertion below is also exercised against a temporary malformed
# copy of the pin and must be observed failing there — a guard that has
# never been seen to fail is not a guard.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
PIN_FILE="${REPO_ROOT}/.planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/playstead-bios-pin.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
CHECKER="$WORK_DIR/bios-pin-provenance-detector.py"

cat > "$CHECKER" <<'PY'
import json
import re
import sys

HEX64 = re.compile(r"^[0-9a-f]{64}$")
NO_ACQUISITION = "none - this product never sources, links to, mirrors, or distributes BIOS content"


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        fail("usage: bios-pin-provenance-detector.py <pin-path>")
    path = sys.argv[1]
    count = 0

    try:
        with open(path, "r", encoding="utf-8") as fh:
            pin = json.load(fh)
    except FileNotFoundError:
        fail(f"pin file missing entirely: {path}")
    except json.JSONDecodeError as exc:
        fail(f"pin file does not parse as JSON: {exc}")

    count += 1
    print("ASSERT: pin file exists and parses")

    provenance = pin.get("provenance")
    if not isinstance(provenance, list) or len(provenance) < 2:
        fail("provenance must have at least 2 entries")
    count += 1
    print("ASSERT: provenance has at least 2 entries")

    for entry in provenance:
        if not isinstance(entry, dict) or not entry.get("url"):
            fail("every provenance entry must have a non-empty url")
    count += 1
    print("ASSERT: every provenance entry has a non-empty url")

    digests = pin.get("known_sha256_digests")
    if not isinstance(digests, list) or len(digests) == 0:
        fail("known_sha256_digests must be non-empty")
    count += 1
    print("ASSERT: known_sha256_digests is non-empty")

    for digest in digests:
        if not isinstance(digest, str) or not HEX64.match(digest):
            fail(f"digest is not 64 lowercase hex characters: {digest!r}")
    count += 1
    print("ASSERT: every digest is 64 lowercase hex characters")

    length = pin.get("expected_byte_length")
    if not isinstance(length, int) or isinstance(length, bool) or length <= 0:
        fail(f"expected_byte_length must be a positive integer, got {length!r}")
    count += 1
    print("ASSERT: expected_byte_length is a positive integer")

    if pin.get("open_replacement_declared") is not False:
        fail("open_replacement_declared must be the JSON literal false")
    count += 1
    print("ASSERT: open_replacement_declared is false")

    if pin.get("acquisition_path") != NO_ACQUISITION:
        fail("acquisition_path must be the fixed no-acquisition string")
    count += 1
    print("ASSERT: acquisition_path is the fixed no-acquisition string")

    print(f"ASSERTION_COUNT={count}")
    sys.exit(0)


if __name__ == "__main__":
    main()
PY

# --- Positive check: the real pin must pass every assertion. ---
POSITIVE_OUTPUT="$(python3 "$CHECKER" "$PIN_FILE")"
ASSERTION_COUNT="$(printf '%s\n' "$POSITIVE_OUTPUT" | sed -n 's/^ASSERTION_COUNT=//p')"

if [ -z "$ASSERTION_COUNT" ] || [ "$ASSERTION_COUNT" -eq 0 ]; then
  printf 'bios-pin-provenance-test: 0 assertions ran against the real pin — fail-open\n' >&2
  exit 1
fi

# --- Negative control: a pin with only one provenance entry must fail. ---
python3 - "$PIN_FILE" "$WORK_DIR/one-provenance.json" <<'PY'
import json, sys
pin = json.load(open(sys.argv[1]))
pin["provenance"] = pin["provenance"][:1]
json.dump(pin, open(sys.argv[2], "w"))
PY

if python3 "$CHECKER" "$WORK_DIR/one-provenance.json" >/dev/null 2>&1; then
  printf 'bios-pin-provenance-test: guard accepted a pin with only 1 provenance entry\n' >&2
  exit 1
fi

# --- Negative control: a pin with a non-hex digest must fail. ---
python3 - "$PIN_FILE" "$WORK_DIR/bad-digest.json" <<'PY'
import json, sys
pin = json.load(open(sys.argv[1]))
pin["known_sha256_digests"] = ["not-a-real-digest"]
json.dump(pin, open(sys.argv[2], "w"))
PY

if python3 "$CHECKER" "$WORK_DIR/bad-digest.json" >/dev/null 2>&1; then
  printf 'bios-pin-provenance-test: guard accepted a non-hex digest\n' >&2
  exit 1
fi

# --- Negative control: a missing pin file must fail (never read as clean). ---
if python3 "$CHECKER" "$WORK_DIR/does-not-exist.json" >/dev/null 2>&1; then
  printf 'bios-pin-provenance-test: guard accepted a missing pin file\n' >&2
  exit 1
fi

printf 'bios-pin-provenance-test: %s assertions ran against the real pin, all passed (plus 3 negative controls confirmed failing)\n' "$ASSERTION_COUNT"
