"""Verify the integrated normal game in a real window; isolated audio preferences."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from godot import ROOT, engine_path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", action="store_true")
parser.add_argument("--stage", choices=("b", "full", "restart", "inputs"), default="full")
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--size", default="1280x720")
parser.add_argument("--record", action="store_true")
parser.add_argument("--settings-file", type=Path)
parser.add_argument("--expected-values", type=Path)
args = parser.parse_args()
output = args.output.resolve()
output.relative_to((ROOT / ".local").resolve())
output.mkdir(parents=True, exist_ok=False)
exe = engine_path(None) if args.source else str(ROOT / "builds/windows/blue-hour.exe")
def binding():
    paths = [ROOT / name for name in ("project.godot", "export_presets.cfg", ".godot-version")]
    extensions = {".gd", ".uid", ".tscn", ".tres", ".gdshader", ".png", ".wav", ".import", ".json"}
    paths += [p for base in ("src", "assets") for p in (ROOT / base).rglob("*")
              if p.is_file() and p.suffix in extensions and "__pycache__" not in p.parts]
    if not args.source:
        paths += [Path(exe), Path(exe).with_suffix(".pck")]
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
before = binding()
command = [exe, "--rendering-method", "gl_compatibility", "--resolution", args.size,
           "--log-file", str(output / "engine.log")]
if args.source:
    command += ["--path", str(ROOT)]
if args.record:
    command += ["--write-movie", str(output / "native-run.avi"), "--fixed-fps", "30", "--disable-vsync"]
command += ["--", "--verify-m202=" + str(output), "--m202-stage=" + args.stage,
            "--bh-audio-settings=" + str((args.settings_file or output / "audio-settings.json").resolve()),
            "--bh-progress=" + str(output / "progress" / "run.json")]
if args.expected_values:
    command += ["--m202-expected=" + str(args.expected_values.resolve())]
(output / "command.json").write_text(json.dumps(command, indent=2), encoding="utf-8")
with (output / "run.txt").open("w", encoding="utf-8") as log:
    run = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=240)
after = binding()
(output / "run-binding.json").write_text(json.dumps({"before":before,"after":after,"unchanged":before==after},indent=2)+"\n",encoding="utf-8")
if before != after:
    raise SystemExit("FAIL: runtime inputs or binaries changed during native validation")
plain = re.sub(r"\x1b\[[0-9;]*m", "", (output / "run.txt").read_text(encoding="utf-8"))
report = json.loads((output / "run-report.json").read_text(encoding="utf-8")) if (output / "run-report.json").exists() else None
if run.returncode or re.search(r"(?m)^(?:SCRIPT ERROR|ERROR|WARNING):", plain) or report is None or report["failures"]:
    raise SystemExit(f"FAIL native integration exit={run.returncode}; inspect {output}")
print(f"PASS native {args.stage} behavior={report['behavior_checks']} captures={report['capture_checks']} driver={report['audio_driver']}; {output}")
