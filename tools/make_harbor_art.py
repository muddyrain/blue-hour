"""Original north-harbor SVGs, using the existing IsoAtlas foot/map convention.

Run with Python's standard library only. No AI imagery or third-party assets.
All faces use the same exact 2:1 projection as make_iso_buildings.py.
"""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/iso'
SPRITES = {}


def paint(color, name):
    if len(color) == 9 and color.startswith('#'):
        return f'{name}="{color[:7]}" {name}-opacity="{int(color[7:], 16)/255:.4f}"'
    return f'{name}="{color}"'


class Sprite:
    def __init__(self, w, d, h):
        self.w, self.d = w, d
        self.ox, self.oy = w / 2 + 24, (w / 2 + d) * .5 + h + 24
        self.width, self.height = (w + d + 48) * 2, (w / 2 + d / 2 + h + 48) * 2
        self.parts = []

    def p(self, x, y, z=0):
        return ((x - y + self.ox) * 2, ((x + y) * .5 - z + self.oy) * 2)

    def poly(self, points, fill, stroke='#484e4d', width=1):
        coords = ' '.join(f'{x:.2f},{y:.2f}' for x, y in [self.p(*p) for p in points])
        self.parts.append(f'<polygon points="{coords}" {paint(fill, "fill")} {paint(stroke, "stroke")} stroke-width="{width * 2}" stroke-linejoin="round"/>')

    def line(self, points, color='#627271', width=1):
        coords = ' '.join(f'{x:.2f},{y:.2f}' for x, y in [self.p(*p) for p in points])
        self.parts.append(f'<polyline points="{coords}" fill="none" {paint(color, "stroke")} stroke-width="{width * 2}" stroke-linecap="round" stroke-linejoin="round"/>')

    def box(self, x, y, w, d, h, color, z=0):
        def shade(factor):
            return '#' + ''.join(f'{min(255, round(int(color[i:i+2], 16) * factor)):02x}' for i in (1, 3, 5))
        self.poly([(x, y, z), (x+w, y, z), (x+w, y, z+h), (x, y, z+h)], shade(.85))
        self.poly([(x+w, y, z), (x+w, y-d, z), (x+w, y-d, z+h), (x+w, y, z+h)], shade(.69))
        self.poly([(x, y, z+h), (x+w, y, z+h), (x+w, y-d, z+h), (x, y-d, z+h)], color)

    def shadow(self):
        self.poly([(-self.w/2-5, 5), (self.w/2+10, 5), (self.w/2+10, -self.d+8), (-self.w/2-5, -self.d+8)], '#45483d22', 'none')

    def ring(self, x, y, z, r, color, width=2):
        self.line([(x+math.cos(a)*r, y+math.sin(a)*r, z) for a in [i*math.tau/24 for i in range(25)]], color, width)

    def save(self, name):
        rel = f'harbor/{name}.svg'
        dest = ART / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        body = ''.join(self.parts)
        dest.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width:g}" height="{self.height:g}" viewBox="0 0 {self.width:g} {self.height:g}">{body}</svg>\n', encoding='utf-8', newline='\n')
        SPRITES[rel] = {'w': self.width, 'h': self.height, 'foot': [self.ox*2, self.oy*2], 'map': [self.w, self.d]}


def container(name, color, stacked=False):
    s = Sprite(320, 128, 128 if stacked else 64)
    s.shadow()
    for level in range(2 if stacked else 1):
        x, y, z = -160 + level*12, -level*10, level*62
        s.box(x, y, 304, 112, 60, color, z)
        for i in range(1, 23):
            a = x + i*13
            s.line([(a, y, z+5), (a, y, z+55)], '#e0d8bb44', 1.5)
            s.line([(a, y, z+61), (a, y-110, z+61)], '#263d3e44', 1)
        for i in range(4):
            s.line([(x+305, y-7-i*29, z+5), (x+305, y-7-i*29, z+55)], '#d7d1b3', 1.5)
        s.line([(x+305, y-56, z+2), (x+305, y-56, z+58)], '#394a48', 2)
        for xx, yy in [(x, y), (x+304, y), (x+304, y-112), (x, y-112)]:
            s.box(xx-2, yy+2, 5, 5, 6, '#d4c7a7', z+55)
        s.poly([(x+22, y+.2, z+35), (x+56, y+.2, z+35), (x+56, y+.2, z+47), (x+22, y+.2, z+47)], '#e7dfc8', 'none')
    s.save(name)


def building(name, w, d, h, roof, wall, cold=False, office=False):
    s = Sprite(w, d, h+45)
    s.shadow()
    s.box(-w/2, 0, w, d, 7, '#8a8c84')
    s.box(-w/2, 0, w, d, h, wall, 7)
    if office:
        s.box(-w/2-6, 6, w+12, d+12, 8, roof, h+7)
    else:
        # Closed gable; no interior is present in the image or collision.
        z, ridge = h+8, h+40
        s.poly([(-w/2-6, 6, z), (w/2+6, 6, z), (w/2+6, -d/2, ridge), (-w/2-6, -d/2, ridge)], roof)
        s.poly([(-w/2-6, -d/2, ridge), (w/2+6, -d/2, ridge), (w/2+6, -d-6, z), (-w/2-6, -d-6, z)], '#66767a')
        s.poly([(w/2, 0, h+7), (w/2, -d, h+7), (w/2, -d/2, ridge-2)], wall)
        for i in range(1, int(w/16)):
            x = -w/2+i*16
            s.line([(x, 6, z+1), (x, -d/2, ridge+1), (x, -d-6, z+1)], '#d2ddd04c')
    for x in range(int(-w/2+16), int(w/2), 24):
        s.line([(x, 0, 9), (x, 0, h)], '#e6dfcc55')
    s.poly([(-36, 1, 7), (36, 1, 7), (36, 1, h-10), (-36, 1, h-10)], '#8eaaa8' if cold else '#6c7777')
    for z in range(13, h-10, 7):
        s.line([(-34, 2, z), (34, 2, z)], '#c7cbbf', .7)
    if cold:
        s.box(w/2-60, -d+42, 44, 30, 18, '#d9ded5', h+16)
        for x in range(int(w/2-55), int(w/2-20), 6):
            s.line([(x, -d+43, h+19), (x, -d+43, h+31)], '#879f9e')
        s.box(-w/2-12, -20, 12, 52, 28, '#9daea7', 12)
    for x in [-w/2+24, w/2-58]:
        s.poly([(x, 2, h-32), (x+30, 2, h-32), (x+30, 2, h-13), (x, 2, h-13)], '#9db8b6', '#e6e2cf', 2)
        s.line([(x+15, 3, h-32), (x+15, 3, h-13)], '#e6e2cf')
    # Blank sign panel: all location labels are supplied by Godot, never baked in.
    s.poly([(-39, 4, h-2), (39, 4, h-2), (39, 4, h+10), (-39, 4, h+10)], '#d5c9ab', '#627a78')
    s.save(name)


def props():
    s = Sprite(160, 160, 210)
    s.shadow()
    s.box(-48, 0, 96, 92, 14, '#b9b9a0')
    s.box(-18, -58, 36, 36, 126, '#698f91', 14)
    s.box(-34, -42, 68, 68, 28, '#c6b781', 140)
    s.box(-70, -66, 178, 18, 18, '#c6b781', 165)
    s.line([(-58, -74, 165), (-5, -74, 201), (99, -74, 165)], '#7c9089', 3)
    s.line([(99, -74, 170), (99, -74, 74)], '#555d58', 1.3)
    s.line([(94, -74, 76), (95, -74, 67), (103, -74, 64), (107, -74, 71)], '#d0c6a8', 3)
    s.save('crane')
    s = Sprite(96, 80, 70)
    s.shadow()
    for x in [-34, 25]:
        for y in [-12, -62]:
            s.box(x, y, 12, 12, 17, '#444f50', 2)
    s.box(-32, -8, 64, 58, 20, '#bda876', 15)
    s.box(-27, -34, 24, 28, 19, '#9da59c', 35)
    for x in [-25, 23]:
        s.line([(x, -24, 35), (x, -24, 68), (x, -62, 68), (x, -62, 35)], '#697e7b', 3)
    s.box(-29, -20, 60, 48, 4, '#8b9a8d', 69)
    for x in [-25, 19]:
        s.box(x, 22, 6, 32, 3, '#677474', 3)
        s.box(x, 0, 6, 5, 59, '#778988', 3)
    s.save('forklift')
    s = Sprite(80, 64, 25)
    s.shadow()
    for z in [0, 9, 18]:
        for x in [-36, 24]:
            s.box(x, 0, 12, 56, 5, '#9b825e', z)
        for y in [0, -18, -36, -54]:
            s.box(-38, y, 76, 7, 4, '#ba9e76', z+5)
    s.save('pallets')
    s = Sprite(72, 64, 24)
    s.shadow()
    for offset in range(0, 38, 6):
        s.line([(-32, -offset, 4), (-16, -offset-8, 14), (13, -offset+3, 18), (30, -offset-12, 5)], '#6b8d82', 2)
        s.line([(-30+offset, 0, 4), (-25+offset, -20, 20), (-30+offset, -56, 4)], '#a9b19a', 1)
    for x in [-24, 4, 26]:
        s.ring(x, -6, 11, 6, '#c7a576', 3)
    s.save('nets')
    s = Sprite(32, 32, 25)
    s.shadow()
    s.box(-12, 0, 24, 24, 5, '#959f94')
    s.box(-5, -7, 10, 10, 16, '#627373', 5)
    s.box(-13, -5, 26, 14, 5, '#788985', 20)
    s.ring(0, -10, 4, 13, '#a59370', 2)
    s.save('bollard')
    s = Sprite(40, 32, 40)
    s.shadow()
    for x in [-8, 9]:
        s.box(x-5, -4, 10, 16, 17, '#b67757', 1)
        s.box(x-4, -5, 8, 14, 10, '#e3d6b5', 18)
        s.ring(x, -12, 31, 3, '#8a8e7c')
    s.save('buoys')
    s = Sprite(48, 40, 36)
    s.shadow()
    for x, y in [(-18, -4), (3, -19)]:
        s.box(x, y, 18, 18, 31, '#859a92')
        for z in [6, 25]:
            s.line([(x, y, z), (x+18, y, z), (x+18, y-18, z)], '#c3c5b0', 1.5)
    s.save('barrels')
    s = Sprite(64, 48, 28)
    s.shadow()
    s.box(-28, 0, 56, 40, 22, '#8a9993')
    s.box(-30, 1, 60, 42, 5, '#d2c5a4', 22)
    s.box(-4, 2, 8, 3, 6, '#8e7759', 14)
    s.save('cargo')
    s = Sprite(48, 40, 114)
    s.box(-10, 0, 20, 20, 5, '#92988b')
    s.box(-2, -8, 4, 4, 101, '#687a76', 5)
    s.box(-14, -3, 28, 12, 6, '#a7aea0', 106)
    s.poly([(-11, -2, 105), (11, -2, 105), (11, -12, 105), (-11, -12, 105)], '#efe0b5', 'none')
    s.save('work_lamp')


def tile(name, color, metal=False, wood=False):
    # Tile texture spans a 32x32 map diamond, without sprite padding.
    parts = [f'<path d="M64 0 L128 32 L64 64 L0 32 Z" fill="{color}"/>']
    for i in range(1, 6):
        if metal or wood:
            y = i*10
            parts.append(f'<path d="M{64-y} {y/2} L{128-y} {32+y/2}" stroke="{"#87918d" if metal else "#796c55"}" stroke-width="1"/>')
        else:
            x = 25+i*11
            y = 24+(i%3)*6
            parts.append(f'<path d="M{x} {y} l12 -3 8 2" stroke="#8caeaf" stroke-opacity=".45" fill="none"/>')
    dest = ART / f'tiles/{name}.svg'
    dest.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="64" viewBox="0 0 128 64">'+''.join(parts)+'</svg>\n', encoding='utf-8', newline='\n')


def main():
    for name, color, stack in [('container_teal', '#779b99', True), ('container_clay', '#b47d65', False), ('container_blue', '#7d929e', True), ('container_cream', '#bcaf86', False)]:
        container(name, color, stack)
    building('fishery', 352, 240, 78, '#9f8c76', '#c1c4b4')
    building('cold_store', 384, 256, 88, '#a3b8b7', '#cbd4cc', cold=True)
    building('office', 192, 144, 66, '#79918c', '#d4cdb8', office=True)
    building('workshop', 256, 176, 74, '#927f6a', '#b4b8a4')
    props()
    tile('harbor_water', '#527f89')
    tile('harbor_steel', '#8a999a', metal=True)
    tile('harbor_wood', '#b09b76', wood=True)
    manifest_path = ART / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest['sprites'].update(SPRITES)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+'\n', encoding='utf-8', newline='\n')
    provenance_path = ROOT / 'assets/PROVENANCE.json'
    provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
    paths = [ART / rel for rel in SPRITES] + list((ART / 'tiles').glob('harbor_*.svg'))
    for path in paths:
        rel = path.relative_to(ROOT).as_posix()
        row = {'path': rel, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'origin': 'Original procedural 2:1 SVG; tools/make_harbor_art.py (Python standard library); AI-assisted code, no AI-generated imagery; no third-party assets', 'ai_generated': False, 'license': 'No additional license granted'}
        provenance['files'] = [item for item in provenance['files'] if item['path'] != rel]
        provenance['files'].append(row)
    provenance_path.write_text(json.dumps(provenance, indent=2, ensure_ascii=False)+'\n', encoding='utf-8', newline='\n')
    print(f'BH_HARBOR_ART {len(paths)} original SVG assets registered')


if __name__ == '__main__':
    main()
