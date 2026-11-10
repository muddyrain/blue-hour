"""Run M47's native directed effects and cross-process recovery scenarios."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess

from m46_campaign_flow import ROOT, run, save_json


ROUTES = {
    "q-equipped": ("q-equipped",),
    "q-stock": ("q-stock",),
    "support": ("support-win", "radio-before", "radio-after"),
    "firepower": ("firepower-win", "reload-prepare", "reload-baseline", "reload-before", "reload-after"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=tuple(phase for route in ROUTES.values() for phase in route))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"), required="GODOT_BIN" not in os.environ)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seed", default="m38-wave-01")
    args = parser.parse_args()
    args.project = ROOT
    args.timeout = 600
    args.headless = False
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local") or output == ROOT / ".local":
        parser.error("Use a dedicated output directory under the repository .local directory")
    version = subprocess.check_output([args.godot, "--version"], text=True, timeout=15).strip()
    if version != (ROOT / ".godot-version").read_text(encoding="utf-8").strip():
        parser.error("Use the repository's pinned Godot")
    phase = args.phase
    route = next(route for route in ROUTES.values() if phase in route)
    index = route.index(phase)
    profile = output / "profile"
    if (output / f"{phase}.txt").exists() or (index == 0 and output.exists()):
        parser.error("Preserve the original run and select a fresh output directory")
    if index > 0 and (not (output / f"{route[index - 1]}-process.json").is_file() or not profile.is_dir()):
        parser.error("Complete the preceding phase in this same output directory")
    output.mkdir(parents=True, exist_ok=True)
    prepared = output / "prepared-profile"
    if phase == "reload-before":
        # The journal identity includes the absolute path. Keep both branches
        # while testing both configurations from one exact prepared profile.
        profile.rename(output / "baseline-profile")
        shutil.copytree(prepared, profile)
    result = run(args, output, phase, profile, "m47_specialty_effects_flow.gd",
                 resume=index > 0, open_streets=False)
    if phase == "reload-prepare":
        shutil.copytree(profile, prepared)
    save_json(output / f"{phase}-process.json", {**result, "godot": version,
                                                "seed_argument": args.seed, "native": True})


if __name__ == "__main__":
    main()
