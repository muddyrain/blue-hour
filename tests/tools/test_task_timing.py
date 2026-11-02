"""No engine, production profile or historical evidence access; temporary fake projects only."""
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timedelta, timezone
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import task_timing as timing


class TaskTimingTests(unittest.TestCase):
    def setUp(self):
        self.parent = (ROOT / os.environ.get("BH_TIMING_TEST_TMP", ".local/task-timing-tests")).resolve()
        self.assertTrue(self.parent.is_relative_to((ROOT / ".local").resolve()))
        self.parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="isolated-", dir=self.parent)
        self.project = Path(self.temp.name)
        self.out = self.project / ".local/task-timing/run.json"
        self.clock = datetime(2026, 1, 1, tzinfo=timezone.utc)

    def tearDown(self):
        # Only this new temporary root is removed, never task evidence or real profiles.
        self.assertTrue(Path(self.temp.name).resolve().is_relative_to(self.parent))
        self.assertNotEqual(Path(self.temp.name).resolve(), self.parent)
        self.temp.cleanup()

    def start(self, phase="inspection", second=0):
        return timing.update(self.project, self.out, "TEST-01", phase, now=self.clock + timedelta(seconds=second))

    def stop(self, phase="inspection", second=1, status="pass", reason=""):
        return timing.update(self.project, self.out, "TEST-01", phase, status=status, reason=reason, now=self.clock + timedelta(seconds=second))

    def preserved_rejection(self, operation):
        before = self.out.read_bytes() if self.out.exists() else None
        with self.assertRaises(timing.TimingError):
            operation()
        self.assertEqual(self.out.read_bytes() if self.out.exists() else None, before)

    def test_normal_utc_and_json(self):
        self.start();event = self.stop(second=2.25)
        self.assertEqual(event["elapsed_seconds"], 2.25)
        self.assertEqual(event["started_at"], "2026-01-01T00:00:00.000000Z")
        data = json.loads(self.out.read_text(encoding="utf-8"))
        self.assertEqual(data["events"], [event])
        result = timing.report(self.project, self.out)
        self.assertEqual(result["closed_interval_union_seconds"], 2.25)
        self.assertEqual(result["hidden_reasoning_seconds"], "UNKNOWN")

    def test_duplicate_start_and_stop_preserve_bytes(self):
        self.start();self.preserved_rejection(self.start)
        self.stop();self.preserved_rejection(self.stop)

    def test_stop_without_start(self):
        self.preserved_rejection(self.stop)

    def test_retry_retains_failed_event(self):
        self.start();old = dict(self.stop(status="fail", reason="UNKNOWN"))
        self.start(second=2);self.stop(second=4)
        events = timing.report(self.project, self.out)["events"]
        self.assertEqual(events[0], old)
        self.assertEqual(events[1]["id"], 2)
        self.assertEqual(events[0]["reason"], "UNKNOWN")

    def test_parallel_union_not_sum_and_gaps(self):
        self.start(second=0);self.start("implementation", second=2)
        self.stop(second=10);self.stop("implementation", second=5)
        self.start("media", second=12);self.stop("media", second=14)
        result = timing.report(self.project, self.out)
        self.assertEqual(result["closed_interval_union_seconds"], 12)
        self.assertEqual(result["recorded_span_seconds"], 14)
        self.assertEqual(result["unrecorded_gap_seconds"], 2)
        self.assertEqual(result["total_task_wall_seconds"], "UNKNOWN")

    def test_open_or_missing_time_is_unknown_and_report_readonly(self):
        self.start();before = self.out.read_bytes()
        result = timing.report(self.project, self.out)
        self.assertEqual(result["open_event_ids"], [1])
        self.assertEqual(result["recorded_span_seconds"], "UNKNOWN")
        self.assertEqual(result["unrecorded_gap_seconds"], "UNKNOWN")
        self.assertIsNone(result["events"][0]["elapsed_seconds"])
        self.assertEqual(self.out.read_bytes(), before)

    def test_invalid_phase_task_status_and_reason(self):
        self.start()
        for args in [("bad", "inspection", None, ""), ("TEST-01", "invented", None, ""),
                     ("TEST-01", "inspection", "success", ""), ("TEST-01", "inspection", "fail", "")]:
            task, phase, status, reason = args
            self.preserved_rejection(lambda: timing.update(self.project, self.out, task, phase, status=status, reason=reason))

    def test_task_mismatch(self):
        self.start()
        self.preserved_rejection(lambda: timing.update(self.project, self.out, "OTHER-02", "media"))

    def test_unsafe_paths_rejected_before_user_file_read(self):
        paths = [self.project / "outside.json", self.project / ".local/protected-profile/run.json",
                 self.project / ".local/task-timing/../run.json", self.project / ".local/task-timing/run.txt",
                 self.project.parent / "outside.json"]
        with patch.object(Path, "read_bytes", side_effect=AssertionError("must not read unrelated files")):
            for path in paths:
                with self.subTest(path=path.name), self.assertRaises(timing.TimingError):
                    timing.update(self.project, path, "TEST-01", "inspection")

    def test_existing_non_timing_file_preserved(self):
        self.out.parent.mkdir(parents=True)
        for raw in [b'{"profile":"synthetic"}', b'{bad', b'\xff', b'{"value":NaN}']:
            self.out.write_bytes(raw)
            self.preserved_rejection(self.start)

    def test_damaged_time_or_elapsed_preserved(self):
        self.start();self.stop();original = json.loads(self.out.read_bytes())
        for key, value in [("started_at", "2026-01-01Z"), ("ended_at", None), ("elapsed_seconds", True), ("elapsed_seconds", 99)]:
            data = json.loads(json.dumps(original));data["events"][0][key] = value
            self.out.write_text(json.dumps(data), encoding="utf-8")
            self.preserved_rejection(lambda: self.start("media"))

    def test_backward_clock_preserves_open_event(self):
        self.start(second=5)
        self.preserved_rejection(lambda: self.stop(second=4))
        self.assertEqual(timing.report(self.project, self.out)["recorded_span_seconds"], "UNKNOWN")

    def test_busy_lock_not_removed(self):
        self.start();lock = self.out.with_name(self.out.name + ".lock");lock.write_bytes(b"synthetic owner")
        self.preserved_rejection(self.stop)
        self.assertEqual(lock.read_bytes(), b"synthetic owner")

    def test_replace_error_preserves_completed_history(self):
        self.start();self.stop();before = self.out.read_bytes()
        with patch.object(timing.os, "replace", side_effect=OSError("simulated write failure")), self.assertRaises(OSError):
            self.start("media", second=3)
        self.assertEqual(self.out.read_bytes(), before)
        self.assertFalse(list(self.out.parent.glob(".timing-*")))
        self.assertFalse(self.out.with_name(self.out.name + ".lock").exists())

    def test_new_file_race_does_not_overwrite_competing_file(self):
        def collision(source, destination):
            Path(destination).write_bytes(b"synthetic competing file")
            raise FileExistsError()
        with patch.object(timing.os, "link", side_effect=collision), self.assertRaises(FileExistsError):
            self.start()
        self.assertEqual(self.out.read_bytes(), b"synthetic competing file")

    def test_hardlink_rejected(self):
        self.start();alias = self.out.with_name("alias.json")
        os.link(self.out, alias)
        self.preserved_rejection(self.stop)
        self.assertEqual(alias.read_bytes(), self.out.read_bytes())

    def test_reparse_point_rejected(self):
        self.out.parent.mkdir(parents=True)
        actual = Path.lstat
        class Reparse:
            st_file_attributes = 0x400
            st_nlink = 1
            st_mode = actual(self.out.parent).st_mode
        with patch.object(Path, "lstat", lambda p: Reparse() if p == self.out.parent else actual(p)):
            with self.assertRaisesRegex(timing.TimingError, "reparse"):
                timing.output_path(self.project, self.out)

    def test_private_reason_rejected(self):
        self.start()
        for reason in ["C:/synthetic/private", "person@example.invalid", "token ghp_example", "line\nbreak"]:
            self.preserved_rejection(lambda: self.stop(status="fail", reason=reason))

    def test_cli_interface_and_invalid_phase(self):
        relative = self.out.relative_to(self.project).as_posix()
        with patch.object(timing, "ROOT", self.project), redirect_stdout(io.StringIO()) as stream:
            self.assertEqual(timing.main(["start", "--task", "TEST-01", "--phase", "inspection", "--out", relative]), 0)
            self.assertEqual(json.loads(stream.getvalue())["status"], "running")
        with patch.object(timing, "ROOT", self.project), redirect_stderr(io.StringIO()):
            self.assertEqual(timing.main(["stop", "--task", "TEST-01", "--phase", "inspection", "--status", "fail", "--out", relative]), 2)
            with self.assertRaises(SystemExit) as result:
                timing.main(["start", "--task", "TEST-01", "--phase", "invalid", "--out", relative])
            self.assertEqual(result.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
