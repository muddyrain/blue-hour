"""Validate the M42 same-camp branches and independent history on Windows."""
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys

from m41_event_flow import ROOT, read_json, run_phase


SCRIPT = "res://tests/m42_recon_flow.gd"


def png_size(path):
    header = path.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(path)
    return list(struct.unpack(">II", header[16:24]))


def main():
    if sys.platform != "win32" or sys.flags.optimize:
        raise RuntimeError("Windows and enabled Python assertions required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seed", default="m42-recon-28")
    parser.add_argument("--headless", action="store_true", help="Diagnostic mode without screenshot evidence")
    parser.add_argument("--core-only", action="store_true", help="Skip separate directed history and hound fixtures")
    args = parser.parse_args()
    engine = subprocess.check_output([args.godot, "--version"], text=True).strip()
    assert engine == (ROOT / ".godot-version").read_text().strip()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT / ".local")
    out.mkdir(parents=True, exist_ok=False)
    profile = out / "profile"
    profile.mkdir()
    phases = []

    def run(phase, *, resume=True):
        phases.append(run_phase(args.godot, out, phase, profile, args.seed,
                                resume=resume, native=not args.headless, script=SCRIPT))

    def restore(snapshot, label):
        # Binding, ACK and journal live at the same absolute profile path.
        profile.rename(out / ("archived-" + label))
        shutil.copytree(out / snapshot, profile)

    run("setup", resume=False)
    shutil.copytree(profile, out / "confirmed-camp")
    run("a")
    restore("confirmed-camp", "a")
    run("b-first")
    shutil.copytree(profile, out / "claimed-source")
    run("b-work")
    run("b-finish")
    a = read_json(out / "a/route-result.json")
    b = read_json(out / "b-finish/route-result.json")
    common = ("seed", "day", "camp", "action", "map", "primary", "optional", "recon_point", "direct", "via")
    assert all(a[key] == b[key] for key in common)
    assert a["recon_progress"] == 0.0 and b["recon_progress"] == 6.0 and a["receipt"] != b["receipt"]
    assert a["viewport"] == b["viewport"] == [1280, 720]
    checkpoints = []
    for source, resumed in (("b-first", "b-work"), ("b-work", "b-finish")):
        saved = read_json(out / source / "recon-checkpoint.json")
        restored = read_json(out / resumed / "recon-restored.json")
        assert saved["pid"] != restored["resume_pid"] and saved["fingerprint"] == restored["fingerprint"]
        checkpoints.append({"saved": saved, "restored": restored})
    if not args.core_only:
        restore("claimed-source", "b")
        run("t4-history")
        run("t4-postdeath")
        run("t4-readback")
        restore("confirmed-camp", "history")
        run("t4-fault")
        restore("confirmed-camp", "fault")
        run("hound")
    screenshots = []
    if not args.headless:
        for phase, name, expected in (("a", "recon-before", [1024, 640]), ("b-work", "recon-after", [1280, 720])):
            evidence = read_json(out / phase / (name + ".json"))
            path = out / phase / (name + ".png")
            assert png_size(path) == evidence["viewport"] == expected
            screenshots.append({"file":path.relative_to(out).as_posix(), **evidence})
    result = {"engine":engine, "platform":"Windows", "renderer":"gl_compatibility",
              "native_background":not args.headless, "viewport_input":True, "physical_input":"NOT_VERIFIED",
              "seed_argument":args.seed, "phases":phases, "checkpoints":checkpoints, "screenshots":screenshots,
              "a":a, "b":b}
    (out / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
