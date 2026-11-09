"""Run the M41 normal-input and directed branches on an isolated Windows desktop."""

import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from windows_test_process import DesktopProcess


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "res://tests/m41_event_flow.gd"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def isolated_env(profile):
    return dict(os.environ, APPDATA=str(profile / "user"), XDG_DATA_HOME=str(profile / "user"))


def input_desktop_name():
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    user32.OpenInputDesktop.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    user32.OpenInputDesktop.restype = wintypes.HANDLE
    user32.GetUserObjectInformationW.argtypes = (
        wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.c_void_p)
    user32.GetUserObjectInformationW.restype = wintypes.BOOL
    user32.CloseDesktop.argtypes = (wintypes.HANDLE,)
    handle = user32.OpenInputDesktop(0, False, 0x0001)  # DESKTOP_READOBJECTS
    if not handle:
        return None
    try:
        name = ctypes.create_unicode_buffer(256)
        if user32.GetUserObjectInformationW(handle, 2, name, ctypes.sizeof(name), None):  # UOI_NAME
            return name.value
        return None
    finally:
        user32.CloseDesktop(handle)


def run_phase(godot, out, phase, profile, seed, *, resume=True, native=True):
    args = [godot, "--path", str(ROOT), "--audio-driver", "Dummy",
            "--rendering-method", "gl_compatibility"]
    if not native:
        args.append("--headless")
    args += ["--script", SCRIPT, "--", "--flow-output=" + (out / phase).as_posix(),
             "--bh-rescue-seed=" + seed]
    if resume:
        args.append("--flow-resume")
    log_path = out / (phase + ".txt")
    began = time.monotonic()
    observed_desktops = set()
    if native:
        observed_desktops.add(input_desktop_name())
    with log_path.open("xb") as log:
        if native:
            proc = DesktopProcess(args, ROOT, isolated_env(profile), log, log)
            try:
                while proc.poll() is None:
                    observed_desktops.add(input_desktop_name())
                    if any(name is not None and name.casefold() == proc.name.casefold() for name in observed_desktops):
                        raise RuntimeError(f"{phase} isolated desktop became the input desktop")
                    if time.monotonic() - began > 240:
                        raise TimeoutError(phase)
                    time.sleep(0.1)
            finally:
                if proc.poll() is None:
                    proc.kill()
                code = proc.wait()
        else:
            code = subprocess.run(args, cwd=ROOT, env=isolated_env(profile), stdout=log,
                                  stderr=log, timeout=240).returncode
    console = log_path.read_text(encoding="utf-8", errors="replace")
    if code or re.search(r"(?m)^(SCRIPT ERROR|ERROR):", console):
        raise RuntimeError(f"{phase} failed ({code})\n{console[-2400:]}")
    report = read_json(out / phase / "report.json")
    if report["failures"]:
        raise RuntimeError(f"{phase} failed checks")
    result = {"phase": phase, "pid": report["pid"], "checks": len(report["checks"]),
              "seconds": round(time.monotonic() - began, 3), "native": native}
    if native:
        result.update(validation_desktop=proc.name, input_desktops=sorted(name for name in observed_desktops if name),
                      input_desktop_query_unavailable=None in observed_desktops,
                      validation_window_focused=report["root_focused"])
    print(result, flush=True)
    return result


def main():
    if sys.platform != "win32" or sys.flags.optimize:
        raise RuntimeError("Windows and enabled Python assertions required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seed", default="m41-event-03")
    parser.add_argument("--headless", action="store_true", help="Diagnostic mode without screenshot evidence")
    parser.add_argument("--old-profile", type=Path, help="Optional M40 run directory containing user and tool-first")
    parser.add_argument("--core-only", action="store_true", help="Diagnostic run of setup and A/B")
    options = parser.parse_args()
    engine = subprocess.check_output([options.godot, "--version"], text=True).strip()
    assert engine == (ROOT / ".godot-version").read_text().strip()
    out = options.output.resolve()
    assert out.is_relative_to(ROOT / ".local")
    out.mkdir(parents=True, exist_ok=False)
    native = not options.headless
    profile = out / "profile"
    profile.mkdir()
    rows = []

    def run(phase, *, resume=True):
        rows.append(run_phase(options.godot, out, phase, profile, options.seed,
                              resume=resume, native=native))

    def branch(phase):
        # Journal identity binds to this same absolute directory. Preserve each run's exact bytes.
        profile.rename(out / ("archived-before-" + phase))
        shutil.copytree(out / "camp-checkpoint", profile)
        run(phase)

    run("setup", resume=False)
    shutil.copytree(profile, out / "camp-checkpoint")
    run("a")
    branch("b-first")
    run("b-resume")
    a = read_json(out / "a/event-result.json")
    b = read_json(out / "b-resume/event-result.json")
    keys = ("seed", "day", "camp_fingerprint", "action", "map", "site", "point")
    assert {key: a[key] for key in keys} == {key: b[key] for key in keys}, (a, b)
    assert a["receipt"] != b["receipt"]
    assert b["pid"] != read_json(out / "b-first/event-checkpoint.json")["pid"]
    if not options.core_only:
        branch("b-unstarted")
        run("b-unstarted-resume")
        branch("early")
        branch("b-capacity")
        branch("failed")
        workshop = out / "workshop"
        workshop.mkdir()
        workshop_profile = workshop / "profile"
        rows.append(run_phase(options.godot, workshop, "tool-first", workshop_profile,
                              "m38-wave-01", resume=False, native=native))
        rows.append(run_phase(options.godot, workshop, "tool-resume", workshop_profile,
                              "m38-wave-01", native=native))
    if options.old_profile:
        old = options.old_profile.resolve()
        assert old.is_relative_to(ROOT / ".local") and (old / "tool-first/tool-checkpoint.json").is_file()
        rows.append(run_phase(options.godot, old, "tool-resume", old, "m38-wave-01",
                              native=native))
    screenshots = sorted(path.relative_to(out).as_posix() for path in out.glob("*/*.png"))
    if native:
        assert screenshots == ["a/return-result.png", "a/station-choice.png", "a/task-card.png"], screenshots
    result = {"engine": engine, "platform": "Windows", "renderer": "gl_compatibility",
              "native_background": native, "viewport_input": True, "physical_input": "NOT_VERIFIED",
              "seed_argument": options.seed, "phases": rows, "screenshots": screenshots, "a": a, "b": b}
    (out / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
