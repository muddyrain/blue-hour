"""Run M47 against a disposable path-bound profile on an isolated Windows desktop."""

import argparse
import os
from pathlib import Path
import subprocess

from m46_campaign_flow import ROOT, run, save_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    fault_phases = ("t4-starvation", "t4-abandon", "t7-first", "t7-readback")
    parser.add_argument("phase", choices=("opening-layout", "victory", "reward", "repeat-victory",
                                         "shared-reward", "maps", "cards", "field-before", "field-after",
                                         "wipe", "early-wipe", *fault_phases))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"), required="GODOT_BIN" not in os.environ)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seed", default="m38-wave-01")
    parser.add_argument("--theme", choices=("commercial", "industrial", "residential"))
    parser.add_argument("--size", choices=("small", "medium", "large"))
    parser.add_argument("--headless", action="store_true")
    args = parser.parse_args()
    args.project = ROOT
    args.timeout = 600
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local") or output == ROOT / ".local":
        parser.error("Use a dedicated output directory under the repository .local directory")
    version = subprocess.check_output([args.godot, "--version"], text=True, timeout=15).strip()
    if version != (ROOT / ".godot-version").read_text(encoding="utf-8").strip():
        parser.error("Use the repository's pinned Godot")
    profile = output / "profile"
    resume = args.phase in ("reward", "repeat-victory", "shared-reward", "field-after", "t7-readback")
    if resume != profile.is_dir():
        parser.error("Continuation phases need their original profile; all other phases need fresh output")
    output.mkdir(parents=True, exist_ok=True)
    more = tuple(f"--flow-{key}={value}" for key, value in (("theme", args.theme), ("size", args.size)) if value)
    script = "m47_progress_fault_flow.gd" if args.phase in fault_phases else "m47_run_replay_flow.gd"
    result = run(args, output, args.phase, profile, script,
                 resume=resume, more=more, open_streets=False)
    save_json(output / f"{args.phase}-process.json", {**result, "godot": version, "seed_argument": args.seed,
                                                       "theme_argument": args.theme, "size_argument": args.size,
                                                       "native": not args.headless})


if __name__ == "__main__":
    main()
