#!/usr/bin/env bash
set -euo pipefail

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "TRACKED_TEXT_HYGIENE_ERROR: repository root unavailable" >&2
  exit 2
fi

is_allowed_synthetic_token() {
  case "$1" in
    '/Users/...') # Synthetic redaction example in planning documentation.
      return 0 ;;
    '/Users/owner') # Synthetic account token in an isolated path-validation example.
      return 0 ;;
    '/Users/owner/game.gba') # Synthetic game path in a recovery trust test.
      return 0 ;;
    '/Users/runner/work/...') # Hosted-runner path in a documented CI example.
      return 0 ;;
    '/Users/private/game.rom') # Synthetic private path in an accessibility test fixture.
      return 0 ;;
    '/Users/private') # Synthetic directory prefix in verifier test examples.
      return 0 ;;
    '/Users/private/Secret.swift') # Synthetic compiler diagnostic in verifier tests.
      return 0 ;;
    '/Users/private/SurfaceAccessibilityTests.swift') # Synthetic source path in verifier tests.
      return 0 ;;
    '/Users/private/token') # Synthetic token path used to verify log redaction.
      return 0 ;;
    '/Users/private/game.gba') # Synthetic game path used to verify log redaction.
      return 0 ;;
    '/Users/private/path') # Synthetic path value in a layout evidence test.
      return 0 ;;
    '/Users/example/secret/testFailure') # Synthetic failure location in a redaction fixture.
      return 0 ;;
    '/Users/example/Build/Playstead.app') # Synthetic app path in notarization evidence tests.
      return 0 ;;
    '/Users/example/private/location') # Synthetic location in a sanitizer test fixture.
      return 0 ;;
    '/Users/example/private/Secret.swift') # Synthetic compiler diagnostic in a sanitizer fixture.
      return 0 ;;
    '/Users/example/private/testFailure') # Synthetic failure location in a sanitizer fixture.
      return 0 ;;
    '/Users/example/private') # Synthetic home-relative path in sanitizer fixtures.
      return 0 ;;
    '/home/Library') # Synthetic home path prefix in browser trust tests.
      return 0 ;;
    '/home/Library/Keychains') # Synthetic keychain path in browser trust tests.
      return 0 ;;
    '/Users/REPLACE_WITH_YOUR_ACCOUNT/Playstead-First-Adopter/inbox') # Explicit setup placeholder in example env config.
      return 0 ;;
    '/Users/REPLACE_WITH_YOUR_ACCOUNT/Playstead-First-Adopter/exports') # Explicit setup placeholder in example env config.
      return 0 ;;
    '/Users/REPLACE_WITH_YOUR_ACCOUNT/Playstead-First-Adopter/backups') # Explicit setup placeholder in example env config.
      return 0 ;;
    *)
      return 1 ;;
  esac
}

finding_count=0
while IFS= read -r -d '' file; do
  # grep -I skips binary files; grep output is captured and never printed.
  if ! grep -Iq '' "$file" 2>/dev/null; then
    continue
  fi

  matches=$(LC_ALL=C grep -Eo '/(Users|home)/[A-Za-z0-9._-]+(/[A-Za-z0-9._/-]+)*' "$file" 2>/dev/null || true)
  if [ -z "$matches" ]; then
    continue
  fi

  while IFS= read -r token; do
    [ -n "$token" ] || continue
    if ! is_allowed_synthetic_token "$token"; then
      finding_count=$((finding_count + 1))
    fi
  done <<< "$matches"
done < <(git ls-files -z)

if [ "$finding_count" -gt 0 ]; then
  echo "TRACKED_TEXT_HYGIENE_FAILED: HWA-001 findings=$finding_count" >&2
  exit 1
fi

echo "TRACKED_TEXT_HYGIENE_PASSED"
