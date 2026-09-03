#!/usr/bin/env bash
# Plan 03.5-09 Task 3, end to end and fail-closed.
#
# Watches one exact authorized run, validates its published evidence, and only
# then mutates ROADMAP.md and 03-UAT.md. Every gate before the mutation exits
# non-zero on failure, so a red or malformed run can never produce a diff --
# which is the plan's central prohibition, not merely a convenience here.
#
#   complete-task3.sh RUN_ID
set -euo pipefail

RUN_ID="${1:?usage: complete-task3.sh RUN_ID}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PHASE="$REPO/.planning/phases/03.5-mac-verification-automation"
TOOLS="$PHASE/tools"
EVIDENCE="$PHASE/evidence"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/playstead-task3.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n== %s\n' "$1"; }

step "watch run $RUN_ID"
gh run watch "$RUN_ID" --exit-status --interval 30 >/dev/null

step "capture exact run identity"
gh run view "$RUN_ID" \
  --json databaseId,workflowName,event,headBranch,headSha,status,conclusion,url,jobs \
  >"$WORK/run-view.json"

# The plan requires the run be reached by exact identity, never by "latest".
python3 - "$WORK/run-view.json" <<'PY'
import json, pathlib, sys
view = json.loads(pathlib.Path(sys.argv[1]).read_text())
if view.get("workflowName") != "ci":
    raise SystemExit(f"unexpected workflow: {view.get('workflowName')}")
if view.get("event") not in {"push", "pull_request"}:
    raise SystemExit(f"unexpected event: {view.get('event')}")
if view.get("status") != "completed" or view.get("conclusion") != "success":
    raise SystemExit(f"run is {view.get('status')}/{view.get('conclusion')}")
print(f"run {view['databaseId']} {view['event']} {view['headBranch']} {view['headSha'][:7]} success")
PY

step "download this run's evidence artifact only"
gh run download "$RUN_ID" --name complete-verification-evidence --dir "$WORK/artifact"
manifest="$(find "$WORK/artifact" -name 'complete-verification-evidence.json' | head -1)"
[ -n "$manifest" ] || { echo "evidence manifest missing from artifact"; exit 1; }

step "build the run record"
mkdir -p "$EVIDENCE"
python3 "$TOOLS/make-final-hosted-run-record.py" \
  --run-view "$WORK/run-view.json" --out "$EVIDENCE/final-hosted-run.json"

step "hosted-run gate (no documentation diff before this passes)"
( cd "$REPO/playstead-mac" && scripts/ci/run-mac-verification.sh \
    --verify-hosted-run complete \
    --run-record "$EVIDENCE/final-hosted-run.json" \
    --run-view "$WORK/run-view.json" \
    --manifest "$manifest" )

step "promote the proven UAT checkpoints"
python3 "$TOOLS/apply-task3-documentation.py" \
  --run-id "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["databaseId"])' "$WORK/run-view.json")" \
  --sha "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["headSha"])' "$WORK/run-view.json")" \
  --run-url "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$WORK/run-view.json")" \
  --uat "$REPO/.planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md" \
  --roadmap "$REPO/.planning/ROADMAP.md"

step "validate the mutated canonical documents"
( cd "$REPO/playstead-mac" && python3 scripts/ci/validate-phase-3-uat-evidence.py \
    --uat "$REPO/.planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md" \
    --roadmap "$REPO/.planning/ROADMAP.md" )

step "TASK 3 COMPLETE -- review the diff, then commit"
git -C "$REPO" --no-pager diff --stat
