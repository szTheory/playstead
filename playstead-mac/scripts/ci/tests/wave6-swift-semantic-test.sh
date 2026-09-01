#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
app_source="$repo_root/playstead-mac/Playstead/App/PlaysteadApp.swift"
fixture_source="$repo_root/playstead-mac/Playstead/UITesting/DeterministicProfile.swift"
forbidden_optional_sort='\.map\(\\\.sha256\)[[:space:]]*\.sorted\(\)'

# Prove the fail-closed matcher catches the exact semantic regression before
# trusting it against production sources.
if ! printf '%s\n' '.map(\.sha256)' '    .sorted()' | rg -Uq "$forbidden_optional_sort"; then
  echo "wave6 semantic contract failed: optional-digest negative control was not detected" >&2
  exit 1
fi

for source in "$app_source" "$fixture_source"; do
  if rg -Uq "$forbidden_optional_sort" "$source"; then
    echo "wave6 semantic contract failed: optional AssetMember.sha256 values must be compacted before sorting" >&2
    exit 1
  fi
done

compact_count="$({ rg -o 'compactMap\(\\\.sha256\)' "$app_source" "$fixture_source" || true; } | wc -l | tr -d ' ')"
if [[ "$compact_count" -lt 3 ]]; then
  echo "wave6 semantic contract failed: expected all three digest fingerprints to compact optional values" >&2
  exit 1
fi

printf '%s\n' 'wave6 optional-digest semantic contract passed'
