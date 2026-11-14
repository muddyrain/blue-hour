#!/usr/bin/env python3
"""Original 2:1 isometric building and prop refinement for Blue Hour.

Hand-authored procedural sprites: tiled hip/gable roofs, eaves, shop fascias,
window frames and signs. Not AI-generated and not a third-party art pack.
"""
from __future__ import annotations

import json
import sys
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

ROOT = Path(__file__).resolve().parents[1] / "assets" / "iso"
SCALE = 2
FONT_DIR = Path("/usr/share/fonts/opentype/noto")
LAST_FOOT = (0.0, 0.0)
LAST_MAP = (0.0, 0.0)
MANIFEST: dict = {"scale": 0.5, "sprites": {}}


def to_view(x: float, y: float) -> tuple[float, float]:
    return (x - y, (x + y) * 0.5)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    n = min(len(c1), len(c2), 3)
    out = tuple(int(lerp(c1[i], c2[i], t)) for i in range(n))
    a1 = c1[3] if len(c1) > 3 else 255
    a2 = c2[3] if len(c2) > 3 else 255
    if len(c1) > 3 or len(c2) > 3:
        return out + (int(lerp(a1, a2, t)),)
    return out


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(round(v))))


def rgb(color, a=255):
    if isinstance(color, str):
        h = color.lstrip("#")
        color = tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))
    if len(color) == 4:
        return color
    return tuple(int(x) for x in color) + (a,)


def shade(color, t):
    if t >= 0:
        return mix(color, (255, 255, 255), t)
    return mix(color, (0, 0, 0), -t)


def font(size: int, jp: bool = False, regular: bool = False):
    name = "NotoSansCJK-Regular.ttc" if regular else "NotoSansCJK-Bold.ttc"
    index = 0 if jp else 2
    try:
        return ImageFont.truetype(str(FONT_DIR / name), size=max(8, int(size)), index=index)
    except Exception:
        return ImageFont.load_default()


def sprite_canvas(w, d, h, pad=20, extra_south=16):
    corners = []
    for x, y in ((-w / 2, 0), (w / 2, 0), (-w / 2, -d), (w / 2, -d)):
        vx, vy = to_view(x, y)
        corners.append((vx, vy + extra_south))
        corners.append((vx, vy - h))
    xs = [c[0] for c in corners] + [0]
    ys = [c[1] for c in corners] + [14]
    minx, maxx = min(xs) - pad, max(xs) + pad
    miny, maxy = min(ys) - pad, max(ys) + pad
    width = int(math.ceil(maxx - minx)) * SCALE
    height = int(math.ceil(maxy - miny)) * SCALE
    origin = (-minx, -miny)

    def vx(mapx, mapy, up=0.0):
        x, y = to_view(mapx, mapy)
        return ((x + origin[0]) * SCALE, (y + origin[1] - up) * SCALE)

    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    foot = vx(0, 0)
    global LAST_FOOT, LAST_MAP
    LAST_FOOT = foot
    LAST_MAP = (w, d)
    return img, vx, foot


def lerp_pt(a, b, t):
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t))


def _inside_mask(size, pts):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask


def fill_masked(img, pts, color):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(pts, fill=rgb(color) if not (isinstance(color, tuple) and len(color) == 4) else color)
    img.alpha_composite(layer)


def edge(img, pts, color, width=1):
    ImageDraw.Draw(img).line(list(pts) + [pts[0]], fill=rgb(color), width=max(1, width), joint="curve")


def blur_shadow(img, pts, alpha=46, radius=5):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon(pts, fill=(0, 0, 0, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(radius * SCALE / 2))
    img.alpha_composite(sh)


def noisy_fill(img, pts, color, amount=0.05, seed=1):
    mask = _inside_mask(img.size, pts)
    bbox = mask.getbbox()
    if not bbox:
        return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(pts, fill=rgb(color))
    if amount <= 0:
        img.alpha_composite(layer)
        return
    grain = Image.new("L", img.size, 0)
    px = grain.load()
    mp = mask.load()
    x0, y0, x1, y1 = bbox
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            if mp[x, y] == 0:
                continue
            n = ((x * 11 + y * 17 + seed * 13) & 255)
            v = 128 + (n - 128) // 3
            px[x, y] = v
            if x + 1 < x1:
                px[x + 1, y] = v
            if y + 1 < y1:
                px[x, y + 1] = v
    # apply brightness
    lp = layer.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            a = lp[x, y][3]
            if a == 0:
                continue
            d = (px[x, y] - 128) / 128.0 * amount
            r, g, b, _ = lp[x, y]
            lp[x, y] = (clamp(r * (1 + d)), clamp(g * (1 + d)), clamp(b * (1 + d)), a)
    img.alpha_composite(layer)


def draw_tiled_quad(img, pts, base, light, dark, courses=8, divisions=10):
    if len(pts) < 3:
        return
    if len(pts) == 3:
        a, b, c = pts
        pts = [a, b, c, c]
    else:
        a, b, c, d = pts[0], pts[1], pts[2], pts[3]
        pts = [a, b, c, d]
    a, b, c, d = pts
    mask = _inside_mask(img.size, pts)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(pts, fill=rgb(base))
    gdr = ImageDraw.Draw(layer)
    steps = max(courses * 2, 8)
    for i in range(steps):
        t0 = i / steps
        t1 = (i + 1) / steps
        col = mix(light, dark, t0 * 0.55 + 0.15)
        gdr.polygon([lerp_pt(a, d, t0), lerp_pt(b, c, t0), lerp_pt(b, c, t1), lerp_pt(a, d, t1)], fill=rgb(col))
    ldr = ImageDraw.Draw(layer)
    n = max(3, courses)
    for i in range(n + 1):
        t = i / n
        col = rgb(mix(dark, (20, 16, 14), 0.25), 140 if i not in (0, n) else 200)
        ldr.line([lerp_pt(a, d, t), lerp_pt(b, c, t)], fill=col, width=1 if i not in (0, n) else 2)
    m = max(3, divisions)
    for i in range(m + 1):
        t = i / m
        ldr.line([lerp_pt(a, b, t), lerp_pt(d, c, t)], fill=rgb(mix(dark, (0, 0, 0), 0.15), 90), width=1)
    layer.putalpha(ImageChops.multiply(layer.split()[3], mask))
    img.alpha_composite(layer)
    edge(img, pts, mix(dark, (0, 0, 0), 0.35), 1)


def draw_scalloped_eave(img, start, end, color, dark, drop=3):
    dr = ImageDraw.Draw(img)
    dist = math.dist(start, end)
    steps = max(4, int(dist / (5 * SCALE)))
    for i in range(steps):
        mid = lerp_pt(start, end, (i + 0.45) / steps)
        r = max(2, int(2.2 * SCALE))
        box = (mid[0] - r, mid[1], mid[0] + r, mid[1] + r + drop * SCALE / 2)
        dr.ellipse(box, fill=rgb(color), outline=rgb(dark, 160))


def ground_shadow(img, vx, w, d):
    blur_shadow(img, [vx(-w / 2 + 6, 10), vx(w / 2 + 12, 10), vx(w / 2 + 12, -d + 6), vx(-w / 2 + 6, -d + 6)], 48, 6)


def wall_quad(vx, x0, y0, x1, y1, z0, z1):
    return [vx(x0, y0, z0), vx(x1, y1, z0), vx(x1, y1, z1), vx(x0, y0, z1)]


def draw_wall(img, vx, x0, y0, x1, y1, z0, z1, color, grain=0.04, seed=2):
    pts = wall_quad(vx, x0, y0, x1, y1, z0, z1)
    noisy_fill(img, pts, color, amount=grain, seed=seed)
    edge(img, pts, shade(color, -0.28), 1)
    return pts


def draw_foundation(img, vx, w, d, height, color):
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, 0, height, shade(color, -0.12), 0.03, 3)
    draw_wall(img, vx, -w / 2, 0, -w / 2, -d, 0, height, shade(color, 0.0), 0.03, 4)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, 0, height, shade(color, -0.22), 0.03, 5)


def draw_window(img, pts, frame, glass, lit=False, mullions=True, sill=True):
    a, b, c, d = pts
    fill_masked(img, pts, frame)

    def inset(t=0.16):
        return [
            lerp_pt(lerp_pt(a, b, t), lerp_pt(d, c, t), t),
            lerp_pt(lerp_pt(a, b, 1 - t), lerp_pt(d, c, 1 - t), t),
            lerp_pt(lerp_pt(a, b, 1 - t), lerp_pt(d, c, 1 - t), 1 - t),
            lerp_pt(lerp_pt(a, b, t), lerp_pt(d, c, t), 1 - t),
        ]

    g = inset(0.16)
    gc = (255, 214, 150) if lit else glass
    fill_masked(img, g, rgb(gc, 230))
    hi = [lerp_pt(g[0], g[1], 0.08), lerp_pt(g[0], g[1], 0.42), lerp_pt(g[3], g[2], 0.28), lerp_pt(g[3], g[2], 0.05)]
    fill_masked(img, hi, rgb((255, 255, 255), 55 if not lit else 90))
    if mullions:
        ImageDraw.Draw(img).line([lerp_pt(g[0], g[1], 0.5), lerp_pt(g[3], g[2], 0.5)], fill=rgb(frame, 220), width=max(1, SCALE))
        ImageDraw.Draw(img).line([lerp_pt(g[0], g[3], 0.5), lerp_pt(g[1], g[2], 0.5)], fill=rgb(frame, 180), width=1)
    edge(img, pts, shade(frame, -0.35), 1)
    if sill:
        ImageDraw.Draw(img).line([lerp_pt(a, b, -0.02), lerp_pt(a, b, 1.02)], fill=rgb(shade(frame, -0.15)), width=max(2, SCALE))


def window_on_south(vx, w, d, x, z, ww, wh):
    return wall_quad(vx, x - ww / 2, 0, x + ww / 2, 0, z, z + wh)


def window_on_west(vx, w, d, y, z, ww, wh):
    return wall_quad(vx, -w / 2, y + ww / 2, -w / 2, y - ww / 2, z, z + wh)


def window_on_east(vx, w, d, y, z, ww, wh):
    return wall_quad(vx, w / 2, y + ww / 2, w / 2, y - ww / 2, z, z + wh)


def draw_door(img, vx, face, w, d, offset, z, width, height, color, style="panel", glass=None):
    if face == "south":
        pts = wall_quad(vx, offset - width / 2, 0, offset + width / 2, 0, z, z + height)
    elif face == "east":
        pts = wall_quad(vx, w / 2, offset + width / 2, w / 2, offset - width / 2, z, z + height)
    else:
        pts = wall_quad(vx, -w / 2, offset + width / 2, -w / 2, offset - width / 2, z, z + height)
    fill_masked(img, pts, color)
    edge(img, pts, shade(color, -0.4), 1)
    a, b, c, dpt = pts
    if style in ("glass", "auto"):
        inset = 0.12
        g = [
            lerp_pt(lerp_pt(a, b, inset), lerp_pt(dpt, c, inset), 0.18),
            lerp_pt(lerp_pt(a, b, 1 - inset), lerp_pt(dpt, c, 1 - inset), 0.18),
            lerp_pt(lerp_pt(a, b, 1 - inset), lerp_pt(dpt, c, 1 - inset), 0.92),
            lerp_pt(lerp_pt(a, b, inset), lerp_pt(dpt, c, inset), 0.92),
        ]
        fill_masked(img, g, rgb(glass or (140, 180, 190), 220))
        ImageDraw.Draw(img).line([lerp_pt(g[0], g[1], 0.5), lerp_pt(g[3], g[2], 0.5)], fill=rgb(shade(color, -0.2)), width=1)
        fill_masked(img, [lerp_pt(g[3], g[2], 0.1), lerp_pt(g[3], g[2], 0.45), lerp_pt(g[0], g[1], 0.35)], rgb((255, 255, 255), 50))
    else:
        for t in (0.22, 0.52, 0.78):
            ImageDraw.Draw(img).line(
                [lerp_pt(lerp_pt(a, b, 0.18), lerp_pt(dpt, c, 0.18), t), lerp_pt(lerp_pt(a, b, 0.82), lerp_pt(dpt, c, 0.82), t)],
                fill=rgb(shade(color, -0.25), 180), width=1,
            )
        hpt = lerp_pt(lerp_pt(a, b, 0.78), lerp_pt(dpt, c, 0.78), 0.48)
        r = max(1, SCALE)
        ImageDraw.Draw(img).ellipse((hpt[0] - r, hpt[1] - r, hpt[0] + r, hpt[1] + r), fill=rgb((210, 190, 120)))
    if face == "south":
        p0, p1 = vx(offset - width / 2 - 4, 6, 0), vx(offset + width / 2 + 4, 6, 0)
        p2, p3 = vx(offset + width / 2 + 2, 0, 0), vx(offset - width / 2 - 2, 0, 0)
        fill_masked(img, [p0, p1, p2, p3], (168, 158, 144))
        edge(img, [p0, p1, p2, p3], (120, 110, 98), 1)
    return pts


def draw_hip_roof(img, vx, w, d, wall_h, rise, roof, over=8, courses=None):
    sw = vx(-w / 2 - over, over, wall_h)
    se = vx(w / 2 + over, over, wall_h)
    nw = vx(-w / 2 - over, -d - over, wall_h)
    ne = vx(w / 2 + over, -d - over, wall_h)
    if w >= d:
        inset = min(d * 0.35, 28) + over * 0.2
        rw = vx(-w / 2 + inset, -d / 2, wall_h + rise)
        re = vx(w / 2 - inset, -d / 2, wall_h + rise)
        axis = "x"
    else:
        inset = min(w * 0.35, 28) + over * 0.2
        rw = vx(0, -inset, wall_h + rise)
        re = vx(0, -d + inset, wall_h + rise)
        axis = "y"
    light, mid, dark, very_dark = shade(roof, 0.28), shade(roof, 0.08), shade(roof, -0.22), shade(roof, -0.38)
    fill_masked(img, [vx(-w / 2, 0, wall_h - 1), vx(w / 2, 0, wall_h - 1), se, sw], shade(roof, -0.45))
    fill_masked(img, [vx(w / 2, 0, wall_h - 1), vx(w / 2, -d, wall_h - 1), ne, se], shade(roof, -0.5))
    if axis == "x":
        n_div = max(6, int((w + over * 2) / 16))
        e_div = max(4, int((d + over * 2) / 16))
        c_long = courses or max(5, int((d / 2 + rise) / 8))
        c_short = courses or max(4, int((w / 4 + rise) / 8))
        draw_tiled_quad(img, [nw, ne, re, rw], shade(roof, -0.05), mid, dark, c_long, n_div)
        draw_tiled_quad(img, [sw, nw, rw], mid, light, shade(roof, -0.1), c_short, e_div)
        draw_tiled_quad(img, [se, ne, re], dark, shade(roof, -0.08), very_dark, c_short, e_div)
        draw_tiled_quad(img, [sw, se, re, rw], mid, light, dark, c_long, n_div)
    else:
        n_div = max(4, int((w + over * 2) / 16))
        e_div = max(6, int((d + over * 2) / 16))
        c_long = courses or max(5, int((w / 2 + rise) / 8))
        c_short = courses or max(4, int((d / 4 + rise) / 8))
        draw_tiled_quad(img, [nw, ne, re], shade(roof, -0.05), mid, dark, c_short, n_div)
        draw_tiled_quad(img, [sw, nw, rw], mid, light, shade(roof, -0.1), c_long, e_div)
        draw_tiled_quad(img, [se, ne, re, rw], dark, shade(roof, -0.08), very_dark, c_long, e_div)
        draw_tiled_quad(img, [sw, se, rw], mid, light, dark, c_short, n_div)
    ImageDraw.Draw(img).line([rw, re], fill=rgb(shade(roof, -0.3)), width=max(3, int(2.5 * SCALE)))
    ImageDraw.Draw(img).line([rw, re], fill=rgb(shade(roof, 0.15), 220), width=max(1, SCALE))
    draw_scalloped_eave(img, sw, se, shade(roof, -0.05), very_dark, drop=2)
    draw_scalloped_eave(img, se, ne, shade(roof, -0.18), very_dark, drop=2)
    return {"sw": sw, "se": se, "nw": nw, "ne": ne, "rw": rw, "re": re}


def draw_gable_roof(img, vx, w, d, wall_h, rise, roof, over=8, axis="x"):
    sw = vx(-w / 2 - over, over, wall_h)
    se = vx(w / 2 + over, over, wall_h)
    nw = vx(-w / 2 - over, -d - over, wall_h)
    ne = vx(w / 2 + over, -d - over, wall_h)
    fill_masked(img, [vx(-w / 2, 0, wall_h - 1), vx(w / 2, 0, wall_h - 1), se, sw], shade(roof, -0.45))
    fill_masked(img, [vx(w / 2, 0, wall_h - 1), vx(w / 2, -d, wall_h - 1), ne, se], shade(roof, -0.5))
    if axis == "x":
        rw = vx(-w / 2 - over, -d / 2, wall_h + rise)
        re = vx(w / 2 + over, -d / 2, wall_h + rise)
        g_w = [vx(-w / 2, 0, wall_h), vx(-w / 2, -d, wall_h), vx(-w / 2, -d / 2, wall_h + rise)]
        g_e = [vx(w / 2, 0, wall_h), vx(w / 2, -d, wall_h), vx(w / 2, -d / 2, wall_h + rise)]
        fill_masked(img, g_w, (236, 226, 210))
        fill_masked(img, g_e, (200, 186, 168))
        edge(img, g_w, (140, 128, 112), 1)
        edge(img, g_e, (120, 108, 94), 1)
        draw_tiled_quad(img, [nw, ne, re, rw], shade(roof, -0.05), shade(roof, 0.15), shade(roof, -0.25), 7, 10)
        draw_tiled_quad(img, [sw, se, re, rw], shade(roof, 0.06), shade(roof, 0.28), shade(roof, -0.18), 7, 10)
    else:
        rw = vx(0, over, wall_h + rise)
        re = vx(0, -d - over, wall_h + rise)
        g_s = [vx(-w / 2, 0, wall_h), vx(w / 2, 0, wall_h), vx(0, 0, wall_h + rise)]
        fill_masked(img, g_s, (236, 226, 210))
        edge(img, g_s, (140, 128, 112), 1)
        draw_tiled_quad(img, [sw, nw, re, rw], shade(roof, 0.1), shade(roof, 0.28), shade(roof, -0.15), 7, 8)
        draw_tiled_quad(img, [se, ne, re, rw], shade(roof, -0.12), shade(roof, 0.0), shade(roof, -0.35), 7, 8)
    ImageDraw.Draw(img).line([rw, re], fill=rgb(shade(roof, -0.3)), width=max(3, int(2.5 * SCALE)))
    ImageDraw.Draw(img).line([rw, re], fill=rgb(shade(roof, 0.18), 220), width=max(1, SCALE))
    draw_scalloped_eave(img, sw, se, shade(roof, -0.05), shade(roof, -0.4), drop=2)
    draw_scalloped_eave(img, se, ne, shade(roof, -0.18), shade(roof, -0.45), drop=2)
    return {"sw": sw, "se": se, "nw": nw, "ne": ne, "rw": rw, "re": re}


def draw_flat_roof(img, vx, w, d, wall_h, roof, over=6, parapet=6):
    sw = vx(-w / 2 - over, over, wall_h)
    se = vx(w / 2 + over, over, wall_h)
    nw = vx(-w / 2 - over, -d - over, wall_h + 3)
    ne = vx(w / 2 + over, -d - over, wall_h + 3)
    fill_masked(img, [vx(-w / 2, 0, wall_h - 1), vx(w / 2, 0, wall_h - 1), se, sw], shade(roof, -0.4))
    fill_masked(img, [vx(w / 2, 0, wall_h - 1), vx(w / 2, -d, wall_h - 1), ne, se], shade(roof, -0.5))
    draw_tiled_quad(img, [sw, se, ne, nw], shade(roof, 0.05), shade(roof, 0.18), shade(roof, -0.18), 6, 8)
    if parapet:
        bands = [
            (-w / 2 - over, over, w / 2 + over, over, shade(roof, 0.05)),
            (w / 2 + over, over, w / 2 + over, -d - over, shade(roof, -0.2)),
            (-w / 2 - over, over, -w / 2 - over, -d - over, shade(roof, 0.12)),
            (-w / 2 - over, -d - over, w / 2 + over, -d - over, shade(roof, -0.05)),
        ]
        for x0, y0, x1, y1, col in bands:
            pts = wall_quad(vx, x0, y0, x1, y1, wall_h, wall_h + parapet)
            fill_masked(img, pts, col)
            edge(img, pts, shade(col, -0.3), 1)
    return {"sw": sw, "se": se, "nw": nw, "ne": ne}


def ac_unit(img, vx, x, y, z, w=16, d=12, h=8):
    sw, se = vx(x - w / 2, y, z), vx(x + w / 2, y, z)
    nw, ne = vx(x - w / 2, y - d, z), vx(x + w / 2, y - d, z)
    up = lambda p: (p[0], p[1] - h * SCALE)
    fill_masked(img, [sw, se, up(se), up(sw)], (168, 172, 176))
    fill_masked(img, [se, ne, up(ne), up(se)], (132, 138, 142))
    fill_masked(img, [up(sw), up(se), up(ne), up(nw)], (190, 194, 198))
    for t in (0.25, 0.5, 0.75):
        p = lerp_pt(sw, se, t)
        ImageDraw.Draw(img).line([(p[0], p[1] - 2 * SCALE), (p[0], p[1] - (h - 2) * SCALE)], fill=rgb((90, 96, 100), 180), width=1)
    edge(img, [up(sw), up(se), up(ne), up(nw)], (100, 104, 108), 1)


def antenna(img, vx, x, y, z, h=22):
    p = vx(x, y, z)
    top = (p[0], p[1] - h * SCALE)
    dr = ImageDraw.Draw(img)
    dr.line([p, top], fill=rgb((70, 72, 74)), width=max(1, SCALE))
    dr.line([(top[0] - 8 * SCALE, top[1] + 4 * SCALE), (top[0] + 8 * SCALE, top[1] + 4 * SCALE)], fill=rgb((70, 72, 74)), width=1)
    dr.line([(top[0] - 6 * SCALE, top[1] + 8 * SCALE), (top[0] + 6 * SCALE, top[1] + 8 * SCALE)], fill=rgb((70, 72, 74)), width=1)


def chimney(img, vx, x, y, z, h=16, color=(140, 92, 78)):
    w, d = 10, 10
    draw_wall(img, vx, x - w / 2, y, x + w / 2, y, z, z + h, shade(color, 0.05), 0.02, 9)
    draw_wall(img, vx, x + w / 2, y, x + w / 2, y - d, z, z + h, shade(color, -0.2), 0.02, 10)
    fill_masked(img, [vx(x - w / 2, y, z + h), vx(x + w / 2, y, z + h), vx(x + w / 2, y - d, z + h), vx(x - w / 2, y - d, z + h)], shade(color, -0.35))
    fill_masked(img, [vx(x - w / 2 - 2, y + 2, z + h + 2), vx(x + w / 2 + 2, y + 2, z + h + 2), vx(x + w / 2 + 2, y - d - 2, z + h + 2), vx(x - w / 2 - 2, y - d - 2, z + h + 2)], shade(color, -0.15))


def planter_box(img, vx, x, y, w=22, d=10, h=8, leaf=True):
    draw_wall(img, vx, x - w / 2, y, x + w / 2, y, 0, h, (140, 92, 70), 0.02, 11)
    draw_wall(img, vx, x + w / 2, y, x + w / 2, y - d, 0, h, (110, 74, 56), 0.02, 12)
    fill_masked(img, [vx(x - w / 2, y, h), vx(x + w / 2, y, h), vx(x + w / 2, y - d, h), vx(x - w / 2, y - d, h)], (72, 96, 64))
    if leaf:
        p = vx(x, y - d / 2, h + 6)
        ImageDraw.Draw(img).ellipse((p[0] - 7 * SCALE, p[1] - 8 * SCALE, p[0] + 7 * SCALE, p[1] + 4 * SCALE), fill=rgb((70, 122, 72)))
        ImageDraw.Draw(img).ellipse((p[0] - 11 * SCALE, p[1] - 4 * SCALE, p[0] - 1 * SCALE, p[1] + 5 * SCALE), fill=rgb((58, 108, 62)))


def fascia_band(img, vx, w, d, z0, z1, south_color, east_color, wrap=True):
    s = wall_quad(vx, -w / 2, 0, w / 2, 0, z0, z1)
    fill_masked(img, s, south_color)
    edge(img, s, shade(south_color[:3], -0.25), 1)
    e = None
    if wrap:
        e = wall_quad(vx, w / 2, 0, w / 2, -d, z0, z1)
        fill_masked(img, e, east_color)
        edge(img, e, shade(east_color[:3], -0.3), 1)
    return s, e


def text_on_quad(img, quad, text, fill, fnt, shadow=True):
    """Affine-map a text strip onto a parallelogram fascia (bl, br, tr, tl)."""
    a, b, c, d = quad
    probe = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    bbox = ImageDraw.Draw(probe).textbbox((0, 0), text, font=fnt)
    tw = max(8, bbox[2] - bbox[0] + 10)
    th = max(8, bbox[3] - bbox[1] + 8)
    strip = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    if shadow:
        sd.text((6, 4), text, font=fnt, fill=rgb((0, 0, 0), 140))
    sd.text((5, 3), text, font=fnt, fill=rgb(fill))
    xs = [p[0] for p in (a, b, c, d)]
    ys = [p[1] for p in (a, b, c, d)]
    minx, maxx = int(math.floor(min(xs))), int(math.ceil(max(xs)))
    miny, maxy = int(math.floor(min(ys))), int(math.ceil(max(ys)))
    # inset slightly so glyphs sit inside the fascia
    a2, b2 = lerp_pt(a, d, 0.18), lerp_pt(b, c, 0.18)
    d2, c2 = lerp_pt(a, d, 0.86), lerp_pt(b, c, 0.86)
    # Keep glyph aspect: only use a centered slice of a wide fascia.
    span = math.hypot(b2[0] - a2[0], b2[1] - a2[1])
    thick = math.hypot(d2[0] - a2[0], d2[1] - a2[1])
    if span > 8 and thick > 4:
        target = min(span * 0.92, max(thick * (tw / max(1, th)) * 1.05, span * 0.28))
        inset = max(0.0, (1.0 - target / span) / 2.0)
        a2, b2 = lerp_pt(a2, b2, inset), lerp_pt(a2, b2, 1.0 - inset)
        d2, c2 = lerp_pt(d2, c2, inset), lerp_pt(d2, c2, 1.0 - inset)
    else:
        a2, b2 = lerp_pt(a2, b2, 0.06), lerp_pt(a2, b2, 0.94)
        d2, c2 = lerp_pt(d2, c2, 0.06), lerp_pt(d2, c2, 0.94)
    ab = (b2[0] - a2[0], b2[1] - a2[1])
    ad = (d2[0] - a2[0], d2[1] - a2[1])
    det = ab[0] * ad[1] - ab[1] * ad[0]
    if abs(det) < 1e-3:
        return
    sp = strip.load()
    dp = img.load()
    sw, sh = strip.size
    for y in range(max(0, miny), min(img.height, maxy)):
        for x in range(max(0, minx), min(img.width, maxx)):
            px, py = x - a2[0], y - a2[1]
            u = (px * ad[1] - py * ad[0]) / det
            v = (ab[0] * py - ab[1] * px) / det
            if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
                continue
            fx = u * (sw - 1)
            fy = (1.0 - v) * (sh - 1)
            x0 = int(math.floor(fx)); y0 = int(math.floor(fy))
            x1 = min(sw - 1, x0 + 1); y1 = min(sh - 1, y0 + 1)
            x0 = max(0, min(sw - 1, x0)); y0 = max(0, min(sh - 1, y0))
            tx, ty = fx - math.floor(fx), fy - math.floor(fy)
            def smp(xx, yy):
                return sp[xx, yy]
            c00, c10, c01, c11 = smp(x0, y0), smp(x1, y0), smp(x0, y1), smp(x1, y1)
            def blerp(i):
                return ((c00[i] * (1 - tx) + c10[i] * tx) * (1 - ty) + (c01[i] * (1 - tx) + c11[i] * tx) * ty)
            sr, sg, sb, al = blerp(0), blerp(1), blerp(2), blerp(3)
            if al < 10:
                continue
            br, bg, bb, ba = dp[x, y]
            t = al / 255.0
            dp[x, y] = (
                int(br * (1 - t) + sr * t),
                int(bg * (1 - t) + sg * t),
                int(bb * (1 - t) + sb * t),
                max(ba, al),
            )


WALL_CREAM, WALL_CREAM_R = (236, 226, 208), (204, 190, 170)
WALL_WHITE, WALL_WHITE_R = (244, 242, 236), (214, 210, 200)
WALL_WARM, WALL_WARM_R = (238, 220, 190), (206, 184, 150)
WALL_GREY, WALL_GREY_R = (226, 222, 216), (192, 186, 178)
WALL_YELLOW, WALL_YELLOW_R = (236, 214, 160), (204, 180, 128)
ROOF_TERRA, ROOF_BROWN, ROOF_DARK = (166, 108, 78), (132, 86, 64), (110, 92, 84)
ROOF_GREY, ROOF_MOSS, ROOF_RED = (126, 122, 118), (106, 112, 86), (152, 78, 66)
WOOD, WOOD_DK, FRAME = (110, 78, 54), (84, 58, 40), (92, 68, 50)
GLASS, GLASS_DK = (118, 154, 166), (86, 122, 136)
STONE, STONE_DK = (166, 160, 150), (128, 122, 112)


def house_body(img, vx, w, d, wall_h, left, right, found=8):
    ground_shadow(img, vx, w, d)
    draw_foundation(img, vx, w, d, found, (150, 142, 130))
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, found, wall_h, mix(left, right, 0.28), 0.045, 21)
    draw_wall(img, vx, -w / 2, 0, -w / 2, -d, found, wall_h, left, 0.04, 22)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, found, wall_h, right, 0.04, 23)
    for x, y, col in ((-w / 2, 0, shade(WOOD, 0.05)), (w / 2, 0, shade(WOOD, -0.1)), (w / 2, -d, shade(WOOD, -0.2)), (-w / 2, -d, shade(WOOD, 0.0))):
        ImageDraw.Draw(img).line([vx(x, y, found), vx(x, y, wall_h)], fill=rgb(col, 200), width=max(1, SCALE))


def build_house(w, d, stories, roof_kind, roof, wall_l, wall_r, door_off, windows, extras, rise=None):
    found = 7
    storey = 34 if stories == 1 else 30
    wall_h = found + storey * stories + (8 if stories >= 2 else 4)
    rise = rise if rise is not None else (26 if stories == 1 else 24)
    over = 9
    img, vx, _ = sprite_canvas(w, d, wall_h + rise + 28, pad=22, extra_south=18)
    house_body(img, vx, w, d, wall_h, wall_l, wall_r, found)
    for win in windows:
        floor = int(win.get("floor", 0))
        z = found + 10 + floor * storey
        ww, wh = win.get("ww", 16), win.get("wh", 18)
        face = win["face"]
        if face == "south":
            pts = window_on_south(vx, w, d, win["u"], z, ww, wh)
        elif face == "east":
            pts = window_on_east(vx, w, d, win["u"], z, ww, wh)
        else:
            pts = window_on_west(vx, w, d, win["u"], z, ww, wh)
        draw_window(img, pts, win.get("frame", FRAME), win.get("glass", GLASS), lit=win.get("lit", False), mullions=win.get("mullions", True))
        if win.get("box") and face == "south":
            planter_box(img, vx, win["u"], 3, w=ww + 4, d=7, h=6)
    door = extras.get("door", {})
    draw_door(img, vx, door.get("face", "south"), w, d, door.get("offset", door_off), found, door.get("width", 22), door.get("height", 32), door.get("color", WOOD_DK), style=door.get("style", "panel"), glass=door.get("glass"))
    if roof_kind == "gable":
        draw_gable_roof(img, vx, w, d, wall_h, rise, roof, over=over, axis=extras.get("gable_axis", "x"))
    else:
        draw_hip_roof(img, vx, w, d, wall_h, rise, roof, over=over)
    if extras.get("chimney"):
        chimney(img, vx, *extras["chimney"], wall_h + 4)
    if extras.get("antenna"):
        antenna(img, vx, *extras["antenna"], wall_h + rise + 2)
    if extras.get("ac"):
        ac_unit(img, vx, *extras["ac"])
    if extras.get("planter"):
        planter_box(img, vx, *extras["planter"])
    return img


def house_a():
    windows = [
        {"face": "south", "u": -48, "floor": 0, "ww": 18, "wh": 18},
        {"face": "south", "u": 50, "floor": 0, "ww": 18, "wh": 18},
        {"face": "east", "u": -36, "floor": 0, "ww": 16, "wh": 17},
        {"face": "east", "u": -96, "floor": 0, "ww": 16, "wh": 17},
    ]
    return build_house(160, 128, 1, "hip", ROOF_TERRA, WALL_CREAM, WALL_CREAM_R, 8, windows, {"door": {"offset": 8, "width": 20, "height": 32}, "chimney": (30, -70), "planter": (-58, 8), "antenna": (10, -64)}, rise=28)


def house_b():
    windows = [
        {"face": "south", "u": -40, "floor": 0, "ww": 16, "wh": 18, "box": True},
        {"face": "south", "u": 44, "floor": 0, "ww": 16, "wh": 18},
        {"face": "south", "u": -40, "floor": 1, "ww": 16, "wh": 16},
        {"face": "south", "u": 44, "floor": 1, "ww": 16, "wh": 16},
        {"face": "east", "u": -40, "floor": 0, "ww": 15, "wh": 16},
        {"face": "east", "u": -100, "floor": 0, "ww": 15, "wh": 16},
        {"face": "east", "u": -70, "floor": 1, "ww": 15, "wh": 15},
    ]
    return build_house(144, 144, 2, "hip", ROOF_BROWN, WALL_WHITE, WALL_WHITE_R, -6, windows, {"door": {"offset": -6, "width": 20, "height": 30}, "ac": (70, -50, 22), "antenna": (0, -72)}, rise=24)


def house_c():
    windows = [
        {"face": "south", "u": -30, "floor": 0, "ww": 16, "wh": 18},
        {"face": "south", "u": 36, "floor": 0, "ww": 16, "wh": 18},
        {"face": "east", "u": -36, "floor": 0, "ww": 15, "wh": 16},
        {"face": "east", "u": -90, "floor": 0, "ww": 15, "wh": 16},
        {"face": "east", "u": -132, "floor": 0, "ww": 15, "wh": 16},
    ]
    return build_house(128, 160, 1, "gable", ROOF_DARK, WALL_GREY, WALL_GREY_R, -8, windows, {"door": {"offset": -8, "width": 20, "height": 32}, "gable_axis": "y", "chimney": (-20, -40), "planter": (40, 8)}, rise=30)


def house_d():
    windows = [
        {"face": "south", "u": -34, "floor": 0, "ww": 16, "wh": 17, "box": True},
        {"face": "south", "u": 38, "floor": 0, "ww": 16, "wh": 17},
        {"face": "east", "u": -30, "floor": 0, "ww": 14, "wh": 15},
        {"face": "east", "u": -70, "floor": 0, "ww": 14, "wh": 15},
    ]
    return build_house(128, 96, 1, "hip", ROOF_MOSS, WALL_WARM, WALL_WARM_R, 10, windows, {"door": {"offset": 10, "width": 18, "height": 30}, "antenna": (8, -48)}, rise=24)


def house_e():
    windows = [
        {"face": "south", "u": -52, "floor": 0, "ww": 16, "wh": 17},
        {"face": "south", "u": 54, "floor": 0, "ww": 16, "wh": 17},
        {"face": "south", "u": -52, "floor": 1, "ww": 16, "wh": 16},
        {"face": "south", "u": 0, "floor": 1, "ww": 16, "wh": 16},
        {"face": "south", "u": 54, "floor": 1, "ww": 16, "wh": 16},
        {"face": "east", "u": -32, "floor": 0, "ww": 14, "wh": 15},
        {"face": "east", "u": -90, "floor": 0, "ww": 14, "wh": 15},
        {"face": "east", "u": -60, "floor": 1, "ww": 14, "wh": 14},
    ]
    return build_house(160, 128, 2, "hip", ROOF_GREY, WALL_CREAM, WALL_CREAM_R, 4, windows, {"door": {"offset": 4, "width": 20, "height": 30}, "chimney": (40, -80), "ac": (78, -40, 20)}, rise=26)


def house_f():
    windows = [
        {"face": "south", "u": -44, "floor": 0, "ww": 17, "wh": 18, "box": True},
        {"face": "south", "u": 48, "floor": 0, "ww": 17, "wh": 18, "box": True},
        {"face": "east", "u": -40, "floor": 0, "ww": 15, "wh": 16},
        {"face": "east", "u": -100, "floor": 0, "ww": 15, "wh": 16},
    ]
    return build_house(144, 144, 1, "hip", ROOF_RED, WALL_YELLOW, WALL_YELLOW_R, -4, windows, {"door": {"offset": -4, "width": 20, "height": 32, "color": (96, 52, 40)}, "planter": (60, 8), "chimney": (-24, -60)}, rise=28)


def house_g():
    windows = [
        {"face": "south", "u": 28, "floor": 0, "ww": 16, "wh": 17},
        {"face": "south", "u": 28, "floor": 1, "ww": 16, "wh": 15},
        {"face": "east", "u": -36, "floor": 0, "ww": 14, "wh": 16},
        {"face": "east", "u": -88, "floor": 0, "ww": 14, "wh": 16},
        {"face": "east", "u": -130, "floor": 0, "ww": 14, "wh": 16},
        {"face": "east", "u": -88, "floor": 1, "ww": 14, "wh": 14},
    ]
    return build_house(128, 160, 2, "gable", (118, 126, 138), WALL_WHITE, WALL_WHITE_R, -20, windows, {"door": {"offset": -20, "width": 20, "height": 30}, "gable_axis": "y", "ac": (62, -70, 40), "antenna": (0, -50)}, rise=26)


def house_wide(variant: str):
    specs = {
        "a": (256, 96, 2, "hip", ROOF_TERRA, WALL_CREAM, WALL_CREAM_R, -20),
        "b": (256, 96, 1, "hip", ROOF_GREY, WALL_WHITE, WALL_WHITE_R, 24),
        "c": (256, 96, 2, "gable", ROOF_BROWN, WALL_WARM, WALL_WARM_R, 0),
    }
    w, d, stories, kind, roof, wl, wr, door = specs[variant]
    windows = [
        {"face": "south", "u": -90, "floor": 0, "ww": 18, "wh": 16},
        {"face": "south", "u": -46, "floor": 0, "ww": 18, "wh": 16},
        {"face": "south", "u": 70, "floor": 0, "ww": 18, "wh": 16},
        {"face": "south", "u": 108, "floor": 0, "ww": 18, "wh": 16},
        {"face": "east", "u": -30, "floor": 0, "ww": 14, "wh": 15},
        {"face": "east", "u": -70, "floor": 0, "ww": 14, "wh": 15},
    ]
    if stories == 2:
        windows += [
            {"face": "south", "u": -90, "floor": 1, "ww": 16, "wh": 15},
            {"face": "south", "u": -46, "floor": 1, "ww": 16, "wh": 15},
            {"face": "south", "u": 70, "floor": 1, "ww": 16, "wh": 15},
            {"face": "south", "u": 108, "floor": 1, "ww": 16, "wh": 15},
            {"face": "east", "u": -48, "floor": 1, "ww": 14, "wh": 14},
        ]
    extras = {"door": {"offset": door, "width": 22, "height": 30}}
    if variant == "a":
        extras["chimney"] = (80, -50)
        extras["planter"] = (-100, 8)
    elif variant == "b":
        extras["antenna"] = (20, -48)
        extras["ac"] = (w / 2 - 2, -36, 18)
    else:
        extras["gable_axis"] = "x"
        extras["planter"] = (90, 8)
    return build_house(w, d, stories, kind, roof, wl, wr, door, windows, extras, rise=24)


def row_house(variant: str):
    w, d = 304, 96
    roof = ROOF_DARK if variant == "a" else ROOF_TERRA
    wl, wr = (WALL_GREY, WALL_GREY_R) if variant == "a" else (WALL_CREAM, WALL_CREAM_R)
    windows = []
    for bay in (-90, 90):
        windows += [
            {"face": "south", "u": bay - 28, "floor": 0, "ww": 16, "wh": 16},
            {"face": "south", "u": bay + 28, "floor": 0, "ww": 16, "wh": 16},
            {"face": "south", "u": bay - 28, "floor": 1, "ww": 16, "wh": 15},
            {"face": "south", "u": bay + 28, "floor": 1, "ww": 16, "wh": 15},
        ]
    windows += [{"face": "east", "u": -30, "floor": 0, "ww": 14, "wh": 15}, {"face": "east", "u": -70, "floor": 1, "ww": 14, "wh": 14}]
    door_off = -90 if variant == "a" else 90
    return build_house(w, d, 2, "hip", roof, wl, wr, door_off, windows, {"door": {"offset": door_off, "width": 20, "height": 30}, "chimney": (20, -48)}, rise=22)


def apartment(variant: str):
    w, d = 320, 88
    roof = ROOF_GREY if variant == "a" else (96, 108, 120)
    wl, wr = (WALL_WHITE, WALL_WHITE_R) if variant == "a" else (WALL_CREAM, WALL_CREAM_R)
    windows = []
    for floor in range(3):
        for u in (-130, -80, -30, 30, 80, 130):
            windows.append({"face": "south", "u": u, "floor": floor, "ww": 16, "wh": 14})
        windows.append({"face": "east", "u": -28, "floor": floor, "ww": 14, "wh": 13})
        windows.append({"face": "east", "u": -60, "floor": floor, "ww": 14, "wh": 13})
    extras = {"door": {"offset": 0, "width": 24, "height": 28, "style": "glass", "color": (70, 80, 86), "glass": GLASS_DK}, "ac": (w / 2 - 2, -40, 50), "antenna": (40, -44)}
    return build_house(w, d, 3, "hip", roof, wl, wr, 0, windows, extras, rise=16)


def make_shop(w, d, wall_h, roof_color, wall_l, wall_r, fascia, sign, door_off=0):
    found = 6
    img, vx, _ = sprite_canvas(w, d, wall_h + 36, pad=24, extra_south=16)
    ground_shadow(img, vx, w, d)
    draw_foundation(img, vx, w, d, found, (150, 148, 142))
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, found, wall_h, mix(wall_l, wall_r, 0.3), 0.03, 31)
    draw_wall(img, vx, -w / 2, 0, -w / 2, -d, found, wall_h, wall_l, 0.03, 32)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, found, wall_h, wall_r, 0.03, 33)
    win_y0 = found + 6
    win_h = max(28, wall_h * 0.42)
    draw_door(img, vx, "south", w, d, door_off, found, 32, win_h + 4, (70, 82, 88), style="auto", glass=GLASS_DK)
    gap = 40
    left_c, right_c = door_off - gap - 28, door_off + gap + 28
    if left_c - 30 > -w / 2 + 8:
        draw_window(img, window_on_south(vx, w, d, left_c, win_y0, 56, win_h), (70, 74, 78), GLASS_DK, mullions=True, sill=False)
    if right_c + 30 < w / 2 - 8:
        draw_window(img, window_on_south(vx, w, d, right_c, win_y0, 56, win_h), (70, 74, 78), GLASS_DK, mullions=True, sill=False)
    draw_window(img, window_on_east(vx, w, d, -d * 0.28, win_y0 + 4, 22, 20), (70, 74, 78), GLASS, mullions=True, sill=False)
    draw_window(img, window_on_east(vx, w, d, -d * 0.58, win_y0 + 4, 22, 20), (70, 74, 78), GLASS, mullions=True, sill=False)
    if fascia.get("pitched"):
        z1, z0 = wall_h - 18, wall_h - 38
        draw_hip_roof(img, vx, w, d, wall_h, 18, roof_color, over=6)
    else:
        z1, z0 = wall_h - 2, wall_h - 22
        draw_flat_roof(img, vx, w, d, wall_h, roof_color, over=7, parapet=5)
        ac_unit(img, vx, -w * 0.22, -d * 0.45, wall_h + 6, w=22, d=16, h=7)
        ac_unit(img, vx, w * 0.18, -d * 0.35, wall_h + 6, w=18, d=14, h=6)
    s, _e = fascia_band(img, vx, w, d, z0, z1, fascia["south"], fascia["east"])
    if fascia.get("stripes"):
        z = z0
        for col_s, col_e, thick in fascia["stripes"]:
            fascia_band(img, vx, w, d, z - thick, z, col_s, col_e)
            z -= thick
    if sign:
        cap = 22 if w >= 400 else 16
        fsz = max(14, int(min(cap, (z1 - z0) * 0.7)) * SCALE)
        text_on_quad(img, s, sign, fascia.get("text", (248, 248, 244)), font(fsz))
    return img


def convenience():
    return make_shop(224, 176, 86, (72, 128, 96), WALL_WHITE, WALL_WHITE_R, {"south": (46, 130, 86), "east": (36, 108, 70), "stripes": [((230, 140, 48), (200, 118, 36), 3), ((196, 52, 46), (160, 40, 38), 3)], "text": (250, 250, 246)}, "Everyday  24小时营业", 8)


def convenience_b():
    # Distinct from the Everyday store: cooler fascia, different name, no copy of a chain mark.
    return make_shop(224, 176, 86, (86, 118, 148), WALL_WHITE, WALL_WHITE_R, {"south": (46, 96, 150), "east": (36, 80, 128), "stripes": [((240, 220, 96), (206, 184, 70), 3)], "text": (250, 250, 246)}, "海灯便利", 16)


def convenience_wide():
    return make_shop(280, 80, 80, (72, 128, 96), WALL_WHITE, WALL_WHITE_R, {"south": (46, 130, 86), "east": (36, 108, 70), "stripes": [((230, 140, 48), (200, 118, 36), 3), ((196, 52, 46), (160, 40, 38), 3)], "text": (250, 250, 246)}, "Everyday  24小时营业", 0)


def grocery():
    return make_shop(208, 160, 84, ROOF_BROWN, WALL_WARM, WALL_WARM_R, {"south": (120, 70, 54), "east": (96, 56, 44), "stripes": [((210, 190, 150), (180, 160, 124), 3)], "text": (248, 236, 214), "pitched": True}, "滨町杂货", -12)


def grocery_b():
    return make_shop(208, 160, 84, ROOF_DARK, (232, 224, 210), (198, 188, 172), {"south": (64, 86, 96), "east": (50, 70, 80), "text": (240, 244, 246), "pitched": True}, "日用商店", 16)


def eatery(variant="a"):
    if variant == "a":
        return make_shop(264, 88, 80, (140, 72, 60), (240, 224, 200), (208, 190, 168), {"south": (180, 86, 70), "east": (150, 68, 56), "text": (255, 236, 220), "pitched": True}, "暖灯食堂", -20)
    return make_shop(264, 88, 80, (90, 80, 70), WALL_CREAM, WALL_CREAM_R, {"south": (64, 90, 86), "east": (50, 74, 70), "text": (236, 244, 236), "pitched": True}, "海风茶屋", 18)


def supermarket():
    return make_shop(480, 120, 92, (86, 96, 92), WALL_WHITE, WALL_WHITE_R, {"south": (48, 100, 110), "east": (38, 84, 94), "stripes": [((236, 200, 90), (200, 168, 70), 4)], "text": (250, 250, 246)}, "青禾超市", -40)


def supermarket_b():
    return make_shop(480, 120, 92, (90, 100, 96), WALL_GREY, WALL_GREY_R, {"south": (70, 92, 80), "east": (56, 76, 66), "text": (245, 247, 240)}, "海岸市场", 30)


def warehouse(variant="a"):
    specs = {
        "a": (288, 192, 108, (90, 102, 112), (176, 186, 192), (140, 150, 158)),
        "b": (288, 192, 100, (86, 92, 90), (168, 170, 164), (132, 136, 130)),
        "wide": (512, 128, 110, (90, 102, 112), (176, 186, 192), (140, 150, 158)),
        "wide_b": (512, 128, 104, (100, 96, 88), (186, 178, 166), (150, 142, 130)),
    }
    w, d, wall_h, roof, wl, wr = specs[variant]
    found = 8
    img, vx, _ = sprite_canvas(w, d, wall_h + 28, pad=22, extra_south=14)
    ground_shadow(img, vx, w, d)
    draw_foundation(img, vx, w, d, found, (130, 132, 134))
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, found, wall_h, mix(wl, wr, 0.3), 0.03, 41)
    draw_wall(img, vx, -w / 2, 0, -w / 2, -d, found, wall_h, wl, 0.03, 42)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, found, wall_h, wr, 0.03, 43)
    spts = wall_quad(vx, -w / 2, 0, w / 2, 0, found, wall_h)
    mask = _inside_mask(img.size, spts)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ldr = ImageDraw.Draw(layer)
    a, b, c, dpt = spts
    for i in range(2, 24):
        t = i / 24
        ldr.line([lerp_pt(a, b, t), lerp_pt(dpt, c, t)], fill=rgb((255, 255, 255), 28), width=1)
    layer.putalpha(ImageChops.multiply(layer.split()[3], mask))
    img.alpha_composite(layer)
    draw_door(img, vx, "south", w, d, 0 if "wide" not in variant else -40, found, 70 if "wide" not in variant else 90, 58, (70, 80, 88), style="panel")
    if "wide" in variant:
        draw_door(img, vx, "south", w, d, 80, found, 70, 58, (70, 80, 88), style="panel")
    for u in ((-0.25, -0.5, -0.75) if d > 140 else (-0.3, -0.65)):
        draw_window(img, window_on_east(vx, w, d, d * u, wall_h - 28, 20, 12), (70, 80, 88), GLASS, mullions=False, sill=False)
    draw_hip_roof(img, vx, w, d, wall_h, 16, roof, over=6, courses=6)
    ac_unit(img, vx, w * 0.2, -d * 0.4, wall_h + 10, w=20, d=14, h=8)
    return img


def garage(variant="a"):
    w, d, wall_h = 264, 96, 72
    roof = (110, 104, 96) if variant == "a" else (90, 96, 100)
    wl, wr = ((210, 206, 198), (176, 170, 162)) if variant == "a" else ((200, 208, 206), (166, 174, 172))
    found = 6
    img, vx, _ = sprite_canvas(w, d, wall_h + 24, pad=20, extra_south=12)
    ground_shadow(img, vx, w, d)
    draw_foundation(img, vx, w, d, found, (140, 138, 132))
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, found, wall_h, mix(wl, wr, 0.3), 0.03, 51)
    draw_wall(img, vx, -w / 2, 0, -w / 2, -d, found, wall_h, wl, 0.03, 52)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, found, wall_h, wr, 0.03, 53)
    for off in (-60, 60):
        draw_door(img, vx, "south", w, d, off, found, 70, 50, (80, 86, 90) if variant == "a" else (70, 90, 88), style="panel")
    draw_window(img, window_on_east(vx, w, d, -d * 0.5, found + 20, 18, 16), FRAME, GLASS, sill=False)
    draw_hip_roof(img, vx, w, d, wall_h, 16, roof, over=7)
    return img


def shrine():
    w, d, wall_h = 88, 88, 44
    img, vx, _ = sprite_canvas(w, d, wall_h + 56, pad=28, extra_south=16)
    ground_shadow(img, vx, w + 8, d + 8)
    draw_foundation(img, vx, w + 8, d + 8, 10, (160, 154, 146))
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, 10, 16, (196, 86, 70), 0.02, 61)
    draw_wall(img, vx, -w / 2, 0, -w / 2, -d, 10, 16, (210, 100, 82), 0.02, 62)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, 10, 16, (160, 64, 54), 0.02, 63)
    hl, hr = (236, 230, 216), (206, 196, 180)
    draw_wall(img, vx, -w * 0.38, -d * 0.08, w * 0.38, -d * 0.08, 16, wall_h, mix(hl, hr, 0.3), 0.03, 64)
    draw_wall(img, vx, -w * 0.38, -d * 0.08, -w * 0.38, -d * 0.9, 16, wall_h, hl, 0.03, 65)
    draw_wall(img, vx, w * 0.38, -d * 0.08, w * 0.38, -d * 0.9, 16, wall_h, hr, 0.03, 66)
    draw_door(img, vx, "south", w * 0.76, d, 0, 16, 18, 26, (120, 36, 32), style="panel")
    draw_gable_roof(img, vx, w * 0.92, d * 0.92, wall_h, 28, (128, 44, 40), over=10, axis="x")
    rp_l = vx(-w * 0.15, -d * 0.46, wall_h + 34)
    rp_r = vx(w * 0.15, -d * 0.46, wall_h + 34)
    ImageDraw.Draw(img).line([rp_l, (rp_l[0] - 4 * SCALE, rp_l[1] - 10 * SCALE)], fill=rgb((80, 24, 22)), width=2)
    ImageDraw.Draw(img).line([rp_r, (rp_r[0] + 4 * SCALE, rp_r[1] - 10 * SCALE)], fill=rgb((80, 24, 22)), width=2)
    p = vx(-w * 0.7, 8, 0)
    ImageDraw.Draw(img).rectangle((p[0] - 3 * SCALE, p[1] - 16 * SCALE, p[0] + 3 * SCALE, p[1]), fill=rgb(STONE_DK))
    ImageDraw.Draw(img).ellipse((p[0] - 5 * SCALE, p[1] - 22 * SCALE, p[0] + 5 * SCALE, p[1] - 12 * SCALE), fill=rgb(STONE), outline=rgb(STONE_DK))
    return img


def bike_shelter():
    w, d, h = 128, 80, 36
    img, vx, _ = sprite_canvas(w, d, h + 10, pad=18, extra_south=10)
    ground_shadow(img, vx, w, d)
    dr = ImageDraw.Draw(img)
    for x, y in ((-w / 2 + 8, 0), (w / 2 - 8, 0), (-w / 2 + 8, -d), (w / 2 - 8, -d)):
        dr.line([vx(x, y), vx(x, y, h)], fill=rgb((90, 90, 86)), width=3)
    draw_hip_roof(img, vx, w, d, h, 8, (148, 128, 104), over=6, courses=4)
    for ox in (-36, 0, 36):
        p = vx(ox, -12, 0)
        dr.ellipse((p[0] - 7, p[1] - 7, p[0] + 3, p[1] + 3), outline=rgb((50, 50, 52)), width=2)
        dr.ellipse((p[0] + 8, p[1] - 5, p[0] + 18, p[1] + 5), outline=rgb((50, 50, 52)), width=2)
        dr.line((p[0] - 2, p[1] - 2, p[0] + 10, p[1] - 14), fill=rgb((50, 50, 52)), width=2)
    return img


def tram_stop():
    w, d, h = 140, 56, 62
    img, vx, _ = sprite_canvas(w, d, h + 18, pad=24, extra_south=12)
    ground_shadow(img, vx, w, d)
    plat = [vx(-w / 2, 4), vx(w / 2, 4), vx(w / 2, -d), vx(-w / 2, -d)]
    fill_masked(img, plat, (196, 196, 188))
    edge(img, plat, (130, 130, 124), 1)
    dr = ImageDraw.Draw(img)
    for x, y in ((-w / 2 + 12, -6), (w / 2 - 12, -6), (-w / 2 + 12, -d + 6), (w / 2 - 12, -d + 6)):
        dr.line([vx(x, y), vx(x, y, h)], fill=rgb((90, 96, 100)), width=4)
    a, b = vx(-w / 2 + 8, -d + 4), vx(w / 2 - 8, -d + 4)
    glass = [a, b, (b[0], b[1] - (h - 8) * SCALE), (a[0], a[1] - (h - 8) * SCALE)]
    fill_masked(img, glass, (180, 210, 220, 130))
    edge(img, glass, (120, 140, 150), 1)
    draw_flat_roof(img, vx, w, d, h, (70, 86, 96), over=8, parapet=0)
    sign_c = vx(0, 8, h - 8)
    sw, sh = 56 * SCALE, 36 * SCALE
    rect = Image.new("RGBA", img.size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(rect)
    x0, y0 = int(sign_c[0] - sw / 2), int(sign_c[1])
    rd.rounded_rectangle((x0, y0, x0 + sw, y0 + sh), radius=3, fill=rgb((48, 92, 150)), outline=rgb((230, 232, 236)), width=2)
    rd.text((x0 + 6, y0 + 3), "海岸線", font=font(11 * SCALE, jp=True), fill=rgb((248, 248, 252)))
    rd.text((x0 + 10, y0 + 16 * SCALE), "のりば", font=font(10 * SCALE, jp=True), fill=rgb((248, 248, 252)))
    img.alpha_composite(rect)
    dr.line([vx(-30, -18, 10), vx(30, -18, 10)], fill=rgb((90, 80, 70)), width=4)
    return img


def vending(color: str):
    w, d, h = 18, 16, 42
    pal = {"red": ((196, 64, 58), (160, 46, 42)), "blue": ((52, 92, 168), (40, 72, 140)), "green": ((46, 122, 86), (36, 98, 70))}
    body, body_r = pal[color]
    img, vx, _ = sprite_canvas(w, d, h + 4, pad=12, extra_south=8)
    ground_shadow(img, vx, w, d)
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, 0, h, mix(body, body_r, 0.25), 0.02, 71)
    draw_wall(img, vx, -w / 2, 0, -w / 2, -d, 0, h, body, 0.02, 72)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, 0, h, body_r, 0.02, 73)
    fill_masked(img, [vx(-w / 2, 0, h), vx(w / 2, 0, h), vx(w / 2, -d, h), vx(-w / 2, -d, h)], shade(body, -0.15))
    draw_window(img, window_on_south(vx, w, d, 0, 18, 12, 16), (40, 42, 46), (160, 200, 210), mullions=False, sill=False)
    fill_masked(img, window_on_south(vx, w, d, 0, 6, 12, 8), (30, 32, 36))
    fascia_band(img, vx, w, d, h - 6, h - 1, (240, 240, 244), (220, 220, 224), wrap=True)
    return img


def lamp():
    img, vx, foot = sprite_canvas(8, 8, 78, pad=20, extra_south=6)
    dr = ImageDraw.Draw(img)
    base = vx(0, 0, 0)
    fill_masked(img, [vx(-5, 3, 0), vx(5, 3, 0), vx(4, 2, 6), vx(-4, 2, 6)], (120, 118, 112))
    dr.line([base, vx(0, 0, 64)], fill=rgb((74, 76, 80)), width=max(3, int(1.6 * SCALE)))
    arm = [vx(t * 14, t * 2, 64 - t * 8) for t in (i / 7 for i in range(8))]
    dr.line(arm, fill=rgb((74, 76, 80)), width=max(2, SCALE), joint="curve")
    lantern = arm[-1]
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((lantern[0] - 16 * SCALE, lantern[1] - 16 * SCALE, lantern[0] + 16 * SCALE, lantern[1] + 16 * SCALE), fill=rgb((255, 200, 110), 40))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(6)))
    r = 7 * SCALE
    dr = ImageDraw.Draw(img)
    dr.ellipse((lantern[0] - r, lantern[1] - r, lantern[0] + r, lantern[1] + r + 2), fill=rgb((210, 170, 90)), outline=rgb((90, 80, 60)), width=1)
    dr.ellipse((lantern[0] - r + 3, lantern[1] - r + 3, lantern[0] + r - 3, lantern[1] + r - 1), fill=rgb((255, 224, 150)))
    global LAST_FOOT
    LAST_FOOT = vx(0, 0, 0)
    return img


def tree():
    img, vx, foot = sprite_canvas(20, 20, 78, pad=28, extra_south=8)
    dr = ImageDraw.Draw(img)
    base = vx(0, 0, 0)
    dr.rectangle((base[0] - 3 * SCALE, base[1] - 26 * SCALE, base[0] + 3 * SCALE, base[1]), fill=rgb((96, 70, 48)))
    for (dx, dy), r, col in (((0, -50), 22, (62, 118, 70)), ((-10, -40), 16, (50, 102, 62)), ((10, -38), 15, (72, 130, 78)), ((-4, -58), 14, (46, 96, 58)), ((6, -54), 13, (80, 140, 86))):
        cx, cy = base[0] + dx * SCALE * 0.6, base[1] + dy * SCALE * 0.85
        dr.ellipse((cx - r * SCALE / 2, cy - r * SCALE / 2, cx + r * SCALE / 2, cy + r * SCALE / 2), fill=rgb(col))
    return img


def make_bike():
    img, vx, _ = sprite_canvas(28, 12, 16, pad=10, extra_south=6)
    dr = ImageDraw.Draw(img)
    p = vx(0, 0, 0)
    dr.ellipse((p[0] - 10, p[1] - 8, p[0] + 2, p[1] + 4), outline=rgb((50, 50, 52)), width=2)
    dr.ellipse((p[0] + 8, p[1] - 6, p[0] + 20, p[1] + 6), outline=rgb((50, 50, 52)), width=2)
    dr.line((p[0] - 4, p[1] - 2, p[0] + 12, p[1] - 16), fill=rgb((50, 50, 52)), width=2)
    dr.line((p[0] + 12, p[1] - 16, p[0] + 12, p[1] - 22), fill=rgb((50, 50, 52)), width=2)
    return img


def stone_bridge():
    w, d = 160, 96
    deck_z = 20
    img, vx, _ = sprite_canvas(w, d, 64, pad=18, extra_south=10)
    ground_shadow(img, vx, w, d)
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, 0, deck_z, (150, 146, 138), 0.04, 81)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, 0, deck_z, (128, 124, 116), 0.04, 82)
    deck = [vx(-w / 2, 0, deck_z), vx(w / 2, 0, deck_z), vx(w / 2, -d, deck_z), vx(-w / 2, -d, deck_z)]
    noisy_fill(img, deck, (168, 164, 156), 0.05, 80)
    edge(img, deck, (110, 106, 98), 1)
    arch = []
    for i in range(17):
        t = i / 16
        arch.append(vx(lerp(-w * 0.32, w * 0.32, t), 0, 1 + math.sin(t * math.pi) * 16))
    arch += [vx(w * 0.32, 0, 0), vx(-w * 0.32, 0, 0)]
    fill_masked(img, arch, (40, 86, 96))
    # voussoir ticks around the arch
    for i in range(1, 16):
        t = i / 16
        inner = vx(lerp(-w * 0.32, w * 0.32, t), 0, 1 + math.sin(t * math.pi) * 16)
        outer = vx(lerp(-w * 0.32, w * 0.32, t), 0, 1 + math.sin(t * math.pi) * 19)
        ImageDraw.Draw(img).line([inner, outer], fill=rgb((110, 108, 100), 180), width=1)
    # stone joints on the deck
    a, b, c, dpt = deck
    for i in range(1, 8):
        ImageDraw.Draw(img).line([lerp_pt(a, b, i / 8), lerp_pt(dpt, c, i / 8)], fill=rgb((130, 126, 118), 90), width=1)
    for y, col in ((0, (176, 172, 164)), (-d, (160, 156, 148))):
        draw_wall(img, vx, -w / 2, y, w / 2, y, deck_z, deck_z + 14, col, 0.03, 83)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, deck_z, deck_z + 14, (148, 144, 136), 0.03, 84)
    for x in (-w / 2, -w / 4, 0, w / 4, w / 2):
        for y in (0, -d):
            p = vx(x, y, deck_z + 14)
            ImageDraw.Draw(img).rectangle((p[0] - 2 * SCALE, p[1] - 4 * SCALE, p[0] + 2 * SCALE, p[1] + 2), fill=rgb((150, 146, 138)))
    return img


def wood_bridge():
    w, d = 140, 72
    img, vx, _ = sprite_canvas(w, d, 40, pad=16, extra_south=10)
    ground_shadow(img, vx, w, d)
    deck = [vx(-w / 2, 0, 6), vx(w / 2, 0, 6), vx(w / 2, -d, 6), vx(-w / 2, -d, 6)]
    fill_masked(img, deck, (166, 126, 82))
    a, b, c, dpt = deck
    for i in range(1, 12):
        t = i / 12
        ImageDraw.Draw(img).line([lerp_pt(a, b, t), lerp_pt(dpt, c, t)], fill=rgb((130, 96, 60), 180), width=1)
    edge(img, deck, (110, 80, 50), 1)
    for x in (-w / 2 + 6, -w / 6, w / 6, w / 2 - 6):
        for y in (0, -d):
            ImageDraw.Draw(img).line([vx(x, y, 0), vx(x, y, 22)], fill=rgb((96, 70, 46)), width=3)
    for y in (0, -d):
        ImageDraw.Draw(img).line([vx(-w / 2 + 4, y, 20), vx(w / 2 - 4, y, 20)], fill=rgb((96, 70, 46)), width=3)
    return img


def canal_rail(axis: str):
    w, d = (10, 48) if axis == "ns" else (48, 10)
    h = 16
    img, vx, _ = sprite_canvas(w, d, h + 6, pad=10, extra_south=6)
    ground_shadow(img, vx, w, d)
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, 0, h, (176, 172, 164), 0.03, 91)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, 0, h, (148, 144, 136), 0.03, 92)
    fill_masked(img, [vx(-w / 2, 0, h), vx(w / 2, 0, h), vx(w / 2, -d, h), vx(-w / 2, -d, h)], (186, 182, 174))
    pts = ((0, y) for y in (0, -d / 2, -d)) if axis == "ns" else ((x, -d / 2) for x in (-w / 2, 0, w / 2))
    for x, y in pts:
        p = vx(x, y, h)
        ImageDraw.Draw(img).rectangle((p[0] - 2 * SCALE, p[1] - 3 * SCALE, p[0] + 2 * SCALE, p[1] + 1), fill=rgb((150, 146, 138)))
    return img


def crate():
    w, d, h = 22, 18, 16
    img, vx, _ = sprite_canvas(w, d, h + 4, pad=10, extra_south=6)
    ground_shadow(img, vx, w, d)
    draw_wall(img, vx, -w / 2, 0, w / 2, 0, 0, h, (200, 164, 108), 0.04, 93)
    draw_wall(img, vx, w / 2, 0, w / 2, -d, 0, h, (168, 134, 86), 0.04, 94)
    top = [vx(-w / 2, 0, h), vx(w / 2, 0, h), vx(w / 2, -d, h), vx(-w / 2, -d, h)]
    fill_masked(img, top, (150, 118, 70))
    edge(img, top, (110, 84, 50), 1)
    return img


def planter_prop():
    img, vx, _ = sprite_canvas(24, 16, 28, pad=12, extra_south=6)
    ground_shadow(img, vx, 24, 16)
    planter_box(img, vx, 0, 0, w=24, d=16, h=12, leaf=True)
    return img


def save_sprite(rel: str, img: Image.Image, map_size=None):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    MANIFEST["sprites"][rel] = {
        "w": img.width,
        "h": img.height,
        "foot": [round(LAST_FOOT[0], 2), round(LAST_FOOT[1], 2)],
        "map": [round((map_size or LAST_MAP)[0], 2), round((map_size or LAST_MAP)[1], 2)],
    }
    print("sprite", rel, img.size, "foot", MANIFEST["sprites"][rel]["foot"], "map", MANIFEST["sprites"][rel]["map"])


def contact_sheet(paths, out: Path, cols=6, cell=340):
    rows = math.ceil(len(paths) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (28, 30, 34, 255))
    dr = ImageDraw.Draw(sheet)
    for y in range(0, sheet.height, 16):
        for x in range(0, sheet.width, 16):
            if (x // 16 + y // 16) % 2 == 0:
                dr.rectangle((x, y, x + 16, y + 16), fill=(36, 38, 44, 255))
    label_font = font(12, regular=True)
    for i, path in enumerate(paths):
        im = Image.open(path).convert("RGBA")
        im.thumbnail((cell - 16, cell - 32), Image.Resampling.LANCZOS)
        x = (i % cols) * cell + (cell - im.width) // 2
        y = (i // cols) * cell + (cell - 20 - im.height) // 2
        sheet.alpha_composite(im, (x, y))
        dr.text(((i % cols) * cell + 8, (i // cols) * cell + cell - 18), path.name, fill=(230, 224, 210), font=label_font)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print("sheet", out, sheet.size)


def main():
    global MANIFEST
    existing = ROOT / "manifest.json"
    if existing.exists():
        try:
            MANIFEST = json.loads(existing.read_text())
            MANIFEST.setdefault("scale", 0.5)
            MANIFEST.setdefault("sprites", {})
        except Exception:
            MANIFEST = {"scale": 0.5, "sprites": {}}
    jobs = [
        ("buildings/house_a.png", house_a),
        ("buildings/house_b.png", house_b),
        ("buildings/house_c.png", house_c),
        ("buildings/house_d.png", house_d),
        ("buildings/house_e.png", house_e),
        ("buildings/house_f.png", house_f),
        ("buildings/house_g.png", house_g),
        ("buildings/house_wide_a.png", lambda: house_wide("a")),
        ("buildings/house_wide_b.png", lambda: house_wide("b")),
        ("buildings/house_wide_c.png", lambda: house_wide("c")),
        ("buildings/row_a.png", lambda: row_house("a")),
        ("buildings/row_b.png", lambda: row_house("b")),
        ("buildings/apartment_a.png", lambda: apartment("a")),
        ("buildings/apartment_b.png", lambda: apartment("b")),
        ("buildings/convenience.png", convenience),
        ("buildings/convenience_b.png", convenience_b),
        ("buildings/convenience_wide.png", convenience_wide),
        ("buildings/grocery.png", grocery),
        ("buildings/grocery_b.png", grocery_b),
        ("buildings/eatery.png", lambda: eatery("a")),
        ("buildings/eatery_b.png", lambda: eatery("b")),
        ("buildings/supermarket.png", supermarket),
        ("buildings/supermarket_b.png", supermarket_b),
        ("buildings/warehouse.png", lambda: warehouse("a")),
        ("buildings/warehouse_b.png", lambda: warehouse("b")),
        ("buildings/warehouse_wide.png", lambda: warehouse("wide")),
        ("buildings/warehouse_wide_b.png", lambda: warehouse("wide_b")),
        ("buildings/garage.png", lambda: garage("a")),
        ("buildings/garage_b.png", lambda: garage("b")),
        ("buildings/shrine.png", shrine),
        ("props/bike_shelter.png", bike_shelter),
        ("props/tram_stop.png", tram_stop),
        ("props/vending_red.png", lambda: vending("red")),
        ("props/vending_blue.png", lambda: vending("blue")),
        ("props/vending_green.png", lambda: vending("green")),
        ("props/lamp.png", lamp),
        ("props/tree.png", tree),
        ("props/bike.png", make_bike),
        ("props/stone_bridge.png", stone_bridge),
        ("props/wood_bridge.png", wood_bridge),
        ("props/canal_rail_ns.png", lambda: canal_rail("ns")),
        ("props/canal_rail_ew.png", lambda: canal_rail("ew")),
        ("props/crate.png", crate),
        ("props/planter.png", planter_prop),
    ]
    wanted = set(sys.argv[1:])
    written = []
    for rel, fn in jobs:
        if wanted and rel not in wanted and Path(rel).name not in wanted:
            continue
        save_sprite(rel, fn())
        written.append(ROOT / rel)
    (ROOT / "manifest.json").write_text(json.dumps(MANIFEST, indent=2) + "\n")
    print("manifest", ROOT / "manifest.json", "sprites", len(MANIFEST["sprites"]))
    contact_sheet(written, Path("/tmp/iso-prev/sheet.png"), cols=6, cell=340)


if __name__ == "__main__":
    main()
