#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="${SCRIPT_DIR}/../../../../.github/workflows/ci.yml"

# Trusted-code regression guard only. Fork PRs can change this workflow and
# guard together, so the actual boundary is that public ci.yml has no runner
# registration or self-hosted selector available to it.
python3 - "$WORKFLOW" <<'PY'
import pathlib, sys
workflow = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

def validate(source):
    executable = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    if "self-hosted" in executable:
        return False
    if "mac-entitled-virtual-gamepad:" in executable:
        return False
    if "PLAYSTEAD_HID_RUNNER_AVAILABLE" in executable or "playstead-virtual-hid" in executable:
        return False
    return "--run-unprivileged-verification" in executable and "mac-ordinary-evidence" in executable

if not validate(workflow):
    raise SystemExit("public CI must retain ordinary Mac evidence and contain no self-hosted HID lane")
mutations = (
    workflow.replace("runs-on: macos-26", "runs-on:\n      - self-hosted\n      - macOS", 1),
    workflow + "\n  mac-entitled-virtual-gamepad:\n    runs-on: [self-hosted, macOS]\n",
    workflow.replace("mac-ordinary-evidence", "mac-entitled-gamepad-evidence", 1),
)
if any(validate(candidate) for candidate in mutations):
    raise SystemExit("public CI trust contract accepted an unsafe/missing-evidence mutation")
print(f"public workflow isolation contract passed ({len(mutations)} unsafe mutations rejected)")
PY

printf '%s\n' 'protected Virtual HID workflow contract (must discover tests)'
contract_output="$(python3 -m unittest discover \
  -s "${SCRIPT_DIR}" \
  -p 'test_virtual_hid_workflow_contract.py' -v 2>&1)" || {
    printf '%s\n' "$contract_output" >&2
    exit 1
  }
printf '%s\n' "$contract_output"
printf '%s\n' "$contract_output" | grep -Eq '^Ran [1-9][0-9]* tests?'
