"""Run P03 verification in a real rendering window with engine-injected inputs."""

import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

from godot import ROOT, engine_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("p03", "m201"), default="p03", help="Native verification scenario")
    parser.add_argument("--source", action="store_true", help="Run source instead of the exported EXE")
    parser.add_argument("--godot", help="Pinned engine executable, for --source")
    parser.add_argument("--record", action="store_true", help="Record native-run.avi with Godot MovieWriter")
    parser.add_argument("--presentation-only", action="store_true", help="Short source art iteration; skips sortie regression")
    parser.add_argument("--output", type=Path, help="New evidence directory; existing directories are rejected")
    args = parser.parse_args()
    if args.suite != "p03" and args.presentation_only:
        parser.error("--presentation-only is specific to the P03 suite")
    try:
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        output = (args.output or ROOT / ".local" / f"p03-{stamp}").resolve()
        executable = engine_path(args.godot) if args.source else str(ROOT / "builds/windows/blue-hour.exe")
        if not Path(executable).is_file():
            raise RuntimeError("Exported EXE missing. Run python tools/godot.py export first.")
        output.mkdir(parents=True, exist_ok=False)
        command = [executable, "--rendering-method", "gl_compatibility"]
        if args.source:
            command += ["--path", str(ROOT)]
        if args.record:
            command += ["--write-movie", str(output / "native-run.avi"), "--fixed-fps", "30", "--disable-vsync"]
        command += ["--", "--verify-" + args.suite + "=" + str(output),
                    "--bh-audio-settings=" + str(output / "audio.json"),
                    "--bh-progress=" + str(output / "progress" / "run.json")]
        if args.presentation_only:
            command += ["--presentation-only"]
        log = output / "run.txt"
        with log.open("w", encoding="utf-8") as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
        plain = re.sub(r"\x1b\[[0-9;]*m", "", log.read_text(encoding="utf-8", errors="replace"))
        report_path = output / "run-report.json"
        report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.is_file() else None
        if result.returncode or re.search(r"(?m)^(?:SCRIPT ERROR|ERROR):", plain) or report is None or report["failures"]:
            raise RuntimeError(f"Native playtest failed (exit {result.returncode}). Inspect {log} and report.")
        print(f"PASS native {args.suite}: behavior={report['behavior_checks']}, capture_saves={len(report['captures'])}; {output}")
        print("Input: engine-injected viewport mouse events and gameplay intents, not desktop input.")
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
