#!/usr/bin/env bash
# A UI test that shells out to live-server.sh must resolve the runner's
# runtime config, not just the inherited environment.
#
# The fixture runs `mix playstead.mac_ci_fixture`. The XCTest process inherits
# a PATH without the Elixir toolchain, so an inherited-only environment makes
# that call die with "mix: command not found" -- at provision-domain, on every
# hosted run. LiveServerSnapshotTests knew this and merged the runner-written
# live-server-runtime.json (which carries the real PATH) over the inherited
# environment. SaveEndToEndTests declared it reused that discipline "verbatim"
# and did not, so its end-to-end proof never once ran.
#
# It stayed invisible because the test was fail-open: the fixture returned
# false, the test returned without asserting, and XCTest recorded a pass.
# Hosted run 34272794656 is the first run that could name the cause -- and only
# because the fixture's stderr stopped going to /dev/null in the same commit.
#
# This is a seam between two plans, which is precisely the defect no
# behavior-level test owns. It earns a static gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
detector="${SCRIPT_DIR}/live-server-env-detector.py"

python3 "$detector" "${MAC_ROOT}/PlaysteadUITests" || exit 1

fixture="$(mktemp -d "${TMPDIR:-/tmp}/playstead-live-env.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

# Negative control: the exact shape that shipped broken.
cat >"$fixture/BadFixtureTests.swift" <<'SWIFT'
import Foundation
final class BadFixtureTests {
    private func fixtureScriptURL() -> URL {
        URL(fileURLWithPath: #filePath).appendingPathComponent("scripts/ci/live-server.sh")
    }
    private func resolvedFixtureEnvironment() -> [String: String]? {
        ProcessInfo.processInfo.environment
    }
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'live-server env detector accepted an inherited-only environment\n' >&2
  exit 1
fi

# Reading the config but not letting it win is the same bug, one step later.
cat >"$fixture/BadFixtureTests.swift" <<'SWIFT'
import Foundation
final class BadFixtureTests {
    private func fixtureScriptURL() -> URL {
        URL(fileURLWithPath: #filePath).appendingPathComponent("scripts/ci/live-server.sh")
    }
    private func runtimeConfigurationURL() -> URL {
        URL(fileURLWithPath: ".build/ci/four-layer/raw/live-server-runtime.json")
    }
    private func resolvedFixtureEnvironment() -> [String: String]? {
        ProcessInfo.processInfo.environment
    }
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'live-server env detector accepted a config it never merges\n' >&2
  exit 1
fi

# ...and the fixed shape must pass, or the guard is unsatisfiable.
cat >"$fixture/BadFixtureTests.swift" <<'SWIFT'
import Foundation
final class BadFixtureTests {
    private func fixtureScriptURL() -> URL {
        URL(fileURLWithPath: #filePath).appendingPathComponent("scripts/ci/live-server.sh")
    }
    private func runtimeConfigurationURL() -> URL {
        URL(fileURLWithPath: ".build/ci/four-layer/raw/live-server-runtime.json")
    }
    private func resolvedFixtureEnvironment() -> [String: String]? {
        let inherited = ProcessInfo.processInfo.environment
        let configured: [String: String] = [:]
        return inherited.merging(configured) { _, configuredValue in configuredValue }
    }
}
SWIFT
python3 "$detector" "$fixture" >/dev/null || {
  printf 'live-server env detector rejected a correctly resolved environment\n' >&2
  exit 1
}

printf 'live-server fixture environment resolution contract: passed\n'
