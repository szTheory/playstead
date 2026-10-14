#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNNER="$ROOT/scripts/ci/run-mac-verification.sh"
TEST="$ROOT/PlaysteadTests/AdapterTests/MGBAInputBridgeTests.swift"
PRELAUNCH_TEST="$ROOT/PlaysteadTests/AdapterTests/GameRowPrelaunchTests.swift"
HELPER_BUILD="$ROOT/scripts/ci/build-mgba-sdl-input-bridge.sh"
HELPER_SOURCE="$ROOT/scripts/ci/mgba-sdl-input-bridge.c"
GAME_ROW="$ROOT/Playstead/Library/GameRowView.swift"
APP_ENV="$ROOT/Playstead/App/PlaysteadApp.swift"
HOST="$ROOT/Playstead/Adapter/AdapterHost.swift"
RELEASE_SIGN="$ROOT/scripts/sign-and-notarize.sh"

required=(
  testAttestsUniqueAssignedDeviceAndDeliversItsBindingToChild
  testRejectsUnassignedOrMismatchedInputEdges
  testRejectsZeroMultipleOrCompetingSDLDevices
  testInvalidatesAttestationOnGenerationOrAssignmentChange
  testMissingAndStaleAttestationsBlockStandInChildSpawn
  testLaunchCoordinatorResumesOnlyAfterSuccessfulChallengeAndHonorsCancel
  testAttestationIsReusedUntilAssignedControllerSessionInvalidates
  testPrivateConfigIsRemovedWhenVerifiedChildCannotSpawn
  testChangedRemapChangesNumericBindingAndDuplicateIsRejected
  testPrivateConfigHasOwnerOnlyPermissionsAndIsLaunchScoped
  testChallengeRejectsEventsOutsideMonotonicCorrelationWindow
)
prelaunch_required=(
  testCancelDropsPendingLaunch
  testFailedAttestationBlocksPendingLaunch
  testSuccessfulAttestationResumesPendingLaunchOnce
  testSameSessionPlayReusesValidAttestation
)

assert_contract() {
  local runner="$1" test="$2" prelaunch="$3" name
  for name in "${required[@]}"; do
    grep -Fq -- "--required-test PlaysteadTests.MGBAInputBridgeTests/$name" "$runner" || return 1
    grep -Fq -- "func $name" "$test" || return 1
  done
  for name in "${prelaunch_required[@]}"; do
    grep -Fq -- "--required-test PlaysteadTests.GameRowPrelaunchTests/$name" "$runner" || return 1
    grep -Fq -- "func $name" "$prelaunch" || return 1
  done
  ! grep -Fq 'XCTSkip' "$test" || return 1
  ! grep -Fq 'XCTSkip' "$prelaunch" || return 1
  grep -Fq 'run_test_layer unit Unit' "$runner" || return 1
  grep -Fq 'codesign --verify --strict' "$HELPER_BUILD" || return 1
  grep -Fq 'SDL 2.30.7' "$HELPER_BUILD" || return 1
  grep -Fq 'SDL_GetVersion' "$HELPER_SOURCE" || return 1
  grep -Fq 'SDL source commit:' "$HELPER_BUILD" || return 1
  grep -Fq 'SDL-LICENSE.txt' "$HELPER_BUILD" || return 1
  grep -Fq 'Cross (×) / A' "$GAME_ROW" || return 1
  grep -Fq 'L1 (left shoulder)' "$GAME_ROW" || return 1
  grep -Fq 'ControllerChallengeLaunchCoordinator.perform' "$GAME_ROW" || return 1
  grep -Fq 'await play()' "$GAME_ROW" || return 1
  grep -Fq 'controllerChallengeTask?.cancel()' "$GAME_ROW" || return 1
  grep -Fq 'testLaunchCoordinatorResumesOnlyAfterSuccessfulChallengeAndHonorsCancel' "$TEST" || return 1
  grep -Fq 'testAttestationIsReusedUntilAssignedControllerSessionInvalidates' "$TEST" || return 1
  grep -Fq 'currentDevices()' "$APP_ENV" || return 1
  grep -Fq 'currentInputIdentity' "$HOST" || return 1
  grep -Fq 'codesign --verify --deep --strict --verbose=2 "$APP_PATH"' "$RELEASE_SIGN" || return 1
  grep -Fq 'SDL input helper has the wrong runtime version' "$RELEASE_SIGN" || return 1
}

assert_contract "$RUNNER" "$TEST" "$PRELAUNCH_TEST" || { echo 'mGBA input bridge CI/release contract is incomplete' >&2; exit 1; }

# Mutation controls: removing a required CI identifier or making a required
# case skipped must make the contract fail, and the untouched inputs must pass.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$RUNNER" "$tmp/runner.sh"
cp "$TEST" "$tmp/tests.swift"
cp "$PRELAUNCH_TEST" "$tmp/prelaunch.swift"
assert_contract "$tmp/runner.sh" "$tmp/tests.swift" "$tmp/prelaunch.swift" || { echo 'baseline contract unexpectedly failed' >&2; exit 1; }
sed -i '' '/testAttestsUniqueAssignedDeviceAndDeliversItsBindingToChild/d' "$tmp/runner.sh"
if assert_contract "$tmp/runner.sh" "$tmp/tests.swift" "$tmp/prelaunch.swift"; then echo 'deletion mutation was not detected' >&2; exit 1; fi
cp "$RUNNER" "$tmp/runner.sh"
sed -i '' 's/func testPrivateConfigHasOwnerOnlyPermissionsAndIsLaunchScoped()/func testPrivateConfigHasOwnerOnlyPermissionsAndIsLaunchScoped() throws { throw XCTSkip("mutation") }\n    func mutationSentinel()/g' "$tmp/tests.swift"
if assert_contract "$tmp/runner.sh" "$tmp/tests.swift" "$tmp/prelaunch.swift"; then echo 'skip mutation was not detected' >&2; exit 1; fi
python3 -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"testNodes":[]}))' "$tmp/empty-result.json"
if "$RUNNER" --verify-layer-result "$tmp/empty-result.json" unit "$tmp/zero-discovery.json" \
  --required-test PlaysteadTests.MGBAInputBridgeTests/testAttestsUniqueAssignedDeviceAndDeliversItsBindingToChild \
  --required-test PlaysteadTests.MGBAInputBridgeTests/testChallengeRejectsEventsOutsideMonotonicCorrelationWindow \
  --required-test PlaysteadTests.GameRowPrelaunchTests/testCancelDropsPendingLaunch \
  --required-test PlaysteadTests.GameRowPrelaunchTests/testFailedAttestationBlocksPendingLaunch \
  --required-test PlaysteadTests.GameRowPrelaunchTests/testSuccessfulAttestationResumesPendingLaunchOnce \
  --required-test PlaysteadTests.GameRowPrelaunchTests/testSameSessionPlayReusesValidAttestation; then
  echo 'zero-discovery mutation was not detected' >&2
  exit 1
fi
printf '%s\n' 'mGBA input bridge CI/release contract and deletion/skip/zero-discovery controls passed'
