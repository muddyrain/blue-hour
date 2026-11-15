"""Register three original imagegen 8x8 sheets; crop portraits, never invent poses.

The existing five atlases are deliberately untouched. Usage: three source PNG paths.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NAMES = ('ruan', 'ye', 'he')


def build(sources):
    manifest_path = ROOT / 'assets/survivors_v1/manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    provenance_path = ROOT / 'assets/PROVENANCE.json'
    provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
    for name, path in zip(NAMES, sources):
        source = Image.open(path).convert('RGBA')
        source.putalpha(source.getchannel('A').point(lambda a: 0 if a < 12 else a))
        atlas = Image.new('RGBA', (2048, 2048))
        registrations = []
        for row in range(8):
            frames = [source.crop((round(col*source.width/8), round(row*source.height/8),
                                   round((col+1)*source.width/8), round((row+1)*source.height/8)))
                      for col in range(8)]
            idle = frames[0].getbbox()
            scale = 184.0 / (idle[3] - idle[1])
            root = ((idle[0]+idle[2])/2, idle[3])
            registrations.append({'direction': manifest['directions'][row],
                                  'source_root': list(root), 'scale': scale})
            for col, frame in enumerate(frames):
                resized = frame.resize((round(frame.width*scale), round(frame.height*scale)), Image.Resampling.LANCZOS)
                registered = Image.new('RGBA', (256, 256))
                registered.alpha_composite(resized, (round(128-root[0]*scale), round(224-root[1]*scale)))
                bounds = registered.getbbox()
                assert bounds and min(bounds[:2]) > 0 and max(bounds[2:]) < 256, (name, row, col, bounds)
                atlas.alpha_composite(registered, (256*col, 256*row))
        dest = ROOT / f'assets/survivors_v1/{name}.png'
        atlas.save(dest, optimize=True)
        front = atlas.crop((0, 512, 256, 768))
        # Face and hair from the actual front idle, retaining the exact identity.
        portrait = front.crop((78, 36, 178, 136)).resize((256, 256), Image.Resampling.LANCZOS)
        face_path = ROOT / f'assets/iso/chars/{name}_portrait.png'
        portrait.save(face_path, optimize=True)
        manifest['characters'][name] = {'sheet': dest.name, 'target_idle_height': 184,
            'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'registration': registrations}
        for output in (dest, face_path):
            rel = output.relative_to(ROOT).as_posix()
            provenance['files'] = [r for r in provenance['files'] if r['path'] != rel]
            provenance['files'].append({'path': rel, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                'origin': 'Original AI-assisted OpenAI image_gen character atlas; deterministic Pillow slice, scale and foot registration / portrait crop via tools/build_recruit_atlas.py. Prompts: assets/survivors_v1/recruit_generation.json',
                'ai_generated': True, 'license': 'No additional license granted'})
            # Match project-native import settings, using unique path-based import keys.
            template = (ROOT / 'assets/survivors_v1/lu.png.import').read_text(encoding='utf-8')
            import re
            template = re.sub(r'^uid=.*\n', '', template, flags=re.M)
            old = 'res://.godot/imported/lu.png-92561d3e8933bf402091b9d3d3365565.ctex'
            new = f'res://.godot/imported/{output.name}-{hashlib.md5(("res://"+rel).encode()).hexdigest()}.ctex'
            template = template.replace(old, new).replace('res://assets/survivors_v1/lu.png', 'res://'+rel)
            output.with_suffix('.png.import').write_text(template, encoding='utf-8')
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    provenance_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('BH_RECRUIT_ATLAS built 3 sheets / 192 authored frames and 3 portraits')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sources', nargs=3, type=Path)
    build(parser.parse_args().sources)
