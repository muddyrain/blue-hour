#!/usr/bin/env python3
"""Original 2:1 isometric first-pass tiles and props for Blue Hour. Not AI."""
from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path("/workspace/bh-iso/assets/iso")
TILE = 64
SCALE = 2  # render 2x for smoother edges
TW, TH = TILE * 2 * SCALE, TILE * SCALE  # 256x128 at SCALE=2


def to_view(x: float, y: float) -> tuple[float, float]:
    return (x - y, (x + y) * 0.5)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(len(c1)))


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def rgb(hex_or_tuple, a=255):
    if isinstance(hex_or_tuple, str):
        h = hex_or_tuple.lstrip("#")
        rgb_t = tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))
        return rgb_t + (a,)
    if len(hex_or_tuple) == 4:
        return hex_or_tuple
    return tuple(hex_or_tuple) + (a,)


# Soft daylight Japanese street palette (from locked concept, not neon).
PAL = {
    "grass": (122, 154, 106),
    "grass_dk": (96, 128, 84),
    "grass_lt": (148, 176, 126),
    "sidewalk": (212, 202, 184),
    "sidewalk_dk": (188, 176, 158),
    "sidewalk_lt": (230, 222, 206),
    "curb": (176, 166, 150),
    "asphalt": (86, 98, 108),
    "asphalt_dk": (70, 80, 90),
    "asphalt_lt": (108, 118, 126),
    "marking": (230, 224, 204),
    "canal": (58, 122, 138),
    "canal_dk": (36, 86, 104),
    "canal_lt": (110, 176, 186),
    "foam": (210, 230, 230),
    "wall_l": (232, 220, 200),
    "wall_r": (196, 180, 156),
    "roof": (154, 118, 90),
    "roof_dk": (120, 90, 68),
    "roof_lt": (180, 142, 108),
    "shop_l": (244, 244, 236),
    "shop_r": (214, 214, 202),
    "shop_roof": (62, 130, 86),
    "shop_stripe": (46, 122, 74),
    "groc_l": (232, 210, 176),
    "groc_r": (196, 168, 132),
    "groc_roof": (120, 86, 70),
    "ware_l": (176, 188, 194),
    "ware_r": (138, 150, 158),
    "ware_roof": (84, 96, 108),
    "stone": (150, 148, 140),
    "stone_dk": (112, 110, 102),
    "wood": (150, 110, 72),
    "wood_dk": (112, 80, 52),
    "bus": (240, 234, 220),
    "bus_dk": (206, 198, 182),
    "bus_win": (120, 160, 176),
    "shadow": (30, 28, 24),
}


def diamond_pts(ox=0, oy=0, s=None):
    s = TILE if s is None else s
    # map cell (0,0)-(s,s) translated so left is 0
    pts = [to_view(0, 0), to_view(s, 0), to_view(s, s), to_view(0, s)]
    minx = min(p[0] for p in pts)
    return [(ox + (p[0] - minx) * SCALE, oy + p[1] * SCALE) for p in pts]


def fill_diamond(img: Image.Image, color, ox=0, oy=0, s=None, outline=None, width=1):
    d = ImageDraw.Draw(img)
    pts = diamond_pts(ox, oy, s)
    d.polygon(pts, fill=rgb(color) if not isinstance(color, tuple) or len(color) < 4 else color)
    if outline:
        d.line(pts + [pts[0]], fill=rgb(outline), width=width, joint="curve")


def shade_diamond(img: Image.Image, base, light, dark, noise=0.06, ox=0, oy=0, s=None, grain=1):
    """Fill a diamond with a soft NW-light gradient and grain."""
    s = TILE if s is None else s
    pts = diamond_pts(ox, oy, s)
    minx, miny = int(min(p[0] for p in pts)), int(min(p[1] for p in pts))
    maxx, maxy = int(max(p[0] for p in pts)) + 1, int(max(p[1] for p in pts)) + 1
    w, h = maxx - minx, maxy - miny
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = layer.load()
    # barycentric-ish: use ellipse falloff from top
    import random
    rng = random.Random(int(base[0] + base[1] * 17 + (s or 0)))
    # mask
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon([(p[0] - minx, p[1] - miny) for p in pts], fill=255)
    for y in range(h):
        for x in range(w):
            if mask.getpixel((x, y)) < 8:
                continue
            # light from top-left of diamond
            t = (x / max(w - 1, 1)) * 0.45 + (y / max(h - 1, 1)) * 0.55
            n = (rng.random() - 0.5) * 2 * noise
            c = mix(light, dark, min(1, max(0, t + n)))
            # slightly blend toward base
            c = mix(c, base, 0.25)
            px[x, y] = (c[0], c[1], c[2], 255)
    img.alpha_composite(layer, (minx, miny))


def tile_grass() -> Image.Image:
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    shade_diamond(img, PAL["grass"], PAL["grass_lt"], PAL["grass_dk"], noise=0.08)
    d = ImageDraw.Draw(img)
    # a few blades
    rng_pts = [(40, 50), (90, 70), (150, 40), (200, 80), (120, 100), (70, 90)]
    for x, y in rng_pts:
        d.line((x, y, x + 3, y - 8), fill=rgb(PAL["grass_lt"], 140), width=1)
    # soft edge
    return img


def tile_sidewalk() -> Image.Image:
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    shade_diamond(img, PAL["sidewalk"], PAL["sidewalk_lt"], PAL["sidewalk_dk"], noise=0.04)
    d = ImageDraw.Draw(img)
    pts = diamond_pts()
    # slab seams
    mid_top = ((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2)
    mid_bot = ((pts[2][0] + pts[3][0]) / 2, (pts[2][1] + pts[3][1]) / 2)
    mid_l = ((pts[0][0] + pts[3][0]) / 2, (pts[0][1] + pts[3][1]) / 2)
    mid_r = ((pts[1][0] + pts[2][0]) / 2, (pts[1][1] + pts[2][1]) / 2)
    d.line([mid_top, mid_bot], fill=rgb(PAL["curb"], 90), width=1)
    d.line([mid_l, mid_r], fill=rgb(PAL["curb"], 70), width=1)
    d.line(pts + [pts[0]], fill=rgb(PAL["curb"], 120), width=1)
    return img


def tile_road() -> Image.Image:
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    shade_diamond(img, PAL["asphalt"], PAL["asphalt_lt"], PAL["asphalt_dk"], noise=0.05)
    return img


def tile_road_dash_ew() -> Image.Image:
    img = tile_road()
    d = ImageDraw.Draw(img)
    # center dashed line along EW (map y mid), which is the long diagonal from left to right slightly...
    # In the diamond, map EW (varying x, const y=S/2) is a line from left to right through mid-height.
    pts = diamond_pts()
    left = ((pts[0][0] + pts[3][0]) / 2, (pts[0][1] + pts[3][1]) / 2)
    right = ((pts[1][0] + pts[2][0]) / 2, (pts[1][1] + pts[2][1]) / 2)
    # short dash in the middle
    d.line(
        [
            (lerp(left[0], right[0], 0.28), lerp(left[1], right[1], 0.28)),
            (lerp(left[0], right[0], 0.72), lerp(left[1], right[1], 0.72)),
        ],
        fill=rgb(PAL["marking"], 200),
        width=2,
    )
    return img


def tile_road_dash_ns() -> Image.Image:
    img = tile_road()
    d = ImageDraw.Draw(img)
    pts = diamond_pts()
    top = ((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2)
    bot = ((pts[2][0] + pts[3][0]) / 2, (pts[2][1] + pts[3][1]) / 2)
    d.line(
        [
            (lerp(top[0], bot[0], 0.28), lerp(top[1], bot[1], 0.28)),
            (lerp(top[0], bot[0], 0.72), lerp(top[1], bot[1], 0.72)),
        ],
        fill=rgb(PAL["marking"], 200),
        width=2,
    )
    return img


def tile_crosswalk(axis: str) -> Image.Image:
    img = tile_road()
    d = ImageDraw.Draw(img)
    pts = diamond_pts()
    # stripes perpendicular to travel
    for i in range(5):
        t0 = 0.12 + i * 0.16
        t1 = t0 + 0.08
        if axis == "ew":
            # stripes along NS (across the EW road)
            a0 = (lerp(pts[0][0], pts[1][0], t0), lerp(pts[0][1], pts[1][1], t0))
            a1 = (lerp(pts[3][0], pts[2][0], t0), lerp(pts[3][1], pts[2][1], t0))
            b0 = (lerp(pts[0][0], pts[1][0], t1), lerp(pts[0][1], pts[1][1], t1))
            b1 = (lerp(pts[3][0], pts[2][0], t1), lerp(pts[3][1], pts[2][1], t1))
        else:
            a0 = (lerp(pts[0][0], pts[3][0], t0), lerp(pts[0][1], pts[3][1], t0))
            a1 = (lerp(pts[1][0], pts[2][0], t0), lerp(pts[1][1], pts[2][1], t0))
            b0 = (lerp(pts[0][0], pts[3][0], t1), lerp(pts[0][1], pts[3][1], t1))
            b1 = (lerp(pts[1][0], pts[2][0], t1), lerp(pts[1][1], pts[2][1], t1))
        d.polygon([a0, b0, b1, a1], fill=rgb(PAL["marking"], 210))
    return img


def tile_canal() -> Image.Image:
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    shade_diamond(img, PAL["canal"], PAL["canal_lt"], PAL["canal_dk"], noise=0.05)
    d = ImageDraw.Draw(img)
    pts = diamond_pts()
    # ripple lines along the long axis
    for i, t in enumerate((0.28, 0.5, 0.72)):
        p1 = (lerp(pts[0][0], pts[1][0], t), lerp(pts[0][1], pts[1][1], t) + 4)
        p2 = (lerp(pts[3][0], pts[2][0], t), lerp(pts[3][1], pts[2][1], t) - 2)
        d.line([p1, p2], fill=rgb(PAL["foam"] if i == 1 else PAL["canal_lt"], 80), width=1)
    return img


def tile_bank() -> Image.Image:
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    shade_diamond(img, PAL["stone"], (176, 174, 166), PAL["stone_dk"], noise=0.05)
    d = ImageDraw.Draw(img)
    pts = diamond_pts()
    d.line(pts + [pts[0]], fill=rgb(PAL["stone_dk"], 140), width=1)
    return img


def save_tile(name: str, img: Image.Image):
    path = ROOT / "tiles" / f"{name}.png"
    # mild sharpen after 2x
    out = img.filter(ImageFilter.SMOOTH)
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)
    print("tile", path.name, out.size)


# ---------- sprites (buildings / props) ----------

def view_offset_box(w, d, h):
    """All corners of an iso box in view space, origin at south-center map foot."""
    corners = []
    for x, y in ((-w / 2, 0), (w / 2, 0), (-w / 2, -d), (w / 2, -d)):
        vx, vy = to_view(x, y)
        corners.append((vx, vy))
        corners.append((vx, vy - h))
    return corners


def sprite_canvas(w, d, h, pad=16):
    corners = view_offset_box(w, d, h)
    # include a little ground shadow
    xs = [c[0] for c in corners] + [0]
    ys = [c[1] for c in corners] + [12]
    minx, maxx = min(xs) - pad, max(xs) + pad
    miny, maxy = min(ys) - pad, max(ys) + pad
    # foot should be at bottom-center-ish
    width = int(math.ceil(maxx - minx)) * SCALE
    height = int(math.ceil(maxy - miny)) * SCALE
    origin = (-minx, -miny)  # add this (map-view units) then *SCALE

    def vx(mapx, mapy, up=0):
        x, y = to_view(mapx, mapy)
        return ((x + origin[0]) * SCALE, (y + origin[1] - up) * SCALE)

    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    foot = vx(0, 0)
    global LAST_FOOT
    LAST_FOOT = foot
    return img, vx, foot


def poly(draw, pts, fill, outline=None, width=1):
    draw.polygon(pts, fill=rgb(fill) if (not isinstance(fill, tuple) or len(fill) != 4) else fill)
    if outline:
        draw.line(list(pts) + [pts[0]], fill=rgb(outline), width=width, joint="curve")


def draw_box(img, vx, w, d, h, roof, left, right, roof_lt=None, eave=True):
    dr = ImageDraw.Draw(img)
    sw, se, nw, ne = vx(-w / 2, 0), vx(w / 2, 0), vx(-w / 2, -d), vx(w / 2, -d)
    up = lambda p, z=h: (p[0], p[1] - z * SCALE)
    # ground shadow
    shadow = [vx(-w / 2 + 8, 8), vx(w / 2 + 10, 8), vx(w / 2 + 10, -d + 8), vx(-w / 2 + 8, -d + 8)]
    # softer blob
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon(shadow, fill=rgb(PAL["shadow"], 50))
    sh = sh.filter(ImageFilter.GaussianBlur(4 * SCALE / 2))
    img.alpha_composite(sh)
    # South wall first (visible front). Then west/east returns, then roof.
    front = mix(left, right, 0.35)
    poly(dr, [sw, se, up(se), up(sw)], front, mix(front, (0, 0, 0), 0.2))
    poly(dr, [sw, nw, up(nw), up(sw)], left, mix(left, (0, 0, 0), 0.18))
    poly(dr, [se, ne, up(ne), up(se)], right, mix(right, (0, 0, 0), 0.22))
    # roof
    rc = roof_lt or mix(roof, (255, 255, 255), 0.2)
    poly(dr, [up(sw), up(se), up(ne), up(nw)], roof, mix(roof, (0, 0, 0), 0.25))
    # ridge highlight
    dr.line([up(sw), up(se)], fill=rgb(rc, 220), width=max(1, SCALE))
    dr.line([up(sw), up(nw)], fill=rgb(mix(rc, (255, 255, 255), 0.3), 160), width=1)
    if eave:
        # slight overhang lines
        dr.line([up(se), up(ne)], fill=rgb((0, 0, 0), 50), width=1)
        dr.line([up(nw), up(ne)], fill=rgb((0, 0, 0), 40), width=1)
    return {"sw": sw, "se": se, "nw": nw, "ne": ne, "up": up, "w": w, "d": d, "h": h}


def window(dr, vx, box, map_pt, size=(18, 16), lit=False):
    # map_pt on the south or east facade, z from ground
    # We'll place windows on the right (east/south-east) wall by default using view of a wall quad.
    pass


def draw_windows_right(img, vx, w, d, h, zs, xs, color, lit=False):
    """Windows on the visible right wall (SE-NE). xs in [0,1] along depth, zs height from ground."""
    dr = ImageDraw.Draw(img)
    for u in xs:
        for z, wh in zs:
            p0 = vx(w / 2, -d * u)
            # local right-wall: along -d and up
            p1 = vx(w / 2, -d * (u + 0.12))
            q = [
                (p0[0], p0[1] - z * SCALE),
                (p1[0], p1[1] - z * SCALE),
                (p1[0], p1[1] - (z + wh) * SCALE),
                (p0[0], p0[1] - (z + wh) * SCALE),
            ]
            fill = PAL["bus_win"] if not lit else (255, 210, 140)
            dr.polygon(q, fill=rgb(fill, 230))
            dr.line(q + [q[0]], fill=rgb(color, 200), width=1)


def draw_windows_left(img, vx, w, d, h, zs, xs, color, lit=False):
    dr = ImageDraw.Draw(img)
    for u in xs:
        for z, wh in zs:
            p0 = vx(-w / 2 + w * u, 0)
            p1 = vx(-w / 2 + w * (u + 0.14), 0)
            q = [
                (p0[0], p0[1] - z * SCALE),
                (p1[0], p1[1] - z * SCALE),
                (p1[0], p1[1] - (z + wh) * SCALE),
                (p0[0], p0[1] - (z + wh) * SCALE),
            ]
            fill = PAL["bus_win"] if not lit else (255, 210, 140)
            dr.polygon(q, fill=rgb(fill, 230))
            dr.line(q + [q[0]], fill=rgb(color, 200), width=1)


def door_south(img, vx, w, d, h, offset=0, width=28, height=40, color=(90, 70, 55), step=True):
    dr = ImageDraw.Draw(img)
    x0, x1 = offset - width / 2, offset + width / 2
    a = vx(x0, 0)
    b = vx(x1, 0)
    q = [a, b, (b[0], b[1] - height * SCALE), (a[0], a[1] - height * SCALE)]
    dr.polygon(q, fill=rgb(color))
    dr.line(q + [q[0]], fill=rgb(mix(color, (0, 0, 0), 0.3)), width=1)
    # glass
    g = [
        (lerp(q[0][0], q[3][0], 0.35), lerp(q[0][1], q[3][1], 0.35)),
        (lerp(q[1][0], q[2][0], 0.35), lerp(q[1][1], q[2][1], 0.35)),
        (lerp(q[1][0], q[2][0], 0.85), lerp(q[1][1], q[2][1], 0.85)),
        (lerp(q[0][0], q[3][0], 0.85), lerp(q[0][1], q[3][1], 0.85)),
    ]
    dr.polygon(g, fill=rgb((160, 190, 196), 200))


def house(variant: str) -> Image.Image:
    if variant == "a":
        w, d, h = 160, 128, 78
        roof, left, right = PAL["roof"], PAL["wall_l"], PAL["wall_r"]
    elif variant == "b":
        w, d, h = 144, 144, 86
        roof, left, right = (132, 96, 78), (236, 222, 204), (198, 178, 154)
    else:
        w, d, h = 128, 160, 80
        roof, left, right = (120, 108, 100), (224, 216, 204), (186, 176, 162)
    img, vx, _ = sprite_canvas(w, d, h + 8)
    draw_box(img, vx, w, d, h, roof, left, right, mix(roof, (255, 255, 255), 0.25))
    draw_windows_left(img, vx, w, d, h, [(28, 20)], [0.2, 0.55], mix(left, (0, 0, 0), 0.3))
    draw_windows_right(img, vx, w, d, h, [(30, 18)], [0.25, 0.6], mix(right, (0, 0, 0), 0.3))
    door_south(img, vx, w, d, h, offset=10 if variant != "c" else -8)
    return img


def convenience() -> Image.Image:
    w, d, h = 224, 176, 96
    img, vx, _ = sprite_canvas(w, d, h + 16)
    box = draw_box(img, vx, w, d, h, PAL["shop_roof"], PAL["shop_l"], PAL["shop_r"], (110, 170, 120))
    dr = ImageDraw.Draw(img)
    # green fascia on south wall
    sw, se = box["sw"], box["se"]
    z0, z1 = 52, 78
    fascia = [
        (sw[0], sw[1] - z0 * SCALE),
        (se[0], se[1] - z0 * SCALE),
        (se[0], se[1] - z1 * SCALE),
        (sw[0], sw[1] - z1 * SCALE),
    ]
    dr.polygon(fascia, fill=rgb(PAL["shop_stripe"]))
    # white band under fascia
    band = [
        (sw[0], sw[1] - 44 * SCALE),
        (se[0], se[1] - 44 * SCALE),
        (se[0], se[1] - 52 * SCALE),
        (sw[0], sw[1] - 52 * SCALE),
    ]
    dr.polygon(band, fill=rgb((250, 250, 244)))
    # two large store windows + automatic door
    draw_windows_left(img, vx, w, d, h, [(16, 36)], [0.08, 0.55], (80, 80, 80))
    door_south(img, vx, w, d, h, offset=0, width=36, height=42, color=(70, 90, 96))
    # awning
    aw0 = vx(-w / 2, 8)
    aw1 = vx(w / 2, 8)
    awning = [
        (aw0[0], aw0[1] - 48 * SCALE),
        (aw1[0], aw1[1] - 48 * SCALE),
        (aw1[0], aw1[1] - 58 * SCALE),
        (aw0[0], aw0[1] - 58 * SCALE),
    ]
    dr.polygon(awning, fill=rgb((240, 240, 236), 230))
    return img


def grocery() -> Image.Image:
    w, d, h = 208, 160, 90
    img, vx, _ = sprite_canvas(w, d, h + 12)
    draw_box(img, vx, w, d, h, PAL["groc_roof"], PAL["groc_l"], PAL["groc_r"])
    dr = ImageDraw.Draw(img)
    # noren-like dark stripe, no letters
    sw, se = vx(-w / 2, 0), vx(w / 2, 0)
    stripe = [
        (sw[0], sw[1] - 46 * SCALE),
        (se[0], se[1] - 46 * SCALE),
        (se[0], se[1] - 62 * SCALE),
        (sw[0], sw[1] - 62 * SCALE),
    ]
    dr.polygon(stripe, fill=rgb((92, 54, 48)))
    # hanging flaps
    for u in (0.15, 0.35, 0.55, 0.75):
        a = (lerp(stripe[0][0], stripe[1][0], u), lerp(stripe[0][1], stripe[1][1], u))
        b = (lerp(stripe[0][0], stripe[1][0], u + 0.12), lerp(stripe[0][1], stripe[1][1], u + 0.12))
        dr.polygon([a, b, (b[0], b[1] + 10 * SCALE), (a[0], a[1] + 10 * SCALE)], fill=rgb((110, 64, 56)))
    door_south(img, vx, w, d, h, offset=-16, color=(86, 60, 44))
    draw_windows_left(img, vx, w, d, h, [(20, 22)], [0.62], (80, 60, 50))
    return img


def warehouse() -> Image.Image:
    w, d, h = 288, 192, 108
    img, vx, _ = sprite_canvas(w, d, h + 12)
    draw_box(img, vx, w, d, h, PAL["ware_roof"], PAL["ware_l"], PAL["ware_r"], (130, 144, 154))
    # big cargo door
    door_south(img, vx, w, d, h, offset=0, width=70, height=58, color=(70, 80, 88))
    draw_windows_right(img, vx, w, d, h, [(50, 14)], [0.2, 0.45, 0.7], (60, 70, 76))
    # ridge vent
    dr = ImageDraw.Draw(img)
    a, b = vx(-20, -d / 2), vx(20, -d / 2)
    dr.line([(a[0], a[1] - (h + 6) * SCALE), (b[0], b[1] - (h + 6) * SCALE)], fill=rgb((70, 80, 88)), width=3)
    return img


def shrine() -> Image.Image:
    w, d, h = 88, 88, 70
    img, vx, _ = sprite_canvas(w, d, h + 36, pad=24)
    # raised floor
    draw_box(img, vx, w, d, 16, (140, 100, 70), (210, 80, 70), (170, 60, 54))
    # upper hall set back
    def vx2(x, y, up=0):
        return vx(x, y - 8, up)

    # peaked roof: extra triangles
    draw_box(img, vx, w * 0.86, d * 0.86, h, (90, 40, 36), (230, 226, 214), (200, 190, 176))
    dr = ImageDraw.Draw(img)
    # steep gable on top of roof
    sw, se, nw, ne = vx(-w * 0.5, 0), vx(w * 0.5, 0), vx(-w * 0.5, -d), vx(w * 0.5, -d)
    peak = ((nw[0] + ne[0]) / 2, ((nw[1] + ne[1]) / 2) - (h + 28) * SCALE)
    dr.polygon([ (sw[0], sw[1] - h * SCALE), (se[0], se[1] - h * SCALE), peak], fill=rgb((110, 48, 42)))
    dr.polygon([ (se[0], se[1] - h * SCALE), (ne[0], ne[1] - h * SCALE), peak], fill=rgb((86, 36, 34)))
    door_south(img, vx, w * 0.86, d, h, width=22, height=32, color=(80, 30, 28))
    return img


def bike_shelter() -> Image.Image:
    w, d, h = 128, 80, 36
    img, vx, _ = sprite_canvas(w, d, h + 8)
    # thin posts + roof only
    dr = ImageDraw.Draw(img)
    for x, y in ((-w / 2 + 8, 0), (w / 2 - 8, 0), (-w / 2 + 8, -d), (w / 2 - 8, -d)):
        p = vx(x, y)
        dr.line([p, (p[0], p[1] - h * SCALE)], fill=rgb((90, 90, 86)), width=3)
    draw_box(img, vx, w, d, 10, (140, 120, 96), (200, 190, 170), (170, 160, 144))
    # bikes underneath
    for ox in (-30, 8, 40):
        p = vx(ox, -10)
        dr.ellipse((p[0] - 7, p[1] - 7, p[0] + 3, p[1] + 3), outline=rgb((50, 50, 52)), width=2)
        dr.ellipse((p[0] + 8, p[1] - 5, p[0] + 18, p[1] + 5), outline=rgb((50, 50, 52)), width=2)
        dr.line((p[0] - 2, p[1] - 2, p[0] + 10, p[1] - 14), fill=rgb((50, 50, 52)), width=2)
    return img


def tram_stop() -> Image.Image:
    w, d, h = 140, 56, 62
    img, vx, _ = sprite_canvas(w, d, h + 8, pad=20)
    dr = ImageDraw.Draw(img)
    sw, se, nw, ne = vx(-w / 2, 0), vx(w / 2, 0), vx(-w / 2, -d), vx(w / 2, -d)
    poly(dr, [sw, se, ne, nw], (198, 198, 190), (130, 130, 124))
    # posts
    for x, y in ((-w / 2 + 14, -6), (w / 2 - 14, -6), (-w / 2 + 14, -d + 6), (w / 2 - 14, -d + 6)):
        a = vx(x, y)
        dr.line([a, (a[0], a[1] - h * SCALE)], fill=rgb((90, 96, 100)), width=4)
    # glass back
    a, b = vx(-w / 2 + 10, -d + 4), vx(w / 2 - 10, -d + 4)
    dr.polygon(
        [a, b, (b[0], b[1] - (h - 8) * SCALE), (a[0], a[1] - (h - 8) * SCALE)],
        fill=rgb((180, 210, 220, 140)),
    )
    # canopy at the top (thin iso slab)
    z = h
    cap_h = 8
    csw, cse, cnw, cne = vx(-w / 2 - 6, 4), vx(w / 2 + 6, 4), vx(-w / 2 - 6, -d - 4), vx(w / 2 + 6, -d - 4)
    up = lambda p: (p[0], p[1] - z * SCALE)
    up2 = lambda p: (p[0], p[1] - (z + cap_h) * SCALE)
    poly(dr, [up(csw), up(cse), up2(cse), up2(csw)], (210, 214, 216), (120, 124, 128))
    poly(dr, [up(cse), up(cne), up2(cne), up2(cse)], (180, 186, 190), (110, 114, 118))
    poly(dr, [up2(csw), up2(cse), up2(cne), up2(cnw)], (96, 102, 108), (70, 74, 78))
    # sign, abstract
    s = vx(0, 10)
    dr.rounded_rectangle(
        (s[0] - 14 * SCALE, s[1] - (h + 6) * SCALE, s[0] + 14 * SCALE, s[1] - (h - 10) * SCALE),
        radius=3,
        fill=rgb((70, 90, 110)),
    )
    return img


def vending(color: str) -> Image.Image:
    w, d, h = 26, 20, 44
    body_l = (200, 70, 62) if color == "red" else (62, 96, 168)
    body_r = mix(body_l, (0, 0, 0), 0.2)
    img, vx, _ = sprite_canvas(w, d, h, pad=12)
    draw_box(img, vx, w, d, h, (50, 54, 58), body_l, body_r)
    dr = ImageDraw.Draw(img)
    a, b = vx(-8, 0), vx(8, 0)
    pane = [(a[0], a[1] - 16 * SCALE), (b[0], b[1] - 16 * SCALE), (b[0], b[1] - 34 * SCALE), (a[0], a[1] - 34 * SCALE)]
    dr.polygon(pane, fill=rgb((140, 190, 210), 220))
    # buttons
    c = vx(0, 0)
    dr.rectangle((c[0] + 2, c[1] - 14 * SCALE, c[0] + 8, c[1] - 8 * SCALE), fill=rgb((40, 40, 42)))
    return img


def lamp() -> Image.Image:
    img = Image.new("RGBA", (48 * SCALE, 90 * SCALE), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    cx, foot = img.width / 2, img.height - 4 * SCALE
    dr.line((cx, foot, cx, 18 * SCALE), fill=rgb((90, 94, 98)), width=3 * SCALE // 1)
    # arm
    dr.line((cx, 22 * SCALE, cx + 10 * SCALE, 16 * SCALE), fill=rgb((90, 94, 98)), width=2)
    # lantern
    lx, ly = cx + 10 * SCALE, 12 * SCALE
    dr.ellipse((lx - 7 * SCALE, ly - 8 * SCALE, lx + 7 * SCALE, ly + 6 * SCALE), fill=rgb((232, 196, 120)))
    dr.ellipse((lx - 4 * SCALE, ly - 5 * SCALE, lx + 4 * SCALE, ly + 3 * SCALE), fill=rgb((255, 230, 170)))
    # base
    dr.rectangle((cx - 5 * SCALE, foot - 4 * SCALE, cx + 5 * SCALE, foot), fill=rgb((70, 74, 78)))
    global LAST_FOOT
    LAST_FOOT = (cx, foot)
    return img


def tree() -> Image.Image:
    img = Image.new("RGBA", (96 * SCALE, 110 * SCALE), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    cx, foot = img.width / 2, img.height - 6 * SCALE
    dr.rectangle((cx - 4 * SCALE, foot - 22 * SCALE, cx + 4 * SCALE, foot), fill=rgb((96, 70, 48)))
    # canopy layers
    for i, (dx, dy, r, c) in enumerate(
        [
            (0, -44, 28, (62, 114, 70)),
            (-12, -36, 20, (80, 132, 80)),
            (12, -34, 18, (52, 100, 62)),
            (0, -54, 16, (74, 126, 78)),
        ]
    ):
        x, y = cx + dx * SCALE, foot + dy * SCALE
        dr.ellipse((x - r * SCALE, y - r * SCALE * 0.7, x + r * SCALE, y + r * SCALE * 0.55), fill=rgb(c))
    global LAST_FOOT
    LAST_FOOT = (cx, foot)
    return img


def make_bike() -> Image.Image:
    img = Image.new("RGBA", (44 * SCALE, 28 * SCALE), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    s = SCALE
    # two wheels in 3/4
    dr.ellipse((2 * s, 12 * s, 16 * s, 26 * s), outline=rgb((40, 40, 44)), width=2)
    dr.ellipse((24 * s, 12 * s, 38 * s, 26 * s), outline=rgb((40, 40, 44)), width=2)
    dr.line((9 * s, 19 * s, 20 * s, 8 * s), fill=rgb((40, 40, 44)), width=2)
    dr.line((20 * s, 8 * s, 31 * s, 19 * s), fill=rgb((40, 40, 44)), width=2)
    dr.line((20 * s, 8 * s, 20 * s, 4 * s), fill=rgb((40, 40, 44)), width=2)
    dr.line((16 * s, 4 * s, 26 * s, 4 * s), fill=rgb((50, 50, 54)), width=2)
    global LAST_FOOT
    LAST_FOOT = (img.width * 0.5, img.height - 2 * s)
    return img


def stone_bridge() -> Image.Image:
    # Canal is 96 map units wide; deck follows the 128-deep EW road.
    w, d, h = 128, 136, 22
    drop = 34
    img, vx, _ = sprite_canvas(w, d, h + drop, pad=24)
    dr = ImageDraw.Draw(img)
    sw, se, nw, ne = vx(-w / 2, 0), vx(w / 2, 0), vx(-w / 2, -d), vx(w / 2, -d)
    # piers / side walls hanging into the canal
    poly(dr, [sw, se, (se[0], se[1] + drop * SCALE), (sw[0], sw[1] + drop * SCALE)], (150, 148, 140), (96, 94, 88))
    poly(dr, [se, ne, (ne[0], ne[1] + drop * SCALE), (se[0], se[1] + drop * SCALE)], (128, 126, 120), (84, 82, 78))
    # arch opening on the south face
    mid = vx(0, 4)
    arch = []
    for i in range(17):
        u = i / 16.0 * 2 - 1
        p = vx(u * 48, 4)
        rise = (1 - u * u) * 26
        arch.append((p[0], mid[1] + (drop - rise) * SCALE))
    a0, a1 = vx(-48, 4), vx(48, 4)
    arch.append((a1[0], a1[1] + drop * SCALE))
    arch.append((a0[0], a0[1] + drop * SCALE))
    dr.polygon(arch, fill=rgb((54, 118, 132)))
    dr.line(arch[:17], fill=rgb((108, 106, 100)), width=3)
    # deck on top
    poly(dr, [sw, se, ne, nw], (176, 174, 166), (118, 116, 108))
    # parapets
    for y, col in ((0, (158, 156, 148)), (-d, (132, 130, 124))):
        a, b = vx(-w / 2, y), vx(w / 2, y)
        poly(dr, [a, b, (b[0], b[1] - 14 * SCALE), (a[0], a[1] - 14 * SCALE)], col, (90, 88, 82))
        for u in (0.0, 0.25, 0.5, 0.75, 1.0):
            p = (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
            dr.rectangle((p[0] - 2, p[1] - 20 * SCALE, p[0] + 2, p[1] + 1), fill=rgb((130, 128, 120)))
    return img


def wood_bridge() -> Image.Image:
    w, d, h = 128, 64, 16
    img, vx, _ = sprite_canvas(w, d, h + 16, pad=16)
    dr = ImageDraw.Draw(img)
    sw, se, nw, ne = vx(-w / 2, 0), vx(w / 2, 0), vx(-w / 2, -d), vx(w / 2, -d)
    poly(dr, [sw, se, ne, nw], PAL["wood"], PAL["wood_dk"])
    # planks
    for i in range(8):
        u = i / 8
        a = (lerp(sw[0], se[0], u), lerp(sw[1], se[1], u))
        b = (lerp(nw[0], ne[0], u), lerp(nw[1], ne[1], u))
        dr.line([a, b], fill=rgb(PAL["wood_dk"], 160), width=1)
    # rails
    for y in (0, -d):
        a, b = vx(-w / 2, y), vx(w / 2, y)
        dr.line([(a[0], a[1] - 14 * SCALE), (b[0], b[1] - 14 * SCALE)], fill=rgb((110, 80, 50)), width=3)
        for u in (0, 0.5, 1):
            p = (lerp(a[0], b[0], u), lerp(a[1], b[1], u))
            dr.line([p, (p[0], p[1] - 14 * SCALE)], fill=rgb((110, 80, 50)), width=2)
    return img


def minibus() -> Image.Image:
    w, d, h = 168, 58, 50
    img, vx, _ = sprite_canvas(w, d, h + 10, pad=20)
    # body
    draw_box(img, vx, w, d, h, (176, 180, 184), PAL["bus"], PAL["bus_dk"], (220, 222, 224))
    dr = ImageDraw.Draw(img)
    # windshield on +x cab end (right wall)
    a, b = vx(w / 2, -4), vx(w / 2, -d + 4)
    glass = [
        (a[0] + 1, a[1] - 18 * SCALE),
        (b[0] + 1, b[1] - 18 * SCALE),
        (b[0] + 1, b[1] - 42 * SCALE),
        (a[0] + 1, a[1] - 42 * SCALE),
    ]
    dr.polygon(glass, fill=rgb(PAL["bus_win"], 230))
    dr.line(glass + [glass[0]], fill=rgb((80, 90, 100)), width=1)
    # side windows
    draw_windows_left(img, vx, w, d, h, [(22, 16)], [0.18, 0.38, 0.58], (90, 90, 92))
    # headlights
    for y in (-8, -d + 8):
        p = vx(w / 2 + 1, y)
        dr.ellipse((p[0] - 3, p[1] - 16 * SCALE, p[0] + 5, p[1] - 10 * SCALE), fill=rgb((255, 210, 120)))
    # wheels
    for x, y in ((-46, 8), (36, 8), (-46, -d - 6), (36, -d - 6)):
        p = vx(x, y)
        dr.ellipse((p[0] - 7, p[1] - 7, p[0] + 7, p[1] + 5), fill=rgb((36, 38, 42)))
        dr.ellipse((p[0] - 3, p[1] - 3, p[0] + 3, p[1] + 2), fill=rgb((70, 72, 76)))
    # amber roof lights
    for x in (-12, 12):
        p = vx(x, -d * 0.5)
        dr.ellipse((p[0] - 3, p[1] - (h + 3) * SCALE, p[0] + 3, p[1] - (h - 1) * SCALE), fill=rgb((220, 150, 60)))
    return img


def crate() -> Image.Image:
    w, d, h = 28, 22, 18
    img, vx, _ = sprite_canvas(w, d, h, pad=10)
    draw_box(img, vx, w, d, h, (150, 118, 70), (200, 164, 108), (168, 134, 86))
    return img


MANIFEST = {"scale": 1.0 / SCALE, "sprites": {}}


def save_sprite(rel: str, img: Image.Image):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    MANIFEST["sprites"][rel] = {
        "w": img.size[0],
        "h": img.size[1],
        "foot": [round(LAST_FOOT[0], 2), round(LAST_FOOT[1], 2)],
    }
    print("sprite", path.relative_to(ROOT), img.size, "foot", MANIFEST["sprites"][rel]["foot"])


def main():
    save_tile("grass", tile_grass())
    save_tile("sidewalk", tile_sidewalk())
    save_tile("road", tile_road())
    save_tile("road_ew", tile_road_dash_ew())
    save_tile("road_ns", tile_road_dash_ns())
    save_tile("crosswalk_ew", tile_crosswalk("ew"))
    save_tile("crosswalk_ns", tile_crosswalk("ns"))
    save_tile("canal", tile_canal())
    save_tile("bank", tile_bank())
    save_sprite("buildings/house_a.png", house("a"))
    save_sprite("buildings/house_b.png", house("b"))
    save_sprite("buildings/house_c.png", house("c"))
    save_sprite("buildings/convenience.png", convenience())
    save_sprite("buildings/grocery.png", grocery())
    save_sprite("buildings/warehouse.png", warehouse())
    save_sprite("buildings/shrine.png", shrine())
    save_sprite("props/bike_shelter.png", bike_shelter())
    save_sprite("props/tram_stop.png", tram_stop())
    save_sprite("props/vending_red.png", vending("red"))
    save_sprite("props/vending_blue.png", vending("blue"))
    save_sprite("props/lamp.png", lamp())
    save_sprite("props/tree.png", tree())
    save_sprite("props/bike.png", make_bike())
    save_sprite("props/stone_bridge.png", stone_bridge())
    save_sprite("props/wood_bridge.png", wood_bridge())
    save_sprite("props/bus.png", minibus())
    save_sprite("props/crate.png", crate())
    import json
    (ROOT / "manifest.json").write_text(json.dumps(MANIFEST, indent=2), encoding="utf-8")
    print("manifest written", len(MANIFEST["sprites"]))
    print("done")


if __name__ == "__main__":
    main()
