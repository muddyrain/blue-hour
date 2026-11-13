"""Drive M46 on an isolated Windows desktop with path-bound synthetic profiles."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import shutil
from statistics import median
import subprocess
import sys
import time

from m41_event_flow import ROOT, input_desktop_name, isolated_env, read_json
from windows_test_process import DesktopProcess


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run(args, output, phase, profile, script, *, resume=False, more=(), open_streets=True):
    log_path = output / f"{phase}.txt"
    command = [args.godot, "--path", str(args.project), "--audio-driver", "Dummy",
               "--rendering-method", "gl_compatibility"]
    if args.headless:
        command.append("--headless")
    command += ["--script", f"res://tests/{script}", "--"]
    if open_streets:
        command.append("--bh-open-streets")
    command += [f"--flow-output={(output / phase).as_posix()}", f"--bh-rescue-seed={args.seed}", *more]
    if resume:
        command.append("--flow-resume")
    start = time.monotonic()
    desktops = set()
    with log_path.open("xb") as log:
        if args.headless:
            code = subprocess.run(command, cwd=args.project, env=isolated_env(profile),
                                  stdout=log, stderr=log, timeout=args.timeout).returncode
        else:
            process = DesktopProcess(command, args.project, isolated_env(profile), log, log)
            try:
                while process.poll() is None:
                    desktop = input_desktop_name()
                    desktops.add(desktop)
                    if desktop and desktop.casefold() == process.name.casefold():
                        raise RuntimeError("Validation desktop became the input desktop")
                    if time.monotonic() - start > args.timeout:
                        raise TimeoutError(f"{phase} exceeded {args.timeout} seconds. See {log_path}")
                    time.sleep(0.1)
            finally:
                if process.poll() is None:
                    process.kill()
                code = process.wait()
    console = log_path.read_text(encoding="utf-8", errors="replace")
    if code != 0 or re.search(r"(?m)^(SCRIPT ERROR|ERROR):", console):
        raise RuntimeError(f"{phase} failed ({code}). See {log_path}\n{console[-3500:]}")
    report = read_json(output / phase / "report.json")
    if report["failures"]:
        raise RuntimeError(f"{phase} reported {report['failures']} failed checks")
    result = {"phase": phase, "pid": report["pid"], "checks": len(report["checks"]),
              "wall_seconds": round(time.monotonic() - start, 3)}
    if not args.headless:
        result.update(validation_desktop=process.name, input_desktops=sorted(filter(None, desktops)),
                      validation_window_focused=report["root_focused"])
    print(result, flush=True)
    return result


def timing(args, output):
    script = install_driver(args.project, "m46_menu_timing.gd")
    if args.phase == "cancel-wait":
        phase = run(args, output, "cancel-wait", output / "profile-cancel-wait", script,
                    more=("--flow-menu-cancel",))
        return {"phases": [phase], "cancel_wait": read_json(output / "cancel-wait/cancel-wait.json")}
    phase_path = output / "phases.json"
    phases = []
    if args.phase != "summarize":
        for index in range(1, 4):
            phase = f"cold-{index}"
            phases.append(run(args, output, phase, output / f"profile-{index}", script))
            save_json(phase_path, phases)
    elif phase_path.exists():
        phases = read_json(phase_path)
    samples = [read_json(output / f"cold-{index}" / "menu-timing.json") for index in range(1, 4)]
    assert len({sample["pid"] for sample in samples}) == 3
    def route_identity(sample):
        # A fresh root has a new run ID in the signed descriptor.
        return [{key: value for key, value in row.items() if key != "signature"}
                for row in sample["candidates"]]

    assert all(route_identity(sample) == route_identity(samples[0]) for sample in samples)
    return {"phases": phases, "samples": samples,
            "median_cold_ms": {key: median(sample["cold"][key] for sample in samples)
                               for key in ("feedback_ms", "cards_ms", "max_frame_ms")}}


def install_driver(project, script):
    if project == ROOT:
        return script
    source = ROOT / "tests" / script
    target = project / "tests" / script
    if target.exists() and source.read_bytes() != target.read_bytes():
        digest = sha256(source.read_bytes()).hexdigest()[:12]
        target = target.with_stem(f"{target.stem}_{digest}")
    if not target.exists():
        shutil.copyfile(source, target)
    return target.name



def campaign(args, output):
    script = "m46_campaign_flow.gd"
    profile = output / "profile"
    phase_path = output / "phases.json"
    phases = read_json(phase_path) if phase_path.exists() else []
    sequence = ("setup", "route-a", "b-prepare", "b-extended", "b-quick", "b-resume")
    selected = sequence
    if args.phase == "summarize":
        selected = ()
    elif args.phase:
        selected = (args.phase,)
    for phase in selected:
        if (output / f"{phase}.txt").exists():
            raise RuntimeError(f"Preserve existing output for {phase} before retrying")
        if phase not in ("setup", "b-resume"):
            checkpoint = output / ("confirmed-camp" if phase in ("route-a", "b-prepare") else "rifle-camp")
            assert checkpoint.is_dir(), f"Missing checkpoint: {checkpoint}"
            # The receipt binds to this exact absolute directory. Restore only the
            # synthetic fixture and retain every branch's original bytes.
            if profile.exists():
                profile.rename(output / f"archived-before-{phase}")
            shutil.copytree(checkpoint, profile)
        phases.append(run(args, output, phase, profile, script, resume=phase != "setup"))
        save_json(phase_path, phases)
        if phase in ("setup", "b-prepare"):
            shutil.copytree(profile, output / ("confirmed-camp" if phase == "setup" else "rifle-camp"))
    if args.phase and args.phase != "summarize":
        return {"phases": phases, "diagnostic_phase": args.phase}
    results = [read_json(output / phase / "route.json") for phase in ("route-a", "b-resume")]
    assert results[0]["starting_camp"] == results[1]["starting_camp"]
    rifles = [read_json(output / phase / "rifle-measurement.json") for phase in ("b-extended", "b-resume")]
    assert rifles[0]["initial"]["instance_id"] == rifles[1]["initial"]["instance_id"]
    return {"phases": phases, "results": results, "rifles": rifles}


def main():
    if sys.platform != "win32" or sys.flags.optimize:
        raise RuntimeError("Windows and enabled Python assertions required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("timing", "campaign"))
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--seed", default="m38-wave-01")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--headless", action="store_true", help="Campaign diagnostic without native evidence")
    campaign_phases = ("setup", "route-a", "b-prepare", "b-extended", "b-quick", "b-resume", "summarize")
    parser.add_argument("--phase", choices=campaign_phases + ("cancel-wait",),
                        help="Run a single retained campaign stage or summarize existing results")
    args = parser.parse_args()
    output = args.output.resolve()
    args.project = args.project.resolve()
    if not output.is_relative_to(ROOT / ".local"):
        raise RuntimeError("Use a new output directory under the project .local directory")
    if args.project != ROOT and (args.mode == "campaign" or not args.project.is_relative_to(ROOT / ".local")):
        raise RuntimeError("Only timing can use an archived baseline under .local")
    if args.mode == "timing" and args.headless:
        raise RuntimeError("Timing requires rendered Windows frames")
    if args.mode == "timing" and args.phase not in (None, "summarize", "cancel-wait"):
        raise RuntimeError("Choose fresh timing, summarize, or cancel-wait")
    if args.phase == "cancel-wait" and args.project != ROOT:
        raise RuntimeError("The cancel-wait proof requires the M46 waiting UI")
    if args.phase and args.mode == "campaign" and args.phase not in campaign_phases:
        raise RuntimeError("Choose a retained campaign phase")
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    assert version == (args.project / ".godot-version").read_text().strip()
    output.mkdir(parents=True, exist_ok=args.phase is not None)
    runner = {"timing": timing, "campaign": campaign}[args.mode]
    result = runner(args, output)
    result.update(engine=version, project=str(args.project), renderer="gl_compatibility", seed=args.seed,
                  open_streets=True, native=not args.headless, physical_input="NOT_VERIFIED")
    save_json(output / "summary.json", result)


if __name__ == "__main__":
    main()
