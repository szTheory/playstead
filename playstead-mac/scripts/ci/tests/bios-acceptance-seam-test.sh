#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
python3 - "$repo_root" <<'PY'
import json
import pathlib
import plistlib
import re
import sys

root = pathlib.Path(sys.argv[1])
app_path = root / "Playstead/App/PlaysteadApp.swift"
profile_path = root / "Playstead/UITesting/DeterministicProfile.swift"
bootstrap_path = root / "Playstead/UITesting/UITestBootstrap.swift"
ui_tests_path = root / "PlaysteadUITests/BiosAcceptanceSeamTests.swift"
release_tests_path = root / "PlaysteadTests/SnapshotTests/ReleaseHookAbsenceTests.swift"
runner_path = root / "scripts/ci/run-mac-verification.sh"
plan_path = root / "TestPlans/UI.xctestplan"
no_hid_entitlements_path = root / "PlaysteadUITests/PlaysteadUITests.no-hid.entitlements"

app = app_path.read_text()
profile = profile_path.read_text()
bootstrap = bootstrap_path.read_text()
ui_tests = ui_tests_path.read_text()
release_tests = release_tests_path.read_text()
runner = runner_path.read_text()
plan = json.loads(plan_path.read_text())
no_hid_entitlements = plistlib.loads(no_hid_entitlements_path.read_bytes())

positive = "PlaysteadUITests.BiosAcceptanceSeamTests/testFixedSyntheticReferenceAcceptsThroughPackagedAppAndPersistsExactly"
negatives = [
    "PlaysteadUITests.BiosAcceptanceSeamTests/testSameLengthWrongDigestIsRejectedWithoutManagedResidue",
    "PlaysteadUITests.BiosAcceptanceSeamTests/testOneByteShortCandidateIsRejectedWithoutManagedResidue",
    "PlaysteadUITests.BiosAcceptanceSeamTests/testOneByteLongCandidateIsRejectedWithoutManagedResidue",
]
release_tokens = [
    "BiosAcceptanceTestReference",
    "syntheticBIOSCandidateBytes",
    "playstead-test-bios-lab",
    "bios-acceptance",
    "VirtualGamepad",
]

def check_composition(source):
    marker = "private init(\n        paths: AppPaths,\n        openedStore store: LocalStore,"
    start = source.find(marker)
    if start < 0:
        raise AssertionError("AppEnvironment designated composition initializer was not found")
    end = source.find("\n    }", start)
    designated = source[start:end]
    if not re.search(r"biosReferences:\s*\[BiosStore\.Reference\]", designated):
        raise AssertionError("designated initializer must require an explicit BIOS reference set")
    if "self.biosStore = BiosStore(localStore: store, managedDirectory: paths.bios, references: biosReferences)" not in designated:
        raise AssertionError("AppEnvironment no longer forwards the selected reference set to BiosStore")
    if "biosReferences: BiosReferences.production" not in source:
        raise AssertionError("normal production composition no longer selects BiosReferences.production explicitly")

check_composition(app)
if "biosReferences: profile.uiTestingBiosReferences" not in bootstrap:
    raise SystemExit("finite UI profile no longer forwards its compiled reference selection")
if "requiresBiosForAcceptance: profile.requiresBIOSForUITesting" not in bootstrap:
    raise SystemExit("finite acceptance profile no longer exposes the existing BIOS readiness remedy")
if not profile.startswith("#if UI_TESTING"):
    raise SystemExit("synthetic BIOS profile is not compile-gated to UI_TESTING")
for marker in (
    "static let syntheticBIOSCandidateBytes = Data([",
    "SHA256.hash(data: Self.syntheticBIOSCandidateBytes)",
    'system: DeterministicProfile.syntheticBIOSSystem',
    'expectedByteLength: Self.syntheticBIOSCandidateBytes.count',
    'case .biosNoReference:\n            return []',
):
    if marker not in profile:
        raise SystemExit(f"finite test-only BIOS profile drifted: {marker}")

required_ui_methods = [positive.split("/", 1)[1], *[item.split("/", 1)[1] for item in negatives]]
for method in required_ui_methods:
    if f"func {method}()" not in ui_tests:
        raise SystemExit(f"packaged acceptance UI oracle is missing: {method}")
if "BiosAcceptanceSeamTests" not in [
    item for target in plan.get("testTargets", []) for item in target.get("selectedTests", [])
]:
    raise SystemExit("packaged BIOS acceptance suite is not selected by UI.xctestplan")
if 'PLAYSTEAD_UI_TEST_ENTITLEMENTS=PlaysteadUITests/PlaysteadUITests.no-hid.entitlements' not in runner:
    raise SystemExit("focused ordinary UI runs no longer select the target-scoped no-HID entitlements")
if '*ControllerHardwareIntegrationTests*) requires_virtual_hid=true ;;' not in runner:
    raise SystemExit("focused virtual-controller UI runs no longer retain the entitled signing path")
if no_hid_entitlements.get("com.apple.developer.hid.virtual.device"):
    raise SystemExit("ad-hoc no-HID entitlements unexpectedly request Apple's virtual HID entitlement")
if no_hid_entitlements.get("com.apple.security.app-sandbox") is not False:
    raise SystemExit("ad-hoc no-HID UI test runner must remain unsandboxed for its owned fixtures")
for identifier in [positive, *negatives]:
    if f"--required-test {identifier}" not in runner:
        raise SystemExit(f"recurring UI evidence inventory omitted: {identifier}")
for token in release_tokens:
    if f'"{token}"' not in release_tests:
        raise SystemExit(f"Release binary/symbol scan does not reject test-only token: {token}")

# Negative control: the contract must reject a mutant composition root that
# silently substitutes an empty set instead of forwarding the selected set.
mutated_app = app.replace(
    "self.biosStore = BiosStore(localStore: store, managedDirectory: paths.bios, references: biosReferences)",
    "self.biosStore = BiosStore(localStore: store, managedDirectory: paths.bios, references: [])",
    1,
)
try:
    check_composition(mutated_app)
except AssertionError:
    pass
else:
    raise SystemExit("composition mutation was accepted after removing BIOS reference forwarding")

print("BIOS acceptance seam: composition, finite fixture, UI evidence, release tokens, and mutation control passed")
PY
