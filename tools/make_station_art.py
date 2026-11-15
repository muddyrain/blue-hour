"""Original closed-roof station SVGs. Standard library; no AI imagery or third-party art."""
from pathlib import Path
import hashlib
import json
from make_harbor_art import Sprite

ROOT = Path(__file__).resolve().parents[1]
SPRITES = {}


class StationSprite(Sprite):
    def save(self, name):
        rel = f'station/{name}.svg'
        dest = ROOT / 'assets/iso' / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width:g}" height="{self.height:g}" viewBox="0 0 {self.width:g} {self.height:g}">'+''.join(self.parts)+'</svg>\n', encoding='utf-8', newline='\n')
        SPRITES[rel] = {'w': self.width, 'h': self.height, 'foot': [self.ox*2, self.oy*2], 'map': [self.w, self.d]}


def building(name, w, d, h, wall, roof):
    s = StationSprite(w, d, h + 56)
    s.shadow()
    s.box(-w/2, 0, w, d, 8, '#929585')
    s.box(-w/2, 0, w, d, h, wall, 8)
    z, ridge = h+12, h+50
    s.poly([(-w/2-8, 8, z), (w/2+8, 8, z), (w/2+8, -d/2, ridge), (-w/2-8, -d/2, ridge)], roof)
    s.poly([(-w/2-8, -d/2, ridge), (w/2+8, -d/2, ridge), (w/2+8, -d-8, z), (-w/2-8, -d-8, z)], '#6c7e7c')
    s.poly([(w/2, 0, h+8), (w/2, -d, h+8), (w/2, -d/2, ridge-2)], wall)
    for x in range(int(-w/2), int(w/2)+1, 16):
        s.line([(x, 8, z+1), (x, -d/2, ridge+1), (x, -d-8, z+1)], '#d5d5bd66', .8)
    for frac in [.25, .5, .75]:
        y = 8 + (-d/2-8)*frac
        zz = z + (ridge-z)*frac
        s.line([(-w/2-8, y, zz+1), (w/2+8, y, zz+1)], '#c1c5b277', .8)
    s.poly([(-24, 1, 8), (24, 1, 8), (24, 1, h-8), (-24, 1, h-8)], '#667f7b', '#e4d9bd', 2)
    s.line([(0, 2, 8), (0, 2, h-8)], '#d1c7ad', 2)
    for x in range(int(-w/2+20), int(w/2-40), 64):
        if abs(x) < 34:
            continue
        s.poly([(x, 2, 32), (x+40, 2, 32), (x+40, 2, h-16), (x, 2, h-16)], '#90aba6', '#eee1c1', 3)
        s.line([(x+20, 3, 32), (x+20, 3, h-16)], '#e4d6b9', 2)
    if name == 'station':
        # Blank fascia and clock; the location name is rendered by Godot.
        s.box(-150, 46, 300, 48, 5, '#a5b7a7', 60)
        for x in [-140, 140]:
            s.box(x, 40, 5, 5, 60, '#ddd4bb')
        s.ring(0, 3, h+3, 15, '#eee3c8', 6)
        s.line([(0, 4, h+3), (0, 4, h+13)], '#5c655e', 2)
        s.line([(0, 4, h+3), (9, 4, h+3)], '#5c655e', 2)
        for x in [-204, 180]:
            s.box(x, 28, 28, 28, 24, '#828e72')
            s.box(x-2, 30, 32, 32, 10, '#a5b17e', 24)
    elif name == 'bakery':
        s.box(-w/2-4, 24, w+8, 28, 5, '#b58c61', h-12)
        for x in range(int(-w/2), int(w/2), 24):
            s.box(x, 25, 12, 30, 3, '#e2d3a9', h-7)
    elif name == 'house':
        s.box(w/2-54, -d+40, 36, 26, 16, '#b7b8a6', h+14)
        s.box(-w/2+12, 22, 56, 24, 17, '#b69872')
        s.box(-w/2+10, 24, 60, 28, 9, '#98a779', 17)
    elif name == 'kiosk':
        s.box(-w/2-4, 20, w+8, 24, 4, '#7d9688', h-10)
    s.save(name)


def ground():
    s = StationSprite(1152, 96, 12)
    s.poly([(-576, 0), (576, 0), (576, -96), (-576, -96)], '#8b9183')
    for x in range(-560, 576, 24):
        s.box(x, -10, 8, 76, 3, '#81755e')
    for y in [-26, -70]:
        s.box(-576, y, 1152, 4, 6, '#b5b7aa')
    for x in [-564, 552]:
        s.box(x, -10, 8, 76, 16, '#7e8177')
    s.save('track')
    s = StationSprite(1056, 96, 14)
    s.box(-528, 0, 1056, 96, 12, '#b5b19d')
    s.line([(-524, -84, 13), (524, -84, 13)], '#d3b572', 5)
    for x in range(-512, 528, 32):
        s.line([(x, 0, 13), (x, -80, 13)], '#92998a', .6)
    s.save('platform')
    s = StationSprite(96, 32, 36)
    for x in [-36, 30]:
        s.box(x, -3, 6, 20, 20, '#687771')
    s.box(-46, 0, 92, 28, 5, '#aa9471', 20)
    s.box(-46, -24, 92, 5, 15, '#aa9471', 20)
    s.save('bench')


def main():
    building('station', 480, 256, 88, '#d4ceaf', '#a58b76')
    building('bakery', 224, 192, 74, '#ded1a5', '#a17d66')
    building('house', 256, 160, 106, '#c5c9b7', '#758f9a')
    building('kiosk', 160, 128, 64, '#d1ceae', '#81978a')
    building('shed', 192, 128, 48, '#b0b6a0', '#7f9088')
    ground()
    path = ROOT / 'assets/iso/manifest.json'
    manifest = json.loads(path.read_text(encoding='utf-8'))
    manifest['sprites'].update(SPRITES)
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+'\n', encoding='utf-8', newline='\n')
    path = ROOT / 'assets/PROVENANCE.json'
    provenance = json.loads(path.read_text(encoding='utf-8'))
    for rel in SPRITES:
        asset = ROOT / 'assets/iso' / rel
        name = asset.relative_to(ROOT).as_posix()
        provenance['files'] = [row for row in provenance['files'] if row['path'] != name]
        provenance['files'].append({'path': name, 'sha256': hashlib.sha256(asset.read_bytes()).hexdigest(), 'origin': 'Original procedural 2:1 SVG; tools/make_station_art.py using Sprite from make_harbor_art.py; Python standard library; AI-assisted code, no AI-generated imagery; no third-party assets', 'ai_generated': False, 'license': 'No additional license granted'})
    path.write_text(json.dumps(provenance, indent=2, ensure_ascii=False)+'\n', encoding='utf-8', newline='\n')
    print(f'BH_STATION_ART {len(SPRITES)} original SVG assets registered')


if __name__ == '__main__':
    main()
