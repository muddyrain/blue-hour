"""Run one M48 proof phase in a project-local disposable profile on macOS."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase")
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, default=ROOT / ".local/m48/runs")
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--script", default="m48_campaign_flow.gd")
    parser.add_argument("--seed", default="m38-wave-01")
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--engine-profiling", action="store_true")
    parser.add_argument("--timeout", type=int, default=900)
    args, extra = parser.parse_known_args()
    output = args.output.resolve()
    profile = (args.profile or output / ("profile-" + args.phase)).resolve()
    retained = [output / args.phase]
    retained += [output / (args.phase + suffix) for suffix in
                 (".log", "-driver.gd", "-inputs.json", "-process.json")]
    if any(path.exists() for path in retained):
        raise RuntimeError("Preserve the previous phase evidence and choose a new phase or output")
    for path in (output, profile):
        assert path.is_relative_to(ROOT / ".local") and path != ROOT / ".local"
    output.mkdir(parents=True, exist_ok=True)
    profile.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, HOME=str(profile / "home"), APPDATA=str(profile / "user"),
               XDG_DATA_HOME=str(profile / "user"))
    if not args.headless and sys.platform == "darwin":
        library = output / "mac-background.dylib"
        if not library.is_file():
            subprocess.run(["clang", "-dynamiclib", "-framework", "AppKit", "-o", str(library),
                            str(ROOT / "tools/macos_background.m")], check=True, timeout=60)
        env["DYLD_INSERT_LIBRARIES"] = str(library)
    command = [args.godot, "--path", str(args.project.resolve()), "--audio-driver", "Dummy",
               "--rendering-method", "gl_compatibility"]
    if args.headless:
        command += ["--headless"]
    if args.engine_profiling:
        command += ["--profiling"]
    command += ["--script", "res://tests/" + args.script, "--",
                "--flow-output=" + str(output / args.phase), "--bh-rescue-seed=" + args.seed]
    if args.resume:
        command.append("--flow-resume")
    command += extra
    project = args.project.resolve()
    source_files = [project / "project.godot", project / ".godot-version"]
    source_files += sorted((project / "src").rglob("*.gd"))
    source_files += sorted((project / "data").rglob("*.json"))
    source_files += sorted((project / "tests").rglob("*.gd"))
    fingerprints = {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in source_files if path.is_file()}
    driver = project / "tests" / args.script
    if driver.is_file():
        fingerprints[str(driver.relative_to(project))] = hashlib.sha256(driver.read_bytes()).hexdigest()
        (output / (args.phase + "-driver.gd")).write_bytes(driver.read_bytes())
    (output / (args.phase + "-inputs.json")).write_text(json.dumps({"files": fingerprints,
        "sha256": hashlib.sha256(json.dumps(fingerprints, sort_keys=True).encode()).hexdigest()}, indent=2) + "\n")
    started_utc = datetime.datetime.now(datetime.timezone.utc).isoformat()
    started = time.monotonic()
    with (output / (args.phase + ".log")).open("xb") as log:
        try:
            result = subprocess.run(command, env=env, cwd=args.project, stdout=log, stderr=log,
                                    timeout=args.timeout)
            exit_code = result.returncode
            timed_out = False
        except subprocess.TimeoutExpired:
            exit_code = -1
            timed_out = True
    console = (output / (args.phase + ".log")).read_text(errors="replace")
    report_path = output / args.phase / "report.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    summary = {"phase": args.phase, "exit": exit_code, "timed_out": timed_out,
               "started_utc": started_utc,
               "finished_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "wall_seconds": time.monotonic() - started, "command": command,
               "native": not args.headless, "pid": report.get("pid"),
               "failures": report.get("failures", "UNKNOWN"),
               "checks": len(report.get("checks", [])),
               "root_focused": report.get("root_focused", "UNKNOWN")}
    (output / (args.phase + "-process.json")).write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False))
    assert exit_code == 0 and report and report["failures"] == 0, console[-4000:]
    assert not re.search(r"(?m)^(SCRIPT ERROR|ERROR):", console), console[-4000:]
    if args.script == "m48_title_flow.gd":
        assert "BH_EXIT requested" in console and exit_code == 0, console[-4000:]


if __name__ == "__main__":
    main()
