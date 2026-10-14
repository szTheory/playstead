#!/usr/bin/env python3
"""Fail-closed validator for the sanitized ordinary macOS CI artifact."""
import argparse
import fnmatch
import json
import pathlib
import sys

LAYERS = ("unit", "rendering", "ui", "live-server")
HID_TEST = "PlaysteadUITests.ControllerHardwareIntegrationTests/testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch"


def validate(view, evidence, changed_files=()):
    if not isinstance(view, dict) or not isinstance(evidence, dict):
        raise ValueError("run and evidence must be JSON objects")
    if evidence.get("schema_version") != 1 or evidence.get("lane") != "ordinary_macos_no_hid":
        raise ValueError("ordinary evidence schema or lane is invalid")
    if evidence.get("source") != "github-hosted" or evidence.get("aggregate_outcome") != "passed":
        raise ValueError("ordinary evidence is not a successful hosted run")
    run = evidence.get("run")
    identity = {
        "run_id": view.get("databaseId"), "workflow": view.get("workflowName"),
        "event": view.get("event"), "head_branch": view.get("headBranch"),
        "head_sha": view.get("headSha"),
    }
    if not isinstance(run, dict) or any(run.get(k) != v for k, v in identity.items()):
        raise ValueError("ordinary evidence does not match the trusted Actions run identity")
    if view.get("workflowName") != "ci" or view.get("status") != "completed" or view.get("conclusion") != "success":
        raise ValueError("producer run is not a completed successful ci workflow")
    if view.get("event") not in ("push", "pull_request"):
        raise ValueError("unsupported producer event")
    expected_jobs = {
        "mix precommit (unit + LiveView + browser + integration)": "test",
        "docker compose cold start": "compose-smoke",
        "macOS ordinary unit + rendering + UI + live server": "mac-verification",
    }
    jobs = view.get("jobs")
    if not isinstance(jobs, list):
        raise ValueError("Actions API job list is absent")
    by_name = {job.get("name"): job for job in jobs if isinstance(job, dict)}
    if len(by_name) != len(jobs):
        raise ValueError("malformed or duplicate Actions API job")
    for name, key in expected_jobs.items():
        job = by_name.get(name)
        if job is None or job.get("status") != "completed":
            raise ValueError(f"missing or incomplete required job: {name}")
        if key != "compose-smoke" and job.get("conclusion") != "success":
            raise ValueError(f"required job did not pass: {name}")
    compose = by_name["docker compose cold start"].get("conclusion")
    compose_evidence = evidence.get("compose")
    infra_patterns = (
        "playstead-server/Dockerfile", "playstead-server/docker-compose.yml",
        "playstead-server/docker-compose.ci.yml", "playstead-server/Caddyfile",
        "playstead-server/mix.lock", "playstead-server/rel/**",
        "playstead-server/config/**", "playstead-server/scripts/**",
        "playstead-server/priv/repo/migrations/**", ".github/workflows/ci.yml",
    )
    compose_required = view.get("event") == "push" or any(
        fnmatch.fnmatch(path, pattern) for path in changed_files for pattern in infra_patterns
    )
    if compose_required and compose != "success":
        raise ValueError("Compose smoke is required for main or infrastructure changes")
    if compose == "success":
        if compose_evidence != "success":
            raise ValueError("executed Compose pass is missing from evidence")
    elif compose == "skipped":
        if view.get("event") == "push" or compose_evidence != "not_run":
            raise ValueError("skipped Compose work cannot be reported as a pass")
    else:
        raise ValueError("Compose job failed or has an unsupported conclusion")
    layers = evidence.get("layers")
    if not isinstance(layers, list) or len(layers) != len(LAYERS) or {x.get("layer") for x in layers if isinstance(x, dict)} != set(LAYERS):
        raise ValueError("all four ordinary Mac layers are required")
    for layer in layers:
        if not isinstance(layer, dict) or type(layer.get("executed_test_count")) is not int or layer["executed_test_count"] <= 0:
            raise ValueError("Mac layer is missing or vacuous")
        if layer.get("failed_test_count") != 0 or layer.get("runner_process_error_count") != 0 or layer.get("audit_issue_count") != 0:
            raise ValueError("Mac layer did not pass")
        tests = layer.get("required_tests")
        if not isinstance(tests, list) or not tests:
            raise ValueError("Mac layer required-test discovery is missing")
        for test in tests:
            if not isinstance(test, dict) or test.get("discovered") is not True or type(test.get("execution_count")) is not int or test["execution_count"] < 1 or test.get("skipped") is not False or test.get("outcome") != "passed":
                raise ValueError("required Mac test was absent, skipped, or failed")
    hid = evidence.get("entitled_gamepad")
    if not isinstance(hid, dict) or hid.get("status") != "blocked/not-configured" or hid.get("gate_passed") is not False or hid.get("test_identifier") != HID_TEST:
        raise ValueError("ordinary CI must retain blocked/not-configured HID status")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-view", type=pathlib.Path)
    parser.add_argument("--manifest", type=pathlib.Path)
    parser.add_argument("--changed-files", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        from copy import deepcopy
        sha = "0123456789abcdef0123456789abcdef01234567"
        view = {"databaseId": 1, "workflowName": "ci", "event": "pull_request", "headBranch": "feature", "headSha": sha, "status": "completed", "conclusion": "success", "jobs": [
            {"name": "mix precommit (unit + LiveView + browser + integration)", "status": "completed", "conclusion": "success"},
            {"name": "docker compose cold start", "status": "completed", "conclusion": "skipped"},
            {"name": "macOS ordinary unit + rendering + UI + live server", "status": "completed", "conclusion": "success"},
        ]}
        layer = lambda name: {"layer": name, "executed_test_count": 1, "failed_test_count": 0, "runner_process_error_count": 0, "audit_issue_count": 0, "required_tests": [{"discovered": True, "execution_count": 1, "skipped": False, "outcome": "passed"}]}
        evidence = {"schema_version": 1, "lane": "ordinary_macos_no_hid", "source": "github-hosted", "aggregate_outcome": "passed", "run": {"run_id": 1, "workflow": "ci", "event": "pull_request", "head_branch": "feature", "head_sha": sha}, "compose": "not_run", "layers": [layer(n) for n in LAYERS], "entitled_gamepad": {"test_identifier": HID_TEST, "status": "blocked/not-configured", "gate_passed": False}}
        validate(view, evidence)
        mutations = []
        bad = deepcopy(evidence); bad["run"]["head_sha"] = "f" * 40; mutations.append((view, bad))
        bad = deepcopy(evidence); bad["layers"][2]["required_tests"] = []; mutations.append((view, bad))
        bad = deepcopy(evidence); bad["layers"].pop(); mutations.append((view, bad))
        bad = deepcopy(evidence); bad["layers"][0]["required_tests"][0]["skipped"] = True; mutations.append((view, bad))
        bad_view = deepcopy(view); bad_view["jobs"][2]["name"] = "macOS renamed"; mutations.append((bad_view, evidence))
        bad = deepcopy(evidence); bad["entitled_gamepad"]["gate_passed"] = True; mutations.append((view, bad))
        bad = deepcopy(evidence); bad["compose"] = "success"; mutations.append((view, bad))
        for candidate_view, candidate in mutations:
            try:
                validate(candidate_view, candidate)
            except ValueError:
                continue
            raise SystemExit("ordinary evidence validator accepted a negative fixture")
        print(f"ordinary hosted evidence validator fixtures passed ({len(mutations)} invalid fixtures rejected)")
        return
    if not args.run_view or not args.manifest:
        parser.error("--run-view and --manifest are required")
    try:
        changed = args.changed_files.read_text().splitlines() if args.changed_files else ()
        validate(json.loads(args.run_view.read_text()), json.loads(args.manifest.read_text()), changed)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"hosted evidence rejected: {exc}")
    print("ordinary hosted evidence matches its completed Actions run")


if __name__ == "__main__":
    main()
