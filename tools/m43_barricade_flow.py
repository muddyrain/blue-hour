"""Exercise a real M43 same-camp A/B and receipt boundaries on Windows."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from m41_event_flow import ROOT, read_json, run_phase
from m42_recon_flow import png_size


SCRIPT = "res://tests/m43_barricade_flow.gd"
PHASES = ("setup", "a-save", "a-finish", "b-save", "b-finish", "edges", "readback")


def summarize(out, engine, seed, headless, phases):
    a = read_json(out / "a-finish/route-result.json")
    b = read_json(out / "b-finish/route-result.json")
    common = ("seed", "day", "camp", "action", "action_fingerprint", "map_fingerprint",
              "marker", "site", "site_point", "measurement", "closed_length", "open_length")
    assert all(a[key] == b[key] for key in common), "A/B source identity or measurement differs"
    assert a["trace"]["worker"] == b["trace"]["worker"] and a["trace"]["start"] == b["trace"]["start"]
    assert a["closed_length"] - a["open_length"] >= 320.0
    assert not a["route_open"] and not a["trace"]["crossed"] and not a["support"]["accepted"]
    assert b["route_open"] and b["trace"]["crossed"] and len(b["support"]["accepted"]) == 1
    assert a["receipt"] != b["receipt"] and a["carried"]["food"] == b["carried"]["food"]
    checkpoints = []
    for branch, opened in (("a", False), ("b", True)):
        saved = read_json(out / f"{branch}-save/checkpoint.json")
        restored = read_json(out / f"{branch}-finish/restored.json")
        assert saved["pid"] != restored["pid"] and saved["pid"] == restored["source_pid"]
        assert all(saved[key] == restored[key] for key in ("fingerprint", "open", "support", "elapsed"))
        assert saved["open"] is opened
        assert (saved["support"]["cooldowns"]["airstrike"] > 0) is opened
        checkpoints.append({"branch": branch, "saved": saved, "restored": restored})
    screenshots = []
    if not headless:
        for phase, name, size, opened in (("a-save", "barricade-closed", [1024, 640], False),
                                          ("b-save", "barricade-open", [1280, 720], True)):
            evidence = read_json(out / phase / f"{name}.json")
            shot = out / phase / f"{name}.png"
            assert png_size(shot) == evidence["viewport"] == size and evidence["open"] is opened
            screenshots.append({"file": shot.relative_to(out).as_posix(), **evidence})
    timing = read_json(out / "b-save/opening-timing.json")["samples"]
    assert len(timing) == 4
    result = {"engine": engine, "platform": "Windows", "renderer": "gl_compatibility",
              "native_background": not headless, "viewport_input": True, "physical_input": "NOT_VERIFIED",
              "seed_argument": seed, "phases": phases, "checkpoints": checkpoints,
              "rejections": read_json(out / "readback/readback.json"),
              "edges": read_json(out / "edges/edges.json"), "opening_timing": timing,
              "cold_navigation": read_json(out / "b-save/field-navigation-timing.json"),
              "screenshots": screenshots, "a": a, "b": b}
    (out / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")


def main():
    if sys.platform != "win32" or sys.flags.optimize:
        raise RuntimeError("Windows and enabled Python assertions required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seed", required=True)
    parser.add_argument("--headless", action="store_true", help="Diagnostic mode without screenshot evidence")
    parser.add_argument("--phase", choices=(*PHASES, "summarize"), help="Run one fresh phase in a retained isolated output")
    args = parser.parse_args()
    engine = subprocess.check_output([args.godot, "--version"], text=True).strip()
    assert engine == (ROOT / ".godot-version").read_text().strip()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT / ".local")
    out.mkdir(parents=True, exist_ok=args.phase is not None)
    profile = out / "profile"
    phase_file = out / "phases.json"
    phases = read_json(phase_file) if phase_file.exists() else []

    def run(phase):
        assert not (out / phase).exists(), f"Preserve existing evidence for {phase} before retrying"
        if phase in ("a-save", "b-save", "edges", "a-finish", "b-finish"):
            if phase.endswith("-finish"):
                snapshot = out / (phase[:1] + "-profile")
            else:
                snapshot = out / "confirmed-camp"
            assert snapshot.is_dir(), f"Missing isolated snapshot for {phase}"
            if profile.exists():
                profile.rename(out / ("archived-before-" + phase))
            # Save binding is absolute, so each branch must return to this exact path.
            shutil.copytree(snapshot, profile)
        phases.append(run_phase(args.godot, out, phase, profile, args.seed,
                                resume=phase != "setup", native=not args.headless, script=SCRIPT))
        phase_file.write_text(json.dumps(phases, indent=2), encoding="utf-8")
        if phase == "setup":
            shutil.copytree(profile, out / "confirmed-camp")
        elif phase in ("a-save", "b-save"):
            shutil.copytree(profile, out / (phase[:1] + "-profile"))

    if args.phase is None:
        for phase in PHASES:
            run(phase)
        summarize(out, engine, args.seed, args.headless, phases)
    elif args.phase == "summarize":
        summarize(out, engine, args.seed, args.headless, phases)
    else:
        run(args.phase)


if __name__ == "__main__":
    main()
