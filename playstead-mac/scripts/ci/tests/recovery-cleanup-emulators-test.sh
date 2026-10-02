#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(uname -s)" = Darwin ] || { printf '%s\n' 'SKIP: emulator cleanup is macOS-only'; exit 0; }
test_root="$(mktemp -d "${TMPDIR:-/tmp}/playstead-cleanup-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
cat "$SCRIPT_DIR/../recovery-cleanup-emulators.swift" >"$test_root/check.swift"
cat >>"$test_root/check.swift" <<'SWIFT'

let testRoot = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
let executable = testRoot.appendingPathComponent("profile/emulators/mGBA.app/Contents/MacOS/mGBA")
try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data().write(to: executable)
assert(ownedEmulatorExecutable(executable, root: testRoot))
assert(!ownedEmulatorExecutable(executable, root: testRoot.appendingPathComponent("different")))
let sibling = testRoot.appendingPathComponent("profile/emulators-other/mGBA.app/Contents/MacOS/mGBA")
try FileManager.default.createDirectory(at: sibling.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data().write(to: sibling)
assert(!ownedEmulatorExecutable(sibling, root: testRoot))
let absent = executable.deletingLastPathComponent().appendingPathComponent("absent")
assert(!ownedEmulatorExecutable(absent, root: testRoot))
let alias = testRoot.appendingPathComponent("profile/emulators/alias.app")
try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
assert(!ownedEmulatorExecutable(alias.appendingPathComponent("Contents/MacOS/mGBA"), root: testRoot))
print("PASS: recovery emulator cleanup ownership checks")
SWIFT
/usr/bin/xcrun swift -warnings-as-errors -D CLEANUP_TESTING \
  -module-cache-path "$test_root/module-cache" "$test_root/check.swift" "$test_root"
/usr/bin/xcrun swiftc -typecheck -warnings-as-errors \
  -module-cache-path "$test_root/module-cache" "$SCRIPT_DIR/../recovery-cleanup-emulators.swift"
python3 - "$SCRIPT_DIR/../recovery-e2e.sh" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
cleanup=source.split('cleanup_recovery_e2e() {',1)[1].split('trap cleanup_recovery_e2e EXIT',1)[0]
assert cleanup.index('cleanup_owned_recovery_emulators') < cleanup.index('rm -rf "$private_root"')
assert 'RECOVERY_CLEANUP outcome=blocked' in cleanup
assert 'return' in cleanup
print('PASS: emulator cleanup precedes profile deletion')
PY
