"""Register original AI sheets without per-frame scaling or runtime animation synthesis."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image
from collections import deque

ROOT = Path(__file__).resolve().parents[1]
KINDS = ['screamer', 'toxic', 'burst', 'hound', 'breacher']
CELL = 256
FOOT = (128, 240)


def clean_islands(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel('A')
    pixels = alpha.load()
    seen = set()
    for y in range(cell.height):
        for x in range(cell.width):
            if pixels[x, y] == 0 or (x, y) in seen:
                continue
            queue = deque([(x, y)])
            seen.add((x, y))
            island = []
            while queue:
                px, py = queue.popleft()
                island.append((px, py))
                for nx, ny in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]:
                    if 0 <= nx < cell.width and 0 <= ny < cell.height and pixels[nx, ny] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        queue.append((nx, ny))
            if len(island) < 24:
                for px, py in island:
                    pixels[px, py] = 0
    cell.putalpha(alpha)
    return cell


def build(kind: str, source: Path) -> dict:
    image = Image.open(source).convert('RGBA')
    # Remove only near-transparent generator residue, preserving antialiased edges.
    alpha = image.getchannel('A').point(lambda value: 0 if value < 20 else value)
    image.putalpha(alpha)
    frames = []
    for direction in range(5):
        row = []
        for pose in range(12):
            bounds = (round(pose * image.width / 12), round(direction * image.height / 5),
                      round((pose + 1) * image.width / 12), round((direction + 1) * image.height / 5))
            cell = clean_islands(image.crop(bounds))
            box = cell.getbbox()
            assert box, (kind, direction, pose)
            row.append((cell, box))
        frames.append(row)
    # One scale for the entire species. Keep gait height/weight shift intact.
    max_w = max(box[2] - box[0] for row in frames for _, box in row)
    max_h = max(box[3] - box[1] for row in frames for _, box in row)
    scale = min(224 / max_w, 218 / max_h)
    sheet = Image.new('RGBA', (CELL * 5, CELL * 12))
    anchors = []
    for direction, row in enumerate(frames):
        # Register to the row's median standing foot; don't stretch individual poses.
        bottoms = sorted(box[3] for _, box in row[:7])
        baseline = bottoms[len(bottoms) // 2]
        centers = sorted((box[0] + box[2]) / 2 for _, box in row[:7])
        center = centers[len(centers) // 2]
        anchors.append([center, baseline])
        for pose, (cell, box) in enumerate(row):
            crop = cell.crop(box)
            crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
            x = round(FOOT[0] + (box[0] - center) * scale)
            y = round(FOOT[1] + (box[1] - baseline) * scale)
            # Fall poses are grounded on the same root; no frame-fitted scale.
            if pose >= 10:
                y = FOOT[1] - crop.height
            assert x >= 4 and x + crop.width <= CELL - 4 and y >= 4 and y + crop.height <= CELL - 4, (kind, direction, pose, x, y, crop.size)
            sheet.alpha_composite(crop, (direction * CELL + x, pose * CELL + y))
    folder = ROOT / 'assets/infected_v1' / kind
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / 'actions.png'
    sheet.save(target)
    return {'kind': kind, 'path': target.relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'source_size': list(image.size), 'scale': scale, 'source_anchors': anchors}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('sources', type=Path, nargs=5, help='screamer toxic burst hound breacher')
    args = parser.parse_args()
    rows = [build(kind, source) for kind, source in zip(KINDS, args.sources)]
    target = ROOT / 'assets/infected_v1/special_generation.json'
    target.write_text(json.dumps({'tool': 'OpenAI built-in image_gen + Pillow registration',
                                  'ai_generated': True, 'cell': CELL, 'root': FOOT,
                                  'prompts': 'assets/infected_v1/special_prompts.json',
                                  'columns': ['e', 'se', 's', 'ne', 'n'],
                                  'rows': ['idle', 'walk_left', 'walk_left_pass', 'walk_right', 'walk_right_pass',
                                           'windup', 'windup_full', 'release', 'recovery', 'hit', 'fall', 'fallen'],
                                  'files': rows}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(rows, indent=2))
