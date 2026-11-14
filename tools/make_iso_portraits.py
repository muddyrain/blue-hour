#!/usr/bin/env python3
"""Build 256x256 face close-up portraits from official m5_anim_01 front idle frames."""
from __future__ import annotations
from pathlib import Path
import hashlib
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/m5_anim_01"
OUT = ROOT / "assets/iso/chars"
PREVIEW = Path("/tmp/art_preview/portraits")
PREVIEW.mkdir(parents=True, exist_ok=True)

# Front idle is column 2 (South). Crop windows are hand-tuned so the face
# fills the badge: (left, top, right, bottom) in the 256 frame.
# Tuned to keep signature hair/hats/goggles while making eyes readable at 40px.
CROPS = {
    "gu":  (86, 36, 172, 128),
    "xia": (78, 36, 178, 132),
    "lin": (82, 30, 174, 128),
    "shen": (86, 40, 176, 132),  # skip the long trailing ponytail
    "lu":  (84, 36, 174, 130),
}


def upscale(im: Image.Image, size: int = 256) -> Image.Image:
    # Scale to cover, then center-crop / pad to exact square.
    w, h = im.size
    scale = size / max(w, h)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    # If we want the crop to fill the square, scale to the smaller side? No:
    # we want the cropped bust to fill 256 as much as possible, so scale to
    # cover the square (scale by max? wait: to fit inside, scale by min).
    # Fit inside 256 with a little margin already in the crop.
    scaled = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(scaled, ((size - nw) // 2, (size - nh) // 2), scaled)
    # Mild sharpen after downsample/upscale so eyes stay crisp at HUD size.
    sharp = canvas.filter(ImageFilter.UnsharpMask(radius=1.15, percent=90, threshold=2))
    # Keep original alpha (unsharp can fray edges slightly)
    a = canvas.split()[-1]
    sharp.putalpha(a)
    return sharp


def build(key: str) -> Image.Image:
    sheet = Image.open(SRC / f"{key}_full.png")
    frame = sheet.crop((2 * 256, 0, 3 * 256, 256))
    box = CROPS[key]
    crop = frame.crop(box)
    portrait = upscale(crop, 256)
    return portrait


def main():
    strip = Image.new("RGBA", (256 * 5, 256 + 48), (28, 30, 36, 255))
    hud = Image.new("RGBA", (48 * 5 + 16, 56), (20, 24, 30, 255))
    for i, key in enumerate(("gu", "xia", "lin", "shen", "lu")):
        img = build(key)
        dest = OUT / f"{key}_portrait.png"
        img.save(dest, "PNG")
        img.save(PREVIEW / f"{key}_portrait.png")
        small = img.resize((40, 40), Image.Resampling.LANCZOS)
        small.save(PREVIEW / f"{key}_hud40.png")
        strip.paste(img, (i * 256, 0), img)
        hud.paste(small, (8 + i * 48, 8), small)
        sha = hashlib.sha256(dest.read_bytes()).hexdigest()
        print(f"{key} {img.size} sha256={sha}")
    strip.save(PREVIEW / "five_portraits.png")
    hud.save(PREVIEW / "five_hud40.png")
    print("wrote", PREVIEW)


if __name__ == "__main__":
    main()
