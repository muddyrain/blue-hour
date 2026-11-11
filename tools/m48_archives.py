"""Build and measure genuine path-bound M48 archive histories on the current platform.

Archive generation uses original registration, damage, death, terminal confirmation,
and replacement transactions. Directed lethal damage is labeled; these are capacity
samples, not complete campaign victories. Outputs remain under the repository .local.
"""

import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "res://tests/m48_archive_flow.gd"


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def restore_retained_source(folder, profile):
    """A failed diagnostic never leaves its deliberately corrupted source in place."""
    metadata = folder / "fault-target.json"
    if not metadata.is_file():
        return
    info = read_json(metadata)
    target, retained = Path(info["target"]), Path(info["retained"])
    if not target.resolve().is_relative_to(profile.resolve()) or target.is_symlink():
        raise RuntimeError("Refusing to restore a source outside this isolated profile")
    if retained.parent.resolve() != folder.resolve() or not retained.is_file():
        raise RuntimeError("Missing exact retained archive source")
    original = retained.read_bytes()
    if sha256(original).hexdigest() != info["sha256"]:
        raise RuntimeError("Retained archive source no longer has its recorded SHA")
    if not target.is_file() or sha256(target.read_bytes()).hexdigest() != info["sha256"]:
        target.write_bytes(original)
        save_json(folder / "runner-restoration.json", {"restored": True, "target": str(target),
                                                       "sha256": sha256(target.read_bytes()).hexdigest()})


def phase(args, output, profile, mode, count):
    label = f"{mode}-{count}" + (f"-{args.label}" if args.label else "")
    folder, log_path = output / label, output / f"{label}.txt"
    if folder.exists() or log_path.exists():
        raise RuntimeError(f"Preserve the previous result and choose a new --label: {label}")
    resume = profile.is_dir()
    if mode != "build" and not resume:
        raise RuntimeError("Measurement and diagnosis require their original generated profile")
    profile.mkdir(parents=True, exist_ok=True)
    # Child-only standard project isolation, matching tools/godot.py. The desktop
    # environment and the ordinary stable player profile are never modified.
    env = dict(os.environ, HOME=str(profile / "home"), APPDATA=str(profile / "user"),
               XDG_DATA_HOME=str(profile / "user"))
    command = [args.godot, "--path", str(ROOT), "--audio-driver", "Dummy",
               "--rendering-method", "gl_compatibility"]
    if args.headless:
        command.append("--headless")
    command += ["--script", SCRIPT, "--", f"--flow-output={folder.as_posix()}",
                f"--bh-rescue-seed={args.seed}", f"--archive-mode={mode}", f"--archive-count={count}"]
    if resume:
        command.append("--flow-resume")
    if not args.headless and sys.platform == "darwin":
        library = args.background_library or output / "mac-background.dylib"
        if not library.is_file():
            subprocess.run(["clang", "-dynamiclib", "-framework", "AppKit", "-o", str(library),
                            str(ROOT / "tools/macos_background.m")], check=True, timeout=60)
        env["DYLD_INSERT_LIBRARIES"] = str(library.resolve())
    sources = [ROOT / "project.godot", ROOT / ".godot-version"]
    sources += sorted((ROOT / "src").rglob("*.gd"))
    sources += sorted((ROOT / "tests").rglob("*.gd"))
    sources += sorted((ROOT / "data").rglob("*.json"))
    fingerprints = {str(path.relative_to(ROOT)): sha256(path.read_bytes()).hexdigest()
                    for path in sources if path.is_file()}
    save_json(output / f"{label}-inputs.json", {"files": fingerprints,
              "sha256": sha256(json.dumps(fingerprints, sort_keys=True).encode()).hexdigest()})
    began = time.monotonic()
    previous = began
    title_interval = None
    with log_path.open("xb") as log:
        if not args.headless and sys.platform == "win32":
            from windows_test_process import DesktopProcess
            process = DesktopProcess(command, ROOT, env, log, log)
        else:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=log)
        try:
            while process.poll() is None:
                now = time.monotonic()
                if title_interval is None and (folder / "startup-ready.json").is_file():
                    title_interval = {"lower_ms": (previous - began) * 1000,
                                      "upper_ms": (now - began) * 1000, "poll_bound_ms": 25}
                if now - began > args.timeout:
                    raise TimeoutError(f"{label} exceeded {args.timeout}s; preserve {log_path}")
                previous = now
                time.sleep(0.025)
        finally:
            if process.poll() is None:
                process.kill()
            code = process.wait()
            restore_retained_source(folder, profile)
    console = log_path.read_text(encoding="utf-8", errors="replace")
    if code or re.search(r"(?m)^(SCRIPT ERROR|ERROR):", console):
        raise RuntimeError(f"{label} failed ({code}); see {log_path}\n{console[-4000:]}")
    report = read_json(folder / "report.json")
    if report["failures"]:
        raise RuntimeError(f"{label} reported {report['failures']} failed checks; see {log_path}")
    result = {"phase": label, "mode": mode, "archive_count": count, "pid": report["pid"],
              "checks": len(report["checks"]), "wall_seconds": time.monotonic() - began,
              "process_launch_to_title_file_detection_ms": title_interval,
              "script_to_first_title_frame_ms": report["startup_to_first_title_frame_ms"],
              "native": not args.headless, "physical_input": "NOT_VERIFIED"}
    save_json(output / f"{label}-process.json", result)
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", default="m38-wave-01")
    parser.add_argument("--phase", choices=("all", "build", "measure", "diagnose"), default="all")
    parser.add_argument("--count", type=int, choices=(0, 5, 20), default=20)
    parser.add_argument("--label", default="", help="A fresh suffix for a preserved retry")
    parser.add_argument("--timeout", type=int, default=3600)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--background-library", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local") or output == ROOT / ".local":
        parser.error("Use a dedicated output directory under this repository .local")
    if args.label and not re.fullmatch(r"[A-Za-z0-9_-]+", args.label):
        parser.error("Use letters, numbers, underscores and hyphens in --label")
    if not args.headless and sys.platform not in ("darwin", "win32"):
        parser.error("Native background validation supports macOS and Windows; choose --headless elsewhere")
    version = subprocess.check_output([args.godot, "--version"], text=True, timeout=15).strip()
    if version != (ROOT / ".godot-version").read_text(encoding="utf-8").strip():
        parser.error("Use the repository's exact pinned Godot")
    if args.phase == "all" and output.exists():
        parser.error("The complete sequence requires a fresh output directory")
    output.mkdir(parents=True, exist_ok=True)
    profile = output / "profile"
    sequence = [(args.phase, args.count)]
    if args.phase == "all":
        sequence = [(mode, count) for count in (0, 5, 20) for mode in ("build", "measure")]
        sequence.append(("diagnose", 20))
    results = []
    for mode, count in sequence:
        results.append(phase(args, output, profile, mode, count))
        save_json(output / "phases.json", results)
    save_json(output / "summary.json", {"phases": results, "engine": version, "seed_argument": args.seed,
                                        "renderer": "gl_compatibility", "native": not args.headless,
                                        "scope": "DIRECTED_ARCHIVE_SCALE_NOT_TWENTY_COMPLETE_CAMPAIGNS"})


if __name__ == "__main__":
    main()
