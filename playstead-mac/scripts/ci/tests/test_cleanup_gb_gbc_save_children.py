import importlib.util
import subprocess
import signal
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "cleanup-gb-gbc-save-children.py"
SPEC = importlib.util.spec_from_file_location("cleanup_children", SCRIPT)
CLEANUP = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CLEANUP
SPEC.loader.exec_module(CLEANUP)


class CleanupGBGBCChildrenTests(unittest.TestCase):
    def setUp(self):
        self.executable = Path("/fixture/mGBA.app/Contents/MacOS/mGBA")
        self.profile = Path("/tmp/playstead-gb-save-e2e.abcd/source-profile")

    def test_only_exact_executable_and_profile_are_signalled(self):
        rows = [
            CLEANUP.ProcessRow(101, "start-a", f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb"),
            CLEANUP.ProcessRow(102, "start-b", f"/other/mGBA -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb"),
            CLEANUP.ProcessRow(103, "start-c", f"{self.executable} -C savegamePath={self.profile}/saves/asset-2 {self.profile}/launch/asset-1/game.gb"),
        ]
        identities = {101: str(self.executable), 102: "/other/mGBA", 103: str(self.executable)}
        live = [101]
        calls = []

        def provider():
            return [row for row in rows if row.pid in live]

        def send(pid, sig):
            calls.append((pid, sig))
            live.remove(pid)

        with patch.object(CLEANUP, "pid_path", side_effect=lambda pid: identities.get(pid)):
            result = CLEANUP.cleanup_children(self.executable, self.profile, rows_provider=provider,
                                              signal_sender=send, sleeper=lambda _: None, monotonic=lambda: 0)

        self.assertEqual(calls, [(101, signal.SIGTERM)])
        self.assertEqual(result[0]["pid"], 101)
        self.assertTrue(result[0]["closed"])

    def test_var_and_private_var_profile_aliases_match_exactly(self):
        with tempfile.TemporaryDirectory(prefix="playstead-gb-save-e2e.", dir=tempfile.gettempdir()) as temporary:
            alias = Path(temporary) / "source-profile"
            (alias / "saves" / "asset-1").mkdir(parents=True)
            (alias / "launch" / "asset-1").mkdir(parents=True)
            rom = alias / "launch" / "asset-1" / "game.gb"
            rom.touch()
            command = f"{self.executable} -C savegamePath={alias}/saves/asset-1 {rom}"
            self.assertTrue(CLEANUP.is_exact_launch(command, self.executable, alias.resolve()))

    def test_unquoted_executable_with_spaces_matches_actual_ps_command(self):
        executable = Path("/Users/jon/Library/Application Support/Playstead/emulators/mgba/0.10.5/mGBA.app/Contents/MacOS/mGBA")
        with tempfile.TemporaryDirectory(prefix="playstead-gb-save-e2e.", dir=tempfile.gettempdir()) as temporary:
            profile = Path(temporary) / "source-profile"
            alias = Path(str(profile).replace("/private/var/", "/var/"))
            command = (
                f"{executable} -C savegamePath={alias}/saves/801487f7-2cc5-47ca-a86c-6ae2cec7d11b "
                f"{alias}/launch/801487f7-2cc5-47ca-a86c-6ae2cec7d11b/gb-mbc1-8k.gb"
            )
            self.assertTrue(CLEANUP.is_exact_launch(command, executable, profile))

    def test_missing_profile_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            missing = Path(temporary) / "deleted-profile"
            with self.assertRaisesRegex(ValueError, "private profile directory is missing"):
                CLEANUP.resolve_profile(missing)

    def test_real_disposable_process_receives_term_and_kill_fallback(self):
        for ignore_term, expected in ((False, [signal.SIGTERM]), (True, [signal.SIGTERM, signal.SIGKILL])):
            child = subprocess.Popen(
                ["/usr/bin/python3", "-c", "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"]
                if ignore_term else ["/bin/sleep", "60"]
            )
            try:
                started = "sleep-test-start"
                command = f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb"
                calls = []

                def provider():
                    return [] if child.poll() is not None else [CLEANUP.ProcessRow(child.pid, started, command)]

                def send(pid, sig):
                    calls.append(sig)
                    if ignore_term and sig == signal.SIGTERM:
                        return
                    import os
                    os.kill(pid, sig)

                with patch.object(CLEANUP, "pid_path", return_value=str(self.executable)):
                    result = CLEANUP.cleanup_children(self.executable, self.profile, rows_provider=provider,
                                                      signal_sender=send, sleeper=lambda _: __import__("time").sleep(0.01),
                                                      monotonic=__import__("time").monotonic)
                child.wait(timeout=3)
                self.assertEqual(calls, expected)
                self.assertTrue(result[0]["closed"])
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()

    def test_real_process_vanishing_during_revalidation_is_closed_without_signal(self):
        child = subprocess.Popen(["/bin/sleep", "60"])
        command = f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb"
        calls = []
        snapshots = 0

        def provider():
            nonlocal snapshots
            snapshots += 1
            if snapshots == 1:
                return [CLEANUP.ProcessRow(child.pid, "disposable-start", command)]
            child.terminate()
            child.wait(timeout=3)
            return []

        try:
            with patch.object(CLEANUP, "pid_path", return_value=str(self.executable)):
                result = CLEANUP.cleanup_children(self.executable, self.profile, rows_provider=provider,
                                                  signal_sender=lambda *args: calls.append(args))
            self.assertEqual(calls, [])
            self.assertEqual(result, [{"pid": child.pid, "path": str(self.executable),
                                       "started": "disposable-start", "closed": True}])
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()

    def test_missing_or_changed_process_identity_is_never_signalled(self):
        rows = [
            CLEANUP.ProcessRow(201, "start-a", f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb"),
            CLEANUP.ProcessRow(202, "start-b", f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb"),
        ]
        identities = {201: None, 202: "/changed/mGBA"}
        calls = []
        with patch.object(CLEANUP, "pid_path", side_effect=lambda pid: identities[pid]):
            result = CLEANUP.cleanup_children(self.executable, self.profile, rows_provider=lambda: rows,
                                              signal_sender=lambda *args: calls.append(args))
        self.assertEqual(calls, [])
        self.assertEqual(result, [])

    def test_changed_process_start_time_is_refused_before_term(self):
        first = CLEANUP.ProcessRow(250, "original-start", f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb")
        reused = CLEANUP.ProcessRow(250, "reused-pid-start", first.command)
        snapshots = iter(([first], [reused], [reused]))
        calls = []
        with patch.object(CLEANUP, "pid_path", return_value=str(self.executable)):
            result = CLEANUP.cleanup_children(self.executable, self.profile, rows_provider=lambda: next(snapshots),
                                              signal_sender=lambda *args: calls.append(args))
        self.assertEqual(calls, [])
        self.assertFalse(result[0]["closed"])
        self.assertEqual(result[0]["reason"], "identity_changed_before_term")

    def test_changed_process_identity_after_term_is_not_escalated(self):
        original = CLEANUP.ProcessRow(251, "original-start", f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb")
        changed = CLEANUP.ProcessRow(251, "reused-pid-start", f"{self.executable} -C savegamePath={self.profile}/saves/asset-1 {self.profile}/launch/asset-1/game.gb")
        snapshots = iter(([original], [original], [original], [changed], [changed]))
        calls = []
        with patch.object(CLEANUP, "pid_path", return_value=str(self.executable)):
            result = CLEANUP.cleanup_children(self.executable, self.profile, rows_provider=lambda: next(snapshots),
                                              signal_sender=lambda *args: calls.append(args), monotonic=lambda: 0)
        self.assertEqual(calls, [(251, signal.SIGTERM)])
        self.assertFalse(result[0]["closed"])
        self.assertEqual(result[0]["reason"], "identity_changed_before_kill")

    def test_stale_preflight_requires_tracer_profile_argument(self):
        rows = [
            CLEANUP.ProcessRow(301, "start-a", f"{self.executable} -C savegamePath=/tmp/playstead-gb-save-e2e.r4Nd0m/aerevenadvance/source-profile/saves/asset /tmp/playstead-gb-save-e2e.r4Nd0m/aerevenadvance/source-profile/launch/asset/game.gba"),
            CLEANUP.ProcessRow(302, "start-b", f"{self.executable} /tmp/unrelated/game.gb"),
        ]
        with patch.object(CLEANUP, "pid_path", side_effect=lambda pid: str(self.executable)):
            self.assertEqual(CLEANUP.stale_candidates(rows, self.executable), [301])

    def test_stale_preflight_matches_only_exact_old_task_roots_and_launches(self):
        rows = [
            CLEANUP.ProcessRow(303, "start-a", f"{self.executable} -C savegamePath=/tmp/playstead-gb-save-e2e.r4Nd0m/aerevenadvance/target-profile/saves/asset /tmp/playstead-gb-save-e2e.r4Nd0m/aerevenadvance/target-profile/launch/asset/game.gba"),
            CLEANUP.ProcessRow(304, "start-b", f"{self.executable} -C savegamePath=/tmp/playstead-gb-save-e2e.r4Nd0m-extra/aerevenadvance/target-profile/saves/asset /tmp/playstead-gb-save-e2e.r4Nd0m-extra/aerevenadvance/target-profile/launch/asset/game.gba"),
            CLEANUP.ProcessRow(305, "start-c", f"{self.executable} /tmp/playstead-gb-save-e2e.r4Nd0m/aerevenadvance/target-profile/launch/asset/game.gba"),
            CLEANUP.ProcessRow(306, "start-d", f"/other/mGBA -C savegamePath=/tmp/playstead-gb-save-e2e.r4Nd0m/aerevenadvance/target-profile/saves/asset /tmp/playstead-gb-save-e2e.r4Nd0m/aerevenadvance/target-profile/launch/asset/game.gba"),
        ]
        paths = {row.pid: str(self.executable) if row.pid != 306 else "/other/mGBA" for row in rows}
        with patch.object(CLEANUP, "pid_path", side_effect=lambda pid: paths[pid]):
            self.assertEqual(CLEANUP.stale_candidates(rows, self.executable), [303])

    def test_stale_preflight_covers_both_disposable_profiles(self):
        rows = [
            CLEANUP.ProcessRow(311, "source", f"{self.executable} -C savegamePath=/tmp/playstead-gb-save-e2e.r4Nd0m/gb-mbc1-8k/source-profile/saves/asset /tmp/playstead-gb-save-e2e.r4Nd0m/gb-mbc1-8k/source-profile/launch/asset/game.gb"),
            CLEANUP.ProcessRow(312, "target", f"{self.executable} -C savegamePath=/tmp/playstead-gb-save-e2e.r4Nd0m/gbc-mbc3-rtc/target-profile/saves/asset /tmp/playstead-gb-save-e2e.r4Nd0m/gbc-mbc3-rtc/target-profile/launch/asset/game.gbc"),
        ]
        with patch.object(CLEANUP, "pid_path", side_effect=lambda pid: str(self.executable)):
            self.assertEqual(CLEANUP.stale_candidates(rows, self.executable), [311, 312])


if __name__ == "__main__":
    unittest.main()
