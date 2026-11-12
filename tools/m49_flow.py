"""Run one M49 proof phase in a project-local disposable profile on Windows or macOS."""

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
    parser.add_argument("--output", type=Path, default=ROOT / ".local/m49/runs")
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--script", default="m48_campaign_flow.gd")
    parser.add_argument("--seed", default="m38-wave-01")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--engine-profiling", action="store_true")
    parser.add_argument("--expect-safe-exit", action="store_true")
    parser.add_argument("--normal-entry", action="store_true", help="Observe an instrumented default scene instead of loading a flow script")
    parser.add_argument("--timeout", type=int, default=900)
    args, extra = parser.parse_known_args()
    version = subprocess.check_output([args.godot, '--version'], text=True, timeout=15).strip()
    if version != (args.project / '.godot-version').read_text(encoding='utf-8').strip():
        parser.error('Use the project pinned engine')
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
    if not args.normal_entry:
        command += ["--script", "res://tests/" + args.script]
    command += ["--",
                "--flow-output=" + (output / args.phase).as_posix(), "--bh-rescue-seed=" + args.seed]
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
    peak_rss = 0
    observed = {}
    previous_poll = started
    native_pid = None
    cpu_seconds = None
    with (output / (args.phase + ".log")).open("xb") as log:
        try:
            if not args.headless and sys.platform == 'win32':
                from windows_test_process import DesktopProcess
                proc = DesktopProcess(command, args.project, env, log, log)
                import ctypes
                from ctypes import wintypes
                class MemoryCounters(ctypes.Structure):
                    _fields_ = [('cb', wintypes.DWORD), ('faults', wintypes.DWORD)] + [
                        (name, ctypes.c_size_t) for name in ('peak_rss', 'rss', 'peak_paged', 'paged',
                        'peak_nonpaged', 'nonpaged', 'pagefile', 'peak_pagefile')]
                memory_reader = ctypes.WinDLL('psapi').GetProcessMemoryInfo
                memory_reader.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
                kernel = ctypes.WinDLL('kernel32', use_last_error=True)
                kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
                kernel.OpenProcess.restype = wintypes.HANDLE
                kernel.CloseHandle.argtypes = [wintypes.HANDLE]
                native_handle = None
                while proc.poll() is None:
                    now = time.monotonic()
                    if native_handle is None:
                        for marker in ('pid.json', 'startup-feedback.json'):
                            path = output / args.phase / marker
                            if path.is_file():
                                try:
                                    native_pid = int(json.loads(path.read_text(encoding='utf-8'))['pid'])
                                    native_handle = kernel.OpenProcess(0x410, False, native_pid)
                                except (ValueError, KeyError):
                                    pass
                                if native_handle:
                                    break
                    memory = MemoryCounters()
                    memory.cb = ctypes.sizeof(memory)
                    if native_handle and memory_reader(native_handle, ctypes.byref(memory), memory.cb):
                        peak_rss = max(peak_rss, memory.peak_rss)
                    for name in ('startup-feedback.json', 'startup-ready.json'):
                        if name not in observed and (output / args.phase / name).is_file():
                            observed[name] = {'lower_ms': (previous_poll-started)*1000,
                                              'upper_ms': (now-started)*1000,
                                              'scope': 'process creation through file detection, includes PNG/JSON overhead'}
                    previous_poll = now
                    if time.monotonic() - started > args.timeout:
                        proc.kill()
                        proc.wait()
                        raise subprocess.TimeoutExpired(command, args.timeout)
                    time.sleep(0.025)
                exit_code = proc.wait()
                if native_handle:
                    process_times = kernel.GetProcessTimes
                    process_times.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
                    times = [wintypes.FILETIME() for _ in range(4)]
                    if process_times(native_handle, *(ctypes.byref(value) for value in times)):
                        cpu_seconds = sum((value.dwHighDateTime << 32) | value.dwLowDateTime for value in times[2:]) / 10000000
                    kernel.CloseHandle(native_handle)
            else:
                result = subprocess.run(command, env=env, cwd=args.project, stdout=log, stderr=log, timeout=args.timeout)
                exit_code = result.returncode
            timed_out = False
        except subprocess.TimeoutExpired:
            exit_code = -1
            timed_out = True
    console = (output / (args.phase + ".log")).read_text(encoding='utf-8', errors="replace")
    report_path = output / args.phase / "report.json"
    if not report_path.exists():
        reports = list(profile.rglob("report.json"))
        if len(reports) == 1:
            report_path = reports[0]
    report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
    summary = {"phase": args.phase, "exit": exit_code, "timed_out": timed_out,
               "started_utc": started_utc,
               "finished_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "wall_seconds": time.monotonic() - started, "command": command,
               "native": not args.headless, "pid": report.get("pid"),
               "failures": report.get("failures", "UNKNOWN"),
               "checks": len(report.get("checks", [])),
               "root_focused": report.get("root_focused", "UNKNOWN")}
    summary['peak_rss_bytes'] = peak_rss or 'UNKNOWN'
    summary['memory_pid'] = native_pid
    summary['cpu_seconds'] = cpu_seconds if cpu_seconds is not None else 'UNKNOWN'
    summary['process_marker_observations'] = observed
    (output / (args.phase + "-process.json")).write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    if args.expect_safe_exit:
        assert exit_code == 0 and 'BH_EXIT requested safe_boundary' in console, console[-4000:]
        assert (output / args.phase / 'runtime-close-request.json').is_file()
    else:
        assert exit_code == 0 and report and report["failures"] in (0, []), console[-4000:]
    assert not re.search(r"(?m)^(SCRIPT ERROR|ERROR):", console), console[-4000:]
    if args.script == "m48_title_flow.gd":
        assert "BH_EXIT requested" in console and exit_code == 0, console[-4000:]


if __name__ == "__main__":
    main()
