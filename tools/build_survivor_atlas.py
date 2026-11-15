"""Register imagegen character sheets on the existing 256px / 0.22 field scale.

Only slices, removes near-transparent noise and resamples; never synthesizes poses.
Input: five 8x8 sheets plus one 8x4 southwest correction (gu/xia/lin/shen).
"""
import argparse
import hashlib
import json
import statistics
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
IDS = ("gu", "xia", "lin", "shen", "lu")
DIRECTIONS = ("e", "se", "s", "sw", "w", "nw", "n", "ne")


def cell(image, row, col, rows=8):
    return image.crop((round(col * image.width / 8), round(row * image.height / rows),
                       round((col + 1) * image.width / 8), round((row + 1) * image.height / rows)))


def load(path):
    image = Image.open(path).convert("RGBA")
    # imagegen exports harmless RGB noise at alpha 1-4. Clear before filtering.
    image.putalpha(image.getchannel("A").point(lambda a: 0 if a < 12 else a))
    return image


def build(inputs, southwest, output):
    output.mkdir(parents=True, exist_ok=True)
    correction = load(southwest)
    manifest = {"cell": [256, 256], "root": [128, 224], "grid": [8, 8],
                "directions": list(DIRECTIONS), "display_scale": 0.22,
                "clips": {"idle": [0], "walk": [1, 2, 3, 4], "attack": [5, 6, 7]},
                "walk_fps": 8.0, "attack_seconds": 0.24, "characters": {}}
    for variant, (name, path) in enumerate(zip(IDS, inputs)):
        source = load(path)
        original = load(ROOT / "assets/m5_anim_01" / (name + "_full.png"))
        heights = []
        # Match the old full-body artwork height, not its transparent cell size.
        for col in range(5):
            bounds = original.crop((col * 256, 0, (col + 1) * 256, 256)).getbbox()
            heights.append(bounds[3] - bounds[1])
        target_height = statistics.median(heights)
        idle_heights = [cell(source, row, 0).getbbox()[3] - cell(source, row, 0).getbbox()[1]
                        for row in range(8)]
        common_scale = target_height / statistics.median(idle_heights)
        atlas = Image.new("RGBA", (2048, 2048))
        registrations = []
        for row in range(8):
            corrected = row == 3 and variant < 4
            frames = [cell(correction, variant, col, 4) if corrected else cell(source, row, col)
                      for col in range(8)]
            idle = frames[0].getbbox()
            scale = target_height / (idle[3] - idle[1]) if corrected else common_scale
            # One authored root for the entire directional strip. Never recenter
            # individual punches or raised feet: that would erase the animation.
            root = ((idle[0] + idle[2]) / 2, idle[3])
            registrations.append({"direction": DIRECTIONS[row], "source_root": list(root),
                                  "scale": scale, "southwest_correction": corrected})
            for col, frame in enumerate(frames):
                resized = frame.resize((round(frame.width * scale), round(frame.height * scale)),
                                       Image.Resampling.LANCZOS)
                registered = Image.new("RGBA", (256, 256))
                registered.alpha_composite(resized, (round(128 - root[0] * scale),
                                                     round(224 - root[1] * scale)))
                bounds = registered.getbbox()
                assert bounds and min(bounds[:2]) > 0 and max(bounds[2:]) < 256, (name, row, col, bounds)
                atlas.alpha_composite(registered, (col * 256, row * 256))
        dest = output / (name + ".png")
        atlas.save(dest, optimize=True)
        manifest["characters"][name] = {"sheet": dest.name, "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                         "target_idle_height": target_height, "registration": registrations}
    manifest["southwest_source_sha256"] = hashlib.sha256(southwest.read_bytes()).hexdigest()
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BH_SURVIVOR_ATLAS built 5 sheets / 320 drawn frames")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs=5, type=Path, metavar="PNG")
    parser.add_argument("--southwest", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/survivors_v1")
    args = parser.parse_args()
    build(args.sources, args.southwest, args.output)
