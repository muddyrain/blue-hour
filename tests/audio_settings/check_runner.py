"""Controlled runner regression: no engine or audio process is started."""

import contextlib
import datetime
import importlib.util
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "src/features/audio_settings/b1.py"


class CapturedOutput(io.StringIO):
    def reconfigure(self, **options):
        pass


def main():
    spec = importlib.util.spec_from_file_location("b1_runner_check", ENTRY)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    scratch_root = ROOT / ".local/b1-logs"
    scratch_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="runner-controlled-", dir=scratch_root) as scratch:
        runner.LOGS = Path(scratch)
        output = CapturedOutput()

        def successful_child(command, **options):
            Path(command[command.index("--log-file") + 1]).write_text("controlled log\n", encoding="utf-8")
            return subprocess.CompletedProcess(command, 0, "controlled stdout\n", "")

        with patch.object(runner.subprocess, "run", side_effect=successful_child), contextlib.redirect_stdout(output):
            runner.invoke("simulated-engine", "with-log", ["--headless"])
        assert runner.RESULTS[-1]["passed"] and "PASS with-log" in output.getvalue()
        print("PASS B1 runner: zero exit plus isolated log records success")

        output = CapturedOutput()
        with patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")), contextlib.redirect_stdout(output):
            try:
                runner.invoke("simulated-engine", "missing-log", ["--headless"])
            except RuntimeError as error:
                assert "log" in str(error).lower()
            else:
                raise AssertionError("missing engine log must fail")
        record = runner.RESULTS[-1]
        assert record["passed"] is False, record
        assert "log" in record["failure_reason"].lower(), record
        assert "FAIL missing-log" in output.getvalue() and "PASS missing-log" not in output.getvalue()
        print("PASS B1 runner: missing log records failure with reason and never prints PASS")

        # Execute the real top-level entry. Every subprocess call is intercepted;
        # only the version/help responses are supplied, never an engine process.
        stamp = "top-level-" + Path(scratch).name

        class ControlledTime:
            @classmethod
            def now(cls):
                return cls()

            def strftime(self, format_string):
                return stamp

        def missing_log_child(command, **options):
            if "--version" in command:
                stdout = (ROOT / ".godot-version").read_text(encoding="utf-8").strip() + "\n"
            elif "--help" in command:
                stdout = '--log-file --audio-driver "Dummy" --headless\n'
            else:
                stdout = "controlled zero exit without engine log\n"
            return subprocess.CompletedProcess(command, 0, stdout, "")

        output = CapturedOutput()
        errors = CapturedOutput()
        with patch.object(subprocess, "run", side_effect=missing_log_child), patch.object(datetime, "datetime", ControlledTime), patch.object(sys, "argv", [str(ENTRY), "check", "--godot", sys.executable]), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            try:
                runpy.run_path(str(ENTRY), run_name="__main__")
            except SystemExit as error:
                assert error.code == 1, error.code
            else:
                raise AssertionError("top-level entry must exit 1")
        commands = json.loads((scratch_root / stamp / "commands.json").read_text(encoding="utf-8"))
        assert len(commands) == 1 and commands[0]["passed"] is False
        assert "log" in commands[0]["failure_reason"].lower()
        assert "PASS import" not in output.getvalue() and "FAIL B1:" in errors.getvalue()
        print("PASS B1 runner: real top-level entry exits 1 and persists passed=false under controlled missing-log simulation")


if __name__ == "__main__":
    main()
