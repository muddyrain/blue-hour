"""Validate every allowlisted runtime image/audio and its public provenance SHA."""
from pathlib import Path
import hashlib,json,wave
import xml.etree.ElementTree as ET
from PIL import Image
R=Path(__file__).resolve().parents[1]
j=json.loads((R/'assets/PROVENANCE.json').read_text(encoding='utf-8'))
for row in j['files']:
 p=R/row['path'];assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],p
 if p.suffix=='.png':
  with Image.open(p) as im:im.verify()
  s=p.with_suffix('.png.import').read_text(encoding='utf-8');assert 'res://'+row['path'] in s
 if p.suffix=='.svg':
  svg=ET.fromstring(p.read_text());assert svg.tag.endswith('svg') and svg.get('viewBox'),p
  assert not any(e.tag.split('}')[-1] in ['script','image','foreignObject'] or any(k.endswith('href') for k in e.attrib) for e in svg.iter()),p
 if p.suffix=='.wav':
  with wave.open(str(p)) as w:assert w.getnchannels()==1 and w.getframerate()==44100
print('PASS public runtime provenance/format/import files',len(j['files']))
