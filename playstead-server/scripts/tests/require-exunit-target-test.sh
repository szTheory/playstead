#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$root/scripts/ci/require-exunit-target.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-exunit-guard-test.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
target='test/playstead/sync/snapshot_test.exs'
cat >"$tmp/manifest.tsv" <<'EOF'
# test_file<TAB>exact identity
test/playstead/sync/snapshot_test.exs	Playstead.Sync.SnapshotTest::the default page size is 200 and the between_reads hook is a no-op by default
EOF
cat >"$tmp/bin/mix" <<'EOF'
#!/usr/bin/env bash
set -eu
case "${PLAYSTEAD_TEST_MODE:-pass}" in
  pass)
    cat <<'OUT'
Running ExUnit with seed: 1, max_cases: 1

Playstead.Sync.SnapshotTest [test/playstead/sync/snapshot_test.exs]
  * test the default page size is 200 and the between_reads hook is a no-op by default [L#37]
  * test the default page size is 200 and the between_reads hook is a no-op by default (2.0ms) [L#37]

Finished in 0.0 seconds
5 tests, 0 failures
OUT
    ;;
  absent)
    printf 'Finished in 0.0 seconds\n1 test, 0 failures\n'
    ;;
  zero)
    printf 'Finished in 0.0 seconds\n0 tests, 0 failures\n'
    ;;
  skipped)
    printf 'Playstead.Sync.SnapshotTest [test/playstead/sync/snapshot_test.exs]\n  * test the default page size is 200 and the between_reads hook is a no-op by default [L#37]\n  - test the default page size is 200 and the between_reads hook is a no-op by default (skipped) [L#37]\nFinished in 0.0 seconds\n5 tests, 0 failures, 1 skipped\n'
    ;;
  duplicate)
    printf 'Playstead.Sync.SnapshotTest [test/playstead/sync/snapshot_test.exs]\n  * test the default page size is 200 and the between_reads hook is a no-op by default [L#37]\n  * test the default page size is 200 and the between_reads hook is a no-op by default [L#37]\nFinished in 0.0 seconds\n5 tests, 0 failures\n'
    ;;
  suppress)
    printf 'Playstead.Sync.SnapshotTest [test/playstead/sync/snapshot_test.exs]\n  * test the default page size is 200 and the between_reads hook is a no-op by default (2.0ms) [L#37]\nFinished in 0.0 seconds\n5 tests, 0 failures\n'
    ;;
esac
EOF
chmod +x "$tmp/bin/mix"

run_case() {
  local mode="$1" expected_status="$2"
  set +e
  (cd "$tmp" && PATH="$tmp/bin:$PATH" PLAYSTEAD_EXUNIT_MANIFEST="$tmp/manifest.tsv" \
    PLAYSTEAD_TEST_MODE="$mode" "$runner" "$target" >"$tmp/$mode.out" 2>&1)
  local actual=$?
  set -e
  if [[ "$actual" -ne "$expected_status" ]]; then
    echo "$mode control returned $actual, expected $expected_status" >&2
    cat "$tmp/$mode.out" >&2
    exit 1
  fi
}

run_case pass 0
for mode in absent zero skipped duplicate suppress; do run_case "$mode" 1; done
echo "exact ExUnit guard controls passed (pass plus absent/zero/skip/duplicate/suppressed rejection)"
