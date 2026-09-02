#!/usr/bin/env python3
"""Build final-hosted-run.json from a `gh run view --json ...` document.

Emits exactly the record shape run-mac-verification.sh's
`--verify-hosted-run complete --run-record` validator enforces: schema_version 1,
the five identity fields it cross-checks against both the run view and the
downloaded evidence manifest, completion/conclusion, the run URL, and the three
required job conclusions keyed as test / compose-smoke / mac-verification.

    make_run_record.py --run-view VIEW.json --out final-hosted-run.json
"""

import argparse
import json
import pathlib
import re
import sys

JOB_KEYS = {
    "mix precommit (unit + LiveView + browser + integration)": "test",
    "docker compose cold start": "compose-smoke",
    "macOS 26 unit + rendering + UI + live server": "mac-verification",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-view", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    view = json.loads(pathlib.Path(args.run_view).read_text(encoding="utf-8"))

    head_sha = str(view.get("headSha", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", head_sha):
        raise SystemExit(f"head SHA is malformed: {head_sha!r}")
    if view.get("workflow") not in (None, "ci") and view.get("workflowName") != "ci":
        raise SystemExit("workflow must be ci")
    if view.get("event") not in {"push", "pull_request"}:
        raise SystemExit(f"event must be push or pull_request, got {view.get('event')!r}")
    if view.get("status") != "completed" or view.get("conclusion") != "success":
        raise SystemExit(
            f"run is not completed successfully: status={view.get('status')!r} "
            f"conclusion={view.get('conclusion')!r}"
        )

    jobs = {}
    for job in view.get("jobs") or []:
        key = JOB_KEYS.get(job.get("name"))
        if key is None:
            continue
        if key in jobs:
            raise SystemExit(f"duplicate hosted job: {job.get('name')}")
        if job.get("status") != "completed" or job.get("conclusion") != "success":
            raise SystemExit(f"required hosted job did not pass: {job.get('name')}")
        jobs[key] = "success"
    missing = set(JOB_KEYS.values()) - set(jobs)
    if missing:
        raise SystemExit(f"required hosted jobs absent from run view: {sorted(missing)}")

    record = {
        "schema_version": 1,
        "run_id": view["databaseId"],
        "workflow": view["workflowName"],
        "event": view["event"],
        "head_branch": view["headBranch"],
        "head_sha": head_sha,
        "status": view["status"],
        "conclusion": view["conclusion"],
        "url": view["url"],
        "jobs": jobs,
    }
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {out} for run {record['run_id']} at {head_sha[:7]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
