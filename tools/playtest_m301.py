"""One pinned build, three separate native processes, isolated progress and audio."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from godot import ROOT, engine_path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def binding(source):
    paths = [ROOT / name for name in ("project.godot", "export_presets.cfg", ".godot-version")]
    extensions = {".gd", ".uid", ".tscn", ".tres", ".png", ".svg", ".gdshader", ".wav", ".import", ".json"}
    paths += [p for base in ("src", "assets") for p in (ROOT / base).rglob("*")
              if p.is_file() and p.suffix in extensions]
    if not source:
        paths += [ROOT / "builds/windows/blue-hour.exe", ROOT / "builds/windows/blue-hour.pck"]
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", default="1280x720")
    args = parser.parse_args()
    output = args.output.resolve()
    output.relative_to((ROOT / ".local").resolve())
    output.mkdir(parents=True, exist_ok=False)
    exe = engine_path(None) if args.source else str(ROOT / "builds/windows/blue-hour.exe")
    before = binding(args.source)
    progress = output / "progress/run.json"
    settings = output / "audio/audio.json"
    env = os.environ.copy()
    user = output / "user"
    user.mkdir()
    env.update(APPDATA=str(user), XDG_DATA_HOME=str(user))
    runs = []
    expected = None
    for mode in ("first", "second", "reopen"):
        stage = output / mode
        stage.mkdir()
        command = [exe, "--rendering-method", "gl_compatibility", "--resolution", args.size,
                   "--log-file", str(stage / "engine.log")]
        if args.source:
            command += ["--path", str(ROOT)]
        command += ["--", "--verify-m301=" + str(stage), "--m301-mode=" + mode,
                    "--bh-progress=" + str(progress), "--bh-audio-settings=" + str(settings)]
        if expected:
            command += ["--m301-expected=" + str(expected)]
        (stage / "command.json").write_text(json.dumps(command, indent=2), encoding="utf-8")
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        with (stage / "run.txt").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=env)
            try:
                code = process.wait(timeout=240)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                raise
        report_file = stage / "run-report.json"
        report = json.loads(report_file.read_text(encoding="utf-8")) if report_file.exists() else None
        text = re.sub(r"\x1b\[[0-9;]*m", "", (stage / "run.txt").read_text(encoding="utf-8"))
        item = {"mode":mode, "pid":process.pid, "started_utc":started,
                "ended_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "exit_code":code, "report_pid":report.get("pid") if report else None}
        runs.append(item)
        (output / "processes.json").write_text(json.dumps(runs, indent=2), encoding="utf-8")
        pid_mismatch = report is not None and report["pid"] != process.pid and not args.source
        if code or not report or report["failures"] or pid_mismatch or re.search(r"(?m)^(?:SCRIPT ERROR|ERROR|WARNING):", text):
            raise RuntimeError(f"FAIL native {mode}; inspect {stage}")
        for file in (progress, progress.with_suffix(".json.bak"), settings):
            if file.exists():
                shutil.copyfile(file, stage / ("saved-" + file.name if file != settings else "saved-audio.json"))
        expected = stage / "camp.json"
        print(f"PASS native {mode}: launcher_pid={process.pid}, game_pid={report['pid']}, checks={report['checks']}, state={report['state']}", flush=True)
        if binding(args.source) != before:
            raise RuntimeError("Runtime inputs/build changed during validation")
    if len({run["report_pid"] for run in runs}) != 3:
        raise RuntimeError("Native stages did not produce three distinct game process IDs")
    (output / "binding.json").write_text(json.dumps({"inputs":before,"unchanged":binding(args.source)==before}, indent=2), encoding="utf-8")
    print(f"PASS separate process sequence; {output}")


if __name__ == "__main__":
    main()
