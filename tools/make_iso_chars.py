#!/usr/bin/env python3
"""Original 2:1 isometric Q-version characters for Blue Hour. Not AI.

A small procedural rig is projected with the same isometric camera as the
town (screen_x = x - y, screen_y = (x + y) / 2 - z). Faces are stamped as
2D decals so the result stays readable at field scale without becoming a
flat billboard.
"""
from __future__ import annotations

import argparse
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_CHARS = ROOT / "assets" / "iso" / "chars"
OUT_INFECTED = ROOT / "assets" / "infected_v1" / "normal"

# Output frames keep the existing atlas contracts.
SURVIVOR_FRAME = 256
SURVIVOR_FOOT = (128, 224)
ENEMY_FRAME = 288
ENEMY_FOOT = (144, 272)
INFECTED_SIZE = 1254
INFECTED_CELL = 1254 / 4.0
INFECTED_ROOTS = {
    "e": (160.0, 304.0),
    "se": (160.0, 292.0),
    "s": (157.0, 304.0),
    "ne": (157.0, 304.0),
    "n": (157.0, 302.0),
}

# Render 2x and downscale for a softer edge that matches town art.
SCALE_2X = 2

# World units: character stands at the origin, Z is up, +Y is facing.
# A 1.5-unit-tall Q-body becomes ~165 px in a 256 frame.
SX = 92.0  # pixels per world unit on the 1x frame (doubled while rendering)
SZ_RATIO = 1.85  # taller than true 2:1 so faces stay readable at field scale


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(round(v))))


def rgb(c, a=255):
    if isinstance(c, str):
        h = c.lstrip("#")
        t = tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))
        return t + (a,)
    if len(c) == 4:
        return c
    return tuple(c) + (a,)


def rot_z(theta):
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]], np.float32)


def rot_x(theta):
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]], np.float32)


def rot_y(theta):
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]], np.float32)


def look_basis(forward, up=np.array([0.0, 0.0, 1.0], np.float32)):
    f = forward / (np.linalg.norm(forward) + 1e-8)
    r = np.cross(up, f)
    if np.linalg.norm(r) < 1e-6:
        r = np.array([1.0, 0.0, 0.0], np.float32)
    r = r / (np.linalg.norm(r) + 1e-8)
    u = np.cross(f, r)
    u = u / (np.linalg.norm(u) + 1e-8)
    # Columns are local X (right), Y (forward), Z (up) in world space.
    return np.stack([r, f, u], axis=1).astype(np.float32)


@dataclass
class Primitive:
    center: np.ndarray
    radii: np.ndarray
    axes: np.ndarray  # 3x3, columns are local axes in world
    color: np.ndarray  # RGB 0-1
    shade: float = 1.0
    tag: str = "body"


@dataclass
class Character:
    key: str
    name: str
    gender: str
    # Palettes
    hair: tuple
    hair_dark: tuple
    hair_light: tuple
    skin: tuple
    skin_shadow: tuple
    blush: tuple
    eye_white: tuple = (248, 248, 252)
    iris: tuple = (60, 140, 170)
    iris_dark: tuple = (24, 60, 80)
    brow: tuple = (40, 44, 52)
    lip: tuple = (180, 110, 110)
    # Clothes
    top: tuple = (40, 60, 80)
    top_dark: tuple = (28, 40, 54)
    top_light: tuple = (70, 100, 120)
    inner: tuple = (80, 200, 210)
    bottom: tuple = (40, 46, 54)
    bottom_dark: tuple = (28, 32, 38)
    shoes: tuple = (32, 32, 36)
    shoe_accent: tuple = (70, 180, 190)
    accent: tuple = (80, 200, 210)
    outline: tuple = (32, 28, 30)
    # Body
    head_r: float = 0.28
    shoulder_w: float = 0.22
    chest_d: float = 0.13
    torso_h: float = 0.32
    hip_w: float = 0.18
    leg_r: float = 0.055
    arm_r: float = 0.042
    hunch: float = 0.0
    skirt: bool = False
    cape: bool = False
    # Hair / props
    style: str = "short_spike"
    zombie: bool = False
    bulk: float = 1.0
    lean: float = 1.0  # leg length scale


CHARACTERS = {
    "gu": Character(
        key="gu",
        name="顾予安",
        gender="male",
        hair=(168, 190, 214),
        hair_dark=(110, 130, 156),
        hair_light=(214, 228, 240),
        skin=(242, 214, 196),
        skin_shadow=(214, 176, 156),
        blush=(236, 168, 168),
        iris=(56, 150, 190),
        iris_dark=(20, 70, 100),
        brow=(90, 110, 130),
        lip=(196, 130, 130),
        top=(36, 58, 82),
        top_dark=(24, 38, 56),
        top_light=(56, 88, 118),
        inner=(70, 196, 210),
        bottom=(42, 50, 62),
        bottom_dark=(30, 36, 46),
        shoes=(28, 30, 36),
        shoe_accent=(64, 196, 210),
        accent=(70, 196, 210),
        style="short_spike",
    ),
    "xia": Character(
        key="xia",
        name="夏之遥",
        gender="female",
        hair=(176, 96, 64),
        hair_dark=(120, 58, 36),
        hair_light=(214, 150, 110),
        skin=(246, 220, 206),
        skin_shadow=(216, 178, 160),
        blush=(236, 160, 154),
        iris=(176, 110, 58),
        iris_dark=(96, 52, 24),
        brow=(120, 64, 40),
        lip=(210, 120, 120),
        top=(52, 78, 48),
        top_dark=(34, 52, 32),
        top_light=(86, 112, 70),
        inner=(236, 220, 186),
        bottom=(236, 222, 196),
        bottom_dark=(200, 178, 148),
        shoes=(92, 58, 40),
        shoe_accent=(150, 100, 70),
        accent=(232, 208, 120),
        style="wavy_bow",
        skirt=True,
        shoulder_w=0.20,
        hip_w=0.20,
    ),
    "lin": Character(
        key="lin",
        name="林知秋",
        gender="female",
        hair=(42, 40, 52),
        hair_dark=(24, 22, 32),
        hair_light=(78, 74, 90),
        skin=(244, 216, 200),
        skin_shadow=(214, 176, 156),
        blush=(232, 156, 150),
        iris=(150, 96, 52),
        iris_dark=(80, 46, 24),
        brow=(36, 32, 40),
        lip=(200, 118, 118),
        top=(196, 86, 70),
        top_dark=(150, 54, 44),
        top_light=(220, 120, 100),
        inner=(240, 224, 210),
        bottom=(46, 48, 58),
        bottom_dark=(32, 34, 42),
        shoes=(90, 56, 40),
        shoe_accent=(160, 100, 70),
        accent=(214, 186, 150),
        style="bob_beret",
        skirt=False,
        cape=True,
        shoulder_w=0.20,
        hip_w=0.18,
    ),
    "shen": Character(
        key="shen",
        name="沈听澜",
        gender="female",
        hair=(118, 86, 150),
        hair_dark=(72, 50, 100),
        hair_light=(168, 136, 196),
        skin=(246, 222, 212),
        skin_shadow=(214, 180, 168),
        blush=(230, 160, 170),
        iris=(130, 90, 170),
        iris_dark=(64, 40, 96),
        brow=(72, 50, 100),
        lip=(200, 124, 140),
        top=(48, 42, 62),
        top_dark=(32, 28, 44),
        top_light=(86, 76, 110),
        inner=(210, 196, 220),
        bottom=(186, 176, 204),
        bottom_dark=(140, 130, 164),
        shoes=(30, 28, 36),
        shoe_accent=(80, 70, 100),
        accent=(200, 196, 214),
        style="long_pony",
        skirt=True,
        cape=True,
        shoulder_w=0.20,
        hip_w=0.20,
    ),
    "lu": Character(
        key="lu",
        name="陆景川",
        gender="male",
        hair=(150, 74, 48),
        hair_dark=(96, 42, 26),
        hair_light=(196, 120, 80),
        skin=(240, 206, 180),
        skin_shadow=(208, 164, 136),
        blush=(220, 150, 130),
        iris=(196, 140, 50),
        iris_dark=(110, 70, 20),
        brow=(96, 48, 28),
        lip=(180, 110, 100),
        top=(196, 140, 48),
        top_dark=(150, 100, 32),
        top_light=(222, 176, 80),
        inner=(236, 210, 150),
        bottom=(52, 78, 128),
        bottom_dark=(36, 54, 90),
        shoes=(86, 54, 36),
        shoe_accent=(140, 96, 60),
        accent=(220, 180, 70),
        style="curly_goggles",
        shoulder_w=0.24,
    ),
    "normal": Character(
        key="normal",
        name="普通感染者",
        gender="none",
        hair=(48, 52, 46),
        hair_dark=(28, 32, 28),
        hair_light=(70, 74, 64),
        skin=(132, 148, 120),
        skin_shadow=(96, 110, 88),
        blush=(110, 100, 90),
        iris=(40, 48, 36),
        iris_dark=(20, 24, 18),
        brow=(36, 40, 34),
        lip=(90, 80, 72),
        top=(74, 78, 62),
        top_dark=(50, 54, 42),
        top_light=(96, 100, 80),
        inner=(150, 148, 130),
        bottom=(58, 62, 56),
        bottom_dark=(40, 44, 40),
        shoes=(40, 42, 38),
        shoe_accent=(50, 54, 48),
        accent=(70, 80, 64),
        outline=(22, 24, 20),
        style="zombie_mess",
        zombie=True,
        hunch=0.28,
        head_r=0.26,
        shoulder_w=0.23,
        lean=0.95,
    ),
    "rush": Character(
        key="rush",
        name="疾跑感染者",
        gender="none",
        hair=(44, 50, 48),
        hair_dark=(24, 28, 26),
        hair_light=(64, 70, 66),
        skin=(120, 140, 118),
        skin_shadow=(84, 100, 82),
        blush=(100, 96, 88),
        iris=(36, 46, 38),
        iris_dark=(16, 20, 16),
        brow=(30, 36, 32),
        lip=(80, 74, 68),
        top=(56, 62, 58),
        top_dark=(36, 42, 38),
        top_light=(78, 86, 80),
        inner=(110, 116, 108),
        bottom=(48, 54, 50),
        bottom_dark=(32, 36, 34),
        shoes=(34, 38, 36),
        shoe_accent=(46, 52, 48),
        accent=(64, 78, 70),
        outline=(20, 22, 20),
        style="zombie_mess",
        zombie=True,
        hunch=0.38,
        head_r=0.24,
        shoulder_w=0.18,
        chest_d=0.11,
        arm_r=0.036,
        leg_r=0.046,
        lean=1.08,
        torso_h=0.28,
    ),
    "heavy": Character(
        key="heavy",
        name="重型感染者",
        gender="none",
        hair=(40, 44, 40),
        hair_dark=(22, 26, 22),
        hair_light=(60, 64, 58),
        skin=(126, 138, 112),
        skin_shadow=(90, 100, 80),
        blush=(108, 100, 90),
        iris=(34, 40, 32),
        iris_dark=(16, 18, 14),
        brow=(30, 34, 28),
        lip=(86, 78, 70),
        top=(64, 68, 58),
        top_dark=(42, 46, 38),
        top_light=(88, 92, 78),
        inner=(128, 126, 110),
        bottom=(52, 56, 50),
        bottom_dark=(36, 40, 36),
        shoes=(36, 38, 34),
        shoe_accent=(50, 54, 48),
        accent=(70, 76, 64),
        outline=(20, 22, 18),
        style="zombie_mess",
        zombie=True,
        hunch=0.18,
        head_r=0.30,
        shoulder_w=0.32,
        chest_d=0.20,
        hip_w=0.26,
        arm_r=0.06,
        leg_r=0.075,
        bulk=1.35,
        torso_h=0.36,
        lean=0.9,
    ),
}


# ---------------------------------------------------------------------------
# Rig
# ---------------------------------------------------------------------------

def pose_params(action: int, zombie: bool, is_enemy_sheet: bool = False) -> dict:
    """Return joint angles / offsets for an atlas row."""
    # Survivor rows: 0 idle, 1-3 walk, 4 fire, 5 hit, 6 down
    # Enemy rows:    0 idle, 1-3 walk, 4 windup/recover, 5 attack, 6 hit, 7 down
    p = {
        "bob": 0.0,
        "leg_l": 0.0,
        "leg_r": 0.0,
        "arm_l": 0.12,
        "arm_r": 0.12,
        "knee_l": 0.15,
        "knee_r": 0.15,
        "spine": 0.0,
        "head_pitch": 0.0,
        "head_yaw": 0.0,
        "down": False,
        "hit": 0.0,
    }
    if action == 0:
        p["leg_l"], p["leg_r"] = -0.06, 0.06
        p["arm_l"], p["arm_r"] = 0.18, 0.10
        p["bob"] = 0.01
    elif action in (1, 2, 3):
        # 1 = left forward, 2 = pass, 3 = right forward
        phase = {1: 0.18, 2: 0.50, 3: 0.82}[action]
        swing = math.sin(phase * math.tau) * (0.55 if not zombie else 0.40)
        p["leg_l"] = swing
        p["leg_r"] = -swing
        p["arm_l"] = -swing * 0.7
        p["arm_r"] = swing * 0.7
        p["knee_l"] = 0.2 + max(0.0, -swing) * 0.5
        p["knee_r"] = 0.2 + max(0.0, swing) * 0.5
        p["bob"] = 0.03 if action == 2 else 0.01
        p["spine"] = swing * 0.08
    elif action == 4:
        if is_enemy_sheet:
            # windup / recover: lean back slightly
            p["spine"] = -0.20
            p["arm_l"] = p["arm_r"] = -0.55
            p["leg_l"], p["leg_r"] = -0.12, 0.18
        else:
            # fire: lean into the shot
            p["spine"] = 0.12
            p["arm_l"] = p["arm_r"] = -0.35
            p["leg_l"], p["leg_r"] = -0.10, 0.16
    elif action == 5:
        if is_enemy_sheet:
            # attack lunge
            p["spine"] = 0.35
            p["arm_l"] = p["arm_r"] = -0.85
            p["leg_l"], p["leg_r"] = 0.45, -0.25
            p["bob"] = 0.04
        else:
            # hit
            p["hit"] = 1.0
            p["spine"] = -0.28
            p["head_pitch"] = -0.2
            p["arm_l"], p["arm_r"] = 0.45, -0.2
            p["leg_l"], p["leg_r"] = -0.15, 0.20
    elif action == 6:
        if is_enemy_sheet:
            # hit
            p["hit"] = 1.0
            p["spine"] = -0.3
            p["head_pitch"] = -0.15
            p["arm_l"], p["arm_r"] = 0.5, -0.15
        else:
            p["down"] = True
    elif action == 7:
        p["down"] = True
    if zombie and not p["down"]:
        p["spine"] += 0.15
        p["head_pitch"] += 0.12
    return p


def world_from_local(origin, basis, local):
    return origin + basis @ np.asarray(local, np.float32)


def add_ellipsoid(parts, center, radii, axes, color, shade=1.0, tag="body"):
    parts.append(
        Primitive(
            center=np.asarray(center, np.float32),
            radii=np.asarray(radii, np.float32),
            axes=np.asarray(axes, np.float32),
            color=np.asarray(color, np.float32) / 255.0,
            shade=shade,
            tag=tag,
        )
    )


def add_capsule(parts, a, b, radius, color, shade=1.0, tag="body", flare=1.0):
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    d = b - a
    length = float(np.linalg.norm(d))
    if length < 1e-5:
        add_ellipsoid(parts, a, (radius, radius, radius), np.eye(3, dtype=np.float32), color, shade, tag)
        return
    mid = (a + b) * 0.5
    axes = look_basis(d)
    add_ellipsoid(parts, mid, (radius, length * 0.5 + radius * 0.15, radius * flare), axes, color, shade, tag)
    add_ellipsoid(parts, a, (radius * 0.95, radius * 0.95, radius * 0.95), np.eye(3, dtype=np.float32), color, shade, tag)
    add_ellipsoid(parts, b, (radius * 0.95, radius * 0.95, radius * 0.95), np.eye(3, dtype=np.float32), color, shade, tag)


def build_rig(ch: Character, facing: float, action: int, enemy_sheet: bool = False) -> tuple[list[Primitive], dict]:
    """Build world-space primitives. facing is map angle, 0 = east."""
    p = pose_params(action, ch.zombie, enemy_sheet)
    parts: list[Primitive] = []

    face_basis = look_basis(np.array([math.cos(facing), math.sin(facing), 0.0], np.float32))
    root = np.array([0.0, 0.0, 0.0], np.float32)
    # Fallen pose is applied as a post-transform after the standing rig is built.
    want_down = p["down"]
    if want_down:
        # Build as an idle body, then tip it over.
        p = pose_params(0, ch.zombie, enemy_sheet)

    # Spine
    hunch = ch.hunch + p["spine"]
    hip_z = 0.46 * ch.lean + p["bob"]
    if p["down"]:
        hip_z = 0.12
    hip = root + np.array([0.0, 0.0, hip_z], np.float32)
    # Hunch pitches the torso toward facing (forward, +Y local)
    spine_axis = rot_axis(face_basis[:, 0], hunch) @ face_basis
    chest = hip + spine_axis[:, 2] * (ch.torso_h * 0.55) + spine_axis[:, 1] * (hunch * 0.08)
    neck = chest + spine_axis[:, 2] * (ch.torso_h * 0.50)
    head_pitch = p["head_pitch"] + hunch * 0.3
    head_basis = rot_axis(spine_axis[:, 0], head_pitch) @ spine_axis
    if p["hit"]:
        # recoil opposite facing
        chest = chest - face_basis[:, 1] * 0.06
        neck = neck - face_basis[:, 1] * 0.08
    head_c = neck + head_basis[:, 2] * (ch.head_r * 0.85)

    # Torso
    torso_r = (
        ch.shoulder_w * 0.95 * ch.bulk,
        ch.chest_d * ch.bulk,
        ch.torso_h * 0.55,
    )
    add_ellipsoid(parts, chest, torso_r, spine_axis, ch.top, 1.0, "cloth")
    # Inner / hoodie lining peek
    add_ellipsoid(
        parts,
        chest + spine_axis[:, 1] * (ch.chest_d * 0.55) + spine_axis[:, 2] * 0.02,
        (ch.shoulder_w * 0.42, ch.chest_d * 0.40, ch.torso_h * 0.30),
        spine_axis,
        ch.inner,
        1.08,
        "cloth",
    )
    # Pelvis / hips
    add_ellipsoid(
        parts,
        hip,
        (ch.hip_w * ch.bulk, ch.chest_d * 0.85 * ch.bulk, 0.10),
        spine_axis,
        ch.bottom if not ch.skirt else ch.bottom,
        0.95,
        "cloth",
    )
    if ch.skirt:
        add_ellipsoid(
            parts,
            hip - spine_axis[:, 2] * 0.06 + spine_axis[:, 1] * 0.01,
            (ch.hip_w * 1.15, ch.chest_d * 1.05, 0.14),
            spine_axis,
            ch.bottom,
            1.0,
            "cloth",
        )
        add_ellipsoid(
            parts,
            hip - spine_axis[:, 2] * 0.14,
            (ch.hip_w * 1.25, ch.chest_d * 1.15, 0.10),
            spine_axis,
            ch.bottom_dark,
            0.9,
            "cloth",
        )

    if ch.cape:
        cape_col = ch.top if ch.key == "lin" else ch.top_dark
        add_ellipsoid(
            parts,
            chest - spine_axis[:, 1] * 0.10 + spine_axis[:, 2] * 0.02,
            (ch.shoulder_w * 1.15, 0.06, ch.torso_h * 0.7),
            spine_axis,
            cape_col,
            0.92,
            "cape",
        )
        add_ellipsoid(
            parts,
            hip - spine_axis[:, 1] * 0.12 - spine_axis[:, 2] * 0.02,
            (ch.hip_w * 1.2, 0.05, 0.16),
            spine_axis,
            cape_col,
            0.88,
            "cape",
        )

    # Legs
    thigh = 0.26 * ch.lean
    shin = 0.24 * ch.lean
    for side, swing, knee_bend, name in (
        (-1.0, p["leg_l"], p["knee_l"], "leg_l"),
        (1.0, p["leg_r"], p["knee_r"], "leg_r"),
    ):
        hip_j = hip + face_basis[:, 0] * (ch.hip_w * 0.55 * side) - spine_axis[:, 2] * 0.02
        thigh_dir = rot_axis(face_basis[:, 0], swing) @ (-face_basis[:, 2] * math.cos(0.05) + face_basis[:, 1] * math.sin(swing * 0.15))
        thigh_dir = thigh_dir / (np.linalg.norm(thigh_dir) + 1e-8)
        knee = hip_j + thigh_dir * thigh
        # knee bend toward back
        shin_dir = rot_axis(face_basis[:, 0], -knee_bend) @ thigh_dir
        ankle = knee + shin_dir * shin
        if p["down"]:
            ankle = hip_j + face_basis[:, 1] * (0.35 * side * 0.15 + 0.40) - face_basis[:, 2] * 0.02
            knee = (hip_j + ankle) * 0.5
        foot = ankle + np.array([0.0, 0.0, -0.02], np.float32)
        if not p["down"]:
            foot[2] = max(0.04, float(foot[2]))
        col = ch.bottom if not ch.skirt else ch.bottom_dark
        add_capsule(parts, hip_j, knee, ch.leg_r * 1.05 * ch.bulk, col, 0.95, "leg")
        add_capsule(parts, knee, ankle, ch.leg_r * 0.9 * ch.bulk, col, 0.9, "leg")
        # shoes: slightly elongated along facing
        shoe_axes = look_basis(face_basis[:, 1] + np.array([0, 0, 0.05], np.float32), face_basis[:, 2])
        add_ellipsoid(
            parts,
            foot + face_basis[:, 1] * 0.04,
            (ch.leg_r * 1.25, 0.09, 0.045),
            shoe_axes,
            ch.shoes,
            0.85,
            "shoe",
        )
        if not ch.zombie:
            add_ellipsoid(
                parts,
                foot + face_basis[:, 1] * 0.07,
                (ch.leg_r * 0.7, 0.04, 0.03),
                shoe_axes,
                ch.shoe_accent,
                1.0,
                "shoe",
            )

    # Arms
    upper_len, lower_len = 0.22, 0.20
    for side, swing, name in ((-1.0, p["arm_l"], "arm_l"), (1.0, p["arm_r"], "arm_r")):
        shoulder = chest + spine_axis[:, 0] * (ch.shoulder_w * 0.95 * side) + spine_axis[:, 2] * (ch.torso_h * 0.25)
        arm_dir = rot_axis(spine_axis[:, 0], swing) @ (
            -spine_axis[:, 2] * 0.75 + spine_axis[:, 1] * 0.2 + spine_axis[:, 0] * (0.15 * side)
        )
        arm_dir = arm_dir / (np.linalg.norm(arm_dir) + 1e-8)
        elbow = shoulder + arm_dir * upper_len
        hand = elbow + arm_dir * lower_len
        if p["down"]:
            hand = shoulder + face_basis[:, 1] * 0.15 - face_basis[:, 2] * 0.04
            elbow = (shoulder + hand) * 0.5
        add_capsule(parts, shoulder, elbow, ch.arm_r * ch.bulk, ch.top, 0.95, "arm")
        add_capsule(parts, elbow, hand, ch.arm_r * 0.88, ch.skin if not ch.zombie else ch.top_dark, 1.0, "arm")
        add_ellipsoid(parts, hand, (ch.arm_r * 1.1, ch.arm_r * 1.2, ch.arm_r * 1.0), face_basis, ch.skin, 1.0, "hand")

    # Head
    add_ellipsoid(parts, head_c, (ch.head_r * 0.95, ch.head_r * 0.90, ch.head_r * 1.02), head_basis, ch.skin, 1.05, "head")
    # Ears
    if not ch.zombie:
        for side in (-1.0, 1.0):
            ear = head_c + head_basis[:, 0] * (ch.head_r * 0.92 * side) + head_basis[:, 2] * 0.02
            add_ellipsoid(parts, ear, (0.04, 0.03, 0.055), head_basis, ch.skin, 0.95, "ear")

    add_hair(parts, ch, head_c, head_basis)
    add_props(parts, ch, head_c, head_basis, chest, spine_axis)

    if want_down:
        # Fall onto the right side; head stays toward the original facing.
        pivot = hip.copy()
        R = rot_axis(face_basis[:, 1], math.radians(88))
        def xf(v):
            return pivot + R @ (v - pivot)
        for prim in parts:
            prim.center = xf(prim.center)
            prim.axes = R @ prim.axes
        head_c = xf(head_c)
        head_basis = R @ head_basis
        neck = xf(neck)
        chest = xf(chest)
        hip = xf(hip)
        # Drop so the lowest primitive sits on the ground.
        min_z = min(float(pr.center[2] - max(pr.radii)) for pr in parts)
        lift = np.array([0.0, 0.0, 0.06 - min_z], np.float32)
        for prim in parts:
            prim.center = prim.center + lift
        head_c = head_c + lift
        neck = neck + lift
        chest = chest + lift
        hip = hip + lift

    anchors = {
        "head": head_c,
        "head_basis": head_basis,
        "face_basis": face_basis,
        "neck": neck,
        "chest": chest,
        "hip": hip,
        "down": want_down,
    }
    return parts, anchors


def rot_axis(axis, angle):
    axis = np.asarray(axis, np.float32)
    axis = axis / (np.linalg.norm(axis) + 1e-8)
    x, y, z = axis
    c, s = math.cos(angle), math.sin(angle)
    C = 1 - c
    return np.array(
        [
            [c + x * x * C, x * y * C - z * s, x * z * C + y * s],
            [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
            [z * x * C - y * s, z * y * C + x * s, c + z * z * C],
        ],
        np.float32,
    )


def add_hair(parts, ch: Character, head_c, hb):
    r = ch.head_r
    # Skull cap
    cap_y = 0.12 if ch.zombie else 0.28
    cap_back = 0.02 if ch.zombie else 0.08
    cap_z = 0.88 if ch.zombie else 0.72
    cap_d = 1.02 if ch.zombie else 0.92
    add_ellipsoid(
        parts,
        head_c + hb[:, 2] * (r * cap_y) - hb[:, 1] * (r * cap_back),
        (r * 1.04, r * cap_d, r * cap_z),
        hb,
        ch.hair,
        1.0,
        "hair",
    )
    if ch.zombie:
        # Full dark helmet so the skull doesn't flash a pale cap.
        add_ellipsoid(
            parts,
            head_c + hb[:, 2] * (r * 0.06) - hb[:, 1] * (r * 0.04),
            (r * 1.08, r * 1.06, r * 1.02),
            hb,
            ch.hair,
            0.95,
            "hair",
        )
    style = ch.style
    if style == "short_spike":
        # Ahoge
        tip = head_c + hb[:, 2] * (r * 1.35) + hb[:, 0] * 0.04 + hb[:, 1] * 0.02
        add_capsule(parts, head_c + hb[:, 2] * r, tip, 0.035, ch.hair, 1.05, "hair")
        for i, (yaw, pitch, length) in enumerate(
            [
                (-0.7, 0.15, 0.22),
                (-0.35, 0.35, 0.26),
                (0.0, 0.45, 0.24),
                (0.4, 0.30, 0.25),
                (0.75, 0.12, 0.20),
                (-1.0, -0.1, 0.18),
                (1.05, -0.05, 0.18),
                (0.2, -0.35, 0.16),
                (-0.2, -0.3, 0.16),
                (0.55, -0.2, 0.18),
            ]
        ):
            d = rot_axis(hb[:, 2], yaw) @ rot_axis(hb[:, 0], -pitch) @ hb[:, 2]
            root = head_c + d * (r * 0.7)
            end = root + d * length
            add_capsule(parts, root, end, 0.055 - i * 0.0015, ch.hair if i % 3 else ch.hair_light, 1.0, "hair")
        # Side-swept bangs, kept off the face.
        for side in (-0.7, -0.4, 0.4, 0.7):
            root = head_c + hb[:, 2] * (r * 0.55) + hb[:, 1] * (r * 0.55) + hb[:, 0] * (r * side * 0.85)
            end = root + hb[:, 0] * (0.06 * (1 if side > 0 else -1)) - hb[:, 2] * 0.10 + hb[:, 1] * 0.02
            add_capsule(parts, root, end, 0.045, ch.hair if abs(side) < 0.5 else ch.hair_dark, 0.95, "hair")
    elif style == "wavy_bow":
        for i, (yaw, pitch, length, rad) in enumerate(
            [
                (-1.1, 0.05, 0.32, 0.07),
                (-0.7, 0.25, 0.28, 0.075),
                (-0.3, 0.4, 0.26, 0.07),
                (0.2, 0.42, 0.24, 0.07),
                (0.7, 0.2, 0.30, 0.075),
                (1.15, 0.0, 0.34, 0.07),
                (-0.9, -0.25, 0.22, 0.06),
                (0.95, -0.25, 0.24, 0.06),
                (0.0, -0.15, 0.16, 0.06),
            ]
        ):
            d = rot_axis(hb[:, 2], yaw) @ rot_axis(hb[:, 0], -pitch) @ (hb[:, 2] * 0.6 + hb[:, 1] * 0.2)
            d = d / (np.linalg.norm(d) + 1e-8)
            root = head_c + d * (r * 0.65)
            end = root + d * length
            add_capsule(parts, root, end, rad, ch.hair if i % 2 == 0 else ch.hair_light, 1.0, "hair")
        # Side waves
        for side in (-1.0, 1.0):
            root = head_c + hb[:, 0] * (r * 0.85 * side) + hb[:, 2] * 0.02
            end = root + hb[:, 0] * (0.08 * side) - hb[:, 2] * 0.18 + hb[:, 1] * 0.04
            add_capsule(parts, root, end, 0.07, ch.hair, 0.95, "hair")
        # Side-swept bangs, kept off the face.
        for side in (-0.7, -0.35, 0.35, 0.7):
            root = head_c + hb[:, 2] * (r * 0.50) + hb[:, 1] * (r * 0.55) + hb[:, 0] * (r * side * 0.8)
            end = root + hb[:, 0] * (0.07 * (1 if side > 0 else -1)) - hb[:, 2] * 0.11
            add_capsule(parts, root, end, 0.05, ch.hair_dark if abs(side) < 0.5 else ch.hair, 0.95, "hair")
        # White bow on the right-back
        bow_c = head_c + hb[:, 0] * (r * 0.7) + hb[:, 2] * (r * 0.7) - hb[:, 1] * 0.05
        add_ellipsoid(parts, bow_c, (0.07, 0.03, 0.05), hb, (244, 236, 224), 1.15, "prop")
        add_ellipsoid(parts, bow_c + hb[:, 0] * 0.07, (0.06, 0.025, 0.045), hb, (244, 236, 224), 1.1, "prop")
    elif style == "bob_beret":
        for i, (yaw, pitch, length, rad) in enumerate(
            [
                (-1.0, 0.05, 0.16, 0.07),
                (-0.5, 0.25, 0.14, 0.07),
                (0.0, 0.3, 0.12, 0.07),
                (0.5, 0.25, 0.14, 0.07),
                (1.0, 0.05, 0.16, 0.07),
                (-1.15, -0.2, 0.14, 0.06),
                (1.15, -0.2, 0.14, 0.06),
            ]
        ):
            d = rot_axis(hb[:, 2], yaw) @ rot_axis(hb[:, 0], -pitch) @ hb[:, 2]
            root = head_c + d * (r * 0.6)
            end = root + d * length
            add_capsule(parts, root, end, rad, ch.hair, 1.0, "hair")
        # Short side bangs, forehead left open.
        for side in (-0.65, -0.35, 0.35, 0.65):
            root = head_c + hb[:, 2] * (r * 0.45) + hb[:, 1] * (r * 0.6) + hb[:, 0] * (r * side * 0.85)
            end = root + hb[:, 0] * (0.05 * (1 if side > 0 else -1)) - hb[:, 2] * 0.10
            add_capsule(parts, root, end, 0.042, ch.hair, 0.95, "hair")
        # Beret
        beret_c = head_c + hb[:, 2] * (r * 0.85) - hb[:, 1] * 0.02
        add_ellipsoid(parts, beret_c, (r * 1.15, r * 1.05, r * 0.38), hb, (214, 186, 150), 1.05, "prop")
        add_ellipsoid(
            parts,
            beret_c + hb[:, 0] * 0.12 + hb[:, 2] * 0.04,
            (0.10, 0.10, 0.05),
            hb,
            (198, 166, 128),
            1.0,
            "prop",
        )
        # Coral pin
        add_ellipsoid(
            parts,
            beret_c + hb[:, 0] * 0.10 + hb[:, 1] * 0.08,
            (0.035, 0.03, 0.03),
            hb,
            (200, 90, 70),
            1.2,
            "prop",
        )
    elif style == "long_pony":
        for i, (yaw, pitch, length, rad) in enumerate(
            [
                (-0.9, 0.2, 0.20, 0.06),
                (-0.4, 0.4, 0.18, 0.06),
                (0.2, 0.42, 0.16, 0.06),
                (0.7, 0.2, 0.20, 0.06),
                (-1.1, -0.15, 0.16, 0.055),
                (1.0, -0.1, 0.16, 0.055),
            ]
        ):
            d = rot_axis(hb[:, 2], yaw) @ rot_axis(hb[:, 0], -pitch) @ hb[:, 2]
            root = head_c + d * (r * 0.65)
            end = root + d * length
            add_capsule(parts, root, end, rad, ch.hair, 1.0, "hair")
        # Soft side bangs, eyes left clear.
        for side in (-0.7, -0.38, 0.38, 0.7):
            root = head_c + hb[:, 2] * (r * 0.48) + hb[:, 1] * (r * 0.55) + hb[:, 0] * (r * side * 0.8)
            end = root + hb[:, 0] * (0.06 * (1 if side > 0 else -1)) - hb[:, 2] * 0.11
            add_capsule(parts, root, end, 0.046, ch.hair_dark, 0.95, "hair")
        # Ponytail
        base = head_c - hb[:, 1] * (r * 0.55) + hb[:, 2] * (r * 0.55)
        add_ellipsoid(parts, base, (0.08, 0.08, 0.08), hb, ch.hair, 1.05, "hair")
        mid = base - hb[:, 1] * 0.10 - hb[:, 2] * 0.16
        tip = mid - hb[:, 1] * 0.06 - hb[:, 2] * 0.28
        add_capsule(parts, base, mid, 0.075, ch.hair, 1.0, "hair")
        add_capsule(parts, mid, tip, 0.065, ch.hair_light, 1.0, "hair")
        # Silver clip
        add_ellipsoid(parts, base + hb[:, 2] * 0.04 + hb[:, 0] * 0.02, (0.05, 0.03, 0.02), hb, (210, 214, 220), 1.2, "prop")
    elif style == "curly_goggles":
        for i, (yaw, pitch, length, rad) in enumerate(
            [
                (-1.0, 0.2, 0.20, 0.075),
                (-0.5, 0.4, 0.22, 0.08),
                (0.0, 0.5, 0.20, 0.08),
                (0.5, 0.4, 0.22, 0.08),
                (1.0, 0.15, 0.20, 0.075),
                (-1.15, -0.15, 0.16, 0.07),
                (1.15, -0.1, 0.16, 0.07),
                (0.25, -0.3, 0.14, 0.06),
                (-0.25, -0.28, 0.14, 0.06),
            ]
        ):
            d = rot_axis(hb[:, 2], yaw) @ rot_axis(hb[:, 0], -pitch) @ hb[:, 2]
            root = head_c + d * (r * 0.55)
            end = root + d * length
            add_ellipsoid(parts, end, (rad, rad * 0.85, rad), hb, ch.hair if i % 2 == 0 else ch.hair_light, 1.0, "hair")
            add_capsule(parts, root, end, rad * 0.7, ch.hair, 0.95, "hair")
        # Goggles on forehead
        gog = head_c + hb[:, 2] * (r * 0.55) + hb[:, 1] * (r * 0.35)
        add_ellipsoid(parts, gog + hb[:, 0] * 0.08, (0.07, 0.05, 0.05), hb, (50, 48, 46), 1.0, "prop")
        add_ellipsoid(parts, gog - hb[:, 0] * 0.08, (0.07, 0.05, 0.05), hb, (50, 48, 46), 1.0, "prop")
        add_ellipsoid(parts, gog + hb[:, 0] * 0.08, (0.045, 0.03, 0.03), hb, (120, 160, 180), 1.3, "prop")
        add_ellipsoid(parts, gog - hb[:, 0] * 0.08, (0.045, 0.03, 0.03), hb, (120, 160, 180), 1.3, "prop")
        add_capsule(parts, gog - hb[:, 0] * 0.08, gog + hb[:, 0] * 0.08, 0.018, (70, 68, 64), 1.0, "prop")
    elif style == "zombie_mess":
        for i, (yaw, pitch, length, rad) in enumerate(
            [
                (-0.8, 0.3, 0.22, 0.05),
                (-0.2, 0.5, 0.18, 0.05),
                (0.5, 0.35, 0.24, 0.055),
                (1.0, 0.05, 0.20, 0.045),
                (-1.1, -0.1, 0.16, 0.04),
                (0.2, -0.2, 0.12, 0.04),
            ]
        ):
            d = rot_axis(hb[:, 2], yaw) @ rot_axis(hb[:, 0], -pitch) @ hb[:, 2]
            root = head_c + d * (r * 0.5)
            end = root + d * length
            add_capsule(parts, root, end, rad, ch.hair if i % 2 == 0 else ch.hair_dark, 0.9, "hair")
        # No bald patch — keep a low, uneven dark cap only.


def add_props(parts, ch, head_c, hb, chest, spine):
    if ch.key == "lin":
        add_ellipsoid(
            parts,
            chest + spine[:, 2] * 0.14 + spine[:, 1] * 0.04,
            (0.10, 0.05, 0.05),
            spine,
            ch.inner,
            1.05,
            "cloth",
        )
    if ch.key == "gu":
        # Cyan hoodie collar / hood roll.
        add_ellipsoid(
            parts,
            chest + spine[:, 2] * 0.18 + spine[:, 1] * 0.02,
            (ch.shoulder_w * 0.7, 0.07, 0.06),
            spine,
            ch.inner,
            1.1,
            "cloth",
        )


# ---------------------------------------------------------------------------
# Rasterizer
# ---------------------------------------------------------------------------

# Toward the isometric camera (SE and slightly up). Matches screen bottom-front.
VIEW = np.array([1.0, 1.0, 0.85], np.float32)
VIEW = VIEW / np.linalg.norm(VIEW)
# Key light from the camera side (SE) and above, so faces looking at us stay lit.
LIGHT = np.array([0.45, 0.70, 1.05], np.float32)
LIGHT = LIGHT / np.linalg.norm(LIGHT)
FILL = np.array([-0.6, -0.2, 0.6], np.float32)
FILL = FILL / np.linalg.norm(FILL)


def project_point(p, sx, sz, ox, oy):
    return (
        ox + (p[0] - p[1]) * sx,
        oy + (p[0] + p[1]) * 0.5 * sx - p[2] * sz,
    )


class Buffer:
    def __init__(self, w: int, h: int, sx: float, sz: float, ox: float, oy: float):
        self.w, self.h = w, h
        self.sx, self.sz, self.ox, self.oy = sx, sz, ox, oy
        self.z = np.full((h, w), np.inf, np.float32)
        self.rgba = np.zeros((h, w, 4), np.float32)
        self.n = np.zeros((h, w, 3), np.float32)
        self.tag = np.zeros((h, w), np.int16)

    def draw_ellipsoid(self, prim: Primitive, tag_id: int = 1):
        # AABB in screen space from the 8 corners of the local box.
        corners = []
        for sx_ in (-1, 1):
            for sy_ in (-1, 1):
                for sz_ in (-1, 1):
                    local = np.array([sx_ * prim.radii[0], sy_ * prim.radii[1], sz_ * prim.radii[2]], np.float32)
                    corners.append(prim.center + prim.axes @ local)
        pts = [project_point(c, self.sx, self.sz, self.ox, self.oy) for c in corners]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        pad = 2
        x0 = max(0, int(math.floor(min(xs))) - pad)
        x1 = min(self.w, int(math.ceil(max(xs))) + pad)
        y0 = max(0, int(math.floor(min(ys))) - pad)
        y1 = min(self.h, int(math.ceil(max(ys))) + pad)
        if x1 <= x0 or y1 <= y0:
            return
        xs_g = np.arange(x0, x1, dtype=np.float32)
        ys_g = np.arange(y0, y1, dtype=np.float32)
        px, py = np.meshgrid(xs_g, ys_g)
        # Particular point on the ray at z=0
        inv_s = 1.0 / self.sx
        wx = ((px - self.ox) * inv_s + 2.0 * (py - self.oy) * inv_s) * 0.5
        wy = (2.0 * (py - self.oy) * inv_s - (px - self.ox) * inv_s) * 0.5
        # Ray: P(t) = P0 + t * VIEW, P0 = (wx, wy, 0)
        # But VIEW was normalized (1,1,-1); the unnormalized direction that
        # keeps screen coords fixed is (1,1,-1) only when sx == sz.
        # Use D = (1, 1, -sx/sz) which is exact, then parameter t.
        # Preimage of a pixel is (1, 1, sx/sz): SE and up, toward the
        # isometric camera (bottom of the screen, slightly above).
        dz = self.sx / self.sz
        D = np.array([1.0, 1.0, dz], np.float32)
        # Intersect ray with ellipsoid: (R^{-1} (P - C)) · same = 1
        # Transform into unit-sphere space.
        axes_t = prim.axes.T  # world -> local
        inv_r = 1.0 / prim.radii
        # P0 - C
        p0x = wx - prim.center[0]
        p0y = wy - prim.center[1]
        p0z = 0.0 - prim.center[2]
        # local(P0-C)
        l0x = axes_t[0, 0] * p0x + axes_t[0, 1] * p0y + axes_t[0, 2] * p0z
        l0y = axes_t[1, 0] * p0x + axes_t[1, 1] * p0y + axes_t[1, 2] * p0z
        l0z = axes_t[2, 0] * p0x + axes_t[2, 1] * p0y + axes_t[2, 2] * p0z
        # local(D)
        ldx = axes_t[0, 0] * D[0] + axes_t[0, 1] * D[1] + axes_t[0, 2] * D[2]
        ldy = axes_t[1, 0] * D[0] + axes_t[1, 1] * D[1] + axes_t[1, 2] * D[2]
        ldz = axes_t[2, 0] * D[0] + axes_t[2, 1] * D[1] + axes_t[2, 2] * D[2]
        # scale by inv radii
        o = np.stack([l0x * inv_r[0], l0y * inv_r[1], l0z * inv_r[2]], axis=-1)
        d = np.array([ldx * inv_r[0], ldy * inv_r[1], ldz * inv_r[2]], np.float32)
        a = float(d @ d)
        b = 2.0 * (o @ d)
        c = np.sum(o * o, axis=-1) - 1.0
        disc = b * b - 4.0 * a * c
        hit = disc >= 0.0
        if not np.any(hit):
            return
        sqrt = np.zeros_like(disc)
        sqrt[hit] = np.sqrt(disc[hit])
        t0 = (-b - sqrt) / (2.0 * a)
        t1 = (-b + sqrt) / (2.0 * a)
        # D goes SE and up, toward the camera. The closer surface is the larger t.
        t = np.where(t0 > t1, t0, t1)
        valid = hit
        zslice = self.z[y0:y1, x0:x1]
        closer = valid & ((-t) < zslice)
        if not np.any(closer):
            return
        # World point and normal
        pw_x = wx + t * D[0]
        pw_y = wy + t * D[1]
        pw_z = 0.0 + t * D[2]
        # local normal = (P_local / radii) / radii, then to world
        lx = l0x + t * ldx
        ly = l0y + t * ldy
        lz = l0z + t * ldz
        nlx = (lx * inv_r[0]) * inv_r[0]
        nly = (ly * inv_r[1]) * inv_r[1]
        nlz = (lz * inv_r[2]) * inv_r[2]
        nw = np.stack(
            [
                prim.axes[0, 0] * nlx + prim.axes[0, 1] * nly + prim.axes[0, 2] * nlz,
                prim.axes[1, 0] * nlx + prim.axes[1, 1] * nly + prim.axes[1, 2] * nlz,
                prim.axes[2, 0] * nlx + prim.axes[2, 1] * nly + prim.axes[2, 2] * nlz,
            ],
            axis=-1,
        )
        nn = np.linalg.norm(nw, axis=-1, keepdims=True) + 1e-8
        nw = nw / nn
        # Lighting
        ndl = np.clip(nw @ LIGHT, 0.0, 1.0)
        ndf = np.clip(nw @ FILL, 0.0, 1.0)
        # Toward the camera is along D (SE and up).
        cam = D / (np.linalg.norm(D) + 1e-8)
        ndv = np.clip(nw @ cam, 0.0, 1.0)
        # Cel + soft residual
        cel = np.where(ndl > 0.62, 1.0, np.where(ndl > 0.28, 0.78, np.where(ndl > 0.08, 0.58, 0.42)))
        soft = 0.55 * cel + 0.45 * (0.4 + 0.6 * ndl)
        rim = np.clip(1.0 - ndv, 0.0, 1.0) ** 2 * 0.18
        wrap = 0.12 * ndf
        shade = (soft + wrap + rim) * prim.shade
        col = prim.color[None, None, :] * shade[..., None]
        col = np.clip(col, 0.0, 1.0)
        rgba = self.rgba[y0:y1, x0:x1]
        nbuf = self.n[y0:y1, x0:x1]
        tbuf = self.tag[y0:y1, x0:x1]
        rgba[closer, :3] = col[closer]
        rgba[closer, 3] = 1.0
        zslice[closer] = -t[closer]
        nbuf[closer] = nw[closer]
        tbuf[closer] = tag_id

    def stamp_face(self, ch: Character, anchors: dict, tex: Image.Image):
        if anchors["down"]:
            return
        head_c = anchors["head"]
        hb = anchors["head_basis"]
        # Face center is on the front of the head, slightly below the equator.
        face_c = head_c + hb[:, 1] * (ch.head_r * 0.70) + hb[:, 2] * (-ch.head_r * 0.02)
        vis = float(np.dot(hb[:, 1], VIEW))
        if vis < 0.05:
            return
        # Project face axes
        # In 2D texture, +X is right, +Y is down. World right is hb[0], world up is hb[2].
        fr = ch.head_r * 0.95
        fu = ch.head_r * 1.05
        # Four corners of the face quad in world
        corners_w = [
            face_c - hb[:, 0] * fr + hb[:, 2] * fu,
            face_c + hb[:, 0] * fr + hb[:, 2] * fu,
            face_c + hb[:, 0] * fr - hb[:, 2] * fu,
            face_c - hb[:, 0] * fr - hb[:, 2] * fu,
        ]
        corners_s = [project_point(c, self.sx, self.sz, self.ox, self.oy) for c in corners_w]
        xs = [p[0] for p in corners_s]
        ys = [p[1] for p in corners_s]
        x0 = max(0, int(math.floor(min(xs))) - 1)
        x1 = min(self.w, int(math.ceil(max(xs))) + 1)
        y0 = max(0, int(math.floor(min(ys))) - 1)
        y1 = min(self.h, int(math.ceil(max(ys))) + 1)
        if x1 <= x0 or y1 <= y0:
            return
        # Bilinear inverse: use barycentric of two triangles (0-1-2 and 0-2-3)
        tex_a = np.array(tex, dtype=np.float32) / 255.0
        th, tw = tex_a.shape[0], tex_a.shape[1]
        uv_tri = [
            (np.array(corners_s[0]), np.array(corners_s[1]), np.array(corners_s[2]), (0.0, 0.0), (1.0, 0.0), (1.0, 1.0)),
            (np.array(corners_s[0]), np.array(corners_s[2]), np.array(corners_s[3]), (0.0, 0.0), (1.0, 1.0), (0.0, 1.0)),
        ]
        # Face should only write where we already hit the head (nearby z)
        # Approximate face plane t from face_c
        # t along D from P0 at z=0: not uniform. We'll accept pixels whose
        # current tag is head/hair/ear and whose z is close.
        px, py = np.meshgrid(np.arange(x0, x1, dtype=np.float32), np.arange(y0, y1, dtype=np.float32))
        pts = np.stack([px, py], axis=-1)
        uv = np.full((y1 - y0, x1 - x0, 2), -1.0, np.float32)
        for a, b, c, uva, uvb, uvc in uv_tri:
            v0 = b - a
            v1 = c - a
            v2 = pts - a
            den = v0[0] * v1[1] - v1[0] * v0[1]
            if abs(den) < 1e-6:
                continue
            inv = 1.0 / den
            s = (v2[..., 0] * v1[1] - v2[..., 1] * v1[0]) * inv
            t = (v0[0] * v2[..., 1] - v0[1] * v2[..., 0]) * inv
            inside = (s >= -0.01) & (t >= -0.01) & (s + t <= 1.01)
            uu = uva[0] + s * (uvb[0] - uva[0]) + t * (uvc[0] - uva[0])
            vv = uva[1] + s * (uvb[1] - uva[1]) + t * (uvc[1] - uva[1])
            uv[inside, 0] = uu[inside]
            uv[inside, 1] = vv[inside]
        valid = (uv[..., 0] >= 0.0) & (uv[..., 0] <= 1.0) & (uv[..., 1] >= 0.0) & (uv[..., 1] <= 1.0)
        if not np.any(valid):
            return
        tx = np.clip(uv[..., 0] * (tw - 1), 0, tw - 1)
        ty = np.clip(uv[..., 1] * (th - 1), 0, th - 1)
        x_i = np.floor(tx).astype(int)
        y_i = np.floor(ty).astype(int)
        fx = tx - x_i
        fy = ty - y_i
        x_j = np.clip(x_i + 1, 0, tw - 1)
        y_j = np.clip(y_i + 1, 0, th - 1)
        # Only sample valid pixels
        sample = np.zeros((y1 - y0, x1 - x0, 4), np.float32)
        yi, xi = np.where(valid)
        if len(yi) == 0:
            return
        def at(yy, xx):
            return tex_a[yy, xx]
        c00 = at(y_i[valid], x_i[valid])
        c10 = at(y_i[valid], x_j[valid])
        c01 = at(y_j[valid], x_i[valid])
        c11 = at(y_j[valid], x_j[valid])
        fxs = fx[valid][:, None]
        fys = fy[valid][:, None]
        samp = c00 * (1 - fxs) * (1 - fys) + c10 * fxs * (1 - fys) + c01 * (1 - fxs) * fys + c11 * fxs * fys
        full = np.zeros((y1 - y0, x1 - x0, 4), np.float32)
        full[valid] = samp
        head_mask = self.tag[y0:y1, x0:x1] >= 1
        fade = float(np.clip(0.15 + vis * 1.2, 0.0, 1.0))
        alpha = full[..., 3] * fade
        write = valid & head_mask & (alpha > 0.08)
        if not np.any(write):
            return
        dest = self.rgba[y0:y1, x0:x1]
        a = alpha[write][..., None]
        dest[write, :3] = dest[write, :3] * (1.0 - a) + full[write, :3] * a
        dest[write, 3] = np.maximum(dest[write, 3], alpha[write])

    def to_image(self, outline_color, outline=2) -> Image.Image:
        rgba = self.rgba.copy()
        alpha = rgba[:, :, 3]
        mask = alpha > 0.3
        if outline > 0 and np.any(mask):
            dil = mask.copy()
            for d in range(outline):
                up = np.roll(dil, -1, 0)
                dn = np.roll(dil, 1, 0)
                lf = np.roll(dil, -1, 1)
                rt = np.roll(dil, 1, 1)
                dil = dil | up | dn | lf | rt
            ring = dil & ~mask
            oc = np.array(outline_color, np.float32) / 255.0
            rgba[ring, :3] = oc
            rgba[ring, 3] = 1.0
        img = Image.fromarray(np.clip(rgba * 255.0, 0, 255).astype(np.uint8), "RGBA")
        return img


# ---------------------------------------------------------------------------
# Face textures
# ---------------------------------------------------------------------------

def make_face_texture(ch: Character, size: int = 256) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Soft face oval (only features; skin already comes from the 3D head)
    # We still paint a very soft skin glaze + blush so the decal can add cheeks.
    cx, cy = size // 2, int(size * 0.52)
    if not ch.zombie:
        # Blush
        for side in (-1, 1):
            bx = cx + side * int(size * 0.22)
            by = cy + int(size * 0.12)
            blush = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            bd = ImageDraw.Draw(blush)
            bd.ellipse((bx - 22, by - 12, bx + 22, by + 16), fill=rgb(ch.blush, 90))
            blush = blush.filter(ImageFilter.GaussianBlur(4))
            img = Image.alpha_composite(img, blush)
            d = ImageDraw.Draw(img)
    # Brows
    brow_y = cy - int(size * 0.20)
    for side in (-1, 1):
        x = cx + side * int(size * 0.16)
        w = 22 if not ch.zombie else 16
        d.line(
            [(x - side * w, brow_y + (2 if ch.zombie else 0)), (x + side * 6, brow_y - 3)],
            fill=rgb(ch.brow, 255),
            width=4 if not ch.zombie else 3,
        )
    # Eyes
    eye_y = cy - int(size * 0.04)
    eye_dx = int(size * 0.16)
    if ch.zombie:
        for side in (-1, 1):
            x = cx + side * eye_dx
            d.ellipse((x - 14, eye_y - 8, x + 14, eye_y + 10), fill=rgb((30, 36, 28), 255))
            d.ellipse((x - 7, eye_y - 3, x + 6, eye_y + 6), fill=rgb((70, 90, 50), 220))
            d.ellipse((x - 3, eye_y, x + 2, eye_y + 4), fill=rgb((12, 14, 10), 255))
    else:
        for side in (-1, 1):
            x = cx + side * eye_dx
            # White
            d.ellipse((x - 20, eye_y - 16, x + 20, eye_y + 18), fill=rgb(ch.eye_white, 255))
            # Iris
            d.ellipse((x - 13, eye_y - 10, x + 13, eye_y + 16), fill=rgb(ch.iris_dark, 255))
            d.ellipse((x - 11, eye_y - 8, x + 11, eye_y + 14), fill=rgb(ch.iris, 255))
            # Pupil
            d.ellipse((x - 6, eye_y - 2, x + 6, eye_y + 10), fill=rgb((20, 18, 22), 255))
            # Highlights
            d.ellipse((x + 1, eye_y - 6, x + 8, eye_y + 2), fill=rgb((255, 255, 255), 240))
            d.ellipse((x - 8, eye_y + 4, x - 4, eye_y + 8), fill=rgb((255, 255, 255), 200))
            # Upper lash
            d.arc((x - 21, eye_y - 18, x + 21, eye_y + 8), 200, 340, fill=rgb((28, 24, 30), 255), width=5)
            # Lower lash hint
            d.arc((x - 16, eye_y + 2, x + 16, eye_y + 18), 20, 160, fill=rgb((60, 44, 48), 180), width=2)
    # Nose (tiny)
    nx, ny = cx, cy + int(size * 0.10)
    d.ellipse((nx - 3, ny - 2, nx + 4, ny + 4), fill=rgb(ch.skin_shadow, 160 if not ch.zombie else 200))
    # Mouth
    mx, my = cx, cy + int(size * 0.22)
    if ch.zombie:
        d.arc((mx - 12, my - 6, mx + 12, my + 8), 20, 160, fill=rgb((70, 40, 36), 255), width=3)
        d.ellipse((mx - 8, my, mx + 8, my + 10), fill=rgb((40, 24, 22), 200))
    else:
        d.arc((mx - 10, my - 6, mx + 10, my + 8), 20, 160, fill=rgb(ch.lip, 255), width=3)
        d.arc((mx - 8, my - 5, mx + 8, my + 5), 30, 150, fill=rgb(mix(ch.lip, (255, 220, 220), 0.4), 200), width=2)
    img = img.filter(ImageFilter.GaussianBlur(0.4))
    return img


# ---------------------------------------------------------------------------
# Frame render
# ---------------------------------------------------------------------------


def fit_frame(img: Image.Image, foot: tuple[float, float], pad: int = 8) -> Image.Image:
    """Scale a finished frame around the foot so hair and limbs stay inside the cell."""
    bbox = img.getbbox()
    if not bbox:
        return img
    x0, y0, x1, y1 = bbox
    w, h = img.size
    fx, fy = foot

    def ratio(room: float, need: float) -> float:
        return 1.0 if need <= 0 else room / need

    scale = min(
        1.0,
        ratio(fx - pad, fx - x0) if x0 < pad else 1.0,
        ratio(w - pad - fx, x1 - fx) if x1 > w - pad else 1.0,
        ratio(fy - pad, fy - y0) if y0 < pad else 1.0,
        ratio(h - pad - fy, y1 - fy) if y1 > h - pad else 1.0,
    )
    if scale >= 0.999:
        return img
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    scaled = img.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(scaled, (int(round(fx - fx * scale)), int(round(fy - fy * scale))), scaled)
    return out


def render_character(
    ch: Character,
    facing: float,
    action: int,
    frame: int,
    foot: tuple[float, float],
    enemy_sheet: bool = False,
    face_tex: Image.Image | None = None,
) -> Image.Image:
    w = h = frame * SCALE_2X
    sx = SX * SCALE_2X
    sz = SX * SZ_RATIO * SCALE_2X
    ox = foot[0] * SCALE_2X
    oy = foot[1] * SCALE_2X
    buf = Buffer(w, h, sx, sz, ox, oy)
    parts, anchors = build_rig(ch, facing, action, enemy_sheet)
    # Draw back-to-front-ish but z-buffer handles order. Still, grouping is fine.
    for i, prim in enumerate(parts):
        tag = 2 if prim.tag in ("head", "hair", "ear") else 1
        buf.draw_ellipsoid(prim, tag)
    if face_tex is not None:
        buf.stamp_face(ch, anchors, face_tex)
    img = buf.to_image(ch.outline, outline=2)
    img = img.resize((frame, frame), Image.Resampling.LANCZOS)
    return fit_frame(img, foot, pad=8)


# Map octant 0..7, 0 = east, +45° each, to facing angle (same).
# The iso camera makes map-east appear down-right, etc.

def sheet_survivor(ch: Character, face_tex: Image.Image, left: bool) -> Image.Image:
    # RIGHT columns: 0 E, 1 SE, 2 S, 3 N, 4 NE  (existing MotionAtlas)
    # LEFT  columns: 0 W, 1 SW, 2 NW
    if left:
        octs = [4, 3, 5]  # W, SW, NW
        cols, rows = 3, 7
    else:
        octs = [0, 1, 2, 6, 7]  # E, SE, S, N, NE
        cols, rows = 5, 7
    canvas = Image.new("RGBA", (cols * SURVIVOR_FRAME, rows * SURVIVOR_FRAME), (0, 0, 0, 0))
    for r in range(rows):
        for c, octant in enumerate(octs):
            facing = octant * math.pi / 4.0
            fr = render_character(ch, facing, r, SURVIVOR_FRAME, SURVIVOR_FOOT, False, face_tex)
            canvas.paste(fr, (c * SURVIVOR_FRAME, r * SURVIVOR_FRAME), fr)
            print(f"  {ch.key} {'L' if left else 'R'} r{r} c{c} oct{octant}", flush=True)
    return canvas


def sheet_enemy_motion(ch: Character, face_tex: Image.Image) -> Image.Image:
    # 5 x 8 of 288. Columns: 0 E, 1 SE, 2 S, 3 N, 4 NE (flipped for W sides).
    octs = [0, 1, 2, 6, 7]
    cols, rows = 5, 8
    canvas = Image.new("RGBA", (cols * ENEMY_FRAME, rows * ENEMY_FRAME), (0, 0, 0, 0))
    for r in range(rows):
        for c, octant in enumerate(octs):
            facing = octant * math.pi / 4.0
            fr = render_character(ch, facing, r, ENEMY_FRAME, ENEMY_FOOT, True, face_tex)
            canvas.paste(fr, (c * ENEMY_FRAME, r * ENEMY_FRAME), fr)
            print(f"  {ch.key} r{r} c{c} oct{octant}", flush=True)
    return canvas


def infected_v1_sheet(ch: Character, face_tex: Image.Image, key: str) -> Image.Image:
    # 4x4 of 16 frames in a 1254 canvas. Directions are e, se, s, ne, n.
    facing = {"e": 0, "se": 1, "s": 2, "ne": 7, "n": 6}[key] * math.pi / 4.0
    root = INFECTED_ROOTS[key]
    canvas = Image.new("RGBA", (INFECTED_SIZE, INFECTED_SIZE), (0, 0, 0, 0))
    # Frame meanings: 0 idle, 1-6 walk, 7-9 attack, 10-11 hit, 12-15 death
    # Map to our action model with extra in-between walk poses.
    action_of = {
        0: 0,
        1: 1,
        2: 1,
        3: 2,
        4: 2,
        5: 3,
        6: 3,
        7: 5,  # attack
        8: 5,
        9: 4,  # recover / windup
        10: 6,  # hit (enemy sheet action 6)
        11: 6,
        12: 7,
        13: 7,
        14: 7,
        15: 7,
    }
    # Death progression uses offsets
    for frame in range(16):
        col, row = frame % 4, frame // 4
        action = action_of[frame]
        # Local foot inside a ~313 cell, with padding.
        # Render into a 320 square then paste, leaving a clear 3px border.
        cell = 313  # safe integer cell; 1-2px gap at the 1254 edge is ok
        # Use exact cell origin from the test math, but draw inside padding.
        origin_x = col * INFECTED_CELL
        origin_y = row * INFECTED_CELL
        foot = (root[0], root[1])
        fr = render_character(ch, facing, action, 320, (foot[0] * 320 / 313.0, foot[1] * 320 / 313.0), True, face_tex)
        # Death progression: rotate / flatten more for later frames
        if frame >= 12:
            angle = [15, 40, 70, 90][frame - 12]
            # Already down (action 7). Further flatten by scaling y slightly.
            fr = fr.resize((320, int(320 * (1.0 - 0.08 * (frame - 12)))), Image.Resampling.LANCZOS)
            pad = Image.new("RGBA", (320, 320), (0, 0, 0, 0))
            pad.paste(fr, (0, 320 - fr.size[1]), fr)
            fr = pad
        # Scale 320 -> place in cell, keep 4px padding
        target = 305
        fr = fr.resize((target, target), Image.Resampling.LANCZOS)
        # Position so the foot (which we designed at foot coords in 320, scaled)
        # lands on root. After resize 320->305, foot moves by 305/320.
        fx = foot[0] * 305 / 313.0
        fy = foot[1] * 305 / 313.0
        px = int(round(origin_x + root[0] - fx))
        py = int(round(origin_y + root[1] - fy))
        canvas.paste(fr, (px, py), fr)
        print(f"  infected {key} frame {frame}", flush=True)
    return canvas


def portrait(ch: Character, face_tex: Image.Image) -> Image.Image:
    # Facing the camera: map SE (octant 1). Full body in 256, head near the top.
    fr = render_character(ch, math.pi / 4.0, 0, SURVIVOR_FRAME, SURVIVOR_FOOT, False, face_tex)
    return fr


def write_import(path: Path, filter_nearest: bool = False):
    """Minimal Godot 4 texture import; uid is generated later if missing."""
    rel = path.as_posix()
    uid = "uid://" + "".join(f"{ord(c)%26:x}" for c in path.name[:8]) + path.name[-6:].encode().hex()[:8]
    # Let Godot regenerate a proper uid on import; this is a placeholder so
    # the editor has something if needed. We actually skip writing if we can
    # just run the importer.
    return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--who", default="gu,xia,lin,shen,lu")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()
    people = [s.strip() for s in args.who.split(",") if s.strip()]

    if args.preview:
        out = args.out or Path("/tmp/isochar")
        out.mkdir(parents=True, exist_ok=True)
        # Five facings of each requested character, idle + one walk, plus a row strip.
        for key in people:
            ch = CHARACTERS[key]
            face = make_face_texture(ch)
            face.save(out / f"{key}_face_tex.png")
            row = Image.new("RGBA", (256 * 8, 256), (40, 44, 52, 255))
            for octant in range(8):
                fr = render_character(ch, octant * math.pi / 4.0, 0, 256, SURVIVOR_FOOT, ch.zombie, face)
                fr.save(out / f"{key}_oct{octant}.png")
                row.paste(fr, (octant * 256, 0), fr)
            # walk SE
            walk = render_character(ch, math.pi / 4.0, 1, 256, SURVIVOR_FOOT, ch.zombie, face)
            walk.save(out / f"{key}_walk.png")
            down = render_character(ch, math.pi / 4.0, 7 if ch.zombie else 6, 256, SURVIVOR_FOOT, ch.zombie, face)
            down.save(out / f"{key}_down.png")
            row.save(out / f"{key}_turnaround.png")
            print("preview", key)
        return

    out_dir = OUT_CHARS
    out_dir.mkdir(parents=True, exist_ok=True)
    survivors = [k for k in people if k in ("gu", "xia", "lin", "shen", "lu")]
    for key in survivors:
        ch = CHARACTERS[key]
        face = make_face_texture(ch)
        right = sheet_survivor(ch, face, left=False)
        left = sheet_survivor(ch, face, left=True)
        right.save(out_dir / f"{key}_full.png")
        left.save(out_dir / f"{key}_left_full.png")
        portrait(ch, face).save(out_dir / f"{key}_portrait.png")
        print("saved", key)

    enemies = [k for k in people if k in ("normal", "rush", "heavy")]
    if "rush" in people or "heavy" in people or "normal" in people:
        for key in ("rush", "heavy", "normal"):
            if key not in people and key != "normal":
                continue
            if key not in people:
                continue
            ch = CHARACTERS[key]
            face = make_face_texture(ch)
            if key in ("rush", "heavy", "normal"):
                sheet = sheet_enemy_motion(ch, face)
                sheet.save(out_dir / f"{key}_full.png")
                print("saved motion", key)
        if "normal" in people:
            ch = CHARACTERS["normal"]
            face = make_face_texture(ch)
            OUT_INFECTED.mkdir(parents=True, exist_ok=True)
            for d in ("e", "se", "s", "ne", "n"):
                infected_v1_sheet(ch, face, d).save(OUT_INFECTED / f"{d}.png")
                print("saved infected", d)


if __name__ == "__main__":
    main()
