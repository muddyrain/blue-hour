"""Validate RGBA probes/candidates against their source manifest; Pillow 12.3.0."""

from pathlib import Path
import hashlib
import json
import wave
import xml.etree.ElementTree as ET
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "assets/probes/bag.png"
with Image.open(path) as image:
    assert image.mode == "RGBA", f"Expected RGBA, got {image.mode}"
    assert image.size == (128, 128), f"Unexpected canvas: {image.size}"
    alpha = image.getchannel("A")
    assert alpha.getextrema() == (0, 255), "Expected transparent and opaque pixels"
    assert image.getpixel((0, 0))[3] == 0, "Expected transparent corner"
    print(f"PASS {path.relative_to(ROOT)} RGBA 128x128 alpha=0..255 bbox={alpha.getbbox()}")

entries = json.loads((ROOT / "assets/candidates/manifest.json").read_text(encoding="utf-8"))
entries += json.loads((ROOT / "assets/m401/manifest.json").read_text(encoding="utf-8"))
entries += json.loads((ROOT / "assets/m402/manifest.json").read_text(encoding="utf-8"))
entries += json.loads((ROOT / "assets/m403/manifest.json").read_text(encoding="utf-8"))
for entry in entries:
    path = ROOT / entry["file"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], path
    if entry.get("kind") == "vector_icon":
        svg = ET.fromstring(path.read_text(encoding="utf-8"))
        assert svg.tag == "{http://www.w3.org/2000/svg}svg" and svg.attrib["viewBox"] == "0 0 32 32", path
        assert len(svg) >= 1, path
        print(f"PASS {path.relative_to(ROOT)} original32px SVG gender glyph")
        continue
    if entry.get("kind") == "audio_manifest":
        manifest = json.loads(path.read_text(encoding="utf-8"))
        generator = ROOT / manifest["generator"]
        assert hashlib.sha256(generator.read_bytes()).hexdigest() == manifest["generator_sha256"]
        assert len(manifest["assets"]) == 6
        for cue in manifest["assets"]:
            audio_path = ROOT / cue["file"]
            assert hashlib.sha256(audio_path.read_bytes()).hexdigest() == cue["sha256"]
            with wave.open(str(audio_path), "rb") as stream:
                assert (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) == (1, 2, 44100)
                assert abs(stream.getnframes() / 44100 - cue["duration_s"]) < 0.0001
            imported = audio_path.with_suffix(".wav.import").read_text(encoding="utf-8")
            assert 'source_file="res://' + cue["file"] + '"' in imported
        print("PASS six original WAVs, generator, format/duration/hash and import source references")
        continue
    with Image.open(path) as image:
        assert image.mode == "RGBA" and image.size == tuple(entry["canvas"]), path
        alpha = image.getchannel("A")
        if entry.get("alpha_mode") == "opaque":
            assert alpha.getextrema() == (255, 255), path
            print(f"PASS {path.relative_to(ROOT)} opaque ground material {image.size}")
            continue
        assert alpha.getextrema() == (0, 255), path
        assert all(image.getpixel(p)[3] == 0 for p in [(0, 0), (image.width - 1, 0), (0, image.height - 1)]), path
        if "grid" in entry:
            fw, fh = entry["frame_size"]
            assert image.size == (fw * entry["grid"][0], fh * entry["grid"][1]), path
            for y in range(entry["grid"][1]):
                for x in range(entry["grid"][0]):
                    frame_alpha = alpha.crop((x*fw, y*fh, (x+1)*fw, (y+1)*fh))
                    box = frame_alpha.getbbox()
                    assert box and box[3] <= entry["anchor"][1], (path, x, y)
                    assert box[0] > 0 and box[1] > 0 and box[2] < fw, (path, x, y)
            if path.name == "xia_lower.png":
                for row in range(3):
                    skirt_frames = [image.crop((x*256, row*256+140, (x+1)*256, row*256+196)) for x in (1, 2, 3)]
                    assert all(ImageChops.difference(skirt_frames[a].getchannel('A'), skirt_frames[b].getchannel('A')).getbbox() for a,b in ((0,1),(1,2),(0,2))), row
                    for frame in skirt_frames:
                        assert frame.getchannel('A').getbbox(), row
                print("PASS Xia three-direction walking frames contain distinct animated skirt silhouettes")
        else:
            assert alpha.getbbox()[3] <= entry["anchor"][1], path
        print(f"PASS {path.relative_to(ROOT)} canvas={image.size} anchor={entry['anchor']}")
