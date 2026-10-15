"""Compile the shipped process-readiness check with controlled observations."""
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "playstead-mac/PlaysteadUITests/GBGBCSaveContinuityTests.swift"


class PinnedProcessReadinessTests(unittest.TestCase):
    def test_missing_or_partial_process_identity_never_finishes_the_wait(self):
        text = SOURCE.read_text()
        start = text.index("    private func pinnedApplicationPID(")
        end = text.index("\n    private func currentProcessPath(", start)
        function = text[start:end]
        program = r'''
import Foundation
import Darwin
final class XCUIElement {
    var exists = true
    var value: Any? = "42"
}
final class Observation {
    var path: String? = "/managed/mgba"
    var digest: String? = "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640"
    var registered: [Int32] = [42]
}
let observation = Observation()
let managedPinnedExecutableURL = URL(fileURLWithPath: "/managed/mgba")
func currentProcessPath(pid: pid_t) -> String? { observation.path }
func sha256Hex(at url: URL) -> String? { observation.digest }
struct NSRunningApplication {
    let processIdentifier: Int32
    static func runningApplications(withBundleIdentifier id: String) -> [Self] {
        precondition(id == "com.endrift.mgba-qt")
        return observation.registered.map { Self(processIdentifier: $0) }
    }
}
''' + function + r'''
let readout = XCUIElement()
precondition(pinnedApplicationPID(from: readout) == 42)
readout.exists = false
precondition(pinnedApplicationPID(from: readout) == nil)
readout.exists = true
for value: Any? in [nil, "idle", "exited", "0", "1", "-1", "2147483648", 42] {
    readout.value = value
    precondition(pinnedApplicationPID(from: readout) == nil)
}
readout.value = "42"
observation.path = nil
precondition(pinnedApplicationPID(from: readout) == nil)
observation.path = "/other/mgba"
precondition(pinnedApplicationPID(from: readout) == nil)
observation.path = "/managed/mgba"
observation.digest = "wrong-digest"
precondition(pinnedApplicationPID(from: readout) == nil)
observation.digest = "f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640"
observation.registered = []
precondition(pinnedApplicationPID(from: readout) == nil)
observation.registered = [43]
precondition(pinnedApplicationPID(from: readout) == nil)
observation.registered = [42]
precondition(pinnedApplicationPID(from: readout) == 42)
print("complete pinned process identity: 16 positive/negative observations passed")
'''
        with tempfile.TemporaryDirectory(prefix="playstead-pid-readiness-") as temporary:
            root = pathlib.Path(temporary)
            source, binary = root / "Probe.swift", root / "probe"
            source.write_text(program)
            built = subprocess.run([
                "xcrun", "swiftc", "-module-cache-path", str(root / "modules"),
                str(source), "-o", str(binary),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertIn("observations passed", run.stdout)
        self.assertEqual(text.count("pinnedApplicationPID(from: processReadout) != nil"), 2)
        self.assertEqual(text.count("pinnedApplicationPID(from: targetProcessReadout) != nil"), 1)


if __name__ == "__main__":
    unittest.main()
