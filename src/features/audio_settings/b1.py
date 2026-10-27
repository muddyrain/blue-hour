"""B1-only launcher: isolated engine logs/settings, pinned engine, silent checks."""

import argparse
from datetime import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[3]
MODULE = Path(__file__).resolve().parent
LOCAL = ROOT / ".local"
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
LOGS = LOCAL / "b1-logs" / STAMP
RESULTS = []


def shared_tools():
    spec = importlib.util.spec_from_file_location("blue_hour_godot", ROOT / "tools/godot.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def invoke(engine, label, args, timeout=120):
    LOGS.mkdir(parents=True, exist_ok=True)
    engine_log = LOGS / (label + "-engine.log")
    command = [engine, "--path", str(ROOT), "--language", "en", "--audio-driver", "Dummy",
               "--log-file", str(engine_log), *args]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8", timeout=timeout)
    output = result.stdout + result.stderr
    (LOGS / (label + "-stdout.txt")).write_text(output, encoding="utf-8", newline="\n")
    plain = re.sub(r"\x1b\[[0-9;]*m", "", output)
    failures = []
    if result.returncode != 0:
        failures.append(f"Subprocess exited {result.returncode}")
    if re.search(r"(?m)^(?:SCRIPT ERROR|ERROR):", plain):
        failures.append("Godot reported an error")
    if not engine_log.is_file():
        failures.append(f"Missing isolated engine log: {engine_log}")
    good = not failures
    failure_reason = "; ".join(failures)
    RESULTS.append({"label": label, "command": command, "exit_code": result.returncode, "passed": good,
                    "failure_reason": failure_reason,
                    "stdout": str(LOGS / (label + "-stdout.txt")), "engine_log": str(engine_log)})
    print(f"{'PASS' if good else 'FAIL'} {label}: {LOGS / (label + '-stdout.txt')}", flush=True)
    if not good:
        print(plain, flush=True)
        raise RuntimeError(f"{label} failed: {failure_reason}")


def analyze_assets():
    manifest = json.loads((ROOT / "assets/audio/b1/manifest.json").read_text(encoding="utf-8"))
    report = []
    assert len(manifest["assets"]) == 6
    assert manifest["generator_sha256"] == hashlib.sha256((MODULE / "generate_cues.py").read_bytes()).hexdigest()
    for asset in manifest["assets"]:
        path = ROOT / asset["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"]
        with wave.open(str(path), "rb") as sound:
            assert (sound.getnchannels(), sound.getsampwidth(), sound.getframerate()) == (1, 2, 44100)
            samples = struct.unpack("<" + "h" * sound.getnframes(), sound.readframes(sound.getnframes()))
        peak = max(abs(x) for x in samples) / 32768
        dc = sum(samples) / len(samples) / 32768
        assert samples[0] == samples[-1] == 0 and 0 < peak <= .551 and abs(dc) < .01
        assert abs(len(samples) / 44100 - asset["duration_s"]) < .0001
        report.append({"cue": asset["cue"], "peak": peak, "dc": dc, "samples": len(samples),
                       "zero_endpoints": True, "sha256": asset["sha256"]})
    (LOGS / "asset-analysis.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("PASS six WAV hashes, formats, lengths, peak headroom, DC and zero endpoints; listening pending")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "audition"))
    parser.add_argument("--godot", help="Pinned Godot executable (or B's .local/toolchain.json)")
    args = parser.parse_args()
    common = shared_tools()
    engine = common.engine_path(args.godot)
    LOGS.mkdir(parents=True, exist_ok=True)
    help_result = subprocess.run([engine, "--help"], capture_output=True, encoding="utf-8", timeout=15)
    (LOGS / "godot-help.txt").write_text(help_result.stdout, encoding="utf-8")
    if help_result.returncode or not all(token in help_result.stdout for token in ("--log-file", "--audio-driver", '"Dummy"', "--headless")):
        raise RuntimeError("Pinned engine does not advertise required isolation options")
    if args.action == "audition":
        settings = LOCAL / "b1-user-data/audio.json"
        command = [engine, "--path", str(ROOT), "--rendering-method", "gl_compatibility",
                   "--log-file", str(LOGS / "audition-engine.log"),
                   "res://src/features/audio_settings/audition.tscn", "--", f"--b1-settings={settings.as_posix()}"]
        print("Audition (use only during the agreed desktop/listening slot):", flush=True)
        print(subprocess.list2cmdline(command), flush=True)
        return subprocess.run(command, cwd=ROOT).returncode
    try:
        # Run the unchanged shared check flow, adding mandatory process isolation at
        # its invoke boundary. No shared source or project configuration is edited.
        common.invoke = invoke
        sys.argv = [str(ROOT / "tools/godot.py"), "check", "--godot", engine]
        if common.main() != 0:
            raise RuntimeError("Shared Godot check failed")
        analyze_assets()
        test_dir = (LOCAL / "b1-user-data" / ("tests-" + STAMP)).as_posix()
        for mode in ("exercise", "restart"):
            invoke(engine, "audio-" + mode, ["--headless", "--script", "res://tests/audio_settings/check.gd",
                                           "--", f"--b1-test-dir={test_dir}", f"--b1-test-mode={mode}"])
        print("B1 automated checks passed; native window and listening pending.")
        return 0
    finally:
        (LOGS / "commands.json").write_text(json.dumps(RESULTS, indent=2) + "\n", encoding="utf-8")
        print(f"Evidence: {LOGS}", flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    try:
        sys.exit(main())
    except (OSError, ValueError, AssertionError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"FAIL B1: {error}", file=sys.stderr)
        sys.exit(1)
