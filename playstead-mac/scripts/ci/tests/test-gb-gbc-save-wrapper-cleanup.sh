#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failure_output="$(mktemp)"
interrupt_output="$(mktemp)"
registry_output="$(mktemp)"
trap 'rm -f "$failure_output" "$interrupt_output" "$registry_output"' EXIT

set +e
"$SCRIPT_DIR/gb-gbc-save-e2e.sh" --case gb-mbc1-8k --local-no-hid --self-test-cleanup-failure >"$failure_output" 2>&1
failure_status=$?
"$SCRIPT_DIR/gb-gbc-save-e2e.sh" --case gb-mbc1-8k --local-no-hid --self-test-cleanup-interrupt >"$interrupt_output" 2>&1
interrupt_status=$?
env -u PLAYSTEAD_AEREVEN_FIXTURE_REGISTRY "$SCRIPT_DIR/gb-gbc-save-e2e.sh" --all-cases --self-test-cleanup-failure >"$registry_output" 2>&1
registry_status=$?
set -e

[ "$failure_status" -eq 42 ] || { cat "$failure_output"; printf 'failure status: %s\n' "$failure_status" >&2; exit 1; }
[ "$interrupt_status" -eq 130 ] || { cat "$interrupt_output"; printf 'interrupt status: %s\n' "$interrupt_status" >&2; exit 1; }
[ "$registry_status" -eq 42 ] || { cat "$registry_output"; printf 'default Aereven registry status: %s\n' "$registry_status" >&2; exit 1; }
rg -q 'private profile cleanup verified' "$failure_output"
rg -q 'private profile cleanup verified' "$interrupt_output"
rg -q 'private profile cleanup verified' "$registry_output"
rg -Fq 'registry="${PLAYSTEAD_AEREVEN_FIXTURE_REGISTRY:-${SCRIPT_DIR}/../../.local/test-fixtures/aerevenadvance.json}"' "$SCRIPT_DIR/gb-gbc-save-e2e.sh"
printf '%s\n' 'wrapper failure, interrupt cleanup, all-case cleanup, and private registry defaults passed'
